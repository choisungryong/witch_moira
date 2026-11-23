"""스킬 시험실 뒷면 검사. 가짜 저장소 폴더(임시)와 가짜 state.json·가짜 Popen·가짜 채택 도구로 돈다.
tools/manager/local-state.json, local-picks.json 과 실제 _local/ 은 건드리지 않는다(채택의 고름 기록도 임시 경로)."""
import json, subprocess, sys, tempfile, threading, time, unittest, urllib.error, urllib.request, wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import picks, server, skill_lab, skill_lab_clips

PO = '''msgid ""
msgstr ""

msgid "character.ember.name"
msgstr "테사"

msgid "character.ember.class"
msgstr "화염 소서리스"

msgid "character.frost.name"
msgstr "아일린"

msgid "character.arc.name"
msgstr "베로니카"

msgid "skill.chapter1.skill.arc.name"
msgstr "체인 라이트닝"

msgid "skill.chapter1.skill.arc.evolved_name"
msgstr "썬더스톰"

msgid "descent.name.arc"
msgstr "저지먼트 볼트"

msgid "descent.desc.arc"
msgstr "번개 줄기가 내리꽂힌다"

msgid "skill.chapter1.skill.arc_ring.name"
msgstr "번개 고리"
'''
COMBAT_AUDIO = '''extends RefCounted
const PATH := "res://chapter1/art/quality03_audio/"
const DIRS := {}
const COUNTS := {"fire":2,"lightning":1,"impact":1}
const SILENT: Array[String] = ["lightning"]
'''


def make_wav(path, frames=2205):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
        w.writeframes(b'\x10\x00' * frames)


def rank(d, cd):
    return {'damage_raw': d, 'cooldown_ticks': cd, 'projectiles': 1, 'chain_targets': 0, 'branches': 1, 'pierce': 0, 'radius_cm': 0,
            'slow_bps': 0, 'freeze_stacks': 0, 'shatter_count': 0, 'death_burst': 0, 'proc_depth': 0, 'hit_budget': 1}


def build_repo(root, schema=2):
    root = Path(root)
    d = root / 'chapter1' / 'data'
    d.mkdir(parents=True)
    (d / 'character_progression.json').write_text(json.dumps({'characters': [
        {'id': 'chapter1.character.' + e, 'signature_skill_id': 'chapter1.skill.' + e} for e in ('ember', 'frost', 'arc')]}), encoding='utf-8')
    (d / 'growth_quality37.json').write_text(json.dumps({'passives': [{'id': 'p.' + e, 'name': '은총 ' + e} for e in ('ember', 'frost', 'arc')],
        'skills': [{'id': 'chapter1.skill.' + e, 'name': e, 'passive_id': 'p.' + e, 'evolution_name': e + '+', 'ranks': [rank(3072, 72), rank(3584, 66)],
                    'evolution': rank(8192, 48)} for e in ('ember', 'frost', 'arc')]}), encoding='utf-8')
    (d / 'descent.json').write_text(json.dumps({'enabled': False, 'cost': [3000, 8000, 10000], 'ultimates': {'arc': {'bolts': 40}, 'ember': {}, 'frost': {}}}), encoding='utf-8')
    amap = {'schema_version': schema, 'chain_lightning': {}}
    if schema == 2:
        amap['slots'] = {'skill.arc.cast': {'parent': 'lightning', 'per_targets': 3}, 'skill.ember.cast': {'parent': 'fire'},
                         'skill.meteor.land': {'parent': 'explosion'}, 'descent.arc.call': {'parent': ''}}
        amap['adopted'] = {}
    (d / 'audio_map.json').write_text(json.dumps(amap, indent=2), encoding='utf-8')
    (root / 'chapter1' / 'i18n').mkdir(parents=True)
    (root / 'chapter1' / 'i18n' / 'ko.po').write_text(PO, encoding='utf-8')
    (root / 'chapter1' / 'presentation').mkdir(parents=True)
    (root / 'chapter1' / 'presentation' / 'combat_audio.gd').write_text(COMBAT_AUDIO, encoding='utf-8')
    for cue, n in (('fire', 2), ('lightning', 1)):
        for i in range(n):
            make_wav(root / 'chapter1/art/quality03_audio' / ('%s_%d.wav' % (cue, i)))
    (root / 'chapter1/art/characters').mkdir(parents=True)
    (root / 'chapter1/art/characters/ember_witch_v02.png').write_bytes(b'\x89PNG fake')
    folder = root / '_local/audio/chain-lightning/round2'
    for k in (1, 2):
        for i in (1, 2, 3):
            make_wav(folder / ('assets/c%d_%d.wav' % (k, i)))
    (folder / 'lab-candidates.json').write_text(json.dumps({'schema': 1, 'title': '체인 2차', 'delivered': '2026-11-23', 'by': 'test', 'candidates': [
        {'key': 'C1', 'label': '하나', 'slot': 'skill.arc.cast', 'files': ['assets/c1_%d.wav' % i for i in (1, 2, 3)],
         'ledger': [{'file': 'c1_1.wav', 'source': 'synth', 'license': 'CC0'}]},
        {'key': 'C2', 'label': '둘', 'slot': 'skill.arc.cast', 'files': ['assets/c2_%d.wav' % i for i in (1, 2, 3)]},
    ]}), encoding='utf-8')


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'repo'
        self.root.mkdir()
        build_repo(self.root)
        skill_lab._LAUNCH.update(proc=None, at=0.0)

    def tearDown(self):
        self.tmp.cleanup()

    def write_state(self, **kw):
        st = {'protocol': 1, 'pid': 4242, 'heartbeat_unix_ms': int(time.time() * 1000), 'applied_seq': 3, 'ready': True,
              'scene': {'character': 'chapter1.character.arc'}, 'run': {}, 'casts': {}, 'audio': {'overrides': {}, 'load_errors': [], 'recent': []}, 'errors': []}
        st.update(kw)
        p = skill_lab.lab_dir(self.root) / 'state.json'
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(st), encoding='utf-8')

    def command(self):
        return json.loads((skill_lab.lab_dir(self.root) / 'command.json').read_text(encoding='utf-8'))

    def scene(self, **kw):
        s = {'character': 'chapter1.character.arc', 'skill': 'chapter1.skill.arc', 'form': 'base', 'layout': 'pack', 'count': 8}
        s.update(kw)
        return s


