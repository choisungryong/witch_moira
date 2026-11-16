import json, tempfile, threading, unittest, urllib.error, urllib.request
from pathlib import Path
import catalog, server


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = catalog.generate()

    def test_no_warnings_and_every_category_has_items(self):
        self.assertEqual(self.c['warnings'], [])
        for cat in self.c['categories']:
            self.assertGreater(cat['count'], 0, cat['key'])

    def test_ids_unique_and_sections_wellformed(self):
        ids = [e['id'] for e in self.c['entities']]
        self.assertEqual(len(ids), len(set(ids)))
        for e in self.c['entities']:
            for s in e['sections']:
                self.assertIn(s['kind'], ('pairs', 'table', 'lines'))
                if s['kind'] == 'table':
                    self.assertTrue(all(len(r) == len(s['columns']) for r in s['rows']), e['id'])

    def test_known_items(self):
        ids = {e['id'] for e in self.c['entities']}
        for want in ('run:skill:chapter1.skill.frost', 'perm:levels', 'combat:enemy:walker', 'gear:slots', 'world:zone:2', 'world:ritual:vigil'):
            self.assertIn(want, ids)
        self.assertEqual(len([e for e in self.c['entities'] if e['category'] == 'characters']), 3)
        self.assertEqual(len([e for e in self.c['entities'] if e['category'] == 'models']), 3)

    def test_tree_nodes_use_game_wording(self):
        node = next(e for e in self.c['entities'] if e['id'] == 'perm:node:witch.frost.needle')
        rows = node['sections'][0]['rows']
        self.assertEqual(len(rows), 5)
        self.assertEqual(rows[0][1], '관통 +1')

    def test_usage_scan(self):
        by = {e['id']: e for e in self.c['entities']}
        self.assertEqual(by['asset:chapter1/art/characters/frost_witch_v02.png']['usage'], 'direct')
        self.assertEqual(by['asset:chapter1/art/actors/hero.png']['usage'], 'composed')
        self.assertEqual(by['asset:chapter1/art/quality03_audio/fire_0.wav']['usage'], 'composed')
        self.assertEqual(by['asset:chapter1/art/quality03/ground_flagstone_v01.png']['usage'], 'direct')

    def test_gd_const_parser(self):
        text = 'const A := [Vector2(0,0),Vector2(48,0)]\nconst B := ["x","y"]\nconst C := [{"id":"r","n":1,"p":Vector2(8,-7)}]\n'
        self.assertEqual(catalog.gd_const(text, 'A')[1], {'x': 48.0, 'y': 0.0})
        self.assertEqual(catalog.gd_const(text, 'B'), ['x', 'y'])
        self.assertEqual(catalog.gd_const(text, 'C')[0]['p'], {'x': 8.0, 'y': -7.0})
        with self.assertRaisesRegex(ValueError, 'Missing constant Z'):
            catalog.gd_const(text, 'Z')

    def test_hundredths_matches_game(self):
        self.assertEqual([catalog.hundredths(v) for v in (500, 1050, 1005, 0)], ['5', '10.5', '10.05', '0'])


class StateTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / 'state.json'
        self.ids = {'a', 'b'}

    def tearDown(self):
        self.dir.cleanup()

    def test_save_and_revision(self):
        code, v = server.update_state({'revision': 0, 'id': 'a', 'changes': {'status': 'review', 'notes': '메모'}}, self.ids, self.path)
        self.assertEqual((code, v['revision']), (200, 1))
        self.assertEqual(server.load_state(self.path)['records']['a']['notes'], '메모')
        code, v = server.update_state({'revision': 0, 'id': 'a', 'changes': {'status': 'done'}}, self.ids, self.path)
        self.assertEqual(code, 409)
        self.assertEqual(v['records']['a']['status'], 'review')
        self.assertFalse(self.path.with_suffix('.tmp').exists())

    def test_rejects_bad_input(self):
        bad = [{}, {'revision': 0, 'id': 'zzz', 'changes': {'notes': 'x'}}, {'revision': -1, 'id': 'a', 'changes': {'notes': 'x'}},
               {'revision': True, 'id': 'a', 'changes': {'notes': 'x'}}, {'revision': 0, 'id': 'a', 'changes': {}},
               {'revision': 0, 'id': 'a', 'changes': {'status': 'bogus'}}, {'revision': 0, 'id': 'a', 'changes': {'priority': 'x'}},
               {'revision': 0, 'id': 'a', 'changes': {'other': 'x'}}, {'revision': 0, 'id': 'a', 'changes': {'notes': 5}},
               {'revision': 0, 'id': 'a', 'changes': {'notes': 'x' * 12001}}, {'revision': 0, 'id': 'a', 'changes': {'notes': 'x'}, 'extra': 1}]
        for payload in bad:
            with self.assertRaises(ValueError, msg=str(payload)[:60]):
                server.update_state(payload, self.ids, self.path)
        self.assertFalse(self.path.exists())

    def test_trusted_request(self):
        self.assertTrue(server.trusted_request('127.0.0.1:8781', None, 8781))
        self.assertFalse(server.trusted_request('evil.com', None, 8781))
        self.assertFalse(server.trusted_request('127.0.0.1:8781', 'http://evil.com', 8781))


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.original = server.STATE
        server.STATE = Path(cls.tmp.name) / 'state.json'
        cls.srv = server.make_server(0)
        cls.port = cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        server.STATE = cls.original
        cls.tmp.cleanup()

    def get(self, path, host=None):
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path), headers={'Host': host or '127.0.0.1:%d' % self.port})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def post(self, body, origin=None):
        headers = {'Content-Type': 'application/json'}
        if origin:
            headers['Origin'] = origin
        req = urllib.request.Request('http://127.0.0.1:%d/api/management' % self.port, json.dumps(body).encode(), headers)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_bound_to_loopback(self):
        self.assertEqual(self.srv.server_address[0], '127.0.0.1')

    def test_catalog_and_static(self):
        status, body = self.get('/api/catalog')
        self.assertEqual(status, 200)
        self.assertGreater(len(json.loads(body)['entities']), 100)
        for p in ('/', '/app.js', '/app.css', '/vendor/model-viewer.min.js'):
            self.assertEqual(self.get(p)[0], 200, p)
        self.assertEqual(self.get('/local-state.json')[0], 404)
        self.assertEqual(self.get('/server.py')[0], 404)

    def test_files_allow_list_and_escape(self):
        self.assertEqual(self.get('/files/chapter1/art/characters/frost_witch_v02.png')[0], 200)
        self.assertEqual(self.get('/files/chapter1/art/chained_warden/v01/chained_demon_animated.glb')[0], 200)
        for p in ('/files/../project.godot', '/files/%2e%2e/project.godot', '/files/chapter1/../project.godot', '/files/project.godot',
                  '/files/CLAUDE.md', '/files/C:/Windows/win.ini', '/files/chapter1%5C..%5Cproject.godot', '/files//etc/passwd',
                  '/files/chapter1/art/characters/frost_witch_v02.png.import', '/files/tools/manager/local-state.json',
                  '/files/chapter1/core/chapter_profile.gd'):
            self.assertEqual(self.get(p)[0], 404, p)

    def test_host_check(self):
        self.assertEqual(self.get('/api/catalog', host='evil.example')[0], 403)

    def test_post_flow(self):
        origin = 'http://127.0.0.1:%d' % self.port
        status, state = self.post({'revision': 0, 'id': 'run:xp', 'changes': {'notes': '확인'}}, origin)
        self.assertEqual((status, state['revision']), (200, 1))
        self.assertEqual(self.post({'revision': 0, 'id': 'run:xp', 'changes': {'notes': 'x'}}, origin)[0], 409)
        self.assertEqual(self.post({'revision': 1, 'id': 'nope', 'changes': {'notes': 'x'}}, origin)[0], 400)
        self.assertEqual(self.post({'revision': 1, 'id': 'run:xp', 'changes': {'notes': 'x'}}, 'http://evil.com')[0], 403)


if __name__ == '__main__':
    unittest.main()
