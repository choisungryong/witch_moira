#!/usr/bin/env python3
"""godot_guard.py und godot_ps.py 자체 검사. 진짜 Godot는 띄우지 않고, 가짜 프로세스 목록과 파이썬 대역 프로세스만 쓴다.

  python tools/dev/test_godot_ps.py
"""
import datetime
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import godot_guard as G  # noqa: E402
import godot_ps as P  # noqa: E402

NOW = datetime.datetime(2026, 11, 19, 12, 0, 0)
REPO = str(P.ROOT)
WORKTREE = str(P.main_root() / '.claude' / 'worktrees' / 'agent-x')


def godot(pid, ppid, cmd, minutes, name='Godot_v4.5.1-stable_win64.exe', cwd=''):
    return {'pid': pid, 'ppid': ppid, 'name': name, 'started': NOW - datetime.timedelta(minutes=minutes), 'cmd': cmd, 'cwd': cwd}


def python_row(pid, cmd, name='python.exe'):
    return {'pid': pid, 'ppid': 1, 'name': name, 'started': NOW, 'cmd': cmd, 'cwd': ''}


def kill_log():
    log = []
    return log, log.append


class GuardArgs(unittest.TestCase):
    def test_default_limits(self):
        self.assertEqual(G.default_timeout(['--headless', '--script', 'x']), 2400)
        self.assertEqual(G.default_timeout(['--path', '.', '--', '--headless']), 1200)  # after "--" belongs to the game
        self.assertEqual(G.default_timeout(['--path', '.']), 1200)

    def test_split_timeout_arg_only_before_double_dash(self):
        args, value = G.split_timeout_arg(['--timeout-s=30', '--headless', '--', '--timeout-s=5'])
        self.assertEqual(args, ['--headless', '--', '--timeout-s=5'])
        self.assertEqual(value, '30')
        self.assertEqual(G.split_timeout_arg(['--headless'])[1], None)

    def test_resolve_order_cli_then_env_then_default(self):
        self.assertEqual(G.resolve_timeout(['--headless'], '12', {G.ENV_NAME: '99'}), 12.0)
        self.assertEqual(G.resolve_timeout(['--headless'], None, {G.ENV_NAME: '99'}), 99.0)
        self.assertEqual(G.resolve_timeout(['--headless'], None, {}), 2400.0)
        self.assertEqual(G.resolve_timeout(['--headless'], '0', {}), 0.0)
        with self.assertRaises(ValueError):
            G.resolve_timeout([], 'abc', {})
        with self.assertRaises(ValueError):
            G.resolve_timeout([], '-1', {})


class GuardKill(unittest.TestCase):
    def test_tree_is_ended_on_timeout(self):
        """A parent that starts a child and waits: after the limit both must be gone, exit code 124."""
        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder) / 'child.pid'
            code = ("import subprocess,sys,time,pathlib\n"
                    "c=subprocess.Popen([sys.executable,'-c','import time;time.sleep(120)'])\n"
                    "pathlib.Path(sys.argv[1]).write_text(str(c.pid))\n"
                    "time.sleep(120)\n")
            started = time.time()
            exit_code, _, timed_out = G.run_guarded([sys.executable, '-c', code, str(marker)], 4)
            self.assertTrue(timed_out)
            self.assertEqual(exit_code, G.TIMEOUT_EXIT)
            self.assertLess(time.time() - started, 60)
            child = int(marker.read_text())
            time.sleep(1)
            self.assertFalse(self.alive(child), 'the child process survived the tree kill')

    def test_normal_exit_code_passes_through(self):
        exit_code, out, timed_out = G.run_guarded([sys.executable, '-c', 'import sys;print("hi");sys.exit(7)'], 30, capture=True)
        self.assertEqual((exit_code, timed_out), (7, False))
        self.assertIn(b'hi', out)

    @staticmethod
    def alive(pid):
        if os.name == 'nt':
            out = subprocess.run(['tasklist', '/FI', 'PID eq %d' % pid, '/NH'], capture_output=True).stdout.decode('utf-8', 'replace')
            return str(pid) in out
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False


