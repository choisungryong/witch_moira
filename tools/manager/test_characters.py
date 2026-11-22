import json, struct, tempfile, threading, unittest, urllib.error, urllib.request
from pathlib import Path
import characters, server


def make_glb(path, nodes, animations):
    doc = json.dumps({'asset': {'version': '2.0'}, 'nodes': [{'name': n} for n in nodes], 'animations': [{'name': a} for a in animations],
                      'skins': [{}]}).encode('utf-8')
    doc += b' ' * (-len(doc) % 4)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'glTF' + struct.pack('<II', 2, 12 + 8 + len(doc)) + struct.pack('<II', len(doc), 0x4E4F534A) + doc)


SLOTS = {'slots': {
    'actor.hero.frost.model': {'kind': 'model', 'file': 'actors/hero/frost/model.glb', 'meta': 'actors/hero/frost/hero.json',
                               'contract': {'scale': 1.32, 'clips': {'run': 'run'}, 'pose': {'run_time_scale': 0.5333333, 'stride_world_m': 5.104}}},
    'actor.hero.ember.model': {'kind': 'model', 'file': '', 'planned': True},
    'actor.walker.model': {'kind': 'model', 'file': 'x.glb'}}}
CORE = 'extends RefCounted\nconst X := 1\nconst BASE_SPEED := 5.8\n'
WORLD = 'const CAMERA_OFFSET := Vector3(11,19,14)\n'
JUICE = '\tif camera != null:\n\t\tcamera.size = 19.5\n'


def make_root(tmp, body=True):
    root = Path(tmp)
    (root / 'chapter1' / 'art').mkdir(parents=True)
    (root / 'chapter1' / 'art' / 'asset_slots.json').write_text(json.dumps(SLOTS), encoding='utf-8')
    for rel, text in (('core/combat_core.gd', CORE), ('view/world/chapter_world.gd', WORLD), ('view/fx/combat_juice.gd', JUICE)):
        p = root / 'chapter1' / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding='utf-8')
    hero = root / 'chapter1' / 'art' / 'actors' / 'hero' / 'frost'
    hero.mkdir(parents=True)
    (hero / 'hero.json').write_text(json.dumps({'look': {'light_key': 0.65}}), encoding='utf-8')
    if body:
        make_glb(hero / 'model.glb', ['mixamorig:Hips', 'mixamorig:LeftToeBase', 'mixamorig:RightToeBase'], ['idle', 'run', 'walk'])
        (hero / 'model.pack-report.json').write_text(json.dumps({'clips': {'run': {'length_s': 0.53333, 'ground_speed_toe_mps': 7.2215, 'ground_speed_mps': 7.1168},
                                                                         'walk': {'length_s': 0.96667, 'ground_speed_toe_mps': 2.2125}}}), encoding='utf-8')
    return root


