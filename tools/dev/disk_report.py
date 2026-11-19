#!/usr/bin/env python3
"""Disk use of the repository and its .claude/worktrees: a fast size table, a worktree table, and a guarded clean-up of regenerable caches.

    python tools/dev/disk_report.py                       # big folders (depth 4, >= 100 MB) of the main checkout and every worktree
    python tools/dev/disk_report.py --worktrees           # one row per worktree: size, last use, live processes, verdict
    python tools/dev/disk_report.py --dups                # large files that look identical (sampled hash). Only listed, never removed
    python tools/dev/disk_report.py --clean               # PLAN only: what could be removed and how much space it returns
    python tools/dev/disk_report.py --clean --apply       # remove exactly the planned, re-checked items

Counting uses os.scandir (no recursion limit, no symlink/junction following, per-folder totals only to --depth, a wall-clock limit
--time-limit). Sizes are file sizes (logical), not clusters. A run that hits the limit is marked PARTIAL and --apply refuses it.

--clean removes only items the rule table (RULES) marks "regenerable": the isolated-APPDATA shader and log caches under
_local/appdata/*/*/, the test fixtures under _local/run-all-fixtures/*, and the .godot import cache of a finished worktree.
It never removes: the user folder (%APPDATA%\\WitchMoira), tracked files, _local/HANDOVER*, _local/sfx/recheck-*, _local/ref/,
anything used in the last 24 hours (--idle-hours cannot go below 24), anything a live process uses (cwd or command line inside it;
any Godot process of the same checkout protects that checkout's caches), links, folders that were not fully counted. It does not end
processes and does not call git worktree remove. Exit code 0; 2 for a bad argument; 3 when --apply could not remove something.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, re, shutil, stat, subprocess, sys, time, unicodedata

sys.path.insert(0, str(Path(__file__).resolve().parent))
import godot_ps

MIN_IDLE_HOURS = 24
MAX_SCAN_DEPTH = 5            # deep enough for _local/appdata/<purpose>/<folder>/shader_cache
REPARSE = getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)
CWD_NAMES = re.compile(r'^(godot|python|py|bash|sh|cmd|powershell|pwsh|git|node|blender|ffmpeg|conhost)', re.I)

# (regex on the lowercase '/'-relative path from a checkout root, kind, deletable, clean, note). First match wins.
# deletable: yes = regenerable, no = keep, ask = a person decides. clean = --clean may remove it (the candidate finders below narrow it further).
RULES = [
    (r'_local/handover[^/]*(/.*)?', 'record', 'no', False, 'handover notes'),
    (r'_local/sfx/recheck-[^/]*(/.*)?', 'recording', 'no', False, 'videos the user listens to'),
    (r'_local/ref(/.*)?', 'recording', 'no', False, 'benchmark recordings'),
    (r'\.git(/.*)?', 'git', 'no', False, 'repository data'),
    (r'_local/appdata/[^/]+/[^/]+/(shader_cache|logs)(/.*)?', 'cache', 'yes', True, 'isolated APPDATA shader/log cache, rebuilt on the next run'),
    (r'_local/appdata/[^/]+/godot(/.*)?', 'cache', 'ask', False, 'editor settings and export templates of an isolated APPDATA'),
    (r'_local/appdata(/.*)?', 'cache', 'ask', False, 'isolated user folder (may hold a test profile)'),
    (r'_local/run-all-fixtures(/.*)?', 'cache', 'yes', True, 'regression temp fixtures, recreated by the tests'),
    (r'\.godot(/.*)?', 'cache', 'yes', True, 'import cache, rebuilt by an import (slow)'),
    (r'_local/(build|builds|export)[^/]*(/.*)?', 'build', 'ask', False, 'built executables'),
    (r'_local/(video|videos|rec|record|recording)[^/]*(/.*)?', 'recording', 'ask', False, 'recordings'),
    (r'_local/(shots|capture|captures|snap|look|review)[^/]*(/.*)?', 'capture', 'ask', False, 'screenshots; the user or a reviewer may still look'),
    (r'_local/(measure|perf|sim|balsim|balance|lab|probe|rhythm)[^/]*(/.*)?', 'measurement', 'ask', False, 'measurement raw data'),
    (r'_local/(art|char3d|fonts|codex-import[^/]*)(/.*)?', 'art-work', 'ask', False, 'art and model work files'),
    (r'_local/(sfx|audio)[^/]*(/.*)?', 'sound-work', 'ask', False, 'sound work and candidates'),
    (r'_local/tools(/.*)?', 'deliverable', 'ask', False, 'task reports and patches'),
    (r'_local(/.*)?', 'other-local', 'ask', False, 'unclassified _local content'),
    (r'\.claude/worktrees/[^/]+(/.*)?', 'worktree', 'ask', False, 'an agent working copy (git worktree remove, not this tool)'),
    (r'(chapter1|combat|docs|tools|art-archive|\.claude)(/.*)?', 'tracked', 'no', False, 'repository files'),
    (r'.*', 'other', 'ask', False, 'unclassified'),
]
RULES_COMPILED = [(re.compile(p, re.I), k, d, c, n) for p, k, d, c, n in RULES]
KIND_KO = {'record': '기록', 'recording': '녹화', 'git': 'git', 'cache': '캐시', 'build': '빌드', 'capture': '캡처', 'measurement': '측정 원시',
           'deliverable': '작업 산출물', 'art-work': '미술 작업물', 'sound-work': '소리 작업물', 'other-local': '_local 기타', 'worktree': 'worktree', 'tracked': '추적 파일', 'other': '기타'}
DELETABLE_KO = {'yes': '예(재생성)', 'no': '아니오(보존)', 'ask': '확인 필요'}

# Candidate finders for --clean: (regex on the key, only in worktrees). The rule of the key must still say clean=True.
CLEAN_PATTERNS = [
    (re.compile(r'_local/appdata/[^/]+/[^/]+/(shader_cache|logs)', re.I), False),
    (re.compile(r'_local/run-all-fixtures/[^/]+', re.I), False),
    (re.compile(r'\.godot', re.I), True),
]


def classify(rel):
    rel = rel.replace('\\', '/').strip('/')
    for regex, kind, deletable, clean, note in RULES_COMPILED:
        if regex.fullmatch(rel):
            return {'kind': kind, 'deletable': deletable, 'clean': clean, 'note': note}
    return {'kind': 'other', 'deletable': 'ask', 'clean': False, 'note': ''}


def protected_rel(rel):
    """True when rel is, lies inside, or is an ancestor of a path that must never be removed."""
    rel = rel.replace(chr(92), '/').strip('/').lower()
    if any(regex.fullmatch(rel) for regex, *_ in RULES_COMPILED[:4]):
        return True
    return any(rel.startswith(guard) or guard.startswith(rel + '/') for guard in ('_local/handover', '_local/sfx/recheck-', '_local/ref'))


# ------------------------------------------------------------------------------------------------------------------ scanning

def long_path(path):
    text = str(path)
    if os.name == 'nt' and not text.startswith('\\\\?\\'):
        text = '\\\\?\\' + os.path.abspath(text)
    return text


def is_link(entry):
    try:
        if entry.is_symlink():
            return True
        st = entry.stat(follow_symlinks=False)
        return bool(getattr(st, 'st_file_attributes', 0) & REPARSE)
    except OSError:
        return True


def scan_tree(root, max_depth, deadline, big_min=0, skip_top=()):
    """Totals per folder key (tuple of path parts under root) up to max_depth.
    Returns {'keys': {parts: [size, files, latest_mtime]}, 'complete': bool, 'errors': [parts], 'links': [parts], 'big': [(size, abs, mtime, parts)]}."""
    keys, errors, links, big = {}, [], [], []
    complete = True
    stack = [(long_path(root), ())]
    keys[()] = [0, 0, 0.0]

    def add(parts, size, count, mtime):
        for depth in range(min(len(parts), max_depth) + 1):
            slot = keys.get(parts[:depth])
            if slot is None:
                slot = keys[parts[:depth]] = [0, 0, 0.0]
            slot[0] += size
            slot[1] += count
            if mtime > slot[2]:
                slot[2] = mtime

    while stack:
        if time.monotonic() > deadline:
            complete = False
            break
        folder, parts = stack.pop()
        try:
            iterator = os.scandir(folder)
        except OSError:
            errors.append(parts)
            continue
        with iterator:
            while True:
                try:
                    entry = next(iterator)
                except StopIteration:
                    break
                except OSError:
                    errors.append(parts)
                    break
                child = parts + (entry.name,)
                try:
                    if is_link(entry):
                        links.append(child)
                        continue
                    if entry.is_dir(follow_symlinks=False):
                        if not parts and entry.name in skip_top:
                            continue
                        add(child, 0, 0, entry.stat(follow_symlinks=False).st_mtime)
                        stack.append((entry.path, child))
                    else:
                        st = entry.stat(follow_symlinks=False)
                        add(parts, st.st_size, 1, st.st_mtime)
                        if big_min and st.st_size >= big_min:
                            big.append((st.st_size, entry.path, st.st_mtime, child))
                except OSError:
                    errors.append(child)
    return {'keys': keys, 'complete': complete, 'errors': errors, 'links': links, 'big': big}


def rel_of(parts):
    return '/'.join(parts)


# ------------------------------------------------------------------------------------------------------------------ roots and processes

class Root:
    def __init__(self, path, label, is_main):
        self.path = Path(path)
        self.label = label
        self.is_main = is_main
        self.scan = None


def find_roots(main):
    main = Path(main)
    roots = [Root(main, 'main', True)]
    folder = main / '.claude' / 'worktrees'
    try:
        names = sorted(e.name for e in os.scandir(folder) if e.is_dir(follow_symlinks=False))
    except OSError:
        names = []
    for name in names:
        roots.append(Root(folder / name, name, False))
    return roots


def norm(path):
    return str(path).replace('\\', '/').rstrip('/').lower()


def list_processes(main):
    """Rows {pid, name, paths:[normalised folders mentioned by cwd or command line]} or None when the list cannot be read."""
    try:
        rows = godot_ps.list_processes()
    except Exception:
        return None
    result = []
    for row in rows:
        if row['pid'] == os.getpid():
            continue
        cwd = row.get('cwd') or ''
        if not cwd and CWD_NAMES.match(row['name'] or ''):
            cwd = godot_ps.process_cwd(row['pid'])
        result.append({'pid': row['pid'], 'name': row['name'], 'cwd': cwd, 'cmd': row.get('cmd') or ''})
    return result


def proc_paths(proc):
    found = []
    if proc.get('cwd'):
        found.append(norm(proc['cwd']))
    text = (proc.get('cmd') or '').replace('\\', '/')
    for match in re.finditer(r'[A-Za-z]:/[^\s"\']*', text):
        found.append(norm(match.group(0)))
    return found


def uses_path(proc, folder):
    """True when the process's cwd or a path in its command line is the folder or inside it."""
    base = norm(folder)
    return any(p == base or p.startswith(base + '/') for p in proc_paths(proc))


