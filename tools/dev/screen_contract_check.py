"""Screen contract checker (docs/SCREEN-DESIGN-HARNESS.ko.md 6 T-1, docs/specs/T8-screen-contract-structure-20261120.ko.md 4).

    python tools/dev/screen_contract_check.py                    everything under the repository root
    python tools/dev/screen_contract_check.py --dumps=<folder>   also the adapter outputs written by test_screen_contracts.gd
    python tools/dev/screen_contract_check.py --layout-dump=<file or folder>   also text contrast of layout dumps (see below)
    python tools/dev/screen_contract_check.py --update-baseline [--add=<file>]  write the current counts as the new baseline
    --root=<folder> reads another tree (the self test points it at a temporary folder)

Last line: SCREEN_CONTRACT {"screens":N,"fixtures":N,"dumps":N,"failures":[...],"notes":[...],"contrast":{...}}. Exit 1 on a failure.

Where things are (both places are read, nothing is moved):
  schema    chapter1/tests/contracts/<id>.contract.json  and  chapter1/view/contracts/<id>.contract.json
  fixture   chapter1/tests/fixtures/contracts/<id>.<variant>.json  and  chapter1/tests/fixtures/ui/<id>.<variant>.json
            (a file in fixtures/ui/ counts only when it has a "screen" key: the older files there are core-state seeds, not contracts)
  screen    chapter1/view/hud/screens/<id>.gd        adapter   chapter1/view/contracts/<id>_contract.gd

Checks: 1 schema shape, 2 version equal in schema = adapter = screen = every fixture, 3 fixtures follow the schema (a "requested" field must be
present), 4 every variant of the schema has a fixture, 5 the signals the screen declares = the schema's, 6 screen files: counts of the
words run/growth, private reads (other._field), Color( literals, get_child(<number>), preload of core/ or app/ (a count above the
baseline file tools/dev/screen_contract_baseline.json fails; no entry means 0), 7 adapters: no writes to run, no mutating calls, get_offer( at
most once, 8 dumps follow the schema ("requested" fields may be missing), 9 contrast.
A schema whose screen or adapter file does not exist yet is a note, not a failure (the design comes before the code). The same for a
fixture whose schema does not exist yet: a note, counted as "unchecked_fixtures" (it is not checked, and the result line says so).

Contrast: a row of a layout dump (chapter1/tests/layout_dump.gd rows) that carries "fc" (text color, hex rrggbb[aa]) and "bg" (the color
under the text, hex) is measured with the WCAG ratio: 4.5, or 3.0 when the text is large (fs >= 24). layout_dump.gd does not write these two
fields yet; rows without "bg" are counted as skipped, and the pixels under the text are not sampled by this tool. Nothing is invented.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = 'tools/dev/screen_contract_baseline.json'
BASELINE_NOTE = ('tools/dev/screen_contract_check.py: the most each screen file may read (run/growth words, private fields, Color( literals, '
                 'get_child(number), preload of core/ or app/). A count above this fails; no entry means 0. Lower it when you remove something. '
                 'Rewrite with --update-baseline [--add=<file>].')
SCHEMA_DIRS = ('chapter1/tests/contracts', 'chapter1/view/contracts')
FIXTURE_DIRS = ('chapter1/tests/fixtures/contracts', 'chapter1/tests/fixtures/ui')
SCREEN_DIR = 'chapter1/view/hud/screens'
ADAPTER_DIR = 'chapter1/view/contracts'
SCREEN_CATEGORIES = ('run', 'private', 'color', 'child_index', 'core_preload')
TOP_KEYS = {'screen', 'contract_version', 'fields', 'variants', 'signals'}
TYPE_KEYS = {'string': {'max_len'}, 'int': {'min', 'max'}, 'float': {'min', 'max'}, 'bool': set(), 'enum': {'values'}, 'array': {'min', 'max', 'item'}, 'object': {'fields'}}
COMMON_KEYS = {'type', 'optional', 'nullable', 'requested'}
MUTATORS = ('choose', 'start', 'step', 'equip', 'reroll', 'open_inventory', 'close_inventory', 'clear_build')
LARGE_TEXT = 24


# ------------------------------------------------------------------------------------------------ schema and values

def check_spec(spec, path, out):
    """The shape of one field spec (docs/specs/T8 2.2). Appends problems to out."""
    if not isinstance(spec, dict):
        out.append('%s: a field spec must be an object' % path)
        return
    kind = spec.get('type')
    if kind not in TYPE_KEYS:
        out.append('%s: unknown type %r' % (path, kind))
        return
    for key in spec:
        if key not in COMMON_KEYS | TYPE_KEYS[kind] and not key.startswith('_'):
            out.append('%s: unknown key %r for type %s' % (path, key, kind))
    for flag in ('optional', 'nullable'):
        if flag in spec and not isinstance(spec[flag], bool):
            out.append('%s: %s must be true or false' % (path, flag))
    if 'requested' in spec and not (isinstance(spec['requested'], str) and spec['requested'].strip()):
        out.append('%s: requested must name the ledger line' % path)
    for key in ('max_len', 'min', 'max'):
        if key in spec and (isinstance(spec[key], bool) or not isinstance(spec[key], (int, float))):
            out.append('%s: %s must be a number' % (path, key))
    if kind == 'enum':
        values = spec.get('values')
        if not (isinstance(values, list) and values and all(isinstance(v, str) for v in values)):
            out.append('%s: enum needs a non-empty list of strings in "values"' % path)
    if kind == 'array':
        if 'item' not in spec:
            out.append('%s: array needs "item"' % path)
        else:
            check_spec(spec['item'], path + '[]', out)
    if kind == 'object':
        fields = spec.get('fields')
        if not isinstance(fields, dict):
            out.append('%s: object needs "fields"' % path)
        else:
            for name, sub in fields.items():
                check_spec(sub, path + '.' + name, out)


def check_schema(schema, label):
    out = []
    if not isinstance(schema, dict):
        return ['%s: the schema must be an object' % label]
    for key in schema:
        if key not in TOP_KEYS and not key.startswith('_'):
            out.append('%s: unknown key %r' % (label, key))
    if not isinstance(schema.get('screen'), str) or not schema.get('screen'):
        out.append('%s: "screen" must be the screen id' % label)
    version = schema.get('contract_version')
    if isinstance(version, bool) or not isinstance(version, int) or version < 0:
        out.append('%s: "contract_version" must be an integer of 0 or more (0 = the draft of the design step, 1 = the first closed version)' % label)
    if not isinstance(schema.get('fields'), dict):
        out.append('%s: "fields" must be an object' % label)
    else:
        for name, spec in schema['fields'].items():
            check_spec(spec, '%s fields.%s' % (label, name), out)
    for key in ('variants', 'signals'):
        value = schema.get(key, [])
        if not (isinstance(value, list) and all(isinstance(v, str) and v for v in value)):
            out.append('%s: %r must be a list of names' % (label, key))
        elif len(set(value)) != len(value):
            out.append('%s: %r has a name twice' % (label, key))
    return out


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def check_value(value, spec, path, out, fixture):
    """Follows one value against its spec. fixture=True: a "requested" field must be present (the caller checks presence)."""
    if value is None:
        if not spec.get('nullable'):
            out.append('%s: null is not allowed' % path)
        return
    kind = spec['type']
    if kind == 'string':
        if not isinstance(value, str):
            out.append('%s: expected a string' % path)
        elif 'max_len' in spec and len(value) > spec['max_len']:
            out.append('%s: %d characters, the schema allows %d' % (path, len(value), spec['max_len']))
    elif kind == 'int':
        if isinstance(value, bool) or not isinstance(value, int):
            out.append('%s: expected an integer' % path)
        else:
            check_range(value, spec, path, out)
    elif kind == 'float':
        if not is_number(value):
            out.append('%s: expected a number' % path)
        else:
            check_range(value, spec, path, out)
    elif kind == 'bool':
        if not isinstance(value, bool):
            out.append('%s: expected true or false' % path)
    elif kind == 'enum':
        if value not in spec['values']:
            out.append('%s: %r is not one of %s' % (path, value, spec['values']))
    elif kind == 'array':
        if not isinstance(value, list):
            out.append('%s: expected an array' % path)
            return
        if 'min' in spec and len(value) < spec['min']:
            out.append('%s: %d items, at least %s' % (path, len(value), spec['min']))
        if 'max' in spec and len(value) > spec['max']:
            out.append('%s: %d items, at most %s' % (path, len(value), spec['max']))
        for index, item in enumerate(value):
            check_value(item, spec['item'], '%s[%d]' % (path, index), out, fixture)
    elif kind == 'object':
        check_object(value, spec['fields'], path, out, fixture)


def check_range(value, spec, path, out):
    if 'min' in spec and value < spec['min']:
        out.append('%s: %s is below the minimum %s' % (path, value, spec['min']))
    if 'max' in spec and value > spec['max']:
        out.append('%s: %s is above the maximum %s' % (path, value, spec['max']))


def check_object(value, fields, path, out, fixture):
    if not isinstance(value, dict):
        out.append('%s: expected an object' % path)
        return
    for name in value:
        if name not in fields:
            out.append('%s.%s: unknown key' % (path, name))
    for name, spec in fields.items():
        here = '%s.%s' % (path, name)
        if name not in value:
            if fixture and 'requested' in spec:
                out.append('%s: a requested field must be in the fixture (with a stand-in value)' % here)
            elif not spec.get('optional') and 'requested' not in spec:
                out.append('%s: required field is missing' % here)
            continue
        check_value(value[name], spec, here, out, fixture)


def check_document(doc, schema, label, fixture):
    """Problems of one fixture (fixture=True) or one adapter output (fixture=False) against the schema."""
    out = []
    if not isinstance(doc, dict):
        return ['%s: the document must be an object' % label]
    if doc.get('screen') != schema['screen']:
        out.append('%s: "screen" is %r, the schema is %r' % (label, doc.get('screen'), schema['screen']))
    if doc.get('contract_version') != schema['contract_version']:
        out.append('%s: contract_version %r, the schema has %r' % (label, doc.get('contract_version'), schema['contract_version']))
    body = {k: v for k, v in doc.items() if k not in ('screen', 'contract_version')}
    check_object(body, schema['fields'], label, out, fixture)
    return out


# ------------------------------------------------------------------------------------------------ GDScript text

def code_lines(text):
    """[(line number, code, code with strings)] without comments. `code` has string contents blanked ("" stays), the other
    keeps them (for preload paths). Triple-quoted strings span lines."""
    result = []
    triple = False
    for number, line in enumerate(text.split('\n'), 1):
        plain, with_strings = [], []
        i, quote = 0, ''
        while i < len(line):
            ch = line[i]
            if triple:
                if line.startswith('"""', i):
                    triple = False
                    i += 3
                    continue
                i += 1
                continue
            if quote:
                if ch == '\\' and i + 1 < len(line):
                    with_strings.append(line[i:i + 2])
                    i += 2
                    continue
                with_strings.append(ch)
                if ch == quote:
                    quote = ''
                    plain.append(ch)
                i += 1
                continue
            if line.startswith('"""', i):
                triple = True
                i += 3
                continue
            if ch == '#':
                break
            if ch in '"\'':
                quote = ch
                plain.append(ch)
                with_strings.append(ch)
                i += 1
                continue
            plain.append(ch)
            with_strings.append(ch)
            i += 1
        result.append((number, ''.join(plain), ''.join(with_strings)))
    return result


