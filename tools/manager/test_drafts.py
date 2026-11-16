import json, tempfile, threading, unittest, urllib.error, urllib.request
from pathlib import Path
import drafts, server


def make_png(path, size=(200, 300)):
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        from PIL import Image
        Image.new('RGB', size, (90, 120, 160)).save(path)
    except ImportError:
        path.write_bytes(b'\x89PNG\r\n\x1a\n')


def entry(i, character='frost_demon', **kw):
    d = {'id': i, 'character': character, 'group': '본래의 속성 악마', 'title': i, 'file': character + '/' + i + '.png',
         'prompt_file': character + '/' + i + '.prompt.txt', 'tool': 't', 'model': 'm', 'created': '2026-11-17 0%d:00' % len(i),
         'status': '검토 대기', 'note': ''}
    d.update(kw)
    return d


class DraftsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.d, self.canon, self.cache = self.root / 'drafts', self.root / 'canon', self.root / 'cache'

    def tearDown(self):
        self.tmp.cleanup()

    def write_index(self, items):
        self.d.mkdir(parents=True, exist_ok=True)
        (self.d / 'index.json').write_text(json.dumps(items, ensure_ascii=False), encoding='utf-8')

    def add(self, i, **kw):
        e = entry(i, **kw)
        make_png(self.d / e['file'])
        (self.d / e['prompt_file']).write_text('프롬프트 ' + i, encoding='utf-8')
        return e

    def test_missing_and_broken_index(self):
        g = drafts.gallery(self.d, self.canon, self.root / 's.json')
        self.assertEqual(g['items'], [])
        self.assertTrue(g['warnings'])
        self.d.mkdir()
        (self.d / 'index.json').write_text('{broken', encoding='utf-8')
        g = drafts.gallery(self.d, self.canon, self.root / 's.json')
        self.assertEqual(g['items'], [])
        (self.d / 'index.json').write_text('{"a":1}', encoding='utf-8')
        self.assertTrue(drafts.gallery(self.d, self.canon, self.root / 's.json')['warnings'])

    def test_grouping_count_and_bad_entries_skipped(self):
        a, b = self.add('aa'), self.add('bbb', character='ember_demon')
        bad = [entry('x', file='../evil.png'), entry('y', file='/abs.png'), entry('nofile'), {'id': 5}, entry('aa')]
        self.write_index([a, b] + bad)
        g = drafts.gallery(self.d, self.canon, self.root / 's.json')
        self.assertEqual({i['id'] for i in g['items']}, {'aa', 'bbb'})
        self.assertEqual({c['character']: c['count'] for c in g['characters']}, {'frost_demon': 1, 'ember_demon': 1})
        self.assertEqual(len(g['warnings']), 5)
        self.assertNotIn('path', g['items'][0])

    def test_newest_first_and_index_reread(self):
        self.write_index([self.add('a'), self.add('bbb')])
        self.assertEqual([i['id'] for i in drafts.gallery(self.d, self.canon)['items']], ['bbb', 'a'])
        self.write_index([self.add('a'), self.add('bbb'), self.add('cc')])
        self.assertEqual(len(drafts.gallery(self.d, self.canon)['items']), 3)

    def test_canonical_listed(self):
        for k in ('frost', 'ember', 'storm'):
            make_png(self.canon / (k + '_witch_v02.png'))
        g = drafts.gallery(self.d, self.canon)
        self.assertEqual([c['id'] for c in g['canonical']], ['canon-frost', 'canon-ember', 'canon-storm'])

    def test_thumbnail_cached(self):
        e = self.add('aa')
        self.write_index([e])
        found = drafts.find('aa', self.d, self.canon)
        if not drafts.thumbs_available():
            self.skipTest('no Pillow')
        t = drafts.thumb_path(found, self.cache)
        self.assertTrue(t.is_file() and t.is_relative_to(self.cache))
        self.assertEqual(drafts.thumb_path(found, self.cache), t)
        self.assertIsNone(drafts.find('nope', self.d, self.canon))

    def test_safe_join(self):
        make_png(self.d / 'a.png')
        for bad in ('../a.png', '/a.png', 'a/../a.png', 'C:/a.png', 'a\\b.png', '', None, 'a.exe'):
            self.assertIsNone(drafts.safe_join(self.d, bad, drafts.IMAGE_TYPES), bad)
        self.assertIsNotNone(drafts.safe_join(self.d, 'a.png', drafts.IMAGE_TYPES))

    def test_store_save_reload_and_conflict(self):
        path = self.root / 'store.json'
        ids = {'aa'}
        status, v = drafts.update_store({'revision': 0, 'id': 'aa', 'changes': {'verdict': 'like', 'notes': '좋음'}}, ids, path)
        self.assertEqual(status, 200)
        self.assertEqual(drafts.load_store(path)['records']['aa']['verdict'], 'like')
        self.assertEqual(drafts.update_store({'revision': 0, 'id': 'aa', 'changes': {'verdict': 'drop'}}, ids, path)[0], 409)
        for bad in ({'revision': 1, 'id': 'zz', 'changes': {'verdict': 'like'}}, {'revision': 1, 'id': 'aa', 'changes': {'verdict': 'x'}},
                    {'revision': 1, 'id': 'aa', 'changes': {'status': 'done'}}, {'revision': 1, 'id': 'aa', 'changes': {}}):
            with self.assertRaises(ValueError):
                drafts.update_store(bad, ids, path)


class DraftsServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.saved = (drafts.DRAFTS, drafts.CANON, drafts.CACHE, drafts.STORE)
        drafts.DRAFTS, drafts.CANON, drafts.CACHE, drafts.STORE = root / 'd', root / 'c', root / 'cache', root / 'store.json'
        items = []
        for i in ('aa', 'bbb'):
            e = entry(i)
            make_png(drafts.DRAFTS / e['file'])
            (drafts.DRAFTS / e['prompt_file']).write_text('프롬프트 ' + i, encoding='utf-8')
            items.append(e)
        (drafts.DRAFTS / 'index.json').write_text(json.dumps(items, ensure_ascii=False), encoding='utf-8')
        (root / 'secret.png').write_bytes(b'x')
        cls.server = server.make_server(0)
        cls.port = cls.server.server_port
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        drafts.DRAFTS, drafts.CANON, drafts.CACHE, drafts.STORE = cls.saved
        cls.tmp.cleanup()

    def get(self, path):
        try:
            with urllib.request.urlopen('http://127.0.0.1:%d%s' % (self.port, path)) as r:
                return r.status, r.headers.get('Content-Type'), r.read()
        except urllib.error.HTTPError as e:
            return e.code, None, e.read()

    def post(self, body):
        req = urllib.request.Request('http://127.0.0.1:%d/api/drafts/state' % self.port, json.dumps(body).encode(),
                                     {'Content-Type': 'application/json', 'Origin': 'http://127.0.0.1:%d' % self.port})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_api_matches_index(self):
        s, _, body = self.get('/api/drafts')
        data = json.loads(body)
        self.assertEqual((s, len(data['items'])), (200, 2))

    def test_images_prompt_and_rejections(self):
        s, mime, body = self.get('/drafts/thumb/aa')
        self.assertEqual(s, 200)
        self.assertIn(mime, ('image/jpeg', 'image/png'))
        self.assertEqual(self.get('/drafts/full/aa')[1], 'image/png')
        self.assertIn('프롬프트 aa', self.get('/drafts/prompt/aa')[2].decode('utf-8'))
        for bad in ('/drafts/full/..%2Fsecret', '/drafts/full/../secret.png', '/drafts/full/%2e%2e%2f%2e%2e%2fsecret.png',
                    '/drafts/full/d%2Findex.json', '/drafts/full/nope', '/drafts/other/aa', '/drafts/full/', '/drafts/prompt/index.json'):
            self.assertEqual(self.get(bad)[0], 404, bad)

    def test_store_post_flow(self):
        s, v = self.post({'revision': 0, 'id': 'aa', 'changes': {'verdict': 'hold', 'notes': '메모'}})
        self.assertEqual(s, 200)
        self.assertEqual(json.loads(self.get('/api/drafts')[2])['decisions']['records']['aa']['verdict'], 'hold')
        self.assertEqual(self.post({'revision': 0, 'id': 'aa', 'changes': {'verdict': 'like'}})[0], 409)
        self.assertEqual(self.post({'revision': v['revision'], 'id': 'ghost', 'changes': {'verdict': 'like'}})[0], 400)


if __name__ == '__main__':
    unittest.main()
