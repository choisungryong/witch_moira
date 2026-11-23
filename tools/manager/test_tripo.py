import io, json, os, struct, tempfile, threading, unittest, urllib.error, urllib.request
from pathlib import Path
import characters, server
from test_characters import make_glb


def glb_bytes(tmp):
    p = Path(tmp) / 'src.glb'
    make_glb(p, ['n'], ['a'])
    return p.read_bytes()


def png_header(w, h):
    return b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', w, h) + bytes(10)


class TripoStore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = Path(self.tmp.name) / 'work'
        self.work.mkdir()
        self.data = glb_bytes(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name='My Model (v2).glb', data=None, **kw):
        data = self.data if data is None else data
        return characters.receive_glb('frost', name, io.BytesIO(data), len(data), work=self.work, **kw)

    def out_dir(self):
        return self.work / 'pipeline' / 'frost' / 'tripo_out'

    def test_safe_name(self):
        self.assertEqual(characters.safe_name('My Model (v2).GLB'), 'My_Model__v2_')
        self.assertEqual(characters.safe_name('../../etc/passwd.glb'), 'passwd')
        self.assertEqual(characters.safe_name('한글.glb'), '__')
        self.assertEqual(characters.safe_name('.glb'), 'model')
        self.assertEqual(len(characters.safe_name('a' * 200 + '.glb')), 60)

    def test_upload_normal_and_listing(self):
        saved = self.put()
        d = self.out_dir()
        self.assertRegex(saved, r'^\d{8}-\d{6}_My_Model__v2_\.glb$')
        self.assertEqual((d / saved).read_bytes(), self.data)
        self.assertEqual([p.name for p in d.iterdir()], [saved])      # 임시 파일이 남지 않음
        info = characters.tripo_info('frost', work=self.work)
        self.assertEqual([o['name'] for o in info['outputs']], [saved])
        self.assertIs(info['outputs'][0]['has_skin'], True)      # 시험용 glb 는 skins 가 하나 있다
        self.assertIs(info['outputs'][0]['has_texture'], False)
        self.assertEqual(info['outputs'][0]['bytes'], len(self.data))
        self.assertEqual(characters.media_registry('frost', work=self.work)['tout_0']['path'], d / saved)

    def test_never_overwrites(self):
        a = self.put()
        first = (self.out_dir() / a).read_bytes()
        other = self.data + b'\0\0\0\0'
        names = {a, self.put(data=other), self.put(data=other)}
        self.assertEqual(len(names), 3)
        self.assertEqual((self.out_dir() / a).read_bytes(), first)

    def test_rejections(self):
        for name, data, status in (('a.gltf', self.data, 400), ('a.glb', b'NOTAGLB' + b'x' * 20, 400), ('a.glb', b'', 411)):
            with self.assertRaises(characters.UploadError) as c:
                characters.receive_glb('frost', name, io.BytesIO(data), len(data), work=self.work)
            self.assertEqual(c.exception.status, status, name)
        with self.assertRaises(characters.UploadError) as c:
            self.put(limit=10)
        self.assertEqual(c.exception.status, 413)
        with self.assertRaises(characters.UploadError) as c:        # 중간에 끊긴 업로드
            characters.receive_glb('frost', 'a.glb', io.BytesIO(self.data[:20]), len(self.data), work=self.work)
        self.assertEqual(c.exception.status, 400)
        with self.assertRaises(characters.UploadError) as c:
            characters.receive_glb('nobody', 'a.glb', io.BytesIO(self.data), len(self.data), work=self.work)
        self.assertEqual(c.exception.status, 404)
        with self.assertRaises(characters.UploadError) as c:
            characters.receive_glb('frost', 'a.glb', io.BytesIO(self.data), len(self.data), work=Path(self.tmp.name) / 'missing')
        self.assertEqual(c.exception.status, 404)
        self.assertEqual(list(self.out_dir().iterdir()) if self.out_dir().exists() else [], [])   # 거부된 것은 남기지 않음

    def test_dir_words_fixed(self):
        self.assertEqual(characters.tripo_dir('frost', 'tripo_in', work=self.work), self.work / 'pipeline' / 'frost' / 'tripo_in')
        for bad in ('tripo', '../x', 'tripo_in/..', '', None, 'chapter1'):
            self.assertIsNone(characters.tripo_dir('frost', bad, work=self.work))
        self.assertIsNone(characters.tripo_dir('../frost', 'tripo_in', work=self.work))

    def test_open_folder(self):
        opened = []
        orig = characters._startfile
        characters._startfile = opened.append
        try:
            ok, _ = characters.open_folder('frost', 'tripo_in', work=self.work)
            self.assertFalse(ok)
            self.assertFalse((self.work / 'pipeline').exists())           # 만들지 않음
            (self.work / 'pipeline' / 'frost' / 'tripo_in').mkdir(parents=True)
            ok, _ = characters.open_folder('frost', 'tripo_in', work=self.work)
            self.assertTrue(ok)
            self.assertEqual(opened, [self.work / 'pipeline' / 'frost' / 'tripo_in'])
            for bad in ('chapter1', '..', 'tripo_in/x'):
                with self.assertRaises(ValueError):
                    characters.open_folder('frost', bad, work=self.work)
        finally:
            characters._startfile = orig

    def test_info_without_work_root(self):
        info = characters.tripo_info('frost', work=Path(self.tmp.name) / 'missing')
        self.assertFalse(info['work_found'])
        self.assertIn('MOIRA_WORK_ROOT', info['rule'])

    def test_info_lists_input_pngs_with_size(self):
        d = self.work / 'pipeline' / 'frost' / 'tripo_in'
        d.mkdir(parents=True)
        (d / 'front.png').write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 1024, 1024) + b'\0' * 10)
        (d / 'note.txt').write_text('x', encoding='utf-8')
        info = characters.tripo_info('frost', work=self.work)
        self.assertEqual([(r['name'], r['width'], r['height']) for r in info['inputs']], [('front.png', 1024, 1024)])
        self.assertIn('--names front,left,back --square', info['split_cmd'])