class DataTests(Base):
    def test_characters_from_data_and_po(self):
        warn = []
        chars = skill_lab.characters_table(self.root, warn)
        self.assertEqual([c['elem'] for c in chars], ['ember', 'frost', 'arc'])
        arc = chars[2]
        self.assertEqual((arc['name'], arc['primary']), ('베로니카', 'chapter1.skill.arc'))
        forms = {f['form']: f for f in arc['forms']}
        self.assertEqual(forms['base']['name'], '체인 라이트닝')
        self.assertEqual(forms['evolved']['name'], '썬더스톰')
        self.assertEqual(forms['descent']['name'], '저지먼트 볼트')
        self.assertIn(['bolts', '40'], forms['descent']['pairs'])
        self.assertFalse(forms['ring']['available'])
        self.assertEqual(forms['base']['table']['columns'], ['단계', '랭크 1', '랭크 2', '진화'])
        self.assertEqual(forms['base']['table']['rows'][1][1], '1.2')   # 72틱 = 1.2초: catalog 의 표기 그대로
        self.assertTrue(chars[0]['portrait'] and not arc['portrait'])

    def test_data_change_is_read_again(self):
        p = self.root / 'chapter1/i18n/ko.po'
        p.write_text(p.read_text(encoding='utf-8').replace('체인 라이트닝', '번개 사슬'), encoding='utf-8')
        self.assertEqual(skill_lab.characters_table(self.root)[2]['forms'][0]['name'], '번개 사슬')

    def test_missing_data_gives_warning_not_crash(self):
        (self.root / 'chapter1/data/growth_quality37.json').unlink()
        warn = []
        self.assertEqual(skill_lab.characters_table(self.root, warn), [])
        self.assertTrue(warn)

    def test_slots_current_sound(self):
        w = []
        t = skill_lab.slots_table(self.root, w)
        rows = {r['slot']: r for r in t['rows']}
        self.assertEqual(rows['skill.ember.cast']['current']['kind'], 'parent')
        self.assertEqual(len(rows['skill.ember.cast']['current']['files']), 2)
        self.assertEqual(rows['skill.arc.cast']['current']['kind'], 'silent')      # SILENT 의 lightning
        self.assertEqual(rows['descent.arc.call']['current']['kind'], 'silent')
        self.assertEqual(rows['skill.meteor.land']['owner'], {'elem': 'ember', 'form': 'evolved'})
        self.assertEqual(rows['skill.arc.cast']['per_targets'], 3)

    def _write_audio(self, text):
        (self.root / 'chapter1/presentation/combat_audio.gd').write_text(text, encoding='utf-8')

    def test_game_loudness_matches_code_and_data(self):
        import math
        self._write_audio(COMBAT_AUDIO + 'const GAINS := {"fire":.8,"lightning":.82,"explosion":1.0}\nconst SLOT_DEFAULT := {"cooldown":60,"gain":1.0}\nvar master_volume := .8\n'
                          'func f():\n\tvoice.volume_db=linear_to_db(maxf(.0001,master_volume*.11*voice_gains[index]))\n')
        t = skill_lab.slots_table(self.root, [])
        rows = {r['slot']: r for r in t['rows']}
        self.assertEqual((t['mix']['master'], t['mix']['mix_gain']), (0.8, 0.11))        # 코드의 곱셈 리터럴에서
        self.assertAlmostEqual(rows['skill.ember.cast']['game_gain'], 0.8 * 0.11 * 0.8, places=6)
        self.assertEqual(rows['skill.ember.cast']['game_db'], round(20 * math.log10(0.8 * 0.11 * 0.8), 1))
        self.assertAlmostEqual(rows['descent.arc.call']['game_gain'], 0.8 * 0.11, places=6)     # 부모 소리 없음: 자리 기본 이득
        self.assertEqual(rows['skill.arc.cast']['current']['kind'], 'silent')              # 게임 안 무음 표시의 근거
        self.assertEqual(rows['descent.arc.call']['current']['kind'], 'silent')
        self.assertEqual(t['mix']['silent_parents'], ['lightning'])

    def test_mix_gain_order_data_then_code_then_default(self):
        self._write_audio(COMBAT_AUDIO + 'const MIX_GAIN_DEFAULT := .2\n')
        self.assertEqual(skill_lab.slots_table(self.root, [])['mix']['mix_gain'], 0.2)     # 코드 상수
        mp = self.root / 'chapter1/data/audio_map.json'
        d = json.loads(mp.read_text(encoding='utf-8')); d['mix_gain'] = 0.3
        mp.write_text(json.dumps(d), encoding='utf-8')
        self.assertEqual(skill_lab.slots_table(self.root, [])['mix']['mix_gain'], 0.3)     # 데이터가 먼저
        d.pop('mix_gain'); mp.write_text(json.dumps(d), encoding='utf-8')
        self._write_audio(COMBAT_AUDIO)
        w = []
        self.assertEqual(skill_lab.slots_table(self.root, w)['mix']['mix_gain'], 0.11)     # 못 읽으면 0.11, 경고
        self.assertTrue(w)

    def test_real_repo_values_are_read(self):
        t = skill_lab.slots_table(skill_lab.ROOT, [])
        self.assertTrue(0 < t['mix']['mix_gain'] < 1 and 0 < t['mix']['master'] <= 1)
        self.assertIn('lightning', t['mix']['silent_parents'])
        self.assertTrue(all(r['game_db'] is not None and r['game_db'] < 0 for r in t['rows']))

    def test_typed_const_is_read_by_gd_const(self):
        import catalog
        t = 'const SILENT: Array[String] = ["lightning", "x"]\nconst D: Dictionary = {"a": 1}\nconst E := 3\nconst F: int = 4\n'
        self.assertEqual(catalog.gd_const(t, 'SILENT'), ['lightning', 'x'])
        self.assertEqual((catalog.gd_const(t, 'D'), catalog.gd_const(t, 'E'), catalog.gd_const(t, 'F')), ({'a': 1}, 3, 4))
        w = []
        self.assertEqual(skill_lab._gd_consts(self.root, w)['SILENT'], ['lightning'])
        self.assertEqual(w, [])

    def test_po_skill_description_is_read_when_present(self):
        arc = lambda: next(c for c in skill_lab.characters_table(self.root) if c['elem'] == 'arc')
        self.assertIn('설명 문장이 없고', arc()['forms'][0]['text'])
        po = self.root / 'chapter1/i18n/ko.po'
        po.write_text(po.read_text(encoding='utf-8') + '\nmsgid "skill.chapter1.skill.arc.desc"\nmsgstr "번개가 적 사이를 튄다"\n\nmsgid "skill.chapter1.skill.arc.evolved_desc"\nmsgstr "폭풍이 몰아친다"\n', encoding='utf-8')
        forms = arc()['forms']
        self.assertEqual((forms[0]['text'], forms[1]['text']), ('번개가 적 사이를 튄다', '폭풍이 몰아친다'))

    def test_schema1_has_no_slots(self):
        with tempfile.TemporaryDirectory() as t:
            r = Path(t) / 'r'
            r.mkdir()
            build_repo(r, schema=1)
            tab = skill_lab.slots_table(r, [])
            self.assertEqual(tab['rows'], [])
            self.assertIn('스키마', tab['note'])
            self.assertFalse(skill_lab.adopt_available(r)[0])

    def test_adopted_slot_is_shown_as_adopted(self):
        p = self.root / 'chapter1/data/audio_map.json'
        d = json.loads(p.read_text(encoding='utf-8'))
        make_wav(self.root / 'chapter1/art/audio/slots/skill.arc.cast/C1_1.wav')
        d['adopted']['skill.arc.cast'] = {'files': ['res://chapter1/art/audio/slots/skill.arc.cast/C1_1.wav'], 'candidate': 'x/C1', 'date': '2026-11-23'}
        p.write_text(json.dumps(d), encoding='utf-8')
        cur = {r['slot']: r for r in skill_lab.slots_table(self.root, [])['rows']}['skill.arc.cast']['current']
        self.assertEqual((cur['kind'], len(cur['files'])), ('adopted', 1))


