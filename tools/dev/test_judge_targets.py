#!/usr/bin/env python3
"""judge_targets.py 와 targets.json 의 자체 검사. Godot 도 실제 측정 파일도 필요 없다.

  python tools/dev/test_judge_targets.py
"""
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import judge_targets as J  # noqa: E402

ROOT = HERE.parent.parent
DOC = J.load_targets(J.DEFAULT_TARGETS)
T = {t['key']: t for t in DOC['targets']}


def nz(s):
    return re.sub(r'\s+', '', s.replace('**', '').replace('`', ''))


def rhythm_input(label_values, n=9, rhythm_on=False, victory=True):
    """label_values: {'기': {alive_avg:..}, ...} 를 n판 똑같이 가진 measure_rhythm JSON 모양."""
    runs = []
    for i in range(n):
        beats = []
        for lab, d in label_values.items():
            b = {'label': lab, 'reached': True, 'alive_avg': 10, 'alive_max': 15, 'kpm': 100, 'hits_pm': 1, 'dmg30': 0.1, 'prim_hits_per_kill': 1.2}
            b.update(d)
            beats.append(b)
        runs.append({'primary': 'ember', 'seed': 11 + i, 'mode': 'victory' if victory else 'defeat', 'secs': 330.0 + i, 'beats': beats,
                     'beat_source': 'beat_started event' if rhythm_on else 'time table (A2)',
                     'summary': {'grace_times': [5.0, 30.0, 60.0, 110.0, 280.0, 340.0]}})
    return {'bin_s': 30.0, 'runs': runs, 'cross': {}}


def write(tmp, name, data):
    p = Path(tmp) / name
    p.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    return str(p)


class TargetsFile(unittest.TestCase):
    def test_unique_keys_and_required_fields(self):
        keys = [t['key'] for t in DOC['targets']]
        self.assertEqual(len(keys), len(set(keys)))
        for t in DOC['targets']:
            for f in ('key', 'group', 'label', 'kind', 'status', 'unit', 'range', 'condition', 'source'):
                self.assertIn(f, t, t['key'])
            self.assertIn(t['kind'], ('auto', 'human'), t['key'])
            self.assertIn(t['status'], ('가설', '확정'), t['key'])
            for f in ('doc', 'section', 'text'):
                self.assertTrue(t['source'][f], t['key'])

    def test_human_items_have_no_range(self):
        for t in DOC['targets']:
            if t['kind'] == 'human':
                self.assertIsNone(t['range'], t['key'])

    def test_ranges_are_ordered(self):
        for t in DOC['targets']:
            r = t['range']
            if r and 'min' in r and 'max' in r:
                self.assertLessEqual(r['min'], r['max'], t['key'])

    def test_conflicts_list_every_candidate(self):
        confl = [t for t in DOC['targets'] if t.get('conflict')]
        self.assertEqual({t['key'] for t in confl}, {'q2.seconds', 'q4.jewelry'})
        for t in confl:
            self.assertGreaterEqual(len(t['conflict']['candidates']), 2)
        ids = {c['id'] for c in T['q2.seconds']['conflict']['candidates']}
        self.assertEqual(ids, {'quality', 'd11_g1', 'user_decision_1'})

    def test_sources_are_verbatim_segments_of_the_documents(self):
        cache = {}
        bad = []
        for t in DOC['targets']:
            srcs = [t['source']] + (t.get('extra_sources') or []) + [{'doc': c['doc'], 'text': c['text']} for c in (t.get('conflict') or {}).get('candidates', [])]
            for s in srcs:
                p = ROOT / s['doc']
                self.assertTrue(p.exists(), '%s: 문서 없음 %s' % (t['key'], s['doc']))
                doc = cache.setdefault(s['doc'], nz(p.read_text(encoding='utf-8')))
                for seg in re.split(r' \| | = ', s['text']):
                    if len(nz(seg)) >= 4 and nz(seg) not in doc:
                        bad.append((t['key'], seg))
        self.assertEqual(bad, [])

    def test_counts_by_kind_and_status(self):
        auto = sum(1 for t in DOC['targets'] if t['kind'] == 'auto')
        human = sum(1 for t in DOC['targets'] if t['kind'] == 'human')
        self.assertEqual(auto + human, len(DOC['targets']))
        self.assertGreater(auto, 100)
        self.assertGreater(human, 30)


