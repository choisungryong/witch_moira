"""wording_lint 자체 검사. 임시 폴더만 쓴다.  python -m unittest discover -s tools/dev -p "test_wording_lint.py" -v"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wording_lint as wl  # noqa: E402

RULES = json.loads((Path(__file__).resolve().parent / "test_data" / "wording-rules.test.json").read_text(encoding="utf-8"))


def T(text, ctx="text", key="k", lang="ko", file="chapter1/data/x.json"):
    return {"file": file, "line": 1, "key": key, "text": text, "lang": lang, "ctx": ctx}


def run(*texts, rules=RULES):
    return wl.lint(list(texts), rules)


def names(fs):
    return sorted(f["rule"] for f in fs)


class WordTests(unittest.TestCase):
    def test_banned_word_hit(self):
        self.assertEqual(names(run(T("잿빛 앞뜰"))), ["banned:잿빛"])

    def test_stems_catch_conjugations(self):
        for s in ("그곳에 깃든 슬픔", "마음에 깃들었다", "깃들어 있다"):
            self.assertEqual(names(run(T(s))), ["banned:깃들다"], s)

    def test_exception_protects_homonym(self):
        self.assertEqual(run(T("기운 숄을 두른 노파")), [])
        self.assertEqual(run(T("기운 자국이 남았다")), [])

    def test_exception_does_not_protect_other_occurrence(self):
        self.assertEqual(names(run(T("기운 숄에 어두운 기운이 있다"))), ["banned:기운"])

    def test_restricted_defaults_to_warn_and_banned_to_fail(self):
        fs = run(T("황혼 발톱"), T("잿빛"))
        self.assertEqual({f["rule"]: f["grade"] for f in fs}, {"restricted:황혼": "warn", "banned:잿빛": "fail"})

    def test_english_text_not_checked_by_korean_words(self):
        self.assertEqual(run(T("잿빛", lang="en")), [])

    def test_unknown_keys_ignored(self):
        self.assertEqual(run(T("평범한 글"), rules={"zzz": 1, "banned": [{"word": "없는말"}]}), [])


class NameTests(unittest.TestCase):
    def test_double_ui_shape(self):
        fs = run(T("격노의 순례자의 붕대", ctx="name"))
        self.assertIn("name_shape:F1", names(fs))

    def test_shape_only_on_names(self):
        self.assertNotIn("name_shape:F1", names(run(T("격노의 순례자의 붕대", ctx="description"))))

    def test_negative_modifier_name_fails(self):
        fs = run(T("꺼지지 않는 불씨", ctx="name"))
        self.assertEqual([f["grade"] for f in fs if f["rule"] == "name_shape:F9"], ["fail"])

    def test_max_chars_default_and_pattern(self):
        self.assertEqual(run(T("가" * 14, ctx="name", key="item.a.name")), [])
        self.assertEqual(names(run(T("가" * 15, ctx="name", key="item.a.name"))), ["name_max_chars"])
        self.assertEqual(names(run(T("가" * 9, ctx="name", key="zone.x.name"))), ["name_max_chars"])

    def test_max_chars_not_applied_to_descriptions(self):
        self.assertEqual(run(T("가" * 40, ctx="description")), [])


class EnglishTests(unittest.TestCase):
    def test_banned_en_word_boundary(self):
        fs = run(T("The Ashen yard", lang="en", file="chapter1/i18n/en.po"))
        self.assertEqual(names(fs), ["en_banned:Ashen"])
        self.assertEqual(run(T("Ashenfall is fine here", lang="en", file="chapter1/i18n/en.po")), [])

    def test_must_pair(self):
        ko = T("서약을 맺다", key="a.b", file="chapter1/i18n/ko.po")
        bad = T("Make a pact", key="a.b", lang="en", file="chapter1/i18n/en.po")
        good = T("Take the vow", key="a.b", lang="en", file="chapter1/i18n/en.po")
        self.assertEqual(len(run(ko, bad)), 1)
        self.assertEqual(run(ko, good), [])


class PendingTests(unittest.TestCase):
    def test_pending_not_counted_as_fail(self):
        fs = run(T("잿빛 앞뜰", file="chapter1/i18n/ko.po", key="zone.x.name", ctx="name"))
        self.assertTrue(all(f["pending"] for f in fs))
        self.assertEqual(wl.summarize(fs), {"fail": 0, "warn": 0, "pending": len(fs)})

    def test_same_word_elsewhere_still_fails(self):
        fs = run(T("잿빛 길", file="chapter1/data/other.json"))
        self.assertEqual(wl.summarize(fs)["fail"], 1)


class CollectTests(unittest.TestCase):
    def test_po_json_gd(self):
        with tempfile.TemporaryDirectory() as d:
            r = Path(d)
            (r / "chapter1" / "i18n").mkdir(parents=True)
            (r / "chapter1" / "data").mkdir()
            (r / "chapter1" / "tests").mkdir()
            (r / "chapter1" / "i18n" / "ko.po").write_text(
                '# c\nmsgid ""\nmsgstr ""\n"Language: ko\\n"\n\nmsgid "zone.a.name"\nmsgstr "잿빛 앞뜰"\n\n'
                'msgid "x.n"\nmsgid_plural "x.n"\nmsgstr[0] "{n}개의"\n"  깃든"\n', encoding="utf-8", newline="\n")
            (r / "chapter1" / "data" / "d.json").write_text(
                json.dumps({"items": [{"id": "a", "name": "황혼", "note": "잿빛 메모"}]}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
            (r / "chapter1" / "x.gd").write_text('var a = "잿빛 문"\n# "잿빛 주석"\nvar b = "plain"\n', encoding="utf-8", newline="\n")
            (r / "chapter1" / "tests" / "t.gd").write_text('var a = "잿빛 시험"\n', encoding="utf-8", newline="\n")
            texts = wl.collect_texts(r)
            by = {(t["file"], t["key"] or t["text"]): t for t in texts}
            self.assertEqual(by[("chapter1/i18n/ko.po", "zone.a.name")]["ctx"], "name")
            self.assertEqual(by[("chapter1/i18n/ko.po", "zone.a.name")]["line"], 7)
            self.assertIn("깃든", by[("chapter1/i18n/ko.po", "x.n")]["text"])
            self.assertEqual(by[("chapter1/data/d.json", "items[0].name")]["ctx"], "name")
            self.assertNotIn(("chapter1/data/d.json", "items[0].note"), by)
            gd = [t for t in texts if t["file"].endswith("x.gd")]
            self.assertEqual([t["text"] for t in gd], ["잿빛 문"])
            self.assertFalse([t for t in texts if t["file"].endswith("t.gd")])

    def test_missing_rules_file_exit_2(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(wl.main(["--rules", str(Path(d) / "none.json")]), 2)

    def test_fail_exit_1_and_pass_exit_0(self):
        with tempfile.TemporaryDirectory() as d:
            r = Path(d)
            (r / "chapter1" / "data").mkdir(parents=True)
            (r / "chapter1" / "data" / "d.json").write_text('{"name": "잿빛"}\n', encoding="utf-8", newline="\n")
            rules = Path(__file__).resolve().parent / "test_data" / "wording-rules.test.json"
            self.assertEqual(wl.main(["--rules", str(rules), "--root", str(r), "--out", str(r / "o.json")]), 1)
            self.assertTrue((r / "o.json").is_file())
            (r / "chapter1" / "data" / "d.json").write_text('{"name": "맑은 길"}\n', encoding="utf-8", newline="\n")
            self.assertEqual(wl.main(["--rules", str(rules), "--root", str(r)]), 0)


if __name__ == "__main__":
    unittest.main()
