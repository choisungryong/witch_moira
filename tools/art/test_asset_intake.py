#!/usr/bin/env python3
"""asset_intake.py 자체 검사. 시험용 GLB를 코드로 만들어 쓴다. 임시 파일은 시스템 임시 폴더에만 둔다.

  python tools/art/test_asset_intake.py
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asset_intake as ai  # noqa: E402


def _png(w: int, h: int) -> bytes:
    def chunk(t: bytes, d: bytes) -> bytes:
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x00\x00\x00" * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def build_glb(with_time_max: bool = True) -> bytes:
    """메시 하나, 프리미티브 둘(인덱스 삼각형 4개 / 스트립 5정점 = 삼각형 3개), 재질 2, 스킨(뼈 3), 클립 1(1.5초), PNG 4x8."""
    blob = bytearray()
    views = []

    def add(data: bytes) -> int:
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        blob.extend(data)
        return len(views) - 1

    pos_a = add(struct.pack("<" + "f" * 18, *([0.0] * 18)))          # 6 정점
    idx_a = add(struct.pack("<12H", 0, 1, 2, 2, 1, 3, 3, 1, 4, 4, 1, 5))  # 12 인덱스 = 삼각형 4
    pos_b = add(struct.pack("<" + "f" * 15, *([0.0] * 15)))          # 5 정점(스트립)
    times = add(struct.pack("<3f", 0.0, 0.5, 1.5))
    png = add(_png(4, 8))
    accessors = [
        {"bufferView": pos_a, "componentType": 5126, "count": 6, "type": "VEC3"},
        {"bufferView": idx_a, "componentType": 5123, "count": 12, "type": "SCALAR"},
        {"bufferView": pos_b, "componentType": 5126, "count": 5, "type": "VEC3"},
        {"bufferView": times, "componentType": 5126, "count": 3, "type": "SCALAR"},
    ]
    if with_time_max:
        accessors[3]["max"] = [1.5]
        accessors[3]["min"] = [0.0]
    doc = {
        "asset": {"version": "2.0", "generator": "test"},
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": accessors,
        "materials": [{"name": "a"}, {"name": "b"}, {"name": "unused"}],
        "meshes": [{"name": "m", "primitives": [
            {"attributes": {"POSITION": 0}, "indices": 1, "material": 0},
            {"attributes": {"POSITION": 2}, "mode": 5, "material": 1},
        ]}],
        "nodes": [{"mesh": 0, "skin": 0}, {}, {}, {}],
        "skins": [{"joints": [1, 2, 3]}],
        "images": [{"bufferView": png, "mimeType": "image/png", "name": "tex"}],
        "animations": [{"name": "run", "samplers": [{"input": 3, "output": 3}], "channels": [{"sampler": 0, "target": {"node": 1, "path": "translation"}}]}],
    }
    j = json.dumps(doc).encode("utf-8")
    j += b" " * ((4 - len(j) % 4) % 4)
    b = bytes(blob) + b"\x00" * ((4 - len(blob) % 4) % 4)
    body = struct.pack("<II", len(j), 0x4E4F534A) + j + struct.pack("<II", len(b), 0x004E4942) + b
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


class IntakeTests(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.tmp = Path(self._td.name)

    def tearDown(self):
        self._td.cleanup()

    def test_inspect_counts(self):
        f = self.tmp / "t.glb"
        f.write_bytes(build_glb())
        r = ai.inspect_glb(f)
        m = r["metrics"]
        self.assertEqual(m["triangles"], 4 + 3)
        self.assertEqual(m["vertices"], 11)
        self.assertEqual(m["materials"], 2)  # 선언은 3, 쓰이는 것은 2
        self.assertEqual(r["detail"]["materials_declared"], 3)
        self.assertEqual(r["detail"]["surfaces"], 2)
        self.assertEqual(m["bones"], 3)
        self.assertEqual(m["clips"], 1)
        self.assertEqual(r["detail"]["clips"][0]["name"], "run")
        self.assertAlmostEqual(r["detail"]["clips"][0]["seconds"], 1.5)
        self.assertEqual(m["texture_max_px"], 8)
        self.assertEqual(m["texture_pixels_total"], 32)

    def test_clip_length_without_accessor_max(self):
        f = self.tmp / "t.glb"
        f.write_bytes(build_glb(with_time_max=False))
        self.assertAlmostEqual(ai.inspect_glb(f)["detail"]["clips"][0]["seconds"], 1.5)

    def test_read_only(self):
        f = self.tmp / "t.glb"
        f.write_bytes(build_glb())
        before = hashlib.sha256(f.read_bytes()).hexdigest()
        ai.inspect_glb(f)
        self.assertEqual(before, hashlib.sha256(f.read_bytes()).hexdigest())
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()), ["t.glb"])

    def test_bad_files(self):
        bad = self.tmp / "bad.glb"
        bad.write_bytes(b"NOPE" + b"\x00" * 40)
        with self.assertRaises(ai.GlbError):
            ai.read_glb(bad)
        good = build_glb()
        bad.write_bytes(good[: len(good) // 2])
        with self.assertRaises(ai.GlbError):
            ai.read_glb(bad)
        self.assertEqual(ai.main([str(bad)]), 2)

    def test_judge(self):
        budget = {"profiles": {"p": {"metrics": {
            "triangles": {"limit": 5, "reference": 4, "basis": []},
            "vertices": {"limit": 11, "reference": None, "basis": []},
            "materials": {"limit": None, "reference": None, "basis": []},
        }}}}
        rows = {r["metric"]: r for r in ai.judge({"triangles": 7, "vertices": 11, "materials": 2, "bones": 3}, budget, "p")}
        self.assertEqual(rows["triangles"]["status"], "초과")
        self.assertEqual(rows["triangles"]["ratio_to_reference"], 1.75)
        self.assertEqual(rows["vertices"]["status"], "통과")
        self.assertEqual(rows["materials"]["status"], "기준 없음")
        self.assertEqual(rows["bones"]["status"], "기준 없음")  # 예산표에 항목이 없어도 통과로 치지 않는다
        with self.assertRaises(KeyError):
            ai.judge({}, budget, "nope")

    def test_real_budget_file(self):
        b = ai.load_budget(ai.DEFAULT_BUDGET)
        self.assertIn("enemy", b["profiles"])
        for name, prof in b["profiles"].items():
            self.assertEqual(set(prof["metrics"]), set(ai.METRIC_LABEL), name)
            for key, e in prof["metrics"].items():
                for s in e["basis"]:
                    self.assertIn(s, b["sources"], f"{name}.{key}의 근거 {s}가 sources에 없다")
                if e["limit"] is None and e["reference"] is None:
                    self.assertTrue(e["note"], "기준이 없으면 note에 이유를 적는다")

    def test_attribution_template_and_init(self):
        d = self.tmp / "m"
        d.mkdir()
        self.assertEqual(ai.main(["--init-attribution", str(d)]), 0)
        att = d / "ATTRIBUTION.ko.md"
        text = att.read_text(encoding="utf-8")
        self.assertNotIn("\r", text)
        codes = {h["code"] for h in ai.check_attribution(att)}
        self.assertIn("TEMPLATE_UNFILLED", codes)
        self.assertIn("NO_SOURCE_URL", codes)
        self.assertIn("NO_LICENSE", codes)
        att.write_text("내가 고친 내용\n", encoding="utf-8")
        ai.main(["--init-attribution", str(d)])
        self.assertEqual(att.read_text(encoding="utf-8"), "내가 고친 내용\n")  # 덮어쓰지 않는다

    def test_attribution_refs(self):
        d = self.tmp / "v02"
        d.mkdir()
        att = d / "ATTRIBUTION.ko.md"
        att.write_text("# x\n원작: A, https://example.org/a. 라이선스: CC0. 2026-11-01에 받음. SHA-256 00.\n"
                       "../v01/ATTRIBUTION.ko.md 와 SOURCE.json 참조. C:/no/such/dir/x 에 보존.\n", encoding="utf-8")
        holes = ai.check_attribution(att)
        msgs = [(h["code"], h["message"]) for h in holes]
        self.assertTrue(any(c == "REF_MISSING" and "../v01/ATTRIBUTION.ko.md" in m for c, m in msgs))
        self.assertTrue(any(c == "REF_MISSING" and "SOURCE.json" in m for c, m in msgs))
        self.assertTrue(any(c == "OUTSIDE_REPO_MISSING" for c, m in msgs))
        self.assertFalse(any(c in ("NO_SOURCE_URL", "NO_LICENSE", "NO_DATE") for c, m in msgs))
        (d.parent / "v01").mkdir()
        (d.parent / "v01" / "ATTRIBUTION.ko.md").write_text("x", encoding="utf-8")
        (d / "SOURCE.json").write_text("{}", encoding="utf-8")
        codes = [h["code"] for h in ai.check_attribution(att)]
        self.assertNotIn("REF_MISSING", codes)

    def test_scan(self):
        root = self.tmp / "art"
        (root / "ok").mkdir(parents=True)
        (root / "bare").mkdir()
        (root / "ok" / "m.glb").write_bytes(build_glb())
        (root / "bare" / "n.glb").write_bytes(build_glb())
        (root / "ok" / "ATTRIBUTION.ko.md").write_text(
            "원작: A https://example.org/a CC0 2026-11-01 SHA-256 00\n", encoding="utf-8")
        res = ai.scan(root)
        by = {Path(m["glb"]).name: m for m in res["models"]}
        self.assertEqual(by["m.glb"]["holes"], [])
        self.assertEqual(by["m.glb"]["stats"]["triangles"], 7)
        self.assertEqual(by["n.glb"]["holes"][0]["code"], "NO_ATTRIBUTION")
        self.assertEqual(ai.count_errors(res), 1)
        self.assertEqual(ai.main(["--scan", str(root), "--strict"]), 1)
        self.assertEqual(ai.main(["--scan", str(root)]), 0)

    def test_cli_glb_strict_over_budget(self):
        f = self.tmp / "t.glb"
        f.write_bytes(build_glb())
        b = self.tmp / "b.json"
        b.write_text(json.dumps({"profiles": {"enemy": {"metrics": {"triangles": {"limit": 3, "reference": None, "basis": []}}}}}),
                     encoding="utf-8")
        self.assertEqual(ai.main([str(f), "--budget", str(b), "--strict"]), 1)
        self.assertEqual(ai.main([str(f), "--budget", str(b)]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
