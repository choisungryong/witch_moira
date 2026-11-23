#!/usr/bin/env python3
"""Sound adoption (T12 skill lab, SL-A): put a candidate's files into a sound slot of the game, or take them out again.

    python tools/dev/audio_adopt.py list [--json]
    python tools/dev/audio_adopt.py adopt  --slot skill.arc.cast --candidate chain-lightning/round2/C7 [--expect-rev SHA] [--dry-run] [--no-import] [--yes]
    python tools/dev/audio_adopt.py revert --slot skill.arc.cast [--expect-rev SHA] [--dry-run]

Slots are the keys of `slots` in chapter1/data/audio_map.json (schema 2); the player (chapter1/presentation/combat_audio.gd) plays
the audition, else the file `adopted` for the slot, else the sound of its parent cue. Candidates are listed by the files
_local/audio/**/lab-candidates.json (docs/specs/T12-skill-lab-20261123.ko.md 3.4); a candidate id is "<folder below _local/audio>/<key>"
(the key alone for a list at _local/audio itself). A candidate's file path is relative to its list file, or starts with "chapter1/"
(a file of this repository); the real path must stay inside _local/audio or chapter1/art.

adopt writes IN THE REPOSITORY (no commit): the files to chapter1/art/audio/slots/<slot>/<key>_<n>.wav (a file of the same name with
other content is refused), `adopted` of audio_map.json (same indentation, key order and line ends, only the changed place),
AUDIO-LEDGER.json (source fields from the list's `ledger` rows or from the ledger row of the same sha256; none known = "origin":
"unverified", which the check allows), ASSET-LEDGER.json (same fields, holes written as "미확인"), the Godot import of the new
files, then audio_ledger_check.py and asset_ledger.py check. Any failure puts every file back (exit 5). It asks for --yes after it
has printed what it will write and the warning that the sound will play in the normal game (a slot whose parent cue is silent
today, like the lightning cast, will start to sound).
--expect-rev is the sha256 of audio_map.json the caller saw; if the file is different now nothing is written (exit 3).
revert drops `adopted` of the slot and deletes the files under slots/<slot>/ that git does not track, with their ledger rows
and .import files (files that are committed stay).
--root: use another folder as the repository (checks); --candidates-dir: where the lists are (default <root>/_local/audio).

Exit codes: 0 done, 1 other error, 2 bad input (slot, candidate, files, wav), 3 --expect-rev differs, 4 a file of the same name
with other content, 5 import or check failed (rolled back), 6 needs --yes. The last output line is `AUDIO_ADOPT {json}`.
"""
import argparse
import array
import datetime
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MAP_REL = 'chapter1/data/audio_map.json'
AUDIO_DIR_REL = 'chapter1/art/audio'
AUDIO_LEDGER_REL = AUDIO_DIR_REL + '/AUDIO-LEDGER.json'
ASSET_LEDGER_REL = 'chapter1/art/ASSET-LEDGER.json'
SLOTS_REL = AUDIO_DIR_REL + '/slots'
PLAYER_REL = 'chapter1/presentation/combat_audio.gd'
UNKNOWN = '미확인'

EXIT_OK, EXIT_ERR, EXIT_INPUT, EXIT_REV, EXIT_CONFLICT, EXIT_CHECK, EXIT_CONFIRM = 0, 1, 2, 3, 4, 5, 6


