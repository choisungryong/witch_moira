"""Post-process generated equipment icons (A3 spec section 9). Pillow + NumPy only, deterministic, no external models.

  python tools/art/make_equipment_icons.py [--src DIR] [--out DIR] [--pick item=rN ...] [--no-sheet]

Source: DIR/<item>-rN.png (1024 magenta-background originals, default _local/art/drafts/equipment_icon).
For each item the highest rN is used unless --pick item=rN is given.
Output (default DIR/processed/): base_<item>.png or unique_<item>.png (512 RGBA master), *_128.png (game size),
and sheet-icons-trial.jpg one level up (DIR/sheet-icons-trial.jpg).
Prints per icon: magenta-fringe ratio, accent-colour area (rough), mean saturation, closest edge distance of the original.
"""
import argparse
import colorsys
import pathlib
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "_local" / "art" / "drafts" / "equipment_icon"
UNIQUE = {"winter_heart", "ash_bloom", "forked_covenant"}
ACCENT = {  # item -> (hue_lo, hue_hi) in degrees of its element accent; None = no element colour allowed
    "cinder_staff": (10, 40), "winter_heart": (165, 205), "linen_robe": None, "glass_ring": None,
}
MASTER, GAME, FILL = 512, 128, 0.84
SURFACE = (0x17, 0x19, 0x1B)
LIGHT = (0xD8, 0xD2, 0xC4)
M = np.array([255.0, 0.0, 255.0])


def remove_magenta(im):
    """RGB image on #FF00FF -> float RGBA (straight alpha), fringe un-mixed."""
    a = np.asarray(im.convert("RGB"), dtype=np.float64)
    s = (np.minimum(a[..., 0], a[..., 2]) - a[..., 1]) / 255.0
    alpha = np.clip((0.70 - s) / (0.70 - 0.25), 0.0, 1.0)
    af = alpha[..., None]
    c = np.where(af > 0.01, (a - (1.0 - af) * M) / np.maximum(af, 0.01), a)
    c = np.clip(c, 0, 255)
    return c, alpha


def finish_alpha(alpha):
    """1px erosion then 0.6px blur on the alpha channel."""
    img = Image.fromarray((alpha * 255).round().astype(np.uint8))
    img = img.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    return np.asarray(img, dtype=np.float64) / 255.0


def hsv_arrays(rgb):
    x = rgb / 255.0
    mx, mn = x.max(-1), x.min(-1)
    d = mx - mn
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0)
    r, g, b = x[..., 0], x[..., 1], x[..., 2]
    h = np.zeros_like(mx)
    dd = np.maximum(d, 1e-9)
    h = np.where(mx == r, ((g - b) / dd) % 6, h)
    h = np.where(mx == g, (b - r) / dd + 2, h)
    h = np.where(mx == b, (r - g) / dd + 4, h)
    h = np.where(d == 0, 0, h) * 60.0
    return h, sat, mx


