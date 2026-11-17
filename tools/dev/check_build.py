"""Checks for a finished build (T4-Q). Nothing here opens a window and nothing touches %APPDATA%/WitchMoira.

    python tools/dev/build.py --preset qa    --stamp S
    python tools/dev/build.py --preset store --stamp S
    python tools/dev/check_build.py --build _local/build/S            # all checks (about 2.5 minutes)
    python tools/dev/check_build.py --build _local/build/S --only build_json,pck,assert_static,export_log
    python tools/dev/check_build.py --self-test                        # the checks must FAIL on synthetic bad input

Checks (names for --only):
  build_json     build.json of qa and store: exe exists, size and sha256 equal the record, commit equals HEAD
                 (dirty tree is a note; --require-clean makes it a failure), template sha256 matched the record
  pck            file list read from the exe: no forbidden path, required files present, report of files that
                 nothing in the sources reads (B3) with a suggested exclude_filter. export_presets.cfg is not touched
  assert_static  every assert( in the repository: no assignment, no set_/add_/append/erase/_persist/save call
                 inside the first argument (FAIL); other state-changing looking calls (WARN)
  export_log     ERROR lines of export.log, split into known (tools/dev/check_build_known_lines.json) and new (FAIL)
  run_qa         QA exe, --headless, 60 s pilot run: exit 0, result line, no new ERROR line, only the isolated APPDATA written
  probe_args     QA exe, --headless, frame-probe arguments are read (metadata.json written); the headless run itself
                 is rejected by the probe on purpose, which is expected. The windowed measurement is NOT done here
  run_store      store exe, --headless, same verification arguments: they must be ignored (no result line, no capture
                 or probe folder, still alive at the time limit), no new ERROR line, files only under the isolated APPDATA

Execution checks run with APPDATA under _local/appdata/check_build-<qa|store>/ (tools/dev/isolated_env.py).
Raw logs go to <build>/check/<time>/ (a new folder each run). Exit code 0 = all selected checks passed.
Test hooks (only for showing that a check can fail): --inject-pck-entry, --inject-export-line, --export-log-dir.
"""
from pathlib import Path
import argparse, datetime, json, os, re, subprocess, sys, tempfile, time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build as build_tool
from isolated_env import isolated_env

ROOT = Path(__file__).resolve().parents[2]
KNOWN_FILE = Path(__file__).resolve().parent / 'check_build_known_lines.json'
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
ERROR_LINE = re.compile(r'^\s*(SCRIPT ERROR|USER SCRIPT ERROR|USER ERROR|ERROR)\s*:|Parse Error', re.I)
REQUIRED_IN_PCK = (
    'res://chapter1/data/combat_tuning.json', 'res://chapter1/data/loot.json', 'res://chapter1/data/skill_trees.json',
    'res://chapter1/data/character_progression.json', 'res://chapter1/i18n/ko.po', 'res://chapter1/i18n/en.po',
    'res://chapter1/i18n/locales.json', 'res://chapter1/ChapterOne.tscn.remap', 'res://chapter1/app/chapter_one.gd.remap',
)
# Spec 2.5: names that must not appear inside assert(...). Second list: looks state-changing, reported as WARN.
ASSERT_FAIL_CALLS = re.compile(r'(?<![A-Za-z0-9])((?:set_|add_|append|erase|_persist|save)\w*)\s*\(')
ASSERT_WARN_CALLS = re.compile(r'(?<![A-Za-z0-9])((?:push_|pop_|insert|remove|clear|emit|queue_free|free|resize|shuffle|sort|fill|merge|connect|call_deferred|randi|randf|randomize|print|duplicate_into)\w*)\s*\(')
ASSIGNMENT = re.compile(r'(?<![=!<>])=(?!=)')
SKIP_DIRS = {'.git', '.godot', '_local', '.claude', 'art-archive', 'docs', 'node_modules'}
RUN_GRACE_S = 60


class Report:
    def __init__(self):
        self.rows = []

    def add(self, name, status, detail=''):
        self.rows.append({'check': name, 'status': status, 'detail': detail})
        print('CHECK %-14s %-4s %s' % (name, status, detail))

    def failed(self):
        return [row for row in self.rows if row['status'] == 'FAIL']


def git(*args):
    result = subprocess.run(['git', '-C', str(ROOT)] + list(args), capture_output=True, text=True, encoding='utf-8', errors='replace')
    return result.stdout.strip() if result.returncode == 0 else ''


