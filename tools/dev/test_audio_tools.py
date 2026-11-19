"""Self-test for audio_scene_audition.py, audio_ledger_check.py and the SILENT reading of audio_mix_offline.py, with small synthetic sounds.

    python tools/dev/test_audio_tools.py

Builds a one-second fake capture (ffmpeg test pattern), a request log and candidate sounds under a temporary folder, then checks:
rules come from the player file (cooldown, SILENT), a changed player file changes the result, blind order and answer key,
loudness policies, the ledger check's findings and exit codes. Needs ffmpeg for the video step. Exit code 0 when all pass.
"""
import hashlib, json, random, re, shutil, subprocess, sys, tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import audio_measure as am
import audio_mix_offline as mo
import audio_audition as ad

REPO = HERE.parents[1]
PY = sys.executable
fails = []


def check(name, cond, detail=''):
    print('%s  %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


def run(args):
    p = subprocess.run([PY] + [str(a) for a in args], capture_output=True, text=True, encoding='utf-8')
    return p.returncode, p.stdout + p.stderr


def tone(path, hz, seconds=0.3, amp=0.5):
    t = np.arange(int(48000 * seconds)) / 48000
    x = amp * np.sin(2 * np.pi * hz * t) * np.exp(-6 * t)
    am.write_wav(path, x, 48000)


def main():
    tmp = Path(tempfile.mkdtemp()) / '_local' / 'selftest'
    try:
        cap = tmp / 'capture'
        (cap / 'frames').mkdir(parents=True)
        r = subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=60', '-frames:v', '60', str(cap / 'frames/f%05d.jpg')],
                           capture_output=True, text=True)
        have_ffmpeg = r.returncode == 0
        rows = [{'f': i, 'tick': 1000 + i, 'mode': 'playing', 'events': ([{'type': 'hit'}] if i == 30 else [{'type': 'hero_hit'}] if i == 40 else [])} for i in range(60)]
        (cap / 'events.json').write_text(json.dumps({'primary': 'x', 'from': 1000, 'frames': 60, 'rows': rows}), encoding='utf-8')
        req = {'seed': 1, 'primary': 'x', 'ticks': 2000, 'seconds': 33.0, 'requests': [
            [1000, 'fire', 0, 1, 'cast'], [1005, 'fire', 0, 1, 'cast'], [1010, 'fire', 0, 1, 'cast'],
            [1020, 'lightning', 0, 1, 'cast'], [1030, 'impact', 0, 1, 'hit'], [1040, 'hurt', 0, 0, 'paused']]}
        (tmp / 'req.json').write_text(json.dumps(req), encoding='utf-8')
        for i in range(3):
            tone(tmp / ('fire_%d.wav' % i), 300 + 100 * i)
        tone(tmp / 'light.wav', 900)
        (tmp / 'cands.json').write_text(json.dumps({'title': 'selftest', 'level_match': 'game', 'candidates': [
            {'id': 'A', 'label': 'A tones', 'files': {'fire': ['fire_0.wav', 'fire_1.wav', 'fire_2.wav'], 'lightning': ['light.wav']}}]}), encoding='utf-8')

        base_args = [HERE / 'audio_scene_audition.py', cap, '--requests', tmp / 'req.json', '--candidates', tmp / 'cands.json']
        code, text = run(base_args + ['--out', tmp / 'o1', '--no-video'])
        check('scene tool runs', code == 0, text[-200:] if code else '')
        m = json.loads((tmp / 'o1/measure.json').read_text(encoding='utf-8'))
        vids = {v['id']: v for v in m['videos']}
        check('alignment matches (hit events == impact requests)', m['alignment']['ok'], str(m['alignment']['notes']))
        check('cooldown from player file: fire 3 requests -> 2 played (COOLDOWNS fire=10)', vids['0']['played_in_window'].get('fire') == 2, str(vids['0']['played_in_window']))
        check('SILENT cue lightning makes no sound (baseline and candidate)', 'lightning' not in vids['0']['played_in_window'] and 'lightning' not in vids['A']['played_in_window'],
              str(vids['A']['played_in_window']))
        check('paused request dropped (hurt)', 'hurt' not in vids['0']['played_in_window'])
        check('candidate files used and level-matched', len(vids['A']['candidate_files']['cues']['fire']) == 3 and vids['A']['candidate_files']['warnings'] == ['lightning is SILENT in the game: its files are not played'],
              str(vids['A']['candidate_files']['warnings']))
        check('true peak at or under -1 dBTP, nothing clipped', all(v['true_peak_dbtp'] <= -0.95 and v['clipped'] == 0 for v in m['videos']), str([v['true_peak_dbtp'] for v in m['videos']]))
        check('common loudness: one gain for all', len({v['gain_db'] for v in m['videos']}) == 1, str([v['gain_db'] for v in m['videos']]))
        ans = (tmp / 'o1/answers.ko.txt').read_text(encoding='utf-8')
        check('blind: send/ has numbers only, answers name both candidates', sorted(p.name for p in (tmp / 'o1/send').glob('*.wav')) == ['01.wav', '02.wav'] and '= 0 (' in ans and '= A (' in ans)
        check('answer key not inside send/', not any(' = A (' in p.read_text(encoding='utf-8') for p in (tmp / 'o1/send').glob('*.txt')))

        # per-candidate unsilence + level_ref: only that candidate's video lets the SILENT cue sound, at the referenced cue's level
        (tmp / 'cands_u.json').write_text(json.dumps({'title': 'selftest', 'level_match': 'game', 'candidates': [
            {'id': 'U', 'label': 'U', 'unsilence': ['lightning'], 'level_ref': {'lightning': 'fire'}, 'level_offset_db': {'lightning': -6}, 'files': {'lightning': ['light.wav']}},
            {'id': 'V', 'label': 'V', 'files': {'lightning': ['light.wav']}}]}), encoding='utf-8')
        code, text = run([HERE / 'audio_scene_audition.py', cap, '--requests', tmp / 'req.json', '--candidates', tmp / 'cands_u.json', '--out', tmp / 'o1u', '--no-video'])
        mu = json.loads((tmp / 'o1u/measure.json').read_text(encoding='utf-8'))
        vu = {v['id']: v for v in mu['videos']}
        check('unsilence: lightning sounds in U only (baseline and V stay SILENT)', code == 0 and vu['U']['played_in_window'].get('lightning') == 1
              and 'lightning' not in vu['0']['played_in_window'] and 'lightning' not in vu['V']['played_in_window'], str({k: v['played_in_window'] for k, v in vu.items()}))
        gu, gv = vu['U']['candidate_files']['cues']['lightning'][0], vu['V']['candidate_files']['cues']['lightning'][0]
        check('level_ref + offset: U lightning level = fire level - 6 dB, differs from own-cue match', gu.get('level_ref') == 'fire' and abs(gu['gain_db'] - gv['gain_db']) > 0.5, '%s %s' % (gu, gv))
        check('unsilenced candidate has no SILENT warning, the other does', vu['U']['candidate_files']['warnings'] == [] and len(vu['V']['candidate_files']['warnings']) == 1)

        # a different player file must change the result: proves the rules are read, not copied
        player = tmp / 'combat_audio.gd'
        text_gd = (REPO / 'chapter1/presentation/combat_audio.gd').read_text(encoding='utf-8')
        edited, n = re.subn(r'("fire":)10,', r'\g<1>3,', text_gd, count=1)
        player.write_text(edited, encoding='utf-8')
        code, text = run(base_args + ['--out', tmp / 'o2', '--no-video', '--player', player])
        m2 = json.loads((tmp / 'o2/measure.json').read_text(encoding='utf-8'))
        v2 = {v['id']: v for v in m2['videos']}
        check('player file edited (COOLDOWNS fire 10 -> 3): fire plays 3', n == 1 and code == 0 and v2['0']['played_in_window'].get('fire') == 3, str(v2['0']['played_in_window']))
        player.write_text(re.sub(r'const SILENT: Array\[String\] = \[[^\]]*\]', 'const SILENT: Array[String] = []', text_gd), encoding='utf-8')
        code, text = run(base_args + ['--out', tmp / 'o3', '--no-video', '--player', player])
        m3 = json.loads((tmp / 'o3/measure.json').read_text(encoding='utf-8'))
        check('SILENT emptied in the player file: lightning plays', {v['id']: v for v in m3['videos']}['0']['played_in_window'].get('lightning') == 1)

        code, text = run(base_args + ['--out', tmp / 'o4', '--no-video', '--loudness', 'each', '--open-labels'])
        m4 = json.loads((tmp / 'o4/measure.json').read_text(encoding='utf-8'))
        check('each loudness: every video at target or limited by -1 dBTP', all(abs(v['lufs_i'] + 16) < 0.2 or v['true_peak_dbtp'] > -1.3 for v in m4['videos']), str([(v['lufs_i'], v['true_peak_dbtp']) for v in m4['videos']]))
        check('open labels name files by candidate id', (tmp / 'o4/send/cand_A.wav').is_file())
        code, text = run(base_args + ['--out', 'C:/elsewhere/out', '--no-video'])
        check('refuses an output folder outside _local', code == 2, text[-100:])
        if have_ffmpeg:
            code, text = run(base_args + ['--out', tmp / 'o5'])
            check('videos written (blind, one per candidate)', code == 0 and sorted(p.name for p in (tmp / 'o5/send').glob('*.mp4')) == ['01.mp4', '02.mp4'] and all(p.stat().st_size > 1000 for p in (tmp / 'o5/send').glob('*.mp4')))
        else:
            print('SKIP  video step: ffmpeg not available')

        # P1 blind order is unchanged by the extraction (same algorithm, same rng use)
        a = ad.BLIND_POOL + ad.BLIND_REPEATS
        b = list(a)
        r1, r2 = random.Random(20261117), random.Random(20261117)
        while True:
            r1.shuffle(a)
            if all(x != y for x, y in zip(a, a[1:])):
                break
        check('blind_order equals the original loop', ad.blind_order(b, r2) == a)

        # mo.simulate honours SILENT
        rules = mo.parse_rules()
        check('parse_rules reads SILENT from combat_audio.gd', 'lightning' in rules['silent'], str(rules['silent']))

        # ledger check
        led = tmp / 'led'
        led.mkdir()
        tone(led / 'a.wav', 440)
        tone(led / 'b.wav', 550)
        tone(led / 'c.wav', 660)

        def sha(n):
            return hashlib.sha256((led / n).read_bytes()).hexdigest()
        (led / 'AUDIO-LEDGER.json').write_text(json.dumps({'creator': 'T', 'products': [
            {'file': 'a.wav', 'sha256': sha('a.wav')}, {'file': 'b.wav', 'sha256': 'f' * 64}, {'file': 'gone.wav', 'sha256': 'e' * 64, 'origin': 'unverified'}]}), encoding='utf-8')
        code, text = run([HERE / 'audio_ledger_check.py', '--dir', led, '--json', tmp / 'led.json'])
        res = json.loads((tmp / 'led.json').read_text(encoding='utf-8'))[0]
        check('ledger: exit 1 with findings', code == 1)
        check('ledger: file without entry c.wav', res['no_entry'] == ['c.wav'])
        check('ledger: hash mismatch b.wav', res['hash_mismatch'] == ['b.wav'])
        check('ledger: entry without file gone.wav', res['entry_without_file'] == ['gone.wav'])
        check('ledger: unverified listed', res['unverified'] == ['gone.wav'])
        (led / 'AUDIO-LEDGER.json').write_text(json.dumps({'creator': 'T', 'files': [
            {'file': n, 'sha256': sha(n)} for n in ('a.wav', 'b.wav', 'c.wav')]}), encoding='utf-8')
        code, text = run([HERE / 'audio_ledger_check.py', '--dir', led])
        check('ledger ("files" format): clean, exit 0', code == 0, text[-80:])
        (led / 'AUDIO-LEDGER.json').write_text(json.dumps({'creator': 'T', 'files': [
            {'file': n, 'sha256': sha(n), 'origin': 'unverified'} for n in ('a.wav', 'b.wav', 'c.wav')]}), encoding='utf-8')
        code_strict = run([HERE / 'audio_ledger_check.py', '--dir', led, '--strict'])[0]
        code_loose = run([HERE / 'audio_ledger_check.py', '--dir', led])[0]
        check('ledger: unverified is a warning, an error with --strict', code_loose == 0 and code_strict == 1)
        (led / 'AUDIO-LEDGER.json').unlink()
        check('ledger: no ledger file -> exit 2', run([HERE / 'audio_ledger_check.py', '--dir', led])[0] == 2)
    finally:
        shutil.rmtree(tmp.parent, ignore_errors=True)
    print('\n%d failed' % len(fails) if fails else '\nall passed')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