def center_to_canvas(rgba_img):
    """Crop to alpha>8/255 bbox, scale long side to 84% of the canvas, centre on a 512 canvas."""
    al = np.asarray(rgba_img.getchannel("A"))
    ys, xs = np.where(al > 8)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    crop = rgba_img.crop(box)
    k = MASTER * FILL / max(crop.width, crop.height)
    nw, nh = max(1, round(crop.width * k)), max(1, round(crop.height * k))
    crop = crop.convert("RGBa").resize((nw, nh), Image.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    canvas.paste(crop, ((MASTER - nw) // 2, (MASTER - nh) // 2))
    return canvas


def process(path, item):
    src = Image.open(path)
    has_alpha = src.mode == "RGBA" and (np.asarray(src.getchannel("A")) < 250).mean() > 0.05  # stray alpha pixels do not count
    raw_alpha = None
    if has_alpha:
        arr = np.asarray(src, dtype=np.float64)
        c, alpha = arr[..., :3], arr[..., 3] / 255.0
    else:
        c, alpha = remove_magenta(src)
    raw_alpha = alpha.copy()
    alpha = finish_alpha(alpha)
    rgba = np.dstack([c, alpha * 255]).round().astype(np.uint8)
    master = center_to_canvas(Image.fromarray(rgba))
    # measurements on the master
    m = np.asarray(master, dtype=np.float64)
    solid = m[..., 3] > 127
    h, sat, val = hsv_arrays(m[..., :3])
    n = max(int(solid.sum()), 1)
    pink = ((h >= 285) & (h <= 315) & (sat >= 0.45) & solid).sum() / n
    rng = ACCENT.get(item)
    accent = None
    if rng:
        accent = ((h >= rng[0]) & (h <= rng[1]) & (sat >= 0.45) & (val >= 0.55) & solid).sum() / n
    mean_sat = float(sat[solid].mean()) if solid.any() else 0.0
    ys, xs = np.where(raw_alpha > 0.5)
    h0, w0 = raw_alpha.shape
    edge = min(xs.min(), ys.min(), w0 - 1 - xs.max(), h0 - 1 - ys.max()) / w0
    return master, dict(pink=pink, accent=accent, sat=mean_sat, edge=edge, alpha_in=has_alpha)


def panel(master, bg, sizes, silhouette=False, pad=8):
    ims = []
    for s in sizes:
        im = master.convert("RGBa").resize((s, s), Image.LANCZOS).convert("RGBA")
        if silhouette:
            a = im.getchannel("A")
            im = Image.new("RGBA", (s, s), (0, 0, 0, 255))
            im.putalpha(a)
        ims.append(im)
    w = sum(sizes) + pad * (len(sizes) + 1)
    out = Image.new("RGB", (w, max(sizes) + 2 * pad), bg)
    x = pad
    for im in ims:
        out.paste(im, (x, (out.height - im.height) // 2), im)
        x += im.width + pad
    return out


def make_sheet(rows, path):
    sizes = (128, 64, 40)
    tiles = []
    for item, tag, master in rows:
        orig = master  # same canvas; (a) shows the processed master at 256
        a = Image.new("RGB", (256 + 16, 256 + 16), SURFACE)
        o = master.convert("RGBa").resize((256, 256), Image.LANCZOS).convert("RGBA")
        a.paste(o, (8, 8), o)
        parts = [a, panel(master, SURFACE, sizes), panel(master, LIGHT, sizes), panel(master, (255, 255, 255), sizes, True)]
        tiles.append((item, tag, parts))
    gap = 10
    width = sum(p.width for p in tiles[0][2]) + gap * 5
    rowh = 272 + 18
    sheet = Image.new("RGB", (width, rowh * len(tiles) + 30), (60, 60, 64))
    d = ImageDraw.Draw(sheet)
    d.text((10, 8), "A3 equipment icon trial | cols: master 256 | 128/64/40 on SURFACE | 128/64/40 on light | silhouette", fill=(230, 230, 230))
    for r, (item, tag, parts) in enumerate(tiles):
        y = 30 + r * rowh
        x = gap
        for p in parts:
            sheet.paste(p, (x, y + 14))
            x += p.width + gap
        d.text((gap, y), f"{item} ({tag})", fill=(255, 220, 140))
    sheet.save(path, quality=90)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=pathlib.Path, default=DEFAULT_DIR)
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument("--pick", nargs="*", default=[])
    ap.add_argument("--no-sheet", action="store_true")
    args = ap.parse_args()
    out = args.out or (args.src / "processed")
    out.mkdir(parents=True, exist_ok=True)
    picks = dict(p.split("=", 1) for p in args.pick)
    found = {}
    for p in sorted(args.src.glob("*-r[0-9]*.png")):
        m = re.fullmatch(r"(.+)-(r\d+)\.png", p.name)
        if m:
            found.setdefault(m.group(1), {})[m.group(2)] = p
    rows = []
    order = ["cinder_staff", "linen_robe", "glass_ring", "winter_heart"]
    for item in sorted(found, key=lambda k: (order.index(k) if k in order else 99, k)):
        tries = found[item]
        rn = picks.get(item) or max(tries, key=lambda k: int(k[1:]))
        if rn not in tries:
            print(f"{item}: {rn} not found", file=sys.stderr)
            continue
        master, st = process(tries[rn], item)
        prefix = "unique" if item in UNIQUE else "base"
        master.save(out / f"{prefix}_{item}.png")
        master.convert("RGBa").resize((GAME, GAME), Image.LANCZOS).convert("RGBA").save(out / f"{prefix}_{item}_128.png")
        acc = "n/a" if st["accent"] is None else f"{st['accent'] * 100:.1f}%"
        print(f"{item} {rn}: pink_fringe={st['pink'] * 100:.3f}% accent_area={acc} mean_sat={st['sat']:.2f} "
              f"edge_dist={st['edge'] * 100:.1f}% src_alpha={st['alpha_in']}")
        rows.append((item, rn, master))
    if rows and not args.no_sheet:
        make_sheet(rows, args.src / "sheet-icons-trial.jpg")
        print("sheet:", args.src / "sheet-icons-trial.jpg")


if __name__ == "__main__":
    main()
