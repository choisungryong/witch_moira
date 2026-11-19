import json, tempfile, threading, unittest
from pathlib import Path
import balance_lab as bl
import catalog

POL = ['synergy', 'synergy:basic_A', 'narrow', 'random', 'spread', 'worst']
KNOWN = {'policies': POL, 'witches': ['ember', 'frost', 'arc'], 'presets': ['spec1', 'spec1p'],
         'spell_files': {'balance_sim_spells_draft': Path('tools/dev/balance_sim_spells_draft.json')},
         'probe': {'p7': {'synergy': [0.9, 1.0], 'narrow': [0.2, 0.4], 'random': [0.15, 0.35], 'spread': [0.0, 0.15], 'worst': [0.0, 0.05]},
                   'p4': {'기': {'synergy': [2.0, 3.0], 'narrow': [1.8, None]}}}}


def req(**kw):
    base = {'preset': 'spec1p', 'spells': 'balance_sim_spells_draft', 'sets': [], 'policies': ['synergy', 'narrow'], 'witches': ['ember'], 'seeds': 3}
    base.update(kw)
    return base


def cell(rate, **extra):
    c = {'win_rate': rate, 'n': 10, 'secs_median': 400.0, 'deaths': [{'beat': '승2', 'cause': '깔림', 'secs': 300.0}] if rate < 1 else [], 'stalls': 0,
         'det_share_mean': 0.2, 'evolve_t': [[300.0]], 'builds': [{}], 'per_beat': {'기': {'secs': 60.0, 'R': 2.4}}}
    c.update(extra)
    return c


def doc(rates, **top):
    d = {'preset': 'spec1p', 'mode': 's', 'set': [], 'results': {k: cell(v) for k, v in rates.items()}}
    d.update(top)
    return d


class ValidationTests(unittest.TestCase):
    def bad(self, **kw):
        with self.assertRaises(ValueError):
            bl.validate_request(req(**kw), KNOWN)

    def test_good_request_normalizes(self):
        r = bl.validate_request(req(sets=[{'key': 'rhythm.beats[2].amount', 'value': 6}, {'key': 'spells.ember_ring.base.ring_radius_cm', 'value': 450.5}]), KNOWN)
        self.assertEqual(len(r['sets']), 2)
        self.assertEqual(r['seeds'], 3)

    def test_bad_keys_rejected(self):
        for k in ['a; rm -rf /', 'a b', '../x', '$(calc)', '-x', 'a=b', "a'b", 'a\nb', '', 'x' * 130, 'a..b', 'a[', 'a[x]', 'a.b.', '`id`', 'a|b', 'a&b']:
            self.bad(sets=[{'key': k, 'value': 1}])

    def test_bad_values_rejected(self):
        for v in [[1], {'a': 1}, None, float('nan'), float('inf'), 1e12, 'a;b', 'a b', '$(x)', 'x' * 41, '../y', '', 'a\nb']:
            self.bad(sets=[{'key': 'calib.cluster', 'value': v}])

    def test_values_render_without_shell_characters(self):
        self.assertEqual(bl.render_value(6), '6')
        self.assertEqual(bl.render_value(4.5), '4.5')
        self.assertEqual(bl.render_value(True), 'true')
        self.assertEqual(bl.render_value('ember'), 'ember')

    def test_set_shape_and_duplicates(self):
        self.bad(sets=[{'key': 'calib.cluster'}])
        self.bad(sets=[{'key': 'calib.cluster', 'value': 1, 'x': 2}])
        self.bad(sets='calib.cluster=1')
        self.bad(sets=[{'key': 'calib.cluster', 'value': 1}, {'key': 'calib.cluster', 'value': 2}])
        self.bad(sets=[{'key': 'calib.k%d' % i, 'value': 1} for i in range(bl.MAX_SETS + 1)])

    def test_bad_files_rejected(self):
        for f in ['../../chapter1/data/combat_tuning.json', 'C:/Windows/win.ini', '/etc/passwd', 'chapter1/data/run_spells.json', 'unknown', '..\\x', 'balance_sim_spells_draft.json']:
            self.bad(spells=f)

    def test_bad_seeds_and_run_cap(self):
        for s in [0, -1, bl.MAX_SEEDS + 1, True, '5', 2.5]:
            self.bad(seeds=s)
        wide = dict(KNOWN, policies=['p%d' % i for i in range(40)])
        with self.assertRaises(ValueError):
            bl.validate_request(req(policies=[], witches=[], seeds=30), wide)

    def test_bad_names_and_gear_and_preset(self):
        self.bad(policies=['synergy; ls'])
        self.bad(policies=['nonexistent'])
        self.bad(policies='synergy')
        self.bad(witches=['ember,frost'])
        self.bad(witches=['storm'])
        self.bad(gear='1.1; calc')
        self.bad(gear='$(x)')
        self.bad(gear='dmg=1.1 hp=1')
        self.bad(preset='spec1p --out=x')
        self.bad(preset='nope')
        self.bad(unknown_field=1)
        ok = bl.validate_request(req(gear='dmg=1.1,hp=1.05'), KNOWN)
        self.assertEqual(ok['gear'], 'dmg=1.1,hp=1.05')

    def test_command_is_an_argument_array_without_shell(self):
        r = bl.validate_request(req(sets=[{'key': 'rhythm.beats[2].amount', 'value': 6}], gear='1.1'), KNOWN)
        cmd = bl.build_command(r, KNOWN, Path('out.json'), Path('.'))
        self.assertIsInstance(cmd, list)
        self.assertIn('--set=rhythm.beats[2].amount=6', cmd)
        self.assertIn('--policies=synergy,narrow', cmd)
        self.assertTrue(any(c.endswith('balance_sim.py') for c in cmd))
        self.assertTrue(all(isinstance(c, str) for c in cmd))


