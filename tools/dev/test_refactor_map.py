#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""refactor_map.py 자체 검사: 작은 가짜 프로젝트를 코드로 만들어 확인한다. Godot를 쓰지 않는다."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refactor_map as rm  # noqa: E402


def put(root, rel, text, binary=False):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb" if binary else "w", encoding=None if binary else "utf-8", newline=None if binary else "\n") as f:
        f.write(text)


def make_project(root):
    put(root, "project.godot", '[application]\nrun/main_scene="res://game/Main.tscn"\n[autoload]\nBus="*res://game/bus.gd"\n')
    put(root, "game/Main.tscn",
        '[gd_scene format=3 uid="uid://main1"]\n'
        '[ext_resource type="Script" path="res://game/main.gd" id="1"]\n'
        '[ext_resource type="Shader" uid="uid://shd1" id="2"]\n'
        '[connection signal="pressed" from="B" to="." method="on_press__v2"]\n')
    put(root, "game/main.gd",
        'extends Node\n'
        'const Used = preload("res://game/used.gd")\n'
        'const Unused = preload("res://game/unused_alias.gd")\n'
        '# preload("res://game/in_comment.gd")\n'
        'var s := "preload(\\"res://game/in_string.gd\\")"\n'
        '"""\npreload("res://game/in_docstring.gd")\n"""\n'
        'func _ready() -> void:\n'
        '\tUsed.new()\n'
        '\tsetup__v2()\n'
        '\tvar x = load("res://data/" + name + ".json")\n'
        '\tvar y = load(path_var)\n'
        '\tvar d = load("res://data/a.json")\n'
        '\tcall("never__v3")\n'
        '\tconnect_it(Callable(self, "named__v2"))\n'
        'func setup__v1() -> void:\n\tpass\n'
        'func setup__v2() -> void:\n\tsetup__v1()\n\tmulti__v1()\n'
        'func multi__v1() -> void:\n\tpass\n'
        'func other() -> void:\n\tmulti__v1()\n'
        'func on_press__v2() -> void:\n\tpass\n'
        'func named__v2() -> void:\n\tpass\n'
        'func never__v3() -> void:\n\tpass\n'
        'func orphan__v1() -> void:\n\tpass\n'
        'func orphan_user__v2() -> void:\n\torphan__v1()\n')
    put(root, "game/used.gd", 'extends RefCounted\nvar sh = preload("res://game/fx.gdshader")\n')
    put(root, "game/unused_alias.gd", "extends RefCounted\n")
    put(root, "game/fx.gdshader", '#include "res://game/lib.gdshaderinc"\n// #include "res://game/comment.gdshaderinc"\n')
    put(root, "game/lib.gdshaderinc", "// lib\n")
    put(root, "game/comment.gdshaderinc", "// c\n")
    put(root, "game/lonely.gd", "extends Node\n")
    put(root, "game/island_a.gd", 'extends Node\nconst B = preload("res://game/island_b.gd")\n')
    put(root, "game/island_b.gd", "extends Node\n")
    put(root, "game/bus.gd", "extends Node\n")
    put(root, "game/with_class.gd", "class_name Widget\nextends Node\n")
    put(root, "game/uses_class.gd", "extends Node\nvar w = Widget.new()\n")
    put(root, "game/quality10_thing.gd", "extends Node\n")
    put(root, "game/ui38/panel.gd", "extends Node\n")
    put(root, "game/hasui.gd", 'extends Node\nconst P = preload("res://game/ui38/panel.gd")\n')
    put(root, "game/dyn/x1.json", "{}")
    put(root, "game/dyn/x2.json", "{}")
    put(root, "game/dynuser.gd", 'extends Node\nfunc f(n):\n\treturn load("res://game/dyn/" + n + ".json")\n')
    put(root, "data/a.json", "{}")
    put(root, "data/b.json", "{}")
    put(root, "data/rel.json", '{"icon":"res://game/lonely.gd"}')
    put(root, "game/broken.gd", 'extends Node\nconst M = preload("res://game/missing.gd")\n')
    put(root, "chapter1/tests/t.gd", 'extends SceneTree\nconst Z = preload("res://game/tests_only.gd")\n')
    put(root, "game/tests_only.gd", "extends Node\n")
    put(root, "tools/run.py", 'ARG = "res://game/bus.gd"\nS = "--script res://game/from_tool.gd"\n')
    put(root, "game/from_tool.gd", "extends SceneTree\n")
    put(root, "game/weak.gd", 'extends Node\nvar p = DATA + "b.json"\n')
    put(root, "docs/.gdignore", "")
    put(root, "docs/ignored.gd", 'preload("res://game/lonely.gd")\n')
    put(root, "docs/note.md", "see res://game/lonely.gd here\n")
    put(root, "_local/.gdignore", "")
    put(root, "game/lonely.gd.uid", "uid://lonely\n")
    put(root, "game/fx.gdshader.uid", "uid://shd1\n")


class RefMapTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = cls.tmp.name
        make_project(cls.root)
        cls.g = rm.Graph(cls.root)
        cls.rep = rm.build_report(cls.g)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def refs(self, f):
        return {(r["from"], r["kind"]) for r in self.rep["files"][f]["referrers"]}

    def test_ignored_dirs_skipped(self):
        self.assertNotIn("docs/ignored.gd", self.g.files)
        self.assertNotIn(("docs/ignored.gd", "preload"), self.refs("game/lonely.gd"))

    def test_preload_and_comment_string_ignored(self):
        self.assertIn(("game/main.gd", "preload"), self.refs("game/used.gd"))
        for n in ("in_comment", "in_string", "in_docstring"):
            self.assertFalse(any(d["literal"].endswith(n + ".gd") for d in self.g.dangling))

    def test_alias_use_counts(self):
        e = {r["from"]: r for r in self.rep["files"]["game/unused_alias.gd"]["referrers"]}["game/main.gd"]
        self.assertEqual(e["alias_uses"], 0)
        e = {r["from"]: r for r in self.rep["files"]["game/used.gd"]["referrers"]}["game/main.gd"]
        self.assertGreaterEqual(e["alias_uses"], 1)

    def test_scene_uid_shader_include(self):
        self.assertIn(("game/Main.tscn", "ext_resource"), self.refs("game/main.gd"))
        self.assertIn(("game/Main.tscn", "uid"), self.refs("game/fx.gdshader"))
        self.assertIn(("game/fx.gdshader", "include"), self.refs("game/lib.gdshaderinc"))
        self.assertEqual(self.refs("game/comment.gdshaderinc"), set())

    def test_roots_and_unreferenced(self):
        self.assertIn("game/Main.tscn", self.rep["roots"])
        self.assertIn("game/bus.gd", self.rep["roots"])
        self.assertIn("game/from_tool.gd", self.rep["roots"])
        un = {r["file"] for r in self.rep["unreferenced"]}
        self.assertIn("game/island_a.gd", un)
        self.assertIn("game/quality10_thing.gd", un)
        self.assertNotIn("game/bus.gd", un)
        self.assertNotIn("game/from_tool.gd", un)
        self.assertNotIn("chapter1/tests/t.gd", un)
        self.assertNotIn("game/lonely.gd", un)          # data/rel.json 이 경로로 가리킨다

    def test_unreachable_island(self):
        ur = {r["file"] for r in self.rep["unreachable_from_roots"]}
        self.assertIn("game/island_b.gd", ur)
        self.assertNotIn("game/used.gd", ur)

    def test_tests_only_and_weak_only(self):
        self.assertIn("game/tests_only.gd", {r["file"] for r in self.rep["only_tests_reference"]})
        weak = {r["file"] for r in self.rep["weak_only_reference"]}
        self.assertIn("data/b.json", weak)

    def test_class_name_edge(self):
        self.assertIn(("game/uses_class.gd", "class_name"), self.refs("game/with_class.gd"))

    def test_version_names(self):
        v = {x["file"]: x for x in self.rep["version_named"]}
        self.assertIn("game/quality10_thing.gd", v)
        self.assertIn("game/ui38/panel.gd", v)
        self.assertEqual(v["game/ui38/panel.gd"]["referrer_count"], 1)
        self.assertNotIn("game/main.gd", v)

    def test_dangling_and_uncertain(self):
        self.assertTrue(any(d["literal"] == "res://game/missing.gd" for d in self.g.dangling))
        kinds = [(u["file"], u["kind"]) for u in self.g.uncertain]
        self.assertIn(("game/main.gd", "동적 경로 조립"), kinds)
        self.assertIn(("game/main.gd", "load(변수)"), kinds)
        self.assertEqual(sum(1 for u in self.g.uncertain if u["file"] == "game/main.gd" and u["kind"] == "load(변수)"), 1)
        pre = {p for _, _, p in self.g.prefixes}
        self.assertIn("game/dyn/", pre)
        mp = {r["file"]: r["maybe_dynamic_prefix"] for r in self.rep["unreferenced"]}
        self.assertEqual(mp.get("game/dyn/x1.json"), ["game/dyn/"])

    def test_layer_methods(self):
        lm = {d["name"]: d for d in self.rep["layer_methods"]}
        self.assertEqual(len(lm), 8)
        self.assertEqual(lm["setup__v1"]["category"], "single")
        self.assertTrue(lm["setup__v1"]["single_caller_is_layer_same_base"])
        self.assertTrue(lm["setup__v1"]["fold_candidate"])
        self.assertEqual(lm["setup__v2"]["category"], "single")
        self.assertFalse(lm["setup__v2"]["single_caller_is_layer_same_base"])
        self.assertEqual(lm["multi__v1"]["category"], "multi")
        self.assertEqual(lm["never__v3"]["category"], "none")
        self.assertTrue(lm["never__v3"]["string_mentions"])
        self.assertTrue(lm["never__v3"]["reachable"])
        self.assertTrue(lm["on_press__v2"]["string_mentions"])           # .tscn [connection]
        self.assertEqual(lm["on_press__v2"]["category"], "none")
        self.assertTrue(lm["named__v2"]["string_mentions"][0]["dyn_call_line"])
        self.assertFalse(lm["named__v2"]["fold_candidate"])
        self.assertEqual(lm["orphan__v1"]["category"], "single")         # 호출은 있으나
        self.assertFalse(lm["orphan__v1"]["reachable"])                  # 부르는 쪽이 아무도 안 불린다
        self.assertEqual(lm["orphan_user__v2"]["category"], "none")
        S = self.rep["summary"]
        self.assertEqual(S["layer_methods"], 8)
        self.assertEqual(S["layer_unreachable"], 2)

    def test_first_line_blind_spots(self):
        md = rm.render_md(self.rep)
        self.assertTrue(md.startswith("이 지도가 보지 못하는 것"))
        self.assertIn("죽은 코드", md.split("\n")[0])

    def test_rename_check(self):
        res = rm.rename_check(self.g, "res://game/used.gd", "res://game/core/used.gd")
        ed = {(e["in"], e["kind"]): e for e in res["edits"]}
        self.assertEqual(ed[("game/main.gd", "preload")]["edit"],
                         "res://game/used.gd -> res://game/core/used.gd")
        self.assertEqual(res["warnings"], [])
        res = rm.rename_check(self.g, "game/lib.gdshaderinc", "game/inc/lib.gdshaderinc")
        self.assertTrue(any("include" == e["kind"] for e in res["edits"]))
        self.assertTrue(any("셰이더" in w for w in res["warnings"]))
        res = rm.rename_check(self.g, "game/lonely.gd", "game/main.gd")
        self.assertTrue(any("이미 있다" in w for w in res["warnings"]))
        self.assertEqual([s["move"] for s in res["sidecars"]], ["game/lonely.gd.uid"])
        self.assertTrue(any(m["file"] == "docs/note.md" for m in res["text_mentions"]))
        res = rm.rename_check(self.g, "game/ui38", "game/ui")
        self.assertTrue(res["is_dir"])
        self.assertEqual(res["edits"][0]["edit"], "res://game/ui38/panel.gd -> res://game/ui/panel.gd")
        res = rm.rename_check(self.g, "game/dyn/x1.json", "game/other/x1.json")
        self.assertTrue(res["dynamic_prefix"])

    def test_out_must_be_under_local(self):
        self.assertIsNone(rm.resolve_out(self.root, "docs/x"))
        self.assertIsNotNone(rm.resolve_out(self.root, "_local/refactor-map/"))

    def test_cli_writes_only_under_local(self):
        rc = rm.main(["--root=" + self.root, "--out=_local/rm/", "--quiet"])
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.exists(os.path.join(self.root, "_local/rm/refmap.json")))
        self.assertTrue(os.path.exists(os.path.join(self.root, "_local/rm/refmap.md")))
        self.assertEqual(rm.main(["--root=" + self.root, "--out=docs/rm/"]), 2)


if __name__ == "__main__":
    unittest.main(verbosity=1)
