#!/usr/bin/env python3
"""run_all.py의 환경 탓 실패 표기(pass(env-retry) / FAIL(env)) 자체 검사. Godot는 띄우지 않는다. 가짜 검사 단위만 쓴다.

  python tools/dev/test_run_all_env.py
"""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import run_all as R  # noqa: E402


def proc(code, text=''):
    return {'timeout': 0, 'code': code, 'text': text}


def sequence(*outputs):
    """A unit function that returns the outputs one after the other and counts the calls."""
    calls = []

    def fn():
        calls.append(1)
        out = outputs[min(len(calls), len(outputs)) - 1]
        if isinstance(out, Exception):
            raise out
        return out
    fn.calls = calls
    return fn


class ReasonTests(unittest.TestCase):
    def test_environment_signs(self):
        self.assertEqual(R.env_reason(proc(3221225477)), 'exit 3221225477')
        self.assertEqual(R.env_reason(proc(3221225794)), 'exit 3221225794')
        self.assertIn('1450', R.env_reason(proc(1, 'OSError: [WinError 1450] Insufficient system resources')))
        self.assertIsNotNone(R.env_reason({'timeout': 0, 'code': None, 'text': 'x', 'env': 'GODOT_SLOT'}))
        self.assertIn('1450', R.env_reason({'exception': 'OSError: [WinError 1450] no'}))
        self.assertIn('3221225477', R.env_reason((False, 'no result line (exit 3221225477)')))

    def test_ordinary_failures_and_passes_are_not_environment(self):
        self.assertIsNone(R.env_reason(proc(1, 'SCRIPT ERROR: bad')))
        self.assertIsNone(R.env_reason(proc(0, 'WinError 1450 mentioned in a passing run')))
        self.assertIsNone(R.env_reason(proc(None, 'timeout')))
        self.assertIsNone(R.env_reason((True, 'WinError 1450')))
        self.assertIsNone(R.env_reason((False, '3 failures')))
        self.assertIsNone(R.env_reason({'exception': 'ValueError: x'}))

    def test_hint(self):
        self.assertEqual(R.env_hint(3221225477, ''), ' [env: exit 3221225477]')
        self.assertIn('1450', R.env_hint(1, 'x WinError 1450 y'))
        self.assertEqual(R.env_hint(1, 'plain'), '')


class RunUnitTests(unittest.TestCase):
    def test_clean_run_is_not_repeated(self):
        fn = sequence(proc(0, 'ok'))
        out, _, _, env = R.run_unit(fn, 'a', pause=0)
        self.assertEqual((len(fn.calls), env, out['code']), (1, None, 0))

    def test_environment_failure_then_pass_is_marked_retry(self):
        fn = sequence(proc(3221225477), proc(0, 'ok'))
        out, _, _, env = R.run_unit(fn, 'a', pause=0)
        self.assertEqual(len(fn.calls), 2)
        self.assertEqual(out['code'], 0)
        self.assertEqual(env[0], 'retry')

    def test_environment_failure_twice_is_marked_fail(self):
        fn = sequence(proc(3221225477), proc(3221225477))
        _, _, _, env = R.run_unit(fn, 'a', pause=0)
        self.assertEqual((len(fn.calls), env[0]), (2, 'fail'))

    def test_ordinary_failure_is_not_repeated(self):
        fn = sequence(proc(1, 'SCRIPT ERROR: bad'), proc(0))
        out, _, _, env = R.run_unit(fn, 'a', pause=0)
        self.assertEqual((len(fn.calls), env, out['code']), (1, None, 1))

    def test_environment_failure_then_a_real_failure_is_a_plain_failure(self):
        fn = sequence(OSError('[WinError 1450] no'), proc(1, 'SCRIPT ERROR: bad'))
        out, _, _, env = R.run_unit(fn, 'a', pause=0)
        self.assertEqual(out['code'], 1)
        self.assertEqual(env[0], 'retry')
        self.assertEqual(R.status_of(False, [env]), 'FAIL')  # the second run was a real verdict, not an environment one


class StatusTests(unittest.TestCase):
    def test_status_names(self):
        self.assertEqual(R.status_of(True, [None]), 'pass')
        self.assertEqual(R.status_of(True, [None, ('retry', 'x')]), 'pass(env-retry)')
        self.assertEqual(R.status_of(False, [None]), 'FAIL')
        self.assertEqual(R.status_of(False, [('fail', 'x')]), 'FAIL(env)')
        self.assertEqual(R.status_of(False, [('retry', 'x')]), 'FAIL')


class ExecuteTests(unittest.TestCase):
    def run_tasks(self, jobs, units):
        """units: {name: function}. Each check is a python-style task whose output is (passed, detail)."""
        tasks = [R.Task([name], [(name, 1, fn)], lambda outs, n=name: {n: outs[0]}) for name, fn in units.items()]
        rows = {}
        original = R.time.sleep
        R.time.sleep = lambda seconds: None
        try:
            R.execute(tasks, jobs, lambda name, status, detail, seconds: rows.__setitem__(name, (status, detail)))
        finally:
            R.time.sleep = original
        return rows

    def test_rows_in_both_modes(self):
        for jobs in (1, 3):
            rows = self.run_tasks(jobs, {
                'plain': sequence((True, '3 tests')),
                'flaky': sequence((False, 'no summary [env: WinError 1450]'), (True, '3 tests')),
                'broken': sequence((False, 'no summary [env: exit 3221225477]'), (False, 'no summary [env: exit 3221225477]')),
                'wrong': sequence((False, '2 failures')),
            })
            self.assertEqual(rows['plain'], ('pass', '3 tests'), jobs)
            self.assertEqual(rows['flaky'][0], 'pass(env-retry)', jobs)
            self.assertIn('WinError 1450', rows['flaky'][1])
            self.assertEqual(rows['broken'][0], 'FAIL(env)', jobs)
            self.assertEqual(rows['wrong'], ('FAIL', '2 failures'), jobs)

    def test_a_runner_that_retried_inside_itself_is_marked(self):
        rows = self.run_tasks(1, {'selftest': sequence((True, '20 files, passed on a second run alone: a.py [first run: x] ' + R.ENV_RETRY_MARK % 'WinError 1450'))})
        self.assertEqual(rows['selftest'][0], 'pass(env-retry)')
        rows = self.run_tasks(1, {'selftest': sequence((True, '20 files, passed on a second run alone: a.py [first run: x]'))})
        self.assertEqual(rows['selftest'][0], 'pass')  # a flake with no environment sign is named but not called an environment failure

    def test_seat_timeout_becomes_an_environment_failure_without_running_godot(self):
        from unittest import mock
        with mock.patch.object(R, 'isolated_env', return_value={}),                 mock.patch.object(R.godot_guard, 'run_seated', side_effect=R.repo_lock.LockTimeout('GODOT_SLOT no free seat of 6 after 1200 s (x)')):
            result = R.run_process('res://x.gd', [], 5, 'unit-test')
        self.assertEqual(result['code'], None)
        self.assertEqual(R.env_reason(result), 'GODOT_SLOT')


if __name__ == '__main__':
    unittest.main()
