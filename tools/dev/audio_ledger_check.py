"""Sound ledger check: every sound file has a ledger entry, every entry's SHA-256 matches, nothing is listed that is gone.

    python tools/dev/audio_ledger_check.py                       # chapter1/art/audio (if it exists) and chapter1/art/quality03_audio
    python tools/dev/audio_ledger_check.py --dir chapter1/art/audio --ledger chapter1/art/audio/AUDIO-LEDGER.json
    python tools/dev/audio_ledger_check.py --strict --json out.json

Ledger formats read (S1 audio direction, 10.3: file, pack, source, license, processing, SHA-256 per file):
  - "products": [ {"file": ..., "sha256": ...}, ... ]   the Kenney ledger of chapter1/art/quality03_audio
  - "files":    [ {"file"|"path": ..., "sha256": ...}, ... ]   the new ledger of chapter1/art/audio
A "file" is a path relative to the ledger's folder. An entry may say "origin": "unverified" (or "source_unverified": true)
when the source could not be established from the record; that is listed, never guessed. With --strict it is an error too.

Exit code: 0 clean, 1 findings (file without entry, hash mismatch, entry without file, entry without sha256; with --strict
also unverified sources), 2 setup problem (no ledger, unreadable JSON). Reads files only; writes nothing except --json.
"""
import argparse, hashlib, json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
AUDIO_EXT = {'.wav', '.ogg', '.mp3', '.flac', '.m4a', '.opus'}
DEFAULT_DIRS = ['chapter1/art/audio', 'chapter1/art/quality03_audio']


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def ledger_entries(data):
    rows = data.get('products') if 'products' in data else data.get('files')
    if not isinstance(rows, list):
        raise ValueError('ledger has neither a "products" nor a "files" list')
    out = {}
    for r in rows:
        name = r.get('file') or r.get('path')
        if name:
            out[str(name).replace('\\', '/')] = r
    return out


def check(folder, ledger_path):
    folder = Path(folder)
    res = {'dir': str(folder), 'ledger': str(ledger_path), 'files': 0, 'entries': 0, 'no_entry': [], 'hash_mismatch': [], 'entry_without_file': [],
           'entry_without_sha': [], 'unverified': [], 'packs': {}}
    data = json.loads(Path(ledger_path).read_text(encoding='utf-8'))
    entries = ledger_entries(data)
    default_pack = data.get('creator', '(unnamed)')
    files = sorted(p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file() and p.suffix.lower() in AUDIO_EXT)
    res['files'], res['entries'] = len(files), len(entries)
    for name in files:
        e = entries.get(name)
        if e is None:
            res['no_entry'].append(name)
            continue
        if not e.get('sha256'):
            res['entry_without_sha'].append(name)
        elif sha256(folder / name) != e['sha256']:
            res['hash_mismatch'].append(name)
    for name, e in entries.items():
        if name not in files:
            res['entry_without_file'].append(name)
        if e.get('origin') == 'unverified' or e.get('source_unverified'):
            res['unverified'].append(name)
        pack = e.get('pack') or default_pack
        res['packs'][pack] = res['packs'].get(pack, 0) + 1
    return res


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dir', action='append', help='sound folder (repeatable); default: the two folders above that exist')
    ap.add_argument('--ledger', help='ledger file (only with one --dir); default FOLDER/AUDIO-LEDGER.json')
    ap.add_argument('--strict', action='store_true', help='unverified sources also fail')
    ap.add_argument('--json', help='write the findings here')
    args = ap.parse_args()
    dirs = [Path(d) if Path(d).is_absolute() else REPO / d for d in (args.dir or DEFAULT_DIRS)]
    if not args.dir:
        dirs = [d for d in dirs if d.is_dir()]
    if args.ledger and len(dirs) != 1:
        print('--ledger needs exactly one --dir')
        return 2
    results, code = [], 0
    for d in dirs:
        lp = Path(args.ledger) if args.ledger else d / 'AUDIO-LEDGER.json'
        if not d.is_dir() or not lp.is_file():
            print('SETUP: %s or %s not found' % (d, lp))
            return 2
        try:
            r = check(d, lp)
        except (ValueError, json.JSONDecodeError) as exc:
            print('SETUP: %s: %s' % (lp, exc))
            return 2
        results.append(r)
        bad = r['no_entry'] + r['hash_mismatch'] + r['entry_without_file'] + r['entry_without_sha']
        if bad or (args.strict and r['unverified']):
            code = 1
        print('%s: %d files, %d ledger entries' % (d, r['files'], r['entries']))
        for key, title in (('no_entry', 'file without ledger entry'), ('hash_mismatch', 'SHA-256 differs from ledger'), ('entry_without_file', 'ledger entry without file'),
                           ('entry_without_sha', 'ledger entry without sha256'), ('unverified', 'source unverified' + (' (error: --strict)' if args.strict else ' (warning)'))):
            for n in r[key]:
                print('  %-34s %s' % (title, n))
        print('  per pack: ' + ', '.join('%s %d' % kv for kv in sorted(r['packs'].items())))
    print('RESULT: %s' % ('findings, exit 1' if code else 'clean'))
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding='utf-8')
    return code


if __name__ == '__main__':
    sys.exit(main())
