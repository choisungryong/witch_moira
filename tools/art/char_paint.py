#!/usr/bin/env python3
"""구운 텍스처(atlas) 위에 마녀별 원소 자리를 그리고, 같은 UV의 발광 가면 텍스처를 만든다(numpy + PIL만, Blender 없이 돈다).

설정(`paint`):
  {
    "detect": [ {"name": "ice", "parts": ["arm_l", "hand_l_*"], "hue": [175, 215], "sat_min": 0.18, "val_min": 0.55,
                 "mode": "texel", "gain": 1.3, "grow": 1}, ...],
        # 구운 색에서 색상·채도·밝기가 맞는 텍셀을 찾아 가면에 칠한다(얼음 팔, 보석, 용암). parts는 부위 이름 패턴(fnmatch).
    "bolts": [ {"name": "veins", "parts": ["arm_l", "arm_r"], "color": "#c9a8ff", "width_px": 16, "glow_px": 7,
                "paths": [[[s, v], ...], ...], "mirror_parts": ["arm_r"], "paint_albedo": true, "albedo_mix": 0.85}],
        # 부위 사각형 안에 (s, v) 0..1 좌표의 꺾인 선을 굵게 직접 그린다. s는 둘레 방향(0..1, 1 넘으면 한 바퀴 돌아옴), v는 길이 방향.
        # mirror_parts에 든 부위는 s를 1.5 - s로 뒤집어(정면 축 대칭) 그린다.
    "fill": [ {"name": "arm_glow", "parts": ["arm_*", "hand_*"], "color": "#8f6bff", "weight": 0.16, "val_min": 0.55} ],
        # 부위 전체에 옅은 원소 색 발광(밝은 텍셀만)
    "tips": {"parts": ["hair_lock_*"], "from_v": 0.45, "color": "#a173ff", "mix": 0.75, "glow": 0.6}
        # 머리 끝 물들이기: v가 from_v 넘는 텍셀을 색으로 섞고, 발광은 glow 세기
  }
가면(RGB uint8)은 원소 자리만 색이고 나머지는 검정이다. 모든 값은 모델의 계산이며 사람이 본 판정이 아니다.
"""
from __future__ import annotations

import fnmatch
import math

import numpy as np


