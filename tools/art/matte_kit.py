"""Matte kit: key the flat magenta (#FF00FF) ground out of generated pictures, measure 9-slice margins, write a kit list.

Pillow + NumPy only, deterministic, no models, no paid calls. Sources are never modified; results go to --out (use _local/art/<kit>/,
never chapter1/art/ before adoption).

  python tools/art/matte_kit.py --spec tools/art/matte_kit_grace.json --out _local/art/grace-kit [--no-sheet]
  python tools/art/matte_kit.py --selftest

Spec file (JSON):
  {"kit": "grace-kit", "items": [
     {"id": "grade-frame-common", "src": "_local/art/queue/.../x.png", "role": "frame", "blend": "normal", "nine_slice": true, "note": "..."},
     ...]}
  role   frame | bg | emblem | icon | sigil | parchment | board | plaque   (free text; only "bg" skips nothing, it is just a label)
  blend  normal | add   (add = the picture is made of light: output is RGB composited on black, alpha 255, use ADD blending only)
  nine_slice  true -> margins are measured from the alpha (left/top/right/bottom, in source pixels)

KIT.json lists per file: file, size, source path, role, blend, margins (band = thickness on the mid line, corner = how far the
corner ornaments reach, nine = max of both, what to use as 9-slice margin), keyed (share of pixels made transparent), notes.
Also writes a check sheet (dark and light ground) next to KIT.json.
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
T0, T1 = 20.0, 165.0     # min(R,B)-G: below T0 = subject, above T1 = pure ground
DILATE = 9               # despill only within this many pixels of the keyed ground


def key_magenta(rgba):
    """RGBA uint8 array -> (RGBA uint8 array keyed and despilled, share of pixels made fully transparent)."""
    a = rgba.astype(np.float32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    raw = np.minimum(r, b) - g
    m = np.clip((raw - T0) / (T1 - T0), 0.0, 1.0)
    near = Image.fromarray((m > 0).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(DILATE))
    near = np.asarray(near) > 0
    spill = np.where(near, np.maximum(0.0, np.minimum(r, b) - g), 0.0)
    r2, b2 = np.clip(r - spill, 0, 255), np.clip(b - spill, 0, 255)
    out_a = al * (1.0 - m)
    out = np.stack([r2, g, b2, out_a], axis=-1)
    gone = out_a < 1.0
    out[gone, :3] = 0
    return np.clip(out + 0.5, 0, 255).astype(np.uint8), float(gone.mean())


def to_additive(rgba):
    """Picture made of light that carries alpha (dark fringe): premultiply onto black, drop alpha."""
    a = rgba.astype(np.float32)
    al = a[..., 3:4] / 255.0
    rgb = a[..., :3] * al
    return np.concatenate([np.clip(rgb + 0.5, 0, 255), np.full_like(a[..., 3:4], 255)], axis=-1).astype(np.uint8)


def _run_start(ok, need):
    """first index where ok[i:i+need] is all True, else len(ok)."""
    n = len(ok)
    c = 0
    for i in range(n):
        c = c + 1 if ok[i] else 0
        if c >= need:
            return i - need + 1
    return n


def measure_margins(alpha, tol=0.1, need=12):
    """9-slice margins from an alpha plane (uint8). band = thickness of the border on the mid line; corner = where the
    straight band begins (corner ornaments end); nine = max of both per side."""
    h, w = alpha.shape
    a = alpha.astype(np.float32) / 255.0

    def side(prof_cols, length):
        # prof_cols: (length, k) profile per position along the side; reference = median over the middle 40%
        lo, hi = int(length * 0.3), int(length * 0.7)
        ref = np.median(prof_cols[lo:hi], axis=0)
        diff = np.abs(prof_cols - ref).mean(axis=1)
        ok = diff < tol
        return _run_start(ok, need), _run_start(ok[::-1], need)

    top_band = a[: int(h * 0.35), :].T          # (w, rows)
    bot_band = a[int(h * 0.65):, :].T
    left_band = a[:, : int(w * 0.35)]           # (h, cols)
    right_band = a[:, int(w * 0.65):]
    cl_t, cr_t = side(top_band, w)
    cl_b, cr_b = side(bot_band, w)
    ct_l, cb_l = side(left_band, h)
    ct_r, cb_r = side(right_band, h)
    corner = {"left": max(cl_t, cl_b), "right": max(cr_t, cr_b), "top": max(ct_l, ct_r), "bottom": max(cb_l, cb_r)}

    def thick_from(line, reverse=False):
        v = line[::-1] if reverse else line
        op = v > 0.5
        if not op.any():
            return 0
        first = int(np.argmax(op))
        rest = ~op[first:]
        return int(first + (np.argmax(rest) if rest.any() else 0))  # inner edge of the band, counted from the outer image edge

    def med(lines, reverse=False):
        return int(np.median([thick_from(l, reverse) for l in lines]))

    ys = range(int(h * 0.3), int(h * 0.7), 4)
    xs = range(int(w * 0.3), int(w * 0.7), 4)
    band = {"left": med([a[y, :] for y in ys]), "right": med([a[y, :] for y in ys], True),
            "top": med([a[:, x] for x in xs]), "bottom": med([a[:, x] for x in xs], True)}
    nine = {k: int(max(band[k], corner[k])) for k in band}
    return {"band": band, "corner": corner, "nine": nine}


def nine_patch(img, margins, size):
    """stretch RGBA image to size by 9-slice with margins dict(left,right,top,bottom)."""
    w, h = img.size
    L, R, T, B = margins["left"], margins["right"], margins["top"], margins["bottom"]
    W, H = size
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    xs, xd = [0, L, w - R, w], [0, L, W - R, W]
    ys, yd = [0, T, h - B, h], [0, T, H - B, H]
    for i in range(3):
        for j in range(3):
            box = (xs[i], ys[j], xs[i + 1], ys[j + 1])
            dst = (xd[i], yd[j], xd[i + 1], yd[j + 1])
            if box[2] <= box[0] or box[3] <= box[1] or dst[2] <= dst[0] or dst[3] <= dst[1]:
                continue
            piece = img.crop(box).resize((dst[2] - dst[0], dst[3] - dst[1]), Image.LANCZOS)
            out.paste(piece, (dst[0], dst[1]))
    return out


def over(bg_rgb, img):
    base = Image.new("RGBA", img.size, bg_rgb + (255,))
    return Image.alpha_composite(base, img)


def add_onto(bg_rgb, img):
    base = np.asarray(Image.new("RGB", img.size, bg_rgb), dtype=np.int32)
    return Image.fromarray(np.clip(base + np.asarray(img.convert("RGB"), dtype=np.int32), 0, 255).astype(np.uint8)).convert("RGBA")


def fringe_report(rgba):
    """Pixels with partial alpha that still lean magenta, and dark partial-alpha share. Mechanical facts, not a verdict."""
    a = rgba.astype(np.int32)
    part = (a[..., 3] > 8) & (a[..., 3] < 247)
    lean = part & ((np.minimum(a[..., 0], a[..., 2]) - a[..., 1]) > 40)
    return {"partial_px": int(part.sum()), "magenta_leaning_edge_px": int(lean.sum())}


def build(spec_path, out_dir, sheet=True):
    spec = json.loads(pathlib.Path(spec_path).read_text(encoding="utf-8"))
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    entries, thumbs = [], []
    for it in spec["items"]:
        src = pathlib.Path(it["src"])
        if not src.is_absolute():
            src = ROOT / src
        if not src.is_file():
            entries.append({"id": it["id"], "error": f"missing source {it['src']}"})
            continue
        arr = np.asarray(Image.open(src).convert("RGBA"))
        blend = it.get("blend", "normal")
        if blend == "add":
            arr_out, keyed = to_additive(arr), 0.0
        else:
            arr_out, keyed = key_magenta(arr)
        img = Image.fromarray(arr_out)
        name = f"{it['id']}.png"
        img.save(out_dir / name)
        e = {"id": it["id"], "file": name, "size": list(img.size), "role": it.get("role", ""), "blend": blend,
             "source": str(src), "keyed_share": round(keyed, 3), "note": it.get("note", "")}
        if blend == "add":
            e["how_to_mix"] = "ADD only (RGB on black, alpha 255). Normal blending shows a dark halo."
        else:
            e.update(fringe_report(arr_out))
        if it.get("nine_slice") and blend != "add":
            e["margins"] = measure_margins(arr_out[..., 3])
        entries.append(e)
        thumbs.append((e, img))
    kit = {"kit": spec.get("kit", "kit"), "tool": "tools/art/matte_kit.py", "ground_key": "min(R,B)-G ramp 20..165 + despill within 9px",
           "files": entries}
    (out_dir / "KIT.json").write_text(json.dumps(kit, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if sheet and thumbs:
        make_sheet(thumbs, out_dir)
    return kit


def make_sheet(thumbs, out_dir, cell=256):
    """check sheets: each file over dark ground and over light ground (additive files: added onto dark, and onto mid grey)."""
    cols = 4
    for tag, bg_a, bg_b in (("dark", (14, 14, 18), (14, 14, 18)), ("light", (226, 220, 205), (226, 220, 205))):
        rows = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), bg_a)
        d = ImageDraw.Draw(sheet)
        for i, (e, img) in enumerate(thumbs):
            t = img.copy()
            t.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
            x, y = (i % cols) * cell, (i // cols) * (cell + 16)
            comp = add_onto(bg_a, t) if e["blend"] == "add" else over(bg_a, t)
            sheet.paste(comp.convert("RGB"), (x + 4, y + 4))
            d.text((x + 4, y + cell), e["id"][:40], fill=(150, 150, 150) if tag == "dark" else (60, 60, 60))
        sheet.save(out_dir / f"check-{tag}.png")
    # 9-slice check: stretch each frame to a wider and a taller shape (source scale), shown small
    nine = [(e, img) for e, img in thumbs if "margins" in e]
    if nine:
        sheet = Image.new("RGB", (len(nine) * 380, 700), (60, 60, 66))
        for i, (e, img) in enumerate(nine):
            m = e["margins"]["nine"]
            w, h = img.size
            for k, size in enumerate(((int(w * 1.5), h), (w, int(h * 1.3)))):
                p = nine_patch(img, m, size)
                p.thumbnail((360, 330), Image.LANCZOS)
                sheet.paste(over((60, 60, 66), p).convert("RGB"), (i * 380 + 10, 10 + k * 345))
        sheet.save(out_dir / "check-nine-slice.png")


def selftest():
    img = np.zeros((200, 200, 4), np.uint8)
    img[..., :] = (255, 0, 255, 255)
    img[40:160, 40:160] = (120, 90, 40, 255)          # band square
    img[70:130, 70:130] = (255, 0, 255, 255)          # inner window
    out, keyed = key_magenta(img)
    assert out[5, 5, 3] == 0 and out[100, 100, 3] == 0 and out[50, 50, 3] == 255, "keying"
    assert keyed > 0.5
    m = measure_margins(out[..., 3])
    assert 29 <= m["band"]["top"] - 40 <= 31, m
    print("selftest ok", m["nine"])
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--spec")
    ap.add_argument("--out")
    ap.add_argument("--no-sheet", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.spec or not a.out:
        ap.error("--spec and --out are required")
    kit = build(a.spec, a.out, sheet=not a.no_sheet)
    for e in kit["files"]:
        print(e.get("file", e["id"]), e.get("size", ""), e.get("error", ""), e.get("margins", {}).get("nine", ""), e.get("magenta_leaning_edge_px", ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
