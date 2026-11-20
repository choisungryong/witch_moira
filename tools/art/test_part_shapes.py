#!/usr/bin/env python3
"""part_shapes(부품 모양 생성기)와 char_paint(발광 가면) 자체 검사. Blender 없이 돈다(tools-selftest에 걸린다).

  python tools/art/test_part_shapes.py
"""
from __future__ import annotations

import sys
import unittest
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402

import char_board as B  # noqa: E402
import char_paint as P  # noqa: E402
import part_shapes as S  # noqa: E402


def edge_report(t):
    """방향 있는 모서리 기준: 같은 방향으로 두 번 쓰이는 모서리 수, 짝(반대 방향)이 없는 모서리 수."""
    c = Counter()
    for a, b, d in t:
        for u, v in ((a, b), (b, d), (d, a)):
            c[(int(u), int(v))] += 1
    dup = sum(1 for k, n in c.items() if n > 1)
    open_ = sum(1 for (u, v), n in c.items() if (v, u) not in c)
    return dup, open_


class ShapeTests(unittest.TestCase):
    def check_closed(self, kind, params=None, max_open=0):
        v, t = S.build(kind, params or {})
        a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
        self.assertTrue((np.linalg.norm(np.cross(b - a, c - a), axis=1) > 1e-12).all(), kind + ": 퇴화 삼각형")
        self.assertGreater(S.signed_volume(v, t), 0, kind + ": 법선이 안쪽")
        dup, open_ = edge_report(t)
        self.assertEqual(dup, 0, kind + ": 같은 방향 모서리 중복(감김 방향 섞임)")
        self.assertLessEqual(open_, max_open, kind + ": 열린 모서리")
        return v, t

    def test_fur_collar(self):
        v, t = self.check_closed("fur_collar")
        self.assertLess(len(t), 1500)
        self.assertGreater(v[:, 0].max(), 0.2)         # 어깨 폭

    def test_pauldron(self):
        v, t = self.check_closed("pauldron")
        self.assertLess(len(t), 900)

    def test_side_panel_and_hem(self):
        v, t = self.check_closed("side_panel")
        self.assertLess(v[:, 2].min(), -0.35)           # 허리띠 아래로 늘어짐
        self.check_closed("hem_tube")

    def test_torn_tapered_folded_panel_and_uv(self):
        prm = {"hem_teeth": 5, "teeth_depth": 0.07, "fold_n": 4, "fold_amp": 0.01, "rows": 8, "cols": 13, "w_top": 0.26, "w_bot": 0.12}
        v, t = self.check_closed("side_panel", prm)
        v2, t2, uv = S.build_uv("side_panel", prm)
        self.assertEqual(len(uv), len(v2))
        self.assertTrue(((uv >= 0) & (uv <= 1)).all())
        width = lambda z0, z1: float(np.ptp(v2[(v2[:, 2] > z0) & (v2[:, 2] < z1), 1]))
        self.assertLess(width(-0.45, -0.3), width(0.0, 0.06))        # 아래가 좁다
        for kind in ("fur_collar", "pauldron", "hem_tube"):
            a, b, u = S.build_uv(kind, {})
            self.assertEqual(len(u), len(a), kind)

    def test_part_textures(self):
        import part_textures as T
        for spec in ({"kind": "fur"}, {"kind": "cloth"}, {"kind": "gold"}):
            a = T.make(spec, 32)
            self.assertEqual(a.shape, (32, 32, 3))
            self.assertTrue(a.min() >= 0 and a.max() <= 1)
            self.assertGreater(float(a.std()), 0.03, spec["kind"])  # 민무늬가 아니다
        g = T.make({"kind": "gold", "glow": "#ff0000"}, 32)
        self.assertGreater(float(g[-2:, :, 0].mean()), float(g[-2:, :, 2].mean()))   # 아래(테두리)는 붉은 쪽
        with self.assertRaises(KeyError):
            T.make({"kind": "nope"})

    def test_scale_and_mirror(self):
        v, t = S.build("pauldron", {}, scale=0.98, mirror=True)
        v0, t0 = S.build("pauldron", {})
        self.assertAlmostEqual(float(v[:, 2].max()), float(v0[:, 2].max()) * 0.98, places=6)
        self.assertGreater(S.signed_volume(v, t), 0)
        self.assertAlmostEqual(float(v[:, 0].mean()), -float(v0[:, 0].mean()) * 0.98, places=6)

    def test_unknown_kind(self):
        with self.assertRaises(KeyError):
            S.build("nope", {})