class Refused(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


# ----------------------------------------------------------------------------------------------- files and json in the file's own style

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    return sha256_bytes(Path(path).read_bytes())


def read_doc(path):
    """(text, parsed) of a JSON file; the text is kept to write the file back in its own style."""
    text = Path(path).read_bytes().decode('utf-8')
    return text, json.loads(text.lstrip('﻿'))


def dump_like(text, obj):
    """JSON text of obj in the style of `text`: indent 2, same line ends, same final newline, non-ASCII kept."""
    newline = '\r\n' if '\r\n' in text else '\n'
    out = json.dumps(obj, indent=2, ensure_ascii=False) + ('\n' if text.endswith('\n') else '')
    return out.replace('\n', newline)


def style_exact(text, obj):
    return dump_like(text, obj) == text


def atomic_write(path, data):
    path = Path(path)
    tmp = path.with_name(path.name + '.tmp-adopt')
    tmp.write_bytes(data)
    os.replace(tmp, path)


def git_tracked(root, rel):
    """True/False when `rel` is in the git index of root; None when git cannot tell (no repository, no git)."""
    try:
        proc = subprocess.run(['git', '-C', str(root), 'ls-files', '--', rel], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return bool(proc.stdout.strip())


# ----------------------------------------------------------------------------------------------- the sound map and the candidates

class Context:
    def __init__(self, root, candidates_dir=None):
        self.root = Path(root).resolve()
        self.cand_dir = Path(candidates_dir).resolve() if candidates_dir else self.root / '_local' / 'audio'
        self.map_path = self.root / MAP_REL
        self.audio_ledger_path = self.root / AUDIO_LEDGER_REL
        self.asset_ledger_path = self.root / ASSET_LEDGER_REL

    def map_doc(self):
        if not self.map_path.is_file():
            raise Refused(EXIT_INPUT, 'no sound map: %s' % self.map_path)
        text, doc = read_doc(self.map_path)
        if int(doc.get('schema_version', 1)) < 2 or not isinstance(doc.get('slots'), dict):
            raise Refused(EXIT_INPUT, 'audio_map.json has no slots (schema_version < 2)')
        return text, doc

    def rev(self):
        return sha256_file(self.map_path) if self.map_path.is_file() else ''

    def silent_cues(self):
        """The cues combat_audio.gd keeps silent (SILENT) today."""
        path = self.root / PLAYER_REL
        if not path.is_file():
            return []
        found = re.search(r'const SILENT\b[^=]*=\s*\[([^\]]*)\]', path.read_text(encoding='utf-8'))
        return re.findall(r'"(\w+)"', found.group(1)) if found else []

    def allowed_bases(self):
        return [self.cand_dir, (self.root / 'chapter1' / 'art').resolve()]

    def resolve_file(self, entry, list_dir):
        """Real path of a candidate file, or Refused: not absolute, and inside _local/audio or chapter1/art after resolving."""
        entry = str(entry).replace('\\', '/')
        if not entry or entry.startswith('/') or re.match(r'^[A-Za-z]:', entry):
            raise Refused(EXIT_INPUT, 'candidate file path must be relative: %r' % entry)
        base = self.root if entry.startswith('chapter1/') else Path(list_dir)
        real = (base / entry).resolve()
        if not any(real == b or b in real.parents for b in self.allowed_bases()):
            raise Refused(EXIT_INPUT, 'candidate file is outside _local/audio and chapter1/art: %r' % entry)
        if real.suffix.lower() != '.wav':
            raise Refused(EXIT_INPUT, 'candidate file is not a .wav: %r' % entry)
        if not real.is_file():
            raise Refused(EXIT_INPUT, 'candidate file does not exist: %r' % entry)
        return real

    def candidates(self):
        """{id: candidate} from every _local/audio/**/lab-candidates.json; unreadable lists are in the second value."""
        found, problems = {}, []
        if not self.cand_dir.is_dir():
            return found, problems
        for list_path in sorted(self.cand_dir.rglob('lab-candidates.json')):
            folder = list_path.parent.relative_to(self.cand_dir).as_posix()
            folder = '' if folder == '.' else folder
            try:
                doc = json.loads(list_path.read_bytes().decode('utf-8').lstrip('﻿'))
                rows = doc['candidates']
            except (OSError, ValueError, KeyError, TypeError) as exc:
                problems.append('%s: %s' % (list_path, exc))
                continue
            for row in rows:
                key = str(row.get('key', ''))
                if not key or '/' in key or '\\' in key or key.startswith('.'):
                    problems.append('%s: bad key %r' % (list_path, key))
                    continue
                cid = '%s/%s' % (folder, key) if folder else key
                found[cid] = {'id': cid, 'key': key, 'label': row.get('label', ''), 'slot': row.get('slot', ''), 'files': list(row.get('files', [])),
                              'ledger': list(row.get('ledger', [])), 'list_path': list_path, 'list_dir': list_path.parent,
                              'title': doc.get('title', ''), 'by': doc.get('by', ''), 'delivered': doc.get('delivered', '')}
        return found, problems


def wav_facts(path):
    """Format and peak of a PCM WAV: {rate, channels, bits, seconds, peak_dbfs}; Refused when it cannot be read."""
    try:
        with wave.open(str(path), 'rb') as w:
            rate, channels, bits, frames = w.getframerate(), w.getnchannels(), w.getsampwidth() * 8, w.getnframes()
            raw = w.readframes(frames)
    except (wave.Error, EOFError, OSError) as exc:
        raise Refused(EXIT_INPUT, 'not a readable PCM wav (%s): %s' % (exc, path.name))
    if frames == 0:
        raise Refused(EXIT_INPUT, 'empty wav: %s' % path.name)
    peak = None
    if bits == 16:
        samples = array.array('h')
        samples.frombytes(raw[:len(raw) - len(raw) % 2])
        if sys.byteorder == 'big':
            samples.byteswap()
        top = max(max(samples), -min(samples)) if len(samples) else 0
        peak = round(20 * math.log10(top / 32768.0), 2) if top else None
    return {'rate': rate, 'channels': channels, 'bits': bits, 'seconds': round(frames / float(rate), 3), 'peak_dbfs': peak}


def dest_names(candidate, slot):
    stem = re.sub(r'[^a-z0-9_-]+', '-', candidate['key'].lower()).strip('-') or 'take'
    return ['%s_%d.wav' % (stem, i + 1) for i in range(len(candidate['files']))]


def ledger_fields(ctx, candidate, real, audio_ledger):
    """Source fields for one candidate file: the list's own row (matched by the path as written, else by its file name), else the
    ledger row of the repository with the same sha256, else {} (written as unverified)."""
    entry = candidate['files'][candidate['_real'].index(real)]
    rows = candidate['ledger']
    row = next((r for r in rows if str(r.get('file', '')).replace('\\', '/') == str(entry).replace('\\', '/')), None)
    if row is None:
        same_name = [r for r in rows if str(r.get('file', '')).replace('\\', '/').split('/')[-1] == real.name]
        row = same_name[0] if len(same_name) == 1 else None
    if row is not None:
        fields = {k: v for k, v in row.items() if k not in ('file', 'sha256')}
        if 'processing' in fields and 'method' not in fields:
            fields['method'] = fields.pop('processing')
        return fields
    digest = sha256_file(real)
    for product in (audio_ledger or {}).get('products', []):
        if product.get('sha256') == digest:
            return {k: v for k, v in product.items() if k not in ('file', 'sha256')}
    return {}


# ----------------------------------------------------------------------------------------------- plan

def build_plan(ctx, slot, candidate_id, any_slot=False):
    map_text, map_doc = ctx.map_doc()
    slots = map_doc['slots']
    if not re.fullmatch(r'[a-z0-9_]+(\.[a-z0-9_]+)+', slot or ''):
        raise Refused(EXIT_INPUT, 'bad slot name: %r' % slot)
    if slot not in slots:
        raise Refused(EXIT_INPUT, 'unknown slot: %s' % slot)
    found, problems = ctx.candidates()
    candidate = found.get(candidate_id)
    if candidate is None:
        raise Refused(EXIT_INPUT, 'unknown candidate: %s (lists with problems: %d)' % (candidate_id, len(problems)))
    if candidate['slot'] != slot and not any_slot:
        raise Refused(EXIT_INPUT, 'candidate %s is made for slot %r, not %r (--any-slot to override)' % (candidate_id, candidate['slot'], slot))
    if not candidate['files']:
        raise Refused(EXIT_INPUT, 'candidate has no files')
    per_targets = int(slots[slot].get('per_targets', 0))
    if per_targets and len(candidate['files']) != per_targets:
        raise Refused(EXIT_INPUT, 'slot %s picks a file by contacts and needs exactly %d files, the candidate has %d' % (slot, per_targets, len(candidate['files'])))
    candidate['_real'] = [ctx.resolve_file(entry, candidate['list_dir']) for entry in candidate['files']]
    if len(set(candidate['_real'])) != len(candidate['_real']):
        raise Refused(EXIT_INPUT, 'the same file is listed twice')
    audio_ledger = json.loads(ctx.audio_ledger_path.read_bytes().decode('utf-8').lstrip('﻿')) if ctx.audio_ledger_path.is_file() else None
    files = []
    for real, name in zip(candidate['_real'], dest_names(candidate, slot)):
        facts = wav_facts(real)
        dest_rel = '%s/%s/%s' % (SLOTS_REL, slot, name)
        dest = ctx.root / dest_rel
        digest = sha256_file(real)
        if dest.is_file() and sha256_file(dest) != digest:
            raise Refused(EXIT_CONFLICT, 'a different file is already there, nothing is overwritten: %s' % dest_rel)
        files.append({'source': str(real), 'dest_rel': dest_rel, 'new': not dest.is_file(), 'sha256': digest, 'size': real.stat().st_size,
                      'format': facts, 'fields': ledger_fields(ctx, candidate, real, audio_ledger), 'res': 'res://' + dest_rel})
    parent = str(slots[slot].get('parent', ''))
    silent = parent in ctx.silent_cues()
    before = map_doc.get('adopted', {}).get(slot)
    warnings = ['이 채택은 저장소 파일을 고칩니다. 커밋은 디렉터가 회귀를 돌린 뒤에 합니다.',
                '채택하면 일반 게임에서 이 자리의 소리가 이 파일로 울리게 됩니다.']
    if silent:
        warnings.append('이 자리의 지금 소리(%s)는 일반 게임에서 무음입니다. 채택하면 일반 게임에서 소리가 나기 시작합니다.' % parent)
    if not any(f['fields'] for f in files):
        warnings.append('출처 기록이 없는 후보입니다. 원장에 "unverified"로 적습니다.')
    if any(f['format']['rate'] != 48000 or f['format']['channels'] != 1 for f in files):
        warnings.append('48kHz 모노가 아닌 파일이 있습니다.')
    confirm = '자리 %s 에 후보 %s 를 채택합니다.\n쓸 파일(%d): %s\n고칠 표: %s (adopted), %s, %s\n%s' % (
        slot, candidate_id, len(files), ', '.join(f['dest_rel'] for f in files), MAP_REL, AUDIO_LEDGER_REL, ASSET_LEDGER_REL, '\n'.join(warnings))
    return {'slot': slot, 'candidate': candidate, 'files': files, 'parent': parent, 'parent_silent': silent, 'adopted_before': before,
            'map_text': map_text, 'map_doc': map_doc, 'warnings': warnings, 'confirm': confirm}


# ----------------------------------------------------------------------------------------------- ledgers

def audio_ledger_row(f, plan):
    row = {'file': f['dest_rel'][len(AUDIO_DIR_REL) + 1:], 'sha256': f['sha256']}
    if f['fields']:
        row.update(f['fields'])
    else:
        row['origin'] = 'unverified'
        row['note'] = 'adopted from candidate %s; the candidate list has no source row' % plan['candidate']['id']
    row['adopted_from'] = plan['candidate']['id']
    row['adopted_slot'] = plan['slot']
    return row


def update_audio_ledger(ctx, plan):
    if not ctx.audio_ledger_path.is_file():
        raise Refused(EXIT_CHECK, 'AUDIO-LEDGER.json is missing: %s' % ctx.audio_ledger_path)
    text, doc = read_doc(ctx.audio_ledger_path)
    products = doc.setdefault('products', [])
    for f in plan['files']:
        row = audio_ledger_row(f, plan)
        index = next((i for i, p in enumerate(products) if p.get('file') == row['file']), None)
        if index is None:
            products.append(row)
        else:
            products[index] = row
    atomic_write(ctx.audio_ledger_path, dump_like(text, doc).encode('utf-8'))


def asset_ledger_module():
    sys.path.insert(0, str(REPO / 'tools' / 'art'))
    import asset_ledger
    return asset_ledger


def update_asset_ledger(ctx, plan, today):
    """The unified ledger (tools/art/asset_ledger.py); skipped when the repository has none."""
    if not ctx.asset_ledger_path.is_file():
        return False
    al = asset_ledger_module()
    text, doc = read_doc(ctx.asset_ledger_path)
    entries = doc.setdefault('assets', [])
    for f in plan['files']:
        rel = f['dest_rel'][len('chapter1/art/'):]
        fields = f['fields']
        pack = fields.get('pack', UNKNOWN)
        entry = {'path': rel}
        entry.update(al.file_facts(ctx.root, rel))
        entry.update({
            'source_type': 'third_party_derived',
            'creator': fields.get('creator') or ('%s 팩 수록 원음' % pack if fields else UNKNOWN + ': 후보 목록에 제작자 없음'),
            'origin': fields.get('source') or UNKNOWN + ': 후보 목록에 출처 없음(audio_adopt)',
            'license': fields.get('license') or UNKNOWN + ': 후보 목록에 라이선스 없음',
            'date': fields.get('date') or today,
            'postprocess': fields.get('method') or fields.get('processing') or UNKNOWN + ': 가공 기록 없음',
            'record_files': [al.record_ref(ctx.root, AUDIO_LEDGER_REL[len('chapter1/art/'):])],
            'release_cleared': False,
            'status': '채택 후보 %s (자리 %s, 스킬 시험실)' % (plan['candidate']['id'], plan['slot'])})
        index = next((i for i, e in enumerate(entries) if e.get('path') == rel), None)
        if index is not None:
            entries[index] = entry
        else:
            at = next((i for i, e in enumerate(entries) if str(e.get('path', '')) > rel), len(entries))
            entries.insert(at, entry)
    atomic_write(ctx.asset_ledger_path, dump_like(text, doc).encode('utf-8'))
    return True


# ----------------------------------------------------------------------------------------------- running the checks

def run(cmd, cwd, timeout):
    try:
        proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, str(exc)
    return proc.returncode, (proc.stdout + proc.stderr).decode('utf-8', 'replace')


def run_import(ctx, plan):
    """python tools/dev/run_dev.py --import-only (once more when the first run leaves no .import: the engine can end early the first time)."""
    runner = ctx.root / 'tools' / 'dev' / 'run_dev.py'
    if not runner.is_file():
        return {'ran': False, 'note': 'no tools/dev/run_dev.py in the root'}
    for attempt in (1, 2):
        code, text = run([sys.executable, str(runner), '--import-only'], ctx.root, 300)
        missing = [f['dest_rel'] for f in plan['files'] if not (ctx.root / (f['dest_rel'] + '.import')).is_file()]
        if not missing:
            return {'ran': True, 'attempts': attempt, 'exit': code, 'missing_import': []}
    return {'ran': True, 'attempts': 2, 'exit': code, 'missing_import': missing, 'tail': text[-400:]}


def run_checks(ctx):
    results = {}
    code, text = run([sys.executable, str(REPO / 'tools' / 'dev' / 'audio_ledger_check.py'), '--dir', str(ctx.root / AUDIO_DIR_REL),
                      '--ledger', str(ctx.audio_ledger_path)], ctx.root, 180)
    results['audio_ledger_check'] = {'exit': code, 'ok': code == 0, 'tail': (text or '').strip().splitlines()[-1:] if text else []}
    if ctx.asset_ledger_path.is_file():
        code, text = run([sys.executable, str(REPO / 'tools' / 'art' / 'asset_ledger.py'), '--root', str(ctx.root), 'check'], ctx.root, 180)
        errors = re.search(r'== 오류[^:\n]*: (\d+)', text or '')
        results['asset_ledger_check'] = {'exit': code, 'errors': int(errors.group(1)) if errors else None, 'ok': code == 0 and bool(errors) and int(errors.group(1)) == 0}
    return results


def git_diff_stat(ctx):
    code, text = run(['git', '-C', str(ctx.root), 'diff', '--stat', '--', MAP_REL, AUDIO_LEDGER_REL, ASSET_LEDGER_REL], ctx.root, 30)
    return text.strip().splitlines() if code == 0 and text else []


# ----------------------------------------------------------------------------------------------- commands

def snapshot(paths):
    return {p: (Path(p).read_bytes() if Path(p).is_file() else None) for p in paths}


def restore(snap, created):
    for path, data in snap.items():
        if data is None:
            Path(path).unlink(missing_ok=True)
        else:
            atomic_write(path, data)
    for path in created:
        Path(path).unlink(missing_ok=True)


def result_line(payload):
    print('AUDIO_ADOPT ' + json.dumps(payload, sort_keys=True))    # ASCII only: the caller may read the pipe in any code page


def cmd_adopt(args):
    ctx = Context(args.root, args.candidates_dir)
    rev_before = ctx.rev()
    if args.expect_rev and args.expect_rev != rev_before:
        raise Refused(EXIT_REV, 'audio_map.json changed since you looked (sha256 now %s)' % rev_before)
    plan = build_plan(ctx, args.slot, args.candidate, args.any_slot)
    summary = {'ok': True, 'slot': plan['slot'], 'candidate': args.candidate, 'rev_before': rev_before, 'parent': plan['parent'],
               'parent_silent_today': plan['parent_silent'], 'adopted_before': plan['adopted_before'],
               'files': [{k: f[k] for k in ('dest_rel', 'sha256', 'size', 'format', 'new')} for f in plan['files']],
               'warnings': plan['warnings'], 'confirm': plan['confirm']}
    if args.dry_run:
        summary.update({'dry_run': True})
        print(plan['confirm'])
        result_line(summary)
        return EXIT_OK
    if not args.yes:
        print(plan['confirm'])
        print('(nothing written; run again with --yes to adopt)')
        summary.update({'ok': False, 'needs_confirm': True})
        result_line(summary)
        return EXIT_CONFIRM
    today = datetime.date.today().isoformat()
    targets = [ctx.map_path, ctx.audio_ledger_path, ctx.asset_ledger_path]
    snap = snapshot(targets)
    created = []
    try:
        for f in plan['files']:
            dest = ctx.root / f['dest_rel']
            if f['new']:
                dest.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(dest, Path(f['source']).read_bytes())
                created.append(dest)
        map_doc = plan['map_doc']
        map_doc.setdefault('adopted', {})[plan['slot']] = {'files': [f['res'] for f in plan['files']], 'candidate': args.candidate, 'date': today}
        atomic_write(ctx.map_path, dump_like(plan['map_text'], map_doc).encode('utf-8'))
        update_audio_ledger(ctx, plan)
        update_asset_ledger(ctx, plan, today)
        imp = {'ran': False, 'note': '--no-import'}
        if not args.no_import:
            before_import = {f['dest_rel'] + '.import' for f in plan['files'] if not (ctx.root / (f['dest_rel'] + '.import')).is_file()}
            imp = run_import(ctx, plan)
            created.extend(ctx.root / rel for rel in before_import if (ctx.root / rel).is_file())
            if imp.get('missing_import'):
                raise Refused(EXIT_CHECK, 'the import left no .import file for: %s' % ', '.join(imp['missing_import']))
        checks = run_checks(ctx)
        failed = [name for name, res in checks.items() if not res['ok']]
        if failed:
            raise Refused(EXIT_CHECK, 'check failed: %s' % ', '.join(failed))
    except Refused as exc:
        restore(snap, created)
        summary.update({'ok': False, 'error': exc.message, 'rolled_back': True})
        result_line(summary)
        print('rolled back: ' + exc.message, file=sys.stderr)
        return exc.code
    except Exception as exc:  # any other failure: the repository is put back as well
        restore(snap, created)
        summary.update({'ok': False, 'error': '%s: %s' % (type(exc).__name__, exc), 'rolled_back': True})
        result_line(summary)
        return EXIT_CHECK
    summary.update({'rev_after': ctx.rev(), 'import': imp, 'checks': checks, 'git_diff_stat': git_diff_stat(ctx), 'adopted_after': map_doc['adopted'][plan['slot']],
                    'style_exact': style_exact(plan['map_text'], json.loads(plan['map_text'].lstrip('﻿')))})
    result_line(summary)
    return EXIT_OK


def cmd_revert(args):
    ctx = Context(args.root, args.candidates_dir)
    rev_before = ctx.rev()
    if args.expect_rev and args.expect_rev != rev_before:
        raise Refused(EXIT_REV, 'audio_map.json changed since you looked (sha256 now %s)' % rev_before)
    map_text, map_doc = ctx.map_doc()
    slot = args.slot
    if not re.fullmatch(r'[a-z0-9_]+(\.[a-z0-9_]+)+', slot or '') or slot not in map_doc['slots']:
        raise Refused(EXIT_INPUT, 'unknown slot: %r' % slot)
    adopted = map_doc.get('adopted', {})
    folder = ctx.root / SLOTS_REL / slot
    on_disk = sorted(p for p in folder.glob('*.wav')) if folder.is_dir() else []
    delete, keep = [], []
    for p in on_disk:
        rel = p.relative_to(ctx.root).as_posix()
        tracked = git_tracked(ctx.root, rel)
        (delete if tracked is False else keep).append(rel)
    summary = {'ok': True, 'slot': slot, 'rev_before': rev_before, 'adopted_before': adopted.get(slot), 'delete': delete, 'keep_tracked_or_unknown': keep}
    if slot not in adopted and not delete:
        summary.update({'nothing_to_do': True})
        result_line(summary)
        return EXIT_OK
    if args.dry_run:
        summary.update({'dry_run': True})
        result_line(summary)
        return EXIT_OK
    adopted.pop(slot, None)
    atomic_write(ctx.map_path, dump_like(map_text, map_doc).encode('utf-8'))
    gone_audio = {r[len(AUDIO_DIR_REL) + 1:] for r in delete}
    gone_asset = {r[len('chapter1/art/'):] for r in delete}
    for ledger_path, key, gone in ((ctx.audio_ledger_path, 'products', gone_audio), (ctx.asset_ledger_path, 'assets', gone_asset)):
        if ledger_path.is_file() and gone:
            text, doc = read_doc(ledger_path)
            doc[key] = [row for row in doc.get(key, []) if row.get('file' if key == 'products' else 'path') not in gone]
            atomic_write(ledger_path, dump_like(text, doc).encode('utf-8'))
    for rel in delete:
        (ctx.root / rel).unlink(missing_ok=True)
        (ctx.root / (rel + '.import')).unlink(missing_ok=True)
    if folder.is_dir() and not any(folder.iterdir()):
        folder.rmdir()
    summary.update({'rev_after': ctx.rev(), 'git_diff_stat': git_diff_stat(ctx)})
    result_line(summary)
    return EXIT_OK


def cmd_list(args):
    ctx = Context(args.root, args.candidates_dir)
    try:
        map_text, map_doc = ctx.map_doc()
    except Refused as exc:
        print('no slot table: ' + exc.message)
        return EXIT_INPUT
    found, problems = ctx.candidates()
    silent = ctx.silent_cues()
    rows = []
    for slot, entry in map_doc['slots'].items():
        taken = map_doc.get('adopted', {}).get(slot)
        parent = str(entry.get('parent', ''))
        now = ('adopted %s' % taken.get('candidate', '?')) if taken else ('silent (parent %s)' % parent if parent in silent else ('parent cue %s' % parent if parent else 'silent (no parent)'))
        rows.append({'slot': slot, 'parent': parent, 'per_targets': int(entry.get('per_targets', 0)), 'now': now,
                     'candidates': [c['id'] for c in found.values() if c['slot'] == slot]})
    unslotted = [c['id'] for c in found.values() if c['slot'] not in map_doc['slots']]
    payload = {'rev': ctx.rev(), 'slots': rows, 'candidates': [{'id': c['id'], 'label': c['label'], 'slot': c['slot'], 'files': len(c['files']), 'by': c['by'],
                                                                'delivered': c['delivered'], 'title': c['title']} for c in found.values()],
               'candidates_without_known_slot': unslotted, 'list_problems': problems}
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return EXIT_OK
    print('audio_map.json sha256 %s' % payload['rev'])
    print('%-26s %-34s %s' % ('slot', 'now', 'candidates'))
    for r in rows:
        print('%-26s %-34s %s' % (r['slot'], r['now'], ' '.join(r['candidates'])))
    print('\ncandidates (%d):' % len(found))
    for c in payload['candidates']:
        print('  %-44s -> %-22s %d files  %s' % (c['id'], c['slot'], c['files'], c['label']))
    if unslotted:
        print('candidates whose slot is not in the table: %s' % ', '.join(unslotted))
    for p in problems:
        print('list problem: ' + p)
    return EXIT_OK


def main(argv=None):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=str(REPO), help='repository folder (default: this one)')
    ap.add_argument('--candidates-dir', help='folder of the lab-candidates.json lists (default <root>/_local/audio)')
    sub = ap.add_subparsers(dest='command', required=True)
    a = sub.add_parser('adopt')
    a.add_argument('--slot', required=True)
    a.add_argument('--candidate', required=True)
    a.add_argument('--expect-rev')
    a.add_argument('--dry-run', action='store_true')
    a.add_argument('--no-import', action='store_true')
    a.add_argument('--yes', action='store_true', help='confirmed (the page asks the user; without it nothing is written)')
    a.add_argument('--any-slot', action='store_true', help='allow a candidate made for another slot')
    r = sub.add_parser('revert')
    r.add_argument('--slot', required=True)
    r.add_argument('--expect-rev')
    r.add_argument('--dry-run', action='store_true')
    ls = sub.add_parser('list')
    ls.add_argument('--json', action='store_true')
    args = ap.parse_args(argv)
    try:
        return {'adopt': cmd_adopt, 'revert': cmd_revert, 'list': cmd_list}[args.command](args)
    except Refused as exc:
        result_line({'ok': False, 'error': exc.message, 'code': exc.code})
        print('refused: ' + exc.message, file=sys.stderr)
        return exc.code


if __name__ == '__main__':
    sys.exit(main())
