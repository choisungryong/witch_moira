"""Single regression entry point for the current working tree.

    python tools/dev/run_all.py            every check, one after the other
    python tools/dev/run_all.py --quick    skip the slow checks (about a minute)
    python tools/dev/run_all.py --only combat,golden
    python tools/dev/run_all.py --only profile-all          a named group (see ALIASES)
    python tools/dev/run_all.py --jobs 4                    independent checks at the same time
    python tools/dev/run_all.py --changed                   only the checks the changed files can break (see CHANGE_TABLE)

Exit code 0 only when every selected check passes. A Godot test that hits a
script error never quits on its own, so each check has a timeout and a timeout
is reported as a failure, not as a pass. A check whose result never arrives
(crash, exception in this script) is a failure too.

--jobs N (default 1, the old behaviour):
  * every Godot process gets its own APPDATA folder (_local/appdata/run_all_<unit>/);
  * the import cache is refreshed once (run_dev.py --import-only) before anything starts;
  * the golden replay, its text-free twin and the core text check share ONE play of each case (golden_core.gd
    --both --text-check) and, with --jobs above 1, run as one process per case;
  * the printed seconds are wall time between the first unit of a check starting and its last unit ending, so with
    other Godot processes running (other agents, other checks) they are reference values only.
A result that a --changed run did not look at is not a pass: the RUN_ALL line carries "selected": true and the
omitted checks are listed.

Environment failures (TECH-REVIEW-20261120 M5): a check whose result shows WinError 1450, exit code 3221225477 (0xC0000005) or
3221225794 (0xC0000142), a seat or import-lock timeout (repo_lock.py) is run once more. If the second run passes, the row says
"pass(env-retry)" (counted as a pass, named in the RUN_ALL line under "env_retry"); if it fails again for the same kind of reason the
row says "FAIL(env)" (counted as failed, named under "env_fail"). A failure that is not of that kind stays a plain "FAIL".
Every Godot process takes a machine-wide seat (default 6, MOIRA_GODOT_SLOTS) and waits for a running import of this work tree.
"""
from pathlib import Path
import argparse, concurrent.futures, datetime, json, os, re, subprocess, sys, threading, time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_env import isolated_env
import godot_guard
import repo_lock

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))
# The profile test only accepts an isolated QA path below this evidence root.
FIXTURES = 'res://_local/run-all-fixtures/'
GOLDEN_SCRIPT = 'res://chapter1/tests/golden_core.gd'
CORE_TEXT_SCRIPT = 'res://chapter1/tests/test_core_text.gd'
# These three names are served by golden_core.gd (one play of each case) when golden or golden-textless is selected.
GOLDEN_GROUP = ('golden', 'golden-textless', 'core-text')

# --only accepts check names and these groups.
ALIASES = {
    'profile-all': ['profile', 'profile-legacy', 'profile-v4', 'profile-v4-fixtures', 'profile-v5', 'app-guard', 'app-loadout'],
    'core-fast': ['growth', 'tree', 'combat', 'chapter', 'loot', 'rhythm', 'growth-pace', 'meteor', 'run-spells', 'grace', 'descent', 'elites', 'element-kit', 'trial-slice', 'descent-fx', 'skill-lab'],
    'core-all': ['growth', 'tree', 'combat', 'chapter', 'loot', 'rhythm', 'growth-pace', 'meteor', 'run-spells', 'grace', 'descent', 'elites', 'element-kit', 'trial-slice', 'descent-fx', 'skill-lab', 'run-record', 'run-spells-full', 'golden', 'golden-textless', 'core-text', 'loot-sim'],
    'golden-all': ['golden', 'golden-textless', 'core-text'],
    'text': ['loc', 'i18n-scan', 'glyphs'],
    'tools': ['manager', 'i18n-scan', 'glyphs', 'tools-selftest', 'screen-contract'],
    'records': ['tools-selftest', 'wording', 'decisions', 'asset-ledger', 'audio-ledger'],
    'quick': None,  # every check that --quick keeps; filled in by resolve_names()
}

# One place for "which changed path needs which checks" (--changed). A rule is (path prefix or exact path, selection name).
# The union over all changed paths wins; a path that matches no rule selects EVERYTHING.
CHANGE_TABLE = [
    ('chapter1/core/', 'all'),
    ('chapter1/data/', 'all'),
    ('combat/', 'all'),
    ('chapter1/tests/', 'all'),
    ('project.godot', 'all'),
    ('tools/dev/run_all.py', 'all'),
    ('tools/dev/isolated_env.py', 'all'),
    ('tools/dev/godot.py', 'all'),
    ('chapter1/ChapterOne.tscn', 'app'),
    ('chapter1/app/', 'app'),
    ('chapter1/art/asset_slots.json', 'view'),
    ('chapter1/view/', 'view'),
    ('chapter1/art/', 'art'),
    ('chapter1/presentation/', 'view'),
    ('chapter1/i18n/', 'text'),
    ('tools/manager/', 'manager'),
    ('docs/story/', 'records'),
    ('docs/reviews/', 'records'),
    ('docs/specs/', 'records'),
    ('tools/dev/i18n_scan.py', 'text'),
    ('tools/dev/i18n_baseline.json', 'text'),
    ('tools/dev/check_glyphs.py', 'text'),
    ('docs/', 'docs'),
    ('.claude/', 'docs'),
    ('CLAUDE.md', 'docs'),
    ('AGENTS.md', 'docs'),
    ('tools/dev/', 'docs'),
    ('tools/art/', 'tools'),
    ('tools/dev/audio_adopt.py', 'tools'),
    ('tools/dev/test_audio_adopt.py', 'tools'),
    ('art-archive/', 'none'),
    ('_local/', 'none'),
]
# What each selection name turns on. 'all' is every check. 'view' / 'app' leave the headless core checks out.
SELECTIONS = {
    'view': ['loc', 'app-guard', 'app-loadout', 'skill-lab', 'asset-slots', 'world-layout', 'playlog', 'manager', 'i18n-scan', 'glyphs', 'wording', 'screen-contract'],
    'art': ['loc', 'app-guard', 'app-loadout', 'skill-lab', 'world-layout', 'manager', 'i18n-scan', 'glyphs', 'wording', 'asset-ledger', 'audio-ledger'],
    'app': ['loc', 'app-guard', 'app-loadout', 'playlog', 'run-record', 'profile', 'profile-legacy', 'profile-v4', 'profile-v4-fixtures', 'profile-v5', 'manager', 'i18n-scan', 'glyphs', 'wording'],
    'text': ['loc', 'i18n-scan', 'glyphs', 'wording'],
    'records': ['wording', 'decisions', 'manager'],
    'tools': ['tools-selftest', 'asset-ledger', 'audio-ledger', 'screen-contract'],
    'manager': ['manager'],
    'docs': 'quick',
    'none': [],
}
# Rough seconds, only used to start the long checks first when --jobs is above 1.
WEIGHTS = {'run-spells-full': 1100, 'run-spells': 300, 'golden': 120, 'core-text-tail': 15, 'loot-sim': 90, 'rhythm': 45, 'run-record': 60, 'playlog': 30, 'manager': 30, 'chapter': 20}


