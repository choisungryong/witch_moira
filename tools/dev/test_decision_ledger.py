"""decision_ledger 자체 검사. 임시 폴더만 쓴다.  python -m unittest discover -s tools/dev -p "test_decision_ledger.py" -v"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decision_ledger as dl  # noqa: E402


def make(files):
    d = tempfile.TemporaryDirectory()
    for rel, text in files.items():
        p = Path(d.name) / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8", newline="\n")
    return d


class ScanTests(unittest.TestCase):
    def test_row_kinds(self):
        occ = dl.scan_text("a.md", "| N5 | 마녀가 눈을 뜬 자리 | 안 가 |\n| **N59** (2판) | 어머니 카드 | 안 |\n| N41·N42 | 새 이름 | 안 1 |\n| N5 균열 속 눈뜸 | 죽은 자리 | 참조 |\n")
        kinds = [(o["num"], o["kind"]) for o in occ]
        self.assertEqual(kinds, [("N5", "row"), ("N59", "row"), ("N41", "row"), ("N42", "row"), ("N5", "ref")])
        self.assertEqual(occ[0]["title"], "마녀가 눈을 뜬 자리")

    def test_markers(self):
        occ = dl.scan_text("a.md", "[잠정 · N7]\n[미정 · N9 · U12와 묶임]\n본문 [링크](x) 에는 번호 없음 N3\n")
        self.assertEqual([(o["num"], o["kind"]) for o in occ], [("N7", "marker"), ("N9", "marker"), ("U12", "marker")])

    def test_status_is_not_read(self):
        occ = dl.scan_text("a.md", "[확정 · N7]\n")
        self.assertFalse(any("확정" in str(v) for o in occ for v in o.values()))


class BuildTests(unittest.TestCase):
    def test_overlap_found_for_different_items(self):
        with make({"docs/story/A.md": "| N39 | 장비 이름 규칙 정하기 | 안 |\n",
                   "docs/reviews/DECISIONS-PENDING-1.md": "| N39 | 우두머리 목소리 유지 여부 | 고친다 |\n"}) as d:
            r = dl.build(Path(d), dl.DEFAULT_SCOPE)
            self.assertEqual([o["num"] for o in r["overlaps"]], ["N39"])
            self.assertEqual(len(r["overlaps"][0]["groups"]), 2)

    def test_same_decision_restated_is_not_overlap(self):
        with make({"docs/story/A.md": "| N32 | 단일 엔딩과 진 엔딩의 악마신 | 안 |\n",
                   "docs/reviews/DECISIONS-PENDING-1.md": "| N32 | 한 캐릭터 엔딩에서는 악마신이 물러나는가, 진 엔딩 | 채택 |\n"}) as d:
            self.assertEqual(dl.build(Path(d), dl.DEFAULT_SCOPE)["overlaps"], [])

    def test_out_of_scope_overlap_reported_but_not_failing(self):
        with make({"docs/specs/x.md": "| N1 | 지팡이 머리 형태 | a |\n", "docs/specs/y.md": "| N1 | 저장 정체성 검증 규칙 | b |\n"}) as d:
            r = dl.build(Path(d), dl.DEFAULT_SCOPE)
            self.assertEqual(r["overlaps"], [])
            self.assertEqual([o["num"] for o in r["overlaps_other_systems"]], ["N1"])
            self.assertEqual(dl.main(["--root", d]), 0)
            self.assertEqual(dl.main(["--root", d, "--all-scope"]), 1)

    def test_next_free_and_files(self):
        with make({"docs/story/A.md": "| N3 | 첫 번째 결정 | a |\n[잠정 · N3]\n| U2 | 두 번째 | b |\n", "docs/story/B.md": "[잠정 · N3] 그리고 N10 언급\n"}) as d:
            r = dl.build(Path(d), dl.DEFAULT_SCOPE)
            self.assertEqual(r["next_free"]["N"], {"highest_in_tables": 3, "highest_incl_prose": 10, "next": 11})
            self.assertEqual(r["next_free"]["U"]["next"], 3)
            n3 = [e for e in r["entries"] if e["num"] == "N3"][0]
            self.assertEqual(n3["files"], ["docs/story/A.md", "docs/story/B.md"])
            self.assertEqual(n3["first"], "docs/story/A.md:1")

    def test_exit_code_on_overlap(self):
        with make({"docs/story/A.md": "| N1 | 장비 이름 규칙 | a |\n| N1 | 우두머리 목소리 | b |\n"}) as d:
            self.assertEqual(dl.main(["--root", d]), 1)


if __name__ == "__main__":
    unittest.main()