PRIVATE = re.compile(r'(\w+|\)|\])\.(_[A-Za-z]\w*)')


def private_reads(code):
    """How many `<something>._name` reads a line has (self._name and super._name are the file's own)."""
    return sum(1 for m in PRIVATE.finditer(code) if m.group(1) not in ('self', 'super') and not m.group(1).isdigit())


def screen_counts(text):
    """{category: [line numbers]} of the things a screen file must not do (docs/specs/T8 3)."""
    found = {c: [] for c in SCREEN_CATEGORIES}
    for number, code, with_strings in code_lines(text):
        if re.search(r'\b(run|growth)\b', code):
            found['run'].append(number)
        found['private'] += [number] * private_reads(code)
        for _ in re.finditer(r'\bColor\(', code):
            found['color'].append(number)
        if re.search(r'\bget_child\(\s*\d', code):
            found['child_index'].append(number)
        if re.search(r'res://chapter1/(core|app)/', with_strings):
            found['core_preload'].append(number)
    return found


def adapter_problems(text):
    """(problems, get_offer count) of an adapter file: it reads the core, it does not change it."""
    problems, offers = [], 0
    mutator = re.compile(r'\brun\.[\w.]*\b(%s)\(|\brun\.[\w.]*\b(set_\w*|import_\w*|configure_\w*)\(' % '|'.join(MUTATORS))
    write = re.compile(r'\brun\.[\w.\[\]]*\s*(?:\+=|-=|\*=|/=|=(?!=))')
    for number, code, _ in code_lines(text):
        if write.search(code):
            problems.append('line %d: writes to run (%s)' % (number, code.strip()[:60]))
        found = mutator.search(code)
        if found:
            problems.append('line %d: calls a changing function of run (%s)' % (number, (found.group(1) or found.group(2))))
        offers += len(re.findall(r'\bget_offer\(', code))
    return problems, offers


