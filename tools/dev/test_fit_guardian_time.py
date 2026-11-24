"""Self-test of fit_guardian_time.py with a small made-up input (run_all.py tools-selftest runs it).

    python tools/dev/test_fit_guardian_time.py

Makes guardian times from a known model (beta 0.5, gamma 0.3, fixed shares per primary), writes them as measure_rhythm / report_kit_reads files in a temporary folder,
and checks that the fit finds the known values, that M1 passes, that a spoiled point is reported OUTSIDE, that a curve prediction equals the hand calculation,
that the M2 rule counts as written, and that a reads file whose numbers disagree with the totals stops the tool.
"""
import contextlib
import io
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fit_guardian_time as fg

BLOCK = {
    'damage_keys': {'chapter1.skill.ember': ['damage_bps', 'fire_damage_bps'], 'chapter1.skill.frost': ['damage_bps'], 'chapter1.skill.arc': ['damage_bps', 'arc_damage_bps']},
    'cooldown_key': 'cooldown_bps',
    'shape_keys': {'chapter1.skill.ember': ['projectiles'], 'chapter1.skill.frost': ['projectiles'], 'chapter1.skill.arc': ['projectiles', 'chain_targets']},
    'shape_base': {'chapter1.skill.ember': 'projectiles', 'chapter1.skill.frost': 'projectiles', 'chapter1.skill.arc': 'chain_targets'},
    'shots_r1': {'chapter1.skill.ember': 2, 'chapter1.skill.frost': 2, 'chapter1.skill.arc': 3},
    'shape_share': 0.5,
}
BETA, GAMMA = 0.5, 0.3
F = {'ember': 0.1, 'frost': 0.3, 'arc': 0.2}
BARE = {'ember': 8.0, 'frost': 15.0, 'arc': 18.0}
SEEDS = list(range(11, 17))
KITS = {  # kit -> totals
    'kit.a': {'damage_bps': 3000, 'cooldown_bps': 2000, 'projectiles': 1, 'fire_damage_bps': 500, 'arc_damage_bps': -500, 'chain_targets': 1},
    'kit.b': {'damage_bps': 9000, 'cooldown_bps': 4000, 'projectiles': 2, 'fire_damage_bps': 1500, 'chain_targets': 3},
    'kit.c': {'damage_bps': 6000, 'cooldown_bps': 8000, 'projectiles': 0, 'chain_targets': 5},
    'kit.d': {'damage_bps': 12000, 'cooldown_bps': 1000, 'projectiles': 3, 'fire_damage_bps': 2500, 'arc_damage_bps': -1200},
    'kit.e': {'damage_bps': 1000, 'cooldown_bps': 6000, 'projectiles': 4, 'chain_targets': 2},
    'kit.f': {'damage_bps': 7000, 'cooldown_bps': 3000, 'projectiles': 1, 'fire_damage_bps': 800},
}


def guardian_run(kind_times, seed, prim, kit):
    return {'kit': kit, 'primary': prim, 'seed': seed, 'sweep': {'big': [{'kind': 'guardian%d' % (i + 1), 'lived_s': t, 'death_s': 100.0} for i, t in enumerate(kind_times)]},
            'mode': 'victory'}


def make(tmp, spoil=None, wrong_reads=False):
    none_runs, kit_runs, rows = [], [], []
    for prim in fg.PRIMS:
        for seed in SEEDS:
            none_runs.append(guardian_run([BARE[prim], BARE[prim] * 1.1], seed, prim, 'none'))
        for kit, totals in KITS.items():
            d, r, s = fg.factors(totals, prim, BLOCK)
            m = d * r ** BETA * s ** GAMMA
            ratio = F[prim] + (1 - F[prim]) / m
            if spoil == (kit, prim):
                ratio += 0.3
            for seed in SEEDS:
                kit_runs.append(guardian_run([BARE[prim] * ratio, BARE[prim] * 1.1 * ratio], seed, prim, kit))
            rows.append({'kit': kit, 'primary': prim, 'damage': d + (0.1 if wrong_reads and kit == 'kit.a' else 0.0), 'rate': r, 'shape': s, 'totals': totals})
    loot = tmp / 'loot.json'
    loot.write_text(json.dumps({'upgrade_verdict': BLOCK}), encoding='utf-8')
    (tmp / 'none.json').write_text(json.dumps({'runs': none_runs}), encoding='utf-8')
    (tmp / 'kits.json').write_text(json.dumps({'runs': kit_runs}), encoding='utf-8')
    (tmp / 'reads.json').write_text(json.dumps({'rows': rows}), encoding='utf-8')
    return loot


