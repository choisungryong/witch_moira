#!/usr/bin/env python3
"""구운 몸 그림(albedo)의 팔 구간에 원통 음영을 넣는다. numpy만 쓴다(Blender 없음). base_build.py가 부른다.

까닭: 게임 조명이 약해서, 얼음 소매처럼 한 색으로 구운 팔은 납작한 띠로 읽힌다. 음영을 그림에 넣는다.
방법: 팔 정점마다 팔 축에 수직인 바깥 방향 n을 구해 L(위·앞쪽 빛)과의 내적으로 밝기 배율을 정하고, 팔꿈치·손목의 마디 띠(어둡게)와 서리 결(옅은 세로 줄무늬)을 얹는다.
이 배율을 uv 삼각형 안에서 보간해(무게중심 좌표) 배율 그림 한 장을 만들고 그림 픽셀에 곱한다. 배율은 쉬는 자세(T자) 기준이라 팔이 돌면 밝은 면이 같이 돈다(그림에 구워진 음영).
"""
from __future__ import annotations

import numpy as np

LIGHT = np.array([0.0, -0.45, 0.9])


def vertex_factor(pos, segs, strength=1.0, streaks=0.07, ring=0.22, ring_w=0.025):
    """pos (N,3) 쉬는 자세 정점. segs: [(head, tail, 정점 마스크(N,bool), 마디 이름)] 마디별 축. 반환 (N,) 배율(마스크 밖은 1)."""
    L = LIGHT / np.linalg.norm(LIGHT)
    f = np.ones(len(pos))
    for head, tail, mask, kind in segs:
        ax = tail - head
        ln = float(np.linalg.norm(ax))
        ax = ax / ln
        p = pos[mask] - head
        t = p @ ax / ln
        r = p - np.outer(p @ ax, ax)
        rn = np.linalg.norm(r, axis=1, keepdims=True)
        n = r / np.maximum(rn, 1e-9)
        lit = np.clip(n @ L * 0.5 + 0.5, 0, 1)
        fac = (0.60 + 0.46 * lit)
        fac = 1.0 + (fac - 1.0) * strength
        # 마디 띠: 마디 양 끝(t=0, t=1) 근처를 어둡게(팔꿈치·손목)
        d = np.minimum(np.abs(t), np.abs(t - 1.0)) * ln
        fac = fac * (1.0 - ring * np.exp(-(d / ring_w) ** 2))
        if streaks:
            ref = np.array([0, 1.0, 0]) if abs(ax[1]) < 0.9 else np.array([1.0, 0, 0])
            u = np.cross(ax, ref)
            u /= np.linalg.norm(u)
            v = np.cross(ax, u)
            ang = np.arctan2(n @ v, n @ u)
            fac = fac * (1.0 + streaks * np.sin(ang * 9.0 + t * 14.0))
        f[mask] = fac
    return f


def apply(img, tris_uv, tris_f, feather=2):
    """img (H,W,3 float 0..1, 위가 y=0)를 제자리에서 곱한다. tris_uv (n,3,2) uv(v 위가 1), tris_f (n,3) 정점 배율. 삼각형 가장자리는 feather 픽셀 넓혀 이음새 틈을 막는다."""
    H, W = img.shape[:2]
    fimg = np.ones((H, W))
    for uv, fv in zip(tris_uv, tris_f):
        px = uv[:, 0] * (W - 1)
        py = (1.0 - uv[:, 1]) * (H - 1)
        x0, x1 = int(np.floor(px.min())) - feather, int(np.ceil(px.max())) + feather
        y0, y1 = int(np.floor(py.min())) - feather, int(np.ceil(py.max())) + feather
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, W - 1), min(y1, H - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(d) < 1e-9:
            continue
        a = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
        b = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
        c = 1.0 - a - b
        e = -feather * 0.5 / max(np.hypot(*(px.max() - px.min(), py.max() - py.min())), 1.0)
        m = (a >= e) & (b >= e) & (c >= e)
        if not m.any():
            continue
        val = np.clip(a, 0, 1) * fv[0] + np.clip(b, 0, 1) * fv[1] + np.clip(c, 0, 1) * fv[2]
        sub = fimg[y0:y1 + 1, x0:x1 + 1]
        sub[m] = val[m]                 # 곱이 아니라 덮어쓴다(이웃 삼각형 겹침에서 두 번 곱해지지 않게)
    img *= fimg[:, :, None]
    return img


def raster_mask(shape, tris_uv, feather=1):
    """삼각형 uv 목록이 덮는 픽셀 마스크(H,W bool). 섬 하나만 고칠 때 쓴다."""
    H, W = shape
    m = np.zeros((H, W), bool)
    one = np.ones(3)
    f = np.zeros((H, W))
    for uv in tris_uv:
        px = uv[:, 0] * (W - 1)
        py = (1.0 - uv[:, 1]) * (H - 1)
        x0, x1 = max(int(np.floor(px.min())) - feather, 0), min(int(np.ceil(px.max())) + feather, W - 1)
        y0, y1 = max(int(np.floor(py.min())) - feather, 0), min(int(np.ceil(py.max())) + feather, H - 1)
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(d) < 1e-9:
            continue
        a = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
        b = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
        c = 1.0 - a - b
        e = -0.02
        m[y0:y1 + 1, x0:x1 + 1] |= (a >= e) & (b >= e) & (c >= e)
    return m