def hex_rgb(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def part_rects(parts, place):
    """부위 이름 -> (x0, y0, w, h, S) 정수 사각형(텍셀)."""
    out = {}
    for i, p in enumerate(parts):
        x0, y0, w, h = place[i]
        out[p["name"]] = (int(math.floor(x0)), int(math.floor(y0)), int(math.ceil(w)), int(math.ceil(h)), int(p["S"]))
    return out


def select_mask(shape, rects, patterns):
    m = np.zeros(shape, bool)
    for name, (x0, y0, w, h, _) in rects.items():
        if any(fnmatch.fnmatch(name, pat) for pat in patterns):
            m[y0:y0 + h, x0:x0 + w] = True
    return m


def rgb_to_hsv(a):
    """a: (...,3) float 0..1 -> h(도 0..360), s, v."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rc = nz & (mx == r)
    gc = nz & (mx == g) & ~rc
    bc = nz & ~rc & ~gc
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h * 60.0, s, mx


def ramp(x, lo, hi):
    return np.clip((x - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def hue_weight(atlas, hue, sat_min, val_min, soft=0.12):
    """색상 범위(도, h0>h1이면 0도를 넘는 범위)·채도·밝기가 맞는 정도 0..1. 색상 경계는 10도쯤 부드럽게."""
    h, s, v = rgb_to_hsv(atlas)
    h0, h1 = hue
    length = (h1 - h0) % 360.0
    d = (h - h0) % 360.0
    inside = np.clip(np.minimum(d, length - d) / 10.0 + 0.5, 0.0, 1.0)
    return inside * ramp(s, sat_min, sat_min + soft + 0.1) * ramp(v, val_min, val_min + soft)


def blur(a, n):
    """상자 흐림(분리형) n회 반경 1."""
    out = a.astype(np.float32)
    for _ in range(max(0, int(n))):
        p = np.pad(out, ((1, 1), (1, 1)) + ((0, 0),) * (out.ndim - 2), mode="edge")
        out = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:] + p[1:-1, 1:-1]) / 5.0
    return out


def grow(w, n):
    out = w
    for _ in range(max(0, int(n))):
        p = np.pad(out, 1, mode="edge")
        out = np.maximum.reduce([p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:], p[1:-1, 1:-1]])
    return out


def draw_paths(shape, rect, paths, width, mirror=False):
    """부위 사각형에 꺾인 선을 굵게 그린 0..1 지도(둘레 방향은 한 바퀴 이어짐)."""
    from PIL import Image, ImageDraw
    x0, y0, w, h, S = rect
    img = Image.new("L", (w * 3, h), 0)          # 좌우 한 칸씩 더 둬서 이음매를 넘는 선도 그린 뒤 가운데 칸만 쓴다
    dr = ImageDraw.Draw(img)
    r = width / 2.0
    for path in paths:
        pts = [(((1.5 - s) if mirror else s) + 1.0) * w for s, v in path]
        ys = [v * h for s, v in path]
        for off in (-1.0, 0.0, 1.0):
            q = [(x + off * w, y) for x, y in zip(pts, ys)]
            dr.line(q, fill=255, width=int(width))
            for x, y in q:
                dr.ellipse((x - r, y - r, x + r, y + r), fill=255)
    arr = np.asarray(img, np.float32)[:, w:2 * w] / 255.0
    out = np.zeros(shape, np.float32)
    hh = min(h, shape[0] - y0)
    ww = min(w, shape[1] - x0)
    out[y0:y0 + hh, x0:x0 + ww] = arr[:hh, :ww]
    return out


def apply(atlas, parts, place, paint, log=print):
    """atlas: float (TS,TS,3) 0..1. 돌려주는 것: (새 atlas, 가면 uint8 (TS,TS,3), 통계 dict). 부위 밖 텍셀은 건드리지 않는다."""
    TS = atlas.shape[0]
    rects = part_rects(parts, place)
    atlas = atlas.copy()
    mask = np.zeros_like(atlas)
    stats = {}
    for rule in paint.get("detect", []):
        sel = select_mask(atlas.shape[:2], rects, rule["parts"])
        w = hue_weight(atlas, rule["hue"], rule.get("sat_min", 0.2), rule.get("val_min", 0.5)) * sel
        w = np.clip(grow(w, rule.get("grow", 0)), 0, 1)
        w = np.clip(blur(w, rule.get("blur", 1)), 0, 1) * sel
        if rule.get("mode", "texel") == "fixed":
            col = hex_rgb(rule["color"])[None, None, :] * np.ones_like(atlas)
        else:
            col = np.clip(atlas * rule.get("gain", 1.3), 0, 1)
        mask = np.maximum(mask, col * w[..., None])
        if rule.get("boost_albedo"):
            atlas = atlas * (1 - w[..., None] * rule["boost_albedo"]) + col * w[..., None] * rule["boost_albedo"]
        stats[rule["name"]] = float((w > 0.2).sum())
    for rule in paint.get("bolts", []):
        col = hex_rgb(rule["color"])
        pat = rule["parts"]
        mirrors = set(rule.get("mirror_parts", []))
        for name, rect in rects.items():
            if not any(fnmatch.fnmatch(name, p) for p in pat):
                continue
            core = draw_paths(atlas.shape[:2], rect, rule["paths"], rule.get("width_px", 12), mirror=name in mirrors)
            glow = blur(grow(core, rule.get("glow_px", 6)), 2)
            core = np.clip(blur(core, 1), 0, 1)
            sel = select_mask(atlas.shape[:2], {name: rect}, [name])
            gl = np.clip(glow, 0, 1) * sel
            core = core * sel
            mask = np.maximum(mask, col[None, None, :] * np.maximum(core, gl * 0.45)[..., None])
            if rule.get("paint_albedo", True):
                k = np.clip(core * rule.get("albedo_mix", 0.85) + gl * 0.2, 0, 1)[..., None]
                atlas = atlas * (1 - k) + col[None, None, :] * k
            stats["%s:%s" % (rule["name"], name)] = float((core > 0.3).sum())
    for rule in paint.get("fill", []):   # 부위 전체에 옅게 원소 색을 깐다(팔 전체의 은은한 발광). val_min 이상 밝은 텍셀만(살갗만, 어두운 방어구는 제외)
        sel = select_mask(atlas.shape[:2], rects, rule["parts"])
        gate = ramp(atlas.max(-1), rule.get("val_min", 0.0), rule.get("val_min", 0.0) + 0.1) if rule.get("val_min") else 1.0
        w = sel * gate * rule.get("weight", 0.2)
        mask = np.maximum(mask, hex_rgb(rule["color"])[None, None, :] * w[..., None])
        stats["fill:" + rule["name"]] = float((w > 0.02).sum())
    tips = paint.get("tips")
    if tips:
        col = hex_rgb(tips["color"])
        for name, (x0, y0, w, h, S) in rects.items():
            if not any(fnmatch.fnmatch(name, p) for p in tips["parts"]):
                continue
            v = (np.arange(h, dtype=np.float32) + 0.5) / h
            t = np.clip((v - tips.get("from_v", 0.45)) / max(1.0 - tips.get("from_v", 0.45), 1e-6), 0, 1) ** 0.8
            t = np.repeat(t[:, None], w, axis=1)[..., None]
            reg = atlas[y0:y0 + h, x0:x0 + w]
            reg[:] = reg * (1 - t * tips.get("mix", 0.75)) + col[None, None, :] * (t * tips.get("mix", 0.75))
            mask[y0:y0 + h, x0:x0 + w] = np.maximum(mask[y0:y0 + h, x0:x0 + w], col[None, None, :] * t * tips.get("glow", 0.6))
            stats["tips:" + name] = float((t > 0.3).sum())
    return atlas, (np.clip(mask, 0, 1) * 255 + 0.5).astype(np.uint8), stats


def mask_stats(mask, rects=None):
    """가면 통계: 켜진 텍셀 수(밝기 > 0.08)와 부위별 비율."""
    lum = mask.max(-1) / 255.0
    on = lum > 0.08
    out = dict(on_texels=int(on.sum()))
    if rects:
        per = {}
        for name, (x0, y0, w, h, _) in rects.items():
            n = int(on[y0:y0 + h, x0:x0 + w].sum())
            if n:
                per[name] = n
        out["per_part"] = per
    return out