def godot_check(name, script, marker, extra=(), timeout=120, slow=False, plain=False):
    """plain=True: the script prints `<marker> pass` or `<marker> fail [..]` instead of a JSON result line (test_playlog.gd)."""
    return {'name': name, 'kind': 'godot', 'script': script, 'marker': marker, 'extra': list(extra), 'timeout': timeout, 'slow': slow, 'plain': plain}


def checks():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    return [
        godot_check('growth', 'res://chapter1/tests/test_growth.gd', 'CHAPTER1_GROWTH_RESULT'),
        godot_check('tree', 'res://chapter1/tests/test_skill_tree.gd', 'CHAPTER1_SKILL_TREE_RESULT'),
        godot_check('combat', 'res://chapter1/tests/test_combat_run.gd', 'CHAPTER1_COMBAT_RESULT'),
        godot_check('chapter', 'res://chapter1/tests/test_chapter_run.gd', 'CHAPTER_FULL_TEST'),
        godot_check('profile', 'res://chapter1/tests/test_chapter_profile.gd', 'CHAPTER_PROFILE', ['--fixture-dir=' + FIXTURES + stamp]),
        godot_check('loot', 'res://chapter1/tests/test_loot.gd', 'CHAPTER1_LOOT_RESULT', timeout=300),
        # D23 T1-M: the fixed gear kits of fixtures/gear_kits.json build, validate and wear (sim_power.gd --gear-kit=).
        godot_check('gear-kits', 'res://chapter1/tests/test_gear_kits.gd', 'CHAPTER1_GEAR_KITS_RESULT'),
        godot_check('loc', 'res://chapter1/tests/test_loc.gd', 'CHAPTER1_LOC_RESULT'),
        godot_check('app-guard', 'res://chapter1/tests/test_profile_app_guard.gd', 'CHAPTER1_APP_GUARD_RESULT'),
        godot_check('profile-legacy', 'res://chapter1/tests/test_profile_legacy_fixtures.gd', 'CHAPTER1_PROFILE_LEGACY_RESULT', ['--work-dir=' + FIXTURES + 'legacy-' + stamp]),
        godot_check('profile-v4', 'res://chapter1/tests/test_profile_v4.gd', 'CHAPTER1_PROFILE_V4_RESULT', ['--work-dir=' + FIXTURES + 'v4-' + stamp]),
        godot_check('profile-v4-fixtures', 'res://chapter1/tests/test_profile_v4_fixtures.gd', 'CHAPTER1_PROFILE_V4_FIXTURES_RESULT', ['--work-dir=' + FIXTURES + 'v4fix-' + stamp]),
        godot_check('profile-v5', 'res://chapter1/tests/test_profile_v5.gd', 'CHAPTER1_PROFILE_V5_RESULT', ['--work-dir=' + FIXTURES + 'v5-' + stamp]),
        godot_check('rhythm', 'res://chapter1/tests/test_rhythm.gd', 'CHAPTER1_RHYTHM_TEST_RESULT', timeout=600),
        # D19 C1 growth-pace keys (level table, seal kills, guardian level, orb multipliers, sweep bonus, pace); off equals today.
        godot_check('growth-pace', 'res://chapter1/tests/test_growth_pace.gd', 'CHAPTER1_GROWTH_PACE_RESULT', timeout=300),
        # D20: the evolved ember (Meteor) falls from the sky: booking, landing, chain, data ranges, determinism.
        godot_check('meteor', 'res://chapter1/tests/test_meteor.gd', 'CHAPTER1_METEOR_RESULT', timeout=300),
        godot_check('grace', 'res://chapter1/tests/test_grace.gd', 'CHAPTER1_GRACE_RESULT', timeout=600),
        godot_check('descent', 'res://chapter1/tests/test_descent.gd', 'CHAPTER1_DESCENT_TEST_RESULT', timeout=600),
        godot_check('elites', 'res://chapter1/tests/test_elites.gd', 'CHAPTER1_ELITES_TEST_RESULT', timeout=600),
        # D-boss-finale (BF1~BF9): the final boss's entrance, three phases and two breaks, switched on in memory; the shipped switch stays off.
        godot_check('boss-finale', 'res://chapter1/tests/test_boss_finale.gd', 'CHAPTER1_BOSS_FINALE_RESULT', timeout=900),
        # D-element-trees ET-A: the element kit (arc only): data format, status and chain, rod, overload, card engine, permanent tree, profile move, boss break, snapshot; switched on in memory.
        godot_check('element-kit', 'res://chapter1/tests/test_element_kit.gd', 'CHAPTER1_ELEMENT_KIT_RESULT', timeout=900),
        # S1-A (T14): the "one run" trial (data/trial_slice.json, app/trial_slice.gd): one definition for the app, checks and measurement; plus the kit's read-only values, C5 descent points, C6 verdict weights, boss shortcut with the kit.
        godot_check('trial-slice', 'res://chapter1/tests/test_trial_slice.gd', 'CHAPTER1_TRIAL_SLICE_RESULT', timeout=900),
        godot_check('descent-fx', 'res://chapter1/tests/test_descent_fx.gd', 'CHAPTER1_DESCENT_FX_TEST_RESULT', timeout=300),
        # T12 SL-D: the skill lab body (stage, commands, sound overrides, soak) in a headless run; the line SKILL_LAB_TEST {"pass": ...} decides.
        godot_check('skill-lab', 'res://chapter1/tests/test_skill_lab.gd', 'SKILL_LAB_TEST', ['--chapter1-start', '--chapter1-profile-off', '--chapter1-qa-ignore-focus', '--chapter1-trial=descent', '--chapter1-descent-cost=1000'], timeout=600),
        godot_check('asset-slots', 'res://chapter1/tests/test_asset_slots.gd', 'CHAPTER1_ASSET_SLOTS_RESULT', ['--strict'], timeout=180),
        # A12-0: what the world presenter places (props, stones, masonry, edge, grass) equals the snapshot of the code that held it as literals, bit for bit.
        godot_check('world-layout', 'res://chapter1/tests/test_world_layout.gd', 'CHAPTER1_WORLD_LAYOUT_RESULT', timeout=180),
        godot_check('ui-parts', 'res://chapter1/tests/test_ui_parts.gd', 'CHAPTER1_UI_PARTS_RESULT', timeout=120),
        godot_check('run-record','res://chapter1/tests/test_run_record.gd', 'CHAPTER1_RUN_RECORD_TEST_RESULT', timeout=900),
        # The unit checks (parts A to E, 191 checks) run always; the enabled whole chapters (part F, 15 checks, about 18 minutes) are the slow line.
        godot_check('run-spells', 'res://chapter1/tests/test_run_spells.gd', 'CHAPTER1_RUN_SPELLS_RESULT', ['--fast'], timeout=900),
        godot_check('run-spells-full', 'res://chapter1/tests/test_run_spells.gd', 'CHAPTER1_RUN_SPELLS_RESULT', ['--runs-only'], timeout=2400, slow=True),
        # Plays a 90 s pilot run and checks the play log file (about 30 s, so it stays in --quick).
        godot_check('playlog', 'res://chapter1/tests/test_playlog.gd', 'TEST_PLAYLOG', plain=True),
        godot_check('app-loadout', 'res://chapter1/tests/test_profile_app_loadout.gd', 'CHAPTER1_APP_LOADOUT_RESULT'),
        # These three are run together by build_tasks() (one play of each case); the literals here are what tools/manager reads.
        godot_check('golden', 'res://chapter1/tests/golden_core.gd', 'GOLDEN_RESULT', timeout=600, slow=True),
        godot_check('golden-textless', 'res://chapter1/tests/golden_core.gd', 'GOLDEN_RESULT', ['--textless'], timeout=600, slow=True),
        godot_check('core-text', 'res://chapter1/tests/test_core_text.gd', 'CHAPTER1_CORE_TEXT_RESULT', timeout=600, slow=True),
        godot_check('loot-sim', 'res://chapter1/tests/sim_loot.gd', 'LOOT_SIM', ['--runs=3000'], timeout=600, slow=True),
        {'name': 'manager', 'kind': 'python', 'timeout': 300, 'slow': False},
        {'name': 'i18n-scan', 'kind': 'i18n-scan', 'timeout': 60, 'slow': False},
        {'name': 'glyphs', 'kind': 'glyphs', 'timeout': 120, 'slow': False},
        # Record checks (docs/PROCESS-CHECKS.ko.md 2). Pass/fail only; tools/dev/audit.py counts the same things and compares with last time.
        {'name': 'tools-selftest', 'kind': 'tools-selftest', 'timeout': 600, 'slow': False},
        {'name': 'wording', 'kind': 'wording', 'timeout': 120, 'slow': False},
        {'name': 'decisions', 'kind': 'decisions', 'timeout': 120, 'slow': False},
        {'name': 'asset-ledger', 'kind': 'asset-ledger', 'timeout': 120, 'slow': False},
        {'name': 'audio-ledger', 'kind': 'audio-ledger', 'timeout': 120, 'slow': False},
        # Screen contracts (docs/SCREEN-DESIGN-HARNESS.ko.md 6): fixtures against the schema, what the screen files read, text contrast.
        {'name': 'screen-contract', 'kind': 'screen-contract', 'timeout': 420, 'slow': False},
    ]


