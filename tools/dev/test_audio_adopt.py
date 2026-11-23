"""Self-test for audio_adopt.py (T12 skill lab, SL-A), in temporary folders used as the repository (--root).

    python tools/dev/test_audio_adopt.py

Checks adopt / revert / list on a copy of the real audio_map.json and AUDIO-LEDGER.json with small synthetic wavs: the confirm step
(exit 6, nothing written), --dry-run, the files and the `adopted` entry, line ends and untouched lines of audio_map.json,
AUDIO-LEDGER and ASSET-LEDGER rows (unverified when a candidate has no source), --expect-rev (exit 3), a file of the same name with
other content (exit 4), bad candidate paths (a "..", an absolute path, a wrong slot, a file count that does not fit per_targets: exit 2),
revert (the map comes back byte for byte, files and rows are gone), and the player: a headless Godot built on the adopted map
plays the adopted file (c7_3 for three contacts) and the lightning cast is silent again after the revert (needs Godot; skipped
with a notice when it is not there). Exit code 0 when all pass.
"""
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
import audio_adopt as aa

PY = sys.executable
NL, CRLF = chr(10), chr(13) + chr(10)
fails = []
GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))


def check(name, cond, detail=''):
    print('%s  %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


def write_wav(path, freq, seconds=0.12, rate=48000):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b''.join(struct.pack('<h', int(9000 * math.sin(2 * math.pi * freq * i / rate))) for i in range(int(rate * seconds)))
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames)


def adopt_tool(root, *args):
    proc = subprocess.run([PY, str(HERE / 'audio_adopt.py'), '--root', str(root)] + [str(a) for a in args], capture_output=True, text=True, encoding='utf-8', timeout=240)
    line = next((l for l in reversed(proc.stdout.splitlines()) if l.startswith('AUDIO_ADOPT ')), None)
    return proc.returncode, (json.loads(line[len('AUDIO_ADOPT '):]) if line else None), proc.stdout + proc.stderr


def git(root, *args):
    return subprocess.run(['git', '-C', str(root)] + list(args), capture_output=True, text=True, encoding='utf-8', timeout=60)


