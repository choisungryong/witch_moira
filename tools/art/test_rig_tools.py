#!/usr/bin/env python3
"""rig_* 도구 자체 검사. Blender 없이 도는 부분이 기본이다(tools-selftest에 걸린다).

  python tools/art/test_rig_tools.py                      # Blender 필요 없는 검사만
  RIG_BLENDER_TESTS=1 python tools/art/test_rig_tools.py   # Blender 5.3이 필요한 끝에서 끝까지 검사도 돌림(약 1~2분)

Blender가 필요한 검사는 기본에서 '건너뜀'으로 표시된다(통과로 세지 않는다).
임시 파일은 시스템 임시 폴더에만 둔다.
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import rig_check  # noqa: E402
import rig_common as rc  # noqa: E402

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None

BONES = rig_check.STANDARD_BONES


# ------------------------------------------------------------------ 합성 glb

def build_rigged_glb(path: Path, bones=None, clip_lengths=None, weight_sum=1.0, tex=True, height=2.0, toe_forward=True):
    bones = bones if bones is not None else BONES
    lengths = clip_lengths or {"idle": 1.2, "run": 0.6, "cast": 0.6, "hit": 0.3, "death": 0.9, "dodge": 0.5}
    blob = bytearray()
    views = []

    def add(data: bytes) -> int:
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        blob.extend(data)
        return len(views) - 1

    nv = 4
    pos = [(-0.1, 0.0, 0.0), (0.1, 0.0, 0.0), (0.0, height, 0.0), (0.0, height / 2, 0.1)]
    pos_v = add(struct.pack("<12f", *[c for p in pos for c in p]))
    idx_v = add(struct.pack("<6H", 0, 1, 2, 0, 2, 3))
    joints_v = add(struct.pack("<16B", *([0, 0, 0, 0] * nv)))
    w = [weight_sum, 0.0, 0.0, 0.0] * nv
    weights_v = add(struct.pack("<16f", *w))
    accessors = [
        {"bufferView": pos_v, "componentType": 5126, "count": nv, "type": "VEC3", "min": [-0.1, 0, 0], "max": [0.1, height, 0.1]},
        {"bufferView": idx_v, "componentType": 5123, "count": 6, "type": "SCALAR"},
        {"bufferView": joints_v, "componentType": 5121, "count": nv, "type": "VEC4"},
        {"bufferView": weights_v, "componentType": 5126, "count": nv, "type": "VEC4"},
    ]
    nodes = []
    index = {}
    for b in bones:
        index[b] = len(nodes)
        nodes.append({"name": b, "translation": [0, 0, 0]})
    for b in bones:
        p = rc.BONE_PARENT.get(b)
        if p in index:
            nodes[index[p]].setdefault("children", []).append(index[b])
    if "tarsal_cr_l" in index:
        nodes[index["tarsal_cr_l"]]["translation"] = [0.2, 0.1, 0.0]
    if "toe_cr_l" in index:
        nodes[index["toe_cr_l"]]["translation"] = [0, -0.05, 0.15 if toe_forward else -0.15]
    root = len(nodes)
    nodes.append({"name": "mesh", "mesh": 0, "skin": 0})
    anims = []
    for name, sec in lengths.items():
        tv = add(struct.pack("<2f", 0.0, sec))
        accessors.append({"bufferView": tv, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0.0], "max": [sec]})
        ti = len(accessors) - 1
        rv = add(struct.pack("<8f", 0, 0, 0, 1, 0, 0, 0, 1))
        accessors.append({"bufferView": rv, "componentType": 5126, "count": 2, "type": "VEC4"})
        anims.append({"name": name, "samplers": [{"input": ti, "output": len(accessors) - 1}],
                      "channels": [{"sampler": 0, "target": {"node": index.get("origin", 0), "path": "rotation"}}]})
    mat = {"name": "m", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}} if tex else {"baseColorFactor": [1, 0, 0, 1]}}
    doc = {
        "asset": {"version": "2.0"}, "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors,
        "nodes": nodes, "scenes": [{"nodes": [index[bones[0]], root]}], "scene": 0,
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "JOINTS_0": 2, "WEIGHTS_0": 3}, "indices": 1, "material": 0}]}],
        "skins": [{"joints": list(index.values())}], "animations": anims, "materials": [mat],
    }
    if tex:
        doc["textures"] = [{"source": 0}]
        doc["images"] = [{"uri": "x.png"}]
    j = json.dumps(doc).encode()
    j += b" " * (-len(j) % 4)
    b = bytes(blob) + b"\x00" * (-len(blob) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(j) + 8 + len(b))
    out += struct.pack("<II", len(j), 0x4E4F534A) + j + struct.pack("<II", len(b), 0x004E4942) + b
    path.write_bytes(out)


class Args:
    bones = None
    require_dodge = False
    max_tris = 15000
    hard_tris = 20000
    scale = 1.32
    slot = None


def verdicts(res, item):
    return [r["verdict"] for r in res["rows"] if r["item"].startswith(item)]


class CheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="rigchk_"))

    def check(self, **kw):
        p = self.tmp / "t.glb"
        build_rigged_glb(p, **kw)
        return rig_check.check_glb(p, Args())

    def test_good_file_passes(self):
        res = self.check(height=2.0)
        bad = [r for r in res["rows"] if r["verdict"] == rig_check.BAD]
        self.assertEqual(bad, [], bad)
        self.assertEqual(res["metrics"]["bones"], 24)
        self.assertEqual(res["metrics"]["clips"], 6)

    def test_missing_bone_fails(self):
        res = self.check(bones=[b for b in BONES if b != "hand_cr_r"])
        self.assertIn(rig_check.BAD, verdicts(res, "뼈 이름"))

    def test_short_clip_fails(self):
        res = self.check(clip_lengths={"idle": 1.2, "run": 0.4, "cast": 0.6, "hit": 0.3, "death": 0.9})
        self.assertIn(rig_check.BAD, verdicts(res, "클립 run"))
        self.assertIn(rig_check.NOTE, verdicts(res, "클립 dodge"))     # 회피는 없어도 주의일 뿐

    def test_long_clip_is_note(self):
        res = self.check(clip_lengths={"idle": 1.225, "run": 0.625, "cast": 0.6, "hit": 0.3, "death": 0.9, "dodge": 0.5})
        self.assertEqual(verdicts(res, "클립 idle"), [rig_check.OK])
        res = self.check(clip_lengths={"idle": 2.0, "run": 0.6, "cast": 0.6, "hit": 0.3, "death": 0.9, "dodge": 0.5})
        self.assertEqual(verdicts(res, "클립 idle"), [rig_check.NOTE])

    def test_unweighted_fails(self):
        res = self.check(weight_sum=0.0)
        self.assertIn(rig_check.BAD, verdicts(res, "가중치"))

    def test_no_texture_fails(self):
        res = self.check(tex=False)
        self.assertIn(rig_check.BAD, verdicts(res, "색 텍스처"))

    def test_backwards_foot_fails(self):
        res = self.check(toe_forward=False)
        self.assertIn(rig_check.BAD, verdicts(res, "방향"))

    def test_height_scale_note(self):
        res = self.check(height=0.5)
        self.assertIn(rig_check.NOTE, verdicts(res, "키"))

    def test_cli_exit_codes(self):
        p = self.tmp / "t.glb"
        build_rigged_glb(p)
        self.assertEqual(rig_check.main([str(p)]), 0)
        build_rigged_glb(p, bones=[b for b in BONES if b != "head_cr"])
        self.assertEqual(rig_check.main([str(p)]), 1)
        (self.tmp / "bad.glb").write_bytes(b"nope")
        self.assertEqual(rig_check.main([str(self.tmp / "bad.glb")]), 2)


# ------------------------------------------------------------------ 설정과 순수 계산

class ConfigTests(unittest.TestCase):
    def test_default_config_complete(self):
        cfg = rc.load_config(None)
        for k in ("mesh", "proportions", "weights", "clips", "stretch"):
            self.assertIn(k, cfg)
        self.assertEqual(cfg["clips"]["lengths"]["run"], 0.6)
        self.assertEqual(len(rc.BONE_ORDER), 24)
        self.assertEqual(set(rc.BONE_PARENT), set(rc.BONE_ORDER))

    def test_user_config_overrides(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.json"
            p.write_text(json.dumps({"weights": {"power": 2.0}, "proportions": {"pelvis_z": 0.6}}), encoding="utf-8")
            cfg = rc.load_config(str(p))
            self.assertEqual(cfg["weights"]["power"], 2.0)
            self.assertEqual(cfg["weights"]["cutoff"], 1.9)     # 덮지 않은 값은 기본 그대로
            self.assertEqual(cfg["proportions"]["pelvis_z"], 0.6)

    def test_parts_demo_and_profiles_json(self):
        demo = json.loads((HERE / "rig_configs" / "parts_demo.json").read_text(encoding="utf-8"))
        for p in demo["parts"]:
            self.assertIn(p["bone"], rc.BONE_ORDER)
            self.assertIn("name", p)
        prof = json.loads((HERE / "rig_configs" / "reduce_profiles.json").read_text(encoding="utf-8"))
        self.assertLess(prof["profiles"]["game"]["triangles"], 15001)
        self.assertGreater(prof["profiles"]["showcase"]["triangles"], prof["profiles"]["game"]["triangles"])


def box(a, b, w):
    a, b = np.array(a, float), np.array(b, float)
    d = (b - a) / np.linalg.norm(b - a)
    t = np.array([0, 1.0, 0]) if abs(d[1]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(d, t)
    u /= np.linalg.norm(u)
    v = np.cross(d, u)
    verts = [p + s1 * u * w[0] / 2 + s2 * v * w[1] / 2 for p in (a, b) for s1 in (-1, 1) for s2 in (-1, 1)]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, quads


def stick_figure(height=1.8):
    """상자로 만든 사람꼴(A자세, 정면 -Y). 반환: (정점 N×3, 면 목록)."""
    H = height
    V, F = [], []

    def add(a, b, w):
        verts, quads = box(a, b, w)
        base = len(V)
        V.extend(verts)
        F.extend([[base + i for i in q] for q in quads])
    add((0, 0, 0.9 * H * 0.55), (0, 0, 0.82 * H), (0.34, 0.2))      # 몸통
    add((0, 0, 0.84 * H), (0, 0, 0.97 * H), (0.18, 0.18))            # 머리
    for s in (1, -1):
        add((s * 0.2, 0, 0.8 * H), (s * 0.55, 0, 0.52 * H), (0.09, 0.09))   # 팔(A자세)
        add((s * 0.1, 0, 0.55 * H), (s * 0.12, 0, 0.06 * H), (0.13, 0.13))  # 다리
        add((s * 0.12, -0.05, 0.0), (s * 0.12, -0.2, 0.04 * H * 0.6), (0.12, 0.05))  # 발(앞쪽 -Y)
    V = np.array(V)
    V[:, 2] -= V[:, 2].min()
    return V, F


@unittest.skipIf(np is None, "numpy 없음")
class BuildMathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import rig_build
        cls.rb = rig_build
        cls.cfg = rc.load_config(None)
        cls.P, cls.F = stick_figure()
        edges = set()
        for f in cls.F:
            for i in range(len(f)):
                a, b = f[i], f[(i + 1) % len(f)]
                edges.add((min(a, b), max(a, b)))
        cls.edges = np.array(sorted(edges))

    def kd(self, Pu, r):
        d = np.linalg.norm(Pu[:, None, :] - Pu[None, :, :], axis=2)
        s, t = np.where((d < r) & (d > 0))
        return s, t

    def test_measure_and_bones(self):
        m = self.rb.measure(self.P, self.cfg)
        self.assertAlmostEqual(m["height"], self.P[:, 2].max(), places=6)
        self.assertTrue(m["feet"]["l"]["found"] and m["feet"]["r"]["found"])
        self.assertGreater(m["hands"]["l"]["tip"][0], 0.3)
        self.assertLess(m["hands"]["r"]["tip"][0], -0.3)
        pos = self.rb.bone_positions(m, self.cfg)
        self.assertEqual(set(pos), set(rc.BONE_ORDER))
        for n, (h, t) in pos.items():
            self.assertTrue(np.all(np.isfinite(h)) and np.all(np.isfinite(t)), n)
        self.assertGreater(pos["thigh_cr_l"][0][0], 0)                  # 왼쪽 = +X
        self.assertLess(pos["shin_cr_l"][1][2], pos["thigh_cr_l"][0][2])  # 발목이 엉덩이보다 아래
        self.assertLess(pos["toe_cr_l"][1][1], pos["tarsal_cr_l"][0][1])  # 발끝이 앞(-Y)

    def test_weights(self):
        m = self.rb.measure(self.P, self.cfg)
        pos = self.rb.bone_positions(m, self.cfg)
        idx, w, names, _info = self.rb.compute_weights(self.P, self.edges, pos, self.cfg, self.kd)
        self.assertEqual(idx.shape, (len(self.P), 4))
        self.assertTrue(np.allclose(w.sum(axis=1), 1.0, atol=1e-6))          # 무가중치 0, 합 1
        self.assertTrue(((w > 1e-9).sum(axis=1) <= 4).all())
        top = np.array(names)[idx[np.arange(len(self.P)), 0]]
        head_i = np.where(self.P[:, 2] > 0.95 * self.P[:, 2].max())[0]
        self.assertTrue(all(top[i] == "head_cr" for i in head_i))
        # 오른발 정점이 왼다리 뼈를 주로 받지 않는다
        right_foot = np.where((self.P[:, 0] < -0.05) & (self.P[:, 2] < 0.05))[0]
        self.assertTrue(all(not top[i].endswith("_l") for i in right_foot))

    def test_override(self):
        cfg = rc.deep_merge(self.cfg, {"bone_overrides": {"head_cr": {"tail": [0, 0, 1.7]}}})
        m = self.rb.measure(self.P, cfg)
        pos = self.rb.bone_positions(m, cfg)
        self.assertAlmostEqual(float(pos["head_cr"][1][2]), 1.7)


# ------------------------------------------------------------------ Blender가 필요한 검사(기본에서 건너뜀)

@unittest.skipUnless(os.environ.get("RIG_BLENDER_TESTS") == "1" and Path(rc.blender_exe()).is_file() and np is not None,
                     "Blender 필요(RIG_BLENDER_TESTS=1): 끝에서 끝까지 시험을 건너뜀")
class BlenderEndToEnd(unittest.TestCase):
    def test_pipeline(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            P, F = stick_figure()
            obj = d / "fig.obj"
            # OBJ는 Y 위 -Z 정면이 기본 축이라 Blender(Z 위, -Y 정면)로 가져오면 같아지게 변환해 쓴다
            with obj.open("w") as fh:
                for x, y, z in P:
                    fh.write("v %f %f %f\n" % (x, z, -y))
                for f in F:
                    fh.write("f " + " ".join(str(i + 1) for i in f) + "\n")
            blend, glb = d / "r.blend", d / "r.glb"
            (d / "cfg.json").write_text(json.dumps({"mesh": {"min_vertices": 1}}), encoding="utf-8")
            py = [sys.executable, str(HERE / "rig_build.py"), "--in", str(obj), "--out-blend", str(blend), "--report", str(d / "b.json"), "--config", str(d / "cfg.json")]
            subprocess.run(py, check=True, capture_output=True, timeout=300)
            rep = json.loads((d / "b.json").read_text(encoding="utf-8"))
            self.assertEqual(rep["bones"], 24)
            self.assertEqual(rep["weights"]["unweighted_vertices"], 0)
            subprocess.run([sys.executable, str(HERE / "rig_clips.py"), "--blend", str(blend), "--out-glb", str(glb), "--report", str(d / "c.json"), "--fps", "30"],
                           check=True, capture_output=True, timeout=300)
            res = rig_check.check_glb(glb, Args())
            self.assertEqual(res["metrics"]["clips"], 6)
            self.assertEqual(verdicts(res, "클립 run"), [rig_check.OK])


if __name__ == "__main__":
    unittest.main(verbosity=1)
