#!/usr/bin/env python3
"""screen_contract_check.py 자체 검사. 임시 폴더에 가짜 스키마·픽스처·화면·어댑터를 만들어 실패 종류마다 하나씩 잡히는지 본다.
진짜 저장소 파일에는 기대지 않는다(다른 담당이 작업 중인 파일에 흔들리지 않게).

  python tools/dev/test_screen_contract_check.py
"""
import contextlib
import copy
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import screen_contract_check as C  # noqa: E402

SCHEMA = {
    'screen': 'demo', 'contract_version': 2,
    'fields': {
        'title': {'type': 'string', 'max_len': 10},
        'count': {'type': 'int', 'min': 0, 'max': 4},
        'ratio': {'type': 'float', 'min': 0, 'max': 1},
        'on': {'type': 'bool'},
        'element': {'type': 'enum', 'values': ['ember', 'frost']},
        'cards': {'type': 'array', 'min': 1, 'max': 2, 'item': {'type': 'object', 'fields': {'name': {'type': 'string'}, 'note': {'type': 'string', 'optional': True}}}},
        'rerolls': {'type': 'int', 'min': 0, 'requested': 'ledger S-7'},
        'extra': {'type': 'string', 'nullable': True, 'optional': True},
    },
    'variants': ['normal', 'long'],
    'signals': ['chosen(card_ref)', 'closed()'],
}
FIXTURE = {'screen': 'demo', 'contract_version': 2, 'title': 'Hello', 'count': 2, 'ratio': 0.5, 'on': True, 'element': 'frost',
           'cards': [{'name': 'a'}, {'name': 'b', 'note': 'n'}], 'rerolls': 3}
SCREEN = 'extends Control\nconst CONTRACT_VERSION := 2\nsignal chosen(card_ref: String)\nsignal closed\nfunc apply(contract: Dictionary) -> void:\n\tpass\n'
ADAPTER = 'extends RefCounted\nconst CONTRACT_VERSION := 2\nstatic func build(run: RefCounted, app_state: Dictionary = {}) -> Dictionary:\n\tvar offer = run.get_offer()\n\treturn {"screen": "demo"}\n'


def write(root, rel, content):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content if isinstance(content, str) else json.dumps(content), encoding='utf-8', newline='\n')


def make_tree(root, schema=None, fixtures=None, screen=SCREEN, adapter=ADAPTER, baseline=None):
    schema = SCHEMA if schema is None else schema
    write(root, 'chapter1/tests/contracts/demo.contract.json', schema)
    for variant in (fixtures if fixtures is not None else {'normal': FIXTURE, 'long': FIXTURE}):
        write(root, 'chapter1/tests/fixtures/contracts/demo.%s.json' % variant, (fixtures or {'normal': FIXTURE, 'long': FIXTURE})[variant])
    if screen is not None:
        write(root, 'chapter1/view/hud/screens/demo.gd', screen)
    if adapter is not None:
        write(root, 'chapter1/view/contracts/demo_contract.gd', adapter)
    if baseline is not None:
        write(root, 'tools/dev/screen_contract_baseline.json', {'files': baseline})


def check(root, **kwargs):
    return C.run(root, **kwargs)


def mutated(**changes):
    doc = copy.deepcopy(FIXTURE)
    for key, value in changes.items():
        if value is KeyError:
            doc.pop(key, None)
        else:
            doc[key] = value
    return doc


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def has(self, result, *words):
        text = '\n'.join(result['failures'])
        for word in words:
            self.assertIn(word, text, text)

    def assertClean(self, result):
        self.assertEqual(result['failures'], [], '\n'.join(result['failures']))


