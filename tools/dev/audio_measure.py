"""Sound-file measurement (read only): length, peak, true peak, clipping, loudness, silence, attack/decay, bands, loop seam.

    python tools/dev/audio_measure.py                                   # the 22 files in chapter1/art/quality03_audio
    python tools/dev/audio_measure.py DIR_OR_FILES... --md out.md --json out.json
    python tools/dev/audio_measure.py --compare-s1 docs/specs/S1-audio-direction.ko.md   # check against the table in S1 1.2
    python tools/dev/audio_measure.py --ffmpeg ...                       # add the ffmpeg ebur128 cross-check

Method (same as S1 1.2): own BS.1770-4 K-weighting, 400 ms blocks every 100 ms (a file shorter than 400 ms is
zero-padded to one block), "M max" = loudest block, integrated = gated (-70 abs, -10 rel). True peak = 4x
oversampling (scipy resample_poly). Silence threshold -60 dBFS. Attack = first sample above threshold to the largest
sample. Decay30 = from the 5 ms-RMS envelope peak to the last time it is above peak-30 dB. Bands = Welch
(nperseg min(4096, n)) energy ratios. "In game" = M max + 20log10(0.8 * 0.11 * gain) (ambience 0.8 * 0.025), gains read
from chapter1/presentation/combat_audio.gd. Needs numpy and scipy (not installed by this tool). ffmpeg is optional.
"""
import argparse, json, math, re, subprocess, sys, wave
from pathlib import Path

try:
    import numpy as np
    from scipy import signal
except ImportError as exc:  # pragma: no cover
    raise SystemExit('audio_measure needs numpy and scipy: %s' % exc)

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DIR = REPO / 'chapter1/art/quality03_audio'
PLAYER = REPO / 'chapter1/presentation/combat_audio.gd'
SILENCE_DB = -60.0


def read_wav(path):
    """Returns float64 array (frames, channels) in [-1, 1), sample rate, bits."""
    with wave.open(str(path), 'rb') as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw == 2:
        x = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v >= 1 << 23, v - (1 << 24), v)
        x = v.astype(np.float64) / (1 << 23)
    else:
        raise SystemExit('unsupported sample width %d in %s' % (sw, path))
    return x.reshape(-1, ch), sr, sw * 8


