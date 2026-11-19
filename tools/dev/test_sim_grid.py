#!/usr/bin/env python3
"""sim_grid.py 자체 검사. Godot도 실제 시험장도 쓰지 않는다(가짜 원시 JSON과 --dry만).

  python tools/dev/test_sim_grid.py
"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import sim_grid as S  # noqa: E402


def cell(beat, variant, **kw):
    base = {"beat": beat, "variant": variant, "contact_share_pct": 50.0, "power_hp_s": 100.0, "taken_30s_pct": 200.0, "alive_cap": 75, "alive_mean": 60.0, "ring_kill_share_pct": 40.0,
            "ranged_in_6m": 5.0, "alive_ranged": 10.0, "src_hits": {"walker": 10, "ranged": 5, "charger": 2}, "ward": {"vs_cc_hits": 4}, "basic_hits": 20, "kill_per_s": 3.0, "dead_np_s": 5.0,
            "i1_extra_share_pct": 2.0, "i2_extra_share_pct": 3.0}
    base.update(kw)
    return base


class SimGridTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="sim_grid_test_")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_spread_and_ratio(self):
        self.assertAlmostEqual(S.spread([90.0, 100.0, 110.0]), 0.1)
        self.assertEqual(S.spread([5.0]), 0.0)
        self.assertTrue(S.ratio(1.0, 0.0) != S.ratio(1.0, 0.0))  # nan
        self.assertAlmostEqual(S.ratio(1.0, 4.0), 0.25)

    def write(self, name, cells):
        d = Path(self.tmp) / "raw" / "base"
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_text(json.dumps({"meta": {}, "cells": cells}), encoding="utf-8")

    def test_store_pass_lines_and_best_nb(self):
        # 서로 다른 시드 셋: NB6 접촉 100, NB6w 80 -> NB 최선(낮을수록 좋음) = 80, SY6 30 -> 비 0.375 통과
        self.write("frost_NB6_base_S.json", [cell(b, "stand", contact_share_pct=100.0, seed=s) for b in S.BEATS for s in (11, 12, 13)])
        self.write("frost_NB6w_base_S.json", [cell(b, "stand", contact_share_pct=80.0, seed=s) for b in S.BEATS for s in (11, 12, 13)])
        self.write("frost_SY6_base_S.json", [cell(b, "stand", contact_share_pct=30.0, seed=s) for b in S.BEATS for s in (11, 12, 13)])
        store = S.Store()
        store.load(self.tmp, "base")
        val, who, unst = S.best_nb(store, "frost", "base", "seung2", "stand", "contact_share_pct", True)
        self.assertEqual((val, who, unst), (80.0, "NB6w", False))
        lines = S.pass_lines(store, "frost", "SY6")
        contact_line = [ln for ln in lines if ln.startswith("접촉 시간 몫")][0]
        self.assertIn("0.38o", contact_line)
        # 접촉으로 맞은 횟수: SY6와 NB가 같으면 1.00x
        self.assertIn("1.00x", [ln for ln in lines if ln.startswith("접촉 맞은 횟수")][0])

    def test_unstable_star(self):
        store = S.Store()
        store.g[("frost", "SY6", "base", "seung2", "stand")] = [cell("seung2", "stand", contact_share_pct=v) for v in (10.0, 50.0, 90.0)]
        self.assertTrue(store.unstable(("frost", "SY6", "base", "seung2", "stand"), "contact_share_pct"))
        self.assertFalse(store.unstable(("frost", "SY6", "base", "seung2", "stand"), "power_hp_s"))

    def test_jobs_and_command(self):
        jobs = S.jobs_of("grid", ["frost"])
        self.assertEqual(len(jobs), 27)
        cmd = jobs[0].command("_local/x", "grid", "11,12,13")
        self.assertIn("--ring-cd-all", cmd)
        self.assertIn("--build=A:d4+R", cmd)
        self.assertTrue(cmd[1].endswith("godot.py"))
        self.assertTrue(any(c.startswith("--out=_local/x/raw/grid/frost_SY0_") for c in cmd))
        for name in S.EXPERIMENTS:
            for j in S.jobs_of(name, S.WITCHES):
                self.assertIn(j.vset, S.VSETS)
        self.assertEqual(len(S.jobs_of("base", S.WITCHES)), (9 + 8 + 8) * 3)  # RNDb는 냉기만

    def test_n2_cfg_and_lines_args(self):
        cfg = S.Cfg.parse("c:15/25/60")
        self.assertEqual((cfg.val, cfg.sb, cfg.sr, cfg.bm, cfg.sx, cfg.wh), ("c", 15, 25, 60, 10, False))
        self.assertEqual(S.Cfg.parse("d:0/0/100:x0").tag(), "base")
        self.assertTrue(S.Cfg.parse("c:15/25/60:wh").wh)
        # D16 2.3절 표: SY6(A:d4+R:r2) = 기본기 3072 x 1.30 = 3994, 울타리 x2.0. RO6 = 기본기 x1.45 = 4454, 울타리 그대로. NB는 줄 없음
        sy = S.cfg_args("frost", "A:d4+R:r2", cfg)
        self.assertIn("--set=spells/chapter1.skill.frost/base/damage_raw=3994", sy)
        self.assertIn("--ring-dmg=2.0000", sy)
        ro = S.cfg_args("frost", "R:d3r3", cfg)
        self.assertIn("--set=spells/chapter1.skill.frost/base/damage_raw=4454", ro)
        self.assertFalse([a for a in ro if a.startswith("--ring-dmg=")])
        self.assertEqual(S.cfg_args("frost", "A:d4r2", cfg), [])
        rnd = S.cfg_args("frost", "A:d1r1+R:d1r1+X:d1r1", cfg)   # 거래 감쇠 x0.6, 거래 줄 +10%: 기본기 3072 x (1 + .15 + .10)
        self.assertIn("--set=spells/chapter1.skill.ember/base/damage_raw=%d" % round(3584 * 0.6), rnd)
        self.assertIn("--set=spells/chapter1.skill.frost/base/damage_raw=%d" % round(3072 * 1.25), rnd)
        self.assertIn("--ring-dmg=1.2500", rnd)

    def test_n2_samples_are_deterministic_and_valid(self):
        a, n_all = S.gen_samples(6)
        b, _ = S.gen_samples(6)
        self.assertEqual(a, b)
        self.assertEqual(len(a), 20)
        self.assertEqual(len({s for _, s in a}), 20)
        self.assertGreater(n_all, 20)
        for _, spec in a + S.gen_samples(8)[0]:
            ax = S.spec_axes(spec)
            self.assertEqual(set(ax), {"A", "R", "X"})
            for d, r in ax.values():
                self.assertTrue(0 < d + r <= 6 and d <= 4 and r <= 4)

    def test_cli_rules(self):
        with self.assertRaises(SystemExit):
            S.main(["run", "base", "--out", "elsewhere"])
        with self.assertRaises(SystemExit):
            S.main(["run", "base", "--out", "_local/x", "--jobs", "9"])


if __name__ == "__main__":
    unittest.main()
