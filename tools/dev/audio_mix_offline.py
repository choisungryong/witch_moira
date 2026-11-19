"""Offline mix of a recorded run: applies today's player rules to a request log and renders a WAV.

    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_audio_requests.gd -- --seed=11 --primary=chapter1.skill.ember --out=_local/audio/requests/req_ember.json
    python tools/dev/audio_mix_offline.py _local/audio/requests/req_ember.json --best-window 10 --out _local/audio/mix/crowd_ember_10s.wav
    python tools/dev/audio_mix_offline.py REQ.json --start 120 --seconds 10 --gain-db 15 --out x.wav
    python tools/dev/audio_mix_offline.py REQ.json --stats            # per sound: requested / played / skipped, no render

Rules are read from chapter1/presentation/combat_audio.gd so they follow the product code: COUNTS (variants, taken in
turn), COOLDOWNS (ticks), GAINS, MAX_VOICES (13; voice 0 = ambience loop; one-shots use voices 1..10, and the
critical cues hurt/drop/equip/pickup/jewel/legend also 11..12), pitch .97/1.0/1.035 by variant (the new run_spells names in DIRS:
PITCH_STEPS, one step per play), voice gain master 0.8 * 0.11 * gain * the call's gain_db (6th column of a request row; none = 0)
(ambience 0.8 * 0.025). A request for a name without files (not in COUNTS) is counted as no_file_skip and makes no sound. A voice stays busy for file length / pitch seconds. A request while the
run is not "playing" is dropped unless it is a UI cue. Playback is linear-interpolated resampling (as the engine does for
pitch_scale). The master bus has no limiter today, so the sum is written as is (clipping is counted, not hidden).
Model limits: time is tick/60 (ticks do not advance in the choice screen), the player's real pause is not modelled, no
audio device is involved, so this says nothing about what a speaker would do.
"""
import argparse, json, re, sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_measure as am

REPO = Path(__file__).resolve().parents[2]
SR = 48000
CRITICAL = ('hurt', 'drop', 'equip', 'pickup', 'jewel', 'legend')


def parse_rules(player=am.PLAYER):
    text = Path(player).read_text(encoding='utf-8')
    def table(name):
        body = re.search(r'const %s\s*:?=\s*\{(.*?)\}' % name, text, re.S).group(1)
        return {k: float(v) for k, v in re.findall(r'"(\w+)"\s*:\s*([\d.]+)', body)}
    # pitch of the old sounds: by variant number (PITCHES; older player files wrote the list inside the voice.pitch_scale line)
    m = re.search(r'const PITCHES\s*:?=\s*\[([^\]]*)\]', text) or re.search(r'voice\.pitch_scale\s*=\s*\[([^\]]*)\]', text)
    pitches = [float(v) for v in m.group(1).split(',')]
    # AU-RS1: the sounds listed in DIRS (the new run_spells names) take their pitch from PITCH_STEPS, one step per play, apart
    # from the variant number. A player file without these constants has no such sounds.
    steps = re.search(r'const PITCH_STEPS\s*:?=\s*\[([^\]]*)\]', text)
    dirs = re.search(r'const DIRS\s*:?=\s*\{(.*?)\}', text, re.S)
    return {
        'pitch_steps': [float(v) for v in steps.group(1).split(',')] if steps else [],
        'stepped': re.findall(r'"(\w+)"\s*:', dirs.group(1)) if dirs else [],
        'counts': {k: int(v) for k, v in table('COUNTS').items()}, 'cooldowns': {k: int(v) for k, v in table('COOLDOWNS').items()},
        'gains': table('GAINS'), 'max_voices': int(re.search(r'const MAX_VOICES\s*:?=\s*(\d+)', text).group(1)),
        'master': float(re.search(r'var master_volume\s*:?=\s*([\d.]+)', text).group(1)), 'pitches': pitches,
        'one_shot_gain': float(re.search(r'\.11\b', text).group()),
        'ambience_gain': float(re.search(r'\.025\b', text).group()),
        # cues that make no sound until replaced (combat_audio.gd SILENT); the game returns before cooldown and voice
        'silent': re.findall(r'"(\w+)"', (re.search(r'const SILENT\b[^=]*=\s*\[([^\]]*)\]', text) or [None, ''])[1]),
    }


def load_sources(rules, audio_dir=am.DEFAULT_DIR):
    src = {}
    for cue, n in rules['counts'].items():
        src[cue] = [am.read_wav(Path(audio_dir) / ('%s_%d.wav' % (cue, i)))[0].mean(axis=1) for i in range(n)]
    src['ambience'] = [am.read_wav(Path(audio_dir) / 'ambience.wav')[0].mean(axis=1)]
    return src


