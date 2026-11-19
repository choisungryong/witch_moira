#!/usr/bin/env python3
"""disk_report.py und isolated_env.py 자체 검사. 가짜 폴더 트리(임시 폴더)와 가짜 프로세스 목록만 쓴다. 진짜 삭제는 임시 폴더 안에서만 일어난다.

  python tools/dev/test_disk_report.py
"""
import io
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import disk_report as D  # noqa: E402
import isolated_env as E  # noqa: E402

DAY = 86400


def put(path, data=b'x' * 1000, age_days=5):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    stamp = time.time() - age_days * DAY
    os.utime(path, (stamp, stamp))
    return path


def age_all(root, age_days=5):
    stamp = time.time() - age_days * DAY
    for dirpath, dirs, files in os.walk(root, topdown=False):
        for name in files + dirs:
            try:
                os.utime(os.path.join(dirpath, name), (stamp, stamp))
            except OSError:
                pass
        os.utime(dirpath, (stamp, stamp))


def junction(link, target):
    done = subprocess.run(['cmd', '/c', 'mklink', '/J', str(link), str(target)], capture_output=True)
    return done.returncode == 0


def proc(pid, name, cwd='', cmd=''):
    return {'pid': pid, 'name': name, 'cwd': cwd, 'cmd': cmd}


def run(args, root, processes=None, tracked=None, user_folders=None):
    buffer = io.StringIO()
    code = D.main(['--root', str(root), '--time-limit', '30'] + args, processes=[] if processes is None else processes,
                  tracked=tracked or (lambda r, rel: False), now=time.time(), user_folders=user_folders if user_folders is not None else [], out=buffer)
    return code, buffer.getvalue()


