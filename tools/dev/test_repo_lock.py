#!/usr/bin/env python3
"""repo_lock.py(좌석과 임포트 잠금), godot_guard.run_seated, godot.py의 용도별 APPDATA 이름 자체 검사.

진짜 Godot는 띄우지 않는다. 임시 폴더와, 이 검사가 직접 띄웠다 끝내는 파이썬 대역 프로세스만 쓴다(다른 프로세스는 건드리지 않는다).

  python tools/dev/test_repo_lock.py
"""
import contextlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import godot  # noqa: E402
import godot_guard as G  # noqa: E402
import repo_lock as L  # noqa: E402


@contextlib.contextmanager
def sleeper():
    """A live stand-in process (a holder that is still running)."""
    proc = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'])
    try:
        yield proc
    finally:
        proc.kill()
        proc.wait()


def dead_pid():
    proc = subprocess.Popen([sys.executable, '-c', 'pass'])
    proc.wait()
    return proc.pid


@contextlib.contextmanager
def env(**values):
    old = {k: os.environ.get(k) for k in values}
    os.environ.update({k: str(v) for k, v in values.items()})
    try:
        yield
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


class ProcessTests(unittest.TestCase):
    def test_pid_alive(self):
        self.assertTrue(L.pid_alive(os.getpid()))
        self.assertFalse(L.pid_alive(0))
        self.assertFalse(L.pid_alive('x'))
        with sleeper() as proc:
            self.assertTrue(L.pid_alive(proc.pid))
        self.assertFalse(L.pid_alive(dead_pid()))

    def test_seat_count_setting(self):
        self.assertEqual(L.seat_count({}), 6)
        self.assertEqual(L.seat_count({'MOIRA_GODOT_SLOTS': '3'}), 3)
        self.assertEqual(L.seat_count({'MOIRA_GODOT_SLOTS': '0'}), 6)
        self.assertEqual(L.seat_count({'MOIRA_GODOT_SLOTS': 'many'}), 6)

    def test_main_root_of_a_work_tree(self):
        self.assertEqual(L.main_root(Path('C:/x/repo/.claude/worktrees/agent-1')), Path('C:/x/repo').resolve())
        self.assertEqual(L.main_root(Path('C:/x/repo')), Path('C:/x/repo').resolve())


