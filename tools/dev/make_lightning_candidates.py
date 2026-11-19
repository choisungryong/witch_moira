"""Lightning (running current) cast sound candidates for the scene audition. Candidates only: nothing here goes into the game.

    python tools/dev/make_lightning_candidates.py --out _local/audio/lightning-cands-20261120
    python tools/dev/make_lightning_candidates.py --out ... --sources D:/witch-moira-audio-sources

Four 48 kHz 16-bit mono WAV files, each peak -3 dBFS (the scene tool matches the level to the fire cast, see audio_scene_audition.py):
  synth_discharge_hum.wav   project synthesis: a spray of short crackles that thins out, then a low 100 Hz-based hum that swells and fades
  synth_tick_small.wav      project synthesis: 0.18 s of a few small crackles, no hum, band-limited (the "very small and short" one)
  local_arc_design.wav      excerpt of a local library file (Sonniss GDC 2026, InMotionAudio "Arc", ELECArc_ArcDesign15), low-passed at 6 kHz
  local_arc_low.wav         excerpt of a local library file (Sonniss GDC 2020, Sound Spark LLC "Electric Arcs and Energy",
                            Electric_Arc_Reverberant_Shock_Long_05), 1.2 s from the 1.1 s mark
The synthesis is seeded and deterministic (same files every run). The library files are read from the local disk only; nothing is
downloaded and no file is sent anywhere. License of the library files: Sonniss GameAudioGDC bundle license (royalty free, commercial
use, no attribution; machine-learning training on the sounds is forbidden, editing is allowed). The synthesized files are project-owned.
This tool does not listen: the measurements it prints are the only evidence.
"""
import argparse, json, sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_measure as am

SR = 48000
SRC = {
    'local_arc_design': ('sonniss-gdc-2026/extracted/InMotionAudio - Arc/ELECArc_ArcDesign15_InMotionAudio_Arc.wav', 0.0, 0.8, 6000.0),
    'local_arc_low': ('sonniss-2020/p12 - Sound Spark LLC - Electric Arcs and Energy/Electric_Arc_Reverberant_Shock_Long_05.wav', 1.1, 1.2, None),
}


def bandpass(x, lo, hi):
    return signal.sosfilt(signal.butter(4, [lo, hi], 'bandpass', fs=SR, output='sos'), x)


def crackles(rng, dur, rate0, rate1, band, tau_ms=1.6):
    """Poisson crackles whose rate falls from rate0 to rate1 per second; each is a short band-limited noise burst."""
    n = int(dur * SR)
    noise = bandpass(rng.standard_normal(n + 2000), *band)
    out = np.zeros(n)
    t, kl = 0.0008, int(0.012 * SR)           # first crackle at 0.8 ms: no lead silence
    env = np.exp(-np.arange(kl) / (tau_ms / 1000 * SR))
    while t < dur - 0.012:
        rate = rate0 * (rate1 / rate0) ** (t / dur)
        i = int(t * SR)
        a = rng.exponential(1.0) ** 0.7 * (1.0 - 0.5 * t / dur)
        j = int(rng.integers(0, 1500))
        out[i:i + kl] += a * noise[j:j + kl] * env
        t += rng.exponential(1.0 / rate)
    return out


def fade_out(x, seconds):
    k = int(seconds * SR)
    x = x.copy()
    x[-k:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, k)))
    return x


def norm(x, peak_db=-3.0):
    return x / np.abs(x).max() * 10 ** (peak_db / 20)


def synth_discharge_hum():
    rng = np.random.default_rng(20261120)
    dur = 0.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    spray = crackles(rng, dur, 170.0, 28.0, (900.0, 5000.0))
    spray = spray / np.abs(spray).max()
    hum = sum(np.sin(2 * np.pi * 100.0 * k * t + rng.uniform(0, 6.28)) / k for k in range(1, 7))
    hum *= 1.0 + 0.4 * np.sin(2 * np.pi * 50.0 * t)                       # mains-style wobble
    hum = signal.sosfilt(signal.butter(2, 800.0, 'lowpass', fs=SR, output='sos'), hum)
    swell = np.clip((t - 0.04) / 0.06, 0, 1) * np.exp(-np.clip(t - 0.10, 0, None) / 0.32)
    hum = hum / np.abs(hum).max() * swell * 0.35
    return norm(fade_out(spray * 0.8 + hum, 0.25))


def synth_tick_small():
    rng = np.random.default_rng(20261121)
    x = crackles(rng, 0.18, 90.0, 22.0, (1200.0, 4500.0), tau_ms=1.2)
    return norm(fade_out(x, 0.07))


def excerpt(sources, key):
    rel, start, length, lowpass = SRC[key]
    x, sr, _ = am.read_wav(Path(sources) / rel)
    m = x.mean(axis=1)
    m = signal.resample_poly(m, SR, sr) if sr != SR else m
    if lowpass:
        m = signal.sosfilt(signal.butter(4, lowpass, 'lowpass', fs=SR, output='sos'), m)
    a = int(start * SR)
    m = m[a:a + int(length * SR)].copy()
    k = int(0.003 * SR)
    m[:k] *= np.linspace(0, 1, k)                                          # 3 ms in, no click
    return norm(fade_out(m, 0.2))


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', required=True, help='output folder (under _local/)')
    ap.add_argument('--sources', default='D:/witch-moira-audio-sources')
    args = ap.parse_args()
    out = Path(args.out)
    if '_local' not in out.resolve().parts:
        print('ERROR: --out must be under _local/')
        return 2
    out.mkdir(parents=True, exist_ok=True)
    made = {'synth_discharge_hum': synth_discharge_hum(), 'synth_tick_small': synth_tick_small()}
    for key in SRC:
        if (Path(args.sources) / SRC[key][0]).is_file():
            made[key] = excerpt(args.sources, key)
        else:
            print('SKIP %s: %s not found' % (key, SRC[key][0]))
    meta = {}
    for name, x in made.items():
        clipped = am.write_wav(out / (name + '.wav'), x, SR)
        r = am.measure(out / (name + '.wav'))
        meta[name] = {'clipped_on_write': clipped, 'duration_s': r['duration_s'], 'peak_dbfs': r['sample_peak_dbfs'], 'attack_ms': r['attack_ms'],
                      'centroid_hz': r['centroid_hz'], 'lead_silence_ms': r['lead_silence_ms'], 'band_ratio': r['band_ratio']}
        print('%-22s %.2f s  peak %.1f dBFS  attack %.0f ms  centroid %d Hz  lead %.1f ms  clipped %d' % (
            name, r['duration_s'], r['sample_peak_dbfs'], r['attack_ms'], r['centroid_hz'], r['lead_silence_ms'], clipped))
    (out / 'made.json').write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
