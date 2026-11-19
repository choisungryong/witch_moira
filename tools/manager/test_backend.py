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
        # hero.png used to be "composed" (folder + name); it is now named by the slot table (asset_slots.json), which the code reads
        self.assertEqual(by['asset:chapter1/art/actors/hero.png']['usage'], 'direct')
        self.assertTrue(any('asset_slots.json' in n for n in by['asset:chapter1/art/actors/hero.png']['usage_notes']))
        self.assertEqual(by['asset:chapter1/art/quality03_audio/fire_0.wav']['usage'], 'composed')
        self.assertEqual(by['asset:chapter1/art/quality03/ground_flagstone_v01.png']['usage'], 'direct')

    def test_files_named_only_by_the_slot_table_count_as_reached(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            def put(rel, text):
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                (root / rel).write_text(text, encoding='utf-8')
            put('chapter1/ChapterOne.tscn', '[ext_resource path="res://chapter1/view/resolver.gd"]\n')
            put('chapter1/view/resolver.gd', 'const T := "res://chapter1/art/asset_slots.json"\n')
            put('chapter1/art/asset_slots.json', json.dumps({'slots': {'a.b': {'kind': 'sprite_sheet', 'file': 'x/only_slot.png', 'meta': 'x/side.json'}}}))
            put('chapter1/art/x/only_slot.png', 'png')
            put('chapter1/art/x/side.json', json.dumps({'overlay': 'x/only_in_side.png'}))
            put('chapter1/art/x/only_in_side.png', 'png')
            put('chapter1/art/x/nobody.png', 'png')
            put('chapter1/data/audio_map.json', json.dumps({'cues': {'hit': {'file': 'audio/hit.wav'}}}))
            put('chapter1/art/audio/hit.wav', 'wav')
            original = catalog.ROOT
            catalog.ROOT = root
            try:
                reached, direct, _, _ = catalog.scan_references()
            finally:
                catalog.ROOT = original
            self.assertIn('chapter1/art/x/only_slot.png', direct)
            self.assertIn('chapter1/art/x/only_in_side.png', reached)   # named by a side JSON of a slot
            self.assertNotIn('chapter1/art/x/nobody.png', reached)
            self.assertNotIn('chapter1/art/audio/hit.wav', reached)     # audio_map.json is not read by anything here

    def test_run_spells_entity_reads_the_data_file(self):
        e = next(e for e in self.c['entities'] if e['id'] == 'run:spells')
        data = json.loads((catalog.ROOT / 'chapter1/data/run_spells.json').read_text(encoding='utf-8'))
        self.assertEqual(e['category'], 'run')
        self.assertIn('꺼짐' if data['enabled'] is False else '켜짐', e['name'])
        spells = next(s for s in e['sections'] if s['title'] == '주문')
        self.assertEqual(len(spells['rows']), len(data['spells']))
        pairs = next(s for s in e['sections'] if s['title'] == '조합')
        self.assertEqual(len(pairs['rows']), len(data['pairs']))

    def test_gd_const_parser(self):
        text = 'const A := [Vector2(0,0),Vector2(48,0)]\nconst B := ["x","y"]\nconst C := [{"id":"r","n":1,"p":Vector2(8,-7)}]\n'
        self.assertEqual(catalog.gd_const(text, 'A')[1], {'x': 48.0, 'y': 0.0})
        self.assertEqual(catalog.gd_const(text, 'B'), ['x', 'y'])
        self.assertEqual(catalog.gd_const(text, 'C')[0]['p'], {'x': 8.0, 'y': -7.0})
        with self.assertRaisesRegex(ValueError, 'Missing constant Z'):
            catalog.gd_const(text, 'Z')

    def count(self, prefix):
        return len([e for e in self.c['entities'] if e['id'].startswith(prefix)])

    def test_gear_counts_match_loot_json(self):
        L = json.loads((catalog.ROOT / 'chapter1/data/loot.json').read_text(encoding='utf-8'))
        self.assertEqual(L['schema_version'], 2)
        self.assertEqual(self.count('gear:base:'), len(L['bases']))
        self.assertEqual(self.count('gear:affix:'), len(L['affixes']))
        self.assertEqual(self.count('gear:legendary:'), len(L['legendaries']))
        self.assertEqual(self.count('gear:unique:'), len(L['uniques']))
        self.assertEqual(self.count('gear:treasure:'), len(L['treasure_classes']))
        slots = next(e for e in self.c['entities'] if e['id'] == 'gear:slots')
        self.assertEqual(len(slots['sections'][0]['rows']), len(L['equip_slots']))
        self.assertEqual(len(slots['sections'][1]['rows']), len(L['qualities']))
        self.assertFalse(any('chapter_items' in (e.get('source') or {}).get('path', '') for e in self.c['entities']))

    def test_combat_counts_match_tuning_json(self):
        T = json.loads((catalog.ROOT / 'chapter1/data/combat_tuning.json').read_text(encoding='utf-8'))
        self.assertEqual(self.count('combat:enemy:'), len(T['enemies']))
        self.assertEqual(self.count('combat:champion:'), len(T['champions']))
        walker = next(e for e in self.c['entities'] if e['id'] == 'combat:enemy:walker')
        self.assertEqual([r[1] for r in walker['sections'][0]['rows']], [str(v) for v in T['enemies']['walker']['hp']])
        potion = next(e for e in self.c['entities'] if e['id'] == 'combat:potion')
        self.assertIn(str(T['potion']['start']), potion['summary'])
        xp = next(e for e in self.c['entities'] if e['id'] == 'combat:xp')
        self.assertEqual(len(xp['sections'][0]['rows']), len(T['xp_thresholds']))
        self.assertEqual(self.count('world:zone:'), len(T['seal_kills']))

    def test_permanent_growth_counts_match_json(self):
        D = catalog.ROOT / 'chapter1/data'
        trees = json.loads((D / 'skill_trees.json').read_text(encoding='utf-8'))['trees']
        prog = json.loads((D / 'character_progression.json').read_text(encoding='utf-8'))
        self.assertEqual(self.count('perm:tree:'), len(trees))
        self.assertEqual(self.count('perm:node:'), sum(len(t['nodes']) for t in trees))
        lv = next(e for e in self.c['entities'] if e['id'] == 'perm:levels')
        self.assertEqual(len(lv['sections'][0]['rows']), len(prog['xp_thresholds']))

    def test_agents_listed_from_definition_files(self):
        files = sorted((catalog.ROOT / '.claude/agents').glob('*.md'))
        agents = [e for e in self.c['entities'] if e['category'] == 'agents' and e['type'] == '에이전트 정의']
        self.assertEqual(sorted(e['id'] for e in agents), sorted('agents:' + f.stem for f in files))
        for e in agents:
            self.assertIn(dict(e['sections'][0]['rows']).get('모델'), ('opus', 'sonnet', 'haiku', '(지정 없음)'), e['id'])

    def test_frontmatter_parser(self):
        meta = catalog.parse_frontmatter('---\nname: x\ndescription: 가. 나.\nmodel: opus\n---\n본문: 아님\n')
        self.assertEqual(meta, {'name': 'x', 'description': '가. 나.', 'model': 'opus'})
        with self.assertRaises(ValueError):
            catalog.parse_frontmatter('본문만')

    def test_docs_and_agents_with_temp_root(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for sub in ('docs/story', 'docs/reviews', '.claude/agents'):
                (root / sub).mkdir(parents=True)
            body = '# 제목\n\n본문\n'
            for rel in ('docs/SEASON1_WORLD_STORY_MASTER.md', 'docs/story/LAW.ko.md', 'docs/reviews/R.ko.md'):
                (root / rel).write_text(body, encoding='utf-8')
            (root / '.claude/agents/a.md').write_text('---\nname: a\ndescription: 첫 문장. 둘째.\nmodel: sonnet\n---\n', encoding='utf-8')
            (root / '.claude/agents/bad.md').write_text('머리글 없음', encoding='utf-8')
            old, catalog.ROOT = catalog.ROOT, root
            try:
                c = catalog.Catalog()
                catalog.doc_entities(c)
                catalog.agent_entities(c)
            finally:
                catalog.ROOT = old
            kinds = {e['id']: e['type'] for e in c.entities}
            self.assertEqual(kinds['doc:docs/SEASON1_WORLD_STORY_MASTER.md'], '세계관·스토리')
            self.assertEqual(kinds['doc:docs/story/LAW.ko.md'], '세계관·스토리')
            self.assertEqual(kinds['doc:docs/reviews/R.ko.md'], '검수')
            self.assertIn('agents:a', kinds)
            self.assertNotIn('agents:bad', kinds)
            self.assertEqual(len(c.warnings), 1)
            self.assertIn('첫 문장.', next(e for e in c.entities if e['id'] == 'agents:a')['summary'])

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

    def test_every_page_asset_is_served(self):
        import re
        html = (server.APP / 'index.html').read_text(encoding='utf-8')
        for ref in re.findall(r'(?:src|href)="/([^"#]+)"', html):
            self.assertEqual(self.get('/' + ref)[0], 200, ref)

    def test_new_static_file_served_without_restart(self):
        with tempfile.TemporaryDirectory() as d:
            app = Path(d)
            (app / 'index.html').write_text('x', encoding='utf-8')
            (app / 'server.py').write_text('x', encoding='utf-8')
            (app / 'local-state.json').write_text('{}', encoding='utf-8')
            original = server.APP
            server.APP = app
            try:
                self.assertEqual(self.get('/later.js')[0], 404)
                (app / 'later.js').write_text('1', encoding='utf-8')   # appears after the server started
                self.assertEqual(self.get('/later.js')[0], 200)
                self.assertEqual(self.get('/server.py')[0], 404)
                self.assertEqual(self.get('/local-state.json')[0], 404)
                self.assertEqual(self.get('/..%2Fserver.py')[0], 404)
            finally:
                server.APP = original
        self.assertIn('tools.js', server.static_names())
        self.assertNotIn('server.py', server.static_names())

    def test_stale_server_report(self):
        with tempfile.TemporaryDirectory() as d:
            app = Path(d)
            (app / 'catalog.py').write_text('a = 1', encoding='utf-8')
            started = server.code_snapshot(app)
            self.assertFalse(server.stale_report(started, app)['stale'])
            (app / 'catalog.py').write_text('a = 22', encoding='utf-8')
            (app / 'new_module.py').write_text('', encoding='utf-8')
            report = server.stale_report(started, app)
            self.assertTrue(report['stale'])
            self.assertEqual((report['changed'], report['added']), (['catalog.py'], ['new_module.py']))
        # The HTTP route reads server.APP; point it (and the snapshot the server took at start-up) at a fake folder, so that
        # another agent editing the real tools/manager/*.py while this runs cannot make the route report "stale".
        with tempfile.TemporaryDirectory() as d:
            fake = Path(d)
            (fake / 'catalog.py').write_text('a = 1', encoding='utf-8')
            real_app, real_started = server.APP, self.srv.code_started
            server.APP = fake
            self.srv.code_started = server.code_snapshot(fake)
            try:
                status, body = self.get('/api/server')
                self.assertEqual(status, 200)
                self.assertFalse(json.loads(body)['stale'])
                (fake / 'catalog.py').write_text('a = 22', encoding='utf-8')
                self.assertTrue(json.loads(self.get('/api/server')[1])['stale'])
            finally:
                server.APP, self.srv.code_started = real_app, real_started

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
