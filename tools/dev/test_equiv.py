#!/usr/bin/env python3
"""equiv.py 비교 함수의 자체 검사. Godot도 git도 쓰지 않는다(가짜 덤프만).

  python tools/dev/test_equiv.py

덤프를 만들고 돌리는 쪽(기준 커밋 꺼내기, 헤드리스 실행)은 실제로 한 번 돌려 확인한다. 이 검사는 비교 규칙만 본다.
"""
import copy
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import equiv as E  # noqa: E402

VOL = E.load_volatile()


def hud_row(d, cls, name, **kw):
    r = {'d': d, 'class': cls, 'name': name, 'visible': True, 'x': 0.0, 'y': 0.0, 'w': 10.0, 'h': 10.0, 'modulate': 'ffffffff', 'tooltip': ''}
    r.update(kw)
    return r


def hud_doc(rows_by_label):
    return {'order': list(rows_by_label), 'dumps': rows_by_label}


def scene_doc(rows_by_label):
    return {'order': list(rows_by_label), 'scenes': rows_by_label}


def node(d, cls, name, **kw):
    r = {'d': d, 'class': cls, 'name': name, 'visible': True, 't': [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]]}
    r.update(kw)
    return r


class Rows(unittest.TestCase):
    def test_identical_has_no_diffs(self):
        a = hud_doc({'menu': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'Title', text='a')]})
        self.assertEqual(E.compare_moments('hud', a, copy.deepcopy(a), VOL), [])

    def test_field_difference_names_moment_node_and_field(self):
        a = hud_doc({'menu': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'Title', text='a')]})
        b = copy.deepcopy(a)
        b['dumps']['menu'][1]['text'] = 'b'
        diffs = E.compare_moments('hud', a, b, VOL)
        self.assertEqual(len(diffs), 1)
        path, x, y = diffs[0]
        self.assertEqual(path, 'hud/menu/Label:Title#1/text')
        self.assertEqual((x, y), ('a', 'b'))

    def test_anonymous_names_compare_by_class(self):
        a = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', '@Label@123')]})
        b = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', '@Label@987')]})
        self.assertEqual(E.compare_moments('hud', a, b, VOL), [])

    def test_inserted_and_missing_rows_are_listed(self):
        a = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'A')]})
        b = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'A'), hud_row(1, 'Button', 'New')]})
        diffs = E.compare_moments('hud', a, b, VOL)
        self.assertEqual([(p, x, y) for p, x, y in diffs], [('hud/m/Button:New#2', '없음', '있음(깊이 1)')])

    def test_hidden_rows_do_not_count_unless_strict(self):
        a = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'Hid', visible=False, x=1.0)]})
        b = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'Hid', visible=False, x=99.0)]})
        self.assertEqual(E.compare_moments('hud', a, b, VOL), [])
        self.assertEqual(len(E.compare_moments('hud', a, b, VOL, strict_hidden=True)), 1)

    def test_becoming_hidden_is_a_difference(self):
        a = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'X')]})
        b = hud_doc({'m': [hud_row(0, 'Control', 'Root'), hud_row(1, 'Label', 'X', visible=False)]})
        self.assertEqual(len(E.compare_moments('hud', a, b, VOL)), 1)

    def test_moment_lists_must_match(self):
        a, b = hud_doc({'menu': []}), hud_doc({'menu': [], 'stash': []})
        self.assertEqual(E.compare_moments('hud', a, b, VOL)[0][0], 'hud/moments')

    def test_scene_nested_values_get_a_path(self):
        a = scene_doc({'t': [node(0, 'Node3D', 'W'), node(1, 'DirectionalLight3D', 'Moon', color='ffeedd', energy=1.0)]})
        b = copy.deepcopy(a)
        b['scenes']['t'][1]['color'] = 'ffeeee'
        b['scenes']['t'][0]['t'][0][2] = 0.5
        paths = sorted(p for p, _, _ in E.compare_moments('scene', a, b, VOL))
        self.assertEqual(paths, ['scene/t/DirectionalLight3D:Moon#1/color', 'scene/t/Node3D:W#0/t[0][2]'])

    def test_deep_diff_limit(self):
        out = []
        E.deep_diff(list(range(100)), [x + 1 for x in range(100)], 'v', out, limit=5)
        self.assertEqual(len(out), 5)


