#!/usr/bin/env python3
"""slot_paths.py, asset_intake.py --slot, asset_ledger.py check의 자리표 대조(T7-2) 자체 검사.

표본 자리표(tools/art/test_data/asset_slots_sample.json)와 코드로 만든 작은 GLB·PNG·SVG를 임시 폴더에 놓고 돌린다.
실제 chapter1/art와 사용자 저장 폴더는 건드리지 않는다.

  python tools/art/test_slot_paths.py
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asset_intake as ai  # noqa: E402
import asset_ledger as led  # noqa: E402
import slot_paths  # noqa: E402

SAMPLE = Path(__file__).resolve().parent / "test_data" / "asset_slots_sample.json"
REAL_ROOT = Path(__file__).resolve().parents[2]


def rig_glb(joints: list[str], clips: dict[str, float]) -> bytes:
    """뼈 이름 목록과 클립(이름 -> 초)만 있는 작은 GLB(메시 없음)."""
    accessors = [{"componentType": 5126, "count": 2, "type": "SCALAR", "max": [secs], "min": [0.0]} for secs in clips.values()]
    doc = {
        "asset": {"version": "2.0", "generator": "test"},
        "nodes": [{"name": n} for n in joints],
        "skins": [{"joints": list(range(len(joints)))}],
        "accessors": accessors,
        "animations": [{"name": name, "samplers": [{"input": i, "output": i}], "channels": []} for i, name in enumerate(clips)],
    }
    j = json.dumps(doc).encode("utf-8")
    j += b" " * ((4 - len(j) % 4) % 4)
    body = struct.pack("<II", len(j), 0x4E4F534A) + j
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def png(w: int, h: int, alpha: bool = True) -> bytes:
    def chunk(t: bytes, d: bytes) -> bytes:
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    px = 4 if alpha else 3
    raw = b"".join(b"\x00" + b"\x10" * (w * px) for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


SHEET_META = {
    "schema": 1,
    "texture": "res://chapter1/art/samples/sheet.png",
    "directions": ["south", "north"],
    "states": {"idle": {}, "cast": {}},
    "frames": [
        {"region": [4, 0, 4, 4], "texture": "res://chapter1/art/samples/sheet.png", "direction": "south"},
        {"region": [0, 0, 4, 4], "texture": "samples/sheet_actions.png", "direction": "north"},
    ],
    "overlay": "samples/only_named_in_json.png",
}


def make_project(root: Path) -> Path:
    art = root / "chapter1" / "art"
    (art / "samples").mkdir(parents=True)
    shutil.copy(SAMPLE, art / "asset_slots.json")
    (art / "samples" / "rig.glb").write_bytes(rig_glb(["ORG-spine", "ORG-head", "hand.R"], {"idle": 1.0, "walk": 1.0}))
    (art / "samples" / "sheet.png").write_bytes(png(8, 4))
    (art / "samples" / "sheet_actions.png").write_bytes(png(8, 4))
    (art / "samples" / "only_named_in_json.png").write_bytes(png(2, 2))
    (art / "samples" / "sheet.json").write_text(json.dumps(SHEET_META), encoding="utf-8")
    (art / "samples" / "icon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"></svg>', encoding="utf-8")
    (root / "project.godot").write_text("", encoding="utf-8")
    return art


class SlotPathTests(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.root = Path(self._td.name)
        self.art = make_project(self.root)
        self.table, _ = slot_paths.load_slots(self.root)

    def tearDown(self):
        self._td.cleanup()

    def compare(self, sid, new=None):
        return ai.compare_slot(self.root, sid, self.table[sid], new)

    def verdicts(self, res):
        return {r["item"]: r["verdict"] for r in res["rows"]}

    # -- 읽기
    def test_repo_path(self):
        self.assertEqual(slot_paths.repo_path("a/b.png"), "chapter1/art/a/b.png")
        self.assertEqual(slot_paths.repo_path("res://chapter1/view/x.json"), "chapter1/view/x.json")
        self.assertIsNone(slot_paths.repo_path(""))

    def test_inherit_is_resolved_and_own_keys_win(self):
        twin = self.table["actor.sample.twin"]
        self.assertEqual(twin["file"], "samples/rig.glb")
        self.assertEqual(twin["contract"]["scale"], 2.0)
        self.assertEqual(twin["contract"]["bones"]["head"], "ORG-head")

    def test_refs_cover_file_meta_extra_and_skip_planned(self):
        refs = {(s, r, p) for s, r, p in slot_paths.slot_refs(self.root)}
        self.assertIn(("actor.sample.sheet", "meta", "chapter1/art/samples/sheet.json"), refs)
        self.assertIn(("actor.sample.sheet", "extra", "chapter1/art/samples/sheet_actions.png"), refs)
        self.assertIn(("actor.sample.twin", "file", "chapter1/art/samples/rig.glb"), refs)
        self.assertFalse([x for x in refs if x[0] == "ui.sample.planned"])

    def test_sidecar_and_audio_refs(self):
        side = slot_paths.sidecar_refs(self.root, "chapter1/art/samples/sheet.json")
        self.assertIn("chapter1/art/samples/only_named_in_json.png", side)   # art 기준 상대 경로
        self.assertIn("chapter1/art/samples/sheet_actions.png", side)
        (self.root / "chapter1" / "data").mkdir()
        (self.root / "chapter1" / "data" / "audio_map.json").write_text(
            json.dumps({"cues": {"hit": {"variants": ["audio/hit_a.wav", "audio/hit_b.ogg"]}}, "note": "x.wav is text"}), encoding="utf-8")
        cues = dict(slot_paths.audio_map_refs(self.root))
        self.assertEqual(cues["cues.hit.variants[1]"], "chapter1/art/audio/hit_b.ogg")
        refs = slot_paths.all_refs(self.root)
        self.assertIn("chapter1/art/audio/hit_a.wav", refs)
        self.assertTrue(any("sheet.json" in why for why in refs["chapter1/art/samples/only_named_in_json.png"]))

    def test_missing_or_broken_table_is_empty_not_a_crash(self):
        self.assertEqual(slot_paths.load_slots(self.root / "nowhere"), ({}, None))
        bad = self.root / "bad.json"
        bad.write_text("{", encoding="utf-8")
        table, err = slot_paths.load_slots(self.root, bad)
        self.assertEqual(table, {})
        self.assertTrue(err)

    # -- 넣기 전 대조(3.6의 1단계)
    def test_same_files_have_no_difference(self):
        for sid in ("actor.sample.model", "actor.sample.sheet", "actor.sample.twin", "icon.sample.square"):
            res = self.compare(sid)
            self.assertEqual(ai.count_verdicts(res)[ai.BAD], 0, (sid, res["rows"]))
            self.assertTrue(res["rows"], sid)
        self.assertEqual(self.compare("ui.sample.planned")["rows"], [])

    def test_renamed_bone_is_the_only_difference_and_a_near_name_is_offered(self):
        new = self.root / "new.glb"
        new.write_bytes(rig_glb(["ORG-spine", "ORG-hed", "hand.R"], {"idle": 1.0, "walk": 1.0}))
        res = self.compare("actor.sample.model", new)
        bad = [r for r in res["rows"] if r["verdict"] == ai.BAD]
        self.assertEqual([r["item"] for r in bad], ["bones.head"])
        self.assertIn("ORG-hed", bad[0]["note"])

    def test_godot_style_renamed_bone_is_a_note_not_a_difference(self):
        new = self.root / "new.glb"
        new.write_bytes(rig_glb(["ORG-spine", "ORG-head", "hand_R"], {"idle": 1.0, "walk": 1.0}))
        v = self.verdicts(self.compare("actor.sample.model", new))
        self.assertEqual(v["bones.hand"], ai.NOTE)

    def test_missing_and_short_clips(self):
        new = self.root / "new.glb"
        new.write_bytes(rig_glb(["ORG-spine", "ORG-head", "hand.R"], {"idle": 1.0, "walk_v2": 0.5}))
        res = self.compare("actor.sample.model", new)
        v = self.verdicts(res)
        self.assertEqual(v["clips.walk"], ai.BAD)
        new.write_bytes(rig_glb(["ORG-spine", "ORG-head", "hand.R"], {"idle": 1.0, "walk": 0.5}))
        self.assertEqual(self.verdicts(self.compare("actor.sample.model", new))["timing.walk_cycle"], ai.BAD)

    def test_png_size_alpha_and_meta_names(self):
        new = self.root / "new.png"
        new.write_bytes(png(6, 4, alpha=False))
        res = self.compare("actor.sample.sheet", new)
        v = self.verdicts(res)
        self.assertEqual((v["size"], v["alpha"]), (ai.BAD, ai.BAD))
        size_row = next(r for r in res["rows"] if r["item"] == "size")
        self.assertEqual((size_row["contract"], size_row["actual"]), ("8x4", "6x4"))
        # 곁 JSON의 조각(region)이 그림 밖으로 나가면 잡는다
        self.assertEqual(v["meta.region(조각이 그림 안에 드나)"], ai.BAD)
        # 곁 JSON에서 상태 하나가 빠지면 이름으로 보고한다
        meta = dict(SHEET_META, states={"idle": {}})
        (self.art / "samples" / "sheet.json").write_text(json.dumps(meta), encoding="utf-8")
        res = self.compare("actor.sample.sheet")
        row = next(r for r in res["rows"] if r["item"] == "meta.states")
        self.assertEqual(row["verdict"], ai.BAD)
        self.assertIn("cast", row["actual"])

    def test_svg_square_and_png_facts(self):
        self.assertEqual(self.verdicts(self.compare("icon.sample.square"))["square"], ai.OK)
        wide = self.root / "wide.svg"
        wide.write_text('<svg viewBox="0 0 64 32"></svg>', encoding="utf-8")
        self.assertEqual(self.verdicts(self.compare("icon.sample.square", wide))["square"], ai.BAD)
        f = self.root / "p.png"
        f.write_bytes(png(3, 5))
        self.assertEqual(ai.png_facts(f), {"size": (3, 5), "alpha": True})
        f.write_bytes(png(3, 5, alpha=False))
        self.assertFalse(ai.png_facts(f)["alpha"])

    def test_import_params_are_compared_when_the_import_file_exists(self):
        slot = {"kind": "texture", "file": "samples/sheet.png", "contract": {"import": {"mipmaps/generate": True}}}
        (self.art / "samples" / "sheet.png.import").write_text("[remap]\nimporter=\"texture\"\n[params]\nmipmaps/generate=false\n", encoding="utf-8")
        res = ai.compare_slot(self.root, "x", slot)
        self.assertEqual(res["rows"][-1]["verdict"], ai.BAD)
        (self.art / "samples" / "sheet.png.import").unlink()
        self.assertEqual(ai.compare_slot(self.root, "x", slot)["rows"][-1]["verdict"], ai.NA)

    def test_cli_slot_directory_and_strict_exit(self):
        folder = self.root / "bundle"
        folder.mkdir()
        (folder / "rig.glb").write_bytes(rig_glb(["ORG-spine", "ORG-hed", "hand.R"], {"idle": 1.0, "walk": 1.0}))
        base = ["--slot", "actor.sample.model", "--dir", str(folder), "--root", str(self.root)]
        self.assertEqual(ai.main(base), 0)                      # 차이가 있어도 --strict 없이는 0
        self.assertEqual(ai.main(base + ["--strict"]), 1)
        (folder / "rig.glb").write_bytes((self.art / "samples" / "rig.glb").read_bytes())
        self.assertEqual(ai.main(base + ["--strict"]), 0)
        # 폴더에 그 이름의 파일이 없으면 차이로 보고한다
        empty = self.root / "empty"
        empty.mkdir()
        self.assertEqual(ai.main(["--slot", "actor.sample.*", "--dir", str(empty), "--root", str(self.root), "--strict"]), 1)
        self.assertEqual(ai.main(["--slot", "nope.*", "--root", str(self.root)]), 2)

    # -- 원장 대조
    def test_ledger_reports_missing_ledger_rows_and_slotless_files(self):
        sl = led.slot_report(self.root, {"samples/rig.glb", "samples/loose.png"})
        self.assertTrue(sl["present"])
        self.assertEqual(sl["planned"], 1)
        text = "\n".join(sl["warnings"])
        self.assertIn("원장에 없는 파일이다: samples/sheet.png", text)
        self.assertNotIn("samples/rig.glb", text)
        self.assertEqual(sl["no_slot"], ["samples/loose.png"])

    def test_ledger_without_a_table_says_so(self):
        empty = self.root / "empty"
        empty.mkdir()
        self.assertFalse(led.slot_report(empty, set())["present"])

    def test_real_repository_check_still_exits_zero(self):
        res = led.run_check(REAL_ROOT, REAL_ROOT / "chapter1" / "art" / "ASSET-LEDGER.json")
        self.assertEqual(res["errors"], [])
        self.assertIn("slots", res)


if __name__ == "__main__":
    unittest.main(verbosity=2)