def owners(procs, roots):
    """{root label: [proc]} using the longest matching checkout root. A process in the main checkout counts for main only outside .claude/worktrees."""
    by_label = {r.label: [] for r in roots}
    ordered = sorted(roots, key=lambda r: -len(norm(r.path)))
    for proc in procs:
        hit = set()
        for p in proc_paths(proc):
            for root in ordered:
                base = norm(root.path)
                if p == base or p.startswith(base + '/'):
                    hit.add(root.label)
                    break
        for label in hit:
            by_label[label].append(proc)
    return by_label


# ------------------------------------------------------------------------------------------------------------------ candidates and judgement

def candidates_of(root, scan):
    """Planned --clean items of one checkout: [{'root', 'rel', 'abs', 'size', 'files', 'latest'}]."""
    found = []
    for parts, (size, files, latest) in scan['keys'].items():
        if not parts:
            continue
        rel = rel_of(parts)
        for regex, worktree_only in CLEAN_PATTERNS:
            if regex.fullmatch(rel):
                if worktree_only and root.is_main:
                    break
                if not classify(rel)['clean']:
                    break
                n = len(parts)
                found.append({'root': root, 'rel': rel, 'abs': root.path.joinpath(*parts), 'size': size, 'files': files, 'latest': latest, 'parts': parts,
                              'complete': scan['complete'], 'errors': any(e[:n] == parts for e in scan['errors']),
                              'links': any(l[:n] == parts for l in scan['links']),
                              'has_protected': any(len(k) > n and k[:n] == parts and protected_rel(rel_of(k)) for k in scan['keys'])})
                break
    return sorted(found, key=lambda c: c['rel'])