# ---------------------------------------------------------------------------------------------------- environment failures

ENV_EXIT_CODES = (3221225477, 3221225794)  # 0xC0000005 access violation, 0xC0000142 DLL initialization failed
ENV_TEXT = re.compile(r'WinError 1450|\b3221225477\b|\b3221225794\b|0xC0000005|0xC0000142')
ENV_RETRY_MARK = '[env-retry: %s]'  # a runner that retried inside itself (tools-selftest) says so with this; done_task turns it into pass(env-retry)


def env_hint(code, text):
    """' [env: ...]' when an exit code or text shows an environment failure, else ''. Added to the detail of a failed runner."""
    if code in ENV_EXIT_CODES:
        return ' [env: exit %d]' % code
    found = ENV_TEXT.search(text or '')
    return ' [env: %s]' % found.group(0) if found else ''


def env_reason(out):
    """Why a unit's output looks like an environment failure (a short text), or None. A passing output is never one."""
    if isinstance(out, dict):
        if out.get('env'):
            return out['env']
        if 'exception' in out:
            found = ENV_TEXT.search(out['exception'])
            return found.group(0) if found else None
        code = out.get('code')
        if code in ENV_EXIT_CODES:
            return 'exit %d' % code
        found = ENV_TEXT.search(out.get('text') or '') if code != 0 else None
        return found.group(0) if found else None
    if isinstance(out, tuple) and len(out) == 2 and not out[0]:
        found = ENV_TEXT.search(str(out[1]))
        return found.group(0) if found else None
    return None


