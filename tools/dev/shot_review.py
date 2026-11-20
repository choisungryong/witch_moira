"""캡처 전후 비교와 화면 측정 (이미 찍힌 그림만 본다. Godot를 돌리지 않는다).

수치는 판정의 보조다. 미감과 읽힘은 사람이 본다.

사용:
  측정만:  python tools/dev/shot_review.py <캡처폴더> --out=_local/<경로>
  전·후:   python tools/dev/shot_review.py <전폴더> <후폴더> --out=_local/<경로>
  임계값:  --limits=<json>   (기본 파일은 없다. 값은 art-lead가 정한다. 예시: tools/dev/test_data/shot_review_limits.example.json)

인수:
  --play=x0,y0,x1,y1       플레이 영역(1080p 좌표). 기본 0,90,1920,900
  --exclude=a,b,c,d;e,f,g,h  플레이 영역에서 더 뺄 사각형(1080p 좌표). 기본 1500,0,1920,200
  --hero=x0,y0,x1,y1       주인공 자리(흰 포화 측정). 기본 905,400,1015,575
  --hero-crop=x0,y0,x1,y1  주인공 확대 그림 범위. 기본 860,360,1080,620
  --diff-thr=N             "바뀐 화소" 기준(채널 최대 차, 0..255). 기본 24
  --no-images              수치 표만

이미지 처리는 Pillow와 NumPy만 쓴다(tools/art/make_equipment_icons.py와 같은 환경).
출력은 경로에 '_local' 폴더가 들어 있을 때만 쓴다.

합친 일회용 스크립트와 고른 정의는 _local/tools/shot-review/REPORT.txt에 적었다.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

DISCLAIMER = "수치는 판정의 보조다. 미감과 읽힘은 사람이 본다."

LIMITATIONS = [
    "밝기(Y)는 sRGB 값 0..1에 0.2126R+0.7152G+0.0722B를 그대로 쓴 것이다(선형화 없음). 화면에서 읽히는 쪽에 맞춘 것이고 물리 휘도가 아니다.",
    "플레이 영역은 인수로 준 사각형에서 제외 사각형을 뺀 것이다. HUD 레이아웃이 바뀌면 인수를 바꿔야 하고, 다른 해상도는 1080p 좌표를 비례 환산한다.",
    "흰 포화 비율은 Y>0.95인 화소의 비율이다. 순백 덩어리는 R,G,B 모두 245 이상인 화소만 4방향으로 이은 것이며(닫기 연산 없음), 지름은 1080p 환산 화소다. 빛 번짐이 덩어리를 끊으면 지름이 작게 나온다.",
    "진홍(전조 색) 면적은 색상 H가 330~360 또는 0~12, 채도>0.45, 명도>0.45인 화소의 비율이다. 원거리 적의 지팡이 머리, 붉은 소품, 피 효과가 섞이므로 전조 면적이 아니라 상한이다.",
    "주인공 자리 흰 포화는 카메라가 화면 가운데를 따른다는 가정으로 고정 사각형을 잰다. 카메라가 멈춘 장면, 메뉴, 마을 장면에서는 뜻이 없다.",
    "가운데/모서리 비는 플레이 영역 가운데 30%x30% 평균 밝기를 네 모서리(각 20%x20%) 평균 밝기로 나눈 것이다. 가운데가 어두운 장면에서는 1 미만이 된다.",
    "채도는 HSV 채도의 평균이다(명도 0.05 이하 화소는 0). 어두운 장면에서는 영향을 받는 화소가 적다.",
    "바뀐 화소 비율은 채널 최대 차가 기준 초과인 화소의 비율이다. 애니메이션, 입자, 임의 시드 차이도 바뀐 것으로 센다. 같은 시드·같은 시각의 캡처끼리만 뜻이 있다.",
    "한 장면의 캡처 한 장이다. 한 장으로 흐름(깜빡임, 번쩍임의 지속)은 알 수 없다.",
]

METRIC_ORDER = [
    ("lum_p50", "밝기 p50", "{:.3f}"),
    ("lum_p90", "밝기 p90", "{:.3f}"),
    ("lum_p99", "밝기 p99", "{:.3f}"),
    ("white_pct", "흰 포화 %", "{:.2f}"),
    ("white_blob_diam", "순백 덩어리 지름(bbox px)", "{:.0f}"),
    ("white_blob_diam_eq", "순백 덩어리 지름(등가원 px)", "{:.0f}"),
    ("dark_pct", "어두운 %", "{:.1f}"),
    ("sat_mean", "채도", "{:.3f}"),
    ("threat_pct", "진홍 면적 %", "{:.2f}"),
    ("threat_dark_pct", "어두운 붉은 면적 % (U-56: 채움 쪽)", "{:.2f}"),
    ("red_excess", "붉기 평균 (R - max(G,B), 0..100)", "{:.2f}"),
    ("hero_white_pct", "주인공 자리 흰 포화 %", "{:.2f}"),
    ("center_corner_ratio", "가운데/모서리 밝기 비", "{:.2f}"),
]
DIFF_KEYS = [("changed_pct", "바뀐 화소 % (플레이 영역)", "{:.2f}"),
             ("changed_pct_all", "바뀐 화소 % (전체)", "{:.2f}")]

DEFAULTS = {
    "play": (0, 90, 1920, 900),
    "exclude": [(1500, 0, 1920, 200)],
    "hero": (905, 400, 1015, 575),
    "hero_crop": (860, 360, 1080, 620),
    "diff_thr": 24,
}


# ---------------------------------------------------------------- 측정

def luminance(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def hsv(a):
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = m & (mx == r)
    gc = m & (mx == g) & ~rc
    bc = m & ~rc & ~gc
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    return h * 60.0, s, mx


def scale_box(box, w, h):
    """1080p 좌표 사각형을 w x h 그림에 맞춰 환산(정수, 그림 안으로 자름)."""
    fx, fy = w / 1920.0, h / 1080.0
    x0 = max(0, min(w, int(round(box[0] * fx))))
    x1 = max(0, min(w, int(round(box[2] * fx))))
    y0 = max(0, min(h, int(round(box[1] * fy))))
    y1 = max(0, min(h, int(round(box[3] * fy))))
    return x0, y0, x1, y1


def play_mask(w, h, cfg):
    x0, y0, x1, y1 = scale_box(cfg["play"], w, h)
    m = np.zeros((h, w), dtype=bool)
    m[y0:y1, x0:x1] = True
    for ex in cfg["exclude"]:
        a, b, c, d = scale_box(ex, w, h)
        m[b:d, a:c] = False
    return m, (x0, y0, x1, y1)


def largest_white_blob(mask):
    """4방향 연결 덩어리 중 bbox 한 변이 가장 긴 것의 (bbox 최대변, 등가원 지름, 넓이, 위치). 없으면 None.
    NumPy와 파이썬만 쓴다(행 구간 + union-find)."""
    h, w = mask.shape
    starts, ends, rows = [], [], []
    for y in range(h):
        row = mask[y]
        if not row.any():
            continue
        padded = np.concatenate(([False], row, [False]))
        dd = np.diff(padded.astype(np.int8))
        s = np.nonzero(dd == 1)[0]
        e = np.nonzero(dd == -1)[0]  # 끝은 배타
        for a, b in zip(s.tolist(), e.tolist()):
            starts.append(a)
            ends.append(b)
            rows.append(y)
    n = len(starts)
    if n == 0:
        return None
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i, j):
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[rj] = ri

    # 행별 구간 색인
    first = {}
    for i, y in enumerate(rows):
        first.setdefault(y, [i, i])
        first[y][1] = i
    for y, (i0, i1) in first.items():
        if (y - 1) not in first:
            continue
        j0, j1 = first[y - 1]
        j = j0
        for i in range(i0, i1 + 1):
            while j <= j1 and ends[j] <= starts[i]:
                j += 1
            k = j
            while k <= j1 and starts[k] < ends[i]:
                union(i, k)
                k += 1
    comp = {}
    for i in range(n):
        r = find(i)
        c = comp.get(r)
        area = ends[i] - starts[i]
        if c is None:
            comp[r] = [area, starts[i], rows[i], ends[i], rows[i] + 1]
        else:
            c[0] += area
            c[1] = min(c[1], starts[i])
            c[2] = min(c[2], rows[i])
            c[3] = max(c[3], ends[i])
            c[4] = max(c[4], rows[i] + 1)
    best = None
    for area, x0, y0, x1, y1 in comp.values():
        d = max(x1 - x0, y1 - y0)
        key = (d, area)
        if best is None or key > best[0]:
            best = (key, area, x0, y0, x1, y1)
    _, area, x0, y0, x1, y1 = best
    return max(x1 - x0, y1 - y0), float(np.sqrt(4.0 * area / np.pi)), area, (x0, y0)


def measure(rgb, cfg):
    """rgb: HxWx3 uint8. 반환: 지표 사전."""
    h, w, _ = rgb.shape
    f = w / 1920.0
    a = rgb.astype(np.float64) / 255.0
    pm, (px0, py0, px1, py1) = play_mask(w, h, cfg)
    n = int(pm.sum())
    out = {"play_pixels": n}
    if n == 0:
        for k, _, _ in METRIC_ORDER:
            out[k] = None
        return out
    y = luminance(a)
    yp = y[pm]
    out["lum_p50"] = float(np.percentile(yp, 50))
    out["lum_p90"] = float(np.percentile(yp, 90))
    out["lum_p99"] = float(np.percentile(yp, 99))
    out["white_pct"] = float((yp > 0.95).mean() * 100)
    out["dark_pct"] = float((yp < 0.08).mean() * 100)
    hh, ss, vv = hsv(a)
    out["sat_mean"] = float(np.where(vv > 0.05, ss, 0.0)[pm].mean())
    threat = ((hh >= 330) | (hh < 12)) & (ss > 0.45) & (vv > 0.45)
    out["threat_pct"] = float(threat[pm].mean() * 100)
    # U-56: 어두운 붉은 채움(명도 .18~.45)과 화면 전체 붉기. 전조의 채움은 밝지 않아 threat_pct에 잡히지 않는다.
    threat_dark = ((hh >= 330) | (hh < 15)) & (ss > 0.45) & (vv > 0.18) & (vv <= 0.45)
    out["threat_dark_pct"] = float(threat_dark[pm].mean() * 100)
    af = rgb.astype(np.float32) / 255.0
    out["red_excess"] = float(np.clip(af[..., 0] - np.maximum(af[..., 1], af[..., 2]), 0, None)[pm].mean() * 100)
    # 순백 덩어리(플레이 영역 안)
    pure = (rgb >= 245).all(axis=2) & pm
    blob = largest_white_blob(pure)
    if blob is None:
        out["white_blob_diam"] = 0.0
        out["white_blob_diam_eq"] = 0.0
        out["white_blob_at"] = None
    else:
        out["white_blob_diam"] = blob[0] / f
        out["white_blob_diam_eq"] = blob[1] / f
        out["white_blob_at"] = [round(blob[3][0] / f), round(blob[3][1] / f)]
    # 주인공 자리
    hx0, hy0, hx1, hy1 = scale_box(cfg["hero"], w, h)
    if hx1 > hx0 and hy1 > hy0:
        out["hero_white_pct"] = float((y[hy0:hy1, hx0:hx1] > 0.95).mean() * 100)
    else:
        out["hero_white_pct"] = None
    # 가운데/모서리
    pw, ph = px1 - px0, py1 - py0
    if pw > 0 and ph > 0:
        cx0, cx1 = px0 + int(pw * 0.35), px0 + int(pw * 0.65)
        cy0, cy1 = py0 + int(ph * 0.35), py0 + int(ph * 0.65)
        cw, ch = max(1, int(pw * 0.2)), max(1, int(ph * 0.2))
        corners = [(px0, py0), (px1 - cw, py0), (px0, py1 - ch), (px1 - cw, py1 - ch)]
        cm = float(y[cy0:cy1, cx0:cx1].mean())
        km = float(np.mean([y[cy:cy + ch, cx:cx + cw].mean() for cx, cy in corners]))
        out["center_corner_ratio"] = cm / km if km > 1e-6 else None
    else:
        out["center_corner_ratio"] = None
    return out


def diff_stats(ra, rb, cfg):
    """ra=전, rb=후 (uint8 HxWx3, 같은 크기). 반환 (지표, 차이 지도 uint8)."""
    d = np.abs(ra.astype(np.int16) - rb.astype(np.int16)).max(axis=2)
    h, w = d.shape
    pm, _ = play_mask(w, h, cfg)
    thr = cfg["diff_thr"]
    ch = d > thr
    return {
        "changed_pct": float(ch[pm].mean() * 100) if pm.any() else None,
        "changed_pct_all": float(ch.mean() * 100),
        "diff_mean": float(d.mean()),
        "diff_max": int(d.max()),
    }, d.astype(np.uint8)


# ---------------------------------------------------------------- 그림

def _label(im, text):
    ImageDraw.Draw(im).text((4, 4), text, fill=(255, 255, 0))
    return im


def _half(im):
    return im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)


def compare_image(pa, pb, d):
    """전 | 후 | 차이 지도(x4 증폭) 한 장, 각 칸은 반 크기."""
    w, h = pa.size
    dm = Image.fromarray(np.clip(d.astype(np.int32) * 4, 0, 255).astype(np.uint8)).convert("RGB")
    tiles = [_label(_half(pa.convert("RGB")), "before"), _label(_half(pb.convert("RGB")), "after"),
             _label(_half(dm), "diff x4")]
    sheet = Image.new("RGB", (sum(t.width for t in tiles), tiles[0].height))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width
    return sheet


def gray_tile(im, label):
    """가운데 60%x60%를 흑백 + 가벼운 흐림, 반 크기(계열을 모양으로 가르는지 보는 용도)."""
    w, h = im.size
    box = (int(w * .2), int(h * .2), int(w * .8), int(h * .8))
    g = ImageOps.grayscale(im.convert("RGB").crop(box)).filter(ImageFilter.GaussianBlur(1.5))
    g = g.resize((max(1, g.width // 2), max(1, g.height // 2))).convert("RGB")
    return _label(g, label)


def hero_tile(im, box, label, scale=3):
    w, h = im.size
    x0, y0, x1, y1 = scale_box(box, w, h)
    crop = im.convert("RGB").crop((x0, y0, x1, y1))
    crop = crop.resize((max(1, crop.width * scale), max(1, crop.height * scale)), Image.NEAREST)
    d = ImageDraw.Draw(crop)
    f = h / 1080.0
    for yy in range(int(box[1]) - int(box[1]) % 10 + 10, int(box[3]), 10):  # 1080p 좌표 10px 눈금
        py = int(round(yy * f)) - y0
        if py < 0 or py >= (y1 - y0):
            continue
        major = yy % 50 == 0
        d.line([(0, py * scale), (18 if major else 8, py * scale)],
               fill=(255, 255, 0) if major else (200, 200, 200), width=1)
        if major:
            d.text((20, py * scale - 6), str(yy), fill=(255, 255, 0))
    return _label(crop, label)


def hstack(tiles):
    sheet = Image.new("RGB", (sum(t.width for t in tiles), max(t.height for t in tiles)))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width
    return sheet


# ---------------------------------------------------------------- 임계값

def load_limits(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and isinstance(data.get("limits"), dict):
        data = data["limits"]
    lim = {}
    for k, v in data.items():
        if k.startswith("_") or not isinstance(v, dict):
            continue
        lim[k] = (v.get("min"), v.get("max"))
    return lim


def check_limits(metrics, limits):
    """지표 사전 -> {키: 'ok'|'low'|'high'|'none'} (임계값이 있는 키만)."""
    res = {}
    for k, (lo, hi) in limits.items():
        v = metrics.get(k)
        if v is None:
            res[k] = "none"
        elif lo is not None and v < lo:
            res[k] = "low"
        elif hi is not None and v > hi:
            res[k] = "high"
        else:
            res[k] = "ok"
    return res


# ---------------------------------------------------------------- 입출력

def list_images(folder):
    out = {}
    for n in sorted(os.listdir(folder)):
        if n.lower().endswith((".png", ".jpg", ".jpeg")):
            out.setdefault(os.path.splitext(n)[0], os.path.join(folder, n))
    return out


def load_rgb(path):
    return Image.open(path).convert("RGB")


def parse_box(s):
    v = [float(x) for x in s.split(",")]
    if len(v) != 4:
        raise ValueError("사각형은 x0,y0,x1,y1 네 값이다: " + s)
    return tuple(v)


def _check_out(path):
    parts = os.path.normpath(os.path.abspath(path)).replace("\\", "/").split("/")
    if "_local" not in parts:
        raise SystemExit("출력 경로에 '_local' 폴더가 들어 있어야 한다: " + path)


def fmt_val(key, v, table):
    if v is None:
        return "-"
    for k, _, f in table:
        if k == key:
            return f.format(v)
    return str(v)


def run(before, after, out_dir, cfg, limits=None, images=True):
    """before: 폴더(측정만이면 이것만 준다), after: 폴더 또는 None. 결과 사전을 돌려주고 파일을 쓴다."""
    os.makedirs(out_dir, exist_ok=True)
    compare = after is not None
    a_imgs = list_images(before)
    b_imgs = list_images(after) if compare else {}
    if compare:
        names = [n for n in a_imgs if n in b_imgs]
        only_before = [n for n in a_imgs if n not in b_imgs]
        only_after = [n for n in b_imgs if n not in a_imgs]
    else:
        names = list(a_imgs)
        only_before, only_after = [], []
    result = {"disclaimer": DISCLAIMER, "limitations": LIMITATIONS,
              "config": {"play": cfg["play"], "exclude": cfg["exclude"], "hero": cfg["hero"],
                         "hero_crop": cfg["hero_crop"], "diff_thr": cfg["diff_thr"]},
              "before_dir": os.path.abspath(before), "after_dir": os.path.abspath(after) if compare else None,
              "unpaired_before": only_before, "unpaired_after": only_after,
              "skipped": [], "images": {}}
    for n in names:
        ia = load_rgb(a_imgs[n])
        rec = {"before": measure(np.asarray(ia), cfg)}
        ib = None
        if compare:
            ib = load_rgb(b_imgs[n])
            rec["after"] = measure(np.asarray(ib), cfg)
            if ia.size != ib.size:
                result["skipped"].append({"name": n, "reason": "크기 다름 %s vs %s: 차이·비교 그림 생략" % (ia.size, ib.size)})
                d = None
            else:
                rec["diff"], d = diff_stats(np.asarray(ia), np.asarray(ib), cfg)
        if limits:
            target = rec["after"] if compare else rec["before"]
            rec["limits"] = check_limits({**target, **rec.get("diff", {})}, limits)
        if images:
            gtiles = [gray_tile(ia, "before " + n)]
            htiles = [hero_tile(ia, cfg["hero_crop"], "before " + n)]
            if compare:
                gtiles.append(gray_tile(ib, "after " + n))
                htiles.append(hero_tile(ib, cfg["hero_crop"], "after " + n))
                if d is not None:
                    compare_image(ia, ib, d).save(os.path.join(out_dir, n + "-cmp.png"))
            hstack(gtiles).save(os.path.join(out_dir, n + "-gray.png"))
            hstack(htiles).save(os.path.join(out_dir, n + "-hero.png"))
        result["images"][n] = rec
    with open(os.path.join(out_dir, "metrics.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
        f.write("\n")
    with open(os.path.join(out_dir, "metrics.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(to_markdown(result, compare, limits))
    return result


def to_markdown(result, compare, limits):
    L = []
    L.append("# 캡처 측정표")
    L.append("")
    L.append("**" + result["disclaimer"] + "**")
    L.append("")
    L.append("한계:")
    for s in result["limitations"]:
        L.append("- " + s)
    L.append("")
    c = result["config"]
    L.append("설정: 플레이 영역 %s, 제외 %s, 주인공 자리 %s, 주인공 확대 %s, 바뀐 화소 기준 %s (좌표는 1080p)" % (
        c["play"], c["exclude"], c["hero"], c["hero_crop"], c["diff_thr"]))
    L.append("전: " + result["before_dir"] + ("  후: " + result["after_dir"] if compare else ""))
    if limits:
        L.append("임계값: 있음. 표의 [높음]/[낮음]은 범위 밖, [없음]은 값 없음. %s의 지표만 검사한다." % ("후" if compare else "측정"))
    else:
        L.append("임계값: 주지 않았다. 범위 판정 없음.")
    for k in ("unpaired_before", "unpaired_after"):
        if result[k]:
            L.append("짝 없음(%s): %s" % ("전에만" if k.endswith("before") else "후에만", ", ".join(result[k])))
    for s in result["skipped"]:
        L.append("건너뜀: %s - %s" % (s["name"], s["reason"]))
    L.append("")
    table = METRIC_ORDER + DIFF_KEYS
    head = ["그림", "구분"] + [t for _, t, _ in METRIC_ORDER]
    if compare:
        head += [t for _, t, _ in DIFF_KEYS]
    L.append("| " + " | ".join(head) + " |")
    L.append("|" + "---|" * len(head))

    def mark(key, rec):
        st = rec.get("limits", {}).get(key)
        return {"low": " [낮음]", "high": " [높음]", "none": " [없음]"}.get(st, "")

    for n, rec in result["images"].items():
        rows = [("전", rec["before"])]
        if compare:
            rows.append(("후", rec["after"]))
        for label, m in rows:
            cells = [n, label]
            for k, _, _ in METRIC_ORDER:
                v = fmt_val(k, m.get(k), table)
                if (label == "후") or not compare:
                    v += mark(k, rec)
                cells.append(v)
            if compare:
                cells += ["", ""]
            L.append("| " + " | ".join(cells) + " |")
        if compare:
            cells = [n, "후-전"]
            for k, _, f in METRIC_ORDER:
                a, b = rec["before"].get(k), rec["after"].get(k)
                cells.append("-" if a is None or b is None else ("{:+" + f[2:]).format(b - a))
            for k, _, _ in DIFF_KEYS:
                cells.append(fmt_val(k, rec.get("diff", {}).get(k), table) + mark(k, rec))
            L.append("| " + " | ".join(cells) + " |")
    outs = []
    for n, rec in result["images"].items():
        for k, st in rec.get("limits", {}).items():
            if st != "ok":
                outs.append("%s: %s %s" % (n, k, st))
    if limits:
        L.append("")
        L.append("범위 밖 %d건" % len(outs) + (":" if outs else "."))
        for s in outs:
            L.append("- " + s)
    L.append("")
    return "\n".join(L)


# ---------------------------------------------------------------- 주인공 자르기 측정과 판 A·B (A7-0, 지시서 2.5절)
# 입력: rig_game_probe.gd --hero-mask --hero-crop-ticks=...가 낸 폴더(crop_tNNNN.png + crop_tNNNN.mask.png, 240x240 원 크기).
# 가면(.mask.png)의 알파가 "주인공 화소"다. 가림(앞에 선 적, 효과)은 가면이 무시하므로 가면 안에는 위에 덮인 효과 화소도 들어 있다.

ELEMENT_HUE = {"ember": 27.0, "frost": 186.0, "arc": 227.0}  # 게임의 원소색 ff943d, 9ce7ef, 8fa6ff의 색상(도). --element-hue로 바꾼다(예: arc=248).
HERO_BAND_PX = 12      # 가면 바깥 고리띠 폭(2.5절 4번째 잰 값)
EFFECT_LUM_MIN = 0.45  # 고리띠 안에서 "효과 화소"로 세는 최소 밝기(바닥과 효과를 가르는 근사. 지시서에 정의가 없어 이 도구가 정한 값)
HERO_LIMITS = {"white_pct_max": 10.0, "lum_mean": (0.30, 0.55), "element_pct": (12.0, 25.0), "other_element_pct_max": 5.0, "ring_gap_min": 0.20}


def hue_dist(h, target):
    d = np.abs(h - target) % 360.0
    return np.minimum(d, 360.0 - d)


def dilate(mask, px):
    """정사각 팽창(2px+1 한 변). PIL MaxFilter는 홀수 크기만 받는다."""
    im = Image.fromarray((mask * 255).astype(np.uint8))
    return np.array(im.filter(ImageFilter.MaxFilter(2 * px + 1))) > 127


EMIT_LUM_MIN = 0.08  # 발광만 그린 그림에서 "켜진" 화소로 세는 최소 최대채널 값


def measure_emit(path_emit):
    """crop_tNNNN.emit.png(rig_game_probe --hero-emit): 알파 = 주인공, 켜진 화소 = 발광 가면이 화면에 나온 화소. 가면 켜진 화소의 비율 %."""
    a = np.array(Image.open(path_emit).convert("RGBA"), dtype=np.float64) / 255.0
    hero = a[..., 3] > 0.5
    n = int(hero.sum())
    if n == 0:
        return {}
    lit = a[..., :3].max(-1) > EMIT_LUM_MIN
    return {"emit_pct": float((lit & hero).sum() / n * 100), "emit_hero_pixels": n}


def measure_hero(rgb, hero_mask, element, hues=None):
    """rgb: (h,w,3) 0..1, hero_mask: (h,w) bool. 지시서 2.5절의 잰 값."""
    hues = hues or ELEMENT_HUE
    n = int(hero_mask.sum())
    out = {"hero_pixels": n}
    if n == 0:
        return out
    y = luminance(rgb)
    h, s, _ = hsv(rgb)
    py = y[hero_mask]
    # 선명도 지표: 주인공 화소 안(가면에서 1화소 안쪽)의 라플라시안 분산 x 1e4. 같은 장면·같은 틱의 설정 비교에만 뜻이 있다(밝기에도 영향을 받는다).
    lap = -4 * y + np.roll(y, 1, 0) + np.roll(y, -1, 0) + np.roll(y, 1, 1) + np.roll(y, -1, 1)
    inner = hero_mask & ~dilate(~hero_mask, 1)
    out["sharp"] = float(lap[inner].var() * 1e4) if inner.any() else float("nan")
    out["white_pct"] = float((py > 0.85).mean() * 100)
    out["lum_mean"] = float(py.mean())
    out["lum_p90"] = float(np.percentile(py, 90))
    sat = s[hero_mask] >= 0.35
    for name, deg in hues.items():
        near = (hue_dist(h[hero_mask], deg) <= 25.0) & sat
        out["element_pct_" + name] = float(near.mean() * 100)
    out["element_pct"] = out.get("element_pct_" + element, float("nan"))
    out["other_element_pct_max"] = max([out["element_pct_" + k] for k in hues if k != element] or [0.0])
    band = dilate(hero_mask, HERO_BAND_PX) & ~hero_mask
    out["band_pixels"] = int(band.sum())
    if band.any():
        by = y[band]
        out["band_lum_mean"] = float(by.mean())
        eff = by > EFFECT_LUM_MIN
        out["band_effect_pixels"] = int(eff.sum())
        if eff.any():
            out["band_effect_lum_mean"] = float(by[eff].mean())
            out["ring_gap"] = float(by[eff].mean() - py.mean())  # 효과 화소 평균 - 주인공 평균. 기준: >= 0.20 (자기 효과 한가운데에서만 뜻이 있다)
    return out


def check_hero(m, element):
    """지시서 2.5절 기준에 대한 ok/FAIL. 값이 없으면 'n/a'. ring_gap은 자기 효과 한가운데 순간에서만 읽는다."""
    res = {}
    if "lum_mean" not in m:
        return res
    res["white_pct"] = "ok" if m["white_pct"] <= HERO_LIMITS["white_pct_max"] else "FAIL"
    lo, hi = HERO_LIMITS["lum_mean"]
    res["lum_mean"] = "ok" if lo <= m["lum_mean"] <= hi else "FAIL"
    lo, hi = HERO_LIMITS["element_pct"]
    # 지시서의 "색상 ±25°, 채도 ≥ 0.35" 화소 비율은 게임의 냉기색(채도 0.347)이 스스로 못 맞춘다. 발광만 그린 그림이 있으면
    # "가면 켜진 화소의 비율"(emit_pct)로 같은 범위(12~25%)를 판정하고, 색상 기준은 참고(element_pct)로만 남긴다.
    if "emit_pct" in m:
        res["emit_pct"] = "ok" if lo <= m["emit_pct"] <= hi else "FAIL"
    else:
        res["element_pct"] = "ok" if lo <= m["element_pct"] <= hi else "FAIL"
    res["other_element_pct_max"] = "ok" if m["other_element_pct_max"] <= HERO_LIMITS["other_element_pct_max"] else "FAIL"
    res["ring_gap"] = ("ok" if m["ring_gap"] >= HERO_LIMITS["ring_gap_min"] else "FAIL") if "ring_gap" in m else "n/a"
    return res


def hero_crops(folder):
    """폴더의 crop_tNNNN.png 가운데 가면이 있는 것: [(틱, 그림 경로, 가면 경로)] 틱 순."""
    out = []
    for n in sorted(os.listdir(folder)):
        if n.startswith("crop_t") and n.endswith(".png") and not n.endswith((".mask.png", ".emit.png")):
            tick = int(n[len("crop_t"):-len(".png")])
            mask = os.path.join(folder, n[:-4] + ".mask.png")
            out.append((tick, os.path.join(folder, n), mask if os.path.isfile(mask) else None))
    return out


def load_hero(path_img, path_mask):
    rgb = np.asarray(Image.open(path_img).convert("RGB"), dtype=np.float64) / 255.0
    mask = None
    if path_mask:
        mask = np.array(Image.open(path_mask).convert("RGBA"))[..., 3] > 127
    return rgb, mask


def hero_sheets(entries, out_dir, seed=7, cell=240):
    """entries: [(마녀 이름, 틱, 그림 경로)]. 3x3 판 셋: 이름 붙은 것, 판 A(이름 가림, 칸 섞음, 컬러), 판 B(같은 판 회색조). 열쇠는 json."""
    import random
    n = len(entries)
    cols = 3
    rows = (n + cols - 1) // cols

    def paste_all(order, labels, gray):
        sheet = Image.new("RGB", (cols * cell + (cols + 1) * 4, rows * cell + (rows + 1) * 4), (70, 70, 74))
        for k, idx in enumerate(order):
            im = Image.open(entries[idx][2]).convert("RGB")
            if im.size != (cell, cell):
                im = im.resize((cell, cell), Image.LANCZOS)
            if gray:
                im = ImageOps.grayscale(im).convert("RGB")
            if labels:
                _label(im, labels[k])
            sheet.paste(im, (4 + (k % cols) * (cell + 4), 4 + (k // cols) * (cell + 4)))
        return sheet

    natural = list(range(n))
    shuffled = natural[:]
    random.Random(seed).shuffle(shuffled)
    os.makedirs(out_dir, exist_ok=True)
    paste_all(natural, ["%s t%d" % (e[0], e[1]) for e in entries], False).save(os.path.join(out_dir, "hero-sheet-labeled.png"))
    paste_all(shuffled, [str(k + 1) for k in range(n)], False).save(os.path.join(out_dir, "hero-sheet-A.png"))
    paste_all(shuffled, [str(k + 1) for k in range(n)], True).save(os.path.join(out_dir, "hero-sheet-B-gray.png"))
    key = {str(k + 1): {"witch": entries[idx][0], "tick": entries[idx][1]} for k, idx in enumerate(shuffled)}
    with open(os.path.join(out_dir, "hero-sheet-key.json"), "w", encoding="utf-8") as f:
        json.dump(key, f, ensure_ascii=False, indent=1)
    return key


def run_hero(specs, out_dir, hues=None):
    """specs: [(마녀 이름, 폴더)]. 측정 json/md와 판 A·B를 out_dir에 쓴다."""
    result = {"hues": hues or ELEMENT_HUE, "limits": {k: list(v) if isinstance(v, tuple) else v for k, v in HERO_LIMITS.items()}, "rows": []}
    entries = []
    for name, folder in specs:
        for tick, pimg, pmask in hero_crops(folder):
            entries.append((name, tick, pimg))
            row = {"witch": name, "tick": tick, "image": pimg, "mask": pmask}
            if pmask is None:
                row["note"] = "가면 없음(--hero-mask 없이 찍은 폴더): 측정 안 함"
            else:
                rgb, mask = load_hero(pimg, pmask)
                row["measure"] = measure_hero(rgb, mask, name, hues)
                emit = pimg[:-4] + ".emit.png"
                if os.path.isfile(emit):
                    row["measure"].update(measure_emit(emit))
                row["check"] = check_hero(row["measure"], name)
            result["rows"].append(row)
    os.makedirs(out_dir, exist_ok=True)
    result["sheet_key"] = hero_sheets(entries, out_dir) if entries else {}
    with open(os.path.join(out_dir, "hero-measure.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    L = ["# 주인공 자르기 측정 (A7-0)", "", DISCLAIMER, "",
         "가면 알파 = 주인공 화소(가림 무시). 효과 화소는 고리띠에서 밝기 > %.2f인 것(근사). ring_gap은 자기 효과 한가운데 순간에서만 뜻이 있다." % EFFECT_LUM_MIN, "",
         "| 마녀 | 틱 | 주인공 화소 | 흰(>0.85) % | 평균 명도 | 원소색 % | 다른 원소색 최대 % | 고리 효과 평균 명도 | ring_gap | 판정 |", "|---|---|---|---|---|---|---|---|---|---|"]
    for r in result["rows"]:
        m = r.get("measure")
        if not m or "lum_mean" not in m:
            L.append("| %s | %d | - | - | - | - | - | - | - | %s |" % (r["witch"], r["tick"], r.get("note", "주인공 화소 0")))
            continue
        chk = " ".join("%s=%s" % (k, v) for k, v in r["check"].items())
        L.append("| %s | %d | %d | %.1f | %.3f | %s | %.1f | %s | %s | %s |" % (
            r["witch"], r["tick"], m["hero_pixels"], m["white_pct"], m["lum_mean"],
            ("%.1f (가면 %.1f)" % (m["element_pct"], m["emit_pct"])) if "emit_pct" in m else "%.1f" % m["element_pct"], m["other_element_pct_max"],
            "%.3f" % m["band_effect_lum_mean"] if "band_effect_lum_mean" in m else "-", "%.3f" % m["ring_gap"] if "ring_gap" in m else "-", chk))
    L.append("")
    with open(os.path.join(out_dir, "hero-measure.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description="캡처 전후 비교와 화면 측정. " + DISCLAIMER)
    ap.add_argument("folders", nargs="*", help="캡처 폴더 하나(측정만) 또는 둘(전, 후). --hero-sheet만 쓰면 생략")
    ap.add_argument("--hero-sheet", action="append", default=[], metavar="NAME=DIR",
                    help="주인공 자르기 폴더(rig_game_probe.gd --hero-mask --hero-crop-ticks). NAME은 ember|frost|arc. 여러 번. 측정 json/md와 판 A·B를 --out에 쓴다")
    ap.add_argument("--element-hue", action="append", default=[], metavar="NAME=DEG", help="원소색 색상(도)을 바꾼다(예: arc=248)")
    ap.add_argument("--out", required=True, help="출력 폴더(경로에 _local 필요)")
    ap.add_argument("--limits", default=None)
    ap.add_argument("--play", default=None)
    ap.add_argument("--exclude", default=None, help="a,b,c,d;e,f,g,h (빈 문자열이면 제외 없음)")
    ap.add_argument("--hero", default=None)
    ap.add_argument("--hero-crop", dest="hero_crop", default=None)
    ap.add_argument("--diff-thr", dest="diff_thr", type=int, default=None)
    ap.add_argument("--no-images", action="store_true")
    args = ap.parse_args(argv)
    if len(args.folders) > 2:
        ap.error("폴더는 하나 또는 둘")
    if not args.folders and not args.hero_sheet:
        ap.error("캡처 폴더 또는 --hero-sheet가 필요하다")
    for p in args.folders:
        if not os.path.isdir(p):
            ap.error("폴더가 없다: " + p)
    _check_out(args.out)
    if args.hero_sheet:
        specs = []
        for item in args.hero_sheet:
            name, _, folder = item.partition("=")
            if not folder or not os.path.isdir(folder):
                ap.error("--hero-sheet NAME=DIR: 폴더가 없다: " + item)
            specs.append((name, folder))
        hues = dict(ELEMENT_HUE)
        for item in args.element_hue:
            name, _, deg = item.partition("=")
            hues[name] = float(deg)
        res = run_hero(specs, args.out, hues)
        print("주인공 측정 %d칸 -> %s" % (len(res["rows"]), args.out))
        if not args.folders:
            return 0
    cfg = {k: (list(v) if isinstance(v, list) else v) for k, v in DEFAULTS.items()}
    if args.play:
        cfg["play"] = parse_box(args.play)
    if args.exclude is not None:
        cfg["exclude"] = [parse_box(s) for s in args.exclude.split(";") if s.strip()]
    if args.hero:
        cfg["hero"] = parse_box(args.hero)
    if args.hero_crop:
        cfg["hero_crop"] = parse_box(args.hero_crop)
    if args.diff_thr is not None:
        cfg["diff_thr"] = args.diff_thr
    limits = load_limits(args.limits) if args.limits else None
    after = args.folders[1] if len(args.folders) == 2 else None
    res = run(args.folders[0], after, args.out, cfg, limits, images=not args.no_images)
    print("그림 %d장 -> %s" % (len(res["images"]), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