class PassingTests(Base):
    def test_a_complete_valid_tree_passes(self):
        make_tree(self.root)
        result = check(self.root)
        self.assertClean(result)
        self.assertEqual((result['screens'], result['fixtures'], result['dumps']), (1, 2, 0))

    def test_empty_tree_passes_with_zero_screens(self):
        result = check(self.root)
        self.assertClean(result)
        self.assertEqual((result['screens'], result['fixtures']), (0, 0))

    def test_schema_without_screen_or_adapter_is_a_note_not_a_failure(self):
        make_tree(self.root, screen=None, adapter=None)
        result = check(self.root)
        self.assertClean(result)
        self.assertEqual(len([n for n in result['notes'] if 'no screen file yet' in n or 'no adapter file yet' in n]), 2)

    def test_schema_in_view_contracts_is_read_too(self):
        make_tree(self.root)
        (self.root / 'chapter1/tests/contracts/demo.contract.json').rename(self.root / 'chapter1/tests/contracts/moved')
        write(self.root, 'chapter1/view/contracts/demo.contract.json', SCHEMA)
        self.assertClean(check(self.root))

    def test_fixtures_in_the_ui_folder_count_only_with_a_screen_key(self):
        make_tree(self.root, fixtures={'normal': FIXTURE})
        write(self.root, 'chapter1/tests/fixtures/ui/demo.long.json', FIXTURE)  # a contract in the older place
        write(self.root, 'chapter1/tests/fixtures/ui/demo.seed.json', {'scene': 'demo', 'give': []})  # a core-state seed: ignored
        result = check(self.root)
        self.assertClean(result)
        self.assertEqual(result['fixtures'], 2)

    def test_the_same_fixture_in_both_places_fails(self):
        make_tree(self.root)
        write(self.root, 'chapter1/tests/fixtures/ui/demo.long.json', FIXTURE)
        self.has(check(self.root), 'exists in', 'too')


class SchemaTests(Base):
    def test_bad_schema_shapes(self):
        cases = {
            'unknown type': dict(SCHEMA, fields={'a': {'type': 'color'}}),
            'unknown key': dict(SCHEMA, fields={'a': {'type': 'string', 'maxlen': 3}}),
            'enum without values': dict(SCHEMA, fields={'a': {'type': 'enum'}}),
            'array without item': dict(SCHEMA, fields={'a': {'type': 'array'}}),
            'object without fields': dict(SCHEMA, fields={'a': {'type': 'object'}}),
            'bad version': dict(SCHEMA, contract_version=0),
            'top level key': dict(SCHEMA, colors=1),
            'variant twice': dict(SCHEMA, variants=['normal', 'normal']),
            'optional not bool': dict(SCHEMA, fields={'a': {'type': 'bool', 'optional': 'yes'}}),
        }
        for name, schema in cases.items():
            with tempfile.TemporaryDirectory() as d:
                write(d, 'chapter1/tests/contracts/demo.contract.json', schema)
                self.assertTrue(check(d)['failures'], name)

    def test_comment_keys_are_allowed(self):
        make_tree(self.root, schema=dict(SCHEMA, _note='x'))
        self.assertClean(check(self.root))

    def test_file_name_must_match_the_screen_id(self):
        make_tree(self.root)
        write(self.root, 'chapter1/tests/contracts/other.contract.json', SCHEMA)
        self.has(check(self.root), "named for 'other'")


class FixtureTests(Base):
    def run_with(self, doc):
        make_tree(self.root, fixtures={'normal': doc, 'long': FIXTURE})
        return check(self.root)

    def test_each_kind_of_violation_is_caught(self):
        cases = [
            ('wrong type', mutated(count='2'), 'expected an integer'),
            ('bool is not an int', mutated(count=True), 'expected an integer'),
            ('above max', mutated(count=9), 'above the maximum'),
            ('below min', mutated(ratio=-0.1), 'below the minimum'),
            ('too long', mutated(title='x' * 11), '11 characters'),
            ('bad enum', mutated(element='fire'), 'is not one of'),
            ('array too long', mutated(cards=[{'name': 'a'}] * 3), 'at most'),
            ('array too short', mutated(cards=[]), 'at least'),
            ('bad item', mutated(cards=[{'name': 1}]), 'expected a string'),
            ('unknown key in an item', mutated(cards=[{'name': 'a', 'zzz': 1}]), 'unknown key'),
            ('unknown top key', mutated(color='red'), 'unknown key'),
            ('missing required', mutated(title=KeyError), 'required field is missing'),
            ('missing requested field', mutated(rerolls=KeyError), 'requested field must be in the fixture'),
            ('null in a field that is not nullable', mutated(title=None), 'null is not allowed'),
            ('wrong version', mutated(contract_version=1), 'contract_version'),
            ('wrong screen', mutated(screen='other'), '"screen" is'),
            ('float where int', mutated(count=1.5), 'expected an integer'),
            ('string where bool', mutated(on='true'), 'expected true or false'),
        ]
        for name, doc, word in cases:
            with self.subTest(name):
                with tempfile.TemporaryDirectory() as d:
                    make_tree(d, fixtures={'normal': doc, 'long': FIXTURE})
                    self.has(check(d), word)

    def test_optional_and_nullable_may_be_missing_or_null(self):
        self.assertClean(self.run_with(mutated(extra=None)))
        self.assertClean(self.run_with(mutated(extra='x')))
        self.assertClean(self.run_with(mutated(ratio=1)))  # an integer is a number

    def test_a_listed_variant_without_a_file_fails(self):
        make_tree(self.root, fixtures={'normal': FIXTURE})
        self.has(check(self.root), "variant 'long' has no fixture file")

    def test_an_unlisted_variant_is_a_note(self):
        make_tree(self.root, fixtures={'normal': FIXTURE, 'long': FIXTURE, 'odd': FIXTURE})
        result = check(self.root)
        self.assertClean(result)
        self.assertTrue(any("'odd'" in n for n in result['notes']))

    def test_a_fixture_for_a_screen_without_a_schema_is_a_counted_note(self):
        write(self.root, 'chapter1/tests/fixtures/contracts/ghost.normal.json', {'screen': 'ghost', 'contract_version': 1})
        write(self.root, 'chapter1/tests/fixtures/ui/ghost.long.json', {'screen': 'ghost', 'contract_version': 1})
        result = check(self.root)
        self.assertClean(result)  # a design in progress is not a failure, but it is not checked either, and the result says so
        self.assertEqual((result['fixtures'], result['unchecked_fixtures']), (0, 2))
        self.assertTrue(any("no schema for the screen 'ghost'" in n for n in result['notes']))

    def test_unreadable_json_fails(self):
        make_tree(self.root)
        write(self.root, 'chapter1/tests/fixtures/contracts/demo.normal.json', '{not json')
        self.has(check(self.root), 'cannot read')