def simulate(requests, rules, src):
    """requests: [tick, cue, ui, playing, source...]. Returns (played events, per-cue stats).
    A played event: dict(t, cue, variant, pitch, voice, len_s, gain)."""
    voice_end = [-1.0] * rules['max_voices']
    last_tick, variants, pitch_turn = {}, {}, {}
    stats, played = {}, []
    for req in sorted(requests, key=lambda r: r[0]):  # stable: keeps the recorded order inside a tick
        tick, cue, ui, playing = int(req[0]), req[1], int(req[2]), int(req[3])
        # 6th column (AU-RS1, only in logs of a run_spells run): this call's own trim in dB; older logs have none = 0
        gain_db = float(req[5]) if len(req) > 5 and isinstance(req[5], (int, float)) else 0.0
        st = stats.setdefault(cue, {'requested': 0, 'paused_skip': 0, 'cooldown_skip': 0, 'no_voice': 0, 'played': 0})
        st['requested'] += 1
        if cue in rules.get('silent', ()):
            st['silent_skip'] = st.get('silent_skip', 0) + 1
            continue
        if cue not in rules['counts']:
            # a name without files: the game has no stream for it and returns before cooldown and voice (combat_audio.gd _play_cue)
            st['no_file_skip'] = st.get('no_file_skip', 0) + 1
            continue
        if not playing and not ui:
            st['paused_skip'] += 1
            continue
        if tick - last_tick.get(cue, -100000) < rules['cooldowns'][cue]:
            st['cooldown_skip'] += 1
            continue
        now = tick / 60.0
        end = rules['max_voices'] if cue in CRITICAL else rules['max_voices'] - 2
        for i in range(1, end):
            if voice_end[i] > now:
                continue
            variant = variants.get(cue, 0) % rules['counts'][cue]
            variants[cue] = variant + 1
            if cue in rules.get('stepped', ()) and rules.get('pitch_steps'):
                pitch = rules['pitch_steps'][pitch_turn.get(cue, 0) % len(rules['pitch_steps'])]
                pitch_turn[cue] = pitch_turn.get(cue, 0) + 1
            else:
                pitch = rules['pitches'][variant % len(rules['pitches'])]
            length = len(src[cue][variant]) / SR
            voice_end[i] = now + length / pitch
            gain = rules['master'] * rules['one_shot_gain'] * rules['gains'][cue] * (10 ** (gain_db / 20) if gain_db else 1.0)
            played.append({'t': now, 'cue': cue, 'variant': variant, 'pitch': pitch, 'voice': i, 'len_s': length / pitch, 'gain': gain})
            st['played'] += 1
            last_tick[cue] = tick
            break
        else:
            st['no_voice'] += 1
    return played, stats


def render(played, rules, src, t0, seconds, ambience=True):
    n = int(round(seconds * SR))
    out = np.zeros(n)
    if ambience:
        amb = src['ambience'][0]
        pos = (int(round(t0 * SR)) + np.arange(n)) % len(amb)
        out += amb[pos] * rules['master'] * rules['ambience_gain']
    for e in played:
        if e['t'] >= t0 + seconds or e['t'] + e['len_s'] <= t0:
            continue
        s = src[e['cue']][e['variant']]
        m = int(len(s) / e['pitch'])
        wave = np.interp(np.arange(m) * e['pitch'], np.arange(len(s)), s) * e['gain']
        a = int(round((e['t'] - t0) * SR))
        lo, hi = max(a, 0), min(a + m, n)
        if hi > lo:
            out[lo:hi] += wave[lo - a:hi - a]
    return out


def best_window(requests, total_ticks, seconds=10, from_fraction=2 / 3):
    """Start second of the window (start >= from_fraction of the run) with the most requests that the player would see."""
    total_s = total_ticks / 60.0
    per = {}
    for r in requests:
        if int(r[3]) or int(r[2]):
            per[int(r[0]) // 60] = per.get(int(r[0]) // 60, 0) + 1
    first = int(total_s * from_fraction)
    best, best_n = first, -1
    for s in range(first, max(first, int(total_s) - seconds) + 1):
        n = sum(per.get(k, 0) for k in range(s, s + seconds))
        if n > best_n:
            best, best_n = s, n
    return best, best_n


def load_log(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def describe(x):
    """Measurements of a rendered mix (mono float)."""
    m = x[:, None]
    lufs_i, mmax = am.loudness(m, SR)
    return {'seconds': round(len(x) / SR, 2), 'peak_dbfs': round(am.db(float(np.abs(x).max())), 2), 'true_peak_dbtp': round(am.true_peak_db(m), 2),
            'lufs_i': None if lufs_i is None else round(lufs_i, 1), 'momentary_max_lufs': round(mmax, 1), 'samples_over_full_scale': int(np.sum(np.abs(x) >= 1.0))}


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('log', help='request log JSON from report_audio_requests.gd')
    ap.add_argument('--out', help='output WAV (48 kHz 16-bit mono)')
    ap.add_argument('--start', type=float, help='window start, seconds of run time')
    ap.add_argument('--seconds', type=float, default=10.0)
    ap.add_argument('--best-window', type=float, metavar='SECONDS', help='pick the busiest window of this length in the last third of the run')
    ap.add_argument('--gain-db', type=float, default=0.0)
    ap.add_argument('--no-ambience', action='store_true')
    ap.add_argument('--stats', action='store_true', help='print per-sound request/played counts for the whole run')
    args = ap.parse_args()
    log = load_log(args.log)
    rules = parse_rules()
    src = load_sources(rules)
    played, stats = simulate(log['requests'], rules, src)
    if args.stats or not args.out:
        print('%s seed %s %s: %.0f s, %d requests, %d played' % (Path(args.log).name, log['seed'], log['primary'], log['seconds'], len(log['requests']), len(played)))
        for cue, st in sorted(stats.items(), key=lambda kv: -kv[1]['requested']):
            print('  %-10s %s' % (cue, st))
    if args.out:
        if args.best_window:
            t0, n = best_window(log['requests'], log['ticks'], int(args.best_window))
            seconds = args.best_window
            print('best window: %d..%d s (%d requests)' % (t0, t0 + seconds, n))
        else:
            t0, seconds = args.start or 0.0, args.seconds
        x = render(played, rules, src, float(t0), seconds, not args.no_ambience) * 10 ** (args.gain_db / 20)
        clipped = am.write_wav(args.out, x, SR)
        print(args.out, json.dumps(describe(x)), 'clipped on write: %d' % clipped)
    return 0


if __name__ == '__main__':
    sys.exit(main())