class AnalysisTests(unittest.TestCase):
    def rates(self, syn, nar, rnd, spr, wst):
        return {'synergy|ember': syn, 'narrow|ember': nar, 'random|ember': rnd, 'spread|ember': spr, 'worst|ember': wst}

    def test_order_holds(self):
        a = bl.analyze(doc(self.rates(0.95, 0.3, 0.2, 0.1, 0.0)), KNOWN['probe'])
        self.assertTrue(a['verdict']['ok'])
        self.assertTrue(a['verdict']['headline'].startswith('서열 성립'))
        self.assertEqual(a['cells']['synergy|ember']['mark'], 'in')
        self.assertEqual(a['cells']['narrow|ember']['mark'], 'in')
        self.assertAlmostEqual(a['verdict']['witches'][0]['gap_pp'], 65.0)
        self.assertTrue(a['verdict']['witches'][0]['gap_ok'])

    def test_order_broken_names_the_pair(self):
        a = bl.analyze(doc(self.rates(0.5, 0.1, 0.4, 0.3, 0.0)), KNOWN['probe'])
        self.assertFalse(a['verdict']['ok'])
        self.assertIn('아무렇게나', a['verdict']['witches'][0]['broken'])
        self.assertEqual(a['cells']['spread|ember']['mark'], 'high')

    def test_unknown_keys_pass_through_and_missing_keys_do_not_crash(self):
        d = doc(self.rates(0.9, 0.3, 0.2, 0.1, 0.0), new_top={'a': 1})
        d['results']['synergy|ember']['crit_share'] = 0.25
        d['results']['synergy|ember']['factor_table'] = {'range': 1, 'count': 2}
        d['results']['narrow|ember'].pop('per_beat')
        d['results']['narrow|ember'].pop('deaths')
        a = bl.analyze(d, {})
        self.assertEqual(a['unknown_cell_keys'], ['crit_share', 'factor_table'])
        self.assertEqual(a['unknown_top_keys'], ['new_top'])
        self.assertEqual(a['cells']['synergy|ember']['extras']['crit_share'], 0.25)
        self.assertIsNone(a['cells']['synergy|ember']['mark'])

    def test_empty_and_odd_results(self):
        a = bl.analyze({'results': {}}, {})
        self.assertFalse(a['verdict']['ok'])
        a = bl.analyze({'results': {'synergy|ember': 'junk', 'x|y': {}}}, {})
        self.assertIn('x|y', a['cells'])

    def test_r_table_marks(self):
        a = bl.analyze(doc(self.rates(0.9, 0.3, 0.2, 0.1, 0.0)), KNOWN['probe'])
        syn = next(r for r in a['r_rows'] if r['cls'] == 'synergy')
        self.assertEqual(syn['beats']['기']['mark'], 'in')


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def fake(self, payload, seen=None):
        def runner(cmd, timeout):
            if seen is not None:
                seen.append(cmd)
            out = Path(next(c for c in cmd if c.startswith('--out='))[6:])
            out.write_text(json.dumps(payload), encoding='utf-8')
            return 0, b'', b''
        return runner

    def test_run_reads_result_and_removes_temp_files(self):
        seen = []
        r = bl.run(req(), self.root, KNOWN, runner=self.fake(doc({'synergy|ember': 0.9, 'narrow|ember': 0.3}), seen))
        self.assertEqual(r['analysis']['cells']['synergy|ember']['win_rate'], 0.9)
        self.assertIn('--preset spec1p', r['command'])
        self.assertEqual(list((self.root / '_local' / 'balance-lab' / 'runs').iterdir()), [])
        self.assertTrue(all(isinstance(c, str) for c in seen[0]))

    def test_bad_request_never_reaches_runner(self):
        called = []
        with self.assertRaises(ValueError):
            bl.run(req(sets=[{'key': 'a;b', 'value': 1}]), self.root, KNOWN, runner=lambda c, t: called.append(1))
        self.assertEqual(called, [])

    def test_simulator_failure_and_timeout_become_run_errors(self):
        with self.assertRaises(bl.RunError):
            bl.run(req(), self.root, KNOWN, runner=lambda c, t: (1, b'', 'KeyError: 키가 없다'.encode('utf-8')))
        import subprocess

        def slow(c, t):
            raise subprocess.TimeoutExpired(c, t)
        with self.assertRaises(bl.RunError):
            bl.run(req(), self.root, KNOWN, runner=slow)
        self.assertTrue(bl.RUN_LOCK.acquire(blocking=False))
        bl.RUN_LOCK.release()

    def test_only_one_run_at_a_time(self):
        gate, started, errors = threading.Event(), threading.Event(), []

        def slow(cmd, timeout):
            started.set()
            gate.wait(5)
            out = Path(next(c for c in cmd if c.startswith('--out='))[6:])
            out.write_text(json.dumps(doc({'synergy|ember': 0.9})), encoding='utf-8')
            return 0, b'', b''
        t = threading.Thread(target=lambda: bl.run(req(), self.root, KNOWN, runner=slow))
        t.start()
        self.assertTrue(started.wait(5))
        try:
            with self.assertRaises(bl.BusyError):
                bl.run(req(), self.root, KNOWN, runner=slow)
        finally:
            gate.set()
            t.join(5)

    def test_missing_results_key_is_reported(self):
        with self.assertRaises(bl.RunError):
            bl.run(req(), self.root, KNOWN, runner=self.fake({'preset': 'x'}))


class ExperimentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def save(self, **kw):
        p = {'name': '승2 생성 양 6', 'memo': '메모', 'settings': req(sets=[{'key': 'rhythm.beats[2].amount', 'value': 6}]), 'summary': {'headline': 'x', 'cells': {}}}
        p.update(kw)
        return bl.save_experiment(p, self.root, KNOWN)

    def test_save_list_export_stay_under_lab_dir(self):
        rec = self.save()
        base = (self.root / '_local' / 'balance-lab').resolve()
        files = [p.resolve() for p in base.rglob('*') if p.is_file()]
        self.assertEqual(len(files), 1)
        self.assertTrue(all(f.is_relative_to(base) for f in files))
        listed = bl.list_experiments(self.root)['experiments']
        self.assertEqual([e['id'] for e in listed], [rec['id']])
        ex = bl.export_sets({'id': rec['id']}, self.root, KNOWN)
        self.assertEqual(ex['bundle']['set_args'], ['rhythm.beats[2].amount=6'])
        self.assertTrue(ex['path'].startswith('_local/balance-lab/exports/'))
        self.assertTrue((self.root / ex['path']).is_file())
        self.assertFalse((self.root / 'chapter1').exists())

    def test_export_current_settings_without_saving(self):
        ex = bl.export_sets({'name': '임시', 'settings': req()}, self.root, KNOWN)
        self.assertEqual(ex['bundle']['sets'], [])
        self.assertTrue((self.root / ex['path']).is_file())

    def test_path_escape_and_bad_ids_rejected(self):
        for i in ['../x', '..\\x', 'exp-20260101-000000-zzzz', 'exp-1', '/abs', 'exp-20260101-000000-abcd/../../x']:
            with self.assertRaises(ValueError):
                bl.export_sets({'id': i}, self.root, KNOWN)
        with self.assertRaises(ValueError):
            bl.export_sets({'id': 'exp-20260101-000000-abcd'}, self.root, KNOWN)

    def test_bad_experiment_input_rejected(self):
        for kw in [{'name': ''}, {'name': 'x' * 61}, {'name': 'a\x00b'}, {'name': 3}, {'memo': 'm' * 4001}, {'settings': req(sets=[{'key': 'a;b', 'value': 1}])},
                   {'settings': req(spells='../../x')}, {'summary': ['x']}, {'summary': {'a': 'x' * 21000}}]:
            with self.assertRaises(ValueError):
                self.save(**kw)
        with self.assertRaises(ValueError):
            bl.save_experiment({'name': 'a', 'settings': req(), 'path': '../x'}, self.root, KNOWN)
        self.assertFalse((self.root / '_local' / 'balance-lab' / 'experiments').exists() and list((self.root / '_local' / 'balance-lab' / 'experiments').iterdir()))

    def test_broken_experiment_file_becomes_warning(self):
        rec = self.save()
        d = self.root / '_local' / 'balance-lab' / 'experiments'
        (d / 'exp-20200101-000000-aaaa.json').write_text('{broken', encoding='utf-8')
        out = bl.list_experiments(self.root)
        self.assertEqual(len(out['experiments']), 1)
        self.assertEqual(len(out['warnings']), 1)


