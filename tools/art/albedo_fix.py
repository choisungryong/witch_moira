#!/usr/bin/env python3
"""구운 몸 그림(albedo)의 상자 구간 안을 피부색으로 매끈하게 메운다. numpy만 쓴다. base_build.py가 부른다.

까닭: 앞에서 투영해 구운 그림이 몸 옆면(넓적다리 바깥 등)에는 앞모습 다리 그림 조각과 가장자리 늘어진 줄무늬로 남아 얼룩처럼 보인다.
방법: 상자 안에서 피부색인 픽셀만 모아 정규화 흐림(흐림(피부색 x 마스크) / 흐림(마스크))으로 매끈한 피부 바탕을 만들고, 상자 안의 배경이 아닌 픽셀을 그것으로 바꾼다(replace="all") 또는 피부 아닌 것만 바꾼다("nonskin").
"""
from __future__ import annotations

import numpy as np


def _box(a, r, axis):
    """축 방향 이동 평균(반지름 r), 가장자리는 잘라 정규화."""
    n = a.shape[axis]
    c = np.cumsum(np.concatenate([np.zeros_like(np.take(a, [0], axis=axis)), a], axis=axis), axis=axis)
    idx = np.arange(n)
    lo = np.clip(idx - r, 0, n)
    hi = np.clip(idx + r + 1, 0, n)
    out = np.take(c, hi, axis=axis) - np.take(c, lo, axis=axis)
    cnt = (hi - lo).astype(float)
    shape = [1] * a.ndim
    shape[axis] = n
    return out / cnt.reshape(shape)


def blur(a, sigma):
    r = max(1, int(round(sigma * 0.8)))
    for _ in range(3):
        a = _box(_box(a, r, 0), r, 1)
    return a


def skin_mask(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = (r + g + b) / 3
    return ((r > g) & (g > b * 0.85) & (r - b > 0.06) & (lum > 0.32) & (lum < 0.9)).astype(float)


def fix(rgb, box, sigma=30.0, mode="all", mask=None):
    """rgb (H,W,3 0..1, 위가 y=0) 제자리 수정. box = (x0,y0,x1,y1) 픽셀. mask(H,W bool)가 있으면 그 안의 픽셀만 다룬다(섬 하나만). mode: all / nonskin / skin(피부색 픽셀만 매끈하게). 반환 바뀐 픽셀 수."""
    x0, y0, x1, y1 = box
    sub = rgb[y0:y1, x0:x1].copy()
    bg = sub.max(axis=2) < 0.02
    if mask is not None:
        bg = bg | ~mask[y0:y1, x0:x1]
    m = skin_mask(sub) * (~bg)
    if m.sum() < 50:
        return 0
    num = blur(sub * m[..., None], sigma)
    den = blur(m, sigma)[..., None]
    fill = num / np.maximum(den, 1e-4)
    # 피부가 너무 멀어 den이 작은 곳은 전체 평균으로
    mean = (sub * m[..., None]).sum((0, 1)) / m.sum()
    fill = np.where(den > 0.02, fill, mean)
    rep = ~bg if mode == "all" else (((m < 0.5) & ~bg) if mode == "nonskin" else ((m >= 0.5) & ~bg))
    sub[rep] = fill[rep]
    rgb[y0:y1, x0:x1] = sub
    return int(rep.sum())
