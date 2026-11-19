"""Derive per-slot crops of one witch illustration (A6 section 8.7). Pillow + NumPy only, deterministic, no models.

  python tools/art/portrait_derive.py --witch ember [--slots tools/art/portrait_slots.json] [--out DIR] [--only a,b]
  python tools/art/portrait_derive.py --all                  # ember, frost, storm
  python tools/art/portrait_derive.py --witch ember --src OTHER.png   # other source (anchors still from the JSON)
  python tools/art/portrait_derive.py --selftest

Input : the illustration (default = the witch's "source" in the slots JSON) and the slots JSON (witch anchors written
        by a person once, slot list, presets). Nothing is judged here: the tables are numbers.
Output: DIR/<witch>/<slot>.png (crop, resized only when the slot has out_px), check.csv, check.txt (cut table and
        edge table), sheet.jpg (review sheet: the original with every crop frame + all crops side by side),
        derive_meta.json. Default DIR = _local/art/derived. DIR must be below a folder named _local.
Never writes below chapter1/, never overwrites the source, never writes next to the source.
A crop window is: height = span(anchor A -> anchor B) * (1 + margin_top + margin_bottom), width = height * aspect,
top = A.y - margin_top * span, x centred on the chosen anchor. A window larger than the image is shrunk (same
aspect), then shifted inside; both are reported in the notes column.
"""
import argparse
import csv
import hashlib
import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_SLOTS = ROOT / "tools" / "art" / "portrait_slots.json"
DEFAULT_OUT = ROOT / "_local" / "art" / "derived"
EDGE_STRIP = 4           # source px
EDGE_TOUCH = 24          # source px: an extreme point closer than this to a window edge is "edge"
NEAR_FRAC = 0.35         # outside by less than this fraction of window height = "near" (a limb may be cut)
BG_MODES = ("keep", "vignette", "edge_fade")
COLORS = [(255, 90, 90), (90, 220, 120), (90, 160, 255), (255, 210, 70), (220, 110, 255), (80, 230, 230),
          (255, 150, 60), (200, 200, 200), (255, 120, 190), (160, 255, 90)]


# ---------------------------------------------------------------- geometry

def anchor_xy(anchors, name):
    a = anchors[name]
    return float(a.get("x", np.nan)), float(a["y"])


def resolve_slot(slot, presets, witch):
    """Merge preset <- slot <- slot.overrides[witch]."""
    cfg = dict(presets[slot["preset"]])
    cfg.update({k: v for k, v in slot.items() if k not in ("overrides",)})
    cfg.update(slot.get("overrides", {}).get(witch, {}))
    return cfg


def compute_window(cfg, anchors, img_w, img_h):
    """-> (x0, y0, w, h, notes) in source px, floats rounded later."""
    notes = []
    ya = anchor_xy(anchors, cfg["span"][0])[1]
    yb = anchor_xy(anchors, cfg["span"][1])[1]
    span = abs(yb - ya)
    top_anchor = min(ya, yb)
    mt, mb = float(cfg["margin_top"]), float(cfg["margin_bottom"])
    ar = cfg["aspect"][0] / cfg["aspect"][1]
    h = span * (1.0 + mt + mb)
    w = h * ar
    cx_name = cfg.get("center_x", "axis")
    cx = anchor_xy(anchors, cx_name)[0] + float(cfg.get("center_x_offset", 0.0))
    y0 = top_anchor - mt * span
    x0 = cx - w / 2.0
    if w > img_w or h > img_h:
        f = min(img_w / w, img_h / h)
        notes.append("window larger than image: shrunk x%.3f" % f)
        cxm, cym = x0 + w / 2.0, y0 + h / 2.0
        w, h = w * f, h * f
        x0, y0 = cxm - w / 2.0, cym - h / 2.0
    sx, sy = 0.0, 0.0
    if x0 < 0:
        sx = -x0
    if x0 + w > img_w:
        sx = img_w - (x0 + w)
    if y0 < 0:
        sy = -y0
    if y0 + h > img_h:
        sy = img_h - (y0 + h)
    if sx or sy:
        notes.append("shifted inside image by (%.0f, %.0f)" % (sx, sy))
        x0 += sx
        y0 += sy
    return x0, y0, w, h, notes