def default_user_folders():
    folders = []
    appdata = os.environ.get('APPDATA')
    if appdata:
        folders.append(Path(appdata) / 'WitchMoira')
    folders.append(Path.home() / 'AppData' / 'Roaming' / 'WitchMoira')
    return folders


_TRACKED = {}


def git_tracked(root_path, rel):
    """True when git tracks the path or anything inside it. The tracked list is read once per checkout. A failing git counts as tracked."""
    key = str(root_path)
    if key not in _TRACKED:
        try:
            done = subprocess.run(['git', '-C', key, 'ls-files', '-z'], capture_output=True, timeout=60)
            if done.returncode != 0:
                raise OSError('git ls-files failed')
            files = done.stdout.decode('utf-8', 'replace').split(chr(0))
            names = set(files)
            for name in files:
                while '/' in name:
                    name = name.rsplit('/', 1)[0]
                    names.add(name)
            _TRACKED[key] = names
        except Exception:
            _TRACKED[key] = None
    names = _TRACKED[key]
    return names is None or rel.replace(chr(92), '/').strip('/') in names


def worktree_last_use(scan):
    """Newest mtime anywhere in the checkout except the .godot cache."""
    latest = 0.0
    for parts, (size, files, mtime) in scan['keys'].items():
        if len(parts) == 1 and parts[0] != '.godot' and mtime > latest:
            latest = mtime
    return latest


