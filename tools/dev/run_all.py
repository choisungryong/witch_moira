"""Single regression entry point for the current working tree.

    python tools/dev/run_all.py            every check
    python tools/dev/run_all.py --quick    skip the golden replay (about a minute)
    python tools/dev/run_all.py --only combat,golden

Exit code 0 only when every selected check passes. A Godot test that hits a
script error never quits on its own, so each check has a timeout and a timeout
is reported as a failure, not as a pass.
"""
from pathlib import Path
import argparse, datetime, json, os, re, subprocess, sys, time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_env import isolated_env

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))
# The profile test only accepts an isolated QA path below this evidence root.
FIXTURES = 'res://_local/run-all-fixtures/'


def godot_check(name, script, marker, extra=(), timeout=120, slow=False):
    return {'name': name, 'kind': 'godot', 'script': script, 'marker': marker, 'extra': list(extra), 'timeout': timeout, 'slow': slow}


def checks():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    return [
        godot_check('growth', 'res://chapter1/tests/test_growth.gd', 'CHAPTER1_GROWTH_RESULT'),
        godot_check('tree', 'res://chapter1/tests/test_skill_tree.gd', 'CHAPTER1_SKILL_TREE_RESULT'),
        godot_check('combat', 'res://chapter1/tests/test_combat_run.gd', 'CHAPTER1_COMBAT_RESULT'),
        godot_check('chapter', 'res://chapter1/tests/test_chapter_run.gd', 'CHAPTER_FULL_TEST'),
        godot_check('profile', 'res://chapter1/tests/test_chapter_profile.gd', 'CHAPTER_PROFILE', ['--fixture-dir=' + FIXTURES + stamp]),
        godot_check('loot', 'res://chapter1/tests/test_loot.gd', 'CHAPTER1_LOOT_RESULT'),
        godot_check('loc', 'res://chapter1/tests/test_loc.gd', 'CHAPTER1_LOC_RESULT'),
        godot_check('app-guard', 'res://chapter1/tests/test_profile_app_guard.gd', 'CHAPTER1_APP_GUARD_RESULT'),
        godot_check('profile-legacy', 'res://chapter1/tests/test_profile_legacy_fixtures.gd', 'CHAPTER1_PROFILE_LEGACY_RESULT', ['--work-dir=' + FIXTURES + 'legacy-' + stamp]),
        godot_check('profile-v4', 'res://chapter1/tests/test_profile_v4.gd', 'CHAPTER1_PROFILE_V4_RESULT', ['--work-dir=' + FIXTURES + 'v4-' + stamp]),
        godot_check('profile-v4-fixtures', 'res://chapter1/tests/test_profile_v4_fixtures.gd', 'CHAPTER1_PROFILE_V4_FIXTURES_RESULT', ['--work-dir=' + FIXTURES + 'v4fix-' + stamp]),
        godot_check('app-loadout', 'res://chapter1/tests/test_profile_app_loadout.gd', 'CHAPTER1_APP_LOADOUT_RESULT'),
        godot_check('golden', 'res://chapter1/tests/golden_core.gd', 'GOLDEN_RESULT', timeout=600, slow=True),
        godot_check('golden-textless', 'res://chapter1/tests/golden_core.gd', 'GOLDEN_RESULT', ['--textless'], timeout=600, slow=True),
        godot_check('core-text', 'res://chapter1/tests/test_core_text.gd', 'CHAPTER1_CORE_TEXT_RESULT', timeout=600, slow=True),
        godot_check('loot-sim', 'res://chapter1/tests/sim_loot.gd', 'LOOT_SIM', ['--runs=3000'], timeout=600, slow=True),
        {'name': 'manager', 'kind': 'python', 'timeout': 300, 'slow': False},
        {'name': 'i18n-scan', 'kind': 'i18n-scan', 'timeout': 60, 'slow': False},
        {'name': 'glyphs', 'kind': 'glyphs', 'timeout': 120, 'slow': False},
    ]


def run_godot(check):
    command = [str(GODOT), '--headless', '--path', str(ROOT), '--script', check['script']]
    if check['extra']:
        command += ['--'] + check['extra']
    try:
        done = subprocess.run(command, capture_output=True, timeout=check['timeout'], env=isolated_env('run_all'))
    except subprocess.TimeoutExpired as expired:
        text = (expired.stdout or b'').decode('utf-8', 'replace') + (expired.stderr or b'').decode('utf-8', 'replace')
        error = re.search(r'SCRIPT ERROR: (.+)', text)
        return False, 'timeout after %ds%s' % (check['timeout'], ' · ' + error.group(1).strip() if error else '')
    text = done.stdout.decode('utf-8', 'replace') + done.stderr.decode('utf-8', 'replace')
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
    return done.returncode == 0 and bool(found), detail or 'exit %d' % done.returncode


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
        return False, 'no result line'
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
    return done.returncode == 0, (lines[0] if done.returncode else '') + (' · ' if done.returncode else '') + (lines[-1] if lines else 'no output')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--quick', action='store_true', help='skip slow checks')
    parser.add_argument('--only', default='', help='comma separated check names')
    parser.add_argument('--json', default='', help='write the summary to this file')
    options = parser.parse_args()
    if not GODOT.is_file():
        raise SystemExit('Godot not found: ' + str(GODOT) + ' (set MOIRA_GODOT)')
    wanted = {name for name in options.only.split(',') if name}
    summary = []
    for check in checks():
        if wanted and check['name'] not in wanted:
            continue
        if options.quick and check['slow']:
            summary.append({'name': check['name'], 'status': 'skipped', 'detail': '--quick', 'seconds': 0})
            continue
        started = time.time()
        runner = {'godot': run_godot, 'python': run_manager, 'i18n-scan': run_i18n_scan, 'glyphs': run_glyphs}[check['kind']]
        passed, detail = runner(check)
        summary.append({'name': check['name'], 'status': 'pass' if passed else 'FAIL', 'detail': detail, 'seconds': round(time.time() - started, 1)})
        row = summary[-1]
        print('%-8s %-7s %6.1fs  %s' % (row['name'], row['status'], row['seconds'], row['detail']), flush=True)
    failed = [row['name'] for row in summary if row['status'] == 'FAIL']
    print('RUN_ALL ' + json.dumps({'passed': sum(row['status'] == 'pass' for row in summary), 'failed': failed, 'skipped': [row['name'] for row in summary if row['status'] == 'skipped']}), flush=True)
    if options.json:
        Path(options.json).write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