def run_tool(tmp, loot, extra=()):
    argv = ['--none', str(tmp / 'none.json'), '--runs', 'syn=%s' % (tmp / 'kits.json'), '--reads', str(tmp / 'reads.json'), '--loot', str(loot),
            '--boot', '60', '--out', str(tmp / 'fit.json')] + list(extra)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = fg.main(argv)
    return code, buf.getvalue(), json.loads((tmp / 'fit.json').read_text(encoding='utf-8'))


class FitTest(unittest.TestCase):
    def test_recovers_known_model(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            loot = make(tmp)
            code, text, out = run_tool(tmp, loot)
            self.assertEqual(code, 0)
            self.assertAlmostEqual(out['beta'], BETA, places=6)
            self.assertAlmostEqual(out['gamma'], GAMMA, places=6)
            for prim in fg.PRIMS:
                self.assertAlmostEqual(out['f'][prim], F[prim], places=6)
            self.assertLess(out['sse'], 1e-9)
            self.assertEqual(out['m1']['outside'], 0)
            self.assertEqual(len(out['points']), len(KITS) * 3)
            self.assertAlmostEqual(out['fixed']['frost']['o_s'], F['frost'] * BARE['frost'] * 1.05, delta=0.05)  # bare median of the two guardians

    def test_spoiled_point_is_outside(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            loot = make(tmp, spoil=('kit.b', 'frost'))
            _, text, out = run_tool(tmp, loot)
            self.assertIn('OUTSIDE', text)
            self.assertGreaterEqual(out['m1']['outside'], 1)

    def test_curve_prediction_by_hand(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            loot = make(tmp)
            _, _, out = run_tool(tmp, loot, ['--curve', '4000,0.5', '--curve-kits', 'kit.b,kit.d,kit.e'])
            cur = out['curves'][0]
            # ember, kit.b: D 9000 -> 4000 + 5000 * 0.5 = 6500; fire 1500 untouched
            d = (1 + 6500 / 10000.0) * (1 + 1500 / 10000.0)
            r = 1 + 4000 / 10000.0
            s = 1 + 0.5 * 2 / 2
            m = d * r ** BETA * s ** GAMMA
            want = F['ember'] + (1 - F['ember']) / m
            self.assertAlmostEqual(cur['preds']['kit.b|ember'], want, places=6)
            self.assertEqual(cur['damage_bps']['kit.b|ember'], [9000.0, 6500.0])
            # below the knee nothing changes
            self.assertEqual(cur['damage_bps']['kit.e|frost'], [1000.0, 1000.0])

    def test_m2_rule(self):
        good = {}
        for k in ('x', 'y', 'z'):
            good[(k, 'ember')] = 0.55
            good[(k, 'frost')] = 0.60
            good[(k, 'arc')] = 0.65
        self.assertTrue(fg.m2_eval(good, {})['pass'])
        bad = dict(good)
        bad[('x', 'ember')] = bad[('y', 'ember')] = 0.45
        self.assertFalse(fg.m2_eval(bad, {})['pass'])
        low = dict(good)
        low[('z', 'arc')] = 0.35
        self.assertFalse(fg.m2_eval(low, {})['pass'])  # outside 0.40..0.80
        edge = fg.m2_eval(good, {('x', 'ember'): (0.45, 0.55, 0.60)})
        self.assertTrue(any('0.50' in n for n in edge['boundary_notes']))

    def test_reads_that_disagree_stop_the_tool(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            loot = make(tmp, wrong_reads=True)
            with self.assertRaises(SystemExit):
                run_tool(tmp, loot)


if __name__ == '__main__':
    unittest.main(verbosity=2)