# ---------------------------------------------------------------------------------------------------- processes

def run_process(script, extra, timeout, purpose, cwd=None):
    """One Godot process with its own APPDATA folder. Returns {'timeout': bool, 'code': int|None, 'text': str}."""
    command = [str(GODOT), '--headless', '--path', str(ROOT), '--script', script]
    if extra:
        command += ['--'] + list(extra)
    # The whole process tree is ended on a timeout: ending only the console parent leaves the engine child (and its window) running.
    try:
        code, out, timed_out = godot_guard.run_seated(command, timeout, env=isolated_env('run_all_' + purpose), capture=True, label=purpose, cwd=cwd)
    except repo_lock.LockTimeout as error:  # no seat or an import that did not end: an environment failure, not a verdict on the check
        return {'timeout': 0, 'code': None, 'text': str(error), 'env': str(error).split(' ', 1)[0]}
    text = (out or b'').decode('utf-8', 'replace')
    if timed_out:
        return {'timeout': timeout, 'code': None, 'text': text}
    return {'timeout': 0, 'code': code, 'text': text}


def timeout_detail(proc):
    error = re.search(r'SCRIPT ERROR: (.+)', proc['text'])
    return 'timeout after %ds%s' % (proc['timeout'], ' · ' + error.group(1).strip() if error else '')


def parse_godot(check, proc):
    """(passed, detail) of one ordinary Godot check."""
    if proc['timeout']:
        return False, timeout_detail(proc)
    text = proc['text']
    if check.get('plain'):
        passed = re.search(r'^' + re.escape(check['marker']) + r' pass(?![A-Za-z])', text, re.M)
        failed = re.search(r'^' + re.escape(check['marker']) + r' fail (.*)', text, re.M)
        script_error = re.search(r'SCRIPT ERROR: (.+)', text)
        if script_error:
            return False, 'SCRIPT ERROR: ' + script_error.group(1).strip()
        if failed:
            return False, 'fail ' + failed.group(1).strip()[:200]
        return proc['code'] == 0 and bool(passed), 'pass' if passed else 'no result line'
    found = re.search(re.escape(check['marker']) + r'\S* (\{.*\})', text)
    detail = ''
    if found:
        try:
            result = json.loads(found.group(1))
            if 'checks' in result:
                detail = '%d checks, %d failures' % (result['checks'], len(result.get('failures', [])))
            elif 'mismatches' in result:
                count = result.get('cases', result.get('runs', 0))
                detail = '%d %s, %d mismatches' % (count, 'cases' if 'cases' in result else 'runs', len(result['mismatches']))
                if 'per_run_average' in result:
                    average = result['per_run_average']
                    detail += ' · per run rare %.2f, jewelry %.2f, legendary %.2f, unique %.2f' % (average['rare'], average['jewelry'], average['legendary'], average['unique'])
                if result['mismatches']:
                    detail += ' · ' + result['mismatches'][0]
            if result.get('failures'):
                detail += ' · ' + str(result['failures'][0])
            if 'pass' in result:  # a result line that carries its own verdict (SKILL_LAB_TEST)
                fails = result.get('fails', [])
                detail = 'pass' if result['pass'] else '%d fails · %s' % (len(fails), str(fails[0])[:160] if fails else '?')
                if result.get('skipped'):
                    detail += ' · skipped %d' % len(result['skipped'])
                if not result['pass'] or proc['code'] != 0:
                    return False, detail
        except ValueError:
            detail = 'unreadable result line'
    else:
        error = re.search(r'(?:SCRIPT ERROR|ERROR): (?!BUG: Unreferenced)(.+)', text)
        detail = 'no result line' + (' · ' + error.group(1).strip() if error else '')
    # A script error stops a test function in the middle and the run still prints a clean result line with fewer checks
    # (found while doing T3-L1), so any script error is a failure.
    script_error = re.search(r'SCRIPT ERROR: (.+)', text)
    if script_error:
        return False, (detail + ' · ' if detail else '') + 'SCRIPT ERROR: ' + script_error.group(1).strip()
    return proc['code'] == 0 and bool(found), detail or 'exit %d' % proc['code']


def run_manager(check):
    command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'tools/manager', '-p', 'test_*.py']
    try:
        done = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=check['timeout'])
    except subprocess.TimeoutExpired:
        return False, 'timeout after %ds' % check['timeout']
    text = done.stderr.decode('utf-8', 'replace')
    ran = re.search(r'Ran (\d+) tests?', text)
    failed = re.findall(r'^(?:FAIL|ERROR): (\w+)', text, re.M)
    detail = (ran.group(1) + ' tests' if ran else 'no summary') + (', failed: ' + ', '.join(failed) if failed else '')
    if done.returncode != 0:
        detail += env_hint(done.returncode, text)
    return done.returncode == 0, detail


def run_i18n_scan(check):
    command = [sys.executable, str(ROOT / 'tools' / 'dev' / 'i18n_scan.py')]
    try:
        done = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=check['timeout'])
    except subprocess.TimeoutExpired:
        return False, 'timeout after %ds' % check['timeout']
    text = done.stdout.decode('utf-8', 'replace')
    found = re.search(r'I18N_SCAN (\{.*\})', text)
    if not found:
        return False, 'no result line' + env_hint(done.returncode, text + done.stderr.decode('utf-8', 'replace'))
    result = json.loads(found.group(1))
    detail = '%d files, %d Hangul literals (baseline %d)' % (result['files'], result['total'], result['baseline_total'])
    if result['grown']:
        detail += ' · grew: ' + result['grown'][0]
    return done.returncode == 0, detail


def run_glyphs(check):
    command = [sys.executable, str(ROOT / 'tools' / 'dev' / 'check_glyphs.py')]
    try:
        done = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=check['timeout'])
    except subprocess.TimeoutExpired:
        return False, 'timeout after %ds' % check['timeout']
    lines = done.stdout.decode('utf-8', 'replace').strip().splitlines()
    detail = (lines[0] if done.returncode else '') + (' · ' if done.returncode else '') + (lines[-1] if lines else 'no output')
    return done.returncode == 0, detail + (env_hint(done.returncode, done.stderr.decode('utf-8', 'replace')) if done.returncode else '')