class DeadLockTests(unittest.TestCase):
    def test_missing_file_is_free_not_dead(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse(L.is_dead(Path(d) / 'nothing'))

    def test_dead_holder_is_dead_and_live_holder_is_not(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'a'
            path.write_text(json.dumps({'pid': dead_pid(), 'time': time.time()}), encoding='utf-8')
            self.assertTrue(L.is_dead(path))
            with sleeper() as proc:
                path.write_text(json.dumps({'pid': proc.pid, 'time': time.time()}), encoding='utf-8')
                self.assertFalse(L.is_dead(path))
                self.assertFalse(L.remove_if_dead(path))
                self.assertTrue(path.exists())

    def test_old_lock_of_a_live_pid_is_dead(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'a'
            path.write_text(json.dumps({'pid': os.getpid(), 'time': time.time() - L.MAX_AGE_S - 5}), encoding='utf-8')
            self.assertTrue(L.is_dead(path))

    def test_half_written_file_is_dead_only_when_old(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'a'
            path.write_text('', encoding='utf-8')
            self.assertFalse(L.is_dead(path))
            old = time.time() - 60
            os.utime(path, (old, old))
            self.assertTrue(L.is_dead(path))
            self.assertTrue(L.remove_if_dead(path))
            self.assertFalse(path.exists())

    def test_try_create_is_exclusive(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'sub' / 'a'
            self.assertTrue(L.try_create(path, 'one'))
            self.assertFalse(L.try_create(path, 'two'))
            self.assertEqual(L.read_lock(path)['label'], 'one')
            self.assertEqual(L.read_lock(path)['pid'], os.getpid())


class SeatTests(unittest.TestCase):
    def test_third_taker_waits_then_times_out_with_one_line(self):
        with tempfile.TemporaryDirectory() as d:
            lines = []
            with L.seat('a', d, 2, 5, out=lines.append), L.seat('b', d, 2, 5, out=lines.append):
                self.assertEqual(len(list(Path(d).glob('godot-slot-*'))), 2)
                with self.assertRaises(L.LockTimeout) as caught:
                    with L.seat('c', d, 2, 0.6, out=lines.append):
                        self.fail('no seat should have been free')
                self.assertTrue(str(caught.exception).startswith('GODOT_SLOT'))
            self.assertEqual(len(lines), 1)  # one line, not one per poll
            self.assertTrue(lines[0].startswith('GODOT_SLOT waiting'))
            self.assertEqual(list(Path(d).glob('godot-slot-*')), [])  # released

    def test_a_waiting_taker_gets_the_seat_when_it_is_freed(self):
        with tempfile.TemporaryDirectory() as d:
            lines, got = [], []
            holder = L.seat('a', d, 1, 5, out=lines.append)
            holder.__enter__()

            def taker():
                with L.seat('b', d, 1, 10, out=lines.append):
                    got.append(time.time())

            thread = threading.Thread(target=taker)
            thread.start()
            time.sleep(1.0)
            self.assertEqual(got, [])
            freed = time.time()
            holder.__exit__(None, None, None)
            thread.join(10)
            self.assertEqual(len(got), 1)
            self.assertGreaterEqual(got[0], freed)

    def test_seat_of_a_dead_process_is_taken_over(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'godot-slot-1').write_text(json.dumps({'pid': dead_pid(), 'time': time.time()}), encoding='utf-8')
            lines = []
            with L.seat('a', d, 1, 2, out=lines.append):
                self.assertEqual(L.read_lock(Path(d) / 'godot-slot-1')['label'], 'a')
            self.assertEqual(lines, [])  # it did not wait

    def test_seat_of_a_live_process_is_respected(self):
        with tempfile.TemporaryDirectory() as d:
            with sleeper() as proc:
                (Path(d) / 'godot-slot-1').write_text(json.dumps({'pid': proc.pid, 'time': time.time()}), encoding='utf-8')
                with self.assertRaises(L.LockTimeout):
                    with L.seat('a', d, 1, 0.5, out=lambda text: None):
                        pass
                self.assertTrue((Path(d) / 'godot-slot-1').exists())

    def test_seats_beyond_the_count_are_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'godot-slot-5').write_text(json.dumps({'pid': os.getpid(), 'time': time.time()}), encoding='utf-8')
            with L.seat('a', d, 2, 1, out=lambda text: None) as path:
                self.assertIn(path.name, ('godot-slot-1', 'godot-slot-2'))


class ImportLockTests(unittest.TestCase):
    def test_run_waits_while_the_import_lock_is_held(self):
        with tempfile.TemporaryDirectory() as d:
            events, lines = [], []
            with L.import_lock('import', d, 5, out=lines.append):
                def runner():
                    with L.run_guard('run', d, 10, out=lines.append):
                        events.append(('run', time.time()))

                thread = threading.Thread(target=runner)
                thread.start()
                time.sleep(1.2)
                self.assertEqual(events, [])
                released = time.time()
            thread.join(10)
            self.assertEqual(len(events), 1)
            self.assertGreaterEqual(events[0][1], released)
            self.assertTrue(any(line.startswith('IMPORT_LOCK waiting') for line in lines))
            self.assertEqual(list(Path(d).glob('*')), [])

    def test_run_guard_times_out_when_the_import_never_ends(self):
        with tempfile.TemporaryDirectory() as d:
            with L.import_lock('import', d, 5, out=lambda text: None):
                with self.assertRaises(L.LockTimeout) as caught:
                    with L.run_guard('run', d, 0.6, out=lambda text: None):
                        pass
                self.assertTrue(str(caught.exception).startswith('IMPORT_LOCK'))
                self.assertEqual(list(Path(d).glob('run-*.run')), [])  # no stray marker left behind

    def test_import_waits_for_a_run_that_was_already_going(self):
        with tempfile.TemporaryDirectory() as d:
            order = []
            guard = L.run_guard('run', d, 5, out=lambda text: None)
            guard.__enter__()

            def importer():
                with L.import_lock('import', d, 5, 10, out=lambda text: None):
                    order.append('import')

            thread = threading.Thread(target=importer)
            thread.start()
            time.sleep(1.2)
            self.assertEqual(order, [])  # the run still holds its marker
            order.append('run ends')
            guard.__exit__(None, None, None)
            thread.join(10)
            self.assertEqual(order, ['run ends', 'import'])

    def test_import_goes_ahead_with_a_warning_when_a_run_never_ends(self):
        with tempfile.TemporaryDirectory() as d:
            lines = []
            with sleeper() as proc:  # a live holder of a run marker
                (Path(d) / ('run-%d-000001.run' % proc.pid)).write_text(json.dumps({'pid': proc.pid, 'time': time.time()}), encoding='utf-8')
                with L.import_lock('import', d, 5, 0.6, out=lines.append):
                    pass
            self.assertTrue(any('importing anyway' in line for line in lines))

    def test_marker_of_a_dead_run_does_not_hold_the_import(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / ('run-%d-000001.run' % dead_pid())
            marker.write_text(json.dumps({'pid': dead_pid(), 'time': time.time()}), encoding='utf-8')
            started = time.time()
            with L.import_lock('import', d, 5, 5, out=lambda text: None):
                pass
            self.assertLess(time.time() - started, 2)
            self.assertFalse(marker.exists())

    def test_dead_import_lock_is_removed_by_the_next_import(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'import.lock').write_text(json.dumps({'pid': dead_pid(), 'time': time.time()}), encoding='utf-8')
            with L.import_lock('import', d, 2, out=lambda text: None):
                self.assertEqual(L.read_lock(Path(d) / 'import.lock')['label'], 'import')

    def test_second_import_waits_for_the_first(self):
        with tempfile.TemporaryDirectory() as d:
            with L.import_lock('one', d, 5, out=lambda text: None):
                with self.assertRaises(L.LockTimeout):
                    with L.import_lock('two', d, 0.6, out=lambda text: None):
                        pass


class RunSeatedTests(unittest.TestCase):
    def test_exit_code_and_output_pass_through_inside_a_seat(self):
        with tempfile.TemporaryDirectory() as seats, tempfile.TemporaryDirectory() as tree:
            code, out, timed_out = G.run_seated([sys.executable, '-c', 'import sys; print("hi"); sys.exit(7)'], 30, capture=True, seat_dir=seats, lock_dir=tree)
            self.assertEqual((code, timed_out), (7, False))
            self.assertIn(b'hi', out)
            self.assertEqual(list(Path(seats).glob('*')), [])
            self.assertEqual(list(Path(tree).glob('*')), [])

    def test_no_seat_raises_instead_of_starting_the_process(self):
        with tempfile.TemporaryDirectory() as seats, tempfile.TemporaryDirectory() as tree:
            marker = Path(tree) / 'started.txt'
            with env(MOIRA_GODOT_SLOTS=1, MOIRA_GODOT_SLOT_WAIT_S=0.5):
                with L.seat('holder', seats, 1, 5, out=lambda text: None):
                    with self.assertRaises(L.LockTimeout):
                        G.run_seated([sys.executable, '-c', 'import sys; open(sys.argv[1], "w").write("x")', str(marker)], 30, seat_dir=seats, lock_dir=tree)
            self.assertFalse(marker.exists())


class PurposeTests(unittest.TestCase):
    def test_purpose_names(self):
        self.assertEqual(godot.purpose_of(['--headless', '--path', '.', '--script', 'res://chapter1/tests/golden_core.gd', '--', '--update']), 'godot-golden_core')
        self.assertEqual(godot.purpose_of(['--script', 'C:\\x\\y\\hud_dump.gd']), 'godot-hud_dump')
        self.assertEqual(godot.purpose_of(['--headless', '--path', '.', '--import']), 'godot-import')
        self.assertEqual(godot.purpose_of(['--path', '.', 'res://a.tscn', '--', '--chapter1-profile-off', '--script']), 'godot-window')


if __name__ == '__main__':
    unittest.main()
