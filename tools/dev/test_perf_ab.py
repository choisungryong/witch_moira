#!/usr/bin/env python3
"""perf_ab.py 자체 검사. Godot도 실제 측정도 쓰지 않는다(가짜 프로브 출력과 가짜 실행기만).

  python tools/dev/test_perf_ab.py
  python tools/dev/test_perf_ab.py --history C:/Project/witch-moira/_local/perf/hero-light   # 과거 원시와 과거 보고의 표를 대조

과거 대조는 --history(또는 환경변수 PERF_AB_HISTORY)가 가리키는 폴더에 runs/, plan.json, main_tables.md, vat_tables.md가
있을 때만 돈다. 없으면 건너뛴다고 출력한다(통과로 세지 않는다).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import perf_ab as P  # noqa: E402

ROOT = HERE.parent.parent
HISTORY = os.environ.get('PERF_AB_HISTORY', '')
if '--history' in sys.argv:
    _i = sys.argv.index('--history')
    HISTORY = sys.argv[_i + 1]
    del sys.argv[_i:_i + 2]


def fake_probe(seconds=60, dt_ms=10.0, nticks=1, act_us=500, seed_shift=0, scale=1.0):
    """A probe JSON with the fields perf_ab reads. Frame i lasts dt_ms*scale (+ a slow frame every 50th)."""
    f_t, f_dt, t = [], [], 0
    i = 0
    while t < seconds * 1e6:
        d = dt_ms * scale * 1000 * (6 if i % 50 == 49 else 1)
        f_dt.append(int(d))
        t += int(d)
        f_t.append(t)
        i += 1
    n = len(f_dt)
    j = {'info': {'final_tick': 3600, 'seconds': seconds, 'debug_build': False, 'focus_samples': [1, 1], 'window_size': [1920, 1080]},
         'f_t': f_t, 'f_dt': f_dt, 'f_nticks': [nticks] * n,
         'f_phys': [1000] * n, 'f_cam': [100] * n, 'f_act': [act_us + seed_shift] * n, 'f_fx': [200] * n, 'f_juice': [300] * n,
         'f_hud': [400] * n, 'f_world': [150] * n, 'f_x': [0] * n,
         'f_draw': [800] * n, 'f_rcpu': [1.5] * n, 'f_rgpu': [4.5] * n, 'f_en': [100] * n}
    ticks = 600
    j['k_t'] = [int(k * seconds * 1e6 / ticks) for k in range(ticks)]
    for k in ('k_pilot', 'k_step', 'k_cons', 'k_audio'):
        j[k] = [1000] * ticks
    return j


def write_run(folder, name, probe, contaminated=False, start='2026-11-19T01:00:00'):
    Path(folder, name + '.json').write_text(json.dumps(probe), encoding='utf-8')
    Path(folder, name + '.env.json').write_text(json.dumps({'name': name, 'contaminated': contaminated, 'forced': False, 'foreign_events': [{'name': 'Godot.exe', 'pid': 1}] if contaminated else [],
                                                              'start': start, 'wall_s': 61, 'exit': 0, 'cpu_delta_top': []}), encoding='utf-8')


class Metrics(unittest.TestCase):
    def test_known_values(self):
        j = fake_probe(seconds=60, dt_ms=10.0)
        m = P.metrics(j, late_from=30)
        self.assertAlmostEqual(m['p50'], 10.0, places=2)
        self.assertGreater(m['p99'], 50.0)      # the slow frame (60 ms) every 50th frame is above p98
        self.assertEqual(m['gt100'], 0)
        self.assertGreater(m['gt50'], 0)
        self.assertAlmostEqual(m['late_act'], 0.5, places=3)
        self.assertAlmostEqual(m['fxj'], 0.5, places=3)         # fx 0.2 + juice 0.3
        self.assertAlmostEqual(m['tick_ms'], 4.0, places=3)     # four 1 ms parts
        self.assertEqual(m['late_en'], 100)
        self.assertEqual(m['final_tick'], 3600)

    def test_other_is_the_remainder(self):
        m = P.metrics(fake_probe(seconds=60, dt_ms=10.0), late_from=30)
        # dt - phys(1) - (cam .1 + act .5 + fx .2 + juice .3 + hud .4 + world .15) = the rest. The slow frames lift the mean.
        self.assertGreater(m['late_other'], 10.0 - 1 - 1.65 - 0.01)

    def test_percentile_matches_linear_rule(self):
        self.assertAlmostEqual(P.pct([1, 2, 3, 4], 50), 2.5)
        self.assertAlmostEqual(P.pct([1, 2, 3, 4, 5], 95), 4.8)

    def test_missing_column_is_an_error(self):
        j = fake_probe(seconds=20)
        del j['f_hud']
        with self.assertRaises(P.ProbeError):
            P.metrics(j)

    def test_short_run_has_no_late_part(self):
        m = P.metrics(fake_probe(seconds=30), late_from=180)
        self.assertEqual(m['late_n'], 0)
        self.assertTrue(m['late_act'] != m['late_act'])   # nan, not 0


class Verdict(unittest.TestCase):
    def test_overlap_is_not_called_equal(self):
        v = P.verdict('a', 'b', [10, 11, 12], [11, 12, 13])
        self.assertTrue(v.startswith('가르지 못함(범위 겹침, 표본 3/3'))
        self.assertNotIn('영향 없음', v)

    def test_separated_names_direction_and_weak_evidence(self):
        v = P.verdict('a', 'b', [10, 11, 12], [20, 21, 22])
        self.assertTrue(v.startswith('분리(b 쪽이 높음'))
        self.assertIn('약한 증거', v)
        v5 = P.verdict('a', 'b', [10, 11, 12, 11, 10], [1, 2, 3, 2, 1])
        self.assertIn('낮음', v5)
        self.assertNotIn('약한 증거', v5)

    def test_too_few_runs(self):
        self.assertTrue(P.verdict('a', 'b', [1, 2], [5, 6, 7]).startswith('판정 불가'))

    def test_nan_values_do_not_count(self):
        self.assertTrue(P.verdict('a', 'b', [1, 2, float('nan')], [5, 6, 7]).startswith('판정 불가'))


class Plan(unittest.TestCase):
    def test_alternation_warmup_blocks(self):
        plan = {'variants': [{'name': 'before', 'exe': 'C:/a.exe', 'rounds': 2}, {'name': 'after', 'project': 'C:/p', 'rounds': 2},
                             {'name': 'vb', 'exe': 'C:/a.exe', 'rounds': 1, 'warmup': False, 'block': 'vat', 'args': ['--chapter1-vat-walker']},
                             {'name': 'va', 'exe': 'C:/b.exe', 'rounds': 1, 'warmup': False, 'block': 'vat', 'args': ['--chapter1-vat-walker']}]}
        runs = P.expand_plan(plan)
        self.assertEqual([r['name'] for r in runs], ['before-r0', 'after-r0', 'before-r1', 'after-r1', 'before-r2', 'after-r2', 'vb-r1', 'va-r1'])
        self.assertEqual([r['warmup'] for r in runs], [True, True] + [False] * 6)
        self.assertEqual([r['order'] for r in runs], list(range(8)))

    def test_legacy_list_blocks_by_args(self):
        plan = [{'name': 'before-r0', 'exe': 'x', 'args': []}, {'name': 'after-r0', 'exe': 'y', 'args': []},
                {'name': 'vbefore-r1', 'exe': 'x', 'args': ['--chapter1-vat-walker']}]
        runs = P.expand_plan(plan)
        self.assertEqual([r['block'] for r in runs], ['block1', 'block1', 'block2'])
        self.assertTrue(runs[0]['warmup'] and not runs[2]['warmup'])

    def test_variant_needs_a_target(self):
        with self.assertRaises(ValueError):
            P.expand_plan({'variants': [{'name': 'a'}]})

    def test_commands(self):
        run = P.expand_plan({'variants': [{'name': 'a', 'exe': 'C:/b/WitchMoira.exe', 'rounds': 1, 'warmup': False}]})[0]
        cmd = P.build_command(run, Path('C:/out/a-r1.json'))
        self.assertEqual(cmd[0], 'C:/b/WitchMoira.exe')
        self.assertIn('--script', cmd)
        script = cmd[cmd.index('--script') + 1]
        self.assertTrue(script.endswith('chapter1/tests/perf_probe.gd') and not script.startswith('res://'))  # exe: absolute path
        self.assertEqual(cmd[cmd.index('--script') - 2:cmd.index('--script')], ['--resolution', '1920x1080'])
        self.assertIn('--probe-out=C:/out/a-r1.json', cmd)
        self.assertNotIn('--headless', cmd)

    def test_project_with_probe_uses_res_path(self):
        run = P.expand_plan({'variants': [{'name': 'a', 'project': str(ROOT), 'rounds': 1, 'warmup': False}]})[0]
        cmd = P.build_command(run, Path('C:/out/x.json'))
        self.assertIn('res://chapter1/tests/perf_probe.gd', cmd)
        self.assertEqual(cmd[1:3], ['--path', str(ROOT)])


class Report(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def build(self, a_scales, b_scales, contaminated=(), compares=None):
        for i, s in enumerate(a_scales):
            write_run(self.tmp, 'a-r%d' % i, fake_probe(60, scale=s))
        for i, s in enumerate(b_scales):
            write_run(self.tmp, 'b-r%d' % i, fake_probe(60, scale=s), contaminated=('b-r%d' % i) in contaminated)
        return P.build_report(self.tmp, compares=compares or [['a', 'b']], late_from=30)

    def test_overlap_and_separation(self):
        text = self.build([1.0, 1.02, 0.98, 1.01], [1.0, 1.03, 0.99, 1.02])
        self.assertIn('가르지 못함(범위 겹침, 표본 3/3)', text)
        self.assertNotIn('영향 없음', text)
        text = self.build([1.0, 1.02, 0.98, 1.01], [1.5, 1.53, 1.49, 1.51])
        self.assertIn('분리(b 쪽이 높음', text)

    def test_warmup_is_shown_but_not_counted(self):
        text = self.build([1.0, 1.02, 0.98, 1.01], [1.0, 1.03, 0.99, 1.02])
        self.assertIn('예열(제외)', text)
        self.assertRegex(text, r'\| a \| 3 \|')

    def test_contaminated_run_is_excluded_and_flagged(self):
        text = self.build([1.0, 1.02, 0.98, 1.01, 1.0], [1.0, 1.03, 0.99, 1.02, 1.01], contaminated=('b-r2',))
        self.assertIn('**오염**', text)
        self.assertRegex(text, r'\| b \| 3 \|')
        self.assertIn('b-r2: 오염=True', text)

    def test_too_few_clean_runs_is_undecided(self):
        text = self.build([1.0, 1.02, 0.98, 1.01], [1.0, 1.03, 0.99, 1.02], contaminated=('b-r2',))
        self.assertIn('판정 불가(표본 3/2', text)

    def test_drift_warning(self):
        # speeds improve with every round in both conditions
        a = [1.0, 1.5, 1.4, 1.3, 1.2, 1.1]
        b = [1.0, 1.45, 1.35, 1.25, 1.15, 1.05]
        text = self.build(a, b)
        self.assertIn('경고 p95', text)
        steady = self.build([1.0, 1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
        self.assertIn('경고 없음', steady)

    def test_header_names_unofficial_conditions(self):
        plan = {'variants': [{'name': 'a', 'project': str(ROOT), 'rounds': 2}, {'name': 'b', 'exe': 'C:/x.exe', 'rounds': 2}]}
        for r in P.expand_plan(plan):
            write_run(self.tmp, r['name'], fake_probe(60))
        text = P.build_report(self.tmp, plan=plan, late_from=30)
        self.assertIn('에디터(프로젝트 폴더) 실행이 있다', text)
        self.assertIn('qa-ignore-focus', text)
        self.assertIn('수직동기', text)

    def test_missing_probe_output_is_listed(self):
        plan = {'variants': [{'name': 'a', 'exe': 'C:/x.exe', 'rounds': 1}, {'name': 'b', 'exe': 'C:/y.exe', 'rounds': 1}]}
        write_run(self.tmp, 'a-r0', fake_probe(60))
        text = P.build_report(self.tmp, plan=plan, late_from=30)
        self.assertIn('no probe output', text)


class Orchestrator(unittest.TestCase):
    """Runs the real orchestrator with a fake program that writes a probe JSON. No Godot is started."""

    def test_run_with_fake_launcher(self):
        tmp = ROOT / '_local' / 'perf-ab-selftest'
        shutil.rmtree(tmp, ignore_errors=True)
        try:
            fake = tmp / 'fake_probe.py'
            tmp.mkdir(parents=True)
            fake.write_text(
                'import json, sys\n'
                'sys.path.insert(0, %r)\n'
                'from test_perf_ab import fake_probe\n'
                'out = [a for a in sys.argv if a.startswith("--probe-out=")][0].split("=", 1)[1]\n'
                'open(out, "w").write(json.dumps(fake_probe(60)))\n' % str(HERE), encoding='utf-8')
            plan = {'title': 'selftest', 'late_from': 30, 'variants': [
                {'name': 'a', 'launcher': [sys.executable, str(fake)], 'rounds': 1, 'warmup': False},
                {'name': 'b', 'launcher': [sys.executable, str(fake)], 'rounds': 1, 'warmup': False}]}
            plan_path = tmp / 'plan.in.json'
            plan_path.write_text(json.dumps(plan), encoding='utf-8')
            out = tmp / 'out'
            code = P.main(['run', str(plan_path), '--out', str(out), '--no-wait', '--poll', '0.2', '--late-from', '30'])
            self.assertEqual(code, 0)
            for n in ('a-r1', 'b-r1'):
                self.assertTrue((out / (n + '.json')).is_file())
                env = json.loads((out / (n + '.env.json')).read_text(encoding='utf-8'))
                self.assertEqual(env['exit'], 0)
                for key in ('foreign_events', 'pre_foreign', 'cpu_delta_top', 'contaminated', 'forced', 'cmd', 'start', 'end', 'monitor'):
                    self.assertIn(key, env)
            self.assertTrue((out / 'report.md').is_file())
            self.assertTrue((out / 'orchestrator.log').is_file())
            # raw results are kept: a second run into the same folder is refused
            self.assertEqual(P.main(['run', str(plan_path), '--out', str(out), '--no-wait']), 2)
            # outside _local is refused
            self.assertEqual(P.main(['run', str(plan_path), '--out', str(Path(tempfile.gettempdir()) / 'perf-ab-x'), '--no-wait']), 2)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_process_table_finds_own_python(self):
        table = P.process_table()
        self.assertIn(os.getpid(), [pid for pid, _, _ in table])
        self.assertIn(os.getpid(), P.descendants(table, os.getpid()))


# ---------------------------------------------------------------- history comparison

def parse_tables(text):
    """{(heading key, row key): cells} for run rows, condition rows and difference rows; verdicts reduced to a class."""
    out = {}
    heading = ''
    for line in text.splitlines():
        if line.startswith('### '):
            heading = line[4:].strip()
            continue
        if not line.startswith('|') or line.startswith('|---') or line.startswith('| 회차') or line.startswith('| 조건') or line.startswith('| 지표'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if heading.endswith('(회차별)'):
            out[(heading.split()[0], 'run', cells[0])] = cells[1:23]
        elif heading.startswith('조건별'):
            out[('median', cells[0])] = cells[1:24]
        elif heading.startswith('차이:'):
            key = tuple(re.split(r'\s+[^\w\s]\s+', heading.split('(')[0].replace('차이:', '').strip()))
            verdict = '분리' if cells[4].startswith('분리') else '가르지 못함' if cells[4].startswith('가르지') else cells[4]
            out[('diff',) + key + (cells[0],)] = cells[1:4] + [verdict]
    return out


class History(unittest.TestCase):
    @unittest.skipUnless(HISTORY and (Path(HISTORY) / 'runs').is_dir(), 'no --history folder: past raw not compared (not counted as pass)')
    def test_same_tables_and_verdicts_as_past_report(self):
        h = Path(HISTORY)
        plan = json.loads((h / 'plan.json').read_text(encoding='utf-8'))
        mine = P.build_report(h / 'runs', plan=plan)
        got = parse_tables(mine)
        checked = 0
        for old_file in ('main_tables.md', 'vat_tables.md'):
            old = parse_tables((h / old_file).read_text(encoding='utf-8'))
            self.assertTrue(old, old_file)
            for key, cells in old.items():
                if key[0] == 'median':
                    # the old file keeps one 조건별 table per file with several rows; same row names exist in mine
                    pass
                self.assertIn(key, got, 'missing in new report: %r' % (key,))
                self.assertEqual(got[key], cells, 'differs: %r' % (key,))
                checked += 1
        self.assertEqual(checked, 66)  # main: 12 run rows + 2 condition rows + 22 differences; vat: 6 + 2 + 22
        print('HISTORY compared %d rows (run rows, condition rows, difference rows with verdict class)' % checked)


if __name__ == '__main__':
    unittest.main(verbosity=1)