def judge(cand, ctx):
    """None when the candidate may be removed, otherwise the reason it is kept. Every guard of the task is here."""
    root, rel, path = cand['root'], cand['rel'], cand['abs']
    # 1. location and protected names
    try:
        resolved = Path(os.path.realpath(path))
    except OSError:
        return 'path cannot be resolved'
    if '..' in Path(rel).parts:
        return 'unsafe path'
    for folder in ctx['user_folders']:
        base = norm(folder)
        here = norm(resolved)
        if here == base or here.startswith(base + '/') or base.startswith(here + '/'):
            return 'user save folder'
    inside = [norm(r.path) for r in ctx['roots']]
    if not any(norm(resolved) == b or norm(resolved).startswith(b + '/') for b in inside):
        return 'outside the repository'
    if norm(resolved) != norm(path):
        return 'path goes through a link'
    if protected_rel(rel):
        return 'protected name'
    if cand['has_protected']:
        return 'contains a protected path'
    if not classify(rel)['clean']:
        return 'rule table does not allow removal'
    # 2. the scan must be trustworthy
    if not cand['complete']:
        return 'size count incomplete (time limit)'
    if cand['errors']:
        return 'part of it could not be read'
    if cand['links']:
        return 'contains a link'
    if os.name == 'nt' and is_reparse(path):
        return 'is a link'
    # 3. tracked files
    if ctx['tracked'](root.path, rel):
        return 'tracked by git'
    # 4. recent use
    limit = ctx['now'] - ctx['idle_hours'] * 3600
    if cand['latest'] > limit:
        return 'used in the last %d h' % ctx['idle_hours']
    # 5. live processes
    if ctx['procs'] is None:
        return 'process list unreadable'
    mine = ctx['owners'].get(root.label, [])
    if any(uses_path(p, path) for p in ctx['procs']):
        return 'a live process uses it'
    if root.is_main:
        if any(re.match(r'godot', p['name'] or '', re.I) for p in mine):
            return 'a Godot process runs in this checkout'
        if any(uses_path(p, root.path / '_local') for p in ctx['procs']):
            return 'a live process uses _local'
    else:
        if mine:
            return 'a live process runs in this worktree (%s)' % ', '.join('%s %d' % (p['name'], p['pid']) for p in mine[:3])
        if cand['rel'] == '.godot' and worktree_last_use(root.scan) > limit:
            return 'worktree edited in the last %d h' % ctx['idle_hours']
    return None


