"""Eye line / head top / feet of the three witches in one table, and how far they drift when placed side by side.
Pillow + NumPy only. Reads tools/art/portrait_slots.json (anchors written by a person for the v02 originals) and,
for the living-portrait source images, chapter1/view/hud/living_portrait/*.json + the layer PNGs.

  python tools/art/portrait_anchor_table.py [--heights 400,800] [--out DIR] [--slots JSON]
  python tools/art/portrait_anchor_table.py --selftest

Two sets are printed because two different pictures exist:
  A. v02 originals (chapter1/art/characters): anchors from portrait_slots.json (frost eye is exact from the json,
     the rest are marked 눈대중 in the slots file).
  B. living-portrait source (chapter1/art/portraits/<w>/layers): eye = json eyes.pos + eye image size/2;
     head top = highest opaque pixel of head + hair layers; feet = lowest opaque pixel of the leg layers. (ember and
     storm differ from their v02 pictures; frost is the same picture.)
Two ways of putting them side by side (numbers only, no judgement):
  same-canvas: all three at the same scale on the same 1536 px canvas (what a fixed portrait rectangle does).
  feet+height: scaled so head-top -> feet is the same height, feet on one line (what a line-up on a floor does);
               px are then in canvas px of the scaled picture, eye drift = distance of the eye line from the others.
Output DIR/anchor_table.txt (default _local/art/anchors). Nothing is written below chapter1/.
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import portrait_motion_table as pmt  # noqa: E402

ROOT = pmt.ROOT
WITCHES = pmt.WITCHES
DEFAULT_SLOTS = ROOT / "tools" / "art" / "portrait_slots.json"
DEFAULT_OUT = ROOT / "_local" / "art" / "anchors"
CANVAS_H = 1536.0


def v02_set(spec):
    out = {}
    for w in WITCHES:
        a = spec["witches"][w]["anchors"]
        out[w] = {"eye_x": a["eye"]["x"], "eye_y": a["eye"]["y"], "head_top": a["head_top"]["y"], "feet": a["feet"]["y"],
                  "src": spec["witches"][w].get("anchor_source", "")[:60]}
    return out


def layer_extent(png):
    p = pathlib.Path(png)
    if not p.exists():
        return None
    a = np.asarray(Image.open(p).convert("RGBA"))[..., 3]
    ys, xs = np.nonzero(a > pmt.ALPHA_MIN)
    if len(ys) == 0:
        return None
    return int(ys.min()), int(ys.max())


def source_set(lp_dir=pmt.LP_DIR, portrait_dir=pmt.PORTRAIT_DIR, root=ROOT):
    out = {}
    for w in WITCHES:
        c = json.loads((lp_dir / (w + ".json")).read_text(encoding="utf-8"))
        e = c["eyes"]
        half = Image.open(root / pmt.String_res(e["half"]))
        ex, ey = e["pos"][0] + half.size[0] / 2.0, e["pos"][1] + half.size[1] / 2.0
        tops, feet = [], []
        for L in c["layers"]:
            ext = layer_extent(portrait_dir / w / "layers" / (L["id"] + ".png"))
            if ext is None:
                continue
            if L["kind"] == "head" or (L["kind"] == "spring" and L.get("follow") == "head"):
                tops.append(ext[0])
            if L.get("legs"):
                feet.append(ext[1])
        out[w] = {"eye_x": ex, "eye_y": ey, "head_top": min(tops) if tops else None, "feet": max(feet) if feet else None, "src": "json+layers"}
    return out


def table(title, data, heights):
    lines = ["## " + title, "witch | eye_x | eye_y | head_top | feet | figure_h(feet-head_top) | eye_from_feet_frac"]
    for w in WITCHES:
        d = data[w]
        if d["head_top"] is None or d["feet"] is None:
            lines.append("%s | %.1f | %.1f | - | - | - | -" % (w, d["eye_x"], d["eye_y"]))
            continue
        fh = d["feet"] - d["head_top"]
        lines.append("%s | %.1f | %.1f | %.0f | %.0f | %.0f | %.3f" % (w, d["eye_x"], d["eye_y"], d["head_top"], d["feet"], fh, (d["feet"] - d["eye_y"]) / fh))
    ok = all(data[w]["head_top"] is not None and data[w]["feet"] is not None for w in WITCHES)
    if not ok:
        return lines + [""]
    lines += ["", "same-canvas: difference to the mean of the three (canvas px; + = lower on the canvas) and display px at the heights"]
    lines.append("item | " + " | ".join(WITCHES) + " | max-min canvas px | " + " | ".join("max-min display px @%d" % h for h in heights))
    for key, lab in (("eye_y", "eye line"), ("head_top", "head top"), ("feet", "feet")):
        vals = [data[w][key] for w in WITCHES]
        mean = sum(vals) / 3.0
        spread = max(vals) - min(vals)
        lines.append("%s | %s | %.0f | %s" % (lab, " | ".join("%+.0f" % (v - mean) for v in vals), spread, " | ".join("%.1f" % (spread * h / CANVAS_H) for h in heights)))
    lines += ["", "feet+height: scaled to the mean figure height, feet on one line; value = height of that point above the feet line (scaled canvas px)"]
    fhs = [data[w]["feet"] - data[w]["head_top"] for w in WITCHES]
    mfh = sum(fhs) / 3.0
    lines.append("item | " + " | ".join(WITCHES) + " | max-min canvas px | " + " | ".join("max-min display px @%d" % h for h in heights) + " | scale used")
    ups = {}
    for key, lab in (("eye_y", "eye line above feet (head top = same by construction)"),):
        vals = [(data[w]["feet"] - data[w][key]) * (mfh / fhs[i]) for i, w in enumerate(WITCHES)]
        ups[key] = vals
        spread = max(vals) - min(vals)
        lines.append("%s | %s | %.0f | %s | scales %s" % (lab, " | ".join("%.0f" % v for v in vals), spread, " | ".join("%.1f" % (spread * h / CANVAS_H) for h in heights),
                                                       "/".join("%.3f" % (mfh / f) for f in fhs)))
    return lines + [""]


def run(spec_path, heights, out_dir, quiet=False):
    spec = json.loads(pathlib.Path(spec_path).read_text(encoding="utf-8"))
    lines = ["# 세 마녀 눈높이·머리 윗선·발끝 (숫자만. 좌표는 캔버스 1024x1536 px, 위가 0)", "",
             "A의 값은 사람이 적은 앵커(눈대중, +-15px)다. 어긋남이 이 오차보다 작으면 의미가 없다.", ""]
    lines += table("A. v02 원화(chapter1/art/characters) — 앵커 파일", v02_set(spec), heights)
    lines += table("B. 움직이는 초상의 원본(layers) — json 눈 위치와 레이어 알파", source_set(), heights)
    text = "\n".join(lines)
    od = pmt.check_out(out_dir)
    od.mkdir(parents=True, exist_ok=True)
    (od / "anchor_table.txt").write_text(text, encoding="utf-8", newline="\n")
    if not quiet:
        print(text)
        print("written: %s" % (od / "anchor_table.txt"))
    return text


def selftest():
    ok = True

    def check(c, msg):
        nonlocal ok
        print(("PASS " if c else "FAIL ") + msg)
        ok = ok and bool(c)

    data = {"ember": {"eye_x": 0, "eye_y": 100, "head_top": 0, "feet": 1000, "src": ""},
            "frost": {"eye_x": 0, "eye_y": 120, "head_top": 20, "feet": 1020, "src": ""},
            "storm": {"eye_x": 0, "eye_y": 100, "head_top": 0, "feet": 500, "src": ""}}
    t = "\n".join(table("t", data, [768]))
    check("eye line | -7 | +13 | -7 | 20 | 10.0" in t, "same-canvas eye spread 20 canvas px = 10 display px at 768 (%s)" % [l for l in t.split("\n") if l.startswith("eye line |")])
    # feet+height: storm figure is half as tall -> scaled x1.5 (mean fh = (1000+1000+500)/3)
    mfh = 2500 / 3.0
    up_storm = (500 - 100) * (mfh / 500)
    check(("%.0f" % up_storm) in t, "feet+height scaling of the short figure present (%.0f)" % up_storm)
    check(len(table("t", {w: dict(data[w], head_top=None) for w in data}, [768])) >= 3, "missing head/feet rows do not crash")
    print("SELFTEST " + ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--heights", default="400,800")
    ap.add_argument("--slots", default=str(DEFAULT_SLOTS))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    run(a.slots, [float(x) for x in a.heights.split(",")], a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