def run_tool(check, args):
    """A python tool as a child process. (exit code, stdout text) or (None, reason) on a timeout."""
    env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
    try:
        done = subprocess.run([sys.executable] + args, cwd=ROOT, capture_output=True, timeout=check['timeout'], env=env)
    except subprocess.TimeoutExpired:
        return None, 'timeout after %ds' % check['timeout']
    return done.returncode, done.stdout.decode('utf-8', 'replace') + '\n' + done.stderr.decode('utf-8', 'replace')


def run_tools_selftest(check):
    """Every tools/dev/test_*.py and tools/art/test_*.py, each as its own process (unittest or plain script: the exit code decides)."""
    files = sorted(list((ROOT / 'tools' / 'dev').glob('test_*.py')) + list((ROOT / 'tools' / 'art').glob('test_*.py')))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:  # the files are independent (temp folders only); the audio one alone takes about a minute
        results = list(pool.map(lambda path: run_tool(check, [str(path)]), files))
    # A file that fails while four run side by side gets one more run on its own: under a loaded machine these self tests have failed
    # once and passed alone (2026-11-21). A retried file is named in the result so a real flake does not stay hidden.
    retried, first_run = [], {}
    for index, path in enumerate(files):
        if results[index][0] != 0:
            retried.append(path.name)
            first_run[path.name] = results[index]
            results[index] = run_tool(check, [str(path)])
    failed = [path.name + (' (' + text + ')' if code is None else '') + env_hint(code, text) for path, (code, text) in zip(files, results) if code != 0]
    note = ', failed: ' + ', '.join(failed) if failed else ''
    rescued = [name for name in retried if name not in ' '.join(failed)]
    if rescued:
        # what the first run said (its last line) stays in the result, so a flake is not only a name; an environment sign makes it an env-retry
        tails = []
        for name in rescued:
            lines = [l.strip() for l in (first_run[name][1] or '').splitlines() if l.strip()]
            tails.append('%s [first run: %s]' % (name, (lines[-1] if lines else 'no output')[:120]))
        note += ', passed on a second run alone: ' + ', '.join(tails)
        reasons = [env_hint(*first_run[name]).strip() for name in rescued if env_hint(*first_run[name])]
        if reasons:
            note += ' ' + ENV_RETRY_MARK % reasons[0].strip('[]').replace('env: ', '')
    return not failed and bool(files), '%d files%s' % (len(files), note)


CONTRACT_TEST = 'res://chapter1/tests/test_screen_contracts.gd'
CONTRACT_TEST_RESULT = 'CHAPTER1_SCREEN_CONTRACTS_RESULT'


def run_screen_contract(check):
    """The contract checker (tools/dev/screen_contract_check.py). When chapter1/tests/test_screen_contracts.gd exists it is run
    first (isolated, seated) to write the real adapter outputs, which the checker then reads with --dumps."""
    command = [str(ROOT / 'tools' / 'dev' / 'screen_contract_check.py')]
    dumps_note = 'dumps 0 (test missing)'
    if (ROOT / 'chapter1' / 'tests' / 'test_screen_contracts.gd').is_file():
        out_dir = '_local/run-all-fixtures/contracts-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        proc = run_process(CONTRACT_TEST, ['--out=' + out_dir], 300, 'screen-contract', cwd=ROOT)
        if proc['timeout']:
            return False, timeout_detail(proc)
        found = re.search(CONTRACT_TEST_RESULT + r' (\{.*\})', proc['text'])
        error = re.search(r'SCRIPT ERROR: (.+)', proc['text'])
        if proc.get('env') or not found or proc['code'] != 0 or error:
            what = 'SCRIPT ERROR: ' + error.group(1).strip() if error else 'no result line (exit %s)' % proc['code']
            return False, 'contract test: ' + what + (' [env: %s]' % proc['env'] if proc.get('env') else env_hint(proc['code'], proc['text']))
        failures = json.loads(found.group(1)).get('failures', [])
        if failures:
            return False, 'contract test: %d failures · %s' % (len(failures), str(failures[0])[:200])
        command.append('--dumps=' + str(ROOT / out_dir))
        if (ROOT / out_dir / 'layout').is_dir():  # the layout rows of the screens built on fixtures: the contrast check reads them
            command.append('--layout-dump=' + str(ROOT / out_dir / 'layout'))
        dumps_note = ''
    code, text = run_tool(check, command)
    if code is None:
        return False, text
    found = re.search(r'^SCREEN_CONTRACT (\{.*\})\s*$', text, re.M)
    if not found:
        return False, 'no result line (exit %d)' % code
    result = json.loads(found.group(1))
    detail = '%d screens, %d fixtures, %d dumps, %d failures' % (result['screens'], result['fixtures'], result['dumps'], len(result['failures']))
    if result.get('unchecked_fixtures'):
        detail += ' · %d fixtures without a schema yet (not checked)' % result['unchecked_fixtures']
    if result['failures']:
        detail += ' · ' + str(result['failures'][0])[:200]
    return code == 0 and not result['failures'], detail + (' · ' + dumps_note if dumps_note else '')


def run_wording(check):
    code, text = run_tool(check, [str(ROOT / 'tools' / 'dev' / 'wording_lint.py'), '--json'])
    if code is None:
        return False, text
    try:
        result = json.loads(text[:text.rindex('}') + 1])
    except ValueError:
        return False, 'unreadable result (exit %d)' % code
    return result['fail'] == 0 and code == 0, '%d texts, fail %d, warn %d, pending a decision %d' % (result['texts'], result['fail'], result['warn'], result['pending'])


