import json, tempfile, unittest
from pathlib import Path
import catalog


def gear_names_entity(loot):
    """Run gear_entities on a temporary root whose chapter1/data/loot.json is `loot`; return (entity, warnings)."""
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / 'chapter1/data').mkdir(parents=True)
        (root / 'chapter1/data/loot.json').write_text(json.dumps(loot, ensure_ascii=False), encoding='utf-8')
        old, catalog.ROOT = catalog.ROOT, root
        try:
            c = catalog.Catalog()
            catalog.gear_entities(c)
        finally:
            catalog.ROOT = old
    return next(e for e in c.entities if e['id'] == 'gear:names'), c.warnings


class RareWordTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.loot = json.loads((catalog.ROOT / 'chapter1/data/loot.json').read_text(encoding='utf-8'))
        # Schema 4 stores the words as {"id","name"} objects; the old-format tests below use their plain names.
        cls.current_is_new_format = all(isinstance(x, dict) for x in cls.loot['rare_names']['first'])
        if cls.current_is_new_format:
            cls.loot['rare_names'] = {part: [x['name'] for x in cls.loot['rare_names'][part]] for part in ('first', 'second')}

    def converted(self):
        loot = json.loads(json.dumps(self.loot))
        rn = loot['rare_names']
        loot['rare_names'] = {'first': [{'id': 'f%02d' % (i + 1), 'name': n} for i, n in enumerate(rn['first'])],
                              'second': [{'id': 's%02d' % (i + 1), 'name': n} for i, n in enumerate(rn['second'])]}
        return loot

    def test_old_format_lists_words(self):
        e, _ = gear_names_entity(self.loot)
        self.assertEqual(e['sections'][0]['items'], self.loot['rare_names']['first'])
        self.assertEqual(e['sections'][1]['items'], self.loot['rare_names']['second'])

    def test_new_format_gives_same_words_with_ids(self):
        e, _ = gear_names_entity(self.converted())
        first = e['sections'][0]['items']
        self.assertEqual(len(first), len(self.loot['rare_names']['first']))
        self.assertEqual([x.split(' · ', 1)[1] for x in first], self.loot['rare_names']['first'])
        self.assertEqual(first[0].split(' · ')[0], 'f01')
        self.assertEqual(e['sections'][1]['items'][-1].split(' · ')[0], 's%02d' % len(self.loot['rare_names']['second']))

    def test_current_data_is_new_format_and_catalog_reads_it(self):
        self.assertTrue(self.current_is_new_format)
        self.assertEqual(catalog.generate()['warnings'], [])

    def test_bad_entries_are_errors_not_crashes(self):
        for bad in ([{'id': 'a'}], [{'id': '', 'name': 'x'}], [3], [{'id': 'a', 'name': 'x'}, {'id': 'a', 'name': 'y'}], 'text'):
            with self.assertRaises(ValueError):
                catalog.rare_word_list(bad, 'first')
        loot = self.converted()
        loot['rare_names']['first'] = [{'id': 'a'}]
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'chapter1/data').mkdir(parents=True)
            (root / 'chapter1/data/loot.json').write_text(json.dumps(loot, ensure_ascii=False), encoding='utf-8')
            old, catalog.ROOT = catalog.ROOT, root
            try:
                c = catalog.Catalog()
                try:
                    catalog.gear_entities(c)
                except ValueError as e:
                    self.assertIn('rare_names', str(e))
            finally:
                catalog.ROOT = old


if __name__ == '__main__':
    unittest.main()
