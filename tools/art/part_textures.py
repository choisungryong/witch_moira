#!/usr/bin/env python3
"""rig_parts 부품용 작은 무늬 텍스처(numpy만, Blender 없이 검사된다). 부품이 색 한 덩어리로 보이지 않게 결·주름·금속 면을 넣는다.

모두 (S, S, 3) float 0..1 이고 첫 행이 uv의 v=0(부품 위쪽 또는 꼭대기)이다. 부품 spec의 "texture": {"kind": ..., ...}.
  fur   : 털의 결 - 세로 가닥마다 밝기가 다르고 끝(v 큰 쪽)이 밝다. base(중간), dark, light 색
  cloth : 천 - 세로 주름 음영(folds개), 아래로 갈수록 어둡게, 맨 아래 밝은 테(rim, rim_frac)
  gold  : 금속 판 - 골(ribs개)마다 밝은 면·어두운 면, 가장자리(v 큰 쪽)에 어두운 테와 가는 밝은 선, 그 위로 붉은 빛(glow 색, glow_start부터)
"""
from __future__ import annotations

import numpy as np


def hexc(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def _grid(size):
    v, u = np.mgrid[0:size, 0:size].astype(np.float32)
    return (u + 0.5) / size, (v + 0.5) / size


def _lerp(a, b, k):
    return a[None, None, :] * (1 - k[..., None]) + b[None, None, :] * k[..., None]


def fur(size=64, base="#a9b8c8", dark="#7a8ea3", light="#eef3f8", seed=3):
    u, v = _grid(size)
    rng = np.random.RandomState(seed)
    strand = rng.rand(size)[None, :].repeat(size, 0)                       # 열마다 한 값(세로 가닥)
    strand = 0.6 * strand + 0.4 * np.roll(strand, 1, axis=1)
    noise = rng.rand(size, size) * 0.25
    k = np.clip(strand * 0.75 + v * 0.35 + noise - 0.25, 0, 1)             # 0 = 어두운 가닥, 1 = 밝은 끝
    lo = _lerp(hexc(dark), hexc(base), np.clip(k * 2, 0, 1))
    return np.clip(lo * (1 - np.clip(k * 2 - 1, 0, 1))[..., None] + hexc(light)[None, None, :] * np.clip(k * 2 - 1, 0, 1)[..., None], 0, 1)


def cloth(size=64, base="#5c3f9e", rim="#b79bff", folds=5, rim_frac=0.07, fade=0.3):
    u, v = _grid(size)
    b = 0.72 + 0.28 * np.cos(2 * np.pi * folds * u)                         # 세로 주름 음영
    b = b * (1.0 - fade * v)                                               # 아래로 갈수록 어둡게
    col = hexc(base)[None, None, :] * b[..., None]
    k = np.clip((v - (1 - rim_frac)) / max(rim_frac * 0.4, 1e-6), 0, 1)     # 맨 아래 밝은 테
    return np.clip(col * (1 - k[..., None]) + hexc(rim)[None, None, :] * k[..., None], 0, 1)


def gold(size=64, base="#b8892e", dark="#5a3d12", light="#f0cd6a", glow="#d8451c", ribs=6, glow_start=0.62, glow_amount=0.55):
    u, v = _grid(size)
    face = 0.5 + 0.5 * np.cos(2 * np.pi * ribs * u)                         # 골: 밝은 면(1)과 어두운 면(0)
    k = np.clip(face * 0.8 + (1 - v) * 0.35 - 0.1, 0, 1)                   # 꼭대기가 더 밝음
    col = _lerp(hexc(dark), hexc(base), np.clip(k * 1.6, 0, 1))
    col = col * (1 - np.clip(k * 1.6 - 1, 0, 1))[..., None] + hexc(light)[None, None, :] * np.clip(k * 1.6 - 1, 0, 1)[..., None]
    edge = np.clip((v - 0.86) / 0.06, 0, 1)                                 # 가장자리: 어두운 띠
    col = col * (1 - 0.55 * edge[..., None])
    line = np.clip(1 - np.abs(v - 0.84) / 0.02, 0, 1)                       # 그 안쪽의 가는 밝은 선
    col = col * (1 - line[..., None]) + hexc(light)[None, None, :] * line[..., None]
    g = np.clip((v - glow_start) / (1 - glow_start), 0, 1) * glow_amount    # 용암 팔 쪽으로 붉은 빛
    return np.clip(_lerp(np.zeros(3, np.float32), hexc(glow), g) + col * (1 - g[..., None]), 0, 1)


KINDS = {"fur": fur, "cloth": cloth, "gold": gold}


def make(spec, size=64):
    kw = {k: v for k, v in spec.items() if k != "kind"}
    if spec["kind"] not in KINDS:
        raise KeyError("모르는 부품 텍스처: %s (있는 것: %s)" % (spec["kind"], ", ".join(KINDS)))
    return KINDS[spec["kind"]](size=size, **kw)
