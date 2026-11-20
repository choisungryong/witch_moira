#!/usr/bin/env python3
"""rig_mocap의 순수 계산(디딤 구간 찾기, 발 디딤 고정)과 짝 표 검사. Blender 없이 돈다(tools-selftest에 걸린다).

  python tools/art/test_rig_mocap.py
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402

import rig_mocap as M  # noqa: E402


class StanceTests(unittest.TestCase):
    def cycle(self, n=40):
        t = np.arange(n) / n
        z = 0.1 + 0.2 * np.clip(np.sin(2 * np.pi * (t - 0.3)), 0, None)          # 앞 절반(0.3 지나 0.5까지) 들림, 나머지 바닥
        return t, z

    def test_detect_and_segments_wrap(self):
        t, z = self.cycle()
        mask = M.detect_stance(z, 0.01)
        segs = M.stance_segments(mask)
        self.assertEqual(len(segs), 1)
        a, b = segs[0]
        self.assertTrue(mask[a] and mask[b])
        self.assertTrue(a > b or (b - a) > 10)      # 0을 넘어 이어지거나 긴 구간
        self.assertEqual(M.stance_segments(np.ones(5, bool)), [])
        self.assertEqual(M.stance_segments(np.zeros(5, bool)), [])

    def test_lock_removes_slide_and_keeps_swing_continuous(self):
        n, dt, vg = 40, 1.0 / 60, 4.0
        t, z = self.cycle(n)
        mask = M.detect_stance(z, 0.01)
        y = np.where(mask, 0.5 * np.arange(n) * dt, 0.0)      # 엉뚱한 속도로 미끄러지는 발
        self.assertGreater(M.slide_error(y, mask, dt, vg), 1.0)
        y2, segs = M.lock_foot(y, mask, dt, vg)
        self.assertLess(M.slide_error(y2, mask, dt, vg), 1e-6)
        self.assertLessEqual(float(np.abs(np.diff(y2, append=y2[0])).max()), float(np.abs(np.diff(y, append=y[0])).max()) + 1e-9)   # 이음이 원본의 튐보다 크지 않다

    def test_no_stance_is_untouched(self):
        y = np.linspace(0, 1, 10)
        y2, segs = M.lock_foot(y, np.zeros(10, bool), 0.01, 3.0)
        self.assertTrue(np.allclose(y, y2))


class MapTests(unittest.TestCase):
    def test_map_covers_our_bones(self):
        mp = json.loads((HERE / "rig_configs" / "mocap_ual.json").read_text(encoding="utf-8"))
        ours = {mp["pelvis"][0]} | set(mp["rot"]) | set(mp["dir"]) | {"thigh_cr_l", "thigh_cr_r", "shin_cr_l", "shin_cr_r", "tarsal_cr_l", "tarsal_cr_r", "toe_cr_l", "toe_cr_r"}
        for b in ("pelvis_cr", "spine_cr_01", "spine_cr_02", "spine_cr_03", "neck_cr", "head_cr", "shoulder_cr_l", "shoulder_cr_r", "upper_arm_cr_l", "upper_arm_cr_r",
                  "forearm_cr_l", "forearm_cr_r", "hand_cr_l", "hand_cr_r"):
            self.assertIn(b, ours)
        self.assertEqual(set(mp["legs"]), {"l", "r"})
        self.assertEqual(set(mp["foot_dirs"]), {"l", "r"})

    def test_clips_config(self):
        d = json.loads((HERE / "rig_configs" / "mocap_clips.json").read_text(encoding="utf-8"))
        for name in ("run", "idle", "cast", "hit", "death", "dodge"):      # 게임이 부르는 이름 여섯이 모두 있다
            self.assertIn(name, d["clips"])
        self.assertTrue(d["clips"]["run"]["lock"] and d["clips"]["run"]["loop"])
        self.assertAlmostEqual(d["clips"]["run"]["seconds"], 0.65, places=2)       # 계약 0.6~0.65초


if __name__ == "__main__":
    unittest.main(verbosity=2)
