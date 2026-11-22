import contextlib, io, json, tempfile, threading, unittest, urllib.error, urllib.request
from pathlib import Path
import picks, server


def rec(**kw):
    d = {'screen': 'character', 'subject': 'frost/locomotion', 'verdict': 'pick', 'note': '조금 빠른 걸음이 낫다',
         'values': {'clip': 'walk', 'rate': 1.3}, 'proposals': []}
    d.update(kw)
    return d


class PicksStore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'picks.json'

    def tearDown(self):
        self.tmp.cleanup()

    def add(self, revision=0, **kw):
        return picks.update({'revision': revision, 'action': 'add', 'record': rec(**kw)}, self.path)

    def test_add_fills_server_fields(self):
        status, v = self.add(**{'by': 'agent'})
        self.assertEqual(status, 200)
        r = v['records'][v['id']]
        self.assertEqual((r['by'], r['status'], r['closed_ref']), ('user', 'open', ''))
        self.assertEqual(v['revision'], 1)
        self.assertEqual(json.loads(self.path.read_text(encoding='utf-8'))['revision'], 1)
        self.assertFalse(self.path.with_suffix('.tmp').exists())

    def test_revision_conflict(self):
        self.add()
        status, v = self.add(revision=0)
        self.assertEqual(status, 409)
        self.assertEqual(v['revision'], 1)
        self.assertEqual(len(picks.load(self.path)['records']), 1)

    def test_validation(self):
        bad = [rec(verdict='love'), rec(screen='nope'), rec(subject='../x'), rec(subject=''), rec(note='x' * 3000), rec(values=[]),
               rec(proposals=[1]), 'x']
        for r in bad:
            with self.assertRaises(ValueError):
                picks.update({'revision': 0, 'action': 'add', 'record': r}, self.path)
        with self.assertRaises(ValueError):
            picks.update({'revision': 0, 'action': 'add', 'record': rec(), 'extra': 1}, self.path)
        with self.assertRaises(ValueError):
            picks.update({'revision': True, 'action': 'add', 'record': rec()}, self.path)
        self.assertFalse(self.path.exists())

    def test_update_and_closed(self):
        _, v = self.add()
        pid = v['id']
        status, v2 = picks.update({'revision': 1, 'action': 'update', 'id': pid, 'record': rec(verdict='hold', note='다시 볼게')}, self.path)
        self.assertEqual(status, 200)
        self.assertEqual(v2['records'][pid]['verdict'], 'hold')
        self.assertEqual(v2['records'][pid]['by'], 'user')
        picks.close(pid, 'commit abc', self.path)
        with self.assertRaises(ValueError):
            picks.update({'revision': 3, 'action': 'update', 'id': pid, 'record': rec()}, self.path)
        with self.assertRaises(ValueError):
            picks.update({'revision': 3, 'action': 'update', 'id': 'nope', 'record': rec()}, self.path)

    def test_ids_unique_in_same_second(self):
        ids = set()
        for i in range(3):
            _, v = self.add(revision=i)
            ids.add(v['id'])
        self.assertEqual(len(ids), 3)

    def test_list_filters_and_close_cli(self):
        _, a = self.add()
        _, b = self.add(revision=1, subject='skill/frost')
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(picks.main(['--file', str(self.path), 'list', '--open', '--subject', 'frost/']), 0)
        self.assertIn(a['id'], out.getvalue())
        self.assertNotIn(b['id'], out.getvalue())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(picks.main(['--file', str(self.path), 'close', a['id'], '--ref', 'docs/x.md']), 0)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            picks.main(['--file', str(self.path), 'list', '--open', '--json'])
        ids = [r['id'] for r in json.loads(out.getvalue())]
        self.assertEqual(ids, [b['id']])
        self.assertEqual(picks.load(self.path)['records'][a['id']]['closed_ref'], 'docs/x.md')

    def test_cli_has_no_add_command(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            picks.main(['--file', str(self.path), 'add'])

    def test_answers_last_pick_wins(self):
        self.add(note='첫째', values={'rate': 1})
        self.add(revision=1, values={'rate': 2})
        self.assertEqual(picks.answers(picks.load(self.path))['frost/locomotion']['values']['rate'], 2)


class PicksHttp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.old = picks.STORE
        picks.STORE = Path(cls.tmp.name) / 'picks.json'
        cls.srv = server.make_server(0)
        cls.port = cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        picks.STORE = cls.old
        cls.tmp.cleanup()

    def call(self, path, body=None, host=None, origin=None):
        data = json.dumps(body).encode('utf-8') if body is not None else None
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path), data=data, method='POST' if data is not None else 'GET')
        req.add_header('Host', host or '127.0.0.1:%d' % self.port)
        if data is not None:
            req.add_header('Content-Type', 'application/json')
        if origin:
            req.add_header('Origin', origin)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_roundtrip_and_conflict(self):
        status, v = self.call('/api/picks')
        self.assertEqual((status, v['revision']), (200, 0))
        status, v = self.call('/api/picks', {'revision': 0, 'action': 'add', 'record': rec()})
        self.assertEqual(status, 200)
        status, v = self.call('/api/picks', {'revision': 0, 'action': 'add', 'record': rec()})
        self.assertEqual(status, 409)
        status, v = self.call('/api/picks')
        self.assertEqual(len(v['records']), 1)

    def test_origin_and_host_checked(self):
        self.assertEqual(self.call('/api/picks', {'revision': 0, 'action': 'add', 'record': rec()}, origin='http://evil.example')[0], 403)
        self.assertEqual(self.call('/api/picks', host='evil.example')[0], 403)
        self.assertEqual(self.call('/api/picks', {'revision': 0, 'action': 'bogus', 'record': rec()})[0], 400)


if __name__ == '__main__':
    unittest.main()