class VersionAndSignalTests(Base):
    def test_screen_adapter_and_fixture_versions_must_match_the_schema(self):
        make_tree(self.root, screen=SCREEN.replace(':= 2', ':= 1'), adapter=ADAPTER.replace(':= 2', ':= 3'))
        self.has(check(self.root), 'screens/demo.gd: CONTRACT_VERSION 1', 'demo_contract.gd: CONTRACT_VERSION 3')

    def test_missing_version_constant_fails(self):
        make_tree(self.root, screen=SCREEN.replace('const CONTRACT_VERSION := 2\n', ''))
        self.has(check(self.root), 'no "const CONTRACT_VERSION')

    def test_typed_and_plain_constant_forms_are_read(self):
        for form in ('const CONTRACT_VERSION = 2', 'const CONTRACT_VERSION: int = 2', 'const CONTRACT_VERSION := 2'):
            with tempfile.TemporaryDirectory() as d:
                make_tree(d, screen=SCREEN.replace('const CONTRACT_VERSION := 2', form))
                self.assertClean(check(d))

    def test_signal_names_must_match(self):
        make_tree(self.root, screen=SCREEN.replace('signal closed\n', 'signal other_thing\n'))
        self.has(check(self.root), 'signals')

    def test_a_missing_signal_fails(self):
        make_tree(self.root, screen=SCREEN.replace('signal closed\n', ''))
        self.has(check(self.root), 'signals')

    def test_a_screen_file_without_a_schema_fails(self):
        write(self.root, 'chapter1/view/hud/screens/loose.gd', 'extends Control\n')
        self.has(check(self.root), 'a screen file without a schema')