def clean(text):
    return ANSI.sub('', text)


def load_known():
    return json.loads(KNOWN_FILE.read_text(encoding='utf-8')).get('known', [])


def classify_lines(lines, where):
    """Return (known_hits, new_lines) for the ERROR lines among `lines`."""
    known, new = [], []
    entries = [entry for entry in load_known() if where in entry.get('applies_to', [])]
    for raw in lines:
        line = clean(raw).rstrip()
        if not ERROR_LINE.search(line):
            continue
        entry = next((entry for entry in entries if entry['contains'] in line), None)
        if entry:
            known.append((entry['id'], line))
        else:
            new.append(line)
    return known, new


# ---------------------------------------------------------------- build.json

def check_build_json(report, build_dir, require_clean):
    head = git('rev-parse', '--short', 'HEAD')
    for kind in ('qa', 'store'):
        folder = build_dir / kind
        record_path = folder / 'build.json'
        if not record_path.is_file():
            report.add('build_json', 'FAIL', '%s: build.json missing (%s)' % (kind, record_path))
            continue
        record = json.loads(record_path.read_text(encoding='utf-8'))
        exe = folder / build_tool.EXE_NAME
        problems, notes = [], []
        if not exe.is_file():
            problems.append('exe missing')
        else:
            if exe.stat().st_size != record.get('bytes'):
                problems.append('size %d != record %s' % (exe.stat().st_size, record.get('bytes')))
            actual = build_tool.sha256(exe)
            if actual != record.get('sha256'):
                problems.append('sha256 %s != record %s' % (actual[:12], str(record.get('sha256'))[:12]))
        if record.get('commit') != head:
            problems.append('commit %s != HEAD %s' % (record.get('commit'), head))
        if record.get('working_tree_dirty'):
            (problems if require_clean else notes).append('built from a dirty working tree')
        if not record.get('template_sha256_matches_record'):
            problems.append('template sha256 was not verified against the acquisition record')
        if record.get('pck_forbidden'):
            problems.append('build.json lists forbidden pck files: %d' % len(record['pck_forbidden']))
        expected_preset = {'qa': 'Windows QA', 'store': 'Windows Store'}[kind]
        if record.get('preset') != expected_preset:
            problems.append('preset %r, expected %r' % (record.get('preset'), expected_preset))
        detail = '%s: sha256=%s commit=%s bytes=%s' % (kind, str(record.get('sha256'))[:12], record.get('commit'), record.get('bytes'))
        if notes:
            detail += ' NOTE ' + '; '.join(notes)
        report.add('build_json', 'FAIL' if problems else 'PASS', detail + ((' PROBLEMS ' + '; '.join(problems)) if problems else ''))


# ---------------------------------------------------------------- pck

def source_texts():
    """Text of runtime sources (scripts, scenes, resources) used to find out which files are read."""
    texts = []
    for folder in ('chapter1', 'combat'):
        for path in (ROOT / folder).rglob('*'):
            if path.is_file() and path.suffix in ('.gd', '.tscn', '.tres', '.cfg') and 'tests' not in path.relative_to(ROOT).parts:
                texts.append((path, path.read_text(encoding='utf-8', errors='replace')))
    texts.append((ROOT / 'project.godot', (ROOT / 'project.godot').read_text(encoding='utf-8', errors='replace')))
    return texts


def unreferenced_data_files(files):
    """Data files in the pck (json/txt/md/csv/cfg under art, data, i18n) whose file name appears in no runtime source
    line other than a print(). A heuristic: names built at run time are not seen, so this is a list to review."""
    texts = source_texts()
    result = []
    for name in files:
        if not name.startswith('res://chapter1/art/') or not name.endswith(('.json', '.txt', '.csv', '.md', '.cfg')):
            continue
        base = name.rsplit('/', 1)[-1]
        folder_concat = re.compile(re.escape(name.rsplit('/', 1)[0] + '/') + r'"\s*\+')  # "res://.../actors/"+kind: name built at run time
        used = any(base in line and 'print(' not in line for _, text in texts for line in text.splitlines() if base in line)
        used = used or any(folder_concat.search(text) for _, text in texts)
        if not used:
            result.append(name)
    return result


