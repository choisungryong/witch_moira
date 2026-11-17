"""Count Hangul string literals in product GDScript files and compare with a baseline.

    python tools/dev/i18n_scan.py            compare with tools/dev/i18n_baseline.json (exit 1 if any file grew)
    python tools/dev/i18n_scan.py --update   rewrite the baseline (only when counts went down, or on first creation)
    python tools/dev/i18n_scan.py --list     print every counted file and its count

What is counted: a "site" is one string literal ("..." or '...') that contains a
Hangul syllable, on a line that is not a comment line. Text after a trailing `#`
outside a string is ignored. Triple-quoted strings are not used in the product code.

Scope (T3 directive 1.1):
  counted   chapter1/core, app, view/hud, view/fx, view/world, view/actors, view/ui51 (any *.gd)
            and other chapter1/view subfolders; combat/*.gd
  legacy    chapter1/view/cloister_*.gd, chapter_world_quality*.gd, view/chapter_world.gd:
            listed in the baseline under "legacy" for information only, never fail the check
            (they are not translated and are removed by T1 directive 4)
  excluded  chapter1/tests/ (tests are rewritten together with L1/L2), chapter1/i18n/
            (translation sources are Hangul by design)
Growth in a counted file, or a new file with a non-zero count, fails.
Shrinking never fails; run --update to lower the baseline.
"""
from pathlib import Path
import argparse, json, re, sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).resolve().with_name('i18n_baseline.json')
HANGUL = re.compile('[가-힣ㄱ-ㆎ]')
EXCLUDED_DIRS = ('chapter1/tests/', 'chapter1/i18n/')
LEGACY = re.compile(r'^chapter1/view/(cloister_[^/]*|chapter_world_quality[^/]*|chapter_world)\.gd$')
SCAN_ROOTS = ('chapter1', 'combat')


def string_literals(line):
    """Yield string literals on one line, stopping at a comment outside strings."""
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == '#':
            return
        if c in '"\'':
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == '\\' else 1
            yield line[i:j + 1]
            i = j + 1
        else:
            i += 1


def count_file(path):
    total = 0
    for raw in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if raw.lstrip().startswith('#'):
            continue
        total += sum(1 for lit in string_literals(raw) if HANGUL.search(lit))
    return total


# The core never knows the screen or the language (T3 directive 2.3, review A12). Comment lines and the text inside
# string literals are not looked at; only code is. A string that is a res://chapter1/ path is kept (a core preload of
# the view or the i18n folder is a reference).
CORE_DIRS = ('chapter1/core', 'combat')
CORE_FORBIDDEN = re.compile(r'res://chapter1/(view|app|i18n)|\bLoc\b|\bTranslationServer\b|\b(tr|tr_n|atr|atr_n)\(')


def blank_strings(line):
    """The line with string literals blanked out (their quotes stay) and any trailing comment removed."""
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == '#':
            break
        if c in '"\'':
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == '\\' else 1
            literal = line[i:j + 1]
            out.append(literal if literal[1:].startswith('res://chapter1/') else c + c)
            i = j + 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def core_references():
    """Places where core code names the view, Loc, TranslationServer or tr(). Returns ['file:line: text']."""
    found = []
    for top in CORE_DIRS:
        base = ROOT / top
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.gd')):
            rel = path.relative_to(ROOT).as_posix()
            for number, raw in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
                if raw.lstrip().startswith('#'):
                    continue
                if CORE_FORBIDDEN.search(blank_strings(raw)):
                    found.append('%s:%d: %s' % (rel, number, raw.strip()[:100]))
    return found


def scan():
    counted, legacy = {}, {}
    for top in SCAN_ROOTS:
        base = ROOT / top
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.gd')):
            rel = path.relative_to(ROOT).as_posix()
            if rel.startswith(EXCLUDED_DIRS):
                continue
            count = count_file(path)
            if count == 0:
                continue
            (legacy if LEGACY.match(rel) else counted)[rel] = count
    return counted, legacy


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--update', action='store_true')
    parser.add_argument('--list', action='store_true')
    options = parser.parse_args()
    counted, legacy = scan()
    core_refs = core_references()
    if core_refs:
        print('I18N_SCAN core references the view, Loc or the translation server: ' + json.dumps(core_refs, ensure_ascii=False))
    if options.list:
        for rel, count in counted.items():
            print('%5d  %s' % (count, rel))
        print('%5d  total (+%d legacy, not checked)' % (sum(counted.values()), sum(legacy.values())))
    if core_refs and (options.update or not BASELINE.is_file()):
        return 1
    if options.update or not BASELINE.is_file():
        old = json.loads(BASELINE.read_text(encoding='utf-8')).get('files', {}) if BASELINE.is_file() else {}
        grew = [rel for rel, count in counted.items() if count > old.get(rel, 0)] if old else []
        if grew:
            print('I18N_SCAN refusing to raise the baseline: ' + ', '.join(grew))
            return 1
        data = {'note': 'Hangul string literal sites per product file. Growth fails i18n_scan.py. Lower with --update.',
                'files': counted, 'legacy': legacy}
        BASELINE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        print('I18N_SCAN ' + json.dumps({'baseline_written': True, 'files': len(counted), 'total': sum(counted.values())}))
        return 0
    base = json.loads(BASELINE.read_text(encoding='utf-8')).get('files', {})
    grown = ['%s: %d > %d' % (rel, count, base.get(rel, 0)) for rel, count in counted.items() if count > base.get(rel, 0)]
    shrunk = ['%s: %d < %d' % (rel, counted.get(rel, 0), count) for rel, count in base.items() if counted.get(rel, 0) < count]
    print('I18N_SCAN ' + json.dumps({'files': len(counted), 'total': sum(counted.values()), 'baseline_total': sum(base.values()),
                                       'grown': grown, 'shrunk': shrunk, 'core_references': len(core_refs)}, ensure_ascii=False))
    return 1 if grown or core_refs else 0


if __name__ == '__main__':
    sys.exit(main())