class Tree(unittest.TestCase):
    """A fake checkout:  main/ with _local content, and worktrees w-old, w-live, w-fresh."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.main = Path(self.tmp.name) / 'main'
        m = self.main
        # main: regenerable caches, protected items, things a person decides
        put(m / '_local/appdata/dev/WitchMoira/shader_cache/shader.bin', b'x' * 5000)
        put(m / '_local/appdata/dev/WitchMoira/logs/godot.log', b'x' * 300)
        put(m / '_local/appdata/dev/WitchMoira/profile.json', b'{"user":1}')
        put(m / '_local/appdata/dev/Godot/editor_settings.tres')
        put(m / '_local/run-all-fixtures/20261116/fixture.json', b'x' * 2000)
        put(m / '_local/run-all-fixtures/tracked1/f.json', b'x' * 100)
        put(m / '_local/ref/benchmark.mp4', b'x' * 9000)
        put(m / '_local/HANDOVER-20261118.ko.md')
        put(m / '_local/sfx/recheck-20261120/listen.mp4', b'x' * 7000)
        put(m / '_local/shots/a/1.png', b'x' * 4000)
        put(m / '_local/.gdignore', b'')
        put(m / 'chapter1/core/core.gd')
        put(m / '.godot/imported/x.bin', b'x' * 6000)
        # worktrees
        for name in ('w-old', 'w-live', 'w-fresh'):
            put(m / '.claude/worktrees' / name / '.godot/imported/a.bin', b'x' * 8000)
            put(m / '.claude/worktrees' / name / '_local/appdata/qa/WitchMoira/shader_cache/s.bin', b'x' * 3000)
            put(m / '.claude/worktrees' / name / 'chapter1/x.gd')
        put(m / '.claude/worktrees/w-fresh/chapter1/edited.gd', age_days=0)   # edited just now: .godot must stay
        age_all(m)
        # (age_all also aged the w-fresh edit: put it back to fresh)
        fresh = m / '.claude/worktrees/w-fresh/chapter1/edited.gd'
        now = time.time()
        os.utime(fresh, (now, now))
        self.live = [proc(7, 'python.exe', cwd=str(m / '.claude/worktrees/w-live'), cmd='python tools/dev/run_all.py')]

    def tearDown(self):
        self.tmp.cleanup()

    def exists(self, rel):
        return (self.main / rel).exists()


class Rules(unittest.TestCase):
    def test_classification(self):
        expect = {
            '_local/HANDOVER-20261118.ko.md': ('no', False),
            '_local/sfx/recheck-20261120': ('no', False),
            '_local/sfx/recheck-20261120/a.mp4': ('no', False),
            '_local/ref': ('no', False),
            '_local/ref/x.mp4': ('no', False),
            '_local/appdata/dev/WitchMoira/shader_cache': ('yes', True),
            '_local/appdata/dev/WitchMoira/logs': ('yes', True),
            '_local/appdata/dev/WitchMoira': ('ask', False),
            '_local/appdata/dev/Godot': ('ask', False),
            '_local/run-all-fixtures/x': ('yes', True),
            '.godot': ('yes', True),
            '_local/shots/a': ('ask', False),
            '_local/builds2': ('ask', False),
            'chapter1/core': ('no', False),
            'docs': ('no', False),
        }
        for rel, (deletable, clean) in expect.items():
            info = D.classify(rel)
            self.assertEqual((info['deletable'], info['clean']), (deletable, clean), rel)

    def test_protected_names(self):
        for rel in ('_local/ref', '_local/ref/a', '_local/HANDOVER-1.md', '_local/sfx/recheck-1', '_local/sfx/recheck-1/a.mp4', '.git/config'):
            self.assertTrue(D.protected_rel(rel), rel)
        for rel in ('_local/appdata/dev/WitchMoira/shader_cache', '.godot', '_local/shots'):
            self.assertFalse(D.protected_rel(rel), rel)

    def test_only_cache_rules_are_clean(self):
        for pattern, kind, deletable, clean, note in D.RULES:
            if clean:
                self.assertEqual((kind, deletable), ('cache', 'yes'), pattern)


class Scan(Tree):
    def test_totals_and_depth(self):
        scan = D.scan_tree(self.main, 3, time.monotonic() + 30, skip_top=('.claude',))
        keys = scan['keys']
        self.assertTrue(scan['complete'])
        self.assertEqual(keys[('_local', 'ref')][:2], [9000, 1])
        self.assertEqual(keys[('_local',)][1], 11)
        self.assertNotIn(('.claude',), keys)
        self.assertNotIn(('_local', 'ref', 'x', 'y'), keys)          # deeper than max_depth: summed into its ancestor only
        self.assertEqual(keys[()][0], sum(v[0] for k, v in keys.items() if len(k) == 1))

    def test_deadline_marks_partial(self):
        scan = D.scan_tree(self.main, 3, time.monotonic() - 1)
        self.assertFalse(scan['complete'])

    @unittest.skipUnless(os.name == 'nt', 'junctions are Windows only')
    def test_link_not_followed(self):
        target = Path(self.tmp.name) / 'outside'
        put(target / 'big.bin', b'x' * 50000)
        if not junction(self.main / '_local/linked', target):
            self.skipTest('mklink /J not available')
        scan = D.scan_tree(self.main, 3, time.monotonic() + 30, skip_top=('.claude',))
        self.assertIn(('_local', 'linked'), scan['links'])
        self.assertNotIn(('_local', 'linked'), scan['keys'])
        self.assertLess(scan['keys'][('_local',)][0], 50000 + 30000)
        self.assertTrue((target / 'big.bin').exists())


class Plan(Tree):
    def test_plan_lists_but_removes_nothing(self):
        code, text = run(['--clean'], self.main)
        self.assertEqual(code, 0)
        self.assertIn('PLAN ONLY', text)
        self.assertIn('_local/appdata/dev/WitchMoira/shader_cache', text)
        for rel in ('_local/appdata/dev/WitchMoira/shader_cache/shader.bin', '.claude/worktrees/w-old/.godot/imported/a.bin', '_local/run-all-fixtures/20261116/fixture.json'):
            self.assertTrue(self.exists(rel), rel)

    def test_apply_needs_clean(self):
        self.assertEqual(run(['--apply'], self.main)[0], 2)

    def test_idle_hours_cannot_go_below_24(self):
        code, text = run(['--clean', '--idle-hours', '1'], self.main)
        self.assertIn('idle>=24 h', text)

    def test_apply_removes_only_regenerable_and_idle(self):
        code, text = run(['--clean', '--apply'], self.main, processes=self.live, tracked=lambda r, rel: rel.endswith('run-all-fixtures/tracked1'))
        self.assertEqual(code, 0, text)
        gone = ['_local/appdata/dev/WitchMoira/shader_cache', '_local/run-all-fixtures/20261116', '.claude/worktrees/w-old/.godot',
                '.claude/worktrees/w-old/_local/appdata/qa/WitchMoira/shader_cache', '.claude/worktrees/w-fresh/_local/appdata/qa/WitchMoira/shader_cache']
        for rel in gone:
            self.assertFalse(self.exists(rel), 'should be removed: ' + rel)
        kept = [
            '_local/appdata/dev/WitchMoira/profile.json',            # user-ish data next to the caches
            '_local/appdata/dev/Godot/editor_settings.tres',
            '_local/ref/benchmark.mp4', '_local/HANDOVER-20261118.ko.md', '_local/sfx/recheck-20261120/listen.mp4',
            '_local/shots/a/1.png', '_local/.gdignore', 'chapter1/core/core.gd',
            '.godot/imported/x.bin',                                  # main .godot is never planned (slow re-import)
            '_local/run-all-fixtures/tracked1/f.json',                # tracked by git (injected)
            '.claude/worktrees/w-live/.godot/imported/a.bin',         # live process in the worktree
            '.claude/worktrees/w-live/_local/appdata/qa/WitchMoira/shader_cache/s.bin',
            '.claude/worktrees/w-fresh/.godot/imported/a.bin',        # edited within 24 h
            '.claude/worktrees/w-old/chapter1/x.gd',
        ]
        for rel in kept:
            self.assertTrue(self.exists(rel), 'must survive: ' + rel)
        self.assertIn('REMOVED', text)

    def test_recent_use_is_kept(self):
        now = time.time()
        os.utime(self.main / '_local/appdata/dev/WitchMoira/shader_cache/shader.bin', (now - 3600, now - 3600))
        code, text = run(['--clean', '--apply'], self.main)
        self.assertTrue(self.exists('_local/appdata/dev/WitchMoira/shader_cache/shader.bin'))
        self.assertIn('used in the last 24 h', text)

    def test_godot_process_in_main_protects_main_caches(self):
        godot = [proc(9, 'Godot_v4.5.1-stable_win64.exe', cwd=str(self.main), cmd='Godot --path %s res://chapter1/ChapterOne.tscn' % self.main)]
        code, text = run(['--clean', '--apply'], self.main, processes=godot)
        self.assertTrue(self.exists('_local/appdata/dev/WitchMoira/shader_cache/shader.bin'))
        self.assertTrue(self.exists('_local/run-all-fixtures/20261116/fixture.json'))
        self.assertFalse(self.exists('.claude/worktrees/w-old/.godot'))   # other checkouts are not protected by it
        self.assertIn('Godot process runs in this checkout', text)

    def test_process_inside_the_candidate_folder_protects_it(self):
        shell = [proc(5, 'bash.exe', cwd=str(self.main / '_local/run-all-fixtures/20261116'))]
        run(['--clean', '--apply'], self.main, processes=shell)
        self.assertTrue(self.exists('_local/run-all-fixtures/20261116/fixture.json'))

    def test_unreadable_process_list_removes_nothing(self):
        buffer = io.StringIO()
        code = D.main(['--root', str(self.main), '--time-limit', '30', '--clean', '--apply'], processes=None, tracked=lambda r, rel: False,
                      now=time.time(), user_folders=[], out=buffer)
        self.assertTrue(self.exists('_local/appdata/dev/WitchMoira/shader_cache/shader.bin'))
        self.assertTrue(self.exists('.claude/worktrees/w-old/.godot/imported/a.bin'))
        self.assertIn('process list unreadable', buffer.getvalue())

    def test_user_save_folder_is_never_removed(self):
        user = self.main / '_local/appdata/dev/WitchMoira'          # pretend this is %APPDATA%\WitchMoira
        run(['--clean', '--apply'], self.main, user_folders=[user])
        self.assertTrue(self.exists('_local/appdata/dev/WitchMoira/shader_cache/shader.bin'))
        self.assertTrue(self.exists('_local/appdata/dev/WitchMoira/profile.json'))

    def test_judge_guards_directly(self):
        scan = D.scan_tree(self.main, D.MAX_SCAN_DEPTH, time.monotonic() + 30, skip_top=('.claude',))
        root = D.Root(self.main, 'main', True)
        root.scan = scan
        ctx = {'now': time.time(), 'idle_hours': 24, 'procs': [], 'roots': [root], 'owners': {'main': []}, 'tracked': lambda r, rel: False, 'user_folders': []}
        good = [c for c in D.candidates_of(root, scan) if c['rel'].endswith('WitchMoira/shader_cache')][0]
        self.assertIsNone(D.judge(good, ctx))
        incomplete = dict(good, complete=False)
        self.assertIn('incomplete', D.judge(incomplete, ctx))
        self.assertIn('could not be read', D.judge(dict(good, errors=True), ctx))
        self.assertIn('link', D.judge(dict(good, links=True), ctx))
        self.assertIn('protected', D.judge(dict(good, has_protected=True), ctx))
        self.assertIn('rule table', D.judge(dict(good, rel='_local/shots/a', parts=('_local', 'shots', 'a')), ctx))
        self.assertIn('protected name', D.judge(dict(good, rel='_local/ref', parts=('_local', 'ref'), abs=self.main / '_local/ref'), ctx))
        outside = Path(self.tmp.name) / 'elsewhere'
        self.assertIn('outside the repository', D.judge(dict(good, abs=outside), ctx))
        self.assertIn('tracked', D.judge(good, dict(ctx, tracked=lambda r, rel: True)))
        self.assertIn('unreadable', D.judge(good, dict(ctx, procs=None)))
        # a file touched after planning is seen by the re-count made just before removal
        put(Path(good['abs']) / 'late.bin', age_days=0)
        self.assertIn('used in the last', D.judge(D.refresh(good), ctx))

    def test_candidates_never_include_main_godot_or_protected(self):
        scan = D.scan_tree(self.main, D.MAX_SCAN_DEPTH, time.monotonic() + 30, skip_top=('.claude',))
        root = D.Root(self.main, 'main', True)
        rels = [c['rel'] for c in D.candidates_of(root, scan)]
        self.assertNotIn('.godot', rels)
        for rel in rels:
            self.assertFalse(D.protected_rel(rel), rel)
            self.assertTrue(D.classify(rel)['clean'], rel)


class Report(Tree):
    def test_size_table_and_worktrees(self):
        code, text = run(['--min-mb', '0', '--depth', '3'], self.main)
        self.assertEqual(code, 0)
        self.assertIn('아니오(보존)', text)        # ref
        self.assertIn('예(재생성)', text)          # caches
        code, text = run(['--worktrees'], self.main, processes=self.live)
        self.assertIn('w-live', text)
        self.assertIn('사용 중', text)
        self.assertIn('프로세스 없음', text)

    def test_duplicates_listed_not_removed(self):
        data = b'y' * 3000
        put(self.main / '_local/shots/dup1.bin', data)
        put(self.main / '_local/shots/dup2.bin', data)
        code, text = run(['--dups', '--dup-min-mb', '0.001'], self.main)
        self.assertIn('_local/shots/dup1.bin', text)
        self.assertIn('_local/shots/dup2.bin', text)
        self.assertTrue(self.exists('_local/shots/dup1.bin') and self.exists('_local/shots/dup2.bin'))


class RemoveTree(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt', 'junctions are Windows only')
    def test_link_inside_is_not_followed(self):
        with tempfile.TemporaryDirectory() as tmp:
            keep = put(Path(tmp) / 'keep/precious.bin')
            victim = Path(tmp) / 'victim'
            put(victim / 'a/b.bin')
            if not junction(victim / 'link', keep.parent):
                self.skipTest('mklink /J not available')
            failures = D.remove_tree(victim)
            self.assertFalse(victim.exists(), failures)
            self.assertTrue(keep.exists(), 'the link target must survive')

    def test_read_only_file_is_removed(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'cache'
            ro = put(target / 'ro.bin')
            os.chmod(ro, 0o444)
            self.assertEqual(D.remove_tree(target), [])
            self.assertFalse(target.exists())


class IsolatedEnv(unittest.TestCase):
    def test_default_is_the_repository(self):
        self.assertEqual(E.appdata_root({}), E.ROOT / '_local' / 'appdata')
        self.assertEqual(E.appdata_root({'MOIRA_LOCAL_ROOT': '  '}), E.ROOT / '_local' / 'appdata')

    def test_override_keeps_the_local_appdata_tail(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = E.appdata_root({'MOIRA_LOCAL_ROOT': tmp})
            self.assertEqual(root, Path(tmp) / '_local' / 'appdata')
            self.assertIn('/_local/appdata/', str(root / 'x').replace('\\', '/') + '/')   # the profile checks in chapter1/tests need this

    def test_rejects_relative_and_user_folder(self):
        with self.assertRaises(ValueError):
            E.appdata_root({'MOIRA_LOCAL_ROOT': 'relative/path'})
        user = Path.home() / 'AppData' / 'Roaming' / 'WitchMoira' / 'x'
        with self.assertRaises(ValueError):
            E.appdata_root({'MOIRA_LOCAL_ROOT': str(user)})
        with self.assertRaises(ValueError):
            E.appdata_root({'MOIRA_LOCAL_ROOT': str(Path('C:/x/WitchMoira/y')), 'APPDATA': 'C:/x'})

    def test_isolated_env_uses_the_override(self):
        old = os.environ.get('MOIRA_LOCAL_ROOT')
        with tempfile.TemporaryDirectory() as tmp:
            try:
                os.environ['MOIRA_LOCAL_ROOT'] = tmp
                env = E.isolated_env('unit test')
                self.assertEqual(Path(env['APPDATA']), Path(tmp) / '_local' / 'appdata' / 'unit_test')
                self.assertTrue(Path(env['APPDATA']).is_dir())
                os.environ.pop('MOIRA_LOCAL_ROOT')
                self.assertEqual(E.appdata_root(), E.ROOT / '_local' / 'appdata')
            finally:
                if old is None:
                    os.environ.pop('MOIRA_LOCAL_ROOT', None)
                else:
                    os.environ['MOIRA_LOCAL_ROOT'] = old


if __name__ == '__main__':
    unittest.main(verbosity=1)