def suggest_filter(paths):
    """Group paths into exclude_filter patterns (relative to the project, as export_presets.cfg writes them)."""
    patterns = set()
    for path in paths:
        relative = path[len('res://'):]
        folder, base = relative.rsplit('/', 1)
        stem = re.sub(r'(?<=-)v?\d+$', '', base.rsplit('.', 1)[0])
        if stem != base.rsplit('.', 1)[0] and stem.endswith('-'):
            patterns.add('%s/%s*' % (folder, stem))
        elif base.startswith(('GENERATED-', 'GENERATION-')):
            patterns.add('%s/%s*' % (folder, base.split('-')[0] + '-'))
        elif base.endswith('-INSPECTION.json'):
            patterns.add('%s/*-INSPECTION.json' % folder)
        else:
            patterns.add(relative)
    return sorted(patterns)


def evaluate_pck(files):
    bad = [name for name in files if name.startswith(build_tool.FORBIDDEN_PREFIXES) or name.endswith(build_tool.FORBIDDEN_SUFFIXES)]
    # Godot 4.5 keeps scripts as res://x.gd.remap + x.gdc with script_export_mode=2; a plain .gd means source shipped.
    plain_scripts = [name for name in files if name.endswith('.gd')]
    missing = [name for name in REQUIRED_IN_PCK if name not in files]
    return bad, plain_scripts, missing


def check_pck(report, build_dir, inject):
    for kind in ('qa', 'store'):
        exe = build_dir / kind / build_tool.EXE_NAME
        if not exe.is_file():
            report.add('pck', 'FAIL', '%s: exe missing' % kind)
            continue
        files = build_tool.list_pck(exe)
        if files is None:
            report.add('pck', 'FAIL', '%s: could not read the pck file list' % kind)
            continue
        files = files + list(inject)
        bad, plain, missing = evaluate_pck(files)
        listed = (build_dir / kind / 'pck_files.txt')
        note = ''
        if listed.is_file():
            recorded = [line for line in listed.read_text(encoding='utf-8').splitlines() if line]
            if recorded != files[:len(recorded)] or len(recorded) != len(files) - len(inject):
                note = ' pck_files.txt differs from the exe'
        problems = []
        if bad:
            problems.append('forbidden: ' + ', '.join(bad[:10]) + (' ...(%d)' % len(bad) if len(bad) > 10 else ''))
        if plain:
            problems.append('plain .gd source in pck: ' + ', '.join(plain[:5]))
        if missing:
            problems.append('required missing: ' + ', '.join(missing))
        if note:
            problems.append(note.strip())
        report.add('pck', 'FAIL' if problems else 'PASS', '%s: files=%d %s' % (kind, len(files), '; '.join(problems)))
    # B3 report (same list for both presets; read from the store exe)
    exe = build_dir / 'store' / build_tool.EXE_NAME
    files = build_tool.list_pck(exe) if exe.is_file() else None
    if files:
        unused = unreferenced_data_files(files)
        report.add('pck', 'WARN' if unused else 'PASS', 'files in the pck that no runtime source reads (B3): %d' % len(unused))
        for name in unused:
            print('       unread: ' + name)
        if unused:
            print('       suggested additions to exclude_filter: ' + ', '.join(suggest_filter(unused)))


# ---------------------------------------------------------------- assert( static scan