class TripoHttp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.work = Path(cls.tmp.name) / 'work'
        cls.work.mkdir()
        cls.old_env = os.environ.get('MOIRA_WORK_ROOT')
        os.environ['MOIRA_WORK_ROOT'] = str(cls.work)
        cls.data = glb_bytes(cls.tmp.name)
        cls.srv = server.make_server(0)
        cls.port = cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        if cls.old_env is None:
            os.environ.pop('MOIRA_WORK_ROOT', None)
        else:
            os.environ['MOIRA_WORK_ROOT'] = cls.old_env
        cls.tmp.cleanup()

    def post(self, path, body, ctype='application/octet-stream', host=None, origin=None):
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path), data=body, method='POST')
        req.add_header('Host', host or '127.0.0.1:%d' % self.port)
        req.add_header('Content-Type', ctype)
        if origin:
            req.add_header('Origin', origin)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def get(self, path):
        try:
            with urllib.request.urlopen('http://127.0.0.1:%d%s' % (self.port, path)) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def test_upload_list_and_serve(self):
        status, v = self.post('/api/characters/frost/tripo_out?name=hero%20test.glb', self.data)
        self.assertEqual(status, 200, v)
        self.assertTrue((self.work / 'pipeline' / 'frost' / 'tripo_out' / v['saved']).is_file())
        info = json.loads(self.get('/api/characters/frost/tripo')[1])
        self.assertIn(v['saved'], [o['name'] for o in info['outputs']])
        key = next(o['key'] for o in info['outputs'] if o['name'] == v['saved'])
        self.assertEqual(self.get('/media/frost/' + key), (200, self.data))
        self.assertEqual(self.get('/api/characters/nobody/tripo')[0], 404)

    def test_refusals(self):
        self.assertEqual(self.post('/api/characters/frost/tripo_out?name=a.txt', self.data)[0], 400)
        self.assertEqual(self.post('/api/characters/frost/tripo_out?name=a.glb', b'NOTAGLBxxxxxxxx')[0], 400)
        self.assertEqual(self.post('/api/characters/frost/tripo_out?name=a.glb', self.data, ctype='application/json')[0], 415)
        self.assertEqual(self.post('/api/characters/nobody/tripo_out?name=a.glb', self.data)[0], 404)
        old = characters.GLB_LIMIT
        characters.GLB_LIMIT = 10
        try:
            self.assertEqual(self.post('/api/characters/frost/tripo_out?name=a.glb', self.data)[0], 413)
        finally:
            characters.GLB_LIMIT = old

    def test_host_and_origin_checked(self):
        for path, body, ctype in (('/api/characters/frost/tripo_out?name=a.glb', self.data, 'application/octet-stream'),
                                  ('/api/characters/frost/open', b'{"folder":"tripo_in"}', 'application/json')):
            self.assertEqual(self.post(path, body, ctype, origin='http://evil.example')[0], 403)
            self.assertEqual(self.post(path, body, ctype, host='evil.example')[0], 403)

    def test_open_accepts_only_fixed_words(self):
        calls = []
        orig = characters._startfile
        characters._startfile = calls.append
        try:
            for word in ('chapter1', '../x', 'tripo_in/..', 'C:/'):
                self.assertEqual(self.post('/api/characters/frost/open', json.dumps({'folder': word}).encode(), 'application/json')[0], 404)
            self.assertEqual(self.post('/api/characters/frost/open', b'{"folder":"tripo_in","path":"C:/"}', 'application/json')[0], 400)
            status, v = self.post('/api/characters/frost/open', b'{"folder":"tripo_in"}', 'application/json')
            self.assertEqual((status, v['opened']), (200, False))      # 폴더가 없으면 만들지 않고 없음
            self.assertFalse((self.work / 'pipeline' / 'frost' / 'tripo_in').exists())
            self.assertEqual(calls, [])
        finally:
            characters._startfile = orig


