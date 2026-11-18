"""Cuts the painted snowflake and its rings out of the original for the living portrait (v4).

    python tools/dev/make_living_portrait_flake.py

Writes flake_disc.png (128x128, centred on the flake at 808,112) and flake_rings.png (crop at 690,10) into
chapter1/view/hud/living_portrait/. Both are meant for ADDITIVE blending: the dark background is subtracted so only
the light remains, and pixels of the hand layer are masked out so no finger is ever drawn twice.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'chapter1/view/hud/living_portrait'
SRC = ROOT / 'chapter1/art/characters/frost_witch_v02.png'
HAND = OUT / 'layers/L7_right_arm.png'
CENTER = (808, 112)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def light(rgb, lo=0.10, gain=1.25):
    return np.clip((rgb - lo) * gain, 0, 1)


def main():
    rgb = np.asarray(Image.open(SRC).convert('RGB'), dtype=np.float32) / 255.0
    hand = Image.open(HAND).convert('RGBA').getchannel('A').filter(ImageFilter.MaxFilter(5))
    hand = np.asarray(hand, dtype=np.float32) / 255.0
    keep = 1.0 - smooth(0.05, 0.5, hand)

    def cut(x0, y0, w, h, radial, lo=0.10, gain=1.25):
        sub = light(rgb[y0:y0 + h, x0:x0 + w], lo, gain)
        yy, xx = np.mgrid[y0:y0 + h, x0:x0 + w].astype(np.float32)
        r = np.hypot(xx - CENTER[0], yy - CENTER[1])
        edge = np.minimum(np.minimum(xx - x0, x0 + w - 1 - xx), np.minimum(yy - y0, y0 + h - 1 - yy))
        m = radial(r) * keep[y0:y0 + h, x0:x0 + w] * smooth(0, 18, edge)
        return Image.fromarray(np.dstack([sub * 255, m * 255]).astype(np.uint8), 'RGBA')

    disc = cut(CENTER[0] - 64, CENTER[1] - 64, 128, 128, lambda r: 1 - smooth(50, 62, r), 0.24, 1.6)
    disc.save(OUT / 'flake_disc.png')
    rings = cut(690, 10, 240, 170, lambda r: smooth(50, 62, r), 0.22, 1.5)
    rings.save(OUT / 'flake_rings.png')
    print('ok')


if __name__ == '__main__':
    main()