def blank_code(text):
    """Same length as `text`; comments and the inside of string literals replaced by spaces (newlines kept)."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '#':
            while i < n and text[i] != '\n':
                out[i] = ' '
                i += 1
        elif ch in '"\'':
            triple = text.startswith(ch * 3, i)
            quote = ch * 3 if triple else ch
            i += len(quote)
            while i < n and not text.startswith(quote, i):
                if text[i] == '\\' and i + 1 < n:
                    out[i] = out[i + 1] = ' ' if text[i + 1] != '\n' else '\n'
                    i += 2
                    continue
                if text[i] == '\n' and not triple:
                    break
                if text[i] != '\n':
                    out[i] = ' '
                i += 1
            i += len(quote) if text.startswith(quote, i) else 0
        else:
            i += 1
    return ''.join(out)


def find_asserts(text):
    """Yield (line_number, first_argument_text) for every assert( call, with the string/comment-blanked first argument."""
    blank = blank_code(text)
    for match in re.finditer(r'(?<![A-Za-z0-9_.])assert\s*\(', blank):
        start = match.end()
        depth, i, first_end = 1, start, None
        while i < len(blank) and depth:
            c = blank[i]
            if c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            elif c == ',' and depth == 1 and first_end is None:
                first_end = i
            i += 1
        end = i - 1
        argument = blank[start:first_end if first_end is not None else end]
        yield text.count('\n', 0, match.start()) + 1, argument, text[start:end].strip()


def scan_asserts(paths):
    sites = []
    for path in paths:
        text = path.read_text(encoding='utf-8', errors='replace')
        for line, argument, shown in find_asserts(text):
            problems, warnings = [], []
            if ASSIGNMENT.search(argument):
                problems.append('assignment')
            problems += ['call ' + m.group(1) for m in ASSERT_FAIL_CALLS.finditer(argument)]
            warnings += ['call ' + m.group(1) for m in ASSERT_WARN_CALLS.finditer(argument)]
            sites.append({'path': path, 'line': line, 'text': shown, 'fail': problems, 'warn': warnings})
    return sites


def gd_files():
    for folder, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in names:
            if name.endswith('.gd'):
                yield Path(folder) / name


def check_assert_static(report, paths=None):
    sites = scan_asserts(sorted(paths if paths is not None else gd_files()))
    bad = [site for site in sites if site['fail']]
    warn = [site for site in sites if site['warn'] and not site['fail']]
    report.add('assert_static', 'FAIL' if bad else 'PASS', 'assert( sites=%d side-effect suspects=%d (WARN-level=%d)' % (len(sites), len(bad), len(warn)))
    for site in sites:
        tag = 'FAIL' if site['fail'] else ('WARN' if site['warn'] else 'ok  ')
        reasons = ', '.join(site['fail'] + site['warn'])
        rel = site['path'].relative_to(ROOT).as_posix() if ROOT in site['path'].parents else str(site['path'])
        print('       %s %s:%d  assert(%s)%s' % (tag, rel, site['line'], site['text'][:90].replace('\n', ' '), ('  <- ' + reasons) if reasons else ''))
    return sites


# ---------------------------------------------------------------- export.log

def check_export_log(report, build_dir, inject_line, log_dir):
    base = Path(log_dir) if log_dir else build_dir
    for kind in ('qa', 'store'):
        path = base / kind / 'export.log'
        if not path.is_file():
            report.add('export_log', 'FAIL', '%s: export.log missing (%s)' % (kind, path))
            continue
        lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
        if inject_line:
            lines.append(inject_line)
        known, new = classify_lines(lines, 'export')
        head = lines[0].strip() if lines else ''
        problems = []
        if head != 'exit=0':
            problems.append('first line %r, expected exit=0' % head)
        if new:
            problems.append('NEW ERROR lines: %d' % len(new))
        report.add('export_log', 'FAIL' if problems else 'PASS', '%s: known=%d new=%d%s' % (kind, len(known), len(new), (' ' + '; '.join(problems)) if problems else ''))
        for ident, line in known:
            print('       known[%s] %s' % (ident, line[:160]))
        for line in new[:10]:
            print('       NEW   ' + line[:200])


# ---------------------------------------------------------------- execution checks

def tree_files(folder):
    result = {}
    if folder.is_dir():
        for path in folder.rglob('*'):
            if path.is_file():
                stat = path.stat()
                result[path.relative_to(folder).as_posix()] = (stat.st_size, stat.st_mtime_ns)
    return result


def run_exe(exe, user_args, engine_args, env, out_dir, label, time_limit):
    """Run exe headless with piped-to-file output. Returns (exit_code or None if killed at the limit, stdout, stderr, seconds)."""
    out_path, err_path = out_dir / (label + '.out.txt'), out_dir / (label + '.err.txt')
    started = time.time()
    with open(out_path, 'wb') as out, open(err_path, 'wb') as err:
        proc = subprocess.Popen([str(exe), '--headless'] + engine_args + ['--'] + user_args, stdout=out, stderr=err, env=env, cwd=str(exe.parent))
        try:
            code = proc.wait(timeout=time_limit)
        except subprocess.TimeoutExpired:
            proc.kill()  # our own child only
            proc.wait()
            code = None
    return code, out_path.read_text(encoding='utf-8', errors='replace'), err_path.read_text(encoding='utf-8', errors='replace'), time.time() - started


def parse_result_line(stdout):
    for line in stdout.splitlines():
        if line.startswith('FULL_CHAPTER_RUNTIME_RESULT'):
            try:
                return json.loads(line[line.index('{'):])
            except ValueError:
                return None
    return None


def check_run_qa(report, build_dir, out_dir, seconds):
    exe = build_dir / 'qa' / build_tool.EXE_NAME
    if not exe.is_file():
        report.add('run_qa', 'FAIL', 'qa exe missing')
        return
    env = isolated_env('check_build-qa')
    appdata = Path(env['APPDATA'])
    before = tree_files(appdata)
    args = ['--chapter1-start', '--chapter1-pilot', '--chapter1-profile-off', '--chapter1-qa-ignore-focus', '--chapter1-seed=11',
            '--chapter1-primary=chapter1.skill.frost', '--chapter1-quit-after=%d' % seconds]
    code, out, err, spent = run_exe(exe, args, [], env, out_dir, 'run_qa', seconds + RUN_GRACE_S)
    lines = (out + '\n' + err).splitlines()
    known, new = classify_lines(lines, 'run')
    result = parse_result_line(out)
    problems = []
    if code != 0:
        problems.append('exit %s (None = killed at the time limit)' % code)
    if 'CHAPTER1_READY' not in out:
        problems.append('no CHAPTER1_READY line')
    if result is None:
        problems.append('no FULL_CHAPTER_RUNTIME_RESULT line')
    else:
        if not (result.get('pilot') and result.get('profile_off')):
            problems.append('pilot/profile_off not set in result (arguments not honored by the QA build)')
        if result.get('tick', 0) < int(seconds * 60 * 0.9):
            problems.append('tick %s < %d' % (result.get('tick'), int(seconds * 60 * 0.9)))
        if result.get('mode') not in ('playing', 'choice', 'victory', 'defeat'):
            problems.append('mode %r' % result.get('mode'))
    if new:
        problems.append('NEW ERROR lines: %d' % len(new))
    after = tree_files(appdata)
    changed = sorted(name for name in after if before.get(name) != after[name])
    saved = [name for name in changed if 'profile' in name and not name.startswith('logs/')]
    if saved:
        problems.append('profile files written although --chapter1-profile-off: %s' % saved)
    summary = 'exit=%s seconds=%.1f mode=%s tick=%s kills=%s known_errors=%d new_errors=%d files_written_in_isolated_appdata=%d' % (
        code, spent, result and result.get('mode'), result and result.get('tick'), result and result.get('kills'), len(known), len(new), len(changed))
    report.add('run_qa', 'FAIL' if problems else 'PASS', summary + ((' PROBLEMS ' + '; '.join(problems)) if problems else ''))
    for line in new[:10]:
        print('       NEW   ' + line[:200])
    for name in changed[:6]:
        print('       wrote ' + name)


def check_probe_args(report, build_dir, out_dir):
    exe = build_dir / 'qa' / build_tool.EXE_NAME
    if not exe.is_file():
        report.add('probe_args', 'FAIL', 'qa exe missing')
        return
    env = isolated_env('check_build-qa')
    probe_dir = exe.parent / 'qa-probe' / ('check-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    args = ['--chapter1-start', '--chapter1-pilot', '--chapter1-profile-off', '--chapter1-seed=11',
            '--chapter1-frame-probe-dir=' + str(probe_dir).replace('\\', '/'), '--chapter1-frame-probe-quit']
    code, out, err, spent = run_exe(exe, args, ['--disable-vsync', '--resolution', '1920x1080'], env, out_dir, 'probe_args', 40)
    metadata_path, summary_path = probe_dir / 'metadata.json', probe_dir / 'summary.json'
    problems = []
    if not metadata_path.is_file():
        problems.append('metadata.json not written: the probe arguments were not read or the folder was refused')
    else:
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        if not any(str(arg).startswith('--chapter1-frame-probe-dir=') for arg in metadata.get('user_args', [])):
            problems.append('probe argument missing from user_args')
        if metadata.get('seed') != 11 or not metadata.get('pilot'):
            problems.append('seed/pilot not read (seed=%s pilot=%s)' % (metadata.get('seed'), metadata.get('pilot')))
    errors = []
    if summary_path.is_file():
        errors = json.loads(summary_path.read_text(encoding='utf-8')).get('eligibility_errors', [])
    known, new = classify_lines((out + '\n' + err).splitlines(), 'run')
    # The probe refuses a headless run (expected). Any other refusal reason is only listed, it is not this check's job.
    if 'headless' not in errors and summary_path.is_file():
        problems.append('probe summary has no "headless" refusal; unexpected: %s' % errors)
    report.add('probe_args', 'FAIL' if problems else 'PASS', 'exit=%s metadata.json=%s eligibility_errors(headless run, expected non-empty)=%s%s' % (
        code, metadata_path.is_file(), errors, (' PROBLEMS ' + '; '.join(problems)) if problems else ''))
    print('       NOTE: this proves the arguments are read. It does not prove a windowed run is eligible (vsync, focus): see the QA-T4Q document')


def check_run_store(report, build_dir, out_dir):
    exe = build_dir / 'store' / build_tool.EXE_NAME
    if not exe.is_file():
        report.add('run_store', 'FAIL', 'store exe missing')
        return
    env = isolated_env('check_build-store')
    appdata = Path(env['APPDATA'])
    before = tree_files(appdata)
    capture_dir, probe_dir = exe.parent / 'qa-captures', exe.parent / 'qa-probe' / 'store-must-not-exist'
    args = ['--chapter1-start', '--chapter1-pilot', '--chapter1-profile-off', '--chapter1-qa-ignore-focus', '--chapter1-seed=11',
            '--chapter1-quit-after=3', '--chapter1-capture-dir=' + str(capture_dir).replace('\\', '/'),
            '--chapter1-frame-probe-dir=' + str(probe_dir).replace('\\', '/'), '--chapter1-frame-probe-quit']
    limit = 15
    code, out, err, spent = run_exe(exe, args, [], env, out_dir, 'run_store', limit)
    known, new = classify_lines((out + '\n' + err).splitlines(), 'run')
    problems = []
    if code is not None:
        problems.append('exited by itself with code %s after %.1f s: --chapter1-quit-after was honored' % (code, spent))
    for marker in ('RUNTIME_RESULT', 'CHAPTER1_CAPTURE', 'FRAME_PROBE_RESULT'):
        if marker in out:
            problems.append('output contains ' + marker)
    if 'pilot":true' in out.replace(' ', ''):
        problems.append('pilot flag active in output')
    for path in (capture_dir, probe_dir, probe_dir.parent):
        if path.exists():
            problems.append('folder created next to the exe: ' + str(path))
    if new:
        problems.append('NEW ERROR lines: %d' % len(new))
    after = tree_files(appdata)
    changed = sorted(name for name in after if before.get(name) != after[name])
    if not changed:
        problems.append('no file appeared in the isolated APPDATA (cannot show that the process wrote there and nowhere else)')
    report.add('run_store', 'FAIL' if problems else 'PASS', 'alive_at_limit=%s seconds=%.1f known_errors=%d new_errors=%d files_written_in_isolated_appdata=%d%s' % (
        code is None, spent, len(known), len(new), len(changed), (' PROBLEMS ' + '; '.join(problems)) if problems else ''))
    for line in new[:10]:
        print('       NEW   ' + line[:200])
    for name in changed[:6]:
        print('       wrote ' + name)


# ---------------------------------------------------------------- self test

def self_test(report):
    """Each synthetic bad input must be rejected, each good input accepted."""
    cases = []
    bad, plain, missing = evaluate_pck(['res://docs/a.md', 'res://chapter1/tests/x.gdc', 'res://tools/dev/y.py', 'res://_local/z', 'res://art-archive/a.png', 'res://chapter1/app/chapter_one.gd'] + list(REQUIRED_IN_PCK))
    cases.append(('pck rejects docs/tests/tools/_local/art-archive/.md and plain .gd', len(bad) == 5 and len(plain) == 1 and not missing))
    bad, plain, missing = evaluate_pck(list(REQUIRED_IN_PCK))
    cases.append(('pck accepts a clean list', not bad and not plain and not missing))
    bad, plain, missing = evaluate_pck([name for name in REQUIRED_IN_PCK if 'loot' not in name])
    cases.append(('pck rejects a list without required data', bool(missing)))
    known, new = classify_lines(['ERROR: brand new problem', 'SCRIPT ERROR: Parse Error: x', 'WARNING: only a warning'], 'export')
    cases.append(('log: new ERROR / SCRIPT ERROR lines are new, WARNING is not', len(new) == 2 and not known))
    known, new = classify_lines(['\x1b[91mERROR: Could not load C:/WINDOWS/FONTS/MALGUNBD.TTF\x1b[0m'], 'export')
    cases.append(('log: the MALGUNBD line is known, not new', len(known) == 1 and not new))
    known, new = classify_lines(['ERROR: Could not load C:/WINDOWS/FONTS/MALGUNBD.TTF'], 'run')
    cases.append(('log: the MALGUNBD line is NOT excused in run logs', len(new) == 1))
    samples = {
        'assert(x == 3, "msg")': ([], []),
        'assert(a <= b and c != d)': ([], []),
        'assert(items.size() > 0, "set_x(1) in a message is fine")': ([], []),
        'assert(count = 3)': (['assignment'], []),
        'assert((n := compute()) > 0)': (['assignment'], []),
        'assert(profile.save(path))': (['call save'], []),
        'assert(list.append(1))': (['call append'], []),
        'assert(_persist())': (['call _persist'], []),
        'assert(obj.set_value(2) == 2)': (['call set_value'], []),
        'assert(arr.pop_back() == 1)': ([], ['call pop_back']),
        '# assert(x = 1)': ([], None),
    }
    for source, (want_fail, want_warn) in samples.items():
        sites = scan_asserts_text(source)
        if want_warn is None:
            ok = not sites
        else:
            ok = len(sites) == 1 and [s for s in sites[0]['fail']] == want_fail and sites[0]['warn'] == want_warn
        cases.append(('assert scan: ' + source, ok))
    for name, ok in cases:
        report.add('self_test', 'PASS' if ok else 'FAIL', name)


def scan_asserts_text(source):
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'x.gd'
        path.write_text(source + '\n', encoding='utf-8')
        return scan_asserts([path])


# ---------------------------------------------------------------- main

ALL = ['build_json', 'pck', 'assert_static', 'export_log', 'run_qa', 'probe_args', 'run_store']


def newest_build():
    base = ROOT / '_local' / 'build'
    folders = [p for p in base.iterdir() if p.is_dir() and (p / 'qa').is_dir() and (p / 'store').is_dir()] if base.is_dir() else []
    return max(folders, key=lambda p: p.stat().st_mtime) if folders else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--build', help='_local/build/<stamp> (default: newest with qa/ and store/)')
    parser.add_argument('--only', default='', help='comma list of: ' + ','.join(ALL))
    parser.add_argument('--seconds', type=int, default=60, help='QA run length (default 60)')
    parser.add_argument('--require-clean', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--inject-pck-entry', action='append', default=[], help='test hook: add a fake entry to the pck list read from the exe')
    parser.add_argument('--inject-export-line', default='', help='test hook: append a line to each export.log before classifying')
    parser.add_argument('--export-log-dir', default='', help='test hook: read <dir>/{qa,store}/export.log instead of the build folder')
    args = parser.parse_args()
    report = Report()
    if args.self_test:
        self_test(report)
    else:
        build_dir = Path(args.build).resolve() if args.build else newest_build()
        if build_dir is None or not (build_dir / 'qa').is_dir():
            print('CHECK_BUILD_ERROR no build folder with qa/ and store/ (run tools/dev/build.py first)')
            return 2
        selected = [name for name in args.only.split(',') if name] or ALL
        unknown = [name for name in selected if name not in ALL]
        if unknown:
            print('CHECK_BUILD_ERROR unknown check: %s' % unknown)
            return 2
        out_dir = build_dir / 'check' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        out_dir.mkdir(parents=True, exist_ok=False)
        print('CHECK_BUILD build=%s head=%s out=%s' % (build_dir, git('rev-parse', '--short', 'HEAD'), out_dir))
        if 'build_json' in selected:
            check_build_json(report, build_dir, args.require_clean)
        if 'pck' in selected:
            check_pck(report, build_dir, args.inject_pck_entry)
        if 'assert_static' in selected:
            check_assert_static(report)
        if 'export_log' in selected:
            check_export_log(report, build_dir, args.inject_export_line, args.export_log_dir)
        if 'run_qa' in selected:
            check_run_qa(report, build_dir, out_dir, args.seconds)
        if 'probe_args' in selected:
            check_probe_args(report, build_dir, out_dir)
        if 'run_store' in selected:
            check_run_store(report, build_dir, out_dir)
        (out_dir / 'result.json').write_text(json.dumps(report.rows, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    failed = report.failed()
    counts = {status: sum(1 for row in report.rows if row['status'] == status) for status in ('PASS', 'WARN', 'FAIL')}
    print('CHECK_BUILD_RESULT pass=%d warn=%d fail=%d' % (counts['PASS'], counts['WARN'], counts['FAIL']))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