class CandidateTests(Base):
    def test_scan(self):
        w = []
        c = skill_lab.scan_candidates(self.root, w)
        self.assertEqual([x['id'] for x in c], ['chain-lightning/round2/C1', 'chain-lightning/round2/C2'])
        self.assertEqual(c[0]['paths'][0], '_local/audio/chain-lightning/round2/assets/c1_1.wav')
        self.assertTrue(c[0]['origin_known'] and not c[1]['origin_known'])
        self.assertEqual(w, [])

    def test_empty_slot_is_listen_only_not_a_warning(self):
        f = self.root / '_local/audio/chain-lightning/round2/lab-candidates.json'
        f.write_text(json.dumps({'schema': 1, 'title': '자리 없는 묶음', 'candidates': [
            {'key': 'free-1', 'label': '자리 없음 · 아무 소리', 'slot': '', 'files': ['assets/c1_1.wav']}]}), encoding='utf-8')
        w = []
        c = skill_lab.scan_candidates(self.root, w)
        self.assertEqual(w, [])
        self.assertEqual([(x['id'], x['slot'], x['listen_only']) for x in c], [('chain-lightning/round2/free-1', '', True)])
        self.assertIsNotNone(skill_lab.audio_file(self.root, 'chain-lightning/round2/free-1', None, 0))      # 듣기는 된다
        with self.assertRaises(ValueError):                                                                     # 끼우기는 안 된다
            skill_lab.clean_audio({'skill.arc.cast': 'chain-lightning/round2/free-1'}, self.root)
        self.assertTrue(skill_lab.overview(self.root)['candidates'][0]['listen_only'])

    def test_bad_paths_rejected(self):
        f = self.root / '_local/audio/chain-lightning/round2/lab-candidates.json'
        bad = ['../../../../chapter1/data/audio_map.json', '/etc/x.wav', 'C:/x.wav', 'assets/..\\x.wav', 'assets/c1_1.txt', 'chapter1/art/../data/x.wav', './assets/c1_1.wav', '']
        for b in bad:
            f.write_text(json.dumps({'schema': 1, 'candidates': [{'key': 'X', 'slot': 'skill.arc.cast', 'files': [b]}]}), encoding='utf-8')
            w = []
            self.assertEqual(skill_lab.scan_candidates(self.root, w), [], b)
            self.assertTrue(w, b)

    def test_missing_file_flagged_and_repo_art_path_allowed(self):
        make_wav(self.root / 'chapter1/art/audio/chain/a1.wav')
        f = self.root / '_local/audio/chain-lightning/round2/lab-candidates.json'
        f.write_text(json.dumps({'schema': 1, 'candidates': [
            {'key': 'A', 'slot': 'skill.arc.cast', 'files': ['chapter1/art/audio/chain/a1.wav']},
            {'key': 'M', 'slot': 'skill.arc.cast', 'files': ['assets/nope.wav']}]}), encoding='utf-8')
        c = {x['key']: x for x in skill_lab.scan_candidates(self.root, [])}
        self.assertEqual(c['A']['paths'], ['chapter1/art/audio/chain/a1.wav'])
        self.assertEqual(c['M']['missing'], ['_local/audio/chain-lightning/round2/assets/nope.wav'])

    def test_wrong_schema_and_duplicate(self):
        f = self.root / '_local/audio/chain-lightning/round2/lab-candidates.json'
        f.write_text(json.dumps({'schema': 2, 'candidates': []}), encoding='utf-8')
        w = []
        self.assertEqual(skill_lab.scan_candidates(self.root, w), [])
        self.assertTrue(w)
        f.write_text(json.dumps({'schema': 1, 'candidates': [{'key': 'D', 'slot': 'skill.arc.cast', 'files': ['assets/c1_1.wav']}] * 2}), encoding='utf-8')
        w = []
        self.assertEqual(len(skill_lab.scan_candidates(self.root, w)), 1)
        self.assertTrue(w)

    def test_audio_served_by_id_only(self):
        ok = skill_lab.audio_file(self.root, 'chain-lightning/round2/C1', None, 2)
        self.assertTrue(ok and ok.name == 'c1_3.wav')
        for bad in (('chain-lightning/round2/C1', 3), ('chain-lightning/round2/C1', -1), ('../../chapter1/data/audio_map', 0), ('nope', 0),
                    ('chain-lightning/round2/C1/../../..', 0), ('chain-lightning/round2/C1', 'x')):
            self.assertIsNone(skill_lab.audio_file(self.root, bad[0], None, bad[1]), bad)
        cur = skill_lab.audio_file(self.root, None, 'skill.ember.cast', 1)
        self.assertTrue(cur and cur.name == 'fire_1.wav')
        self.assertIsNone(skill_lab.audio_file(self.root, None, 'no.such.slot', 0))
        self.assertIsNone(skill_lab.audio_file(self.root, None, None, 0))