def run_decisions(check):
    code, text = run_tool(check, [str(ROOT / 'tools' / 'dev' / 'decision_ledger.py')])
    if code is None:
        return False, text
    found = re.search(r'LEDGER (PASS|FAIL) numbers=(\d+) overlaps=(\d+)', text)
    if not found:
        return False, 'no result line (exit %d)' % code
    return code == 0 and found.group(1) == 'PASS', '%s numbers, %s overlaps' % (found.group(2), found.group(3))


def run_asset_ledger(check):
    """Errors fail; the "unconfirmed" holes are counted but are not a failure (the assets are to be replaced)."""
    code, text = run_tool(check, [str(ROOT / 'tools' / 'art' / 'asset_ledger.py'), 'check'])
    if code is None:
        return False, text
    errors = re.search(r'== 오류[^:\n]*: (\d+)', text)
    holes = re.search(r"== 구멍: '미확인' 칸이 있는 항목 (\d+)", text)
    if not errors:
        return False, 'no result line (exit %d)' % code
    return code == 0 and int(errors.group(1)) == 0, '%s errors, %s entries with unconfirmed fields (not a failure)' % (errors.group(1), holes.group(1) if holes else '?')


def run_audio_ledger(check):
    code, text = run_tool(check, [str(ROOT / 'tools' / 'dev' / 'audio_ledger_check.py')])
    if code is None:
        return False, text
    found = re.search(r'RESULT: (.+)', text)
    return code == 0, found.group(1).strip() if found else 'no result line (exit %d)' % code


# ---------------------------------------------------------------------------------------------------- the golden group

def golden_case_keys():
    proc = run_process(GOLDEN_SCRIPT, ['--list-cases'], 120, 'golden-list')
    found = re.search(r'GOLDEN_CASE_LIST (\[.*\])', proc['text'])
    if proc['timeout'] or not found:
        return []
    return json.loads(found.group(1))


def combine_golden(wanted, mode, procs):
    """Rows of the golden group from the processes' output. wanted: names asked for; mode: 'both', 'textless' or 'plain'."""
    rows = {}

    def problems_of(group):  # a process that timed out or hit a script error fails every row it feeds
        found_problems = []
        for proc in group:
            if proc['timeout']:
                found_problems.append(timeout_detail(proc))
            else:
                error = re.search(r'SCRIPT ERROR: (.+)', proc['text'])
                if error:
                    found_problems.append('SCRIPT ERROR: ' + error.group(1).strip())
        return found_problems

    golden_procs = [proc for proc in procs if not proc.get('tail')]  # the core-text --tail process has no golden result
    for name in wanted:
        if name == 'core-text':
            continue
        problems = problems_of(golden_procs)
        marker = 'GOLDEN_TEXTLESS_RESULT' if (name == 'golden-textless' and mode == 'both') else 'GOLDEN_RESULT'
        cases, mismatches, missing = 0, [], 0
        for proc in golden_procs:
            found = re.search(r'^' + marker + r' (\{.*\})', proc['text'] or '', re.M)
            if not found:
                missing += 1
                continue
            result = json.loads(found.group(1))
            cases += int(result.get('cases', 0))
            mismatches += result.get('mismatches', [])
        detail = '%d cases, %d mismatches' % (cases, len(mismatches)) + (' · ' + mismatches[0] if mismatches else '')
        if missing:
            detail = 'no result line' if not cases else detail + ' · no result line from %d process(es)' % missing
        if problems:
            detail += ' · ' + problems[0]
        rows[name] = (not problems and not missing and not mismatches and all(p['code'] in (0, 1) for p in golden_procs), detail)
    if 'core-text' in wanted:
        problems = problems_of(procs)
        total, failures, offending, missing = 0, [], {}, 0
        for proc in procs:
            found = re.search(r'^CORE_TEXT_PART (\{.*\})', proc['text'] or '', re.M)
            if not found:
                missing += 1
                continue
            part = json.loads(found.group(1))
            total += int(part['checks'])
            failures += part['failures']
            offending.update(part['offending'])
        # test_core_text.gd counts the "nothing outside the equipment text" check once, after all plays.
        total += 1
        if offending:
            failures.append('no Hangul outside the equipment text: ' + json.dumps(offending, ensure_ascii=False, separators=(',', ':')))
        detail = '%d checks, %d failures' % (total, len(failures)) + (' · ' + str(failures[0]) if failures else '')
        if missing:
            detail = 'no result line' if not total > 1 else detail + ' · no result line from %d process(es)' % missing
        if problems:
            detail += ' · ' + problems[0]
        rows['core-text'] = (not problems and not missing and not failures, detail)
    return rows


# ---------------------------------------------------------------------------------------------------- tasks

class Task:
    """names: rows it yields; units: [(label, weight, function() -> output)]; combine(outputs) -> {name: (passed, detail)}."""

    def __init__(self, names, units, combine):
        self.names, self.units, self.combine = names, units, combine


def build_tasks(selected, jobs, golden_files):
    by_name = {check['name']: check for check in selected}
    tasks = []
    group_done = False
    for check in selected:
        name = check['name']
        if name in GOLDEN_GROUP and ('golden' in by_name or 'golden-textless' in by_name):
            if group_done:
                continue
            group_done = True
            wanted = [n for n in GOLDEN_GROUP if n in by_name]
            mode = 'both' if ('golden' in by_name and 'golden-textless' in by_name) else ('textless' if 'golden-textless' in by_name else 'plain')
            flags = {'both': ['--both'], 'textless': ['--textless'], 'plain': []}[mode] + (['--text-check'] if 'core-text' in by_name else []) + golden_files
            timeout = 900 if jobs > 1 else 1500
            keys = golden_case_keys() if jobs > 1 else []
            units = []
            if keys:
                for key in keys:
                    label = 'golden-' + re.sub(r'[^A-Za-z0-9._-]', '_', key)
                    units.append((label, WEIGHTS['golden'], (lambda f=flags + ['--case=' + key], l=label: run_process(GOLDEN_SCRIPT, f, timeout, l))))
            else:
                units.append(('golden-all', WEIGHTS['golden'] * 3, lambda: run_process(GOLDEN_SCRIPT, flags, timeout, 'golden-all')))
            if 'core-text' in by_name:
                units.append(('core-text-tail', WEIGHTS['core-text-tail'], lambda: dict(run_process(CORE_TEXT_SCRIPT, ['--tail'], 300, 'core-text-tail'), tail=True)))
            tasks.append(Task(wanted, units, lambda outs, w=wanted, m=mode: combine_golden(w, m, outs)))
            continue
        weight = WEIGHTS.get(name, 10)
        if check['kind'] == 'godot':
            unit = (name, weight, lambda c=check: run_process(c['script'], c['extra'], c['timeout'], c['name']))
            tasks.append(Task([name], [unit], lambda outs, c=check: {c['name']: parse_godot(c, outs[0])}))
        else:
            runner = {'python': run_manager, 'i18n-scan': run_i18n_scan, 'glyphs': run_glyphs, 'tools-selftest': run_tools_selftest, 'wording': run_wording,
                      'decisions': run_decisions, 'asset-ledger': run_asset_ledger, 'audio-ledger': run_audio_ledger, 'screen-contract': run_screen_contract}[check['kind']]
            tasks.append(Task([name], [(name, weight, lambda c=check, r=runner: r(c))], lambda outs, c=check: {c['name']: outs[0]}))
    return tasks


