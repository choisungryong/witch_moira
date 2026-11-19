"""audit.py 자체 검사. 임시 폴더만 쓴다.  python -m unittest discover -s tools/dev -p "test_audit.py" -v"""
from pathlib import Path
import json, sys, tempfile, unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit


def fake_line(name, values, direction=audit.LOWER, detail=None):
    def fn(ctx):
        return {'metrics': [audit.metric(k, k, v, direction) for k, v in values.items()], 'detail': detail or []}
    return (name, name, fn)


def dying_line(name, error):
    def fn(ctx):
        raise error
    return (name, name, fn)


def seen(values, direction=audit.LOWER):
    return {'id': 'x', 'status': 'seen', 'metrics': [audit.metric(k, k, v, direction) for k, v in values.items()]}


class CompareTests(unittest.TestCase):
    def test_worse_direction(self):
        self.assertTrue(audit.is_worse(audit.LOWER, 1))
        self.assertFalse(audit.is_worse(audit.LOWER, -1))
        self.assertTrue(audit.is_worse(audit.HIGHER, -1))
        self.assertFalse(audit.is_worse(audit.HIGHER, 1))
        self.assertFalse(audit.is_worse(audit.INFO, 5))
        self.assertFalse(audit.is_worse(audit.LOWER, 0))

    def test_compare_marks_worse_and_delta(self):
        cur = dict(seen({'a': 5, 'b': 2}), id='x')
        audit.compare(cur, seen({'a': 3, 'b': 4}))
        by = {m['key']: m for m in cur['metrics']}
        self.assertEqual((by['a']['previous'], by['a']['delta'], by['a']['worse']), (3, 2, True))
        self.assertEqual((by['b']['delta'], by['b']['worse']), (-2, False))
        self.assertTrue(cur['worse'])

    def test_first_run_has_no_baseline(self):
        cur = seen({'a': 5})
        audit.compare(cur, None)
        self.assertFalse(cur['worse'])
        self.assertIsNone(cur['metrics'][0]['previous'])

    def test_unseen_after_seen_is_worse_but_not_after_unseen(self):
        gone = {'id': 'x', 'status': 'unseen', 'metrics': []}
        audit.compare(gone, seen({'a': 1}))
        self.assertTrue(gone['worse'])
        gone2 = {'id': 'x', 'status': 'unseen', 'metrics': []}
        audit.compare(gone2, {'id': 'x', 'status': 'unseen', 'metrics': []})
        self.assertFalse(gone2['worse'])

    def test_strict_hole(self):
        self.assertTrue(audit.has_hole(dict(seen({'a': 1}), status='seen')))
        self.assertFalse(audit.has_hole(seen({'a': 0})))
        self.assertFalse(audit.has_hole(seen({'a': 9}, audit.INFO)))
        self.assertTrue(audit.has_hole({'status': 'unseen', 'metrics': []}))


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.local = Path(self.tmp.name) / '_local'
        self.local.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def run_once(self, stamp, lines, **kw):
        return audit.run_audit(Path(self.tmp.name), self.local, self.local / 'audit' / stamp, lines=lines, **kw)

    def test_baseline_then_worse_then_better(self):
        result, code = self.run_once('20260101-000001', [fake_line('a', {'n': 3})])
        self.assertEqual(code, 0)
        self.assertTrue((self.local / 'audit' / '20260101-000001' / 'audit.json').is_file())
        self.assertTrue((self.local / 'audit' / '20260101-000001' / 'audit.md').is_file())
        result, code = self.run_once('20260101-000002', [fake_line('a', {'n': 3})])
        self.assertEqual(code, 0)
        result, code = self.run_once('20260101-000003', [fake_line('a', {'n': 4})])
        self.assertEqual(code, 1)
        self.assertEqual(result['worse'], ['a'])
        self.assertEqual(result['lines'][0]['metrics'][0]['delta'], 1)
        result, code = self.run_once('20260101-000004', [fake_line('a', {'n': 2})])
        self.assertEqual(code, 0)

    def test_strict_fails_on_any_hole(self):
        _, code = self.run_once('20260101-000001', [fake_line('a', {'n': 3})], strict=True)
        self.assertEqual(code, 1)
        _, code = self.run_once('20260101-000002', [fake_line('a', {'n': 0})], strict=True)
        self.assertEqual(code, 0)

    def test_one_dying_tool_only_unseen_that_line(self):
        lines = [fake_line('a', {'n': 1}), dying_line('b', RuntimeError('boom')), dying_line('c', audit.Unseen('도구가 없다')), fake_line('d', {'n': 0})]
        result, code = self.run_once('20260101-000001', lines)
        by = {l['id']: l for l in result['lines']}
        self.assertEqual([by[k]['status'] for k in 'abcd'], ['seen', 'unseen', 'unseen', 'seen'])
        self.assertIn('boom', by['b']['reason'])
        self.assertEqual(code, 0)  # 처음이라 기준선
        # 지난번엔 봤던 줄이 이번에 죽으면 나빠짐
        result, code = self.run_once('20260101-000002', [fake_line('a', {'n': 1}), dying_line('d', RuntimeError('x'))])
        self.assertEqual(result['worse'], ['d'])
        self.assertEqual(code, 1)

    def test_only_keeps_other_lines_baseline(self):
        self.run_once('20260101-000001', [fake_line('a', {'n': 1}), fake_line('b', {'n': 1})])
        self.run_once('20260101-000002', [fake_line('a', {'n': 1}), fake_line('b', {'n': 1})], only={'a'})
        result, code = self.run_once('20260101-000003', [fake_line('a', {'n': 1}), fake_line('b', {'n': 5})])
        by = {l['id']: l for l in result['lines']}
        self.assertEqual(by['b']['previous_run'], '20260101-000001')
        self.assertEqual(code, 1)

    def test_markdown_has_notice_and_arrows(self):
        self.run_once('20260101-000001', [fake_line('a', {'n': 1})])
        self.run_once('20260101-000002', [fake_line('a', {'n': 2})])
        text = (self.local / 'audit' / '20260101-000002' / 'audit.md').read_text(encoding='utf-8')
        self.assertIn('기록의 유무와 일치만 본다', text)
        self.assertIn('▲', text)
        self.assertEqual(audit.latest_result(self.local / 'audit')['lines'][0]['id'], 'a')


