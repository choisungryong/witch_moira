"""Standard review sheet for generated attempts (replaces sheet_*.py / mkover*.py copies). Read-only on the sources.

  python tools/art/review_sheet.py --items cinder_staff=equipment_icon/cinder_staff-r2.png linen_robe=... [--prev cinder_staff=equipment_icon/cinder_staff-r1.png]
  python tools/art/review_sheet.py --list ROWS.json [--name sheet-name] [--kind icon|image] [--out FILE.jpg]

ROWS.json: {"id": "attempt file", ...} or [{"id": "...", "file": "...", "prev": "older attempt file"}, ...]. Paths are absolute or
relative to the drafts folder. One row per attempt (a "prev" row is placed right above its new row, tagged prev/new).
Columns: raw original (256) | processed master 256 | 128/64/40 on the dark surface | 128/64/40 on the light surface | silhouettes.
kind icon (default): magenta-key removal, centring, 512/128 masters from make_equipment_icons.process (that file is not modified).
kind image: portraits and other opaque art; the background is keyed from the corner colour (rough), so the silhouette column is rough too.
Output: <_local>/art/review/<name>.jpg plus <name>.rows.jsonl (source sha256, sizes, measurements; not .json, so the drafts scanners ignore it). Refuses to write outside _local/.
"""
import argparse
import datetime
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen  # noqa: E402
import make_equipment_icons as m  # noqa: E402


def ascii_tag(s):
    return str(s).encode("ascii", "replace").decode("ascii")


def process_image(path):
    """Opaque art -> (512 master RGBA, stats). Background keyed from the 4 corners."""
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float64)
    corners = np.array([a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]])
    bg = np.median(corners, axis=0)
    dist = np.abs(a - bg).max(axis=2)
    alpha = np.clip((dist - 12) / 40.0, 0, 1)
    rgba = np.dstack([a, alpha * 255]).round().astype(np.uint8)
    if (alpha > 0.03).sum() < 16:                        # nothing differs from the corner colour: keep it opaque
        rgba[..., 3] = 255
    master = m.center_to_canvas(Image.fromarray(rgba))
    return master, {"bg_key": [int(x) for x in bg], "opaque_share": round(float((alpha > 0.5).mean()), 3)}


def raw_tile(path, size=256):
    im = Image.open(path).convert("RGBA")
    k = size / max(im.size)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    tile = Image.new("RGB", (size + 16, size + 16), (60, 60, 64))
    tile.paste(im, (8 + (size - im.width) // 2, 8 + (size - im.height) // 2), im)
    return tile


def load_rows(args, drafts):
    rows = []
    if args.list:
        data = json.loads(pathlib.Path(args.list).read_text(encoding="utf-8"))
        if isinstance(data, dict):
            data = [{"id": k, "file": v} for k, v in data.items()]
        rows = [dict(r) for r in data]
    for s in args.items or []:
        k, v = s.split("=", 1)
        rows.append({"id": k, "file": v})
    prev = dict(s.split("=", 1) for s in (args.prev or []))
    for r in rows:
        if r["id"] in prev:
            r["prev"] = prev[r["id"]]
    if not rows:
        raise SystemExit("no rows (use --items or --list)")
    for r in rows:
        for key in ("file", "prev"):
            if r.get(key):
                p = gen.resolve_file(r[key], drafts)
                if not p:
                    raise SystemExit(f"{r['id']}: {key} not found: {r[key]}")
                r[key] = p
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--items", nargs="*")
    ap.add_argument("--prev", nargs="*")
    ap.add_argument("--list")
    ap.add_argument("--kind", choices=["icon", "image"], default="icon")
    ap.add_argument("--name")
    ap.add_argument("--out")
    ap.add_argument("--drafts")
    a = ap.parse_args(argv)
    drafts = gen.find_drafts(a.drafts)
    rows = load_rows(a, drafts)
    name = a.name or "sheet-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = pathlib.Path(a.out) if a.out else gen.local_root(drafts) / "art" / "review" / f"{name}.jpg"
    gen.assert_local(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = (lambda p, i: m.process(p, i)) if a.kind == "icon" else (lambda p, i: process_image(p))
    sheet_rows, raws, report = [], [], []
    for r in rows:
        tag = ascii_tag(r["id"])
        for key, label in (("prev", "prev"), ("file", "new")):
            if not r.get(key):
                continue
            master, st = proc(r[key], r["id"])
            sheet_rows.append((tag, f"{label} {ascii_tag(pathlib.Path(r[key]).name)}", master))
            raws.append(raw_tile(r[key]))
            report.append({"id": r["id"], "role": label, "file": str(r[key]), "sha256": gen.sha(pathlib.Path(r[key]).read_bytes()),
                           "size": list(Image.open(r[key]).size), "stats": {k: (round(float(v), 4) if isinstance(v, (float, np.floating)) else bool(v) if isinstance(v, np.bool_) else v) for k, v in st.items()}})
    tmp = out.with_name(out.stem + ".tmp.jpg")
    m.make_sheet(sheet_rows, tmp)
    base = Image.open(tmp).convert("RGB")
    left = 272 + 10
    full = Image.new("RGB", (base.width + left, base.height), (60, 60, 64))
    full.paste(base, (left, 0))
    from PIL import ImageDraw
    d = ImageDraw.Draw(full)
    d.text((10, 8), "raw original (256)", fill=(230, 230, 230))
    for i, t in enumerate(raws):
        full.paste(t, (10, 30 + i * 290 + 14))
    full.save(out, quality=90)
    tmp.unlink()
    out.with_suffix(".rows.jsonl").write_text(json.dumps({"sheet": str(out), "kind": a.kind, "rows": report}, ensure_ascii=False) + "\n",
                                        encoding="utf-8", newline="\n")
    for x in report:
        print(f"{x['id']} [{x['role']}] {x['size']} {x['stats']}")
    print("sheet:", out, Image.open(out).size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