class PaintTests(unittest.TestCase):
    def make(self):
        parts = [dict(name="arm_l", S=12), dict(name="torso", S=24)]
        place = [(10, 10, 60, 200), (100, 10, 80, 120)]
        return parts, place

    def test_hue_weight_picks_cyan_not_gold(self):
        a = np.zeros((2, 2, 3), np.float32)
        a[0, 0] = (0.2, 0.7, 0.9)    # 하늘색
        a[0, 1] = (0.8, 0.6, 0.2)    # 금색
        a[1, 0] = (0.5, 0.5, 0.5)    # 회색
        w = P.hue_weight(a, (178, 215), 0.4, 0.5)
        self.assertGreater(w[0, 0], 0.8)
        self.assertLess(w[0, 1], 0.05)
        self.assertLess(w[1, 0], 0.05)

    def test_hue_wrap_red(self):
        a = np.zeros((1, 2, 3), np.float32)
        a[0, 0] = (0.9, 0.1, 0.1)    # 빨강 0도
        a[0, 1] = (0.1, 0.9, 0.1)
        w = P.hue_weight(a, (350, 20), 0.4, 0.5)
        self.assertGreater(w[0, 0], 0.8)
        self.assertLess(w[0, 1], 0.05)

    def test_apply_bolts_mirror_and_mask_only_in_parts(self):
        parts, place = self.make()
        atlas = np.full((256, 256, 3), 0.3, np.float32)
        paint = {"bolts": [{"name": "v", "parts": ["arm_*"], "color": "#ffffff", "width_px": 6, "glow_px": 2,
                            "paths": [[[0.9, 0.05], [0.85, 0.5], [0.9, 0.95]]]}]}
        new, mask, st = P.apply(atlas, parts, place, paint)
        self.assertEqual(mask.shape, (256, 256, 3))
        self.assertGreater(int(mask[10:210, 10:70].max()), 200)          # 팔 사각형 안에서 켜짐
        self.assertEqual(int(mask[:, 100:].max()), 0)                    # 다른 부위(torso)에는 안 그림
        self.assertEqual(int(mask[:, :10].max()), 0)                     # 부위 밖은 검정
        self.assertTrue((new[10:210, 10:70] > 0.3).any())                # 알베도에도 칠함
        self.assertTrue(np.allclose(new[:, 100:], 0.3))

    def test_fill_only_bright_texels_in_selected_parts(self):
        parts, place = self.make()
        atlas = np.full((256, 256, 3), 0.1, np.float32)
        atlas[10:60, 10:70] = 0.8                                          # 팔 사각형의 위쪽은 밝은 살갗, 아래는 어두운 방어구
        new, mask, st = P.apply(atlas, parts, place, {"fill": [{"name": "g", "parts": ["arm_l"], "color": "#ff0000", "weight": 0.5, "val_min": 0.5}]})
        self.assertGreater(int(mask[30, 30, 0]), 100)
        self.assertEqual(int(mask[100, 30].max()), 0)                      # 어두운 곳은 안 켬
        self.assertEqual(int(mask[:, 100:].max()), 0)                      # 다른 부위 아님

    def test_wrap_path_crosses_seam(self):
        parts, place = self.make()
        shape = (256, 256)
        rect = P.part_rects(parts, place)["arm_l"]
        m = P.draw_paths(shape, rect, [[[0.98, 0.5], [1.06, 0.5]]], 4)    # s>1 이면 반대편 가장자리로 이어진다
        x0, y0, w, h, _ = rect
        row = m[y0 + h // 2, x0:x0 + w]
        self.assertGreater(row[:6].max(), 0.5)
        self.assertGreater(row[-6:].max(), 0.5)

    def test_tips_tint_end_only(self):
        parts = [dict(name="hair_lock_0", S=8)]
        place = [(0, 0, 40, 100)]
        atlas = np.full((128, 128, 3), 0.8, np.float32)
        new, mask, st = P.apply(atlas, parts, place, {"tips": {"parts": ["hair_lock_*"], "from_v": 0.5, "color": "#9b6cff", "mix": 0.8, "glow": 0.7}})
        self.assertTrue(np.allclose(new[10, 10], 0.8, atol=1e-3))        # 뿌리 쪽은 그대로
        self.assertGreater(abs(new[95, 10, 1] - 0.8), 0.2)               # 끝은 물듦
        self.assertEqual(int(mask[10, 10].max()), 0)
        self.assertGreater(int(mask[95, 10].max()), 80)


class BoardTests(unittest.TestCase):
    def test_slot_stats_hue_and_brightness(self):
        color = np.full((40, 90, 3), 0.1, np.float32)
        sil = np.zeros((40, 90), bool)
        for i, rgb in enumerate(((0.9, 0.5, 0.1), (0.6, 1.0, 1.0), (0.6, 0.3, 0.9))):   # 주황, 하늘, 보라
            sil[5:35, i * 30 + 5:i * 30 + 25] = True
            color[5:35, i * 30 + 5:i * 30 + 25] = rgb
        st = B.slot_stats(color, sil, ["ember", "frost", "storm"])
        self.assertGreater(st["ember"]["frac_hue_ember"], 0.95)
        self.assertLess(st["ember"]["frac_hue_frost"], 0.05)
        self.assertGreater(st["frost"]["frac_hue_frost"], 0.95)
        self.assertGreater(st["storm"]["frac_hue_storm"], 0.95)
        self.assertEqual(st["ember"]["pixels"], 30 * 20)
        self.assertEqual(st["ember"]["height_px"], 30)
        self.assertGreater(st["frost"]["frac_over_0.85"], 0.5)      # 밝은 하늘색 칸
        self.assertEqual(st["ember"]["frac_over_0.85"], 0.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
