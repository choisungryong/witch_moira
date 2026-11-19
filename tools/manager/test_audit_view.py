"""점검 화면 뒷면 검사. 임시 폴더만 쓴다(local-state.json 과 _local/audit 은 건드리지 않는다)."""
import json, sys, tempfile, threading, unittest, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_view, server


class AuditViewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / 'audit'

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, payload):
        (self.dir / name).mkdir(parents=True)
        (self.dir / name / 'audit.json').write_text(json.dumps(payload), encoding='utf-8')

    def script(self, body):
        p = Path(self.tmp.name) / 'fake.py'
        p.write_text(body, encoding='utf-8')
        return p

    def test_latest_none_and_newest(self):
        self.assertIsNone(audit_view.latest(self.dir)['result'])
        self.put('20260101-000001', {'lines': [], 'tag': 'old'})
        self.put('20260102-000001', {'lines': [], 'tag': 'new'})
        got = audit_view.latest(self.dir)
        self.assertEqual((got['folder'], got['result']['tag']), ('20260102-000001', 'new'))

    def test_run_ok_and_exit_one_is_not_failure(self):
        self.put('20260101-000001', {'lines': [], 'tag': 'x'})
        self.assertEqual(audit_view.run(self.script('import sys; sys.exit(1)'), self.dir)['folder'], '20260101-000001')
        self.assertEqual(audit_view.run(self.script('pass'), self.dir)['folder'], '20260101-000001')

    def test_run_errors(self):
        with self.assertRaises(audit_view.RunError):
            audit_view.run(self.script('import sys; sys.exit(2)'), self.dir)
        with self.assertRaises(audit_view.RunError):
            audit_view.run(self.script('import time; time.sleep(5)'), self.dir, timeout=1)

    def test_only_one_at_a_time(self):
        slow = self.script('import time; time.sleep(2)')
        t = threading.Thread(target=lambda: audit_view.run(slow, self.dir))
        t.start()
        try:
            for _ in range(50):
                if audit_view._RUN.locked():
                    break
                threading.Event().wait(0.05)
            with self.assertRaises(audit_view.BusyError):
                audit_view.run(slow, self.dir)
            self.assertTrue(audit_view.latest(self.dir)['running'])
        finally:
            t.join()
        self.assertFalse(audit_view.latest(self.dir)['running'])


class AuditRouteTests(unittest.TestCase):
    def test_routes_and_static(self):
        httpd = server.make_server(0)
        port = httpd.server_port
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        try:
            def req(path, method='GET', body=None, host=None, origin=None):
                headers = {'Host': host or '127.0.0.1:%d' % port, 'Content-Type': 'application/json'}
                if origin:
                    headers['Origin'] = origin
                r = urllib.request.Request('http://127.0.0.1:%d%s' % (port, path), data=body, method=method, headers=headers)
                try:
                    with urllib.request.urlopen(r) as resp:
                        return resp.status, resp.read()
                except urllib.error.HTTPError as e:
                    return e.code, e.read()
            st, body = req('/api/audit')
            self.assertEqual(st, 200)
            self.assertIn('result', json.loads(body))
            self.assertEqual(req('/audit.js')[0], 200)
            # 보안 경계: 낯선 Host/Origin 은 거절
            self.assertEqual(req('/api/audit', host='evil.example')[0], 403)
            self.assertEqual(req('/api/audit/run', 'POST', b'{}', origin='http://evil.example')[0], 403)
        finally:
            httpd.shutdown()
            httpd.server_close()


if __name__ == '__main__':
    unittest.main()