class CommandTests(Base):
    def test_scene_shape_and_seq(self):
        r1 = skill_lab.send_scene(self.root, self.scene(), {'skill.arc.cast': 'chain-lightning/round2/C1'})
        cmd = self.command()
        self.assertEqual((cmd['protocol'], cmd['seq'], cmd['op']), (1, 1, 'scene'))
        self.assertEqual(cmd['scene'], {'character': 'chapter1.character.arc', 'skill': 'chapter1.skill.arc', 'form': 'base', 'layout': 'pack', 'count': 8,
                                        'motion': 'approach', 'durable': False, 'repeat': True, 'interval_s': 3.0, 'speed': 1.0, 'juice': True})
        self.assertEqual(len(cmd['audio']['skill.arc.cast']), 3)
        self.assertTrue(cmd['audio']['skill.arc.cast'][0].startswith('_local/audio/'))
        self.write_state(applied_seq=9)
        skill_lab.send_simple(self.root, 'cast')
        self.assertEqual(self.command()['seq'], 10)      # 창이 적용한 번호보다 늘 크다
        self.assertEqual(r1['seq'], 1)
        self.assertFalse(list(skill_lab.lab_dir(self.root).glob('*.tmp')))

    def test_scene_validation(self):
        bad = [self.scene(character='chapter1.character.nope'), self.scene(skill='chapter1.skill.frost'), self.scene(form='ring'), self.scene(layout='x'),
               self.scene(count=0), self.scene(count=41), self.scene(count=True), self.scene(interval_s=1.0), self.scene(speed=2), self.scene(juice='yes'),
               self.scene(extra=1), 'x', None]
        for b in bad:
            with self.assertRaises(ValueError, msg=str(b)):
                skill_lab.send_scene(self.root, b)
        self.assertFalse((skill_lab.lab_dir(self.root) / 'command.json').exists())

    def test_audio_validation(self):
        S = self.scene()
        for bad in ({'skill.arc.cast': 'nope'}, {'no.slot': 'chain-lightning/round2/C1'}, {'skill.ember.cast': 'chain-lightning/round2/C1'},
                    {'skill.arc.cast': ['../x.wav']}, {'skill.arc.cast': ['/abs/x.wav']}, {'skill.arc.cast': ['chapter1/data/audio_map.json']},
                    {'skill.arc.cast': ['_local/audio/chain-lightning/round2/assets/c1_1.txt']}, {'skill.arc.cast': ['C:\\x.wav']}, [1], {'skill.arc.cast': 5}):
            with self.assertRaises(ValueError, msg=str(bad)):
                skill_lab.send_scene(self.root, S, bad)
        skill_lab.send_scene(self.root, S, {'skill.arc.cast': ['_local/audio/chain-lightning/round2/assets/c1_1.wav'], 'skill.ember.cast': None})
        self.assertEqual(list(self.command()['audio']), ['skill.arc.cast'])

    def test_shot_name_checked(self):
        r = skill_lab.request_shot(self.root, 'page-1')
        self.assertEqual(self.command()['shot'], '_local/skill-lab/shots/page-1.png')
        self.assertEqual(r['path'], '_local/skill-lab/shots/page-1.png')
        for bad in ('../x', 'a/b', '', 'x' * 41, None, 'a.png'):
            with self.assertRaises(ValueError):
                skill_lab.request_shot(self.root, bad)

    def test_window_status(self):
        now = int(time.time() * 1000)
        self.assertEqual(skill_lab.window_status(self.root, now, lambda p: True)['status'], 'none')
        self.write_state(heartbeat_unix_ms=now - 500)
        self.assertEqual(skill_lab.window_status(self.root, now, lambda p: True)['status'], 'connected')
        self.assertEqual(skill_lab.window_status(self.root, now, lambda p: False)['status'], 'lost')
        self.assertEqual(skill_lab.window_status(self.root, now + 5000, lambda p: True)['status'], 'lost')
        (skill_lab.lab_dir(self.root) / 'state.json').write_text('{"half', encoding='utf-8')
        w = skill_lab.window_status(self.root, now, lambda p: True)
        self.assertEqual((w['status'], w['read_error']), ('none', 'unreadable'))

    def test_override_ids_in_overview(self):
        c = skill_lab.scan_candidates(self.root)[0]
        self.write_state(audio={'overrides': {'skill.arc.cast': c['paths']}, 'load_errors': [], 'recent': []})
        o = skill_lab.overview(self.root, None, lambda p: True)
        self.assertEqual(o['window']['override_ids'], {'skill.arc.cast': c['id']})
        self.assertEqual(o['window']['status'], 'connected')


class OpenTests(Base):
    class FakePopen:
        calls = []

        def __init__(self, args, **kw):
            type(self).calls.append((args, kw))

        def poll(self):
            return None

    def setUp(self):
        super().setUp()
        self.FakePopen.calls = []
        (self.root / 'chapter1/tests').mkdir(parents=True)
        (self.root / 'chapter1/tests/skill_lab.gd').write_text('extends SceneTree\n', encoding='utf-8')

    def test_script_missing_says_so(self):
        (self.root / 'chapter1/tests/skill_lab.gd').unlink()
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.open_window(self.root, self.scene(), None, popen=self.FakePopen)
        self.assertEqual(cm.exception.status, 404)
        self.assertEqual(self.FakePopen.calls, [])
        self.assertFalse(skill_lab.overview(self.root)['window']['script_exists'])

    def test_launch_command_and_scene_written_first(self):
        r = skill_lab.open_window(self.root, self.scene(), None, popen=self.FakePopen)
        self.assertTrue(r['launched'])
        (args, kw), = self.FakePopen.calls
        self.assertFalse(kw.get('shell'))
        for need in ('--chapter1-profile-off', '--chapter1-qa-ignore-focus', '--chapter1-trial=descent', '--chapter1-descent-cost=1000', '--timeout-s=14400',
                     '--chapter1-primary=chapter1.skill.arc', '--lab-dir=_local/skill-lab', 'res://chapter1/tests/skill_lab.gd'):
            self.assertIn(need, args)
        self.assertNotIn('--chapter1-pilot', args)
        self.assertTrue(args[1].endswith('godot.py'))
        self.assertNotIn('--headless', args)
        self.assertEqual(self.command()['op'], 'scene')

    def test_alive_window_is_not_launched_again(self):
        self.write_state()
        r = skill_lab.open_window(self.root, self.scene(layout='line'), None, popen=self.FakePopen, pid_alive=lambda p: True)
        self.assertFalse(r['launched'])
        self.assertEqual(self.FakePopen.calls, [])
        self.assertEqual(self.command()['scene']['layout'], 'line')

    def test_starting_window_is_not_launched_twice(self):
        skill_lab.open_window(self.root, self.scene(), None, popen=self.FakePopen)
        skill_lab.open_window(self.root, self.scene(), None, popen=self.FakePopen)
        self.assertEqual(len(self.FakePopen.calls), 1)
        self.assertEqual(skill_lab.window_status(self.root)['status'], 'starting')

    def test_hero_models_flag_and_relaunch(self):
        skill_lab.open_window(self.root, self.scene(), None, hero_models=True, popen=self.FakePopen)
        self.assertIn('--chapter1-hero-models', self.FakePopen.calls[0][0])
        skill_lab._LAUNCH.update(proc=None)
        self.write_state()
        with self.assertRaises(skill_lab.LabError):     # 켜기를 바꾸면 창을 닫으라고 보내고, 안 닫히면 거절
            skill_lab.open_window(self.root, self.scene(), None, hero_models=False, popen=self.FakePopen, pid_alive=lambda p: True, wait=0.2)
        self.assertEqual(self.command()['op'], 'quit')

    def test_pid_alive_never_kills_self(self):
        import os
        self.assertTrue(skill_lab._pid_alive(os.getpid()))
        self.assertFalse(skill_lab._pid_alive(0))
        self.assertFalse(skill_lab._pid_alive('x'))


