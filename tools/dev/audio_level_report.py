#!/usr/bin/env python
"""Level table of recordings (read only): integrated loudness (ebur128 I), true peak, mean and max volume (volumedetect) per file.

Companion of chapter1/tests/audio_level_probe.gd (records the Master bus: raw wav vs the game's own player) and of the skill-lab
clips (mp4, audio stream). A recording that is quieter than the gate (-70 LUFS) shows I as "-inf".

  python tools/dev/audio_level_report.py DIR_OR_FILES... [--json out.json]
"""
import argparse, json, re, shutil, subprocess, sys
from pathlib import Path

EXT = ('.wav', '.mp4', '.ogg')


def _run(path, af):
    ff = shutil.which('ffmpeg')
    if not ff:
        sys.exit('ffmpeg not found')
    p = subprocess.run([ff, '-nostats', '-i', str(path), '-vn', '-af', af, '-f', 'null', '-'], capture_output=True, text=True, errors='replace')
    return p.stderr


def measure(path):
    e = _run(path, 'ebur128=peak=true')
    tail = e[e.rfind('Summary:'):] if 'Summary:' in e else ''
    def grab(pat):
        m = re.search(pat, tail)
        return m.group(1) if m else None
    i = grab(r'I:\s+(-?[\d.]+|-inf) LUFS')
    tp = grab(r'Peak:\s+(-?[\d.]+|-inf) dBFS')
    v = _run(path, 'volumedetect')
    mean = re.search(r'mean_volume: (-?[\d.]+|-inf) dB', v)
    mx = re.search(r'max_volume: (-?[\d.]+|-inf) dB', v)
    f = lambda s: None if s is None else float(s)
    return {'file': Path(path).name, 'I_lufs': f(i), 'true_peak_db': f(tp), 'mean_db': f(mean.group(1) if mean else None),
            'max_db': f(mx.group(1) if mx else None)}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('paths', nargs='+')
    ap.add_argument('--json')
    a = ap.parse_args()
    files = []
    for p in a.paths:
        p = Path(p)
        files += sorted(x for x in p.iterdir() if x.suffix.lower() in EXT) if p.is_dir() else [p]
    rows = [measure(f) for f in files]
    print('%-62s %9s %9s %9s %9s' % ('file', 'I LUFS', 'TP dB', 'mean dB', 'max dB'))
    for r in rows:
        print('%-62s %9s %9s %9s %9s' % (r['file'][:62], r['I_lufs'], r['true_peak_db'], r['mean_db'], r['max_db']))
    if a.json:
        Path(a.json).write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding='utf-8')


if __name__ == '__main__':
    main()