def int_rect(x0, y0, w, h, img_w, img_h):
    ix0, iy0 = int(round(x0)), int(round(y0))
    ix1, iy1 = int(round(x0 + w)), int(round(y0 + h))
    ix0, iy0 = max(0, ix0), max(0, iy0)
    ix1, iy1 = min(img_w, ix1), min(img_h, iy1)
    return ix0, iy0, ix1, iy1


# ---------------------------------------------------------------- checks

def point_status(px, py, rect, kind_margin=EDGE_TOUCH):
    """-> (status, signed distance to nearest window edge: + inside, - outside)."""
    x0, y0, x1, y1 = rect
    d = min(px - x0, x1 - px, py - y0, y1 - py)
    if d >= kind_margin:
        return "inside", d
    if d >= 0:
        return "edge", d
    h = y1 - y0
    if -d <= NEAR_FRAC * h:
        return "outside-near", d
    return "outside-far", d


def edge_stats(crop_rgb):
    """Per side: mean luminance gradient of the 4 px strip relative to the whole crop (a high value = the frame cuts through detail)."""
    a = np.asarray(crop_rgb, dtype=np.float64)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    gy = np.abs(np.diff(lum, axis=0, prepend=lum[:1]))
    gx = np.abs(np.diff(lum, axis=1, prepend=lum[:, :1]))
    g = gx + gy
    allg = float(g.mean()) if g.size else 0.0
    s = EDGE_STRIP
    sides = {"top": (slice(0, s), slice(None)), "bottom": (slice(-s, None), slice(None)),
             "left": (slice(None), slice(0, s)), "right": (slice(None), slice(-s, None))}
    out = {}
    for k, (ys, xs) in sides.items():
        gg = g[ys, xs]
        out[k] = {"grad_ratio": float(gg.mean() / allg) if allg > 1e-9 else 0.0}
    return out


# ---------------------------------------------------------------- background

def apply_bg(img, mode, params):
    if mode == "keep":
        return img.convert("RGB")
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    nx = (xx - (w - 1) / 2.0) / (w / 2.0)
    ny = (yy - (h - 1) / 2.0) / (h / 2.0)
    r = np.sqrt(nx * nx + ny * ny)
    if mode == "vignette":
        start = float(params.get("start", 0.75))
        strength = float(params.get("strength", 0.6))
        t = np.clip((r - start) / max(1.4142 - start, 1e-6), 0.0, 1.0)
        t = t * t * (3 - 2 * t) * strength
        col = np.array(params.get("color", [23, 25, 27]), dtype=np.float64)
        out = a * (1 - t[..., None]) + col * t[..., None]
        return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    if mode == "edge_fade":
        fade = float(params.get("fade", 0.08))  # fraction of the short side
        f = max(1.0, fade * min(w, h))
        d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float64)
        alpha = np.clip(d / f, 0.0, 1.0)
        out = np.dstack([a, alpha * 255.0])
        return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    raise ValueError("unknown bg mode %r" % mode)


# ---------------------------------------------------------------- IO helpers

def check_out_dir(out_dir):
    out_dir = pathlib.Path(out_dir).resolve()
    if "_local" not in [p.name for p in out_dir.parents] and out_dir.name != "_local":
        raise SystemExit("refusing to write: output dir must be below a folder named _local (%s)" % out_dir)
    chapter = (ROOT / "chapter1").resolve()
    if chapter in out_dir.parents or out_dir == chapter:
        raise SystemExit("refusing to write below chapter1/")
    return out_dir


