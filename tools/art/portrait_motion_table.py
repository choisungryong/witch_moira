"""Living-portrait motion numbers as pixel displacements (A6 8.7 / TOOLS-REVIEW 2). Reads, never edits, the
three configs chapter1/view/hud/living_portrait/{ember,frost,storm}.json; Pillow + NumPy only; no Godot.

  python tools/art/portrait_motion_table.py [--heights 200,400,800] [--zoom 1.0] [--motion-scale 1.0] [--deep]
                                            [--flag-ratio 1.5] [--flag-min-diff 0.3] [--out DIR]
  python tools/art/portrait_motion_table.py --selftest

Every row is a peak-to-peak range (the most the part travels from one end to the other) in
  - image px: pixels of the 1024x1536 portrait canvas (the original-art scale), and
  - display px: image px * s, s = H / 1536 * zoom, for each --heights H (the portrait rectangle's height in screen
    px; this assumes the rectangle is at least 2:3 so the height decides the fit, as in living_portrait.gd _layout()).
Rows are marked exact / approx ("근사") / upper bound ("상한"). Where the same row differs between witches by
max/min >= --flag-ratio and by >= --flag-min-diff image px the row is marked with *. The mark is a number rule,
not a judgement of "natural" or "too big".
Output: DIR/motion_table.txt and motion_table.csv (default _local/art/motion). Nothing is written below chapter1/.

How the numbers follow the code (living_portrait.gd, rig_field.gdshaderinc, rig_cloth.gdshader):
  k = motion_scale * motion_gain (json); chapter_hud.gd _portrait_motion_scale() returns 1.0.
  _wave(t) runs 0..1.0 (0.9*f + 0.1*(0.5+0.5 sin), f in 0..1); a deep breath makes f 1.25x -> 0..1.225 (--deep uses 1.225).
  The shader moves the image by +d (samples at p - d), so image px = d exactly.
"""
import argparse
import csv
import json
import math
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
LP_DIR = ROOT / "chapter1" / "view" / "hud" / "living_portrait"
PORTRAIT_DIR = ROOT / "chapter1" / "art" / "portraits"
WITCHES = ["ember", "frost", "storm"]
DEFAULT_OUT = ROOT / "_local" / "art" / "motion"
CANVAS_H = 1536.0
ALPHA_MIN = 32


def lever(layer_png, pivot):
    """Farthest opaque pixel (alpha > 32) from pivot -> (distance px, (x, y)), or None when the PNG is missing."""
    p = pathlib.Path(layer_png)
    if not p.exists():
        return None
    a = np.asarray(Image.open(p).convert("RGBA"))[..., 3]
    ys, xs = np.nonzero(a > ALPHA_MIN)
    if len(xs) == 0:
        return None
    d = np.hypot(xs - pivot[0], ys - pivot[1])
    i = int(np.argmax(d))
    return float(d[i]), (int(xs[i]), int(ys[i]))


def top_point(layer_png):
    p = pathlib.Path(layer_png)
    if not p.exists():
        return None
    a = np.asarray(Image.open(p).convert("RGBA"))[..., 3]
    ys, xs = np.nonzero(a > ALPHA_MIN)
    if len(ys) == 0:
        return None
    i = int(np.argmin(ys))
    return int(xs[i]), int(ys[i])


def rad(deg):
    return math.radians(deg)