def stale_review(roots, now, days):
    """Top-level _local items a person has to decide on (rule says 'ask') that nobody touched for `days` days. Listed only, --apply never removes them."""
    found = []
    for root in roots:
        for parts, (size, files, latest) in root.scan['keys'].items():
            if len(parts) != 2 or parts[0] != '_local':
                continue
            rel = rel_of(parts)
            info = classify(rel)
            if info['deletable'] == 'ask' and not protected_rel(rel) and latest and (now - latest) >= days * 86400 and size > 0:
                found.append((size, root.label, rel, files, latest, info['kind']))
    return sorted(found, reverse=True)


def refresh(cand):
    """The candidate counted again right before removal (size, newest mtime, unreadable parts, links)."""
    again = scan_tree(cand['abs'], 0, time.monotonic() + 60)
    slot = again['keys'][()]
    try:
        own = os.lstat(long_path(cand['abs'])).st_mtime
    except OSError:
        own = time.time()
    return dict(cand, size=slot[0], files=slot[1], latest=max(slot[2], own), complete=again['complete'], errors=bool(again['errors']), links=bool(again['links']))


def is_reparse(path):
    try:
        return bool(os.lstat(path).st_file_attributes & REPARSE)
    except (OSError, AttributeError):
        return False


# ------------------------------------------------------------------------------------------------------------------ removal

def remove_tree(path):
    """Remove a folder tree without following links. Returns the list of (path, error) that failed (empty = all gone)."""
    failures = []
    top = long_path(path)
    if is_reparse(top) or os.path.islink(top):
        try:
            os.rmdir(top)
        except OSError as error:
            failures.append((str(path), str(error)))
        return failures
    stack, order = [top], []
    while stack:
        folder = stack.pop()
        order.append(folder)
        try:
            with os.scandir(folder) as it:
                for entry in it:
                    try:
                        if entry.is_dir(follow_symlinks=False) and not is_link(entry):
                            stack.append(entry.path)
                        else:
                            drop_file(entry.path, failures)
                    except OSError as error:
                        failures.append((entry.path, str(error)))
        except OSError as error:
            failures.append((folder, str(error)))
    for folder in reversed(order):
        try:
            os.rmdir(folder)
        except OSError as error:
            try:
                os.chmod(folder, stat.S_IWRITE)
                os.rmdir(folder)
            except OSError:
                failures.append((folder, str(error)))
    return failures


def drop_file(path, failures):
    try:
        os.unlink(path)
    except OSError:
        try:
            os.chmod(path, stat.S_IWRITE)
            os.unlink(path)
        except OSError as error:
            failures.append((path, str(error)))


# ------------------------------------------------------------------------------------------------------------------ output

def width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in 'WF' else 1 for ch in text)


def pad(text, size, right=False):
    gap = max(0, size - width(text))
    return (' ' * gap + text) if right else (text + ' ' * gap)


def fmt_size(num):
    if num >= 1 << 30:
        return '%.2f GB' % (num / (1 << 30))
    if num >= 1 << 20:
        return '%.0f MB' % (num / (1 << 20))
    if num >= 1 << 10:
        return '%.0f KB' % (num / (1 << 10))
    return '%d B' % num


def fmt_age(mtime, now):
    if not mtime:
        return '-'
    hours = (now - mtime) / 3600
    if hours < 1:
        return '%d분 전' % max(0, hours * 60)
    if hours < 48:
        return '%.0f시간 전' % hours
    return '%.0f일 전' % (hours / 24)


def table(headers, rows, rights=()):
    sizes = [max(width(str(r[i])) for r in [headers] + rows) for i in range(len(headers))]
    lines = ['  '.join(pad(str(h), sizes[i], i in rights) for i, h in enumerate(headers))]
    lines.append('  '.join('-' * s for s in sizes))
    for r in rows:
        lines.append('  '.join(pad(str(c), sizes[i], i in rights) for i, c in enumerate(r)))
    return '\n'.join(lines)