class RealSimulatorTests(unittest.TestCase):
    """Uses the repo's simulator in a subprocess. Skipped if it is not there."""

    @classmethod
    def setUpClass(cls):
        if not (catalog.ROOT / bl.SIM_REL).is_file():
            raise unittest.SkipTest('balance_sim.py not found')

    def test_spell_files_are_an_allow_list(self):
        files = bl.spell_files()
        self.assertTrue(files)
        for f in files:
            self.assertTrue(f['abs'].is_file() and (f['abs'].is_relative_to(catalog.ROOT / 'tools' / 'dev') or f['abs'] == catalog.ROOT / bl.REAL_SPELLS))

    def test_meta_lists_spells_rhythm_and_policies(self):
        m = bl.meta()
        self.assertEqual(m['warnings'], [])
        self.assertTrue(m['spells'] and m['rhythm'] and m['policies'])
        keys = [r['key'] for g in m['spells'] for r in g['rows'] if r['key']]
        self.assertTrue(all(bl.KEY_RE.match(k) for k in keys))
        self.assertTrue(all(bl.KEY_RE.match(r['key']) for g in m['rhythm'] for r in g['rows'] if r['key']))
        self.assertIn('모델의 답이며 게임의 답이 아니다', m['banner']['text'])

    def test_real_run_and_set_changes_the_result(self):
        known = bl.known_options()
        r = bl.run(dict(preset='spec1p', spells='balance_sim_spells_draft', policies=['narrow'], witches=['ember'], seeds=2), None, known)
        self.assertIn('narrow|ember', r['analysis']['cells'])
        with self.assertRaises(bl.RunError):
            bl.run(dict(preset='spec1p', spells='balance_sim_spells_draft', policies=['narrow'], witches=['ember'], seeds=1,
                        sets=[{'key': 'rhythm.beats[2].nonexistent_key', 'value': 1}]), None, known)


if __name__ == '__main__':
    unittest.main()