VERSION = re.compile(r'^const\s+CONTRACT_VERSION\s*(?::\s*\w+\s*)?:?=\s*(\d+)', re.M)


def read_version(text):
    found = VERSION.search(text)
    return int(found.group(1)) if found else None


def declared_signals(text):
    return sorted(re.findall(r'^\s*signal\s+(\w+)', '\n'.join(code for _, code, _ in code_lines(text)), re.M))


def signal_names(signals):
    return sorted(s.split('(', 1)[0].strip() for s in signals)


# ------------------------------------------------------------------------------------------------ contrast

def parse_hex(text):
    if not isinstance(text, str):
        return None
    t = text.strip().lstrip('#')
    if not re.fullmatch(r'[0-9a-fA-F]{6}([0-9a-fA-F]{2})?', t):
        return None
    r, g, b = int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16)
    return (r, g, b, int(t[6:8], 16) / 255.0 if len(t) == 8 else 1.0)


def luminance(rgb):
    def lin(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])


def contrast_ratio(fc, bg, row_alpha=1.0):
    """WCAG ratio of text color fc over background bg (hex tuples). The text's own alpha and the row's alpha blend it into bg."""
    alpha = fc[3] * row_alpha
    mixed = tuple(fc[i] * alpha + bg[i] * (1 - alpha) for i in range(3))
    a, b = luminance(mixed), luminance(bg)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def walk_rows(node):
    if isinstance(node, dict):
        if 'class' in node and 'fc' in node:
            yield node
        for value in node.values():
            yield from walk_rows(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk_rows(value)


def check_contrast(doc, label, minimum, stats, failures):
    for row in walk_rows(doc):
        if not str(row.get('text', '')).strip() or not row.get('visible', True):
            continue
        stats['rows'] += 1
        fc, bg = parse_hex(row.get('fc')), parse_hex(row.get('bg'))
        if fc is None:
            failures.append('%s: %s has an unreadable text color %r' % (label, row.get('name'), row.get('fc')))
            continue
        if bg is None:
            stats['skipped_no_bg'] += 1
            continue
        stats['checked'] += 1
        need = 3.0 if float(row.get('fs', 0) or 0) >= LARGE_TEXT else minimum
        ratio = contrast_ratio(fc, bg, float(row.get('alpha', 1.0)))
        if ratio < need:
            failures.append('%s: contrast %.2f is below %.1f for "%s" (%s)' % (label, ratio, need, str(row.get('text'))[:30], row.get('name')))


# ------------------------------------------------------------------------------------------------ the run

def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8')), None
    except (OSError, ValueError) as error:
        return None, '%s: cannot read (%s)' % (rel(path), error.__class__.__name__)


def rel(path):
    try:
        return Path(path).resolve().relative_to(CURRENT_ROOT).as_posix()
    except ValueError:
        return str(path)


CURRENT_ROOT = ROOT


def load_baseline(root):
    data, problem = load_json(root / BASELINE) if (root / BASELINE).is_file() else ({}, None)
    files = data.get('files', {}) if isinstance(data, dict) else {}
    return files if isinstance(files, dict) else {}, problem


def run(root, dumps=None, layout_dumps=(), min_contrast=4.5, update_baseline=False, add=()):
    global CURRENT_ROOT
    CURRENT_ROOT = Path(root).resolve()
    root = CURRENT_ROOT
    failures, notes = [], []
    baseline, problem = load_baseline(root)
    if problem:
        failures.append(problem)
    schemas = {}
    for folder in SCHEMA_DIRS:
        for path in sorted((root / folder).glob('*.contract.json')) if (root / folder).is_dir() else []:
            schema, problem = load_json(path)
            if problem:
                failures.append(problem)
                continue
            issues = check_schema(schema, rel(path))
            failures += issues
            name = path.name[:-len('.contract.json')]
            if not issues and schema['screen'] != name:
                failures.append('%s: "screen" is %r but the file is named for %r' % (rel(path), schema['screen'], name))
            elif not issues:
                if name in schemas:
                    failures.append('%s: the schema of %r exists twice (also %s)' % (rel(path), name, schemas[name][1]))
                else:
                    schemas[name] = (schema, rel(path))
    # fixtures
    fixtures = unchecked = 0
    seen = {}
    for folder in FIXTURE_DIRS:
        base = root / folder
        for path in sorted(base.glob('*.json')) if base.is_dir() else []:
            parts = path.name[:-len('.json')].split('.')
            if len(parts) != 2:
                continue
            screen_id, variant = parts
            doc, problem = load_json(path)
            if problem:
                if screen_id in schemas or folder.endswith('contracts'):
                    failures.append(problem)
                continue
            if folder.endswith('/ui') and not (isinstance(doc, dict) and 'screen' in doc):
                continue  # an older core-state seed, not a contract
            if folder.endswith('/ui') and isinstance(doc.get('screen'), str) and doc['screen']:
                screen_id = doc['screen']  # a draft fixture may carry a prefix in its name (title_v0.normal.json is a "title" contract)
            if screen_id not in schemas:
                # a design in progress (the fixtures come before the schema is closed): not checkable yet, so a note, and counted
                notes.append('%s: no schema for the screen %r yet, not checked' % (rel(path), screen_id))
                unchecked += 1
                continue
            schema = schemas[screen_id][0]
            fixtures += 1
            key = (screen_id, variant)
            if key in seen:
                if folder.endswith('/ui') and seen[key].startswith(FIXTURE_DIRS[0] + '/'):
                    notes.append('%s: the same variant of %r exists in %s, which counts; this draft fixture is not checked' % (rel(path), screen_id, seen[key]))
                    continue
                failures.append('%s: the same fixture exists in %s too' % (rel(path), seen[key]))
            seen[key] = rel(path)
            failures += check_document(doc, schema, rel(path), True)
            if variant not in schema.get('variants', []):
                notes.append('%s: variant %r is not listed in the schema' % (rel(path), variant))
    # per screen: variants, versions, signals, static scans
    screen_files = {p.stem: p for p in sorted((root / SCREEN_DIR).glob('*.gd'))} if (root / SCREEN_DIR).is_dir() else {}
    for name, path in screen_files.items():
        if name not in schemas:
            failures.append('%s: a screen file without a schema (%s/%s.contract.json)' % (rel(path), SCHEMA_DIRS[0], name))
    for name, (schema, schema_path) in sorted(schemas.items()):
        for variant in schema.get('variants', []):
            if (name, variant) not in seen:
                failures.append('%s: variant %r has no fixture file' % (schema_path, variant))
        screen_path = screen_files.get(name)
        adapter_path = root / ADAPTER_DIR / (name + '_contract.gd')
        for label, path in (('screen', screen_path), ('adapter', adapter_path if adapter_path.is_file() else None)):
            if path is None:
                notes.append('%s: no %s file yet' % (name, label))
                continue
            text = path.read_text(encoding='utf-8', errors='replace')
            version = read_version(text)
            if version is None:
                failures.append('%s: no "const CONTRACT_VERSION := N" line' % rel(path))
            elif version != schema['contract_version']:
                failures.append('%s: CONTRACT_VERSION %d, the schema has %d' % (rel(path), version, schema['contract_version']))
            if label == 'screen':
                want, have = signal_names(schema.get('signals', [])), declared_signals(text)
                if want != have:
                    failures.append('%s: signals %s, the schema lists %s' % (rel(path), have, want))
            else:
                issues, offers = adapter_problems(text)
                failures += ['%s: %s' % (rel(path), i) for i in issues]
                if offers > 1:
                    failures.append('%s: get_offer( is called %d times, one place at most' % (rel(path), offers))
    # static counts of screen files against the baseline
    watched = {rel(p): p for p in screen_files.values()}
    for key in list(baseline):
        if (root / key).is_file():
            watched.setdefault(key, root / key)
        else:
            notes.append('%s: in the baseline but the file does not exist' % key)
    for key in add:
        if (root / key).is_file():
            watched.setdefault(key, root / key)
        else:
            failures.append('--add: %s does not exist' % key)
    counts = {}
    for key, path in sorted(watched.items()):
        counts[key] = screen_counts(path.read_text(encoding='utf-8', errors='replace'))
    if update_baseline:
        new = {k: {c: len(v) for c, v in cats.items() if v} for k, cats in counts.items()}
        (root / BASELINE).parent.mkdir(parents=True, exist_ok=True)
        (root / BASELINE).write_text(json.dumps({'_note': BASELINE_NOTE, 'files': new}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        baseline = new
    for key, cats in counts.items():
        allowed = baseline.get(key, {})
        for category, lines in cats.items():
            limit = int(allowed.get(category, 0))
            if len(lines) > limit:
                failures.append('%s: %s %d, baseline %d (lines %s)' % (key, category, len(lines), limit, ', '.join(str(n) for n in lines[:8])))
            elif len(lines) < limit:
                notes.append('%s: %s %d is below the baseline %d (lower the baseline)' % (key, category, len(lines), limit))
    # dumps
    dump_count = 0
    if dumps:
        folder = Path(dumps)
        if not folder.is_dir():
            failures.append('--dumps: %s is not a folder' % dumps)
        else:
            for path in sorted(folder.glob('*.json')):
                screen_id = path.name.split('.')[0]
                doc, problem = load_json(path)
                if problem:
                    failures.append(problem)
                    continue
                dump_count += 1
                if screen_id not in schemas:
                    failures.append('%s: no schema for the screen %r' % (path.name, screen_id))
                    continue
                failures += check_document(doc, schemas[screen_id][0], 'dump ' + path.name, False)
    # contrast
    stats = {'rows': 0, 'checked': 0, 'skipped_no_bg': 0}
    for item in layout_dumps:
        item = Path(item)
        paths = sorted(item.glob('*.json')) if item.is_dir() else [item]
        for path in paths:
            doc, problem = load_json(path)
            if problem:
                failures.append(problem)
                continue
            check_contrast(doc, path.name, min_contrast, stats, failures)
    return {'screens': len(schemas), 'fixtures': fixtures, 'unchecked_fixtures': unchecked, 'dumps': dump_count, 'failures': failures, 'notes': notes, 'contrast': stats}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', default=str(ROOT))
    parser.add_argument('--dumps', default='')
    parser.add_argument('--layout-dump', action='append', default=[])
    parser.add_argument('--min-contrast', type=float, default=4.5)
    parser.add_argument('--update-baseline', action='store_true')
    parser.add_argument('--add', action='append', default=[], help='with --update-baseline: also count this file (path from the root)')
    options = parser.parse_args(argv)
    result = run(options.root, options.dumps or None, options.layout_dump, options.min_contrast, options.update_baseline, options.add)
    for failure in result['failures']:
        print('FAIL ' + failure)
    for note in result['notes']:
        print('NOTE ' + note)
    print('SCREEN_CONTRACT ' + json.dumps(result, ensure_ascii=False, separators=(',', ':')))
    return 1 if result['failures'] else 0


if __name__ == '__main__':
    sys.exit(main())