class CharacterData(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = Path(self.tmp.name) / 'work'
        self.root = make_root(Path(self.tmp.name) / 'repo')

    def tearDown(self):
        self.tmp.cleanup()

    def test_lines_only_hero_slots_and_body_flag(self):
        v = characters.list_lines(self.root)
        self.assertEqual([l['id'] for l in v['lines']], ['frost', 'ember'])
        self.assertEqual([l['has_body'] for l in v['lines']], [True, False])
        self.assertEqual(v['lines'][0]['name'], '냉기 마녀')

    def test_no_body_means_no_media(self):
        root = make_root(Path(self.tmp.name) / 'repo2', body=False)
        self.assertNotIn('body', characters.media_registry('frost', root, self.work))
        self.assertFalse(characters.list_lines(root)['lines'][0]['has_body'])

    def test_base_speed_read_and_not_invented(self):
        self.assertEqual(characters.read_base_speed(self.root)['value'], 5.8)
        (self.root / 'chapter1' / 'core' / 'combat_core.gd').write_text('const OTHER := 1\n', encoding='utf-8')
        v = characters.read_base_speed(self.root)
        self.assertIsNone(v['value'])
        self.assertIn('error', v)
        (self.root / 'chapter1' / 'core' / 'combat_core.gd').unlink()
        self.assertIsNone(characters.read_base_speed(self.root)['value'])

    def test_camera_read_and_not_invented(self):
        c = characters.read_camera(self.root)
        self.assertEqual((c['offset'], c['size']), ([11.0, 19.0, 14.0], 19.5))
        self.assertEqual(c['size_candidate'], 14.0)
        (self.root / 'chapter1' / 'view' / 'fx' / 'combat_juice.gd').write_text('nothing', encoding='utf-8')
        c = characters.read_camera(self.root)
        self.assertIsNone(c['size'])
        self.assertTrue(c['errors'])

    def test_glb_info_reads_bone_and_clip_names(self):
        info = characters.glb_info(self.root / 'chapter1' / 'art' / 'actors' / 'hero' / 'frost' / 'model.glb')
        self.assertEqual(info['animations'], ['idle', 'run', 'walk'])
        self.assertEqual(info['toe_bones'], ['mixamorig:LeftToeBase', 'mixamorig:RightToeBase'])
        bad = self.root / 'bad.glb'
        bad.write_bytes(b'not a glb at all')
        self.assertIn('error', characters.glb_info(bad))
        self.assertIn('error', characters.glb_info(self.root / 'missing.glb'))

    def test_detail_numbers(self):
        d = characters.detail('frost', self.root, self.work)
        self.assertAlmostEqual(d['rate_now'], 0.606, delta=0.001)
        self.assertEqual(d['run_clip'], 'run')
        self.assertEqual(d['game']['base_speed']['value'], 5.8)
        self.assertEqual(d['body']['clips']['walk']['g_toe'], 2.2125)
        self.assertEqual(d['media']['body']['url'], '/media/frost/body')
        self.assertIn('main', d['missing_media'])
        self.assertEqual(d['subject'], 'frost/locomotion')
        self.assertTrue(d['selfcheck'])
        self.assertFalse(d['warnings'])
        self.assertIsNone(characters.detail('nobody', self.root, self.work))

    def test_detail_warns_instead_of_inventing(self):
        (self.root / 'chapter1' / 'core' / 'combat_core.gd').write_text('', encoding='utf-8')
        d = characters.detail('frost', self.root, self.work)
        self.assertIsNone(d['rate_now'])
        self.assertTrue(any('이동 속도' in w for w in d['warnings']))

    def test_motions_candidate_appears_only_when_present(self):
        self.assertIsNone(characters.detail('frost', self.root, self.work)['motions'])
        make_glb(self.work / 'pipeline' / 'frost' / 'motions' / 'motions.glb', ['a'], ['walk_a'])
        d = characters.detail('frost', self.root, self.work)
        self.assertEqual(d['motions']['info']['animations'], ['walk_a'])
        self.assertIn('motions', d['media'])

    def test_media_path_only_registered_keys(self):
        for key in ('../x', 'body/../../x', '', 'nope', 'C:/x', 'body\\x'):
            self.assertIsNone(characters.media_path('frost', key, self.root, self.work))
        self.assertIsNone(characters.media_path('../frost', 'body', self.root, self.work))
        self.assertIsNotNone(characters.media_path('frost', 'body', self.root, self.work))

    def test_media_outside_repo_only_when_listed(self):
        img = self.work / 'char3d' / 'gen3d' / 'frost' / 'front.png'
        img.parent.mkdir(parents=True)
        img.write_bytes(b'\x89PNG')
        (self.work / 'char3d' / 'gen3d' / 'frost' / 'secret.txt').write_text('x', encoding='utf-8')
        self.assertEqual(characters.media_path('frost', 'apose_front', self.root, self.work), img)
        self.assertIsNone(characters.media_path('frost', 'secret', self.root, self.work))

    def test_real_repo_smoke(self):
        v = characters.list_lines()
        self.assertTrue(any(l['id'] == 'frost' for l in v['lines']))
        base = characters.read_base_speed()
        self.assertEqual(base['value'], 5.8, '코어의 BASE_SPEED 가 바뀌었으면 이 시험과 문서의 5.8 을 함께 본다')


class ServerRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.file = root / 'a.glb'
        cls.file.write_bytes(bytes(range(256)) * 4)
        cls.bad = root / 'a.txt'
        cls.bad.write_text('x', encoding='utf-8')
        cls.orig = characters.media_path
        characters.media_path = lambda line, key, *a, **k: {'body': cls.file, 'txt': cls.bad}.get(key) if line == 'frost' else None
        cls.srv = server.make_server(0)
        cls.port = cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        characters.media_path = cls.orig
        cls.tmp.cleanup()

    def get(self, path, headers=None, host=None):
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path))
        req.add_header('Host', host or '127.0.0.1:%d' % self.port)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()

    def test_media_full_and_range(self):
        status, h, body = self.get('/media/frost/body')
        self.assertEqual((status, h['Content-Type'], len(body)), (200, 'model/gltf-binary', 1024))
        self.assertEqual(h['Accept-Ranges'], 'bytes')
        status, h, body = self.get('/media/frost/body', {'Range': 'bytes=10-19'})
        self.assertEqual((status, h['Content-Range'], body), (206, 'bytes 10-19/1024', bytes(range(10, 20))))
        status, h, body = self.get('/media/frost/body', {'Range': 'bytes=1020-'})
        self.assertEqual((status, len(body)), (206, 4))
        status, h, body = self.get('/media/frost/body', {'Range': 'bytes=-8'})
        self.assertEqual((status, body), (206, bytes(range(256))[-8:]))
        self.assertEqual(self.get('/media/frost/body', {'Range': 'bytes=5000-'})[0], 416)
        self.assertEqual(self.get('/media/frost/body', {'Range': 'items=1-2'})[0], 416)

    def test_media_refusals(self):
        self.assertEqual(self.get('/media/frost/nope')[0], 404)
        self.assertEqual(self.get('/media/other/body')[0], 404)
        self.assertEqual(self.get('/media/frost/..%2Fbody')[0], 404)
        self.assertEqual(self.get('/media/frost/body/extra')[0], 404)
        self.assertEqual(self.get('/media/frost/txt')[0], 404)   # 허용 확장자가 아니다
        self.assertEqual(self.get('/media/frost/body', host='evil.example')[0], 403)

    def test_api_routes(self):
        status, _, body = self.get('/api/characters')
        self.assertEqual(status, 200)
        self.assertIn('lines', json.loads(body))
        self.assertEqual(self.get('/api/characters/nobody')[0], 404)
        self.assertEqual(self.get('/api/characters', host='evil.example')[0], 403)
        self.assertEqual(self.get('/api/picks')[0], 200)

    def test_three_files_served_by_exact_name_only(self):
        for name in sorted(server.THREE_FILES):
            self.assertTrue((server.APP / name).is_file(), name)
            status, h, _ = self.get('/' + name)
            self.assertEqual(status, 200, name)
            self.assertTrue(h['Content-Type'].startswith('text/javascript'))
        for name in ('/vendor/three/', '/vendor/three/README.md', '/vendor/three/LICENSE', '/vendor/three/addons/', '/vendor/three/../app.py', '/vendor/three/addons/loaders/Other.js'):
            self.assertEqual(self.get(name)[0], 404, name)
        self.assertEqual(self.get('/character.js')[0], 200)

    def test_character_js_has_no_outside_addresses(self):
        text = (server.APP / 'character.js').read_text(encoding='utf-8')
        import re
        for url in re.findall(r'https?://[^\s\'"`)]+', text):
            self.fail('character.js 에 바깥 주소가 있다: ' + url)


class UiShotHelpers(unittest.TestCase):
    def test_out_must_be_under_local(self):
        import ui_shot
        ok = ui_shot.check_out(ui_shot.ROOT / '_local' / 'shots' / 'x' / 'a.png')
        self.assertTrue(ok.is_relative_to((ui_shot.ROOT / '_local').resolve()))
        for bad in (ui_shot.ROOT / 'chapter1' / 'a.png', ui_shot.ROOT / '_local' / '..' / 'a.png', Path('C:/Windows/a.png')):
            with self.assertRaises(ui_shot.ShotError):
                ui_shot.check_out(bad)

    def test_parse_dom_reads_data_attributes(self):
        import ui_shot
        dom = '<html><body><section id="other" data-x="1"></section><section id="character" class="c" data-ready="1" data-a-rate="0.606" hidden></section></body></html>'
        self.assertEqual(ui_shot.parse_dom(dom), {'ready': '1', 'a-rate': '0.606'})
        self.assertIsNone(ui_shot.parse_dom('<p>none</p>'))


if __name__ == '__main__':
    unittest.main()