class PureLineTests(unittest.TestCase):
    def test_disabled_blocks(self):
        tree = {'a': {'enabled': False, 'x': {'enabled': False}}, 'b': {'enabled': True}, 'c': [{'enabled': False}]}
        self.assertEqual(sorted(audit.disabled_blocks(tree)), ['a', 'a.x', 'c[0]'])

    def test_doc_paths_filters(self):
        text = '`chapter1/core/a.gd:12` `res://chapter1/x.json` `docs/<name>.md` `docs/story/*.md` `tools/dev/` `foo/bar` `_local/x.py` `docs/a b.md`'
        self.assertEqual([p for p, _ in audit.doc_paths(text)], ['chapter1/core/a.gd', 'chapter1/x.json', 'tools/dev/'])

    def test_similar_groups(self):
        groups = audit.similar_groups(['sheet_t1.py', 'sheet_t2.py', 'sheet_t3.py', 'build.py', 'other.py'])
        self.assertEqual(list(groups), ['sheet_t'])

    def test_doc_paths_line_and_switches_on_temp_repo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'docs').mkdir()
            (root / 'chapter1' / 'data').mkdir(parents=True)
            (root / 'docs' / 'A.md').write_text('`docs/A.md` `docs/none.md`', encoding='utf-8')
            (root / 'CLAUDE.md').write_text('`rhythm.enabled`', encoding='utf-8')
            (root / 'chapter1' / 'data' / 't.json').write_text(json.dumps({'rhythm': {'enabled': False, 'trial': {'enabled': False}}}), encoding='utf-8')
            ctx = audit.Context(root, root / '_local', root / '_local' / 'w')
            got = audit.line_doc_paths(ctx)
            self.assertEqual(got['metrics'][0]['value'], 1)
            self.assertEqual(got['detail'], ['docs/A.md -> docs/none.md'])
            sw = {m['key']: m['value'] for m in audit.line_switches(ctx)['metrics']}
            self.assertEqual(sw, {'unnoted': 1, 'disabled': 2})


if __name__ == '__main__':
    unittest.main(verbosity=2)