class RangeLogic(unittest.TestCase):
    def test_in_range(self):
        self.assertTrue(J.in_range(5, {'min': 5, 'max': 15}))
        self.assertFalse(J.in_range(15.01, {'min': 5, 'max': 15}))
        self.assertTrue(J.in_range(0.39, {'max_excl': 0.4}))
        self.assertFalse(J.in_range(0.4, {'max_excl': 0.4}))
        self.assertTrue(J.in_range(1.0, {'eq': 1.0}))
        self.assertFalse(J.in_range(None, {'min': 1}))

    def test_fmt_range(self):
        self.assertEqual(J.fmt_range({'min': 5, 'max': 15}), '5~15')
        self.assertEqual(J.fmt_range({'max': 20}), '≤20')
        self.assertEqual(J.fmt_range({'min': 60}), '≥60')
        self.assertEqual(J.fmt_range(None), '(수치 범위 없음)')

    def test_sample_rules(self):
        t = {'range': {'min': 5, 'max': 15}, 'condition': {'min_runs': 9}}
        self.assertEqual(J.judge_values([10] * 9, t)['verdict'], J.PASS)
        self.assertEqual(J.judge_values([10] * 8 + [99], t)['verdict'], J.FAIL)
        self.assertEqual(J.judge_values([10] * 3, t, total_runs=3)['verdict'], J.NOMEAS)     # 표본 부족, 아직 판정 못 함
        self.assertEqual(J.judge_values([10, 99, 10], t, total_runs=3)['verdict'], J.FAIL)   # 남은 판이 다 통과해도 전 판 기준에 못 닿음
        self.assertEqual(J.judge_values([None, None], t, total_runs=2)['verdict'], J.NOMEAS)
        t8 = dict(t, pass_fraction=8 / 9)
        self.assertEqual(J.judge_values([10] * 8 + [99], t8)['verdict'], J.PASS)