def font(size):
    for p in ("C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


def sha1(path):
    return hashlib.sha1(pathlib.Path(path).read_bytes()).hexdigest()


# ---------------------------------------------------------------- main derive

def derive(witch, spec, src_path, out_root, only=None, all_who=False, quiet=False):
    """spec = the whole slots JSON dict. Returns dict with rows and paths."""
    wcfg = spec["witches"][witch]
    anchors = wcfg["anchors"]
    presets = spec["presets"]
    src_path = pathlib.Path(src_path)
    out_dir = check_out_dir(out_root) / witch
    if out_dir.resolve() == src_path.resolve().parent:
        raise SystemExit("refusing: output dir equals the source dir")
    img = Image.open(src_path)
    img.load()
    img_rgb = img.convert("RGB")
    W, H = img_rgb.size
    out_dir.mkdir(parents=True, exist_ok=True)
    rows, edge_rows, tiles, frames = [], [], [], []
    ext = wcfg.get("extremes", [])
    for i, slot in enumerate(spec["slots"]):
        name = slot["name"]
        if only and name not in only:
            continue
        if slot.get("same_as"):
            continue
        cfg = resolve_slot(slot, presets, witch)
        who = cfg.get("who", "witch")
        framing_only = False
        if who != "witch":
            if not all_who:
                rows.append({"slot": name, "status": "skipped (who=%s: needs the patron illustration)" % who})
                continue
            framing_only = True
        x0, y0, w, h, notes = compute_window(cfg, anchors, W, H)
        rect = int_rect(x0, y0, w, h, W, H)
        crop = img_rgb.crop(rect)
        cw, ch = crop.size
        bg_mode = cfg.get("bg", "keep")
        if bg_mode not in BG_MODES:
            raise SystemExit("slot %s: bg must be one of %s" % (name, BG_MODES))
        out_px = cfg.get("out_px")
        scale_note = "native %dx%d; display size undecided" % (cw, ch)
        up = ""
        if out_px:
            tw, th = int(out_px[0]), int(out_px[1])
            crop_r = crop.resize((tw, th), Image.LANCZOS)
            sc = tw / cw
            scale_note = "resized to %dx%d (x%.3f)" % (tw, th, sc)
            up = "UPSCALE" if sc > 1.0 else ""
        else:
            crop_r = crop
        final = apply_bg(crop_r, bg_mode, cfg.get("bg_params", {}))
        fname = name + ("_FRAMING-ONLY" if framing_only else "") + ".png"
        final.save(out_dir / fname)
        st = edge_stats(crop)
        kinds = set(cfg.get("must_include_kinds", ["head", "hand"]))
        pts = []
        for e in ext:
            if e.get("kind") in kinds:
                s, d = point_status(float(e["x"]), float(e["y"]), rect)
                pts.append((e["name"], e["kind"], s, d))
        for nm in cfg.get("span", []):
            pass
        rows.append({"slot": name, "file": fname, "rect": rect, "size": (cw, ch), "out": final.size, "bg": bg_mode,
                     "notes": "; ".join(notes + ([scale_note] if scale_note else []) + ([up] if up else [])
                                        + (["framing only (who=%s)" % cfg.get("who")] if framing_only else [])),
                     "points": pts, "status": "ok"})
        edge_rows.append((name, st))
        frames.append((name, rect))
        tiles.append((name, final.convert("RGB")))
    rows_ok = [r for r in rows if r.get("status") == "ok"]
    write_checks(out_dir, witch, rows, edge_rows)
    sheet_path = write_sheet(out_dir, witch, img_rgb, anchors, ext, frames, tiles)
    meta = {"witch": witch, "source": str(src_path), "source_sha1": sha1(src_path), "source_size": [W, H],
            "anchors_source": wcfg.get("anchor_source", ""), "slots": [
                {"slot": r["slot"], "rect": r.get("rect"), "size": r.get("size"), "file": r.get("file"),
                 "status": r.get("status")} for r in rows]}
    (out_dir / "derive_meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    if not quiet:
        print("[%s] %d crops -> %s" % (witch, len(rows_ok), out_dir))
    return {"rows": rows, "edge_rows": edge_rows, "dir": out_dir, "sheet": sheet_path}


def write_checks(out_dir, witch, rows, edge_rows):
    lines = ["# %s: crop and cut table (numbers only; distances in source px, + inside the window, - outside)" % witch, ""]
    lines.append("slot | file | window(x0,y0,x1,y1) | crop px | notes")
    for r in rows:
        if r.get("status") != "ok":
            lines.append("%s | %s" % (r["slot"], r["status"]))
            continue
        lines.append("%s | %s | %s | %dx%d | %s" % (r["slot"], r["file"], r["rect"], r["size"][0], r["size"][1], r["notes"]))
    lines += ["", "## extreme points (head top / hand tips / feet) against each window",
              "state: inside = >= %d px from every edge; edge = inside but < %d px; outside-near = outside by <= %d%% of window height"
              " (a limb may be cut by the frame); outside-far = outside, probably simply not in this crop" % (EDGE_TOUCH, EDGE_TOUCH, int(NEAR_FRAC * 100)), ""]
    lines.append("slot | point | kind | state | distance")
    for r in rows:
        for p in r.get("points", []):
            lines.append("%s | %s | %s | %s | %+.0f" % (r["slot"], p[0], p[1], p[2], p[3]))
    lines += ["", "## window edges (4 px strip of the crop): grad = strip gradient / whole-crop mean gradient; skin = skin-like pixel %% (rough colour test,"
              " hair and fire can fool it)", ""]
    lines.append("slot | side | grad")
    for name, st in edge_rows:
        for side in ("top", "bottom", "left", "right"):
            lines.append("%s | %s | %.2f" % (name, side, st[side]["grad_ratio"]))
    (out_dir / "check.txt").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    with open(out_dir / "check.csv", "w", encoding="utf-8", newline="") as f:
        wri = csv.writer(f, lineterminator="\n")
        wri.writerow(["witch", "slot", "table", "item", "kind_or_side", "state_or_grad", "value"])
        for r in rows:
            for p in r.get("points", []):
                wri.writerow([witch, r["slot"], "point", p[0], p[1], p[2], "%.0f" % p[3]])
        for name, st in edge_rows:
            for side in ("top", "bottom", "left", "right"):
                wri.writerow([witch, name, "edge", side, "grad", "%.2f" % st[side]["grad_ratio"], ""])


def write_sheet(out_dir, witch, img, anchors, ext, frames, tiles):
    fs = font(15)
    ph = 760
    sc = ph / img.size[1]
    left = img.resize((int(img.size[0] * sc), ph), Image.LANCZOS).convert("RGB")
    d = ImageDraw.Draw(left)
    for i, (name, rect) in enumerate(frames):
        c = COLORS[i % len(COLORS)]
        d.rectangle([rect[0] * sc, rect[1] * sc, rect[2] * sc - 1, rect[3] * sc - 1], outline=c, width=2)
        d.text((rect[0] * sc + 3, rect[1] * sc + 2 + 14 * (i % 3)), name, fill=c, font=font(12))
    for k, a in anchors.items():
        x = a.get("x")
        y = a["y"]
        if x is None:
            d.line([(0, y * sc), (14, y * sc)], fill=(255, 255, 255))
            d.text((16, y * sc - 7), k, fill=(255, 255, 255), font=font(11))
        else:
            d.ellipse([x * sc - 3, y * sc - 3, x * sc + 3, y * sc + 3], outline=(255, 255, 255))
    for e in ext:
        d.rectangle([e["x"] * sc - 3, e["y"] * sc - 3, e["x"] * sc + 3, e["y"] * sc + 3], outline=(255, 255, 0))
    # tiles on the right
    th = 300
    labelh = 20
    placed, x, y, rowh, maxw = [], 8, 8, 0, 1250
    for name, t in tiles:
        s = th / t.size[1]
        tw = max(1, int(t.size[0] * s))
        tt = t.resize((tw, th), Image.LANCZOS)
        if x + tw + 8 > maxw and x > 8:
            x, y = 8, y + rowh + 8
            rowh = 0
        placed.append((name, tt, x, y, t.size))
        x += tw + 8
        rowh = max(rowh, th + labelh)
    total_h = max(ph, y + rowh + 8)
    sheet = Image.new("RGB", (left.size[0] + 12 + maxw, total_h), (24, 24, 26))
    sheet.paste(left, (0, 0))
    ds = ImageDraw.Draw(sheet)
    ox = left.size[0] + 12
    for name, tt, px, py, osz in placed:
        sheet.paste(tt, (ox + px, py + labelh))
        ds.text((ox + px, py), "%s  %dx%d" % (name, osz[0], osz[1]), fill=(220, 220, 220), font=fs)
    ds.text((4, ph + 2), "%s: white = anchors, yellow = extreme points, coloured = crop windows" % witch, fill=(200, 200, 200), font=font(12))
    p = out_dir / "sheet.jpg"
    sheet.save(p, quality=88)
    return p


# ---------------------------------------------------------------- selftest

def selftest():
    import tempfile
    ok = True

    def check(cond, msg):
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + msg)
        ok = ok and bool(cond)

    # synthetic 200x300 picture: grey bg, head circle at (100,40) r20, body rectangle, a hand sticking out to x=190
    im = Image.new("RGB", (200, 300), (60, 60, 70))
    d = ImageDraw.Draw(im)
    d.ellipse([80, 20, 120, 60], fill=(220, 170, 140))
    d.rectangle([85, 60, 115, 200], fill=(40, 40, 120))
    d.rectangle([115, 80, 190, 90], fill=(220, 170, 140))
    d.rectangle([90, 200, 110, 290], fill=(30, 30, 30))
    anchors = {"head_top": {"y": 20}, "eye": {"x": 100, "y": 38}, "chin": {"x": 100, "y": 60}, "chest": {"y": 100},
               "waist": {"y": 160}, "feet": {"y": 290}, "axis": {"x": 100, "y": 150}}
    ext = [{"name": "head_top", "kind": "head", "x": 100, "y": 20}, {"name": "hand", "kind": "hand", "x": 190, "y": 85},
           {"name": "toe", "kind": "foot", "x": 100, "y": 290}]
    presets = {"face_square": {"aspect": [1, 1], "span": ["head_top", "chin"], "margin_top": 0.25, "margin_bottom": 0.25, "center_x": "eye"},
               "bust": {"aspect": [1, 1], "span": ["head_top", "waist"], "margin_top": 0.1, "margin_bottom": 0.1, "center_x": "axis"}}
    spec = {"witches": {"t": {"anchors": anchors, "extremes": ext}}, "presets": presets,
            "slots": [{"name": "face", "preset": "face_square", "must_include_kinds": ["head", "hand"]},
                      {"name": "bust", "preset": "bust", "out_px": [100, 100]},
                      {"name": "patron", "preset": "bust", "who": "patron"}]}
    # geometry: face span 40, h = 40*1.5 = 60, w 60, y0 = 20-10 = 10, x0 = 70
    x0, y0, w, h, n = compute_window(resolve_slot(spec["slots"][0], presets, "t"), anchors, 200, 300)
    check((x0, y0, w, h) == (70.0, 10.0, 60.0, 60.0), "face window math %s" % ((x0, y0, w, h),))
    # bust span 140 -> h=168, w=168, x0=16, y0=6
    x0, y0, w, h, n = compute_window(resolve_slot(spec["slots"][1], presets, "t"), anchors, 200, 300)
    check(abs(x0 - 16) < 1e-9 and abs(y0 - 6) < 1e-9 and abs(h - 168) < 1e-9, "bust window math")
    # shrink + shift
    big = dict(presets["bust"], margin_top=1.0, margin_bottom=1.0)
    x0, y0, w, h, n = compute_window(big, anchors, 200, 300)
    check(w <= 200 and h <= 300 and x0 >= 0 and y0 >= 0 and len(n) >= 1, "oversized window shrunk and inside image (%s)" % n)
    # point status
    check(point_status(100, 50, (50, 0, 150, 100))[0] == "inside", "point inside")
    check(point_status(170, 85, (50, 0, 150, 100))[0] == "outside-near", "hand outside the frame, near")
    check(point_status(100, 290, (50, 0, 150, 100))[0] == "outside-far", "foot far outside")
    check(point_status(140, 50, (50, 0, 150, 100))[0] == "edge", "point at edge")
    # background modes keep size, edge_fade makes RGBA with transparent corner
    v = apply_bg(im, "vignette", {})
    check(v.size == im.size and v.mode == "RGB" and v.getpixel((0, 0)) != im.getpixel((0, 0)), "vignette darkens corner")
    f = apply_bg(im, "edge_fade", {"fade": 0.1})
    check(f.mode == "RGBA" and f.getpixel((0, 0))[3] == 0 and f.getpixel((100, 150))[3] == 255, "edge fade alpha")
    # edge stats: skin strip detected
    st = edge_stats(im.crop((70, 10, 130, 70)))
    check(set(st) == {"top", "bottom", "left", "right"} and st["top"]["grad_ratio"] >= 0.0, "edge stats run")
    # out guard
    try:
        check_out_dir(ROOT / "chapter1" / "art")
        check(False, "out guard (chapter1)")
    except SystemExit:
        check(True, "out guard refuses chapter1/ and non-_local dirs")
    try:
        check_out_dir(pathlib.Path(tempfile.gettempdir()) / "x")
        check(False, "out guard (non _local)")
    except SystemExit:
        check(True, "out guard refuses a dir outside _local")
    # end to end in a temp _local, source untouched
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        src = td / "src" / "t.png"
        src.parent.mkdir()
        im.save(src)
        before = sha1(src)
        res = derive("t", spec, src, td / "_local" / "derived", quiet=True)
        outd = td / "_local" / "derived" / "t"
        check(sha1(src) == before, "source unchanged")
        check((outd / "face.png").exists() and (outd / "bust.png").exists() and (outd / "sheet.jpg").exists()
              and (outd / "check.txt").exists(), "outputs written")
        check(Image.open(outd / "bust.png").size == (100, 100), "out_px resize")
        check(not (outd / "patron.png").exists(), "patron slot skipped without --all-who")
        pts = {(r["slot"], p[0]): p[2] for r in res["rows"] for p in r.get("points", [])}
        check(pts.get(("face", "hand")) == "outside-far" or pts.get(("face", "hand")) == "outside-near", "face crop reports the hand as outside")
        check(pts.get(("face", "head_top")) == "edge", "face crop keeps head top, 10 px from the frame (reported as edge)")
        res2 = derive("t", spec, src, td / "_local" / "derived", all_who=True, quiet=True)
        check((outd / "patron_FRAMING-ONLY.png").exists(), "patron slot gets framing-only file with --all-who")
    print("SELFTEST " + ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--witch")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--src")
    ap.add_argument("--slots", default=str(DEFAULT_SLOTS))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--only", help="comma separated slot names")
    ap.add_argument("--all-who", action="store_true", help="also cut slots meant for the patron (framing test only)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    spec = json.loads(pathlib.Path(a.slots).read_text(encoding="utf-8"))
    names = list(spec["witches"].keys()) if a.all else [a.witch]
    if not names or names == [None]:
        ap.error("--witch NAME or --all")
    only = set(a.only.split(",")) if a.only else None
    for n in names:
        src = a.src if (a.src and not a.all) else ROOT / spec["witches"][n]["source"]
        derive(n, spec, src, a.out, only=only, all_who=a.all_who)
    return 0


if __name__ == "__main__":
    sys.exit(main())
