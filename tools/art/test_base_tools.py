#!/usr/bin/env python3
"""기본 몸 길(base_bake: 맞춤·래스터, base_build: 뼈 이름 규칙) 자체 검사. Blender 없이 돈다.

  python tools/art/test_base_tools.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402

import base_bake as B  # noqa: E402
import base_build as U  # noqa: E402


class FitTests(unittest.TestCase):
    def test_zmap_piecewise_and_extrapolation(self):
        f = B.build_zmap([0, 1, 2], [0, 2, 3])
        self.assertAlmostEqual(float(f(0.5)), 1.0)
        self.assertAlmostEqual(float(f(1.5)), 2.5)
        self.assertAlmostEqual(float(f(3.0)), 4.0)      # 끝 밖은 기울기 1
        self.assertAlmostEqual(float(f(-0.5)), -0.5)

    def test_group_of(self):
        self.assertEqual(B.group_of("Head"), "head")
        self.assertEqual(B.group_of("upperarm_l"), "arm")
        self.assertEqual(B.group_of("index_02_r"), "hand")
        self.assertEqual(B.group_of("calf_r"), "leg_r")
        self.assertEqual(B.group_of("spine_02"), "body")

    def test_fit_scales_width_to_target(self):
        rng = np.random.RandomState(1)
        z = rng.rand(400) * 1.0
        P = np.stack([rng.uniform(-0.2, 0.2, 400), rng.uniform(-0.1, 0.1, 400), z], 1)
        T = np.stack([rng.uniform(-0.3, 0.3, 400), rng.uniform(-0.1, 0.1, 400), z], 1)           # 목표는 x 폭이 1.5배
        groups = np.array(["body"] * 400)
        zbins = np.arange(0, 1.0, 0.05)
        zc, fit = B.fit_regions(P, groups, {"torso": T}, zbins)
        Q = B.apply_fit(P, groups, lambda zz: zz, zc, fit, 1.0)
        self.assertGreater(float(Q[:, 0].max()), float(P[:, 0].max()) * 1.3)
        self.assertAlmostEqual(float(Q[:, 2].max()), float(P[:, 2].max()))                       # z는 함수만 따른다

    def test_thin_arms_keeps_length(self):
        t = np.linspace(0, 1, 60)
        P = np.stack([0.2 + t * 0.5, np.cos(t * 20) * 0.04, np.sin(t * 20) * 0.04 - t * 0.2], 1)
        G = np.array(["arm"] * 60)
        Q = B.thin_arms(P, G, 0.5)
        self.assertLess(float(np.ptp(Q[:, 1])), float(np.ptp(P[:, 1])) * 0.8)
        self.assertAlmostEqual(float(np.ptp(Q[:, 0])), float(np.ptp(P[:, 0])), places=1)


class RasterTests(unittest.TestCase):
    def test_triangle_covers_texels_with_positions(self):
        verts = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], float)
        nrm = np.tile([0, 0, 1.0], (3, 1))
        tris = np.array([[0, 1, 2]])
        uv = np.array([[[0.1, 0.1], [0.9, 0.1], [0.1, 0.9]]])
        tex = B.rasterize_uv(verts, nrm, tris, uv, np.array(["body"] * 3), 64, {"body": 0})
        self.assertGreater(len(tex["ix"]), 800)
        self.assertTrue((tex["P"][:, 0] >= -0.05).all() and (tex["P"][:, 0] <= 1.05).all())
        self.assertTrue(np.allclose(tex["N"], [0, 0, 1], atol=1e-6))


class NameTests(unittest.TestCase):
    def test_our_bone_names(self):
        self.assertEqual(U.our_name("root"), "origin")
        self.assertEqual(U.our_name("pelvis"), "pelvis_cr")
        self.assertEqual(U.our_name("Head"), "head_cr")
        self.assertEqual(U.our_name("upperarm_r"), "upper_arm_cr_r")
        self.assertEqual(U.our_name("middle_01_r"), "finger_middle.01.r")      # 게임이 지팡이를 붙이는 뼈
        self.assertEqual(U.our_name("thumb_02_l"), "thumb.02.l")
        self.assertTrue(U.our_name("index_04_leaf_l").startswith("finger_index."))
        names = {U.OUR[k] for k in U.OUR}
        for must in ("pelvis_cr", "spine_cr_01", "spine_cr_02", "spine_cr_03", "neck_cr", "head_cr", "hand_cr_r", "tarsal_cr_l", "toe_cr_r", "origin"):
            self.assertIn(must, names)


if __name__ == "__main__":
    unittest.main(verbosity=2)
