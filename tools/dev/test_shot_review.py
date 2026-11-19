"""shot_review.py 자체 검사. 작은 그림을 코드로 만들어 지표를 확인한다.
  python tools/dev/test_shot_review.py
"""
import json
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shot_review as sr  # noqa: E402

W, H = 960, 540  # 1080p의 절반: 1080p 좌표는 0.5배로 환산된다
CFG = {k: (list(v) if isinstance(v, list) else v) for k, v in sr.DEFAULTS.items()}


def canvas(v=0):
    return np.full((H, W, 3), v, dtype=np.uint8)


class MeasureTest(unittest.TestCase):
    def test_flat_gray(self):
        m = sr.measure(canvas(128), CFG)
        self.assertAlmostEqual(m["lum_p50"], 128 / 255, places=3)
        self.assertAlmostEqual(m["white_pct"], 0.0)
        self.assertAlmostEqual(m["dark_pct"], 0.0)
        self.assertAlmostEqual(m["sat_mean"], 0.0)
        self.assertAlmostEqual(m["center_corner_ratio"], 1.0, places=3)
        self.assertEqual(m["white_blob_diam"], 0.0)

    def test_white_square_in_play_area(self):
        a = canvas(20)
        a[200:240, 300:340] = 255  # 40x40 화소 = 1080p 80x80
        m = sr.measure(a, CFG)
        self.assertAlmostEqual(m["white_blob_diam"], 80.0, places=3)
        self.assertAlmostEqual(m["white_blob_diam_eq"], np.sqrt(4 * 1600 / np.pi) * 2, delta=0.5)
        expected = 1600 / m["play_pixels"] * 100
        self.assertAlmostEqual(m["white_pct"], expected, places=3)

    def test_white_in_hud_is_ignored(self):
        a = canvas(20)
        a[500:540, 100:200] = 255  # 아래 HUD(1080p y>=900 => 450 이후)
        a[10:40, 800:900] = 255    # 위 HUD
        a[60:90, 800:900] = 255    # 오른쪽 위 제외 사각형(1080p 1500.., 0..200 => 750.., 0..100)
        m = sr.measure(a, CFG)
        self.assertEqual(m["white_pct"], 0.0)
        self.assertEqual(m["white_blob_diam"], 0.0)

    def test_largest_blob_chosen(self):
        a = canvas(0)
        a[200:210, 100:110] = 255
        a[250:300, 200:260] = 255  # 60 wide
        m = sr.measure(a, CFG)
        self.assertAlmostEqual(m["white_blob_diam"], 120.0, places=3)

    def test_blob_connectivity_is_4way(self):
        mask = np.zeros((10, 10), dtype=bool)
        mask[2, 2] = True
        mask[3, 3] = True  # 대각선: 이어지지 않는다
        d, _, area, _ = sr.largest_white_blob(mask)
        self.assertEqual((d, area), (1, 1))
        mask[3, 2] = True  # 이어짐
        d, _, area, _ = sr.largest_white_blob(mask)
        self.assertEqual((d, area), (2, 3))

    def test_blob_u_shape_merges(self):
        mask = np.zeros((10, 10), dtype=bool)
        mask[1:8, 1] = True
        mask[1:8, 5] = True
        mask[7, 1:6] = True  # 아래에서 이어지는 U
        d, _, area, _ = sr.largest_white_blob(mask)
        self.assertEqual(area, 7 + 7 + 3)
        self.assertEqual(d, 7)

    def test_crimson_share(self):
        a = canvas(0)
        a[200:300, 200:300] = (230, 20, 60)  # 진홍
        a[200:300, 400:500] = (60, 200, 60)  # 초록은 세지 않는다
        m = sr.measure(a, CFG)
        self.assertAlmostEqual(m["threat_pct"], 10000 / m["play_pixels"] * 100, places=3)

    def test_hero_white(self):
        a = canvas(0)
        # 주인공 자리 1080p (905,400)-(1015,575) => 절반 해상도 (452,200)-(507,287)
        a[200:287, 452:507] = 255
        m = sr.measure(a, CFG)
        self.assertGreater(m["hero_white_pct"], 95.0)

    def test_center_corner_ratio(self):
        a = canvas(50)
        a[200:300, 380:580] = 200  # 가운데
        m = sr.measure(a, CFG)
        self.assertGreater(m["center_corner_ratio"], 1.5)

    def test_scale_is_resolution_independent(self):
        small = canvas(20)
        small[200:240, 300:340] = 255
        big = np.kron(small, np.ones((2, 2, 1), dtype=np.uint8))  # 1920x1080
        self.assertAlmostEqual(sr.measure(small, CFG)["white_blob_diam"], sr.measure(big, CFG)["white_blob_diam"], places=3)

    def test_diff(self):
        a = canvas(100)
        b = canvas(100)
        b[200:300, 200:300] = 200  # 차 100 > 24
        b[300:310, 200:300] = 110  # 차 10, 세지 않는다
        s, d = sr.diff_stats(a, b, CFG)
        self.assertAlmostEqual(s["changed_pct"], 10000 / sr.play_mask(W, H, CFG)[0].sum() * 100, places=3)
        self.assertEqual(s["diff_max"], 100)
        s0, _ = sr.diff_stats(a, a, CFG)
        self.assertEqual(s0["changed_pct"], 0.0)


