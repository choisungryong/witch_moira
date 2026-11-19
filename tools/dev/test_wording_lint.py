"""wording_lint 자체 검사. 임시 폴더만 쓴다.  python -m unittest discover -s tools/dev -p "test_wording_lint.py" -v

규칙은 tools/dev/test_data/wording-rules.test.json(실제 규칙 파일의 꼴을 줄여 옮긴 것)을 쓴다.
실제 규칙 파일(docs/story/wording-rules.json)이 작업 폴더에 있으면 마지막 시험이 그것으로 한 번 돌아 본다.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wording_lint as wl  # noqa: E402

HERE = Path(__file__).resolve().parent
RULES_PATH = HERE / "test_data" / "wording-rules.test.json"
RULES = json.loads(RULES_PATH.read_text(encoding="utf-8"))
REAL = wl.DEFAULT_RULES


def T(text, key="k", lang="ko", file="chapter1/data/x.json", slot=None, kind="json"):
    return {"file": file, "line": 1, "key": key, "text": text, "lang": lang, "kind": kind, "slot": slot}


def run(*texts, rules=RULES):
    return wl.lint(list(texts), rules, Path(tempfile.gettempdir()))


def ids(fs):
    return sorted(f["rule"] for f in fs)


class WordTests(unittest.TestCase):
    def test_stems_catch_conjugations(self):
        for s in ("그곳에 깃든 슬픔", "마음에 깃들었다", "깃들어 있다"):
            self.assertEqual(ids(run(T(s, "x.y"))), ["banned:깃들다"], s)

    def test_exception_covers_only_its_own_place(self):
        self.assertEqual(run(T("기운 숄을 두른 노파", "x.y")), [])
        self.assertEqual(ids(run(T("기운 숄에 어두운 기운이 있다", "x.y"))), ["banned:기운(氣運)"])

    def test_exception_keys(self):
        self.assertEqual(run(T("얼음 파편", "item.rare.second.s04")), [])
        self.assertEqual(ids(run(T("얼음 파편", "item.rare.second.s05"))), ["restricted:파편"])
        self.assertEqual(run(T("파쇄 파편", "x.y")), [])

    def test_pattern_instead_of_stems(self):
        self.assertEqual(ids(run(T("정적이 흘렀다", "x.y"))), ["restricted:정적"])
        self.assertEqual(run(T("결정적인 순간", "x.y")), [])

    def test_applies_to_group_and_unkeyed_texts(self):
        self.assertEqual(ids(run(T("서약 반지", "item.base.ring.name"))), ["banned:서약·계약·봉인"])
        self.assertEqual(run(T("서약을 맺는다", "ui.title")), [])          # 키가 @items 에 없음
        self.assertEqual(run(T("서약 반지", "data:loot.json:bases[0].name")), [])  # 키 없는 글에는 applies_to 규칙을 안 건다
        self.assertEqual(run(T("서약 반지", "code:chapter1/a.gd", kind="code")), [])

    def test_rule_without_applies_to_hits_unkeyed_texts(self):
        self.assertEqual(ids(run(T("잿빛 회랑", "code:chapter1/a.gd", kind="code"))), ["banned:잿빛"])
        self.assertEqual(ids(run(T("잿빛", "data:loot.json:rare[0]"))), ["banned:잿빛"])

    def test_ko_rules_skip_en_texts(self):
        self.assertEqual(run(T("잿빛", "x.y", lang="en", file="chapter1/i18n/en.po", kind="po")), [])

    def test_grade_from_rule(self):
        fs = run(T("황혼 발톱", "x.y"), T("잿빛", "x.z"))
        self.assertEqual({f["word"]: f["grade"] for f in fs}, {"황혼": "warn", "잿빛": "fail"})

    def test_unknown_keys_ignored(self):
        self.assertEqual(run(T("평범한 글", "x.y"), rules={"zzz": 1, "banned": [{"word": "없는말", "stems": ["없는말"]}]}), [])


class NameTests(unittest.TestCase):
    def test_shape_on_names_only(self):
        self.assertIn("name_shape:F1", ids(run(T("격노의 순례자의 붕대", "item.rare.x"))))
        self.assertEqual(run(T("격노의 순례자의 붕대", "ui.some.text")), [])

    def test_shape_exceptions_and_only_slots(self):
        base = lambda t, slot: T(t, "item.base.a.name", slot=slot)  # noqa: E731
        self.assertEqual(ids(run(base("박동의 마법봉", "weapon"))), ["name_shape:F1-base"])
        self.assertEqual(run(base("순례자의 장화", "feet")), [])          # 칸이 only_slots 밖
        self.assertEqual(run(base("재의 두건", "weapon")), [])             # 예외 문구가 걸린 자리를 덮음

    def test_negative_modifier_name_is_warn(self):
        fs = run(T("꺼지지 않는 불씨", "ritual.a.name"))
        self.assertEqual([(f["word"], f["grade"]) for f in fs if f["word"] == "F9"], [("F9", "warn")])

    def test_applies_to_star_hits_keyed_texts_only(self):
        self.assertEqual(ids(run(T("새 저장으로 시작…", "profile.x.start"))), ["name_shape:F4"])
        self.assertEqual(run(T("새 저장으로 시작…", "code:a.gd", kind="code")), [])

    def test_en_rule_only_on_en(self):
        self.assertEqual(ids(run(T("Gatekeeper of Embers", "enemy.a.name", lang="en", file="chapter1/i18n/en.po", kind="po"))), ["name_shape:EN-F1"])
        self.assertNotIn("name_shape:EN-F1", ids(run(T("Gatekeeper of Embers", "enemy.a.name"))))

    def test_max_chars_default_pattern_warn_only_and_spaces(self):
        self.assertEqual(run(T("가" * 5, "enemy.a.name")), [])
        fs = run(T("가" * 6, "enemy.a.name"))
        self.assertEqual([(f["rule"], f["grade"]) for f in fs], [("name_max_chars", "fail")])
        self.assertEqual(run(T("가나 다라 마바", "item.base.x.name")), [])   # 공백 빼고 6자
        fs = run(T("가나다 라마바 사", "item.base.x.name"))                 # 7자
        self.assertEqual([(f["rule"], f["grade"]) for f in fs], [("name_max_chars", "warn")])
        self.assertEqual(ids(run(T("가" * 5, "item.legendary.q.name"))), ["name_max_chars"])
        self.assertEqual(run(T("가" * 30, "ui.description.text")), [])        # 이름이 아님


class EnglishTests(unittest.TestCase):
    EN = dict(lang="en", file="chapter1/i18n/en.po", kind="po")

    def test_banned_en_boundary_and_restricted(self):
        self.assertEqual(ids(run(T("The Ashen yard", "a.b", **self.EN))), ["en_banned:Ashen"])
        self.assertEqual(run(T("Ashenfall", "a.b", **self.EN)), [])
        self.assertEqual(ids(run(T("A Sanctum of Cinders", "zone.2.name", **self.EN)))[0], "en_banned:Sanctum of")
        self.assertEqual(ids(run(T("Hello there", "a.b", **self.EN))), [])
        self.assertEqual([f["grade"] for f in run(T("deep Shadow", "a.b", **self.EN))], ["warn"])

    def test_must_pair_and_applies_to(self):
        ko = T("서약을 맺다", "a.b", file="chapter1/i18n/ko.po", kind="po")
        self.assertEqual(ids(run(ko, T("Make a pact", "a.b", **self.EN))), ["en_must:서약=Vow"])
        self.assertEqual(run(ko, T("Take the vow", "a.b", **self.EN)), [])
        ko2 = T("재가 부족하다", "profile.essence_short", file="chapter1/i18n/ko.po", kind="po")
        self.assertEqual(ids(run(ko2, T("Not enough essence", "profile.essence_short", **self.EN))), ["en_must:재=Ash"])
        ko3 = T("재가 부족하다", "other.key", file="chapter1/i18n/ko.po", kind="po")
        self.assertEqual(run(ko3, T("Not enough", "other.key", **self.EN)), [])   # applies_to 밖의 키


class PendingTests(unittest.TestCase):
    def test_word_and_text_must_match(self):
        po = dict(file="chapter1/i18n/ko.po", kind="po")
        fs = run(T("잿빛 앞뜰", "zone.0.name", **po))
        self.assertTrue(all(f["pending"] for f in fs))
        self.assertEqual(wl.summarize(fs)["fail"], 0)
        fs = run(T("잿빛 안뜰", "zone.0.name", **po))                 # 글이 바뀌면 다시 걸린다
        self.assertEqual(wl.summarize(fs)["fail"], 1)
        fs = run(T("잿빛 앞뜰 · 깃든", "zone.0.name", **po))
        self.assertEqual(wl.summarize(fs)["fail"], 3)   # 깃든, 글자 수, 글이 달라져 다시 걸린 잿빛

    def test_pending_without_word_covers_every_hit_of_that_text(self):
        fs = run(T("황혼", "item.rare.first.f06", file="chapter1/data/loot.json"))
        self.assertTrue(fs and all(f["pending"] for f in fs))

    def test_same_word_elsewhere_still_fails(self):
        self.assertEqual(wl.summarize(run(T("잿빛 길", "x.y", file="chapter1/data/other.json")))["fail"], 1)

    def test_pending_with_other_word_does_not_cover(self):
        fs = run(T("Sanctum of Cinders", "zone.2.name", lang="en", file="chapter1/i18n/en.po", kind="po"))
        self.assertEqual([f["word"] for f in fs if f["pending"]], ["Sanctum of"])


class CollectTests(unittest.TestCase):
    def _root(self, files):
        d = tempfile.TemporaryDirectory()
        for rel, text in files.items():
            p = Path(d.name) / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8", newline="\n")
        return d

    def test_po_json_gd_godot_and_excludes(self):
        loot = {"slot_names": {"weapon": "무기"}, "bases": [{"id": "a", "slot": "weapon", "name": "박동의 마법봉", "stats": {"name": "x"}}],
                "uniques": [{"id": "u", "name": "고유", "description": "기운이 깃든 설명"}], "rare_names": {"first": [{"id": "f01", "name": "황혼"}]}}
        trees = {"trees": [{"tree_id": "witch.frost", "nodes": [{"id": "volley", "name": "한 줄", "lore": "예전 글", "note": "잿빛 메모"}]}]}
        with self._root({
            "chapter1/i18n/ko.po": '# c\nmsgid ""\nmsgstr ""\n"Language: ko\\n"\n\nmsgid "zone.a.name"\nmsgstr "잿빛 앞뜰"\n\nmsgid "x.n"\nmsgid_plural "x.n"\nmsgstr[0] "{n}개의"\n"  깃든"\n',
            "chapter1/i18n/en.po": 'msgid "zone.a.name"\nmsgstr "Ashen Yard"\n',
            "chapter1/data/loot.json": json.dumps(loot, ensure_ascii=False, indent=1) + "\n",
            "chapter1/data/skill_trees.json": json.dumps(trees, ensure_ascii=False, indent=1) + "\n",
            "chapter1/x.gd": 'var a = "잿빛 문"\n# "잿빛 주석"\nvar b = "plain"\n',
            "chapter1/tests/t.gd": 'var a = "잿빛 시험"\n',
            "chapter1/core/chapter_items.gd": 'var a = "잿빛 옛 장비"\n',
            "project.godot": 'config/name="잿빛 창"\n; config/x="잿빛 주석"\n',
        }) as d:
            root = Path(d)
            texts = wl.collect_texts(root, RULES)
            by = {(t["file"], t["key"]): t for t in texts}
            self.assertEqual(by[("chapter1/i18n/ko.po", "zone.a.name")]["line"], 7)
            self.assertIn("깃든", by[("chapter1/i18n/ko.po", "x.n")]["text"])
            self.assertEqual(by[("chapter1/i18n/en.po", "zone.a.name")]["lang"], "en")
            b = by[("chapter1/data/loot.json", "item.base.a.name")]
            self.assertEqual((b["text"], b["slot"]), ("박동의 마법봉", "weapon"))
            self.assertIn(("chapter1/data/loot.json", "item.unique.u.desc"), by)
            self.assertIn(("chapter1/data/loot.json", "item.slot.weapon"), by)
            self.assertIn(("chapter1/data/loot.json", "data:loot.json:bases[0].stats.name"), by)   # 표에 없는 경로는 data: 키
            self.assertIn(("chapter1/data/loot.json", "data:loot.json:rare_names.first[0].name"), by)
            self.assertEqual(by[("chapter1/data/skill_trees.json", "tree.witch.frost.node.volley.lore")]["text"], "예전 글")
            self.assertNotIn("잿빛 메모", [t["text"] for t in texts])   # json_fields 밖
            self.assertEqual([t["text"] for t in texts if t["file"] == "chapter1/x.gd"], ["잿빛 문"])
            self.assertEqual([t["text"] for t in texts if t["file"] == "project.godot"], ["잿빛 창"])
            self.assertFalse([t for t in texts if "tests/" in t["file"] or t["file"].endswith("chapter_items.gd")])
            fs = wl.lint(texts, RULES, root)
            # en.po 에는 한국어 규칙이 안 걸리고, 영어 금지어만 걸린다
            self.assertEqual([f["rule"] for f in fs if f["file"].endswith("en.po")], ["en_banned:Ashen"])

    def test_structure_check_parses_without_eval(self):
        with self._root({"chapter1/data/loot.json": json.dumps({"rare_names": {"first": [1, 2], "second": [1]}}) + "\n"}) as d:
            self.assertEqual([f for f in wl.lint([], RULES, Path(d)) if f["rule"].startswith("structure")], [])
        with self._root({"chapter1/data/loot.json": json.dumps({"rare_names": {"first": [1], "second": [1]}}) + "\n"}) as d:
            self.assertEqual([f["rule"] for f in wl.lint([], RULES, Path(d))], ["structure:T-count"])

    def test_docs_scan_is_opt_in_and_warn_only(self):
        with self._root({"docs/a.md": "잿빛 회랑이다\n무언가가 있다\n", "docs/story/WORDING-RULES.ko.md": "잿빛\n"}) as d:
            root = Path(d)
            self.assertEqual(wl.lint([], RULES, root), [])
            fs = wl.lint([], RULES, root, docs=True)
            self.assertEqual(sorted(f["word"] for f in fs), ["잿빛"])          # 무언가는 skip_docs, 제외 문서는 안 봄
            self.assertEqual([f["grade"] for f in fs], ["warn"])
            self.assertTrue(fs[0]["pending"])                                  # docs/**/*.md 의 결정 대기('잿빛 회랑')

    def test_exit_codes(self):
        with tempfile.TemporaryDirectory() as t:
            self.assertEqual(wl.main(["--rules", str(Path(t) / "none.json")]), 2)
            bad = Path(t) / "bad.json"
            bad.write_text("[1]", encoding="utf-8")
            self.assertEqual(wl.main(["--rules", str(bad)]), 2)
        with self._root({"chapter1/data/loot.json": '{"bases": [{"id": "a", "name": "잿빛"}]}\n'}) as d:
            out = Path(d) / "o.json"
            self.assertEqual(wl.main(["--rules", str(RULES_PATH), "--root", d, "--out", str(out), "--summary"]), 1)
            self.assertEqual(json.loads(out.read_text(encoding="utf-8"))["fail"], 1)
            txt = Path(d) / "o.txt"
            wl.main(["--rules", str(RULES_PATH), "--root", d, "--out", str(txt)])
            self.assertIn("SUMMARY fail=1", txt.read_text(encoding="utf-8"))
        with self._root({"chapter1/data/loot.json": '{"bases": [{"id": "a", "name": "맑은 길"}]}\n'}) as d:
            self.assertEqual(wl.main(["--rules", str(RULES_PATH), "--root", d]), 0)


class RealRulesTests(unittest.TestCase):
    @unittest.skipUnless(REAL.is_file(), "docs/story/wording-rules.json 이 없다")
    def test_real_rules_load_and_every_pending_entry_is_still_used(self):
        rules = json.loads(REAL.read_text(encoding="utf-8"))
        texts = wl.collect_texts(wl.ROOT, rules)
        self.assertGreater(len(texts), 500)
        keys = {t["key"] for t in texts}
        self.assertIn("item.base.ash_hood.name", keys)          # key_map 이 장비 이름 키를 만든다
        fs = wl.lint(texts, rules, wl.ROOT)
        self.assertEqual(wl.summarize(fs)["fail"], 0, [f"{f['file']}:{f['line']} {f['rule']}" for f in fs if not f["pending"] and f["grade"] == "fail"])
        self.assertEqual(len(wl.LAST["used_pending"]), len(rules["allow_pending"]) - sum(1 for p in rules["allow_pending"] if p["file"].startswith(("docs/", ".claude/"))))


if __name__ == "__main__":
    unittest.main()