def build_rows(cfgs, wmax, motion_scale, portrait_dir):
    """cfgs: {witch: cfg dict}. Returns list of rows: dict(key, label, unit, basis, exact, vals{witch: float|None}, note)."""
    rows = []

    def add(key, label, basis, exact, vals, note=""):
        rows.append({"key": key, "label": label, "basis": basis, "exact": exact, "vals": vals, "note": note})

    def per(fn):
        out = {}
        for w, c in cfgs.items():
            try:
                out[w] = fn(w, c)
            except (KeyError, TypeError):
                out[w] = None
        return out

    def m(c, key, default=0.0):
        return float(c.get("motion", {}).get(key, default))

    def kk(c):
        return motion_scale * float(c.get("motion_gain", 1.0))

    # --- breathing and weight shift (body field, whole-image px)
    add("chest_rise", "가슴 오르내림(가슴 위 전체)", "py:496 chest.y = -chest_rise*wave*k", "정확",
        per(lambda w, c: m(c, "chest_rise") * kk(c) * wmax))
    add("pelvis_y", "골반 오르내림", "py:495 pelvis.y = -pelvis_y*wave*k; 발목에서 0으로 줄어듦(rig_field 하반신 가중)", "정확",
        per(lambda w, c: m(c, "pelvis_y") * kk(c) * wmax))
    add("arm_extra", "왼팔 윗부분 추가 들림", "py:497, 셰이더 body_disp smoothstep(500,380,y)", "정확",
        per(lambda w, c: m(c, "arm_extra") * kk(c) * wmax))
    add("shoulder_open", "어깨 벌어짐(팔 하나가 가로로)", "py:519 open_px, py:619 open_dx = open(+-1)*open_px", "정확(팔 하나). 두 팔 사이 간격 변화는 2배",
        per(lambda w, c: m(c, "shoulder_open") * kk(c) * wmax))
    add("pelvis_x", "무게 이동 골반 가로 (좌우 끝에서 끝)", "py:500 pelvis.x = pelvis_x*shift*k, shift -1..1 (py:499 clamp)", "정확",
        per(lambda w, c: 2.0 * m(c, "pelvis_x") * kk(c)))
    add("chest_x", "무게 이동 가슴 가로 (골반의 0.35배)", "py:501 chest.x = pelvis.x*0.35", "정확",
        per(lambda w, c: 2.0 * 0.35 * m(c, "pelvis_x") * kk(c)))
    add("knee", "무릎 옆으로(한쪽 무릎, 무릎 높이에서)", "py:502-507 knee*bend*k, bend 0..(0.75+0.25*wave max); 셰이더 가우스 폭 130px 중심값", "정확(무릎 높이 중심, 주변은 줄어듦)",
        per(lambda w, c: m(c, "knee") * kk(c) * (0.75 + 0.25 * wmax)))
    add("knee_dy", "무릎 아래로(한쪽 무릎)", "py:508-509 knee_dy = 0.5*knee*bend*k", "정확",
        per(lambda w, c: 0.5 * m(c, "knee") * kk(c) * (0.75 + 0.25 * wmax)))
    add("tilt_hip", "엉덩이 높이 어긋남(한쪽 끝에서 끝)", "py:510-512 tilt_px = tilt_deg*0.0175*100*k, 좌 +tilt_px*shift 우 -tilt_px*shift; 한쪽 2*tilt_px", "정확(각도->px는 코드의 100px 팔 길이 상수)",
        per(lambda w, c: 2.0 * m(c, "tilt_deg") * 0.0175 * 100.0 * kk(c)))
    # --- head
    add("head_dx", "머리 가로 흔들림(머리 자체, 가슴 이동 제외)", "py:526 head_dx*sin*k", "정확",
        per(lambda w, c: 2.0 * m(c, "head_dx") * kk(c)))
    add("head_dy", "머리 세로 (head_extra 오르내림 + head_dy 흔들림)", "py:523 -head_extra*wave, py:527 head_dy*sin", "정확(두 파가 겹치는 최대)",
        per(lambda w, c: (m(c, "head_extra") * wmax + 2.0 * m(c, "head_dy")) * kk(c)))
    add("head_total_y", "머리 세로 합(가슴 오름 + 머리 항)", "chest_rise 와 head_dy/extra 의 합", "상한(위상이 달라 동시에 최대가 되는 일은 드묾)",
        per(lambda w, c: (m(c, "chest_rise") * wmax + m(c, "head_extra") * wmax + 2.0 * m(c, "head_dy")) * kk(c)))
    add("head_deg_total", "머리 기울기 총 각도(도, 끝에서 끝)", "py:524-525 nod 0.7*nod + head_deg*1.5 + tilt_event, 부호 양쪽으로 2배 폭", "상한(도). 각 항의 최댓값을 더함",
        per(lambda w, c: 2.0 * (m(c, "head_deg") * 1.5 + m(c, "tilt_event_deg") + 0.7 * m(c, "head_nod_deg")) * kk(c)))

    def head_pts(w, c):
        rig = c["rig"]["neck"]
        e = c["eyes"]
        half = Image.open(ROOT / String_res(e["half"]))
        ex = e["pos"][0] + half.size[0] / 2.0
        ey = e["pos"][1] + half.size[1] / 2.0
        r_eye = math.hypot(ex - rig[0], ey - rig[1])
        tp = top_point(portrait_dir / w / "layers" / "L4_head.png")
        r_top = math.hypot(tp[0] - rig[0], tp[1] - rig[1]) if tp else None
        return r_eye, r_top, (ex, ey), tp

    eye_r, top_r = {}, {}
    for w, c in cfgs.items():
        try:
            r_eye, r_top, ep, tp = head_pts(w, c)
            ang = rad(2.0 * (m(c, "head_deg") * 1.5 + m(c, "tilt_event_deg") + 0.7 * m(c, "head_nod_deg")) * kk(c))
            eye_r[w] = r_eye * ang
            top_r[w] = r_top * ang if r_top is not None else None
        except Exception:
            eye_r[w] = None
            top_r[w] = None
    add("head_rot_eye", "머리 기울기로 눈이 움직이는 거리", "눈 중심(json eyes.pos + 눈 그림 크기/2)과 neck 사이 거리 * 각도(라디안)", "근사(소각 근사, 상한 각도)", eye_r)
    add("head_rot_top", "머리 기울기로 머리 윗끝이 움직이는 거리", "L4_head.png 불투명 맨 윗점과 neck 사이 거리 * 각도", "근사(소각 근사, 상한 각도)", top_r)

    # --- per-layer rows
    ids = []
    for w, c in cfgs.items():
        for L in c.get("layers", []):
            if L["kind"] in ("cloth", "arm", "spring", "pendulum") and L["id"] not in ids:
                ids.append(L["id"])

    def layer_of(c, lid):
        for L in c.get("layers", []):
            if L["id"] == lid:
                return L
        return None

    for lid in ids:
        kind = next(L["kind"] for c in cfgs.values() for L in c["layers"] if L["id"] == lid)
        if kind == "cloth":
            def v(w, c, lid=lid):
                L = layer_of(c, lid)
                if L is None:
                    return None
                a = min(float(L.get("amp", 8.0)) * kk(c), float(L.get("amp_max", 1000.0)))
                return 2.0 * a
            add("cloth:" + lid, "천 %s 자락 끝 옆 흔들림(끝에서 끝)" % lid, "셰이더 rig_cloth amp*pow(s,1.5)*w, w -1..1 (0.72+0.28); py:606 amp 상한 amp_max", "정확(s=1 맨 끝)", per(v))
        elif kind == "arm":
            def vb(w, c, lid=lid):
                L = layer_of(c, lid)
                if L is None:
                    return None
                sh = L.get("breath_pivot", L["pivot"])
                lv = lever(portrait_dir / w / "layers" / (lid + ".png"), sh)
                if lv is None:
                    return None
                return abs(float(L.get("breath_deg", 1.0))) * wmax * kk(c) * rad(1.0) * lv[0]
            add("arm_breath:" + lid, "팔 %s 숨쉬기 들림(가장 먼 점)" % lid, "py:618 lift = breath_deg*arm_deg/arm_breath_deg = breath_deg*wave; 어깨(breath_pivot)에서 가장 먼 불투명 점 * 각도", "근사(소각 근사)", per(vb))

            def vr(w, c, lid=lid):
                L = layer_of(c, lid)
                if L is None:
                    return None
                lv = lever(portrait_dir / w / "layers" / (lid + ".png"), L["pivot"])
                if lv is None:
                    return None
                return 2.0 * float(L.get("rot_deg", 0.0)) * kk(c) * rad(1.0) * lv[0]
            add("arm_rot:" + lid, "팔 %s 느린 회전(가장 먼 점, 끝에서 끝)" % lid, "py:620 rot_deg*sin*k, pivot 에서 가장 먼 불투명 점 * 각도", "근사(소각 근사)", per(vr))
        elif kind in ("spring", "pendulum"):
            gain = 1.15 if kind == "spring" else 1.0

            def vs(w, c, lid=lid, gain=gain):
                L = layer_of(c, lid)
                if L is None:
                    return None
                lv = lever(portrait_dir / w / "layers" / (lid + ".png"), L["root"])
                if lv is None:
                    return None
                return 2.0 * float(L.get("amp_deg", 2.5)) * gain * kk(c) * rad(1.0) * lv[0]
            add("%s:%s" % (kind, lid), "%s %s 끝 흔들림(끝에서 끝)" % ("머리카락" if kind == "spring" else "추", lid),
                "py:578 amp_deg*(0.8 sin + 0.35 sin)*k(최대 1.15)" if kind == "spring" else "py:622 amp_deg*sin*k",
                "상한(용수철 필터가 줄이는 몫 무시, 소각 근사)" if kind == "spring" else "근사(소각 근사)", per(vs))
    # periods (context rows, seconds)
    add("body_period", "숨 주기(초)", "json motion.body_period", "정확", per(lambda w, c: m(c, "body_period", 3.4)), "단위 초(변위 아님)")
    add("shift_period", "무게 이동 주기(초)", "json motion.shift_period", "정확", per(lambda w, c: m(c, "shift_period", 8.3)), "단위 초(변위 아님)")
    return rows