class LimitsTest(unittest.TestCase):
    def test_check(self):
        lim = {"white_pct": (None, 1.0), "lum_p50": (0.1, None), "x": (0, 1)}
        r = sr.check_limits({"white_pct": 2.0, "lum_p50": 0.05}, lim)
        self.assertEqual(r, {"white_pct": "high", "lum_p50": "low", "x": "none"})
        self.assertEqual(sr.check_limits({"white_pct": 0.5}, {"white_pct": (None, 1.0)}), {"white_pct": "ok"})

    def test_example_file_loads(self):
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_data", "shot_review_limits.example.json")
        lim = sr.load_limits(p)
        self.assertEqual(lim["white_pct"], (None, 1.0))


class EndToEndTest(unittest.TestCase):
    def test_compare_run(self):
        with tempfile.TemporaryDirectory() as t:
            b, a, out = (os.path.join(t, "b"), os.path.join(t, "a"), os.path.join(t, "_local", "out"))
            os.makedirs(b)
            os.makedirs(a)
            x = canvas(40)
            y = canvas(40)
            y[200:260, 300:360] = 255
            Image.fromarray(x).save(os.path.join(b, "s1.png"))
            Image.fromarray(y).save(os.path.join(a, "s1.png"))
            Image.fromarray(x).save(os.path.join(b, "only-before.png"))
            Image.fromarray(x[:100, :100].copy()).save(os.path.join(b, "s2.png"))
            Image.fromarray(x).save(os.path.join(a, "s2.png"))
            lim = os.path.join(t, "lim.json")
            with open(lim, "w", encoding="utf-8") as f:
                json.dump({"limits": {"white_pct": {"max": 0.5}}}, f)
            self.assertEqual(sr.main([b, a, "--out=" + out, "--limits=" + lim]), 0)
            with open(os.path.join(out, "metrics.json"), encoding="utf-8") as f:
                res = json.load(f)
            self.assertEqual(res["unpaired_before"], ["only-before"])
            self.assertEqual(res["images"]["s1"]["limits"]["white_pct"], "high")
            self.assertGreater(res["images"]["s1"]["diff"]["changed_pct"], 0)
            self.assertEqual(res["skipped"][0]["name"], "s2")
            for n in ("s1-cmp.png", "s1-gray.png", "s1-hero.png", "metrics.md"):
                self.assertTrue(os.path.exists(os.path.join(out, n)), n)
            with open(os.path.join(out, "metrics.md"), encoding="utf-8") as f:
                md = f.read()
            self.assertIn(sr.DISCLAIMER, md)
            self.assertIn("[높음]", md)
            self.assertIn("원거리 적의 지팡이 머리", md)

    def test_measure_only_and_out_guard(self):
        with tempfile.TemporaryDirectory() as t:
            b = os.path.join(t, "b")
            os.makedirs(b)
            Image.fromarray(canvas(40)).save(os.path.join(b, "s1.png"))
            with self.assertRaises(SystemExit):
                sr.main([b, "--out=" + os.path.join(t, "out")])
            out = os.path.join(t, "_local", "o")
            self.assertEqual(sr.main([b, "--out=" + out]), 0)
            self.assertFalse(os.path.exists(os.path.join(out, "s1-cmp.png")))
            self.assertTrue(os.path.exists(os.path.join(out, "s1-gray.png")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