def size_rows(roots, depth, min_bytes, now):
    rows = []
    for root in roots:
        scan = root.scan
        for parts, (size, files, latest) in sorted(scan['keys'].items()):
            if not parts or len(parts) > depth or size < min_bytes:
                continue
            rel = rel_of(parts)
            info = classify(rel)
            label = root.label if not root.is_main else 'main'
            rows.append([('  ' * (len(parts) - 1)) + rel_of(parts[-1:]) + ('  [' + label + ']' if len(parts) == 1 else ''), fmt_size(size), files,
                         fmt_age(latest, now), KIND_KO.get(info['kind'], info['kind']), DELETABLE_KO[info['deletable']]])
    return rows


def link_lines(roots):
    """Links near the top of a checkout (for example _local -> another drive). They are not followed, so their target is not in the totals."""
    lines = []
    for root in roots:
        for parts in root.scan['links']:
            if len(parts) <= 2:
                try:
                    target = os.path.realpath(root.path.joinpath(*parts))
                except OSError:
                    target = '?'
                lines.append('링크(따라가지 않음, 합계에 없음): [%s] %s -> %s' % (root.label, rel_of(parts), target))
    return lines


def partial_note(roots):
    bad = [r.label for r in roots if r.scan and not r.scan['complete']]
    return 'PARTIAL: time limit hit in %s (totals are lower bounds, --apply refuses)' % ', '.join(bad) if bad else ''


def worktree_rows(roots, procs, now, registered):
    by_owner = owners(procs, roots) if procs is not None else {}
    rows = []
    for root in roots:
        if root.is_main:
            continue
        keys = root.scan['keys']
        size, files, latest = keys[()]
        godot = keys.get(('.godot',), [0, 0, 0])[0]
        last = worktree_last_use(root.scan)
        mine = by_owner.get(root.label, [])
        if procs is None:
            verdict = '프로세스 목록 읽기 실패'
        elif mine:
            verdict = '사용 중: ' + ', '.join('%s %d' % (re.sub(r'\.exe$', '', p['name'], flags=re.I), p['pid']) for p in mine[:4])
        elif files == 0:
            verdict = '빈 껍데기(파일 없음)'
        else:
            verdict = '프로세스 없음'
        reg = ('예' if registered.get(norm(root.path)) else '아니오') if registered is not None else '?'
        rows.append([root.label, fmt_size(size), files, fmt_size(godot), fmt_age(last, now), reg, verdict + ('' if root.scan['complete'] else ' (PARTIAL)')])
    return rows


def git_registered(main):
    try:
        done = subprocess.run(['git', '-C', str(main), 'worktree', 'list', '--porcelain'], capture_output=True, timeout=30)
        text = done.stdout.decode('utf-8', 'replace')
    except Exception:
        return None
    return {norm(line[9:].strip()): True for line in text.splitlines() if line.startswith('worktree ')}


def sample_hash(path, size):
    digest = hashlib.sha1()
    try:
        with open(long_path(path), 'rb') as handle:
            digest.update(handle.read(1 << 20))
            if size > 2 << 20:
                handle.seek(-(1 << 20), os.SEEK_END)
                digest.update(handle.read(1 << 20))
    except OSError:
        return None
    return digest.hexdigest()


def duplicate_groups(roots):
    """Groups of large files with the same size and the same sampled hash (first + last MB). Candidates for a person, never removed here."""
    by_size = {}
    for root in roots:
        for size, path, mtime, parts in root.scan['big']:
            by_size.setdefault(size, []).append((root, path, mtime, parts))
    groups = []
    for size, items in by_size.items():
        if len(items) < 2:
            continue
        by_hash = {}
        for item in items:
            digest = sample_hash(item[1], size)
            if digest:
                by_hash.setdefault(digest, []).append(item)
        groups += [(size, g) for g in by_hash.values() if len(g) > 1]
    return sorted(groups, key=lambda g: -g[0] * (len(g[1]) - 1))


# ------------------------------------------------------------------------------------------------------------------ main