def String_res(path):
    s = str(path)
    return s[len("res://"):] if s.startswith("res://") else s


def flags(rows, ratio, min_diff):
    out = {}
    for r in rows:
        vals = [v for v in r["vals"].values() if v is not None]
        if len(vals) < 2 or r["note"].startswith("단위 초"):
            out[r["key"]] = False
            continue
        hi, lo = max(vals), min(vals)
        diff = hi - lo
        rat = (hi / lo) if lo > 1e-9 else (float("inf") if hi > 1e-9 else 1.0)
        out[r["key"]] = bool(rat >= ratio and diff >= min_diff)
    return out


def fmt(v, nd=2):
    return "-" if v is None else ("%.*f" % (nd, v))


def render(rows, heights, zoom, flagmap, ratio, min_diff, motion_scale, wmax):
    names = WITCHES
    lines = ["# 초상 움직임 표 (숫자만. 크다/자연스럽다는 사용자가 본다)", "",
             "이미지 px = 1024x1536 캔버스(원화와 같은 크기) 기준 끝에서 끝 폭. 표시 px = 이미지 px * H/1536*zoom (zoom=%g, motion_scale=%g, 숨 최댓값 %.3f)." % (zoom, motion_scale, wmax),
             "표시 높이 H(초상 사각형의 높이): " + ", ".join(str(int(h)) for h in heights) + ". 사각형이 2:3보다 좁으면 가로가 맞춤을 정하므로 이 표를 쓰지 않는다.",
             "* = 세 마녀 사이 같은 항목이 max/min >= %g 이고 차이 >= %g 이미지 px (숫자 규칙).  정확 / 근사 / 상한 은 환산식의 성격." % (ratio, min_diff), ""]
    # table 1: image px
    lines.append("## 1. 이미지 px (ember / frost / storm)")
    lines.append("flag | item | ember | frost | storm | 성격 | 근거")
    for r in rows:
        v = r["vals"]
        lines.append("%s | %s | %s | %s | %s | %s | %s%s" % ("*" if flagmap[r["key"]] else " ", r["label"],
                     fmt(v.get("ember")), fmt(v.get("frost")), fmt(v.get("storm")), r["exact"], r["basis"], (" [" + r["note"] + "]") if r["note"] else ""))
    for h in heights:
        s = h / CANVAS_H * zoom
        lines += ["", "## 표시 높이 %d px (s = %.4f): 표시 px, ember / frost / storm" % (h, s), "flag | item | ember | frost | storm"]
        for r in rows:
            if r["note"].startswith("단위 초"):
                continue
            v = r["vals"]
            def d(x):
                return fmt(None if x is None else x * s, 2)
            lines.append("%s | %s | %s | %s | %s" % ("*" if flagmap[r["key"]] else " ", r["label"], d(v.get("ember")), d(v.get("frost")), d(v.get("storm"))))
    lines.append("")
    lines.append("각도 항목(머리 기울기 총 각도)은 도(degree)이므로 표시 높이 표에서는 px 환산이 아니다. 해당 줄은 위 1번 표에서만 읽는다.")
    return "\n".join(lines) + "\n"