class Eq(unittest.TestCase):
    def snapshot(self, label, tick, parts, info=None):
        return {'label': label, 'tick': tick, 'mode': 'playing', 'hash': 'h' + ''.join(sorted(parts.values())), 'parts': parts,
                'info': info or {'actors': 1, 'mm_visible_instances': 5, 'mm_nonidentity_transforms': 0}}

    def test_part_difference_drills_into_full_dump(self):
        a = {'snapshots': [self.snapshot('t600', 600, {'a:7:base': 'x1', 'a:7:bones': 'b1'})]}
        b = {'snapshots': [self.snapshot('t600', 600, {'a:7:base': 'x2', 'a:7:bones': 'b1'})]}
        fa = {'t600': {'a:7': {'base': {'t': [1, 2, 3], 'vis': True}, 'bones': [], 'meshes': []}}}
        fb = {'t600': {'a:7': {'base': {'t': [1, 2, 4], 'vis': True}, 'bones': [], 'meshes': []}}}
        diffs = E.compare_eq(a, b, fa, fb, VOL)
        self.assertEqual(diffs, [('eq/t600/a:7:base/base.t[2]', '3', '4')])

    def test_missing_actor_and_tick_and_info(self):
        a = {'snapshots': [self.snapshot('t600', 600, {'a:7:base': 'x'}, {'actors': 1})]}
        b = {'snapshots': [self.snapshot('t600', 601, {}, {'actors': 0})]}
        paths = [p for p, _, _ in E.compare_eq(a, b, None, None, VOL)]
        self.assertIn('eq/t600/tick', paths)
        self.assertIn('eq/t600/info.actors', paths)
        self.assertIn('eq/t600/a:7:base', paths)

    def test_equal_snapshots(self):
        a = {'snapshots': [self.snapshot('t600', 600, {'hero:base': 'q'})]}
        self.assertEqual(E.compare_eq(a, copy.deepcopy(a), None, None, VOL), [])

    def test_hero_and_effect_parts(self):
        a = {'snapshots': [self.snapshot('t1', 1, {'hero:base': 'a', 'fx:ring': 'f1'})]}
        b = {'snapshots': [self.snapshot('t1', 1, {'hero:base': 'b', 'fx:ring': 'f2'})]}
        fa = {'t1': {'hero': {'t': [0], 'staff': [0], 'anim': ['idle', 0.0], 'fade': 1.0}, 'fx:ring': {'vis': True, 'shown': 3}}}
        fb = {'t1': {'hero': {'t': [0], 'staff': [0], 'anim': ['idle', 0.1], 'fade': 1.0}, 'fx:ring': {'vis': True, 'shown': 4}}}
        paths = sorted(p for p, _, _ in E.compare_eq(a, b, fa, fb, VOL))
        self.assertEqual(paths, ['eq/t1/fx:ring/.shown', 'eq/t1/hero:base/anim[1]'])

    def test_mm_note_is_observed(self):
        doc = {'snapshots': [self.snapshot('t', 1, {}, {'mm_visible_instances': 12, 'mm_nonidentity_transforms': 0})]}
        self.assertIn('모두 단위 행렬', E.mm_note(doc))
        doc = {'snapshots': [self.snapshot('t', 1, {}, {'mm_visible_instances': 12, 'mm_nonidentity_transforms': 3})]}
        self.assertIn('값이 읽혔다', E.mm_note(doc))


class Volatile(unittest.TestCase):
    def test_rules_skip_and_count(self):
        vol = {'ignore': [{'name': 'clock', 'match': r'/Label:Clock#\d+/text$', 'why': 'shows wall time'}]}
        diffs = [('hud/m/Label:Clock#3/text', '1', '2'), ('hud/m/Label:Title#1/text', 'a', 'b')]
        kept, ignored = E.apply_volatile(diffs, vol)
        self.assertEqual(kept, [diffs[1]])
        self.assertEqual(ignored, {'clock': 1})

    def test_shipped_rules_are_explained(self):
        for rule in VOL.get('ignore', []):
            self.assertTrue(rule.get('why'), rule)
        self.assertTrue(VOL['normalize_names']['why'])

    def test_first_line_lists_what_is_not_compared(self):
        text = '; '.join(E.NOT_COMPARED)
        for word in ('MultiMesh', '셰이더', '그림자', '픽셀'):
            self.assertIn(word, text)


if __name__ == '__main__':
    unittest.main(verbosity=1)
