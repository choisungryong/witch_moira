"""Synthesize the loot drop cues that have no licensed source: jewelry and high-grade drops.

    python tools/dev/make_drop_sounds.py

Writes 48 kHz mono 16-bit WAV files into chapter1/art/quality03_audio/. The sounds
are generated from sine partials by this script, so they carry no third-party
licence. They are placeholders in the project's own name: nobody has listened to
them in the game yet.
"""
from pathlib import Path
import math, struct, wave

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'chapter1/art/quality03_audio'
RATE = 48000
PEAK = 0.66  # the mixer budget assumes individual peaks <= .68


def render(seconds, voices):
    """voices: (start_s, frequency_hz, amplitude, decay_per_second, attack_s)"""
    count = int(seconds * RATE)
    samples = [0.0] * count
    for start, frequency, amplitude, decay, attack in voices:
        first = int(start * RATE)
        for index in range(first, count):
            t = (index - first) / RATE
            envelope = min(1.0, t / attack) * math.exp(-decay * t)
            samples[index] += amplitude * envelope * math.sin(2 * math.pi * frequency * t)
    peak = max(abs(s) for s in samples) or 1.0
    fade = int(0.01 * RATE)
    for index in range(fade):
        samples[count - 1 - index] *= index / fade
    return [s / peak * PEAK for s in samples]


def save(name, samples):
    path = OUT / name
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    return path


def main():
    # Jewelry: a small bright "ting" with an inharmonic bell partial and a fainter second strike.
    jewel = render(0.75, [
        (0.000, 2637.0, 1.00, 7.0, 0.002), (0.000, 5274.0, 0.45, 10.0, 0.002), (0.000, 7120.0, 0.22, 14.0, 0.001),
        (0.085, 3520.0, 0.55, 8.0, 0.002), (0.085, 7040.0, 0.20, 12.0, 0.001),
    ])
    # Legendary / unique: a lower, longer chime that rises through a fifth and an octave.
    legend = render(1.6, [
        (0.00, 523.25, 1.00, 2.6, 0.004), (0.00, 1046.5, 0.40, 3.4, 0.004),
        (0.11, 783.99, 0.85, 2.8, 0.004), (0.11, 1567.98, 0.30, 3.8, 0.003),
        (0.22, 1046.5, 0.80, 2.4, 0.004), (0.22, 2093.0, 0.28, 3.6, 0.003), (0.22, 3135.96, 0.12, 5.0, 0.002),
    ])
    for name, samples in (('jewel_0.wav', jewel), ('legend_0.wav', legend)):
        path = save(name, samples)
        print('WROTE %s %.2fs peak %.2f' % (path.relative_to(ROOT).as_posix(), len(samples) / RATE, max(abs(s) for s in samples)))


if __name__ == '__main__':
    main()
