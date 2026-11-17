import json, sys, tempfile, threading, unittest, urllib.error, urllib.request
from pathlib import Path
import catalog, drafts, playlog, server


def ids_of(groups):
    return [i['id'] for g in groups for i in g['items']]


class QuestionTests(unittest.TestCase):
    def test_questions_come_from_current_docs(self):
        groups, warnings = playlog.questions()
        self.assertEqual(warnings, [])
        self.assertEqual([g['key'] for g in groups], playlog.ORDER)
        text = (catalog.ROOT / 'docs/QUALITY-TARGETS.ko.md').read_text(encoding='utf-8')
        combat = next(g for g in groups if g['key'] == 'combat')
        self.assertEqual(len(combat['items']), 5)
        for item in combat['items']:
            self.assertIn(item['text'], text)
        self.assertEqual(len(next(g for g in groups if g['key'] == 'compare')['items']), 5)
        self.assertEqual(len(next(g for g in groups if g['key'] == 'loot')['items']), 5)
        ids = ids_of(groups)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(g['from_doc'] for g in groups))

    def test_docs_missing_falls_back_to_defaults_with_warning(self):
        with tempfile.TemporaryDirectory() as d:
            groups, warnings = playlog.questions(Path(d))
        self.assertEqual(len(warnings), len(playlog.ORDER))
        self.assertTrue(all(not g['from_doc'] and g['items'] for g in groups))

    def test_changed_doc_changes_question_and_id(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'docs').mkdir()
            (root / 'docs/QUALITY-TARGETS.ko.md').write_text('### 사람이 플레이하고 답하는 것\n\n1. 새 질문 하나.\n2. 둘째.\n\n## 3. 화면\n', encoding='utf-8')
            groups, warnings = playlog.questions(root)
        combat = next(g for g in groups if g['key'] == 'combat')
        self.assertEqual([i['text'] for i in combat['items']], ['새 질문 하나.', '둘째.'])
        self.assertTrue(combat['from_doc'])
        self.assertFalse(next(g for g in groups if g['key'] == 'hud')['from_doc'])


class SaveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / 'playtests'
        self.groups, _ = playlog.questions()
        self.q = self.groups[0]['items'][0]['id']

    def tearDown(self):
        self.tmp.cleanup()

    def body(self, **kw):
        b = {'played_at': '2026-11-17 21:30', 'witch': 'frost', 'result': 'win', 'minutes': 12, 'sound': 'on', 'resolution': '1920x1080',
             'answers': {self.q: {'score': 4, 'note': '좋음'}}, 'memo': '자유'}
        b.update(kw)
        return b

    def test_save_creates_folder_and_reads_back(self):
        rec = playlog.save(self.body(), self.groups, self.dir, build={'commit': 'abc1234', 'dirty': False, 'changed_files': 0}, now='2026-11-17 21:40:00')
        self.assertEqual(rec['id'], '20261117-2130')
        files = list(self.dir.glob('*.json'))
        self.assertEqual([f.name for f in files], ['20261117-2130.json'])
        self.assertFalse(list(self.dir.glob('*.tmp')))
        records, skipped = playlog.load_all(self.dir)
        self.assertEqual(skipped, [])
        r = records[0]
        self.assertEqual((r['build']['commit'], r['result'], r['minutes']), ('abc1234', 'win', 12))
        self.assertEqual(r['answers'][self.q]['score'], 4)
        self.assertIn('맞았다는', r['answers'][self.q]['text'])

    def test_same_minute_gets_suffix(self):
        for _ in range(2):
            playlog.save(self.body(), self.groups, self.dir, build={})
        self.assertEqual(sorted(p.name for p in self.dir.glob('*.json')), ['20261117-2130-2.json', '20261117-2130.json'])

    def test_rejects_bad_input(self):
        bad = [self.body(played_at='어제'), self.body(played_at='2026-13-40 99:99'), self.body(witch='x'), self.body(result='win!'),
               self.body(minutes=-1), self.body(minutes='12'), self.body(minutes=True), self.body(sound='loud'),
               self.body(answers={'nope': {'score': 3}}), self.body(answers={self.q: {'score': 6}}), self.body(answers={self.q: {'score': '3'}}),
               self.body(answers={self.q: {'score': 3, 'extra': 1}}), self.body(answers={self.q: {'note': 'x' * 401}}),
               self.body(memo='x' * 12001), self.body(resolution='x' * 21), dict(self.body(), build={'commit': 'forged'}), 'text', None]
        for payload in bad:
            with self.assertRaises(ValueError, msg=str(payload)[:60]):
                playlog.save(payload, self.groups, self.dir, build={})
        self.assertFalse(self.dir.exists() and list(self.dir.glob('*')))

    def test_empty_answers_are_not_stored_and_broken_file_is_reported(self):
        rec = playlog.save(self.body(answers={self.q: {'score': 0, 'note': ''}}), self.groups, self.dir, build={})
        self.assertEqual(rec['answers'], {})
        (self.dir / 'broken.json').write_text('{', encoding='utf-8')
        records, skipped = playlog.load_all(self.dir)
        self.assertEqual((len(records), skipped), (1, ['broken.json']))

    def test_trend_orders_by_play_time(self):
        for when, score in (('2026-11-18 10:00', 5), ('2026-11-17 10:00', 2), ('2026-11-19 10:00', 4)):
            playlog.save(self.body(played_at=when, answers={self.q: {'score': score}}), self.groups, self.dir, build={})
        records, _ = playlog.load_all(self.dir)
        self.assertEqual([r['played_at'][:10] for r in records], ['2026-11-19', '2026-11-18', '2026-11-17'])
        t = playlog.trend(records)
        self.assertEqual([p['score'] for p in t[0]['points']], [2, 5, 4])

    def test_build_info_reads_git(self):
        info = playlog.build_info()
        self.assertTrue(info['commit'] is None or len(info['commit']) >= 7)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def entries(self):
        mk = lambda i, g, c='2026-11-17 10:0%d': dict(id=i, group=g, created=c % len(i)) 
        return [mk('a', '여름 수영복 컬렉션 시험'), mk('bb', '여름 수영복 컬렉션 시험'), mk('c', '장비 아이콘 시험'), mk('dd', '화면 재디자인 목업')]

    def test_marks_save_without_touching_index(self):
        index = self.dir / 'index.json'
        index.write_text('[]', encoding='utf-8')
        ids = {'a', 'bb'}
        code, v = drafts.update_selection({'revision': 0, 'id': 'a', 'mark': 'candidate'}, ids, self.dir)
        self.assertEqual((code, v['revision'], v['records']['a']['mark']), (200, 1, 'candidate'))
        self.assertEqual(index.read_text(encoding='utf-8'), '[]')
        self.assertEqual(drafts.update_selection({'revision': 0, 'id': 'a', 'mark': 'final'}, ids, self.dir)[0], 409)
        code, v = drafts.update_selection({'revision': 1, 'id': 'a', 'mark': ''}, ids, self.dir)
        self.assertEqual((code, v['records']), (200, {}))
        self.assertFalse(list(self.dir.glob('*.tmp')))

    def test_rejects_bad_marks(self):
        for bad in ({'revision': 0, 'id': 'zz', 'mark': 'final'}, {'revision': 0, 'id': 'a', 'mark': 'yes'}, {'revision': 0, 'id': 'a'},
                    {'revision': True, 'id': 'a', 'mark': 'final'}, {'revision': 0, 'id': 'a', 'mark': 'final', 'x': 1}):
            with self.assertRaises(ValueError):
                drafts.update_selection(bad, {'a'}, self.dir)
        self.assertFalse((self.dir / 'selection.json').exists())

    def test_waiting_groups_until_a_final_is_marked(self):
        rows = {g['group']: g for g in drafts.group_summary(self.entries(), {'records': {}})}
        self.assertTrue(rows['여름 수영복 컬렉션 시험']['waiting'])
        self.assertTrue(rows['화면 재디자인 목업']['waiting'])
        self.assertFalse(rows['장비 아이콘 시험']['waiting'])
        sel = {'records': {'a': {'mark': 'final'}, 'bb': {'mark': 'archive'}, 'dd': {'mark': 'candidate'}}}
        rows = {g['group']: g for g in drafts.group_summary(self.entries(), sel)}
        swim = rows['여름 수영복 컬렉션 시험']
        self.assertEqual((swim['waiting'], swim['final'], swim['archive'], swim['count']), (False, 1, 1, 2))
        self.assertTrue(rows['화면 재디자인 목업']['waiting'])
        self.assertEqual(drafts.group_summary(self.entries(), {'records': {}})[0]['waiting'], True)


class CatalogSyncTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = catalog.generate()
        cls.by = {e['id']: e for e in cls.c['entities']}

    def test_po_parser(self):
        text = '# c\nmsgid ""\nmsgstr ""\n"Language: en\\n"\n\nmsgid "a.b"\nmsgstr ""\n\n#, fuzzy\nmsgid "long"\n"er"\nmsgstr "x"\n"y"\n\nmsgid "n"\nmsgid_plural "n"\nmsgstr[0] "one"\nmsgstr[1] ""\n'
        e = catalog.parse_po(text)
        self.assertEqual([x['id'] for x in e], ['a.b', 'longer', 'n'])
        self.assertEqual(e[1]['strs'][0], 'xy')
        st = catalog.po_stats(text)
        self.assertEqual((st['empty'], st['fuzzy']), (['a.b', 'n'], ['longer']))

    def test_translation_counts_match_files(self):
        for code in ('ko', 'en'):
            text = (catalog.ROOT / ('chapter1/i18n/%s.po' % code)).read_text(encoding='utf-8')
            keys = sum(1 for ln in text.split('\n') if ln.startswith('msgid "')) - 1
            e = self.by['i18n:lang:' + code]
            self.assertIn('키 %d개' % keys, e['summary'])
            self.assertEqual(dict(e['sections'][0]['rows'])['빈 번역'], str(catalog.po_stats(text)['empty'].__len__()))
        self.assertIn('파일이 아직 없습니다', self.by['i18n:lang:ja']['summary'])

    def test_presets_match_export_presets(self):
        text = (catalog.ROOT / 'export_presets.cfg').read_text(encoding='utf-8')
        names = [ln.split('=', 1)[1].strip().strip('"') for ln in text.split('\n') if ln.startswith('name=')]
        got = [e['name'] for e in self.c['entities'] if e['id'].startswith('build:preset:')]
        self.assertEqual(got, names)
        self.assertGreaterEqual(len(got), 2)

    def test_regression_checks_match_run_all(self):
        sys.path.insert(0, str(catalog.ROOT / 'tools' / 'dev'))
        try:
            import run_all
            real = [c['name'] for c in run_all.checks()]
        finally:
            sys.path.pop(0)
        got = [e['name'] for e in self.c['entities'] if e['id'].startswith('build:check:')]
        self.assertEqual(got, real)
        self.assertIn('manager', got)

    def test_new_categories_present_and_no_warnings(self):
        self.assertEqual(self.c['warnings'], [])
        keys = {c['key']: c['count'] for c in self.c['categories']}
        self.assertGreater(keys['i18n'], 0)
        self.assertGreater(keys['build'], 0)


class PlaytestServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.saved = (playlog.DIR, drafts.DRAFTS, drafts.CANON, drafts.CACHE, drafts.STORE, server.STATE)
        playlog.DIR, drafts.DRAFTS, drafts.CANON, drafts.CACHE, drafts.STORE, server.STATE = (
            root / 'playtests', root / 'drafts', root / 'canon', root / 'cache', root / 'store.json', root / 'state.json')
        (drafts.DRAFTS).mkdir()
        (drafts.DRAFTS / 'g.png').write_bytes(b'\x89PNG\r\n\x1a\n')
        (drafts.DRAFTS / 'index.json').write_text(json.dumps([{'id': 'sw1', 'character': 'frost_witch', 'group': '여름 수영복 시험', 'file': 'g.png', 'created': '2026-11-17 10:00'}]), encoding='utf-8')
        cls.server = server.make_server(0)
        cls.port = cls.server.server_port
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        playlog.DIR, drafts.DRAFTS, drafts.CANON, drafts.CACHE, drafts.STORE, server.STATE = cls.saved
        cls.tmp.cleanup()

    def call(self, path, body=None, origin=True):
        headers = {'Content-Type': 'application/json'}
        if origin:
            headers['Origin'] = 'http://127.0.0.1:%d' % self.port
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path), json.dumps(body).encode() if body is not None else None, headers if body is not None else {})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_static_files_served(self):
        for p in ('/playlog.js', '/drafts.js', '/'):
            with urllib.request.urlopen('http://127.0.0.1:%d%s' % (self.port, p)) as r:
                self.assertEqual(r.status, 200, p)

    def test_save_then_read_back(self):
        s, ov = self.call('/api/playtests')
        self.assertEqual(s, 200)
        self.assertEqual(ov['records'], [])
        q = ov['questions'][0]['items'][0]['id']
        s, rec = self.call('/api/playtests', {'played_at': '2026-11-17 22:00', 'witch': 'ember', 'result': 'down', 'minutes': 9, 'sound': 'off',
                                              'resolution': '375x667', 'answers': {q: {'score': 3, 'note': '메모'}}, 'memo': '끝'})
        self.assertEqual(s, 200)
        self.assertTrue((playlog.DIR / (rec['id'] + '.json')).is_file())
        s, ov = self.call('/api/playtests')
        self.assertEqual(len(ov['records']), 1)
        self.assertEqual(ov['records'][0]['answers'][q]['note'], '메모')
        self.assertEqual(ov['trend'][0]['points'][0]['score'], 3)
        self.assertEqual(self.call('/api/playtests', {'played_at': 'bad'})[0], 400)
        before = len(list(playlog.DIR.glob('*.json')))
        req = urllib.request.Request('http://127.0.0.1:%d/api/playtests' % self.port, json.dumps({'played_at': '2026-11-17 23:00'}).encode(),
                                     {'Content-Type': 'application/json', 'Origin': 'http://evil.example'})
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req)
        self.assertEqual(ctx.exception.code, 403)
        self.assertEqual(len(list(playlog.DIR.glob('*.json'))), before)

    def test_selection_flow_and_gallery_waiting(self):
        s, g = self.call('/api/drafts')
        row = g['group_summary'][0]
        self.assertEqual((row['group'], row['waiting']), ('여름 수영복 시험', True))
        s, sel = self.call('/api/drafts/selection', {'revision': 0, 'id': 'sw1', 'mark': 'final'})
        self.assertEqual((s, sel['records']['sw1']['mark']), (200, 'final'))
        self.assertTrue((drafts.DRAFTS / 'selection.json').is_file())
        self.assertEqual(self.call('/api/drafts/selection', {'revision': 0, 'id': 'sw1', 'mark': 'candidate'})[0], 409)
        self.assertEqual(self.call('/api/drafts/selection', {'revision': 1, 'id': 'ghost', 'mark': 'candidate'})[0], 400)
        self.assertFalse(self.call('/api/drafts')[1]['group_summary'][0]['waiting'])


if __name__ == '__main__':
    unittest.main()