class AdoptTests(Base):
    def setUp(self):
        super().setUp()
        (self.root / 'tools/dev').mkdir(parents=True)
        (self.root / 'tools/dev/audio_adopt.py').write_text('# fake\n', encoding='utf-8')
        self.picks = Path(self.tmp.name) / 'picks.json'
        self.calls = []

    def runner(self, code=0, out=''):
        def run(args, **kw):
            self.calls.append(args)
            if args[0] == 'git':
                return subprocess.CompletedProcess(args, 0, b' chapter1/data/audio_map.json | 4 +++-\n', b'')
            return subprocess.CompletedProcess(args, code, out.encode('utf-8'), b'boom' if code else b'')
        return run

    def rev(self):
        return skill_lab.map_info(self.root)['rev']

    def test_tool_missing_disables(self):
        (self.root / 'tools/dev/audio_adopt.py').unlink()
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.adopt(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.rev(), self.runner(), self.picks)
        self.assertEqual(cm.exception.status, 503)
        o = skill_lab.overview(self.root)
        self.assertFalse(o['adopt']['available'])
        self.assertIn('audio_adopt.py', o['adopt']['reason'])

    def test_rev_mismatch_409_without_running(self):
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.adopt(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', 'deadbeef', self.runner(), self.picks)
        self.assertEqual(cm.exception.status, 409)
        self.assertEqual(cm.exception.extra['map_rev'], self.rev())
        self.assertEqual(self.calls, [])
        self.assertFalse(self.picks.exists())

    def test_tool_exit3_is_409(self):
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.adopt(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.rev(), self.runner(3), self.picks)
        self.assertEqual(cm.exception.status, 409)
        self.assertFalse(self.picks.exists())

    def test_tool_failure_is_reported_and_no_pick(self):
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.adopt(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.rev(), self.runner(1, 'bad'), self.picks)
        self.assertEqual(cm.exception.status, 422)
        self.assertFalse(self.picks.exists())

    def test_unknown_inputs_rejected(self):
        for slot, cand in (('no.slot', 'chain-lightning/round2/C1'), ('skill.arc.cast', 'nope'), ('skill.ember.cast', 'chain-lightning/round2/C1'), ('skill.arc.cast', None)):
            with self.assertRaises(skill_lab.LabError) as cm:
                skill_lab.adopt(self.root, slot, cand, self.rev(), self.runner(), self.picks)
            self.assertEqual(cm.exception.status, 400, (slot, cand))
        self.assertEqual(self.calls, [])

    def test_success_records_pick_and_reloads_window(self):
        self.write_state()
        out = 'noise\nAUDIO_ADOPT {"written": ["a.wav"], "check": "ok"}\n'
        r = skill_lab.adopt(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.rev(), self.runner(0, out), self.picks, lambda p: True)
        self.assertEqual(r['result'], {'written': ['a.wav'], 'check': 'ok'})
        self.assertIn('audio_map.json', r['git_diff_stat'])
        tool_args = self.calls[0]
        self.assertEqual(tool_args[2:], ['adopt', '--slot', 'skill.arc.cast', '--candidate', 'chain-lightning/round2/C1', '--expect-rev', self.rev(), '--yes'])
        rec, = picks.load(self.picks)['records'].values()
        self.assertEqual((rec['screen'], rec['subject'], rec['verdict']), ('skill', 'skill/chapter1.skill.arc/sound/skill.arc.cast', 'pick'))
        self.assertTrue(r['reload_sent'])
        self.assertEqual(self.command()['op'], 'reload_audio')

    def test_preview_uses_dry_run_and_never_yes(self):
        out = 'text\nAUDIO_ADOPT ' + json.dumps({'ok': True, 'dry_run': True, 'confirm': '채택 확인 글', 'warnings': ['무음이던 소리가 울립니다'],
                                              'files': [{'dest_rel': 'chapter1/art/audio/slots/skill.arc.cast/C1_1.wav', 'format': 'wav'}], 'parent': 'lightning',
                                              'parent_silent_today': True}) + '\n'
        r = skill_lab.adopt_preview(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.runner(0, out))
        self.assertEqual(self.calls[0][2:], ['adopt', '--slot', 'skill.arc.cast', '--candidate', 'chain-lightning/round2/C1', '--dry-run'])
        self.assertNotIn('--yes', self.calls[0])
        self.assertEqual((r['confirm'], r['parent_silent_today'], r['map_rev']), ('채택 확인 글', True, self.rev()))
        self.assertEqual(r['files'][0]['dest_rel'].split('/')[-1], 'C1_1.wav')
        self.assertFalse(self.picks.exists())

    def test_preview_refusals(self):
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.adopt_preview(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.runner(2, 'bad'))
        self.assertEqual(cm.exception.status, 422)
        for slot, cand in (('no.slot', 'chain-lightning/round2/C1'), ('skill.arc.cast', 'nope')):
            with self.assertRaises(skill_lab.LabError) as cm:
                skill_lab.adopt_preview(self.root, slot, cand, self.runner(0, 'AUDIO_ADOPT {}\n'))
            self.assertEqual(cm.exception.status, 400)
        (self.root / 'tools/dev/audio_adopt.py').unlink()
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.adopt_preview(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.runner(0, ''))
        self.assertEqual(cm.exception.status, 503)

    def test_success_without_window_sends_nothing(self):
        r = skill_lab.adopt(self.root, 'skill.arc.cast', 'chain-lightning/round2/C1', self.rev(), self.runner(0, 'AUDIO_ADOPT {}\n'), self.picks)
        self.assertFalse(r['reload_sent'])
        self.assertFalse((skill_lab.lab_dir(self.root) / 'command.json').exists())

    def test_revert(self):
        r = skill_lab.revert(self.root, 'skill.arc.cast', self.rev(), self.runner(0, 'AUDIO_ADOPT {"reverted": true}\n'), self.picks)
        self.assertEqual(self.calls[0][2:], ['revert', '--slot', 'skill.arc.cast', '--expect-rev', self.rev()])
        self.assertEqual(r['result'], {'reverted': True})
        with self.assertRaises(skill_lab.LabError) as cm:
            skill_lab.revert(self.root, 'skill.arc.cast', 'old', self.runner(), self.picks)
        self.assertEqual(cm.exception.status, 409)


class PolicyTests(unittest.TestCase):
    def test_policy_declared_in_one_place(self):
        P = skill_lab.route_policy
        self.assertEqual(P('POST', '/api/skill-lab/open'), skill_lab.LOCAL_ONLY)
        self.assertEqual(P('POST', '/api/skill-lab/shot'), skill_lab.LOCAL_ONLY)
        self.assertEqual(P('GET', '/api/skill-lab/shot?name=x'), skill_lab.LOCAL_ONLY)
        self.assertEqual(P('POST', '/api/skill-lab/clip'), 'skill_lab.clip')
        self.assertEqual(P('POST', '/api/skill-lab/adopt'), 'skill_lab.adopt')
        self.assertEqual(P('POST', '/api/skill-lab/adopt-preview'), 'skill_lab.adopt')
        self.assertEqual(P('POST', '/api/skill-lab/scene'), 'skill_lab.scene')
        self.assertEqual(P('GET', '/api/skill-lab/clip/' + 'a' * 24 + '/video'), 'view')
        self.assertIsNone(P('POST', '/api/skill-lab/unknown'))
        self.assertIsNone(P('GET', '/api/skill-lab/clip/zz'))


class ClipTests(Base):
    def setUp(self):
        super().setUp()
        skill_lab_clips._JOBS.clear()
        skill_lab_clips._QUEUE.clear()
        skill_lab_clips._SIG.clear()
        self.shots = []
        self.real = skill_lab_clips.SHOOT['fn']
        self.limit = skill_lab_clips.MAX_BYTES

        def fake(root, scene, audio, way, cid, out):
            self.shots.append((cid, way, audio))
            Path(out).write_bytes(b'x' * 1000)
            return {'start_frame': 7}
        skill_lab_clips.SHOOT['fn'] = fake
        (self.root / 'chapter1/core').mkdir(parents=True)
        for i in (1, 2, 3):
            make_wav(self.root / ('_local/audio/chain-lightning/round2/assets/c2_%d.wav' % i), frames=3000)   # 내용이 다르면 열쇠도 다르다
        (self.root / 'chapter1/core/combat_core.gd').write_text('# core v1\n', encoding='utf-8')

    def tearDown(self):
        skill_lab_clips.SHOOT['fn'] = self.real
        skill_lab_clips.MAX_BYTES = self.limit
        skill_lab_clips._JOBS.clear()
        skill_lab_clips._QUEUE.clear()
        super().tearDown()

    def ask(self, audio=None, **kw):
        return skill_lab_clips.request(self.root, self.scene(**kw), audio, 'movie', start_worker=False)

    def test_world_hash_follows_files_not_mtime_only(self):
        a = skill_lab_clips.world_hash(self.root)
        self.assertEqual(a, skill_lab_clips.world_hash(self.root))
        (self.root / 'chapter1/core/combat_core.gd').write_text('# core v2\n', encoding='utf-8')
        self.assertNotEqual(a, skill_lab_clips.world_hash(self.root))
        b = skill_lab_clips.world_hash(self.root)
        p = self.root / 'chapter1/data/audio_map.json'
        p.write_text(p.read_text(encoding='utf-8') + ' ', encoding='utf-8')
        self.assertNotEqual(b, skill_lab_clips.world_hash(self.root))

    def test_shoot_once_then_cache(self):
        j = self.ask()
        self.assertEqual(j['state'], 'queued')
        skill_lab_clips.run_queue()
        self.assertEqual(len(self.shots), 1)
        st = skill_lab_clips.status(self.root, j['id'])
        self.assertEqual((st['state'], st['stale'], st['size']), ('done', False, 1000))
        self.assertTrue(st['video'].endswith(j['id'] + '/video'))
        meta = skill_lab_clips.read_meta(self.root, j['id'])
        self.assertEqual((meta['way'], meta['start_frame']), ('movie', 7))
        again = self.ask()
        self.assertEqual((again['state'], again['cached'], again['id']), ('done', True, j['id']))
        skill_lab_clips.run_queue()
        self.assertEqual(len(self.shots), 1)               # 같은 열쇠는 다시 찍지 않는다

    def test_key_parts(self):
        ids = {self.ask()['id'], self.ask(count=9)['id'], self.ask(layout='line')['id'], self.ask(speed=0.5)['id'], self.ask(juice=False)['id']}
        skill_lab_clips.run_queue()
        ids |= {self.ask({'skill.arc.cast': 'chain-lightning/round2/C1'})['id'], self.ask({'skill.arc.cast': 'chain-lightning/round2/C2'})['id']}
        self.assertEqual(len(ids), 7)
        self.assertEqual(skill_lab_clips.request(self.root, self.scene(), None, 'offline', start_worker=False)['way'], 'offline')

    def test_changed_world_marks_old_clip_stale_and_new_id(self):
        j = self.ask()
        skill_lab_clips.run_queue()
        (self.root / 'chapter1/core/combat_core.gd').write_text('# core v2\n', encoding='utf-8')
        st = skill_lab_clips.status(self.root, j['id'])
        self.assertTrue(st['stale'])
        self.assertIn('낡음', st['stale_reason'])
        j2 = self.ask()
        self.assertNotEqual(j2['id'], j['id'])
        self.assertEqual(j2['state'], 'queued')
        skill_lab_clips.run_queue()
        lst = skill_lab_clips.listing(self.root)
        self.assertEqual(sorted(c['stale'] for c in lst['clips']), [False, True])      # 옛 영상은 지워지지 않는다
        self.assertTrue(skill_lab_clips.video_file(self.root, j['id']))

    def test_queue_limit_and_order(self):
        for n in range(1, 6):
            self.ask(count=n)
        with self.assertRaises(skill_lab.LabError) as cm:
            self.ask(count=6)
        self.assertEqual(cm.exception.status, 429)
        skill_lab_clips.run_queue()
        self.assertEqual(len(self.shots), 5)
        self.assertEqual(self.ask(count=6)['state'], 'queued')   # 비면 다시 받는다

    def test_failure_is_state_not_crash_and_retry(self):
        def boom(*a):
            raise RuntimeError('godot 가 없다')
        skill_lab_clips.SHOOT['fn'] = boom
        j = self.ask()
        skill_lab_clips.run_queue()
        st = skill_lab_clips.status(self.root, j['id'])
        self.assertEqual(st['state'], 'error')
        self.assertIn('godot', st['error'])
        self.assertIsNone(skill_lab_clips.video_file(self.root, j['id']))
        skill_lab_clips.SHOOT['fn'] = lambda root, scene, audio, way, cid, out: Path(out).write_bytes(b'y' * 10) and None
        r = skill_lab_clips.retry(self.root, j['id'], start_worker=False)
        skill_lab_clips.run_queue()
        self.assertEqual(skill_lab_clips.status(self.root, r['id'])['state'], 'done')

    def test_prune_oldest_first(self):
        import os
        ids = []
        for n in (1, 2, 3):
            ids.append(self.ask(count=n)['id'])
        skill_lab_clips.run_queue()
        for i, cid in enumerate(ids):
            os.utime(skill_lab_clips._video_path(self.root, cid), (1000 + i, 1000 + i))
        skill_lab_clips.MAX_BYTES = 2500
        removed = skill_lab_clips.prune(self.root)
        self.assertEqual(removed, [ids[0]])
        self.assertIsNone(skill_lab_clips.video_file(self.root, ids[0]))
        self.assertFalse(skill_lab_clips._meta_path(self.root, ids[0]).exists())

    def test_ids_only(self):
        for bad in ('../x', 'A' * 24, 'a' * 23, None, 'a' * 24):
            self.assertIsNone(skill_lab_clips.video_file(self.root, bad))
            self.assertIsNone(skill_lab_clips.status(self.root, bad))
        with self.assertRaises(ValueError):
            skill_lab_clips.request(self.root, self.scene(), None, 'bogus', start_worker=False)

    def fake_godot_and_ffmpeg(self, crashes=0):
        calls = {'godot': [], 'ffmpeg': []}
        real_run = subprocess.run

        def run(args, **kw):
            if len(args) > 1 and str(args[1]).endswith('godot.py'):
                calls['godot'].append(args)
                if len(calls['godot']) <= crashes:
                    return subprocess.CompletedProcess(args, 4294967295, b'', b'error(-1): no debug info in PE/COFF executable\n')
                avi = Path(self.root) / args[args.index('--write-movie') + 1]
                avi.write_bytes(b'avi')
                lab = Path(self.root) / [a for a in args if a.startswith('--lab-dir=')][0][len('--lab-dir='):]
                lab.mkdir(parents=True, exist_ok=True)
                (lab / 'state.json').write_text(json.dumps({'clip': {'start_frame': 30, 'start_time_s': 0.5, 'frames': 270, 'seconds': 4.0, 'done': True}}), encoding='utf-8')
                return subprocess.CompletedProcess(args, 0, b'SKILL_LAB_QUIT\n', b'')
            calls['ffmpeg'].append(args)
            Path(args[-1]).write_bytes(b'mp4')
            return subprocess.CompletedProcess(args, 0, b'', b'')
        return calls, run, real_run

    def test_real_shoot_command_and_ffmpeg_use_the_window_start_time(self):
        skill_lab_clips.SHOOT['fn'] = self.real
        (self.root / 'chapter1/tests').mkdir(parents=True)
        (self.root / 'chapter1/tests/skill_lab.gd').write_text('# fake\n', encoding='utf-8')
        calls, run, real_run = self.fake_godot_and_ffmpeg()
        old = skill_lab_clips._ffmpeg
        skill_lab_clips._ffmpeg = lambda: 'ffmpeg'
        skill_lab_clips.subprocess.run = run
        try:
            j = self.ask()
            skill_lab_clips.run_queue()
        finally:
            skill_lab_clips.subprocess.run = real_run
            skill_lab_clips._ffmpeg = old
        st = skill_lab_clips.status(self.root, j['id'])
        self.assertEqual(st['state'], 'done', st)
        g = calls['godot'][0]
        self.assertEqual(g[g.index('--position') + 1], '4000,4000')                  # 화면 밖(Movie Maker 는 창이 필요하다)
        self.assertIn('--write-movie', g)
        self.assertNotIn('--headless', g)
        self.assertIn('--lab-clip-seconds=4', g)
        self.assertTrue(any(a.startswith('--lab-dir=_local/skill-lab/clips/tmp/lab-') for a in g))
        f = calls['ffmpeg'][0]
        self.assertEqual(f[f.index('-ss') + 1], '0.500')                               # 창이 state.json 에 쓴 start_time_s
        self.assertEqual(f[f.index('-t') + 1], '4')
        self.assertIn('libx264', f)
        self.assertIn('aac', f)
        meta = skill_lab_clips.read_meta(self.root, j['id'])
        self.assertEqual((meta['start_frame'], meta['attempts']), (30, 1))
        self.assertFalse((skill_lab_clips.clips_dir(self.root) / 'tmp' / ('lab-' + j['id'])).exists())     # 찌꺼기를 치운다

    def test_real_shoot_retries_one_crash_and_keeps_the_log(self):
        skill_lab_clips.SHOOT['fn'] = self.real
        (self.root / 'chapter1/tests').mkdir(parents=True)
        (self.root / 'chapter1/tests/skill_lab.gd').write_text('# fake\n', encoding='utf-8')
        calls, run, real_run = self.fake_godot_and_ffmpeg(crashes=1)
        old = skill_lab_clips._ffmpeg
        skill_lab_clips._ffmpeg = lambda: 'ffmpeg'
        skill_lab_clips.subprocess.run = run
        try:
            j = self.ask()
            skill_lab_clips.run_queue()
        finally:
            skill_lab_clips.subprocess.run = real_run
            skill_lab_clips._ffmpeg = old
        self.assertEqual(len(calls['godot']), 2)
        self.assertEqual(skill_lab_clips.read_meta(self.root, j['id'])['attempts'], 2)
        self.assertIn('PE/COFF', (skill_lab_clips.clips_dir(self.root) / 'last-crash.log').read_text(encoding='utf-8'))

    def test_two_crashes_are_an_error_with_the_reason(self):
        skill_lab_clips.SHOOT['fn'] = self.real
        (self.root / 'chapter1/tests').mkdir(parents=True)
        (self.root / 'chapter1/tests/skill_lab.gd').write_text('# fake\n', encoding='utf-8')
        calls, run, real_run = self.fake_godot_and_ffmpeg(crashes=5)
        old = skill_lab_clips._ffmpeg
        skill_lab_clips._ffmpeg = lambda: 'ffmpeg'
        skill_lab_clips.subprocess.run = run
        try:
            j = self.ask()
            skill_lab_clips.run_queue()
        finally:
            skill_lab_clips.subprocess.run = real_run
            skill_lab_clips._ffmpeg = old
        st = skill_lab_clips.status(self.root, j['id'])
        self.assertEqual(len(calls['godot']), 2)
        self.assertEqual(st['state'], 'error')
        self.assertIn('4294967295', st['error'])
        self.assertIn('last-shoot.log', st['error'])

    def test_waiting_info_counts_jobs_ahead_and_uses_measured_time(self):
        a, b = self.ask(count=1), self.ask(count=2)
        self.assertEqual(skill_lab_clips.status(self.root, b['id'])['ahead'], 1)
        self.assertIsNone(skill_lab_clips.status(self.root, b['id'])['eta_s'])           # 잰 값이 없으면 숫자를 지어내지 않는다
        skill_lab_clips.run_queue()
        c, d = self.ask(count=3), self.ask(count=4)
        skill_lab_clips._JOBS[c['id']]['queued'] -= 5
        for cid in (a['id'], b['id']):
            m = skill_lab_clips.read_meta(self.root, cid)
            m['seconds'] = 20.0
            skill_lab_clips._meta_path(self.root, cid).write_text(json.dumps(m), encoding='utf-8')
        st = skill_lab_clips.status(self.root, d['id'])
        self.assertEqual((st['ahead'], st['typical_s'], st['eta_s']), (1, 20.0, 40.0))

    def test_real_shoot_reports_missing_script_instead_of_crashing(self):
        skill_lab_clips.SHOOT['fn'] = self.real
        j = self.ask()
        skill_lab_clips.run_queue()
        st = skill_lab_clips.status(self.root, j['id'])
        self.assertEqual(st['state'], 'error')
        self.assertIn('skill_lab.gd', st['error'])


class ServerTests(Base):
    def setUp(self):
        super().setUp()
        self.orig_root = server.ROOT
        server.ROOT = self.root
        self.httpd = server.make_server(0)
        self.port = self.httpd.server_port
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        server.ROOT = self.orig_root
        super().tearDown()

    def req(self, path, body=None, headers=None, method=None):
        h = {'Host': '127.0.0.1:%d' % self.port}
        data = None
        if body is not None:
            data = json.dumps(body).encode('utf-8')
            h['Content-Type'] = 'application/json'
            h['Origin'] = 'http://127.0.0.1:%d' % self.port
        h.update(headers or {})
        r = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path), data=data, headers=h, method=method)
        try:
            with urllib.request.urlopen(r) as resp:
                return resp.status, resp.headers, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read()

    def test_overview_and_audio_by_id(self):
        st, _, body = self.req('/api/skill-lab')
        d = json.loads(body)
        self.assertEqual(st, 200)
        self.assertEqual(len(d['characters']), 3)
        self.assertEqual(len(d['candidates']), 2)
        self.assertEqual(d['map_rev'], skill_lab.map_info(self.root)['rev'])
        st, h, data = self.req('/api/skill-lab/audio?id=chain-lightning/round2/C1&n=0')
        self.assertEqual((st, h['Content-Type']), (200, 'audio/wav'))
        self.assertEqual(data[:4], b'RIFF')
        st, h, data = self.req('/api/skill-lab/audio?id=chain-lightning/round2/C1&n=1', headers={'Range': 'bytes=0-9'})
        self.assertEqual((st, len(data)), (206, 10))
        for path in ('/api/skill-lab/audio?id=../../chapter1/data/audio_map.json&n=0', '/api/skill-lab/audio?path=chapter1/data/audio_map.json',
                     '/api/skill-lab/audio?id=chain-lightning/round2/C1&n=9', '/api/skill-lab/audio'):
            self.assertEqual(self.req(path)[0], 404, path)

    def test_portrait_registered_only(self):
        self.assertEqual(self.req('/api/skill-lab/portrait?id=ember')[0], 200)
        self.assertEqual(self.req('/api/skill-lab/portrait?id=arc')[0], 404)
        self.assertEqual(self.req('/api/skill-lab/portrait?id=../x')[0], 404)

    def test_untrusted_host_and_origin_refused(self):
        self.assertEqual(self.req('/api/skill-lab', headers={'Host': 'evil.example'})[0], 403)
        for path in ('scene', 'adopt', 'clip', 'open'):
            self.assertEqual(self.req('/api/skill-lab/' + path, {}, {'Origin': 'http://evil.example'})[0], 403, path)
            self.assertEqual(self.req('/api/skill-lab/' + path, {}, {'Host': 'evil.example'})[0], 403, path)
        self.assertFalse((skill_lab.lab_dir(self.root) / 'command.json').exists())

    def test_scene_post_writes_command(self):
        st, _, body = self.req('/api/skill-lab/scene', {'scene': self.scene(), 'audio': {}})
        self.assertEqual(st, 200)
        self.assertEqual(self.command()['seq'], json.loads(body)['seq'])
        self.assertEqual(self.req('/api/skill-lab/scene', {'scene': self.scene(count=99)})[0], 400)
        self.assertEqual(self.req('/api/skill-lab/nothing', {})[0], 404)

    def test_open_without_script_is_404_with_reason(self):
        st, _, body = self.req('/api/skill-lab/open', {'scene': self.scene()})
        self.assertEqual(st, 404)
        self.assertIn('skill_lab.gd', json.loads(body)['error'])

    def test_adopt_conflict_and_disabled(self):
        st, _, body = self.req('/api/skill-lab/adopt', {'slot': 'skill.arc.cast', 'candidate': 'chain-lightning/round2/C1', 'map_rev': 'x'})
        self.assertEqual(st, 503)             # 채택 도구가 이 가짜 저장소에 없다
        (self.root / 'tools/dev').mkdir(parents=True)
        (self.root / 'tools/dev/audio_adopt.py').write_text('# fake\n', encoding='utf-8')
        st, _, body = self.req('/api/skill-lab/adopt', {'slot': 'skill.arc.cast', 'candidate': 'chain-lightning/round2/C1', 'map_rev': 'stale'})
        self.assertEqual(st, 409)
        self.assertEqual(json.loads(body)['map_rev'], skill_lab.map_info(self.root)['rev'])

    def test_adopt_preview_route(self):
        st, _, body = self.req('/api/skill-lab/adopt-preview', {'slot': 'skill.arc.cast', 'candidate': 'chain-lightning/round2/C1'})
        self.assertEqual(st, 503)             # 채택 도구가 이 가짜 저장소에 없다
        (self.root / 'tools/dev').mkdir(parents=True)
        (self.root / 'tools/dev/audio_adopt.py').write_text('# fake\n', encoding='utf-8')
        st, _, body = self.req('/api/skill-lab/adopt-preview', {'slot': 'skill.arc.cast', 'candidate': 'nope'})
        self.assertEqual(st, 400)
        st, _, body = self.req('/api/skill-lab/adopt-preview', {'slot': 'skill.arc.cast', 'candidate': 'chain-lightning/round2/C1'}, headers={'Origin': 'http://evil.example'})
        self.assertEqual(st, 403)

    def test_clip_routes_and_range(self):
        def fake(root, scene, audio, way, cid, out):
            Path(out).write_bytes(bytes(range(200)))
        real = skill_lab_clips.SHOOT['fn']
        skill_lab_clips.SHOOT['fn'] = fake
        skill_lab_clips._JOBS.clear()
        try:
            st, _, body = self.req('/api/skill-lab/clip', {'scene': self.scene(), 'audio': {}, 'way': 'movie'})
            self.assertEqual(st, 200)
            cid = json.loads(body)['id']
            for _ in range(50):
                st, _, body = self.req('/api/skill-lab/clip/' + cid)
                if json.loads(body)['state'] == 'done':
                    break
                time.sleep(0.1)
            self.assertEqual(json.loads(body)['state'], 'done')
            st, h, data = self.req('/api/skill-lab/clip/%s/video' % cid, headers={'Range': 'bytes=10-19'})
            self.assertEqual((st, h['Content-Type'], data, h['Content-Range']), (206, 'video/mp4', bytes(range(10, 20)), 'bytes 10-19/200'))
            self.assertEqual(self.req('/api/skill-lab/clip/%s/video' % cid)[0], 200)
            self.assertEqual(self.req('/api/skill-lab/clip/' + 'f' * 24 + '/video')[0], 404)
            self.assertEqual(self.req('/api/skill-lab/clips')[0], 200)
        finally:
            skill_lab_clips.SHOOT['fn'] = real
            skill_lab_clips._JOBS.clear()


if __name__ == '__main__':
    unittest.main()
