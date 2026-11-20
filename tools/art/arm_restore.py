#!/usr/bin/env python3
"""맞춤(fit)이 납작하게 누른 팔 단면을 원본 기본 몸의 굵기로 되돌린다. numpy만 쓴다(Blender 없음). base_build.py가 부른다.

까닭: 맞춤 결과 몸(rest_fit)은 원본과 정점 수가 같은데 위팔·아래팔·손의 짧은 폭(앞뒤)이 원본의 약 60%로 눌려 있다(arm_section.py로 잰 값).
하는 일: 마디(위팔·아래팔·손)마다 중간 구간(뼈 축 위 30~70%) 단면의 짧은 폭을 원본과 맞춘 배율 k를 구하고(상한 cap), 그 마디의 단면 짧은 방향 성분만 k배로 늘린다.
  정점은 마디 가중치로 섞어(어깨·팔꿈치 이음에서 끊기지 않게) 변위를 더한다. 긴 폭과 길이는 맞춤 그대로 둔다.
"""
from __future__ import annotations

import numpy as np


def _frame(ax):
    ax = ax / np.linalg.norm(ax)
    ref = np.array([0, 1.0, 0]) if abs(ax[1]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(ax, ref)
    u /= np.linalg.norm(u)
    return ax, u, np.cross(ax, u)


def mid_section(P, head, tail, lo=0.3, hi=0.7):
    """뼈 축에 수직인 평면 단면: (긴 폭, 짧은 폭, 짧은 방향 3차원 단위벡터, 중심 3차원). 정점이 모자라면 None."""
    ax, u, v = _frame(tail - head)
    L = float(np.linalg.norm(tail - head))
    t = (P - head) @ ax / L
    sel = P[(t >= lo) & (t <= hi)]
    if len(sel) < 6:
        return None
    c = sel.mean(0)
    q = np.stack([(sel - c) @ u, (sel - c) @ v], 1)
    w, vec = np.linalg.eigh(np.cov(q.T))
    pr = q @ vec
    ext = pr.max(0) - pr.min(0)
    minor_dir = vec[0, 0] * u + vec[1, 0] * v
    return float(ext[1]), float(ext[0]), minor_dir / np.linalg.norm(minor_dir), c


def restore(orig, fit, weights, bones_orig, bones_fit, segs, cap=1.9, floor=1.0):
    """orig, fit (N,3). weights: {마디: (N,) 가중치}. bones_*: {마디: (head, tail)}. segs: 마디 이름 목록.
    반환: (새 정점 (N,3), 보고 {마디: {k, 원본 짧은 폭, 맞춤 짧은 폭}})."""
    new = fit.copy()
    rep = {}
    for s in segs:
        w = weights[s]
        sel_o = orig[w > 0.5]
        sel_f = fit[w > 0.5]
        mo = mid_section(sel_o, *bones_orig[s])
        mf = mid_section(sel_f, *bones_fit[s])
        if mo is None or mf is None:
            continue
        # 짧은 폭 비. 긴 폭이 맞춤에서 달라졌으면(옷·실루엣 맞춤) 그 비율도 감안해 둘레 비율을 유지한다
        k = float(np.clip(mo[1] / max(mf[1], 1e-6) * 1.0, floor, cap))
        u = mf[2]
        c = mf[3]
        rep[s] = {"k": k, "minor_orig": mo[1], "minor_fit": mf[1], "major_orig": mo[0], "major_fit": mf[0]}
        d = ((fit - c) @ u)[:, None] * u[None, :]
        new += (w * (k - 1.0))[:, None] * d
    return new, rep


def _smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def elbow_blend(pos, W, up, fo, elbow, axis, band):
    """팔꿈치 둘레 가중치를 매끈한 이음으로 다시 깐다. W[g] (N,) 가중치 배열 사전. 위팔·아래팔 합이 0.9 이상이고 팔꿈치에서 축 방향 거리 |t| < band 인 정점만:
    아래팔 몫 s = smoothstep((t+band)/(2 band)), 위팔 몫 = 1-s (합은 그대로). 반환: 바뀐 정점 수."""
    axis = axis / np.linalg.norm(axis)
    t = (pos - elbow) @ axis
    S = W[up] + W[fo]
    m = (S >= 0.9) & (np.abs(t) < band)
    s = _smoothstep((t + band) / (2 * band))
    W[up][m] = (S * (1 - s))[m]
    W[fo][m] = (S * s)[m]
    return int(m.sum())


def smooth_region(pos, W, edges, center, radius, iters=4, mix=0.5):
    """center 반경 radius 안 정점의 가중치(모든 뼈)를 이웃 평균과 섞는 평탄화(어깨 이음의 갈라짐 줄이기). 각 정점 가중치 합은 보존(정규화)."""
    names = list(W)
    A = np.stack([W[n] for n in names], 1)
    N = len(pos)
    inside = np.linalg.norm(pos - center, axis=1) < radius
    nb = [[] for _ in range(N)]
    for a, b in edges:
        nb[a].append(b)
        nb[b].append(a)
    tot = A.sum(1, keepdims=True)
    for _ in range(iters):
        B = A.copy()
        for i in np.where(inside)[0]:
            if nb[i]:
                B[i] = (1 - mix) * A[i] + mix * A[nb[i]].mean(0)
        A = B
    s = A.sum(1, keepdims=True)
    A = np.where(s > 1e-9, A * tot / np.maximum(s, 1e-9), A)
    for k, n in enumerate(names):
        W[n] = A[:, k]
    return int(inside.sum())