if __name__ == '__main__':
    unittest.main()

    def test_nobody_lines_tripo_works(self):
        """몸이 아직 없는 줄(ember, arc)도 보낼 그림 정보·받은 모델 저장·폴더 열기가 된다."""
        calls = []
        orig = characters._startfile
        characters._startfile = calls.append
        try:
            for line in ('ember', 'arc'):
                self.assertFalse(next(l for l in json.loads(self.get('/api/characters')[1])['lines'] if l['id'] == line)['has_body'])
                inp = self.work / 'pipeline' / line / 'tripo_in'
                inp.mkdir(parents=True, exist_ok=True)
                (inp / 'front.png').write_bytes(png_header(640, 480))
                status, body = self.get('/api/characters/%s/tripo' % line)
                self.assertEqual(status, 200)
                info = json.loads(body)
                self.assertEqual([(r['name'], r['width'], r['height']) for r in info['inputs']], [('front.png', 640, 480)])
                status, v = self.post('/api/characters/%s/tripo_out?name=hand.glb' % line, self.data)
                self.assertEqual(status, 200, v)
                self.assertTrue((self.work / 'pipeline' / line / 'tripo_out' / v['saved']).is_file())
                out = next(o for o in v['tripo']['outputs'] if o['name'] == v['saved'])
                self.assertEqual(self.get('/media/%s/%s' % (line, out['key'])), (200, self.data))   # 돌려 보기용 파일, 몸 없이도 열림
                status, o = self.post('/api/characters/%s/open' % line, b'{"folder":"tripo_in"}', 'application/json')
                self.assertEqual((status, o['opened']), (200, True))
            self.assertEqual(len(calls), 2)
        finally:
            characters._startfile = orig

    def test_nobody_detail_returns_state_without_error(self):
        status, body = self.get('/api/characters/ember')
        self.assertEqual(status, 200)
        d = json.loads(body)
        self.assertNotIn('body', d['media'])
        self.assertIsNone(d['body']['info'])
        self.assertTrue(any('몸 파일이 없' in w for w in d['warnings']))
