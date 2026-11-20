#!/usr/bin/env python3
"""그림 면별 시트(정면·측면·후면 + 3/4 + 머리 클로즈업) -> 게임용 리깅된 주인공 glb. Blender와 numpy/scipy/PIL만 쓴다(내려받기·외부 호출 0).

  python tools/art/char_from_sheets.py --config tools/art/char_configs/frost.json --work D:/Project/witch-moira-work/char3d-blender-only/v2/frost
         [--stage all|geom|bake|glb|rig|check] [--out _local/char3d-blender-only/v2/frost]

걸음
  geom  그림에서 마스크를 따고(배경 단색 가정) 행 구간표를 뽑아 부위별 메시(char_geom.py)를 만든다. 3/4 그림의 카메라는 윤곽 겹침으로 맞춘다.
  bake  네 시점(+머리 클로즈업)에서 텍스처 한 장(2048^2)을 굽는다. 가려진 쪽은 모델의 깊이로 거르고(팔과 몸통을 서로 안 물들게),
        그림 속 조명은 색 덩어리별 밝기 평탄화로 덜어 낸다.
  glb   Blender로 메시 한 덩어리 glb를 내보낸다(char_blender.py).
  rig   tools/art의 rig_build -> rig_clips(동작 6개, 회피 포함)를 부른다. 뼈대·가중치·동작은 이 도구가 짜지 않는다.
  check rig_check로 계약을 검사한다.
캐릭터마다 달라지는 것은 모두 설정 JSON(그림 경로, 부위 행 구간표, 손으로 정한 몸통 폭 같은 예외)에 있다.
새 그림이 오면: 설정에서 views의 image와 행 구간표를 맞추고 위 명령을 다시 돌린다(docs/ART-3D-PIPELINE.ko.md 2절).
이 도구는 라이선스를 판단하지 않는다(입력 그림의 것을 따른다).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
MAIN_REPO = Path(os.environ.get("WITCH_MAIN_REPO", "C:/Project/witch-moira"))
sys.path.insert(0, str(HERE))
import char_geom as G  # noqa: E402

PY = sys.executable


# ------------------------------------------------------------------ 설정과 그림

def _merge(base, over):
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config(path):
    """설정 JSON. `extends`(같은 폴더의 다른 설정 파일 이름)가 있으면 그것을 바탕으로 깊게 덮는다(변형 판: 번개 머리 끝 보라 등)."""
    p = Path(path)
    cfg = json.loads(p.read_text(encoding="utf-8"))
    if "extends" in cfg:
        base = load_config(p.parent / cfg["extends"])
        over = {k: v for k, v in cfg.items() if k != "extends"}
        cfg = _merge(base, over)
    return cfg


def resolve_art(cfg, name):
    """그림 경로: 절대 경로 그대로, 아니면 art_root 아래. 작업 트리에 없으면 본 저장소(_local은 git 밖)에서 찾는다."""
    p = Path(name)
    if not p.is_absolute():
        p = Path(cfg.get("art_root", "")) / name
    if p.is_absolute() and p.is_file():
        return p
    for base in (REPO, MAIN_REPO):
        q = base / p
        if q.is_file():
            return q
    raise FileNotFoundError(str(p))


def load_rgb(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert("RGB"))


def figure_mask(im, thresh=22, trim=0, window=None):
    """단색 회색 배경에서 사람 윤곽: 바탕 행별 중앙값과의 색 거리, 열림·닫힘·구멍 메움, 가장 큰 덩어리."""
    from scipy import ndimage as ndi
    f = im.astype(float)
    edge = np.concatenate([f[:, trim:trim + 12], f[:, f.shape[1] - trim - 12:f.shape[1] - trim]], axis=1)   # trim: 시트 가장자리의 칸막이 선을 바탕 추정과 윤곽에서 뺀다
    bg = np.median(edge, axis=1)[:, None, :]
    d = np.sqrt(((f - bg) ** 2).sum(2))
    m = d > thresh
    if trim:
        m[:, :trim] = False
        m[:, f.shape[1] - trim:] = False
    if window:   # [x0, x1]: 이 열 구간 밖은 지운다(시트 가장자리에 이웃 그림의 손이 걸쳐 있을 때)
        m[:, :window[0]] = False
        m[:, window[1]:] = False
    m = ndi.binary_opening(m, iterations=1)
    m = ndi.binary_closing(m, iterations=3)
    m = ndi.binary_fill_holes(m)
    lab, n = ndi.label(m)
    if n == 0:
        return m
    sizes = ndi.sum(m, lab, range(1, n + 1))
    return lab == 1 + int(np.argmax(sizes))


def fill_background(im, mask, erode=3):
    """배경 픽셀을 가장 가까운 몸 색으로 채운다(투영이 윤곽을 넘어도 회색이 안 묻게)."""
    from scipy import ndimage as ndi
    m = ndi.binary_erosion(mask, iterations=erode)
    idx = ndi.distance_transform_edt(~m, return_distances=False, return_indices=True)
    return im[idx[0], idx[1]]


def sole_profile(path, box, bins=12, thresh=22):
    """장화 클로즈업의 밑창 그림(box = x0,y0,x1,y1)에서 발 폭을 길이 방향으로 잰다. 가운데로 갈수록 0..1로 정규화한 폭 12개(발끝 -> 뒤꿈치).
    그림 속 두 밑창 가운데 왼쪽 것. 좁은 쪽 끝을 발끝으로 본다. 모델의 계산이다."""
    from scipy import ndimage as ndi
    im = load_rgb(path)
    x0, y0, x1, y1 = box
    sub = im[y0:y1, x0:x1]
    m = figure_mask(sub, thresh)
    lab, n = ndi.label(m)
    if n == 0:
        return None
    sizes = ndi.sum(m, lab, range(1, n + 1))
    order = np.argsort(-sizes)[:2]
    comps = [lab == (i + 1) for i in order]
    comps.sort(key=lambda c: np.where(c)[1].mean())
    c = comps[0]
    ys, xs = np.where(c)
    pts = np.stack([xs, ys], 1).astype(float)
    pts -= pts.mean(0)
    w, v = np.linalg.eigh(np.cov(pts.T))
    ax = v[:, 1]                       # 가장 긴 축
    along = pts @ ax
    perp = pts @ v[:, 0]
    edges = np.linspace(along.min(), along.max(), bins + 1)
    widths = []
    for i in range(bins):
        sel = (along >= edges[i]) & (along < edges[i + 1] + 1e-9)
        widths.append(float(perp[sel].max() - perp[sel].min()) if sel.any() else 0.0)
    widths = np.array(widths)
    if widths[:3].mean() > widths[-3:].mean():
        widths = widths[::-1]
    return (widths / widths.max()).tolist(), float((along.max() - along.min()) / max(widths.max(), 1))


def detect_eyes(im, ymax_frac=0.4, rule=None):
    """밝은 하늘색 홍채 덩어리 두 개(좌우, 높이 비슷)를 찾아 [(x,y),(x,y)]를 돌려준다. 가장 위쪽의 쌍을 고른다(귀걸이·머리핀 보석은 눈보다 아래나 한쪽).
    눈 색이 하늘색인 캐릭터용. 못 찾으면 None."""
    from scipy import ndimage as ndi
    f = im.astype(int)
    H, W, _ = f.shape
    if rule:   # 눈 색 규칙: {"hue":[lo,hi](도), "sat_min", "val_min"} - 보라·주황 눈 등
        import char_paint as _P
        h, sat, val = _P.rgb_to_hsv(im.astype(np.float32) / 255.0)
        lo, hi = rule["hue"]
        d = (h - lo) % 360.0
        m = (d <= (hi - lo) % 360.0) & (sat >= rule.get("sat_min", 0.4)) & (val >= rule.get("val_min", 0.5))
    else:
        m = ((f[..., 2] - f[..., 0]) > 40) & (f[..., 2] > 120)
    m[int(H * ymax_frac):] = False
    if not rule or rule.get("open", True):
        m = ndi.binary_opening(m, iterations=1)
    lab, n = ndi.label(m)
    blobs = []
    min_px = (rule or {}).get("min_px", 8)
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if min_px <= len(xs) <= 6000:
            blobs.append((len(xs), float(xs.mean()), float(ys.mean())))
    best = None
    for i in range(len(blobs)):
        for j in range(i + 1, len(blobs)):
            a1, x1, y1 = blobs[i]; a2, x2, y2 = blobs[j]
            dx, dy = abs(x1 - x2), abs(y1 - y2)
            if dx < W * 0.03 or dy > dx * (rule or {}).get("dy_ratio", 0.08):
                continue
            y = (y1 + y2) / 2
            if best is None or y < best[0]:
                best = (y, sorted([(x1, y1), (x2, y2)]))
    return best[1] if best else None


def row_table(mask):
    return {int(y): G.intervals(mask[y]) for y in range(mask.shape[0])}


def flatten_lighting(im, mask, strength=0.5, clusters=10, clamp=(0.72, 1.45), seed=1):
    """그림에 박힌 조명(한쪽이 밝고 반대쪽이 어두운 것)을 덜어 낸다.
    색 덩어리(밝기+색 k-평균)마다 '넓게 부드럽게 한 밝기'를 그 덩어리의 중앙값으로 나눈 비율을 되돌린다. 무늬·장신구(작은 것)는 그대로 둔다.
    strength 0이면 아무것도 안 한다. 결과는 같은 크기의 uint8."""
    if strength <= 0:
        return im
    from scipy import ndimage as ndi
    from scipy.cluster.vq import kmeans2
    f = im.astype(np.float32)
    lum = f @ np.array([0.299, 0.587, 0.114], np.float32)
    mf = mask.astype(np.float32)
    sig = max(6.0, im.shape[0] / 90.0)
    num = ndi.gaussian_filter(lum * mf, sig)
    den = ndi.gaussian_filter(mf, sig) + 1e-4
    low = num / den                                   # 몸 안에서만 번진 부드러운 밝기
    small = ndi.zoom(f, (0.25, 0.25, 1), order=1)
    small_lum = ndi.zoom(low, 0.25, order=1)
    feat = np.concatenate([small_lum[..., None] / 255.0 * 1.2, small / 255.0 * 0.0 + (small - small_lum[..., None]) / 255.0], axis=2)
    ys, xs = np.where(ndi.zoom(mf, 0.25, order=0) > 0.5)
    X = feat[ys, xs]
    rng = np.random.RandomState(seed)
    k = min(clusters, max(2, len(X) // 50))
    cent, lab_small = kmeans2(X, k, minit="++", seed=rng)
    lab_img = np.full(small_lum.shape, -1, np.int32)
    lab_img[ys, xs] = lab_small
    # 덩어리별 기준 밝기 = 중앙값
    ref = np.zeros(k, np.float32)
    for c in range(k):
        v = small_lum[lab_img == c]
        ref[c] = np.median(v) if len(v) else 1.0
    ref_small = np.where(lab_img >= 0, ref[np.clip(lab_img, 0, k - 1)], small_lum)
    ratio_small = ref_small / np.maximum(small_lum, 8.0)
    ratio = ndi.zoom(ratio_small, (im.shape[0] / ratio_small.shape[0], im.shape[1] / ratio_small.shape[1]), order=1)
    ratio = ratio[:im.shape[0], :im.shape[1]]
    ratio = np.clip(ratio, clamp[0], clamp[1])
    gain = ratio ** strength
    out = np.clip(f * gain[..., None], 0, 255)
    return out.astype(np.uint8)


# ------------------------------------------------------------------ 카메라(정사영)

class Cam:
    """az(도): 0 정면(카메라가 -Y), 90 캐릭터 왼쪽(+X), 180 후면, -35 정면에서 캐릭터 오른쪽(-X)으로 35도.
    s 픽셀/m, (cx, cy) 는 월드 원점(발 아래 중심)이 그림에서 놓이는 곳."""

    def __init__(self, az, s, cx, cy, size):
        self.az, self.s, self.cx, self.cy, self.size = float(az), float(s), float(cx), float(cy), size  # size = (W, H)

    @property
    def d(self):
        a = math.radians(self.az)
        return np.array([math.sin(a), -math.cos(a), 0.0])

    @property
    def r(self):
        a = math.radians(self.az)
        return np.array([math.cos(a), math.sin(a), 0.0])

    def project(self, P):
        px = self.cx + self.s * (P @ self.r)
        py = self.cy - self.s * P[:, 2]
        return px, py, P @ self.d

    def as_dict(self):
        return dict(az=self.az, s=self.s, cx=self.cx, cy=self.cy)


def dense_points(parts, up_r=4, up_s=3):
    """부위의 고리 점을 보간해 표면 점구름(윤곽 겹침 계산용)을 만든다."""
    pts = []
    for p in parts:
        rp = p["ring_pts"]
        R, S, _ = rp.shape
        rr = np.linspace(0, R - 1, (R - 1) * up_r + 1)
        r0 = np.clip(np.floor(rr).astype(int), 0, R - 2); fr = (rr - r0)[:, None, None]
        a = rp[r0] * (1 - fr) + rp[r0 + 1] * fr
        ss = np.linspace(0, S, S * up_s, endpoint=False)
        s0 = np.floor(ss).astype(int) % S; s1 = (s0 + 1) % S; fs = (ss - np.floor(ss))[None, :, None]
        b = a[:, s0] * (1 - fs) + a[:, s1] * fs
        pts.append(b.reshape(-1, 3))
    return np.concatenate(pts)


def silhouette_iou(cam, pts, mask_small, f):
    from scipy import ndimage as ndi
    px, py, _ = cam.project(pts)
    H, W = mask_small.shape
    ix = np.round(px / f).astype(int); iy = np.round(py / f).astype(int)
    ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
    sil = np.zeros((H, W), bool)
    sil[iy[ok], ix[ok]] = True
    sil = ndi.binary_closing(sil, iterations=2)
    sil = ndi.binary_fill_holes(sil)
    inter = (sil & mask_small).sum(); uni = (sil | mask_small).sum()
    return inter / max(uni, 1)


def fit_cam(pts, mask, init: Cam, free=("az", "s", "cx", "cy"), f=4, steps=None):
    """정사영 카메라를 윤곽 겹침(IoU)이 최대가 되게 맞춘다(Nelder-Mead). 모델 계산이며 사람이 본 일치가 아니다."""
    from scipy.optimize import minimize
    from scipy import ndimage as ndi
    small = mask[::f, ::f]
    names = [n for n in ("az", "s", "cx", "cy") if n in free]
    x0 = np.array([getattr(init, n) for n in names], float)
    sc = {"az": 4.0, "s": 25.0, "cx": 12.0, "cy": 12.0}
    step = np.array([sc[n] for n in names])

    def make(x):
        d = init.as_dict(); d.update(dict(zip(names, x)))
        return Cam(d["az"], d["s"], d["cx"], d["cy"], init.size)

    def loss(x):
        return -silhouette_iou(make(x), pts, small, f)

    sim = np.vstack([x0] + [x0 + np.eye(len(x0))[i] * step[i] for i in range(len(x0))])
    res = minimize(loss, x0, method="Nelder-Mead", options=dict(initial_simplex=sim, xatol=0.05, fatol=1e-4, maxiter=400))
    cam = make(res.x)
    return cam, -float(res.fun)


# ------------------------------------------------------------------ UV 배치와 굽기

def pack_uv(parts, size=2048, gut=6):
    """선반 방식으로 직사각형 배치. 부위마다 dens 배율. 가장 큰 밀도(px/m)를 이분 탐색."""
    lo, hi = 100.0, 3000.0
    best = None
    order = sorted(range(len(parts)), key=lambda i: -parts[i]["h"] * parts[i]["dens"])
    for _ in range(20):
        k = (lo + hi) / 2
        x = y = rowh = 0.0
        place = {}
        ok = True
        for i in order:
            w = parts[i]["w"] * k * parts[i]["dens"] + gut
            h = parts[i]["h"] * k * parts[i]["dens"] + gut
            if w > size:
                ok = False; break
            if x + w > size:
                x = 0.0; y += rowh; rowh = 0.0
            place[i] = (x + gut / 2, y + gut / 2, w - gut, h - gut)
            x += w; rowh = max(rowh, h)
        if ok and y + rowh <= size:
            best = (k, place); lo = k
        else:
            hi = k
    return best


def texel_maps(parts, place):
    """텍셀마다 표면 위치 P와 법선 N. 고리 격자 위 쌍선형 보간(벡터화)."""
    out = []
    for i, p in enumerate(parts):
        x0, y0, w, h = place[i]
        S, R, cum = p["S"], p["R"], p["cum"]
        ix = np.arange(int(np.ceil(x0 - 0.5)), int(np.floor(x0 + w - 0.5)) + 1)
        iy = np.arange(int(np.ceil(y0 - 0.5)), int(np.floor(y0 + h - 0.5)) + 1)
        gx, gy = np.meshgrid(ix, iy)
        gx = gx.reshape(-1); gy = gy.reshape(-1)
        sv = np.clip((gx + 0.5 - x0) / w * S, 0, S - 1e-6)
        yv = np.clip((gy + 0.5 - y0) / h * cum[-1], 0, cum[-1])
        r = np.interp(yv, cum, np.arange(R))
        s0 = np.floor(sv).astype(int); fs = (sv - s0)[:, None]; s1 = (s0 + 1) % S
        r0 = np.clip(np.floor(r).astype(int), 0, R - 2); fr = (r - r0)[:, None]
        ring = p["ring_pts"]
        nr = p["normals"][:R * S].reshape(R, S, 3)

        def bil(a):
            return (a[r0, s0] * (1 - fs) * (1 - fr) + a[r0, s1] * fs * (1 - fr) + a[r0 + 1, s0] * (1 - fs) * fr + a[r0 + 1, s1] * fs * fr)

        P = bil(ring); N = bil(nr)
        N = N / (np.linalg.norm(N, axis=1, keepdims=True) + 1e-9)
        out.append(dict(ix=gx, iy=gy, P=P, N=N, part=np.full(len(gx), i, np.int32)))
    cat = {k: np.concatenate([o[k] for o in out]) for k in out[0]}
    return cat


def bilinear(im, px, py):
    h, w, _ = im.shape
    px = np.clip(px, 0, w - 1.001); py = np.clip(py, 0, h - 1.001)
    x0 = px.astype(int); y0 = py.astype(int)
    fx = (px - x0)[:, None]; fy = (py - y0)[:, None]
    return (im[y0, x0] * (1 - fx) * (1 - fy) + im[y0, x0 + 1] * fx * (1 - fy) + im[y0 + 1, x0] * (1 - fx) * fy + im[y0 + 1, x0 + 1] * fx * fy)


def bicubic(im, px, py):
    """3차 스플라인 표본(scipy). 그림을 키워 구울 때 쌍선형보다 번짐이 적다."""
    from scipy import ndimage as ndi
    h, w, _ = im.shape
    c = np.stack([py, px])
    return np.stack([ndi.map_coordinates(im[..., k], c, order=3, mode="nearest") for k in range(3)], axis=1)


def bake_texture(parts, tex, views, TS, power=4.0, arm_px=9, tol=0.012, log=print, clamp_z=None, margin=0.12, resample="bilinear", tol_head=None):
    """views: [{name, cam, img(float 0..1, 배경을 채운 그림), mask, groups(None 또는 허용 부위군), qual}].
    깊이로 가려짐 판정: 텍셀 점들을 그 시점에 찍어 가장 가까운 깊이 지도를 만들고(3x3 키움), 팔 점은 따로(arm_px 키움) 지도를 만들어
    팔이 가리는 몸통 텍셀은 그 시점 색을 안 쓴다. 가중 = (법선·카메라)^power x 보임 x 마스크 안."""
    from scipy import ndimage as ndi
    P, N = tex["P"], tex["N"]
    part_idx = tex["part"]
    groups = np.array([parts[i]["group"] for i in range(len(parts))])
    tg = groups[part_idx]
    is_arm = np.isin(tg, ("arm", "hand"))
    n = len(P)
    stats = {}
    cs, cols = [], []
    for v in views:
        cam = v["cam"]; img = v["img"]; mk = v["mask"]
        Hh, Ww = img.shape[:2]
        px, py, D = cam.project(P)
        ix = np.clip(np.round(px).astype(int), 0, Ww - 1); iy = np.clip(np.round(py).astype(int), 0, Hh - 1)
        flat = iy * Ww + ix
        zmax = np.full(Hh * Ww, -1e9, np.float32)
        np.maximum.at(zmax, flat, D.astype(np.float32))
        zmax = ndi.maximum_filter(zmax.reshape(Hh, Ww), size=3)
        zarm = np.full(Hh * Ww, -1e9, np.float32)
        if is_arm.any():
            np.maximum.at(zarm, flat[is_arm], D[is_arm].astype(np.float32))
        zarm = ndi.maximum_filter(zarm.reshape(Hh, Ww), size=int(arm_px))
        tol_v = np.where(tg == "head", tol_head, tol) if tol_head else tol   # 머리는 행마다 앞뒤가 들쭉날쭉해 더 너그럽게
        vis = D >= zmax[iy, ix] - tol_v
        occ_arm = (~is_arm) & (zarm[iy, ix] > D + tol)
        vis &= ~occ_arm
        cosv = np.clip(N @ cam.d, 0, 1)
        inm = mk[iy, ix]
        c = cosv * vis * np.where(inm, 1.0, 0.15) * v.get("qual", 1.0)
        if v.get("groups"):
            c = c * np.isin(tg, v["groups"])
        if clamp_z:   # 치마 밑단 그림자가 허벅지 위쪽에 묻지 않게: 이 높이 위의 텍셀은 그 높이의 색을 쓴다
            Pc = P.copy()
            for g_name, zc in clamp_z.items():
                m = (tg == g_name) & (Pc[:, 2] > zc)
                Pc[m, 2] = zc
            pxc, pyc, _ = cam.project(Pc)
            col = (bicubic if resample == "bicubic" else bilinear)(img, pxc, pyc)
        else:
            col = (bicubic if resample == "bicubic" else bilinear)(img, px, py)
        cs.append(c.astype(np.float32)); cols.append(col.astype(np.float32))
    # 시점 섞기: 가장 정면에 가까운 시점이 이긴다. 그보다 margin 이내로 모자란 시점만 섞는다(생성 그림끼리 기하가 어긋나 얼굴이 겹쳐 보이는 것을 막는다)
    cmax = np.max(cs, axis=0)
    acc = np.zeros((n, 3), np.float32)
    wsum = np.zeros(n, np.float32)
    for v, c, col in zip(views, cs, cols):
        feather = np.clip((c - (cmax - margin)) / max(margin, 1e-6), 0, 1)
        w = (np.clip(c, 0, 1) ** power) * feather
        acc += col * w[:, None]
        wsum += w
        stats[v["name"]] = float((w > 0.05).mean())
        log("bake view %-8s texels used %.1f%%" % (v["name"], 100 * stats[v["name"]]))
    ok = wsum > 1e-3
    dbg = np.zeros((TS, TS, 3), np.uint8)
    dbg[tex["iy"], tex["ix"]] = np.where(ok[:, None], np.clip(wsum[:, None] * 40, 0, 255), 0).astype(np.uint8) * np.array([1, 1, 1], np.uint8)
    dbg[tex["iy"][~ok], tex["ix"][~ok]] = (255, 0, 0)
    tex["_dbg"] = dbg
    color = np.zeros((n, 3), np.float32)
    color[ok] = acc[ok] / wsum[ok, None]
    # 조명 박힘 지표: 같은 몸 부위에서 +X 쪽을 보는 텍셀과 -X 쪽을 보는 텍셀의 평균 밝기 차(상대). 그림 속 조명이 한쪽으로 박혀 있으면 크다. 모델의 계산.
    lum = color @ np.array([0.299, 0.587, 0.114], np.float32)
    selb = (wsum > 0.3) & ~is_arm & np.isin(tg, ("body", "leg", "boot", "skirt"))
    la, lb = lum[selb & (N[:, 0] > 0.6)], lum[selb & (N[:, 0] < -0.6)]
    asym = float(abs(la.mean() - lb.mean()) / max((la.mean() + lb.mean()) / 2, 1e-6)) if len(la) > 100 and len(lb) > 100 else None
    stats["lit_asymmetry"] = asym
    # 못 본 텍셀(머리 꼭대기·턱 밑·치마 속·장화 밑창): 같은 부위에서 가장 가까운 본 텍셀의 색을 이어 쓴다(부위 평균색보다 무늬가 이어진다).
    from scipy import ndimage as ndi2
    sure = wsum > 0.01
    for i in range(len(parts)):
        sel = np.where(part_idx == i)[0]
        if len(sel) == 0:
            continue
        x0, y0 = tex["ix"][sel].min(), tex["iy"][sel].min()
        lx, ly = tex["ix"][sel] - x0, tex["iy"][sel] - y0
        valid = np.zeros((ly.max() + 1, lx.max() + 1), bool)
        col = np.zeros(valid.shape + (3,), np.float32)
        good = sure[sel]
        valid[ly[good], lx[good]] = True
        col[ly[good], lx[good]] = color[sel][good]
        if not valid.any():
            color[sel] = 0.25
            continue
        if (~good).any():
            idx = ndi2.distance_transform_edt(~valid, return_distances=False, return_indices=True)
            filled_col = col[idx[0], idx[1]]
            miss = ~good
            fc = filled_col[ly[miss], lx[miss]]
            color[sel[miss]] = fc * 0.92
    atlas = np.zeros((TS, TS, 3), np.float32)
    filled = np.zeros((TS, TS), bool)
    atlas[tex["iy"], tex["ix"]] = color
    filled[tex["iy"], tex["ix"]] = True
    for _ in range(4):
        nf = filled.copy(); na = atlas.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            sa = np.roll(np.roll(atlas, dy, 0), dx, 1)
            m = (~nf) & sh
            na[m] = sa[m]; nf |= sh
        atlas, filled = na, nf
    return atlas, dict(filled_fraction=float(filled.mean()), view_use={k: v for k, v in stats.items() if k != "lit_asymmetry"}, lit_asymmetry=stats["lit_asymmetry"], unseen_fraction=float((~ok).mean()))


# ------------------------------------------------------------------ 입출력

def save_mesh(parts, place, TS, path):
    """부위를 한 메시로 합쳐 npz로 저장(Blender 쪽이 읽는다). UV는 삼각형 모서리마다."""
    verts, tris, uvs, names, ranges = [], [], [], [], []
    base = 0
    for i, p in enumerate(parts):
        x0, y0, w, h = place[i]
        S, R, cum = p["S"], p["R"], p["cum"]
        g = p["uvg"]
        uv = np.zeros_like(g)
        uv[..., 0] = x0 + g[..., 0] / S * w
        rr = np.clip(g[..., 1], 0, R - 1)
        uv[..., 1] = y0 + np.interp(rr, np.arange(R), cum) / max(cum[-1], 1e-9) * h
        uv[..., 0] /= TS
        uv[..., 1] = 1 - uv[..., 1] / TS
        verts.append(p["verts"]); tris.append(p["tris"] + base); uvs.append(uv)
        names.append(p["name"]); ranges.append((base, base + len(p["verts"])))
        base += len(p["verts"])
    np.savez_compressed(path, verts=np.concatenate(verts), tris=np.concatenate(tris), uv=np.concatenate(uvs),
                        names=np.array(names), ranges=np.array(ranges), part_tris=np.array([len(p["tris"]) for p in parts]))


def run(cmd, timeout=900, label=""):
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
    sec = time.time() - t0
    if r.returncode != 0:
        print(r.stdout[-2000:]); print(r.stderr[-2000:], file=sys.stderr)
        raise SystemExit("실패(%s): %s" % (label, " ".join(map(str, cmd[:4]))))
    return r.stdout, sec


# ------------------------------------------------------------------ 한 걸음씩

def stage_geom(cfg, work, log=print):
    from PIL import Image
    work.mkdir(parents=True, exist_ok=True)
    mdir = work / "masks"; mdir.mkdir(exist_ok=True)
    thresh = cfg.get("mask", {}).get("threshold", 22)
    imgs, masks, fills, rows = {}, {}, {}, {}
    for v, vc in cfg["views"].items():
        if "image" not in vc:
            continue
        p = resolve_art(cfg, vc["image"])
        im = load_rgb(p)
        m = figure_mask(im, thresh, vc.get("trim", 0), vc.get("window"))
        imgs[v], masks[v] = im, m
        Image.fromarray((m * 255).astype(np.uint8)).save(mdir / ("mask_%s.png" % v))
        if v in ("front", "side", "back"):
            rows[v] = row_table(m)
    R = G.Rows(cfg, rows)
    extra = {}
    fc = cfg.get("foot") or {}
    if fc.get("sole_image"):
        sp = sole_profile(resolve_art(cfg, fc["sole_image"]), fc["sole_box"])
        if sp:
            extra["sole"] = sp[0]
            log("sole profile (toe->heel) %s aspect %.2f" % ([round(v, 2) for v in sp[0]], sp[1]))
    parts, info = G.build_all(R, cfg, side_mask=masks["side"], extra=extra)
    return dict(R=R, imgs=imgs, masks=masks, parts=parts, info=info)


def build_views(cfg, g, flat_cfg, log=print):
    """네 시점 + (있으면) 머리 클로즈업의 카메라와 그림을 만든다."""
    R = g["R"]
    views = []
    for name, az, scale, cx, cy in (("front", 0, 1 / R.sf, R.xc, R.feet["front"]),
                                    ("side", R.side_az, 1 / R.ss, R.zc, R.feet["side"]),
                                    ("back", 180, 1 / R.sb, float(cfg["views"]["back"].get("cx", R.xc)), R.feet["back"])):
        h, w = g["imgs"][name].shape[:2]
        views.append(dict(name=name, cam=Cam(az, scale, cx, cy, (w, h)), kind="body"))
    meta = {}
    if "3q" in g["imgs"]:
        vc = cfg["views"]["3q"]
        h, w = g["imgs"]["3q"].shape[:2]
        pts = dense_points(g["parts"])
        best = None
        for az0 in vc.get("fit_starts", [vc.get("az", -35)]):
            init = Cam(az0, 1 / R.sf, R.xc, R.feet["front"] + 10, (w, h))
            cam, iou = fit_cam(pts, g["masks"]["3q"], init, f=4)
            cam, iou = fit_cam(pts, g["masks"]["3q"], cam, f=2)
            log("3q fit start az=%g -> az=%.1f s=%.0f cx=%.0f cy=%.0f IoU=%.3f" % (az0, cam.az, cam.s, cam.cx, cam.cy, iou))
            if best is None or iou > best[1]:
                best = (cam, iou)
        views.append(dict(name="3q", cam=best[0], kind="body"))
        meta["3q_fit"] = dict(best[0].as_dict(), iou=best[1])
    # 머리 클로즈업: 눈 두 점의 간격으로 크기를, 눈 가운데로 위치를 맞춘다(정면 눈이 정면 전신 그림의 눈과 같은 자리·같은 간격이 되도록)
    for hv in cfg.get("head_views", []):
        im = load_rgb(resolve_art(cfg, hv["image"]))
        e_img = detect_eyes(im, hv.get("img_ymax", 0.6), hv.get("eye_rule"))
        ref = next(v for v in views if v["name"] == hv.get("ref", "front"))
        e_ref = detect_eyes(g["imgs"][ref["name"]], hv.get("ref_ymax", 0.14), hv.get("ref_eye_rule", hv.get("eye_rule")))
        if not e_img or not e_ref:
            log("head view %s: eyes not found (%s / %s) -> skipped" % (hv["name"], bool(e_img), bool(e_ref)))
            continue
        d_img = e_img[1][0] - e_img[0][0]; d_ref = e_ref[1][0] - e_ref[0][0]
        sc_h = ref["cam"].s * d_img / d_ref
        mid_ref = ((e_ref[0][0] + e_ref[1][0]) / 2, (e_ref[0][1] + e_ref[1][1]) / 2)
        mid_img = ((e_img[0][0] + e_img[1][0]) / 2, (e_img[0][1] + e_img[1][1]) / 2)
        # 기준 시점에서 눈 가운데의 세계 좌표(x, z). 정면 정사영: px = cx + s*x, py = cy - s*z
        cr = ref["cam"]
        wx = (mid_ref[0] - cr.cx) / cr.s; wz = (cr.cy - mid_ref[1]) / cr.s
        h, w = im.shape[:2]
        cam = Cam(ref["cam"].az, sc_h, mid_img[0] - sc_h * wx, mid_img[1] + sc_h * wz, (w, h))
        g["imgs"][hv["name"]] = im
        g["masks"][hv["name"]] = figure_mask(im, cfg.get("mask", {}).get("threshold", 22))
        views.append(dict(name=hv["name"], cam=cam, kind="head", groups=hv.get("groups", ["head"]), qual=hv.get("qual", 1.5)))
        meta[hv["name"] + "_cam"] = dict(cam.as_dict(), eye_dist_ratio=d_img / d_ref)
        log("head view %s: eyes %s -> s=%.0f px/m" % (hv["name"], [(round(a), round(b)) for a, b in e_img], sc_h))
    for v in views:
        im = g["imgs"][v["name"]]
        m = g["masks"][v["name"]]
        fim = fill_background(im, m)
        fim = flatten_lighting(fim, m, **flat_cfg) if flat_cfg else fim
        v["img"] = fim.astype(np.float32) / 255.0
        v["mask"] = m
    return views, meta


def stage_bake(cfg, g, work, log=print):
    from PIL import Image
    b = cfg.get("bake", {})
    TS = b.get("texture", 2048)
    parts = g["parts"]
    k, place = pack_uv(parts, TS)
    log("texel density %.0f px/m, parts %d, triangles %d" % (k, len(parts), sum(len(p["tris"]) for p in parts)))
    tex = texel_maps(parts, place)
    views, meta = build_views(cfg, g, cfg.get("flatten"), log)
    atlas, st = bake_texture(parts, tex, views, TS, b.get("power", 4.0), b.get("arm_occlusion_px", 9), b.get("depth_tol", 0.012), log,
                             clamp_z=b.get("clamp_z"), margin=b.get("margin", 0.12), resample=b.get("resample", "bilinear"), tol_head=b.get("depth_tol_head"))
    import char_paint as P
    if b.get("sharpen", 0) > 0:   # 언샤프: 큰 번짐(굽기 섞임)에서 온 흐림을 덜어 낸다. 부위 사각형 안에서만(섬 사이 빈 곳은 건드리지 않음)
        from scipy import ndimage as ndi
        sig = float(b.get("sharpen_sigma", 1.2)) * TS / 2048.0
        blurred = np.stack([ndi.gaussian_filter(atlas[..., k], sig) for k in range(3)], axis=2)
        atlas = np.clip(atlas + float(b["sharpen"]) * (atlas - blurred), 0, 1)
    rects = P.part_rects(parts, place)
    (work / "parts_uv.json").write_text(json.dumps({k: list(v) for k, v in rects.items()}, indent=1), encoding="utf-8")
    if cfg.get("paint"):
        atlas, emis, pst = P.apply(atlas, parts, place, cfg["paint"], log)
        Image.fromarray(emis).save(work / "emission.png")
        meta["paint"] = dict(pst, **{"mask": P.mask_stats(emis, rects)})
        log("paint: mask texels on %d" % meta["paint"]["mask"]["on_texels"])
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8)).save(work / "albedo.png")
    Image.fromarray(tex["_dbg"]).save(work / "weights_debug.png")
    save_mesh(parts, place, TS, work / "mesh.npz")
    meta.update(st)
    (work / "views.json").write_text(json.dumps(
        [dict(name=v["name"], w=int(v["cam"].size[0]), h=int(v["cam"].size[1]), **v["cam"].as_dict()) for v in views], indent=1), encoding="utf-8")
    meta.update(density_px_per_m=k, triangles=int(sum(len(p["tris"]) for p in parts)),
                part_triangles={p["name"]: int(len(p["tris"])) for p in parts})
    (work / "bake.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False), encoding="utf-8")
    return meta


def unique_texture_name(cfg):
    """glb 안 이미지 이름. Godot는 <glb 이름>_<이미지 이름>.png로 풀고 이미 있으면 그 파일을 쓴다(docs/ART-3D-PIPELINE.ko.md 게임에 끼울 때 1항) ->
    `color` 같은 흔한 이름을 피하고 마녀·판 이름을 넣는다."""
    return "%s_%s_albedo" % (cfg["name"], cfg.get("texture_tag", "a7"))


def stage_glb(cfg, work):
    import shutil
    tex_name = unique_texture_name(cfg)
    shutil.copyfile(work / "albedo.png", work / (tex_name + ".png"))
    out, sec = run([PY, str(HERE / "char_blender.py"), "--npz", str(work / "mesh.npz"), "--albedo", str(work / (tex_name + ".png")),
                    "--out-glb", str(work / "mesh.glb"), "--name", cfg["name"]], 300, "glb")
    return sec


def stage_views(cfg, work, model=None, tag=""):
    """원본 그림과 같은 틀로 정면·3/4·측면·후면을 렌더하고 나란히 붙인다(compare.png, compare_head.png)."""
    import char_montage
    model = model or (work / "mesh.glb")
    out, sec = run([PY, str(HERE / "char_render.py"), "views", "--model", str(model), "--views", str(work / "views.json"),
                    "--out", str(work / ("r" + tag))], 300, "views")
    srcs = {v: str(resolve_art(cfg, vc["image"])) for v, vc in cfg["views"].items() if "image" in vc}
    rd = work / ("r" + tag)
    q = "3q" in srcs
    rows = [[srcs["front"], str(rd / "front.png")] + ([srcs["3q"], str(rd / "3q.png")] if q else []),
            [srcs["side"], str(rd / "side.png"), srcs["back"], str(rd / "back.png")]]
    char_montage.montage(rows, 700, work / ("compare%s.png" % tag))
    char_montage.montage([[srcs["front"], str(rd / "front.png")] + ([srcs["3q"], str(rd / "3q.png")] if q else []) + [srcs["side"], str(rd / "side.png")]],
                         620, work / ("compare_head%s.png" % tag), crop=cfg.get("head_crop", (0.30, 0.0, 0.75, 0.27)))
    return sec


POSE_SHEET = [("idle", "0,30,60"), ("run", "0,9,18,27"), ("cast", "0,14,24"), ("hit", "0,6,12"), ("death", "0,20,40,54"), ("dodge", "0,8,16,24")]


def stage_poses(cfg, work):
    """동작 6개 시트(3/4 카메라, 동작마다 몇 컷). 모델은 rig_clips가 남긴 clips.blend. 자세 확인용이며 손맛 평가가 아니다."""
    import char_montage
    rows = []
    total = 0.0
    for clip, frames in POSE_SHEET:
        _, sec = run([PY, str(HERE / "char_render.py"), "poses", "--model", str(work / "final.glb"), "--out", str(work / "poses"),
                      "--clip", clip, "--frames", frames], 300, "poses")
        total += sec
        rows.append([str(work / "poses" / ("pose_%s_%s.png" % (clip, f))) for f in frames.split(",")])
    char_montage.montage(rows, 360, work / "poses_sheet.png")
    return total


def stage_rig(cfg, work, out_dir, preview=True):
    rig_cfg = json.loads(json.dumps(cfg.get("rig", {})))
    if cfg.get("mocap"):   # 사람 동작 옮기기 설정(클립 목록): rig_configs/mocap_clips*.json
        mj = Path(cfg["mocap"])
        if not mj.is_absolute():
            mj = REPO / mj
        rig_cfg.setdefault("clips", {})["mocap"] = json.loads(mj.read_text(encoding="utf-8"))
    (work / "rig_config.json").write_text(json.dumps(rig_cfg, indent=1), encoding="utf-8")
    secs = {}
    _, secs["rig_build"] = run([PY, str(HERE / "rig_build.py"), "--in", str(work / "mesh.glb"), "--out-blend", str(work / "rigged.blend"),
                               "--config", str(work / "rig_config.json"), "--report", str(work / "build.json")], 600, "rig_build")
    has_parts = bool(cfg.get("parts"))
    cmd = [PY, str(HERE / "rig_clips.py"), "--blend", str(work / "rigged.blend"), "--out-glb", str(work / ("body.glb" if has_parts else "final.glb")),
           "--out-blend", str(work / "clips.blend"), "--config", str(work / "rig_config.json"), "--report", str(work / "clips.json")]
    if preview:
        cmd += ["--preview", str(work / "prev")]
    _, secs["rig_clips"] = run(cmd, 900, "rig_clips")
    if has_parts:   # 뼈에 묶는 부품(털 목도리·어깨 갑옷·허리 자락)을 얹어 final.glb로. 동작은 그대로 같이 나간다
        pj = Path(cfg["parts"])
        if not pj.is_absolute():
            pj = REPO / pj
        _, secs["rig_parts"] = run([PY, str(HERE / "rig_parts.py"), "--blend", str(work / "clips.blend"), "--parts", str(pj),
                                    "--out-glb", str(work / "final.glb"), "--out-blend", str(work / "parts.blend"), "--report", str(work / "parts.json"),
                                    "--check-clips", cfg.get("parts_check_clips", "run,idle,cast,dodge")], 1800, "rig_parts")
    return secs


def stage_check(cfg, work):
    r = subprocess.run([PY, str(HERE / "rig_check.py"), str(work / "final.glb"), "--slot", "actor.hero.model"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout


LOOK_KEYS = ("albedo_mul", "element_lean", "emission_mode", "emission_energy", "rim", "rim_tint", "rim_color", "light_key", "light_fill")


def stage_look(cfg, work, out_dir):
    """마녀별 겉모습 값(look.json, 지시서 A7 2.3 칸)과 발광 가면을 out_dir에 낸다. 값은 설정의 `look`에서 온다(첫 값, 캡처를 보고 고친다)."""
    import shutil
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    look = dict(cfg.get("look", {}))
    unknown = sorted(set(look) - set(LOOK_KEYS))
    if unknown:
        raise SystemExit("look에 모르는 칸: %s (허용: %s)" % (unknown, ", ".join(LOOK_KEYS)))
    doc = {"_about": "A7 2.3 겉모습 값. 발광 가면은 몸 텍스처(albedo)와 같은 UV다. 부품(목도리·어깨 갑옷·자락) 재질에는 가면이 없다.",
           "model": cfg["name"]}
    doc.update(look)
    em = work / "emission.png"
    if em.is_file() and look.get("emission_mode") == "mask":
        name = "%s_%s_emission.png" % (cfg["name"], cfg.get("texture_tag", "a7"))
        shutil.copyfile(em, out_dir / name)
        doc["emission_texture"] = (out_dir / name).resolve().as_posix()
    (out_dir / "look.json").write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")
    return doc


def stage_measure(cfg, step=20, log=print):
    """새 그림 설정용 측정표: 면별 마스크의 키(top/feet), 머리 가운데 열, 행별 가운데 구간 반폭(정면·후면)과 앞뒤 끝(측면).
    설정의 views 숫자와 torso 키 표를 손으로 정할 때 근거로 쓴다(모델의 계산, 맞춤은 렌더를 보고 한다)."""
    out = {}
    for v, vc in cfg["views"].items():
        if "image" not in vc:
            continue
        im = load_rgb(resolve_art(cfg, vc["image"]))
        m = figure_mask(im, cfg.get("mask", {}).get("threshold", 22), vc.get("trim", 0), vc.get("window"))
        ys = np.where(m.any(1))[0]
        head = m[ys[0] + 10:ys[0] + 60]
        hc = [(np.where(r)[0].min() + np.where(r)[0].max()) / 2 for r in head if r.any()]
        rows = {}
        for y in range(int(ys[0]), int(ys[-1]) + 1, step):
            iv = G.intervals(m[y])
            c = min(iv, key=lambda i: abs((i[0] + i[1]) / 2 - float(np.median(hc)))) if iv else None
            rows[y] = dict(n=len(iv), central=c, all=iv)
        out[v] = dict(top=int(ys[0]), feet=int(ys[-1]), head_cx=float(np.median(hc)), rows=rows)
        log("%-6s top %d feet %d head_cx %.1f" % (v, ys[0], ys[-1], np.median(hc)))
        for y, r in rows.items():
            c = r["central"]
            if c:
                log("   y=%4d n=%d central %4d..%4d (c %.0f hw %.0f)" % (y, r["n"], c[0], c[1], (c[0] + c[1]) / 2, (c[1] - c[0]) / 2))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="그림 시트 -> 리깅된 주인공 glb")
    ap.add_argument("--config", required=True)
    ap.add_argument("--work", required=True, help="큰 중간 파일 폴더(D 드라이브)")
    ap.add_argument("--stage", default="all", choices=["all", "measure", "geom", "bake", "glb", "views", "rig", "poses", "check", "look"])
    ap.add_argument("--look-out", help="stage look(와 all)에서 look.json·발광 가면을 낼 폴더")
    ap.add_argument("--tag", default="", help="views 결과 폴더·파일 이름 꼬리표")
    ap.add_argument("--no-preview", action="store_true")
    a = ap.parse_args(argv)
    cfg = load_config(a.config)
    work = Path(a.work)
    work.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    times = {}
    if a.stage == "measure":
        res = stage_measure(cfg)
        (work / "measure.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
        return 0
    if a.stage in ("all", "geom", "bake"):
        t = time.time(); g = stage_geom(cfg, work); times["geom"] = time.time() - t
        print("geom: parts %d triangles %d" % (len(g["parts"]), sum(len(p["tris"]) for p in g["parts"])))
        if a.stage in ("all", "bake"):
            t = time.time(); meta = stage_bake(cfg, g, work); times["bake"] = time.time() - t
            print("bake:", json.dumps({k: v for k, v in meta.items() if k != "part_triangles"}, ensure_ascii=False))
    if a.stage in ("all", "glb"):
        times["glb"] = stage_glb(cfg, work)
    if a.stage in ("all", "views"):
        times["views"] = stage_views(cfg, work, tag=a.tag)
    if a.stage in ("all", "rig"):
        times.update(stage_rig(cfg, work, work, not a.no_preview))
    if a.stage in ("all", "poses"):
        times["poses"] = stage_poses(cfg, work)
    code = 0
    if a.look_out and a.stage in ("all", "look", "bake"):
        stage_look(cfg, work, a.look_out)
    if a.stage in ("all", "check"):
        code, text = stage_check(cfg, work)
        print(text)
    times["total"] = time.time() - t0
    (work / "times.json").write_text(json.dumps({k: round(v, 1) for k, v in times.items()}, indent=1), encoding="utf-8")
    print("times(s):", {k: round(v, 1) for k, v in times.items()})
    return code


if __name__ == "__main__":
    sys.exit(main())