def run_unit(fn, label='unit', pause=3.0):
    """Runs one unit. An output that shows an environment failure is run once more (M5). Returns (output, started, ended, env)
    where env is None, ('retry', reason) when the second run was not an environment failure, or ('fail', reason) when it was."""
    started = time.time()

    def attempt():
        try:
            return fn()
        except Exception as error:  # a crashing runner must not take the other checks' results with it
            return {'exception': '%s: %s' % (type(error).__name__, error)}

    out = attempt()
    env = None
    reason = env_reason(out)
    if reason:
        print('ENV_RETRY %s: %s, running it once more' % (label, reason), flush=True)
        time.sleep(pause)
        out = attempt()
        again = env_reason(out)
        env = ('fail', again) if again else ('retry', reason)
    return out, started, time.time(), env


def status_of(passed, envs):
    """Row status. pass(env-retry): passed after an environment failure; FAIL(env): failed and the last run was one too."""
    envs = [e for e in envs if e]
    if passed:
        return 'pass(env-retry)' if envs else 'pass'
    return 'FAIL(env)' if any(e[0] == 'fail' for e in envs) else 'FAIL'


def finish_task(task, outputs):
    """Rows (name -> (passed, detail)) of a finished task. An exception or a missing output fails every row."""
    broken = [o['exception'] for o in outputs if isinstance(o, dict) and 'exception' in o]
    if broken or any(o is None for o in outputs):
        detail = 'runner exception · ' + broken[0] if broken else 'no result'
        return {name: (False, detail) for name in task.names}
    try:
        rows = task.combine(outputs)
    except Exception as error:
        return {name: (False, 'result unreadable · %s: %s' % (type(error).__name__, error)) for name in task.names}
    for name in task.names:
        rows.setdefault(name, (False, 'no result'))
    return rows


def execute(tasks, jobs, emit):
    """Runs every unit; calls emit(name, status, detail, seconds) when all units of a task are done."""
    outputs = {i: [None] * len(task.units) for i, task in enumerate(tasks)}
    spans = {i: [] for i in range(len(tasks))}
    envs = {i: [] for i in range(len(tasks))}
    remaining = {i: len(task.units) for i, task in enumerate(tasks)}

    def done_task(i):
        task = tasks[i]
        rows = finish_task(task, outputs[i])
        seconds = max(s[1] for s in spans[i]) - min(s[0] for s in spans[i]) if spans[i] else 0
        for name in task.names:
            passed, detail = rows[name]
            status = status_of(passed, envs[i])
            if status == 'pass' and '[env-retry:' in detail:  # the runner retried inside itself and saw an environment failure
                status = 'pass(env-retry)'
            marks = [e[1] for e in envs[i] if e]
            if marks and status != 'pass':
                detail += ' · env: ' + marks[0]
            emit(name, status, detail, seconds)

    if jobs <= 1:
        for i, task in enumerate(tasks):
            for j, unit in enumerate(task.units):
                out, begin, end, env = run_unit(unit[2], unit[0])
                outputs[i][j] = out
                spans[i].append((begin, end))
                envs[i].append(env)
            done_task(i)
        return
    lock = threading.Lock()
    order = sorted(((i, j) for i, task in enumerate(tasks) for j in range(len(task.units))), key=lambda p: -tasks[p[0]].units[p[1]][1])
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(run_unit, tasks[i].units[j][2], tasks[i].units[j][0]): (i, j) for i, j in order}
        for future in concurrent.futures.as_completed(futures):
            i, j = futures[future]
            try:
                out, begin, end, env = future.result()
            except Exception as error:
                out, begin, end, env = {'exception': '%s: %s' % (type(error).__name__, error)}, time.time(), time.time(), None
            with lock:
                outputs[i][j] = out
                spans[i].append((begin, end))
                envs[i].append(env)
                remaining[i] -= 1
                if remaining[i] == 0:
                    done_task(i)


# ---------------------------------------------------------------------------------------------------- selection

def resolve_names(text, everything):
    """Check names from --only: names and ALIASES."""
    known = {check['name']: check for check in everything}
    names = []
    for word in [w.strip() for w in text.split(',') if w.strip()]:
        if word == 'quick':
            names += [check['name'] for check in everything if not check['slow']]
        elif word in ALIASES:
            names += ALIASES[word]
        elif word in known:
            names.append(word)
        else:
            raise SystemExit('unknown check or group: %s (checks: %s; groups: %s)' % (word, ', '.join(known), ', '.join(ALIASES)))
    return set(names)


def changed_paths():
    paths = set()
    for command in (['git', 'diff', '--name-only', 'HEAD'], ['git', 'ls-files', '--others', '--exclude-standard']):
        done = subprocess.run(command, cwd=ROOT, capture_output=True)
        if done.returncode != 0:
            return None
        paths |= {line.strip().replace('\\', '/') for line in done.stdout.decode('utf-8', 'replace').splitlines() if line.strip()}
    return sorted(paths)