def main(argv=None, processes=-1, tracked=None, now=None, user_folders=None, out=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--root', default=None, help='main checkout (default: this repository\'s main checkout)')
    parser.add_argument('--depth', type=int, default=4, help='folder depth to list (1-%d)' % MAX_SCAN_DEPTH)
    parser.add_argument('--min-mb', type=float, default=100, help='hide folders smaller than this')
    parser.add_argument('--time-limit', type=float, default=90, help='seconds for the whole count')
    parser.add_argument('--worktrees', action='store_true', help='one row per worktree with live processes and last use')
    parser.add_argument('--dups', action='store_true', help='list large files that look identical')
    parser.add_argument('--dup-min-mb', type=float, default=20)
    parser.add_argument('--clean', action='store_true', help='plan the removal of regenerable caches (list only)')
    parser.add_argument('--apply', action='store_true', help='with --clean: remove the planned items')
    parser.add_argument('--idle-hours', type=float, default=MIN_IDLE_HOURS, help='not used for this long (at least %d)' % MIN_IDLE_HOURS)
    parser.add_argument('--stale-days', type=float, default=3, help='with --clean: also list unclassified/ask items untouched this long (list only)')
    parser.add_argument('--json', default=None, help='also write the clean plan / tables to this file')
    args = parser.parse_args(argv)
    if args.apply and not args.clean:
        print('DISK bad arguments: --apply needs --clean', file=sys.stderr)
        return 2
    if not 1 <= args.depth <= MAX_SCAN_DEPTH or args.time_limit <= 0 or args.min_mb < 0:
        print('DISK bad arguments', file=sys.stderr)
        return 2
    idle = max(MIN_IDLE_HOURS, args.idle_hours)
    write = (lambda text='': print(text, file=out)) if out is not None else print
    clock = now if now is not None else time.time()
    main_path = Path(args.root) if args.root else godot_ps.main_root()
    roots = find_roots(main_path)
    deadline = time.monotonic() + args.time_limit
    for index, root in enumerate(roots):
        # each checkout gets an equal share of what is left, so one huge tree cannot starve the others
        share = 0.6 if index == 0 and len(roots) > 1 else 1.0 / (len(roots) - index)  # main holds most of _local
        stop = time.monotonic() + max(0.5, (deadline - time.monotonic()) * share)
        # the main checkout holds .claude/worktrees, which are counted as their own roots
        root.scan = scan_tree(root.path, MAX_SCAN_DEPTH, stop, big_min=int(args.dup_min_mb * (1 << 20)) if args.dups else 0,
                              skip_top=('.claude',) if root.is_main else ())
    procs = list_processes(main_path) if processes == -1 else processes
    ctx = {'now': clock, 'idle_hours': idle, 'procs': procs, 'roots': roots, 'owners': owners(procs, roots) if procs is not None else {},
           'tracked': tracked or git_tracked, 'user_folders': user_folders if user_folders is not None else default_user_folders()}
    note = partial_note(roots)
    stamp = datetime.datetime.fromtimestamp(clock).strftime('%Y-%m-%d %H:%M')

    if not args.clean:
        write('DISK REPORT %s  root=%s  roots=%d  depth=%d  min=%g MB  (sizes are file sizes)' % (stamp, main_path, len(roots), args.depth, args.min_mb))
        if args.worktrees:
            registered = git_registered(main_path)
            write(table(['worktree', '크기', '파일 수', '.godot', '마지막 수정', 'git 등록', '판정'],
                        worktree_rows(roots, procs, clock, registered), rights=(1, 2, 3)))
        else:
            write(table(['폴더', '크기', '파일 수', '마지막 수정', '종류', '지워도 되는가'], size_rows(roots, args.depth, int(args.min_mb * (1 << 20)), clock), rights=(1, 2)))
        total = sum(r.scan['keys'][()][0] for r in roots)
        write('합계 %s (main + worktree %d)' % (fmt_size(total), len(roots) - 1))
        for line in link_lines(roots):
            write(line)
        if args.dups:
            groups = duplicate_groups(roots)
            write('중복으로 보이는 큰 파일(앞·뒤 1MB 해시, 목록만): %d묶음' % len(groups))
            for size, items in groups[:30]:
                write('  %s x%d' % (fmt_size(size), len(items)))
                for root, path, mtime, parts in items:
                    write('    [%s] %s  (%s)' % (root.label, rel_of(parts), fmt_age(mtime, clock)))
        if note:
            write(note)
        return 0

    plan = []
    for root in roots:
        for cand in candidates_of(root, root.scan):
            reason = judge(cand, ctx)
            plan.append((cand, reason))
    ok = [c for c, reason in plan if reason is None]
    kept = [(c, reason) for c, reason in plan if reason is not None]
    write('DISK CLEAN %s  idle>=%d h  %s' % (stamp, idle, 'APPLY' if args.apply else 'PLAN ONLY (nothing is removed; add --apply)'))
    write('지울 것(재생성 가능, 규칙 통과):')
    write(table(['위치', '경로', '크기', '파일 수', '마지막 수정'],
                [[c['root'].label, c['rel'], fmt_size(c['size']), c['files'], fmt_age(c['latest'], clock)] for c in ok], rights=(2, 3)))
    write('되찾을 크기: %s (%d개)' % (fmt_size(sum(c['size'] for c in ok)), len(ok)))
    write('남기는 후보와 이유:')
    reasons = {}
    for c, reason in kept:
        reasons.setdefault(reason.split(' (')[0], []).append(c)
    for reason, items in sorted(reasons.items(), key=lambda kv: -sum(c['size'] for c in kv[1])):
        write('  %-44s %3d개 %10s  e.g. %s/%s' % (reason, len(items), fmt_size(sum(c['size'] for c in items)), items[0]['root'].label, items[0]['rel']))
    review = stale_review(roots, clock, args.stale_days)
    write('사람이 정할 오래된 것(%g일 이상 손대지 않음, 목록만 — --apply는 지우지 않음): %d개, 합계 %s' % (args.stale_days, len(review), fmt_size(sum(r[0] for r in review))))
    for size, label, rel, files, latest, kind in review[:25]:
        write('  %10s  %-26s %-28s %6d files  %s  [%s]' % (fmt_size(size), label[:26], rel, files, fmt_age(latest, clock), KIND_KO.get(kind, kind)))
    if note:
        write(note)
    code = 0
    result = {'time': stamp, 'apply': args.apply, 'planned': [{'root': c['root'].label, 'rel': c['rel'], 'bytes': c['size']} for c in ok],
              'kept': [{'root': c['root'].label, 'rel': c['rel'], 'bytes': c['size'], 'reason': r} for c, r in kept],
              'review': [{'root': r[1], 'rel': r[2], 'bytes': r[0]} for r in review], 'removed': [], 'failed': []}
    if args.apply:
        # re-check each item right before removing it: fresh process list and a fresh count of that folder
        fresh = list_processes(main_path) if processes == -1 else processes
        ctx['procs'] = fresh
        ctx['owners'] = owners(fresh, roots) if fresh is not None else {}
        ctx['now'] = time.time() if now is None else clock
        freed = 0
        for cand in ok:
            check = refresh(cand)
            reason = judge(check, ctx)
            if reason is not None:
                write('SKIP %s/%s: %s' % (cand['root'].label, cand['rel'], reason))
                result['kept'].append({'root': cand['root'].label, 'rel': cand['rel'], 'bytes': cand['size'], 'reason': reason + ' (re-check)'})
                continue
            failures = remove_tree(cand['abs'])
            if failures:
                code = 3
                write('FAILED %s/%s: %d items, first: %s' % (cand['root'].label, cand['rel'], len(failures), failures[0][1][:120]))
                result['failed'].append({'root': cand['root'].label, 'rel': cand['rel'], 'first_error': failures[0][1]})
            else:
                freed += cand['size']
                write('REMOVED %s/%s  %s' % (cand['root'].label, cand['rel'], fmt_size(cand['size'])))
                result['removed'].append({'root': cand['root'].label, 'rel': cand['rel'], 'bytes': cand['size']})
        write('DISK freed %s in %d items, failed %d' % (fmt_size(freed), len(result['removed']), len(result['failed'])))
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding='utf-8')
    return code


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    sys.exit(main())