class ScreenScanTests(Base):
    def test_each_forbidden_thing_is_counted(self):
        cases = {
            'run': 'func f():\n\tvar x = run.hp\n',
            'growth': 'func f():\n\treturn growth\n',
            'private': 'func f(o):\n\treturn o._secret\n',
            'private after a call': 'func f(o):\n\treturn o.get_x()._secret\n',
            'color': 'func f():\n\treturn Color(1, 0, 0)\n',
            'color string': 'func f():\n\treturn Color("#fff")\n',
            'child': 'func f():\n\treturn get_child(2)\n',
            'preload core': 'const A := preload("res://chapter1/core/combat_core.gd")\n',
            'preload app': 'const A := preload("res://chapter1/app/chapter_one.gd")\n',
        }
        for name, body in cases.items():
            with self.subTest(name):
                with tempfile.TemporaryDirectory() as d:
                    make_tree(d, screen=SCREEN + body)
                    result = check(d)
                    self.assertTrue(any('baseline 0' in f for f in result['failures']), (name, result['failures']))

    def test_comments_strings_and_own_privates_are_not_counted(self):
        body = ('# run growth Color(1,1,1) o._x get_child(0)\n'
                'func f():\n\tvar s = "run the growth Color(0) o._x"\n\tself._own = 1\n\tsuper._ready()\n\tvar t = get_child(i)\n\tvar r = run_speed + running\n'
                '\tvar n = 3 # run.hp here\n\tvar c = Palette.GOLD\n')
        make_tree(self.root, screen=SCREEN + body)
        self.assertClean(check(self.root))

    def test_triple_quoted_text_is_not_counted(self):
        make_tree(self.root, screen=SCREEN + 'const DOC := """\nrun Color(1,1,1)\n"""\nfunc g():\n\tpass\n')
        self.assertClean(check(self.root))

    def test_baseline_allows_up_to_the_count_and_fails_above(self):
        body = 'func f():\n\tvar a = Color(1,0,0)\n\tvar b = Color(0,1,0)\n'
        make_tree(self.root, screen=SCREEN + body, baseline={'chapter1/view/hud/screens/demo.gd': {'color': 2}})
        self.assertClean(check(self.root))
        make_tree(self.root, screen=SCREEN + body + '\tvar c = Color(0,0,1)\n', baseline={'chapter1/view/hud/screens/demo.gd': {'color': 2}})
        self.has(check(self.root), 'color 3, baseline 2')

    def test_below_the_baseline_is_a_note(self):
        make_tree(self.root, baseline={'chapter1/view/hud/screens/demo.gd': {'color': 2}})
        result = check(self.root)
        self.assertClean(result)
        self.assertTrue(any('below the baseline' in n for n in result['notes']))

    def test_a_file_outside_the_screens_folder_can_be_watched_through_the_baseline(self):
        write(self.root, 'chapter1/view/hud/old_hud.gd', 'func f():\n\treturn Color(1,1,1)\n')
        write(self.root, 'tools/dev/screen_contract_baseline.json', {'files': {'chapter1/view/hud/old_hud.gd': {'color': 1}}})
        self.assertClean(check(self.root))
        write(self.root, 'chapter1/view/hud/old_hud.gd', 'func f():\n\treturn [Color(1,1,1), Color(0,0,0)]\n')
        self.has(check(self.root), 'old_hud.gd: color 2, baseline 1')

    def test_update_baseline_writes_the_current_counts(self):
        make_tree(self.root, screen=SCREEN + 'func f():\n\tvar a = Color(1,0,0)\n')
        self.assertTrue(check(self.root)['failures'])
        result = check(self.root, update_baseline=True)
        self.assertClean(result)
        saved = json.loads((self.root / 'tools/dev/screen_contract_baseline.json').read_text(encoding='utf-8'))
        self.assertEqual(saved['files'], {'chapter1/view/hud/screens/demo.gd': {'color': 1}})
        self.assertClean(check(self.root))


class AdapterScanTests(Base):
    def test_writes_and_mutating_calls_are_caught(self):
        cases = {
            'assign': '\trun.hp = 5\n',
            'plus assign': '\trun.growth.count += 1\n',
            'index assign': '\trun.slots[0] = 1\n',
            'choose': '\trun.choose(2)\n',
            'step': '\trun.core.step()\n',
            'set_': '\trun.set_seed(1)\n',
            'import_': '\trun.import_state(a)\n',
            'configure_': '\trun.configure_run(a)\n',
            'equip': '\trun.equip(i)\n',
        }
        for name, line in cases.items():
            with self.subTest(name):
                with tempfile.TemporaryDirectory() as d:
                    make_tree(d, adapter=ADAPTER + line)
                    self.assertTrue(check(d)['failures'], name)

    def test_reads_and_comparisons_are_fine(self):
        make_tree(self.root, adapter=ADAPTER + '\tvar a = run.hp\n\tif run.level == 3 and run.hp >= 1 and run.hp != 2:\n\t\tpass\n\t# run.choose(1)\n')
        self.assertClean(check(self.root))

    def test_get_offer_at_most_once(self):
        make_tree(self.root, adapter=ADAPTER + '\tvar again = run.get_offer()\n')
        self.has(check(self.root), 'get_offer( is called 2 times')