class PsTable(unittest.TestCase):
    ROOTS = {P.norm(REPO), P.norm(P.main_root()), P.norm(P.main_root() / '.claude' / 'worktrees')}

    def table(self, rows):
        return P.build_table(rows, NOW, self.ROOTS)

    def test_isolated_headless_script_run_is_a_tool_target_when_old(self):
        cmd = '"G.exe" --headless --fixed-fps 60 --path "%s" --script res://chapter1/tests/hud_dump.gd -- --until=1800 --dump=a.json --scene=b.json' % WORKTREE
        table = self.table([godot(10, 99, cmd, 300)])
        self.assertEqual(table[0]['kind'], 'tool')
        self.assertEqual(table[0]['mode'], 'headless')
        self.assertIn('--until=1800', table[0]['args'])
        self.assertEqual(len(P.stale_targets(table, 60)), 1)
        self.assertEqual(len(P.stale_targets(table, 400)), 0)

    def test_user_play_is_never_a_target(self):
        plain = '"G.exe" --path "%s" res://chapter1/ChapterOne.tscn -- --chapter1-start' % REPO
        trial = '"G.exe" --path "%s" res://chapter1/ChapterOne.tscn -- --chapter1-profile-off --chapter1-trial=spells,rhythm' % REPO
        table = self.table([godot(11, 99, plain, 9999), godot(12, 99, trial, 9999)])
        self.assertEqual([t['kind'] for t in table], ['user play', 'user play'])
        self.assertEqual(P.stale_targets(table, 1), [])

    def test_automated_window_with_profile_off_is_a_target(self):
        cmd = '"G.exe" --path "%s" res://chapter1/ChapterOne.tscn -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus' % REPO
        table = self.table([godot(13, 99, cmd, 500)])
        self.assertEqual(table[0]['kind'], 'tool')

    def test_other_repository_and_unreadable_folder_are_shown_not_ended(self):
        other = '"G.exe" --headless --path "D:/other/game" --script res://x.gd'
        relative = '"G.exe" --headless --path . --script res://x.gd'
        table = self.table([godot(14, 99, other, 900), godot(15, 99, relative, 900)])
        self.assertEqual([t['kind'] for t in table], ['foreign', 'unclear'])
        self.assertEqual(P.stale_targets(table, 1), [])

    def test_relative_path_uses_the_working_folder(self):
        cmd = '"G.exe" --headless --path . --script res://x.gd'
        table = self.table([godot(16, 99, cmd, 900, cwd=WORKTREE)])
        self.assertEqual(table[0]['kind'], 'tool')

    def test_parent_that_is_not_a_dev_tool_blocks(self):
        cmd = '"G.exe" --headless --path "%s" --script res://x.gd' % REPO
        rows = [godot(20, 21, cmd, 900), python_row(21, 'python.exe somewhere/other_script.py'),
                godot(22, 23, cmd, 900), python_row(23, 'python.exe C:/x/tools/dev/godot.py --headless')]
        table = {t['pid']: t for t in self.table(rows)}
        self.assertEqual(table[20]['kind'], 'unclear')
        self.assertEqual(table[22]['kind'], 'tool')

    def test_console_parent_and_engine_child_are_one_kill(self):
        cmd = '"G.exe" --headless --path "%s" --script res://x.gd' % REPO
        rows = [godot(30, 99, cmd, 900, name='Godot_console.exe'), godot(31, 30, cmd, 900)]
        targets = P.stale_targets(self.table(rows), 60)
        self.assertEqual([t['pid'] for t in targets], [30])

    def test_non_godot_processes_are_ignored(self):
        self.assertEqual(self.table([python_row(40, 'python.exe godot.py')]), [])


class PsMain(unittest.TestCase):
    def run_main(self, argv, rows):
        log, killer = kill_log()
        import io
        from contextlib import redirect_stdout
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = P.main(argv, processes=rows, killer=killer, now=NOW)
        return code, buffer.getvalue(), log

    def rows(self):
        old = '"G.exe" --headless --path "%s" --script res://x.gd' % REPO
        user = '"G.exe" --path "%s" res://chapter1/ChapterOne.tscn -- --chapter1-start' % REPO
        return [godot(50, 99, old, 300), godot(51, 99, old, 5), godot(52, 99, user, 300)]

    def test_listing_does_not_kill(self):
        code, text, log = self.run_main([], self.rows())
        self.assertEqual((code, log), (0, []))
        self.assertIn('user play', text)

    def test_stale_filter(self):
        _, text, _ = self.run_main(['--stale-min=60'], self.rows())
        self.assertIn('50 ', text)
        self.assertNotIn('\n51 ', text)

    def test_kill_stale_ends_only_old_tool_runs(self):
        code, text, log = self.run_main(['--kill-stale'], self.rows())
        self.assertEqual(log, [50])
        self.assertIn('ended=1', text)

    def test_dry_run_ends_nothing(self):
        _, text, log = self.run_main(['--kill-stale', '--dry-run'], self.rows())
        self.assertEqual(log, [])
        self.assertIn('WOULD END 50', text)


if __name__ == '__main__':
    unittest.main()