class Judging(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_rows(self, files, playtests=None):
        inputs = [J.load_input(f) for f in files]
        rows, skipped = J.run_judge(DOC, inputs, J.load_playtests(playtests) if playtests else [])
        return inputs, rows, skipped

    def test_a2_pass_and_fail_on_synthetic_rhythm(self):
        ok = write(self.tmp, 'ok.json', rhythm_input({'기': {'alive_avg': 10, 'alive_max': 18, 'kpm': 120, 'hits_pm': 1, 'dmg30': 0.1}}))
        bad = write(self.tmp, 'bad.json', rhythm_input({'기': {'alive_avg': 40, 'alive_max': 99, 'kpm': 500, 'hits_pm': 9, 'dmg30': 0.5}}))
        _, rows, _ = self.run_rows([ok, bad])

        def v(key, name):
            return [r['verdict'] for r in rows if r['key'] == key and r['input'] == name][0]
        for k in ('a2.gi.alive_avg', 'a2.gi.alive_max', 'a2.gi.kpm', 'a2.gi.hits_pm', 'a2.gi.dmg30'):
            self.assertEqual(v(k, 'ok.json'), J.PASS, k)
            self.assertEqual(v(k, 'bad.json'), J.FAIL, k)

    def test_unmapped_auto_target_is_not_measured(self):
        _, rows, _ = self.run_rows([])
        r = [x for x in rows if x['key'] == 'q1.perf_p95_ms'][0]
        self.assertEqual(r['verdict'], J.NOMEAS)
        self.assertIn('재려면', r['detail'])

    def test_human_is_always_unevaluated_and_playlog_is_only_pointed_at(self):
        pt = Path(self.tmp) / 'playtests'
        pt.mkdir()
        q = T['q2.play.5']['question']
        (pt / '20261120-100000.json').write_text(json.dumps({'played_at': '2026-11-20T10:00:00', 'answers': {'a': {'text': q, 'score': 5, 'group_name': '전투 화면'}}}, ensure_ascii=False), encoding='utf-8')
        _, rows, _ = self.run_rows([], playtests=str(pt))
        human = [r for r in rows if r['kind'] == 'human']
        self.assertTrue(human)
        self.assertTrue(all(r['verdict'] == J.HUMAN for r in human))
        r = [x for x in human if x['key'] == 'q2.play.5'][0]
        self.assertIn('20261120-100000', r['detail'])
        other = [x for x in human if x['key'] == 'q2.play.1'][0]
        self.assertNotIn('플레이 기록', other['detail'])

    def test_conflict_combines_candidates(self):
        # 판 길이 330~339초: quality(300~360) 통과, d11_g1(390~450) 미달 → 충돌
        inp = write(self.tmp, 'r.json', rhythm_input({'기': {}}))
        _, rows, _ = self.run_rows([inp])
        r = [x for x in rows if x['key'] == 'q2.seconds'][0]
        self.assertEqual(r['verdict'], J.CONFLICT)
        self.assertTrue(r['conflict'])
        self.assertIn('quality', r['detail'])
        self.assertIn('d11_g1', r['detail'])

    def test_model_rows_never_mix_with_real(self):
        model = write(self.tmp, 'm.json', {'preset': 'spec1p', 'mode': 's', 'set': [], 'results': {
            'narrow|ember': {'win_rate': 0.3, 'n': 10, 'deaths': [], 'stalls': 0, 'per_beat': {'기': {'secs': 60, 'R': 2.0}}},
            'synergy|ember': {'win_rate': 0.95, 'n': 10, 'deaths': [], 'stalls': 0, 'per_beat': {'기': {'secs': 60, 'R': 2.5}}}}})
        _, rows, _ = self.run_rows([model])
        mrows = [r for r in rows if r['family'] == 'model']
        self.assertTrue(mrows)
        self.assertTrue(all(r['input'] == 'm.json' for r in mrows))
        real_with_input = [r for r in rows if r['family'] == 'real' and r['input']]
        self.assertEqual(real_with_input, [])
        win = [r for r in mrows if r['key'] == 'p7.win.narrow'][0]
        self.assertEqual(win['verdict'], J.PASS)
        self.assertEqual([r for r in mrows if r['key'] == 'p4.gi.synergy'][0]['verdict'], J.PASS)
        md = J.render_md(dict(DOC, path_shown='x'), [J.load_input(model)], rows, [])
        self.assertIn('모델(balance_sim) — 실측과 섞지 않는다', md)

    def test_base_state_targets_skip_inputs_with_equipment(self):
        def builds(no_equip):
            return {'cause_rules': {}, 'groups': {'narrow|ember': {'policy': 'narrow', 'primary': 'ember', 'win_rate': 0.3, 'n': 15, 'timeouts': 0, 'death_times': [300.0], 'defeat_causes': {'crowd': 1}}},
                    'no_equip': no_equip, 'rhythm_on': False, 'runs': [{}], 'policies': ['narrow']}
        a = write(self.tmp, 'noequip.json', builds(True))
        b = write(self.tmp, 'equip.json', builds(False))
        _, rows, skipped = self.run_rows([a, b])
        w = [r for r in rows if r['key'] == 'p7.win.narrow']
        self.assertEqual([r['input'] for r in w], ['noequip.json'])
        self.assertEqual(w[0]['verdict'], J.PASS)
        self.assertTrue(any(s['input'] == 'equip.json' for s in skipped))

    def test_synergy_now_is_never_the_synergy_verdict(self):
        b = write(self.tmp, 'b.json', {'cause_rules': {}, 'no_equip': True, 'rhythm_on': False, 'runs': [{}], 'policies': ['synergy_now'],
                                       'groups': {'synergy_now|ember': {'policy': 'synergy_now', 'primary': 'ember', 'win_rate': 1.0, 'n': 15, 'timeouts': 0}}})
        _, rows, _ = self.run_rows([b])
        r = [x for x in rows if x['key'] == 'p7.win.synergy' and x['input']][0]
        self.assertEqual(r['verdict'], J.NOMEAS)
        self.assertIn('synergy_now', r['detail'])

    def test_text_loaders_for_loot_and_combat(self):
        loot = Path(self.tmp) / 'loot.txt'
        loot.write_text('noise\nLOOT_SIM ' + json.dumps({'runs': 100, 'primary': 'chapter1.skill.frost', 'per_run_average': {'rare': 4.6, 'jewelry': 1.4, 'legendary': 0.9, 'unique': 0.2}}) + '\n', encoding='utf-8')
        row = {'primary': 'chapter1.skill.ember', 'seconds': 340.0, 'defeat': False, 'friendly_peak_1s': 70.0, 'combined_peak_1s': 70.0, 'hero_share_pre_evo': 1.0, 'hero_share_post_evo': 0.8,
               'primary_hit_share': 0.9, 'secondary_contribution': 0.2, 'attacks_per_min': 100.0, 'min_hp_ratio': 0.3, 'burst60': 0.1, 'heavy_min_gap_ticks': None, 'cap_fraction': 0.9}
        comb = Path(self.tmp) / 'comb.txt'
        comb.write_text('COMBAT_MEASURE ' + json.dumps({'cases': 9, 'rows': [dict(row, seed=11 + i) for i in range(9)], 'targets': {}}) + '\n', encoding='utf-8')
        _, rows, _ = self.run_rows([str(loot), str(comb)])

        def v(key, name):
            return [r['verdict'] for r in rows if r['key'] == key and r['input'] == name][0]
        self.assertEqual(v('q4.rare', 'loot.txt'), J.PASS)
        self.assertEqual(v('q4.legendary', 'loot.txt'), J.FAIL)          # 0.9 > 0.45
        self.assertEqual(v('q4.jewelry', 'loot.txt'), J.PASS)            # 1.4 는 d6_d2 0.6~1.6 안. quality("1개 안팎")는 범위가 없어 판정에서 빠진다
        self.assertEqual(v('q2.attacks_per_min', 'comb.txt'), J.PASS)
        self.assertEqual(v('q2.threat', 'comb.txt'), J.PASS)
        self.assertEqual(v('q2.heavy_gap', 'comb.txt'), J.PASS)
        self.assertEqual(v('q2.seconds', 'comb.txt'), J.CONFLICT)         # 340초: quality 300~360 통과, d11_g1 390~450 미달

    def test_unreadable_input_is_reported_not_crashing(self):
        p = Path(self.tmp) / 'junk.txt'
        p.write_text('nothing here', encoding='utf-8')
        inputs, rows, skipped = self.run_rows([str(p)])
        self.assertTrue(any(s['input'] == 'junk.txt' for s in skipped))

    def test_markdown_has_fixed_header(self):
        inputs, rows, skipped = self.run_rows([])
        md = J.render_md(dict(DOC, path_shown='x'), inputs, rows, skipped)
        self.assertIn('자동 조작 기준, 재미 미평가', md.splitlines()[2])

    def test_output_path_must_be_under_local(self):
        with self.assertRaises(SystemExit):
            J.safe_out(str(Path(self.tmp) / 'out.md'))
        ok = Path(self.tmp) / '_local' / 'x' / 'out.md'
        self.assertEqual(J.safe_out(str(ok)), ok.resolve())


class Constants(unittest.TestCase):
    def test_current_repo_known_differences(self):
        rows = J.check_constants(DOC, ROOT)
        self.assertGreater(len(rows), 60)
        by = {(r['where'].split('/')[-1], r['name']): r for r in rows}
        sec = by[('measure_combat.gd', 'TARGETS.seconds')]
        self.assertIn('quality', sec['status'])
        self.assertIn('충돌', sec['status'])
        self.assertEqual(by[('measure_combat.gd', 'COUNTERFACTUAL_GAIN')]['status'], '목표 없음')
        self.assertIn('d6_d2', by[('sim_loot.gd', 'TARGETS.jewelry')]['status'])
        self.assertEqual(by[('measure_combat.gd', 'TARGETS.friendly_peak_1s')]['status'], '일치')
        self.assertEqual(by[('balance_sim.py', 'P7_WIN.narrow')]['status'], '일치')
        self.assertEqual(by[('balance_sim.py', 'P7_WIN.synergy (synergy 일반형에도 같은 값 적용)')]['status'], '다름')

    def test_detects_a_changed_constant_in_a_copy(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            for rel in ('chapter1/tests/measure_combat.gd', 'chapter1/tests/sim_loot.gd', 'chapter1/tests/sim_progression.gd', 'chapter1/tests/measure_rhythm.gd', 'tools/dev/balance_sim.py'):
                dst = tmp / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / rel, dst)
            p = tmp / 'chapter1/tests/measure_rhythm.gd'
            txt = p.read_text(encoding='utf-8')
            self.assertIn('"kpm": [80, 180]', txt)
            p.write_text(txt.replace('"kpm": [80, 180]', '"kpm": [80, 999]'), encoding='utf-8', newline='')
            rows = J.check_constants(DOC, tmp)
            r = [x for x in rows if x['name'] == 'BEATS.기.kpm'][0]
            self.assertEqual(r['status'], '다름')
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_check_constants_never_writes_sources(self):
        before = (ROOT / 'chapter1/tests/measure_combat.gd').read_bytes()
        J.check_constants(DOC, ROOT)
        self.assertEqual(before, (ROOT / 'chapter1/tests/measure_combat.gd').read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
