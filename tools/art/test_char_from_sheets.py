#!/usr/bin/env python3
"""char_from_sheets / char_geom 자체 검사. Blender 필요 없는 부분이 기본이다(tools-selftest에 걸린다).

  python tools/art/test_char_from_sheets.py                         # Blender 없이 도는 검사
  RIG_BLENDER_TESTS=1 python tools/art/test_char_from_sheets.py     # 그림이 있으면 냉기 마녀를 끝까지(약 2분) 돌려 rig_check까지

Blender가 필요하거나 그림(_local/, git 밖)이 필요한 검사는 건너뜀으로 표시된다(통과로 세지 않는다).
임시 파일은 시스템 임시 폴더에만 둔다.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402

import char_from_sheets as C  # noqa: E402
import char_geom as G  # noqa: E402

CFG_DIR = HERE / "char_configs"


def blob(shape, cy, cx, ry, rx, value=200, base=None):
    im = np.full(shape + (3,), 110, np.uint8) if base is None else base.copy()
    yy, xx = np.mgrid[:shape[0], :shape[1]]
    m = ((yy - cy) / ry) ** 2 + ((xx - cx) / rx) ** 2 <= 1
    im[m] = value
    return im, m


class GeomTests(unittest.TestCase):
    def test_intervals(self):
        row = np.zeros(40, bool)
        row[3:9] = True; row[12:14] = True; row[30:35] = True
        self.assertEqual(G.intervals(row, gap=3), [(3, 8), (12, 13), (30, 34)])
        self.assertEqual(G.intervals(row, gap=5), [(3, 13), (30, 34)])
        self.assertEqual(G.intervals(np.zeros(5, bool)), [])

    def test_tube_is_closed_outward_and_counted(self):
        centers = np.array([[0, 0, z] for z in np.linspace(0, 1, 6)])
        pts = G.make_rings(centers, np.full(6, 0.1), np.full(6, 0.1), (0, 1, 0), 12)
        p = G.part_from_rings("t", pts, centers, (True, True))
        self.assertEqual(len(p["tris"]), 5 * 12 * 2 + 24)
        # 법선이 바깥(축에서 멀어지는 쪽)을 향한다
        side = p["normals"][:6 * 12].reshape(6, 12, 3)
        out = pts[:, :, :2] - centers[:, None, :2]
        self.assertGreater(float((side[:, :, :2] * out).sum(-1).min()), 0.0)
        self.assertEqual(p["uvg"].shape, (len(p["tris"]), 3, 2))

    def test_rows_side_sign(self):
        cfg = {"height": 2.0, "views": {"front": {"feet": 1000, "top": 0, "cx": 100}, "side": {"feet": 1000, "top": 0, "cx": 50, "az": -90},
                                        "back": {"feet": 1000, "top": 0, "cx": 100}}}
        R = G.Rows(cfg, {"front": {}, "side": {}, "back": {}})
        self.assertAlmostEqual(R.Yw(60), -(10) * R.ss)   # 얼굴이 그림 오른쪽인 측면은 부호가 뒤집힌다
        cfg["views"]["side"]["az"] = 90
        self.assertAlmostEqual(G.Rows(cfg, {"front": {}, "side": {}, "back": {}}).Yw(60), 10 * R.ss)
        self.assertAlmostEqual(R.Z(1000), 0.0)
        self.assertAlmostEqual(R.Z(0), 2.0)

    def test_head_taper_narrows_to_neck(self):
        cfg = json.loads((CFG_DIR / "frost.json").read_text(encoding="utf-8"))
        rows = {v: {y: [(380, 640)] for y in range(1536)} for v in ("front", "side", "back")}
        R = G.Rows(cfg, rows)
        head = G.build_head(R, cfg)
        ring = head["ring_pts"]
        widths = np.ptp(ring[:, :, 0], axis=1)
        self.assertLess(widths[-1], widths.max() * 0.7)


class CameraTests(unittest.TestCase):
    def test_project_axes(self):
        cam = C.Cam(0, 100, 50, 200, (100, 300))
        px, py, d = cam.project(np.array([[0.1, 0.0, 0.5]]))
        self.assertAlmostEqual(px[0], 60.0); self.assertAlmostEqual(py[0], 150.0)
        cam90 = C.Cam(90, 100, 50, 200, (100, 300))   # +X에서 본다: 이미지 오른쪽 = +Y(뒤)
        px, _, d = cam90.project(np.array([[0.2, 0.1, 0.0]]))
        self.assertAlmostEqual(px[0], 60.0); self.assertAlmostEqual(d[0], 0.2)
        cam_m = C.Cam(-90, 100, 50, 200, (100, 300))  # -X에서 본다: 이미지 오른쪽 = -Y(앞)
        px, _, _ = cam_m.project(np.array([[0.0, -0.1, 0.0]]))
        self.assertAlmostEqual(px[0], 60.0)

    def test_fit_cam_recovers_shift_and_scale(self):
        rng = np.random.RandomState(0)
        th = rng.uniform(0, 2 * np.pi, 400000); z = rng.uniform(0, 1.8, 400000)
        pts = np.stack([0.18 * np.cos(th), 0.1 * np.sin(th), z], 1)
        truth = C.Cam(-25, 700, 300, 1550, (600, 1600))
        px, py, _ = truth.project(pts)
        mask = np.zeros((1600, 600), bool)
        mask[np.clip(py.astype(int), 0, 1599), np.clip(px.astype(int), 0, 599)] = True
        from scipy import ndimage as ndi
        mask = ndi.binary_fill_holes(ndi.binary_closing(mask, iterations=3))
        cam, iou = C.fit_cam(pts, mask, C.Cam(-15, 680, 310, 1540, (600, 1600)), free=("az", "s", "cx", "cy"), f=4)
        self.assertGreater(iou, 0.9)
        self.assertAlmostEqual(cam.s, 700, delta=25)
        self.assertAlmostEqual(cam.cx, 300, delta=10)


class ImageTests(unittest.TestCase):
    def test_figure_mask_trim_window(self):
        im, m = blob((200, 120), 100, 60, 70, 20)
        im[:, :3] = 20                      # 칸막이 선
        im2, _ = blob((200, 120), 30, 108, 10, 8, base=im)   # 이웃 그림 조각
        mk = C.figure_mask(im2, 22, trim=5, window=(30, 100))
        self.assertTrue(mk[100, 60])
        self.assertFalse(mk[:, :5].any())
        self.assertFalse(mk[30, 108])

    def test_detect_eyes_prefers_upper_level_pair(self):
        im = np.full((300, 300, 3), 120, np.uint8)
        for (x, y) in ((100, 90), (160, 90), (80, 160), (190, 162)):
            im[y - 3:y + 4, x - 3:x + 4] = (110, 170, 230)
        e = C.detect_eyes(im, 0.9)
        self.assertEqual([(round(a), round(b)) for a, b in e], [(100, 90), (160, 90)])
        self.assertIsNone(C.detect_eyes(np.full((50, 50, 3), 120, np.uint8)))

    def test_flatten_identity_and_reduces_gradient(self):
        im = np.full((200, 200, 3), 120, np.uint8)
        grad = np.linspace(0.6, 1.4, 200)[None, :, None]
        im = np.clip(im * grad, 0, 255).astype(np.uint8)
        mask = np.ones((200, 200), bool)
        self.assertTrue((C.flatten_lighting(im, mask, 0) == im).all())
        out = C.flatten_lighting(im, mask, 1.0, clusters=2, clamp=(0.5, 2.0))
        self.assertLess(float(out[:, :, 0].std()), float(im[:, :, 0].std()))

    def test_sole_profile_toe_narrower(self):
        im = np.full((400, 300, 3), 120, np.uint8)
        yy, xx = np.mgrid[:400, :300]
        # 위가 뾰족한 밑창(발끝 위, 폭이 아래로 갈수록 커진다)
        half = np.clip((yy - 30) * 0.18, 0, 40)
        sole = (np.abs(xx - 80) <= half) & (yy > 30) & (yy < 380)
        im[sole] = 40
        with tempfile.TemporaryDirectory() as d:
            from PIL import Image
            Image.fromarray(im).save(Path(d) / "s.png")
            prof, aspect = C.sole_profile(Path(d) / "s.png", (0, 0, 300, 400))
        self.assertLess(prof[0], prof[-1])
        self.assertAlmostEqual(max(prof), 1.0)
        self.assertEqual(len(prof), 12)


class BakeTests(unittest.TestCase):
    def test_front_back_colours_and_arm_occlusion(self):
        # 몸통 관 하나를 정면(빨강)과 뒤(파랑) 그림으로 굽는다. 앞에 놓인 팔 관이 가리는 몸통 텍셀은 그 시점 색을 못 쓴다.
        cen = np.array([[0, 0, z] for z in np.linspace(0, 1, 12)])
        torso = G.part_from_rings("torso", G.make_rings(cen, np.full(12, 0.15), np.full(12, 0.1), (0, 1, 0), 16), cen, (True, True), "body")
        acen = np.array([[0.0, -0.14, z] for z in np.linspace(0.2, 0.8, 8)])
        arm = G.part_from_rings("arm_l", G.make_rings(acen, np.full(8, 0.05), np.full(8, 0.05), (0, 1, 0), 10), acen, (True, True), "arm")
        parts = [torso, arm]
        k, place = C.pack_uv(parts, 512)
        tex = C.texel_maps(parts, place)
        W, H = 200, 300
        red = np.zeros((H, W, 3), np.float32); red[...] = (1, 0, 0)
        blue = np.zeros((H, W, 3), np.float32); blue[...] = (0, 0, 1)
        full = np.ones((H, W), bool)
        views = [dict(name="front", cam=C.Cam(0, 200, 100, 280, (W, H)), img=red, mask=full),
                 dict(name="back", cam=C.Cam(180, 200, 100, 280, (W, H)), img=blue, mask=full)]
        atlas, st = C.bake_texture(parts, tex, views, 512, power=4.0, arm_px=7, tol=0.012, log=lambda *a: None)
        self.assertGreater(st["filled_fraction"], 0.2)
        P, N, part = tex["P"], tex["N"], tex["part"]
        col = atlas[tex["iy"], tex["ix"]]
        front_free = (part == 0) & (N[:, 1] < -0.9) & ((P[:, 2] < 0.15) | (P[:, 2] > 0.85))    # 팔(높이 0.2~0.8)에 안 가려진 앞쪽 텍셀
        back = (part == 0) & (N[:, 1] > 0.95)
        self.assertGreater(float(col[front_free][:, 0].mean()), 0.8)
        self.assertGreater(float(col[back][:, 2].mean()), 0.8)
        hidden = (part == 0) & (N[:, 1] < -0.95) & (np.abs(P[:, 0]) < 0.03) & (P[:, 2] > 0.3) & (P[:, 2] < 0.7)
        self.assertGreater(int(hidden.sum()), 20)
        # 팔에 가려진 곳은 정면 그림 색(빨강)이 아니라 이웃에서 이어 받은 색이어야 한다: 파랑이 섞이거나 어두워도 빨강 1.0은 아니다
        self.assertLess(float(col[hidden][:, 0].mean()), 0.95)


class ConfigTests(unittest.TestCase):
    def check_cfg(self, name):
        cfg = json.loads((CFG_DIR / name).read_text(encoding="utf-8"))
        for k in ("name", "height", "art_root", "views", "torso", "neck", "head", "arm", "leg"):
            self.assertIn(k, cfg, name)
        for v in ("front", "side", "back"):
            for k in ("image", "feet", "top", "cx"):
                self.assertIn(k, cfg["views"][v], "%s %s" % (name, v))
        t = cfg["torso"]
        n = len(t["key_y"])
        for k in ("key_half_width", "key_zf", "key_zb"):
            self.assertEqual(len(t[k]), n, "%s torso.%s" % (name, k))
        h = cfg["hip"] if "hip" in cfg else t["hip"]
        self.assertEqual({len(v) for v in h.values()}, {len(h["y"])}, name)
        nk = cfg["neck"]
        self.assertEqual({len(nk["y"]), len(nk["half_width"]), len(nk["half_depth"])}, {len(nk["y"])})
        if cfg.get("skirt"):
            for tier in cfg["skirt"]["tiers"]:
                self.assertEqual(len(tier["k_y"]), len(tier["k"]))
        return cfg

    def test_configs_have_consistent_tables(self):
        for f in sorted(CFG_DIR.glob("*.json")):
            self.check_cfg(f.name)

    def test_resolve_art_missing_is_reported(self):
        with self.assertRaises(FileNotFoundError):
            C.resolve_art({"art_root": "no/such/"}, "x.png")


class EndToEnd(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("RIG_BLENDER_TESTS") == "1", "RIG_BLENDER_TESTS=1 이 아니면 건너뜀(Blender와 그림이 필요)")
    def test_storm_all_stages(self):
        try:
            C.resolve_art({"art_root": "_local/art/3d-sheets/storm/"}, "hi3d-front.png")
        except FileNotFoundError:
            self.skipTest("그림(_local/art/3d-sheets/storm)이 없다")
        with tempfile.TemporaryDirectory() as d:
            r = subprocess.run([sys.executable, str(HERE / "char_from_sheets.py"), "--config", str(CFG_DIR / "storm.json"), "--work", d,
                                "--stage", "all", "--no-preview"], capture_output=True, text=True, encoding="utf-8", errors="replace")
            self.assertEqual(r.returncode, 0, r.stdout[-1500:] + r.stderr[-800:])
            self.assertTrue((Path(d) / "final.glb").is_file())


if __name__ == "__main__":
    unittest.main(verbosity=1)