def check_out(out_dir):
    out_dir = pathlib.Path(out_dir).resolve()
    if "_local" not in [p.name for p in out_dir.parents]:
        raise SystemExit("refusing to write: output dir must be below a folder named _local (%s)" % out_dir)
    ch = (ROOT / "chapter1").resolve()
    if ch in out_dir.parents or out_dir == ch:
        raise SystemExit("refusing to write below chapter1/")
    return out_dir


def run(heights, zoom, motion_scale, deep, ratio, min_diff, out_dir, lp_dir=LP_DIR, portrait_dir=PORTRAIT_DIR, quiet=False):
    cfgs = {w: json.loads((lp_dir / (w + ".json")).read_text(encoding="utf-8")) for w in WITCHES}
    wmax = 1.225 if deep else 1.0
    rows = build_rows(cfgs, wmax, motion_scale, portrait_dir)
    # the head angle row is degrees; keep it but remove it from the px height tables
    fm = flags(rows, ratio, min_diff)
    text = render(rows, heights, zoom, fm, ratio, min_diff, motion_scale, wmax)
    # drop the degree row from the per-height tables
    out = []
    in_h = False
    for ln in text.split("\n"):
        if ln.startswith("## 표시 높이"):
            in_h = True
        if in_h and "머리 기울기 총 각도" in ln:
            continue
        out.append(ln)
    text = "\n".join(out)
    od = check_out(out_dir)
    od.mkdir(parents=True, exist_ok=True)
    (od / "motion_table.txt").write_text(text, encoding="utf-8", newline="\n")
    with open(od / "motion_table.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["key", "label", "flag", "kind", "ember_img_px", "frost_img_px", "storm_img_px"] + ["%s_%d" % (n, h) for h in heights for n in WITCHES])
        for r in rows:
            v = r["vals"]
            disp = []
            for h in heights:
                s = h / CANVAS_H * zoom
                for n in WITCHES:
                    disp.append("" if v.get(n) is None else "%.3f" % (v[n] * s))
            w.writerow([r["key"], r["label"], "*" if fm[r["key"]] else "", r["exact"]] + ["" if v.get(n) is None else "%.3f" % v[n] for n in WITCHES] + disp)
    if not quiet:
        print(text)
        print("written: %s" % (od / "motion_table.txt"))
    return rows, fm, text


def selftest():
    import tempfile
    ok = True

    def check(c, msg):
        nonlocal ok
        print(("PASS " if c else "FAIL ") + msg)
        ok = ok and bool(c)

    base = {"canvas": [1024, 1536], "motion_gain": 1.0, "rig": {"neck": [100, 100]},
            "motion": {"chest_rise": 4.0, "pelvis_x": 5.0, "pelvis_y": 1.0, "knee": 3.5, "tilt_deg": 1.0, "head_deg": 1.0, "head_dx": 1.0,
                       "head_dy": 0.5, "tilt_event_deg": 1.0, "head_extra": 2.0, "head_nod_deg": 1.0, "shoulder_open": 1.0, "arm_extra": 1.0, "body_period": 3.0, "shift_period": 9.0},
            "layers": [{"id": "C", "kind": "cloth", "amp": 10.0, "amp_max": 6.0}]}
    big = json.loads(json.dumps(base))
    big["motion"]["chest_rise"] = 16.0
    cfgs = {"ember": base, "frost": big, "storm": base}
    rows = {r["key"]: r for r in build_rows(cfgs, 1.0, 1.0, pathlib.Path("/nonexistent"))}
    check(abs(rows["chest_rise"]["vals"]["ember"] - 4.0) < 1e-9, "chest_rise = 4 image px")
    check(abs(rows["chest_rise"]["vals"]["frost"] - 16.0) < 1e-9, "chest_rise 16 in the config")
    g2 = json.loads(json.dumps(base))
    g2["motion_gain"] = 2.0
    r2 = {r["key"]: r for r in build_rows({"ember": g2, "frost": base, "storm": base}, 1.0, 1.0, pathlib.Path("/nonexistent"))}
    check(abs(r2["chest_rise"]["vals"]["ember"] - 8.0) < 1e-9, "motion_gain doubles it")
    check(abs(rows["pelvis_x"]["vals"]["ember"] - 10.0) < 1e-9, "pelvis_x p-p = 2*5")
    check(abs(rows["tilt_hip"]["vals"]["ember"] - 3.5) < 1e-9, "tilt_hip p-p = 2*1*1.75")
    check(abs(rows["knee"]["vals"]["ember"] - 3.5 * 1.0) < 1e-9, "knee = knee*(0.75+0.25)")
    check(abs(rows["cloth:C"]["vals"]["ember"] - 12.0) < 1e-9, "cloth amp capped by amp_max: 2*6")
    check(abs(rows["head_deg_total"]["vals"]["ember"] - 2 * (1.5 + 1.0 + 0.7)) < 1e-9, "head angle total degrees")
    check(rows["head_rot_eye"]["vals"]["ember"] is None, "head eye row is None without the portrait files (no crash)")
    deep = {r["key"]: r for r in build_rows(cfgs, 1.225, 1.0, pathlib.Path("/nonexistent"))}
    check(abs(deep["chest_rise"]["vals"]["ember"] - 4.9) < 1e-9, "deep breath x1.225")
    half = {r["key"]: r for r in build_rows(cfgs, 1.0, 0.5, pathlib.Path("/nonexistent"))}
    check(abs(half["chest_rise"]["vals"]["ember"] - 2.0) < 1e-9, "motion_scale 0.5 halves it")
    fm = flags(list(rows.values()), 1.5, 0.3)
    check(fm["chest_rise"] is True and fm["pelvis_x"] is False, "flag: chest_rise differs (4 vs 16), pelvis_x same")
    # lever with a synthetic layer
    with tempfile.TemporaryDirectory() as td:
        im = Image.new("RGBA", (1024, 1536), (0, 0, 0, 0))
        for x in range(100, 110):
            for y in range(100, 110):
                im.putpixel((x, y), (255, 255, 255, 255))
        for x in range(400, 404):
            im.putpixel((x, 100), (255, 255, 255, 255))
        f = pathlib.Path(td) / "a.png"
        im.save(f)
        lv = lever(f, (100, 100))
        check(lv is not None and abs(lv[0] - 303.0) < 1e-9 and lv[1] == (403, 100), "lever finds the farthest opaque pixel (%s)" % (lv,))
        check(top_point(f) == (100, 100), "top point")
    try:
        check_out(ROOT / "chapter1" / "x")
        check(False, "out guard")
    except SystemExit:
        check(True, "out guard refuses chapter1/ and non-_local")
    print("SELFTEST " + ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--heights", default="200,400,800")
    ap.add_argument("--zoom", type=float, default=1.0)
    ap.add_argument("--motion-scale", type=float, default=1.0)
    ap.add_argument("--deep", action="store_true", help="use the deep-breath wave maximum 1.225 instead of 1.0")
    ap.add_argument("--flag-ratio", type=float, default=1.5)
    ap.add_argument("--flag-min-diff", type=float, default=0.3)
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    hs = [float(x) for x in a.heights.split(",") if x.strip()]
    run(hs, a.zoom, a.motion_scale, a.deep, a.flag_ratio, a.flag_min_diff, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