def build_root(tmp):
    root = tmp / 'repo'
    (root / aa.MAP_REL).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(REPO / aa.MAP_REL, root / aa.MAP_REL)
    # an old sound that is already in the ledgers (the real ledgers are not copied: their files are not here)
    write_wav(root / 'chapter1/art/audio/chain/x1.wav', 333)
    old_sha = aa.sha256_file(root / 'chapter1/art/audio/chain/x1.wav')
    (root / aa.AUDIO_LEDGER_REL).write_bytes(json.dumps({'products': [{'file': 'chain/x1.wav', 'sha256': old_sha, 'pack': 'old', 'source': 'old/source.wav', 'license': 'old'}]}, indent=2).replace(NL, CRLF).encode() + CRLF.encode())
    al = aa.asset_ledger_module()
    entry = dict(al.file_facts(root, 'audio/chain/x1.wav'), path='audio/chain/x1.wav', source_type='third_party_derived', origin='old/source.wav', license='old',
                 date='2026-11-01', postprocess='none', record_files=[], release_cleared=False, status='test')
    (root / aa.ASSET_LEDGER_REL).write_bytes((json.dumps({'schema': 1, 'assets': [entry]}, indent=2) + NL).encode())
    (root / 'chapter1' / 'presentation').mkdir(parents=True)
    shutil.copyfile(REPO / aa.PLAYER_REL, root / aa.PLAYER_REL)
    shutil.copyfile(REPO / 'chapter1/presentation/audio_routes.gd', root / 'chapter1/presentation/audio_routes.gd')
    base = root / '_local' / 'audio' / 'test-round'
    files = []
    for i, freq in ((1, 440), (2, 660), (3, 880)):
        write_wav(base / 'assets' / ('c7_%d.wav' % i), freq)
        files.append('assets/c7_%d.wav' % i)
    for i, freq in ((1, 300), (2, 500), (3, 700)):    # a candidate with no source rows
        write_wav(base / 'assets' / ('n9_%d.wav' % i), freq)
    write_wav(base / 'assets' / 'other_1.wav', 1000)
    write_wav(base / 'clash' / 'assets' / 'c7_1.wav', 1234)    # same destination name as C7's first file, other content
    write_wav(base / 'clash' / 'assets' / 'c7_2.wav', 1235)
    write_wav(base / 'clash' / 'assets' / 'c7_3.wav', 1236)
    outside = tmp / 'outside.wav'
    write_wav(outside, 1500)
    rows = [{'file': f, 'pack': 'test-pack', 'source': 'test/source.wav', 'license': 'test licence', 'method': 'sine', 'creator': 'test'} for f in files]
    (base / 'lab-candidates.json').write_text(json.dumps({'schema': 1, 'title': 'test', 'delivered': '2026-11-23', 'by': 'test', 'candidates': [
        {'key': 'C7', 'label': 'test C7', 'slot': 'skill.arc.cast', 'files': files, 'ledger': rows},
        {'key': 'N9', 'label': 'no source', 'slot': 'skill.arc.cast', 'files': ['assets/n9_%d.wav' % i for i in (1, 2, 3)]},
        {'key': 'TWO', 'label': 'two files for a per_targets 3 slot', 'slot': 'skill.arc.cast', 'files': ['assets/n9_1.wav', 'assets/n9_2.wav']},
        {'key': 'UP', 'label': 'path with ..', 'slot': 'skill.arc.cast', 'files': ['../../../../outside.wav'] + ['assets/n9_2.wav', 'assets/n9_3.wav']},
        {'key': 'ABS', 'label': 'absolute path', 'slot': 'skill.arc.cast', 'files': [str(outside).replace('\\', '/'), 'assets/n9_2.wav', 'assets/n9_3.wav']},
        {'key': 'WRONG', 'label': 'made for the ember cast', 'slot': 'skill.ember.cast', 'files': ['assets/other_1.wav']},
        {'key': 'OTHER', 'label': 'one take, a variant slot', 'slot': 'skill.ember.hit', 'files': ['assets/other_1.wav']}]}), encoding='utf-8')
    (base / 'clash' / 'lab-candidates.json').write_text(json.dumps({'schema': 1, 'title': 'clash', 'delivered': '2026-11-23', 'by': 'test', 'candidates': [
        {'key': 'C7', 'label': 'same file names, other content', 'slot': 'skill.arc.cast', 'files': ['assets/c7_%d.wav' % i for i in (1, 2, 3)]}]}), encoding='utf-8')
    git(root, 'init', '-q')
    git(root, 'config', 'user.email', 't@example.invalid')
    git(root, 'config', 'user.name', 'test')
    (root / '.gitignore').write_text('_local/\n', encoding='utf-8')
    git(root, 'add', '.')
    git(root, 'commit', '-q', '-m', 'base')
    return root


def lines_changed(before, after):
    a, b = before.split('\n'), after.split('\n')
    return sum(1 for x, y in zip(a, b) if x != y) + abs(len(a) - len(b))


def play_probe(root, args):
    """Headless Godot on a copy of the project parts the player needs; returns the AUDIO_SLOTS_PROBE json."""
    proj = root.parent / 'godot-project'
    if proj.exists():
        shutil.rmtree(proj)
    (proj / 'chapter1' / 'presentation').mkdir(parents=True)
    (proj / 'chapter1' / 'data').mkdir(parents=True)
    (proj / 'tools' / 'dev').mkdir(parents=True)
    (proj / 'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="adopt-test"\n', encoding='utf-8')
    for name in ('combat_audio.gd', 'audio_routes.gd'):
        shutil.copyfile(root / 'chapter1' / 'presentation' / name, proj / 'chapter1' / 'presentation' / name)
    shutil.copyfile(root / aa.MAP_REL, proj / aa.MAP_REL)
    shutil.copytree(REPO / 'chapter1' / 'art' / 'quality03_audio', proj / 'chapter1' / 'art' / 'quality03_audio', ignore=shutil.ignore_patterns('*.import'))
    if (root / aa.SLOTS_REL).is_dir():
        shutil.copytree(root / aa.SLOTS_REL, proj / aa.SLOTS_REL)
    shutil.copyfile(HERE / 'audio_slots_probe.gd', proj / 'tools' / 'dev' / 'audio_slots_probe.gd')
    cmd = [PY, str(HERE / 'godot.py'), '--headless', '--path', str(proj), '--script', 'res://tools/dev/audio_slots_probe.gd', '--'] + args
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=300)
    line = next((l for l in reversed(proc.stdout.splitlines()) if l.startswith('AUDIO_SLOTS_PROBE ')), None)
    return json.loads(line[len('AUDIO_SLOTS_PROBE '):]) if line else {'error': (proc.stdout + proc.stderr)[-600:]}