def select_changed(everything, paths):
    """(names to run, explanation) for the changed paths. Unknown paths select every check."""
    names = {check['name'] for check in everything}
    quick = {check['name'] for check in everything if not check['slow']}
    if paths is None:
        return names, 'git failed: everything'
    if not paths:
        return quick, 'no changed file: the quick set'
    chosen, reasons = set(), []
    for path in paths:
        selection = None
        for prefix, rule in CHANGE_TABLE:
            if path == prefix or (prefix.endswith('/') and path.startswith(prefix)):
                selection = rule
                break
        if selection is None or selection == 'all':
            return names, '%s -> everything%s' % (path, '' if selection else ' (unknown path)')
        picked = quick if SELECTIONS[selection] == 'quick' else set(SELECTIONS[selection])
        chosen |= picked
        reasons.append('%s -> %s' % (path, selection))
    return chosen, '%d changed file(s): %s' % (len(paths), ', '.join(sorted({r.split(' -> ')[1] for r in reasons})))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--quick', action='store_true', help='skip slow checks')
    parser.add_argument('--only', default='', help='comma separated check names or groups: ' + ', '.join(ALIASES))
    parser.add_argument('--json', default='', help='write the summary to this file')
    parser.add_argument('--jobs', type=int, default=1, help='checks run at the same time (default 1)')
    parser.add_argument('--changed', action='store_true', help='only the checks the changed files can break (git diff HEAD plus new files); the RUN_ALL line says "selected": true')
    parser.add_argument('--list', action='store_true', help='print the selected checks and stop (nothing is run)')
    parser.add_argument('--golden-file', default='', help='read this file as the golden baseline instead (negative tests)')
    parser.add_argument('--golden-textless-file', default='', help='read this file as the text-free baseline instead (negative tests)')
    options = parser.parse_args()
    if not GODOT.is_file():
        raise SystemExit('Godot not found: ' + str(GODOT) + ' (set MOIRA_GODOT)')
    jobs = max(1, options.jobs)
    everything = checks()
    wanted = resolve_names(options.only, everything)
    omitted = []
    if options.changed:
        chosen, why = select_changed(everything, changed_paths())
        print('CHANGED ' + why, flush=True)
        omitted = [check['name'] for check in everything if check['name'] not in chosen and (not wanted or check['name'] in wanted)]
        wanted = chosen & wanted if wanted else chosen
        if omitted:
            print('OMITTED (not looked at, not a pass) ' + ', '.join(omitted), flush=True)
    summary = {}
    skipped_rows = []
    selected = []
    for check in everything:
        if wanted and check['name'] not in wanted:
            continue
        if options.quick and check['slow']:
            skipped_rows.append({'name': check['name'], 'status': 'skipped', 'detail': '--quick', 'seconds': 0})
            continue
        selected.append(check)
    if options.list:
        print('SELECTED ' + ', '.join(check['name'] for check in selected))
        return 0
    golden_files = []
    if options.golden_file:
        golden_files.append('--golden=' + options.golden_file)
    if options.golden_textless_file:
        golden_files.append('--golden-textless=' + options.golden_textless_file)
    if jobs > 1 and any(check['kind'] == 'godot' for check in selected):
        # Parallel Godot processes must not all try to import at once: bring the cache up to date first.
        command = [sys.executable, str(ROOT / 'tools' / 'dev' / 'run_dev.py'), '--import-only']
        done = subprocess.run(command, capture_output=True)
        retried = done.returncode != 0
        if retried:  # a failed import is an environment failure (M5): once more, and say so
            print('IMPORT exit=%d, running it once more (env-retry)' % done.returncode, flush=True)
            time.sleep(3)
            done = subprocess.run(command, capture_output=True)
        print('IMPORT exit=%d%s' % (done.returncode, (' (env-retry)' if done.returncode == 0 else ' FAIL(env)') if retried else ''), flush=True)
        if done.returncode != 0:
            print(done.stdout.decode('utf-8', 'replace')[-2000:])
            raise SystemExit(done.returncode)
    tasks = build_tasks(selected, jobs, golden_files)

    def emit(name, status, detail, seconds):
        summary[name] = {'name': name, 'status': status, 'detail': detail, 'seconds': round(seconds, 1)}
        row = summary[name]
        print('%-8s %-7s %6.1fs  %s' % (row['name'], row['status'], row['seconds'], row['detail']), flush=True)

    execute(tasks, jobs, emit)
    rows = []
    for check in everything:
        name = check['name']
        if name in summary:
            rows.append(summary[name])
        elif any(r['name'] == name for r in skipped_rows):
            rows.append(next(r for r in skipped_rows if r['name'] == name))
        elif name in omitted:
            rows.append({'name': name, 'status': 'omitted', 'detail': '--changed', 'seconds': 0})
        elif check in selected:  # a selected check that produced no row at all counts as failed
            rows.append({'name': name, 'status': 'FAIL', 'detail': 'no result', 'seconds': 0})
            print('%-8s %-7s %6.1fs  %s' % (name, 'FAIL', 0, 'no result'), flush=True)
    failed = [row['name'] for row in rows if row['status'].startswith('FAIL')]
    line = {'passed': sum(row['status'].startswith('pass') for row in rows), 'failed': failed, 'skipped': [row['name'] for row in rows if row['status'] == 'skipped']}
    if any(row['status'] == 'pass(env-retry)' for row in rows):
        line['env_retry'] = [row['name'] for row in rows if row['status'] == 'pass(env-retry)']
    if any(row['status'] == 'FAIL(env)' for row in rows):
        line['env_fail'] = [row['name'] for row in rows if row['status'] == 'FAIL(env)']
    if options.changed:
        line['selected'] = True
        line['omitted'] = omitted
    print('RUN_ALL ' + json.dumps(line), flush=True)
    if options.json:
        Path(options.json).write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