def write_wav(path, x, sr=48000):
    """x: float array (frames,) or (frames, ch); written as 16-bit PCM, clipped. Returns the number of clipped samples."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    scaled = np.round(x * 32768.0)
    clipped = int(np.sum((scaled > 32767) | (scaled < -32768)))
    pcm = np.clip(scaled, -32768, 32767).astype('<i2')
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(pcm.shape[1]); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    return clipped


def kweight(x, sr):
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / sr); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / sr)
    d = 1 + K / Q + K * K
    a2 = [1, 2 * (K * K - 1) / d, (1 - K / Q + K * K) / d]
    y = signal.lfilter(b1, a1, x, axis=0)
    return signal.lfilter([1, -2, 1], a2, y, axis=0)


def loudness(x, sr):
    """Returns (integrated LUFS or None, momentary-max LUFS). x shape (frames, ch)."""
    y = kweight(x, sr)
    block, hop = int(.4 * sr), int(.1 * sr)
    if len(y) < block:
        y = np.vstack([y, np.zeros((block - len(y), y.shape[1]))])
    zs = np.array([np.mean(y[s:s + block] ** 2, axis=0).sum() for s in range(0, len(y) - block + 1, hop)])
    lk = -0.691 + 10 * np.log10(np.maximum(zs, 1e-20))
    g = zs[lk > -70]
    if len(g) == 0:
        return None, float(lk.max())
    rel = -0.691 + 10 * np.log10(g.mean()) - 10
    g2 = zs[(lk > -70) & (lk > rel)]
    return float(-0.691 + 10 * np.log10(g2.mean())), float(lk.max())


def true_peak_db(x):
    return db(float(np.abs(signal.resample_poly(x, 4, 1, axis=0)).max()))


def db(v):
    return float(20 * np.log10(max(v, 1e-12)))


def load_gains():
    """GAINS table from the player script (the source of the in-game offset)."""
    try:
        text = PLAYER.read_text(encoding='utf-8')
        body = re.search(r'const GAINS\s*:?=\s*\{(.*?)\}', text, re.S).group(1)
        return {k: float(v) for k, v in re.findall(r'"(\w+)"\s*:\s*([\d.]+)', body)}
    except (OSError, AttributeError):
        return {}


def ffmpeg_ebur128(path):
    cmd = ['ffmpeg', '-hide_banner', '-nostats', '-i', str(path), '-af', 'apad=pad_dur=1,ebur128=peak=true:framelog=quiet', '-f', 'null', '-']
    try:
        t = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace').stderr
    except OSError:
        return None, None
    i = re.findall(r'I:\s+(-?[\d.]+|-inf) LUFS', t)
    tp = re.findall(r'Peak:\s+(-?[\d.]+|-inf) dBFS', t)
    return (float(i[-1]) if i and i[-1] != '-inf' else None), (float(tp[-1]) if tp and tp[-1] != '-inf' else None)


BANDS = {'lt150': (0, 150), '150_600': (150, 600), '600_2k': (600, 2000), '2k_6k': (2000, 6000), 'gt6k': (6000, None)}


def analyze(x, sr):
    """Measures an in-memory signal (frames, ch). Returns a dict (no file facts, no in-game offset)."""
    m = x.mean(axis=1)
    n = len(m)
    dur = n / sr
    peak = float(np.abs(x).max())
    rms = float(np.sqrt(np.mean(m ** 2)))
    thr = 10 ** (SILENCE_DB / 20)
    above = np.nonzero(np.abs(m) > thr)[0]
    lead = above[0] / sr if len(above) else dur
    trail = (n - 1 - above[-1]) / sr if len(above) else dur
    ipk = int(np.argmax(np.abs(m)))
    attack_ms = (ipk - (above[0] if len(above) else 0)) / sr * 1000
    w = max(1, int(.005 * sr))
    env = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    ie = int(np.argmax(env))
    below = np.nonzero(env[ie:] > env.max() * 10 ** (-30 / 20))[0]
    decay30_ms = (below[-1] / sr * 1000) if len(below) else 0.0
    f, P = signal.welch(m, sr, nperseg=min(4096, n))
    tot = P.sum() or 1e-20
    br = {k: float(P[(f >= a) & (f < (b if b else sr / 2 + 1))].sum() / tot) for k, (a, b) in BANDS.items()}
    centroid = float((f * P).sum() / tot)
    roll85 = float(f[np.searchsorted(np.cumsum(P) / tot, .85)])
    lufs_i, m_max = loudness(x, sr)
    f8, P8 = signal.welch(m, sr, nperseg=min(8192, n))  # finer bins for the sub-40 Hz share (S1 extra.txt)
    lt40 = float(P8[f8 < 40].sum() / (P8.sum() or 1e-20))
    return {
        'duration_s': round(dur, 3), 'sample_peak_dbfs': round(db(peak), 2), 'true_peak_dbtp': round(true_peak_db(x), 2),
        'clipped_samples': int(np.sum(np.abs(x) >= 32767 / 32768)), 'rms_dbfs': round(db(rms), 2),
        'dc_offset': round(float(m.mean()), 5), 'lufs_i': None if lufs_i is None else round(lufs_i, 2),
        'momentary_max_lufs': round(m_max, 2), 'lead_silence_ms': round(lead * 1000, 1), 'trail_silence_ms': round(trail * 1000, 1),
        'attack_ms': round(attack_ms, 1), 'decay30_ms': round(decay30_ms, 1), 'centroid_hz': round(centroid),
        'rolloff85_hz': round(roll85), 'band_ratio': {k: round(v, 3) for k, v in br.items()}, 'lt40hz_ratio': round(lt40, 3),
        'first_sample': round(float(m[0]), 5), 'last_sample': round(float(m[-1]), 5),
    }, m


def loop_seam(m, sr):
    jump = abs(float(m[-1] - m[0]))
    d = np.abs(np.diff(m))
    p99 = float(np.percentile(d, 99))
    seg = int(.5 * sr)
    return {
        'jump_abs': round(jump, 5), 'median_step': round(float(np.median(d)), 6), 'p99_step': round(p99, 6),
        'jump_over_p99': round(jump / max(p99, 1e-12), 2),
        'rms_first_5ms_dbfs': round(db(float(np.sqrt(np.mean(m[:int(.005 * sr)] ** 2)))), 2),
        'rms_last_5ms_dbfs': round(db(float(np.sqrt(np.mean(m[-int(.005 * sr):] ** 2)))), 2),
        'rms_first_50ms_dbfs': round(db(float(np.sqrt(np.mean(m[:int(.05 * sr)] ** 2)))), 2),
        'rms_last_50ms_dbfs': round(db(float(np.sqrt(np.mean(m[-int(.05 * sr):] ** 2)))), 2),
        'rms_by_500ms_dbfs': [round(db(float(np.sqrt(np.mean(m[i:i + seg] ** 2)))), 1) for i in range(0, len(m) - seg + 1, seg)],
    }


def measure(path, gains=None, use_ffmpeg=False, loop=None):
    path = Path(path)
    x, sr, bits = read_wav(path)
    res, m = analyze(x, sr)
    gains = load_gains() if gains is None else gains
    cue = path.stem.rsplit('_', 1)[0] if path.stem[-1:].isdigit() else path.stem
    is_amb = path.stem.startswith('ambience')
    gain = None if is_amb else gains.get(cue)
    offset = db(.8 * (.025 if is_amb else .11 * (gain if gain else 1.0)))
    out = {'file': path.name, 'rate': sr, 'bits': bits, 'channels': x.shape[1], 'bytes': path.stat().st_size}
    out.update(res)
    out['game_gain'] = gain
    out['ingame_offset_db'] = round(offset, 1)
    out['ingame_lufs'] = round(res['momentary_max_lufs'] + round(offset, 1), 1)
    if use_ffmpeg:
        out['lufs_i_ffmpeg_padded'], out['ffmpeg_true_peak_dbtp'] = ffmpeg_ebur128(path)
    if loop is None:
        loop = is_amb
    if loop:
        out['loop_seam'] = loop_seam(m, sr)
    return out


def collect(paths):
    files = []
    for p in paths:
        p = Path(p)
        files += sorted(p.glob('*.wav')) if p.is_dir() else [p]
    return files


def s1_order(rows):
    names = list(load_gains())
    def key(r):
        stem = r['file'][:-4]
        cue = stem.rsplit('_', 1)[0] if stem[-1:].isdigit() else stem
        return (names.index(cue) if cue in names else 99, stem)
    return sorted(rows, key=key)


def s1_table(rows):
    lines = ['| 파일 | 길이 s | 최대 dBFS / dBTP | 잘림 | M최대 LUFS | 게임 안 LUFS | 앞 / 뒤 무음 ms | 어택 / 감쇠 ms | 중심 Hz | <150 / 150–600 / 600–2k / 2–6k / >6k |', '|' + '---|' * 10]
    for r in rows:
        b = r['band_ratio']
        lines.append('| %s | %.2f | %.2f / %.2f | %d | %.1f | %.1f | %.1f / %.1f | %.0f / %.0f | %d | %s |' % (
            r['file'][:-4], r['duration_s'], r['sample_peak_dbfs'], r['true_peak_dbtp'], r['clipped_samples'], r['momentary_max_lufs'],
            r['ingame_lufs'], r['lead_silence_ms'], r['trail_silence_ms'], r['attack_ms'], r['decay30_ms'], r['centroid_hz'],
            ' / '.join(('%.2f' % b[k]).lstrip('0') or '0' for k in BANDS)))
    return '\n'.join(lines)


def num(s):
    s = s.replace('−', '-').replace('**', '').strip()
    m = re.search(r'-?\d*\.?\d+', s)
    return float(m.group()) if m else None


def parse_s1(path):
    """Rows of the 1.2 table of the S1 document -> {name: dict of the printed numbers}."""
    text = Path(path).read_text(encoding='utf-8')
    start = text.index('### 1.2')
    rows = {}
    for line in text[start:].splitlines()[1:]:
        if line.startswith('###') or line.startswith('---'):
            break
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) != 10 or not re.match(r'^[a-z]+(_\d)?$', cells[0]):
            continue
        peak = [num(v) for v in cells[2].split('/')]
        silence = [num(v) for v in cells[6].split('/')]
        ad = [num(v) for v in cells[7].replace('—', '').split('/') if v.strip()]
        rows[cells[0]] = {
            'duration_s': num(cells[1]), 'sample_peak_dbfs': peak[0], 'true_peak_dbtp': peak[1], 'clipped_samples': num(cells[3]),
            'momentary_max_lufs': num(cells[4]), 'ingame_lufs': num(cells[5]), 'lead_silence_ms': silence[0], 'trail_silence_ms': silence[1],
            'attack_ms': ad[0] if ad else None, 'decay30_ms': ad[1] if len(ad) > 1 else None, 'centroid_hz': num(cells[8]),
            'bands': [num(v) for v in cells[9].split('/')],
        }
    return rows


def compare_s1(rows, s1_path):
    table = parse_s1(s1_path)
    by_name = {r['file'][:-4]: r for r in rows}
    tol = {'duration_s': .006, 'sample_peak_dbfs': .1, 'true_peak_dbtp': .1, 'clipped_samples': 0, 'momentary_max_lufs': .1, 'ingame_lufs': .1,
           'lead_silence_ms': 1, 'trail_silence_ms': 1, 'attack_ms': 1, 'decay30_ms': 1, 'centroid_hz': 1}
    diffs, checked = [], 0
    for name in sorted(set(table) | set(by_name)):
        if name not in table:
            diffs.append((name, 'row', 'not in S1 table', 'measured')); continue
        if name not in by_name:
            diffs.append((name, 'row', 'in S1 table', 'file not measured')); continue
        t, r = table[name], by_name[name]
        for k, tl in tol.items():
            if t[k] is None:
                continue
            checked += 1
            if abs(t[k] - r[k]) > tl + 1e-9:
                diffs.append((name, k, t[k], r[k]))
        for k, tv in zip(BANDS, t['bands']):
            checked += 1
            if abs(tv - r['band_ratio'][k]) > .0051:
                diffs.append((name, 'band ' + k, tv, r['band_ratio'][k]))
    return checked, diffs


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('paths', nargs='*', help='wav files or folders (default: chapter1/art/quality03_audio)')
    ap.add_argument('--json', help='write full measurements as JSON')
    ap.add_argument('--md', help='write the S1-style table as markdown')
    ap.add_argument('--ffmpeg', action='store_true', help='add ffmpeg ebur128 cross-check (slower)')
    ap.add_argument('--loop', action='store_true', help='report loop seam for every file (ambience* is automatic)')
    ap.add_argument('--compare-s1', metavar='S1_MD', help='compare with the 1.2 table of the S1 document (exit 1 on a difference)')
    args = ap.parse_args()
    files = collect(args.paths or [DEFAULT_DIR])
    if not files:
        raise SystemExit('no wav files')
    gains = load_gains()
    rows = s1_order([measure(p, gains, args.ffmpeg, True if args.loop else None) for p in files])
    table = s1_table(rows)
    print(table)
    for r in rows:
        extra = []
        if r['dc_offset'] and abs(r['dc_offset']) > .003:
            extra.append('dc %.3f' % r['dc_offset'])
        if r['lt40hz_ratio'] > .1:
            extra.append('<40Hz %.2f' % r['lt40hz_ratio'])
        if 'loop_seam' in r:
            s = r['loop_seam']
            extra.append('loop: jump %.5f (%.2fx p99 step), rms first/last 5ms %.1f/%.1f dB, first/last 50ms %.1f/%.1f dB, 500ms rms %s' % (
                s['jump_abs'], s['jump_over_p99'], s['rms_first_5ms_dbfs'], s['rms_last_5ms_dbfs'], s['rms_first_50ms_dbfs'], s['rms_last_50ms_dbfs'], s['rms_by_500ms_dbfs']))
        if 'lufs_i_ffmpeg_padded' in r:
            extra.append('ffmpeg I(pad) %s, TP %s' % (r['lufs_i_ffmpeg_padded'], r['ffmpeg_true_peak_dbtp']))
        if extra:
            print('  %s: %s' % (r['file'], '; '.join(extra)))
    if args.md:
        Path(args.md).parent.mkdir(parents=True, exist_ok=True)
        Path(args.md).write_text(table + '\n', encoding='utf-8')
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps(rows, indent=1, ensure_ascii=False), encoding='utf-8')
    if args.compare_s1:
        checked, diffs = compare_s1(rows, args.compare_s1)
        print('\nS1 1.2 comparison: %d values checked, %d differences' % (checked, len(diffs)))
        for d in diffs:
            print('  DIFF %s %s: S1=%s measured=%s' % d)
        return 1 if diffs else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