class DumpTests(Base):
    def dumps(self, docs):
        folder = self.root / 'dumps'
        for name, doc in docs.items():
            write(folder, name, doc)
        return folder

    def test_adapter_output_following_the_schema_passes_and_requested_may_be_missing(self):
        make_tree(self.root)
        folder = self.dumps({'demo.first.json': mutated(rerolls=KeyError)})
        result = check(self.root, dumps=folder)
        self.assertClean(result)
        self.assertEqual(result['dumps'], 1)

    def test_adapter_output_breaking_the_schema_fails(self):
        make_tree(self.root)
        folder = self.dumps({'demo.first.json': mutated(count=99)})
        self.has(check(self.root, dumps=folder), 'dump demo.first.json', 'above the maximum')

    def test_a_dump_for_an_unknown_screen_fails(self):
        make_tree(self.root)
        folder = self.dumps({'ghost.first.json': {'screen': 'ghost'}})
        self.has(check(self.root, dumps=folder), "no schema for the screen 'ghost'")

    def test_dump_folder_must_exist(self):
        make_tree(self.root)
        self.has(check(self.root, dumps=self.root / 'nothing'), 'is not a folder')


class ContrastTests(Base):
    def layout(self, rows):
        path = self.root / 'layout.json'
        write(self.root, 'layout.json', [{'label': 'moment', 'rows': rows}])
        return [path]

    def row(self, **kwargs):
        base = {'d': 1, 'class': 'Label', 'name': 'Title', 'visible': True, 'text': 'Hello', 'fs': 16, 'alpha': 1.0}
        base.update(kwargs)
        return base

    def test_ratio_values(self):
        black, white = C.parse_hex('000000'), C.parse_hex('ffffff')
        self.assertAlmostEqual(C.contrast_ratio(black, white), 21.0, places=1)
        self.assertAlmostEqual(C.contrast_ratio(white, white), 1.0, places=2)
        self.assertLess(C.contrast_ratio(C.parse_hex('ffffff80'), white), 1.2)  # half transparent white on white

    def test_good_and_bad_contrast(self):
        good = check(self.root, layout_dumps=self.layout([self.row(fc='ffffff', bg='000000')]))
        self.assertClean(good)
        self.assertEqual(good['contrast'], {'rows': 1, 'checked': 1, 'skipped_no_bg': 0})
        bad = check(self.root, layout_dumps=self.layout([self.row(fc='777777', bg='888888')]))
        self.has(bad, 'contrast 1.', 'below 4.5')

    def test_large_text_needs_only_three(self):
        rows = [self.row(fc='949494', bg='ffffff', fs=16, name='Small'), self.row(fc='949494', bg='ffffff', fs=30, name='Big')]
        result = check(self.root, layout_dumps=self.layout(rows))
        self.assertEqual(len(result['failures']), 1)
        self.assertIn('Small', result['failures'][0])

    def test_rows_without_a_background_are_skipped_not_passed(self):
        result = check(self.root, layout_dumps=self.layout([self.row(fc='777777')]))
        self.assertClean(result)
        self.assertEqual((result['contrast']['checked'], result['contrast']['skipped_no_bg']), (0, 1))

    def test_rows_without_text_color_or_without_text_or_hidden_are_ignored(self):
        rows = [self.row(), self.row(fc='777777', bg='888888', text=''), self.row(fc='777777', bg='888888', visible=False)]
        result = check(self.root, layout_dumps=self.layout(rows))
        self.assertClean(result)
        self.assertEqual(result['contrast']['rows'], 0)

    def test_bad_color_text_fails(self):
        self.has(check(self.root, layout_dumps=self.layout([self.row(fc='red', bg='000000')])), 'unreadable text color')

    def test_a_folder_of_dumps_is_read(self):
        write(self.root, 'ld/a.json', [self.row(fc='ffffff', bg='000000')])
        self.assertEqual(check(self.root, layout_dumps=[self.root / 'ld'])['contrast']['checked'], 1)


class CommandLineTests(Base):
    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = C.main(list(args))
        return code, out.getvalue()

    def test_exit_codes_and_the_last_line(self):
        make_tree(self.root)
        code, text = self.run_main('--root=' + str(self.root))
        self.assertEqual(code, 0)
        last = text.strip().splitlines()[-1]
        self.assertTrue(last.startswith('SCREEN_CONTRACT {'))
        self.assertEqual(json.loads(last[len('SCREEN_CONTRACT '):])['screens'], 1)
        write(self.root, 'chapter1/tests/fixtures/contracts/demo.normal.json', mutated(count=99))
        code, text = self.run_main('--root=' + str(self.root))
        self.assertEqual(code, 1)
        self.assertIn('FAIL ', text)
        self.assertTrue(text.strip().splitlines()[-1].startswith('SCREEN_CONTRACT {'))


if __name__ == '__main__':
    unittest.main()
