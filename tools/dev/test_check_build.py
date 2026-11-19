#!/usr/bin/env python3
"""check_build.py의 빌드가 필요 없는 부분의 자체 검사(run_all.py의 tools-selftest가 돌린다).

창·빌드·Godot를 쓰지 않는다. 하는 일: 점검기 안의 --self-test 사례 전부, 그리고
"chapter1/data/*.json 가운데 REQUIRED_IN_PCK 목록에 없는 것이 없다"(새 데이터 파일이 목록에서 빠지면 여기서 실패한다).

  python tools/dev/test_check_build.py
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_build as cb  # noqa: E402


class CheckBuildTests(unittest.TestCase):
    def test_every_data_file_is_in_the_required_list(self):
        self.assertEqual(cb.data_files_not_listed(), [],
                         "chapter1/data 에 새 json 이 생겼다: tools/dev/check_build.py 의 REQUIRED_IN_PCK 에 더한다")
        self.assertIn('res://chapter1/data/run_spells.json', cb.REQUIRED_IN_PCK)

    def test_a_missing_data_file_is_reported_and_a_listed_one_is_not(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ('a.json', 'new_one.json'):
                (Path(folder) / name).write_text('{}', encoding='utf-8')
            (Path(folder) / 'notes.txt').write_text('x', encoding='utf-8')
            found = cb.data_files_not_listed(Path(folder), ('res://chapter1/data/a.json',))
            self.assertEqual(found, ['res://chapter1/data/new_one.json'])

    def test_pck_check_fails_when_the_required_data_file_is_gone(self):
        files = [name for name in cb.REQUIRED_IN_PCK if not name.endswith('run_spells.json')]
        _, _, missing = cb.evaluate_pck(files)
        self.assertEqual(missing, ['res://chapter1/data/run_spells.json'])

    def test_built_in_self_test_has_no_failure(self):
        report = cb.Report()
        cb.self_test(report)
        self.assertTrue(report.rows)
        self.assertEqual([row for row in report.rows if row['status'] == 'FAIL'], [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