def main():
    tmp = Path(tempfile.mkdtemp(prefix='audio-adopt-test-'))
    try:
        root = build_root(tmp)
        map_before = (root / aa.MAP_REL).read_bytes()
        audio_before = (root / aa.AUDIO_LEDGER_REL).read_bytes()
        rev0 = aa.sha256_bytes(map_before)
        check('fixture: audio_map.json is a schema 2 file with CRLF (this is what the tool must keep)', b'"slots"' in map_before and b'\r\n' in map_before)

        code, res, out = adopt_tool(root, 'list', '--json')
        listed = json.loads(out[out.index('{'):out.rindex('}') + 1]) if code == 0 else {}
        ids = {c['id'] for c in listed.get('candidates', [])}
        check('list: candidates and slots are listed, the rev is the sha256 of the map', code == 0 and 'test-round/C7' in ids and 'test-round/clash/C7' in ids and listed.get('rev') == rev0 and len(listed.get('slots', [])) >= 12, 'ids %s' % sorted(ids))
        arc = next((s for s in listed.get('slots', []) if s['slot'] == 'skill.arc.cast'), {})
        check('list: the lightning cast reads "silent" (its parent cue is in SILENT) and shows its candidates', arc.get('now', '').startswith('silent') and 'test-round/C7' in arc.get('candidates', []), arc.get('now', ''))

        # ---- nothing is written without --yes, nor by --dry-run
        code, res, out = adopt_tool(root, 'adopt', '--slot', 'skill.arc.cast', '--candidate', 'test-round/C7', '--no-import')
        check('adopt without --yes: exit 6 and nothing written', code == 6 and (root / aa.MAP_REL).read_bytes() == map_before and not (root / aa.SLOTS_REL).exists())
        check('adopt confirm text says the sound will play in the normal game, and that the lightning cast is silent today',
              '일반 게임에서' in out and '무음' in out and (res or {}).get('parent_silent_today') is True)
        code, res, out = adopt_tool(root, 'adopt', '--slot', 'skill.arc.cast', '--candidate', 'test-round/C7', '--dry-run')
        check('adopt --dry-run: exit 0, plan with 3 files, nothing written', code == 0 and res and len(res['files']) == 3 and (root / aa.MAP_REL).read_bytes() == map_before and not (root / aa.SLOTS_REL).exists())

        # ---- bad input
        for name, args, want in (
                ('a candidate file path with ".." out of the allowed folders', ['--slot', 'skill.arc.cast', '--candidate', 'test-round/UP'], 2),
                ('an absolute candidate file path', ['--slot', 'skill.arc.cast', '--candidate', 'test-round/ABS'], 2),
                ('a candidate made for another slot', ['--slot', 'skill.arc.cast', '--candidate', 'test-round/WRONG'], 2),
                ('two files for a per_targets 3 slot', ['--slot', 'skill.arc.cast', '--candidate', 'test-round/TWO'], 2),
                ('an unknown slot', ['--slot', 'skill.nothing.cast', '--candidate', 'test-round/C7'], 2),
                ('a slot name with ".."', ['--slot', '..\\..\\evil', '--candidate', 'test-round/C7'], 2),
                ('an unknown candidate', ['--slot', 'skill.arc.cast', '--candidate', 'test-round/NOPE'], 2)):
            code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', *args)
            check('refused (exit 2): ' + name, code == want and (root / aa.MAP_REL).read_bytes() == map_before and not (root / aa.SLOTS_REL).exists(), 'exit %s' % code)

        # ---- --expect-rev
        code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', '--slot', 'skill.arc.cast', '--candidate', 'test-round/C7', '--expect-rev', '0' * 64)
        check('adopt with a wrong --expect-rev: exit 3 and nothing written', code == 3 and (root / aa.MAP_REL).read_bytes() == map_before and not (root / aa.SLOTS_REL).exists())

        # ---- the adoption
        code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', '--slot', 'skill.arc.cast', '--candidate', 'test-round/C7', '--expect-rev', rev0)
        check('adopt: exit 0, ok, checks passed', code == 0 and res and res['ok'] and all(c['ok'] for c in res['checks'].values()), json.dumps((res or {}).get('checks')) + ' ' + str((res or {}).get('error')))
        dest = root / aa.SLOTS_REL / 'skill.arc.cast'
        check('adopt: three files copied byte for byte', sorted(p.name for p in dest.glob('*.wav')) == ['c7_1.wav', 'c7_2.wav', 'c7_3.wav'] and
              all((dest / ('c7_%d.wav' % i)).read_bytes() == (root / ('_local/audio/test-round/assets/c7_%d.wav' % i)).read_bytes() for i in (1, 2, 3)))
        map_after = (root / aa.MAP_REL).read_bytes().decode('utf-8')
        doc = json.loads(map_after)
        taken = doc.get('adopted', {}).get('skill.arc.cast', {})
        check('adopt: the adopted entry has the three res:// files, the candidate id and a date',
              taken.get('files') == ['res://chapter1/art/audio/slots/skill.arc.cast/c7_%d.wav' % i for i in (1, 2, 3)] and taken.get('candidate') == 'test-round/C7' and len(taken.get('date', '')) == 10, str(taken))
        check('audio_map.json keeps its CRLF line ends and changes only the adopted place', '\r\n' in map_after and map_after.count('\n') == map_after.count('\r\n') and
              map_after.startswith(map_before.decode('utf-8').split('"adopted"')[0]) and lines_changed(map_before.decode('utf-8'), map_after) <= 16 and doc['chain_lightning'] == json.loads(map_before)['chain_lightning'] and doc['slots'] == json.loads(map_before)['slots'])
        led = json.loads((root / aa.AUDIO_LEDGER_REL).read_bytes())
        row = next((p for p in led['products'] if p['file'] == 'slots/skill.arc.cast/c7_1.wav'), {})
        check('AUDIO-LEDGER: a row per file with the sha256 and the list\'s source fields', len([p for p in led['products'] if p['file'].startswith('slots/')]) == 3 and
              row.get('sha256') == aa.sha256_file(dest / 'c7_1.wav') and row.get('source') == 'test/source.wav' and row.get('pack') == 'test-pack' and row.get('adopted_from') == 'test-round/C7')
        check('AUDIO-LEDGER keeps its CRLF and its old rows', b'\r\n' in (root / aa.AUDIO_LEDGER_REL).read_bytes() and led['products'][:1] == json.loads(audio_before)['products'])
        assets = json.loads((root / aa.ASSET_LEDGER_REL).read_bytes())['assets']
        check('ASSET-LEDGER: a row per file under audio/slots/', sorted(a['path'] for a in assets) == ['audio/chain/x1.wav'] + ['audio/slots/skill.arc.cast/c7_%d.wav' % i for i in (1, 2, 3)] and
              all(a['sha256'] and a['origin'] == 'test/source.wav' for a in assets if 'slots' in a['path']))
        check('the result lists a new sha256 of the map (the page uses it as map_rev)', res and res['rev_before'] == rev0 and res['rev_after'] == aa.sha256_bytes((root / aa.MAP_REL).read_bytes()) and res['rev_after'] != rev0)

        # ---- the same file names with other content are refused (exit 4), and nothing changes
        snapshot = (root / aa.MAP_REL).read_bytes()
        code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', '--slot', 'skill.arc.cast', '--candidate', 'test-round/clash/C7')
        check('a file of the same name with other content: exit 4, nothing written', code == 4 and (root / aa.MAP_REL).read_bytes() == snapshot, 'exit %s' % code)
        code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', '--slot', 'skill.arc.cast', '--candidate', 'test-round/C7')
        check('adopting the same candidate again changes nothing that matters (same files accepted)', code == 0 and res and json.loads((root / aa.MAP_REL).read_bytes())['adopted']['skill.arc.cast']['candidate'] == 'test-round/C7')

        # ---- the player on the adopted map
        if GODOT.is_file():
            probe = play_probe(root, ['--mode=play', '--cue=lightning', '--slot=skill.arc.cast', '--targets=3'])
            check('player: the lightning cast with three contacts plays the adopted third file (c7_3) although the cue is silent today',
                  probe.get('played') == 1 and probe.get('adopted_index') == 2 and probe.get('voice', -1) >= 1 and
                  probe.get('adopted_paths', [''])[-1].endswith('c7_3.wav') and not probe.get('map_errors'), json.dumps(probe)[:300])
            probe1 = play_probe(root, ['--mode=play', '--cue=lightning', '--slot=skill.arc.cast', '--targets=1'])
            check('player: one contact plays the first file; the same request without the slot stays silent',
                  probe1.get('adopted_index') == 0 and play_probe(root, ['--mode=play', '--cue=lightning']).get('played') == 0, json.dumps(probe1)[:200])
            probe2 = play_probe(root, ['--mode=routes'])
            check('player: every slot a route makes is in the table with the cue of its parent', probe2.get('missing_in_table') == [] and probe2.get('parent_not_cue') == [] and probe2.get('table_slots_no_event') == [], json.dumps(probe2)[:300])
        else:
            print('SKIP  player checks: Godot not found (%s)' % GODOT)

        # ---- no source in the list: unverified
        code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', '--slot', 'skill.arc.cast', '--candidate', 'test-round/N9')
        led = json.loads((root / aa.AUDIO_LEDGER_REL).read_bytes())
        row = next((p for p in led['products'] if p['file'] == 'slots/skill.arc.cast/n9_1.wav'), {})
        check('a candidate without source rows: AUDIO-LEDGER origin "unverified" (the check allows it), ASSET-LEDGER hole "미확인"',
              code == 0 and row.get('origin') == 'unverified' and any(a['origin'].startswith('미확인') for a in json.loads((root / aa.ASSET_LEDGER_REL).read_bytes())['assets'] if 'n9_1' in a['path']))

        # ---- revert: the map comes back byte for byte
        code, res, out = adopt_tool(root, 'revert', '--slot', 'skill.arc.cast', '--dry-run')
        check('revert --dry-run lists the untracked files and writes nothing', code == 0 and res and len(res['delete']) == 6 and (dest / 'c7_1.wav').is_file())
        code, res, out = adopt_tool(root, 'revert', '--slot', 'skill.arc.cast', '--expect-rev', '0' * 64)
        check('revert with a wrong --expect-rev: exit 3', code == 3 and (dest / 'c7_1.wav').is_file())
        code, res, out = adopt_tool(root, 'revert', '--slot', 'skill.arc.cast')
        check('revert: adopted entry gone, files and ledger rows gone', code == 0 and not dest.exists() and json.loads((root / aa.MAP_REL).read_bytes()).get('adopted') == {} and
              not [p for p in json.loads((root / aa.AUDIO_LEDGER_REL).read_bytes())['products'] if p['file'].startswith('slots/')] and [a['path'] for a in json.loads((root / aa.ASSET_LEDGER_REL).read_bytes())['assets']] == ['audio/chain/x1.wav'])
        check('revert: audio_map.json and AUDIO-LEDGER.json are the original bytes again', (root / aa.MAP_REL).read_bytes() == map_before and (root / aa.AUDIO_LEDGER_REL).read_bytes() == audio_before)
        if GODOT.is_file():
            check('player: after the revert the lightning cast is silent again', play_probe(root, ['--mode=play', '--cue=lightning', '--slot=skill.arc.cast', '--targets=3']).get('played') == 0)
        code, res, out = adopt_tool(root, 'revert', '--slot', 'skill.arc.cast')
        check('revert of a slot with nothing adopted: exit 0, nothing to do', code == 0 and res and res.get('nothing_to_do'))

        # ---- committed files are kept by revert
        code, res, out = adopt_tool(root, 'adopt', '--yes', '--no-import', '--slot', 'skill.ember.hit', '--candidate', 'test-round/OTHER')
        git(root, 'add', '-A', '--force')
        git(root, 'commit', '-q', '-m', 'adopted')
        code, res, out = adopt_tool(root, 'revert', '--slot', 'skill.ember.hit')
        check('revert keeps files git already tracks (only the adopted entry goes)', code == 0 and (root / aa.SLOTS_REL / 'skill.ember.hit' / 'other_1.wav').is_file() and json.loads((root / aa.MAP_REL).read_bytes()).get('adopted') == {})
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('\n%d failed' % len(fails) if fails else '\nall passed')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
