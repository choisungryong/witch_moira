import json, tempfile, threading, unittest, urllib.request
from pathlib import Path

try:
    from . import tools_index, server
except ImportError:
    import tools_index, server


class ParseTests(unittest.TestCase):
    def test_py_header_and_examples(self):
        text = '"""한 줄 설명.\n\n    python tools/dev/x.py --a   # 주석\n    python tools/dev/x.py --b        뒤의 설명\n"""\nimport os\n'
        first, ex = tools_index.parse_py(text)
        self.assertEqual(first, '한 줄 설명.')
        self.assertEqual(ex, ['python tools/dev/x.py --a', 'python tools/dev/x.py --b'])

    def test_py_without_docstring_or_bad_syntax(self):
        self.assertEqual(tools_index.parse_py('x = 1\n'), ('', []))
        self.assertEqual(tools_index.parse_py('def (:\n'), ('', []))

    def test_gd_header_godot_command_becomes_godot_py(self):
        text = 'extends SceneTree\n## 측정 도구.\n##\n##   godot --headless --path <stage> --script res://chapter1/tests/a.gd -- --x\n##   ... -- --y\nconst A = 1\n'
        first, ex = tools_index.parse_gd(text)
        self.assertEqual(first, '측정 도구.')
        self.assertEqual(ex, ['python tools/dev/godot.py --headless --path . --script res://chapter1/tests/a.gd -- --x'])

    def test_gd_script_only_lines_get_a_command(self):
        text = 'extends SceneTree\n## 골든.\n##   --script res://chapter1/tests/g.gd   비교\n'
        self.assertEqual(tools_index.parse_gd(text)[1], ['python tools/dev/godot.py --headless --path . --script res://chapter1/tests/g.gd'])


class BuildTests(unittest.TestCase):
    def test_build_on_working_tree(self):
        d = tools_index.build()
        self.assertGreater(d['tool_count'], 20)
        self.assertEqual([w for w in d['warnings'] if '파일이 없습니다' in w], [], '색인이 가리키는 파일이 모두 있어야 한다')
        mapped = sum(len(r['tools']) for r in d['roles'])
        self.assertGreater(mapped, 20)
        self.assertTrue(all('header' in t for r in d['roles'] for t in r['tools']))

    def test_export_writes_utf8_lf_to_given_path_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'sub' / 'index.md'
            p, data = tools_index.export(out)
            raw = p.read_bytes()
            self.assertEqual(p, out)
            self.assertNotIn(b'\r', raw)
            self.assertIn('도구 색인'.encode('utf-8'), raw)
            self.assertFalse(list(Path(tmp).rglob('*.tmp')))

    def test_missing_map_yields_warning_not_crash(self):
        orig = tools_index.INDEX_JSON
        try:
            tools_index.INDEX_JSON = Path(tempfile.gettempdir()) / 'no-such-tools-index.json'
            d = tools_index.build()
            self.assertTrue(any('tools_index.json이 없어' in w for w in d['warnings']))
            self.assertEqual(d['roles'], [])
            self.assertEqual(len(d['unmapped']), d['tool_count'])
        finally:
            tools_index.INDEX_JSON = orig


class ServerTests(unittest.TestCase):
    def test_api_tools_and_static(self):
        httpd = server.make_server(0)
        port = httpd.server_port
        t = threading.Thread(target=httpd.serve_forever, daemon=True)
        t.start()
        try:
            def get(path):
                req = urllib.request.Request('http://127.0.0.1:%d%s' % (port, path), headers={'Host': '127.0.0.1:%d' % port})
                with urllib.request.urlopen(req) as r:
                    return r.status, r.read()
            st, body = get('/api/tools')
            self.assertEqual(st, 200)
            self.assertIn('roles', json.loads(body))
            self.assertEqual(get('/tools.js')[0], 200)
        finally:
            httpd.shutdown()
            httpd.server_close()


if __name__ == '__main__':
    unittest.main()
