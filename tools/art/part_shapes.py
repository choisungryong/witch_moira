#!/usr/bin/env python3
"""rig_parts.py가 쓰는 부품 모양 생성기(numpy만, Blender 없이 검사된다).

모든 모양은 (verts (N,3), tris (M,3)) 를 돌려준다. 좌표는 Blender와 같다(Z 위, 정면 -Y, 캐릭터 왼쪽 +X), 원점은 부품이 붙는 자리(뼈 위의 한 점).
길이는 미터이고 키 2.0 m 모델 기준이다(호출하는 쪽이 키/2.0 배로 늘린다). 닫힌 모양은 법선이 바깥을 보게 감긴다(signed_volume > 0).
  fur_collar  : 목 밑·어깨를 두르는 털 목도리(닫힌 고리 관, 털 뭉치처럼 두께가 출렁임)
  pauldron    : 어깨 갑옷(위가 둥근 판 둘을 포갬, 테가 살짝 벌어짐)
  side_panel  : 허리 옆에 늘어지는 짧은 판(허리 자락). 아랫단이 물결, 아래로 갈수록 바깥으로 벌어짐
  hem_tube    : 판 아랫단의 가는 테(관)
"""
from __future__ import annotations

import math

import numpy as np


def signed_volume(v, t):
    a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


def _grid_tris(R, S, wrap=True):
    tris = []
    for r in range(R - 1):
        for s in range(S if wrap else S - 1):
            s1 = (s + 1) % S
            a, b, c, d = r * S + s, r * S + s1, (r + 1) * S + s, (r + 1) * S + s1
            tris.append((a, c, d))
            tris.append((a, d, b))
    return np.array(tris, int)


def _cap(center_idx, ring_start, S, flip):
    t = []
    for s in range(S):
        a, b = ring_start + s, ring_start + (s + 1) % S
        t.append((center_idx, b, a) if not flip else (center_idx, a, b))
    return t


def _fix_outward(v, t):
    if signed_volume(v, t) < 0:
        t = t[:, ::-1].copy()
    return t


def fur_collar(p):
    """닫힌 고리 관. p: a(x 반축), b(y 반축), z0, dip_side(옆으로 갈수록 처짐), dip_front, tube(관 반지름), lumps(털 뭉치 세기), n_major, n_minor."""
    a, b = p.get("a", 0.185), p.get("b", 0.105)
    z0 = p.get("z0", 0.0)
    dip_side, dip_front = p.get("dip_side", 0.05), p.get("dip_front", 0.025)
    r0 = p.get("tube", 0.05)
    lump = p.get("lumps", 0.16)
    M, N = int(p.get("n_major", 36)), int(p.get("n_minor", 10))
    cy = p.get("cy", 0.0)
    verts = []
    for i in range(M):
        th = 2 * math.pi * i / M
        cx, cyy = a * math.cos(th), b * math.sin(th)
        front = max(0.0, -math.sin(th))           # -Y(정면) 쪽
        zc = z0 - dip_side * (cx / a) ** 2 - dip_front * front
        r = r0 * (1 + lump * math.sin(5 * th + 0.7) + 0.6 * lump * math.sin(11 * th + 2.1))
        r *= 1.0 + 0.25 * (abs(math.cos(th)) ** 3)   # 어깨 쪽이 더 두툼
        # 고리 단면: 바깥 방향(xy 평면의 타원 법선)과 z
        nx, ny = math.cos(th) / a, math.sin(th) / b
        ln = math.hypot(nx, ny)
        nx, ny = nx / ln, ny / ln
        for j in range(N):
            ph = 2 * math.pi * j / N
            verts.append((cx + nx * r * math.cos(ph), cyy + cy + ny * r * math.cos(ph) * 0.95, zc + r * 0.9 * math.sin(ph)))
    v = np.array(verts)
    # 감김: i(둘레)와 j(단면)로 격자, 둘 다 닫힘
    tris = []
    for i in range(M):
        i1 = (i + 1) % M
        for j in range(N):
            j1 = (j + 1) % N
            A, B, C, D = i * N + j, i * N + j1, i1 * N + j, i1 * N + j1
            tris.append((A, C, D))
            tris.append((A, D, B))
    t = _fix_outward(v, np.array(tris, int))
    return v, t


def _dome(rx, ry, rz, center, n_az=18, n_el=6, flare=1.0):
    """위가 둥근 판(반 타원체) + 아래 테 한 겹 + 아래 뚜껑. 닫힌 모양(꼭대기는 한 점으로 용접)."""
    verts = [(center[0], center[1], center[2] + rz)]          # 꼭대기 한 점
    for k in range(1, n_el + 1):                              # 위에서 아래로 고리, 마지막(k=n_el)이 테
        el = (math.pi / 2) * (1 - k / n_el)
        f = flare if k == n_el else 1.0
        for s in range(n_az):
            az = 2 * math.pi * s / n_az
            verts.append((center[0] + rx * f * math.cos(el) * math.cos(az), center[1] + ry * f * math.cos(el) * math.sin(az), center[2] + rz * math.sin(el)))
    for s in range(n_az):                                     # 테 아래로 한 칸(두께)
        az = 2 * math.pi * s / n_az
        verts.append((center[0] + rx * flare * 0.96 * math.cos(az), center[1] + ry * flare * 0.96 * math.sin(az), center[2] - rz * 0.18))
    R = n_el + 1                                              # 고리 수(꼭대기 한 점 제외)
    tris = []
    for s in range(n_az):                                     # 꼭대기 부채
        s1 = (s + 1) % n_az
        tris.append((0, 1 + s, 1 + s1))
    for r in range(R - 1):
        for s in range(n_az):
            s1 = (s + 1) % n_az
            a, b = 1 + r * n_az + s, 1 + r * n_az + s1
            c, d = 1 + (r + 1) * n_az + s, 1 + (r + 1) * n_az + s1
            tris.append((a, c, d))
            tris.append((a, d, b))
    bot = len(verts)
    verts.append((center[0], center[1], center[2] - rz * 0.18))
    last = 1 + (R - 1) * n_az
    for s in range(n_az):
        s1 = (s + 1) % n_az
        tris.append((bot, last + s1, last + s))
    return np.array(verts), np.array(tris, int)


def pauldron(p):
    """어깨 갑옷: 큰 판 + 작은 위 판. p: rx, ry, rz, up(위 판 높이), up_scale, flare, tilt_deg(팔 방향에 맞춰 기울임)."""
    rx, ry, rz = p.get("rx", 0.085), p.get("ry", 0.095), p.get("rz", 0.058)
    v1, t1 = _dome(rx, ry, rz, (0.0, 0.0, 0.0), flare=p.get("flare", 1.08))
    s = p.get("up_scale", 0.72)
    v2, t2 = _dome(rx * s, ry * s, rz * 0.9, (-0.004, 0.0, p.get("up", 0.04)), flare=1.06)
    # 퇴화 삼각형 제거
    def clean(v, t):
        a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
        area = np.linalg.norm(np.cross(b - a, c - a), axis=1)
        return t[area > 1e-9]
    t1, t2 = clean(v1, t1), clean(v2, t2)
    t1 = _fix_outward(v1, t1)
    t2 = _fix_outward(v2, t2)
    v = np.concatenate([v1, v2])
    t = np.concatenate([t1, t2 + len(v1)])
    th = math.radians(p.get("tilt_deg", 0.0))   # Y축 둘레로 기울임: 양수면 위가 +X 쪽으로 눕는다(-X 쪽 어깨에는 음수로 위를 바깥으로 눕혀 테두리가 팔 위로 걸치게)
    if th:
        c, s_ = math.cos(th), math.sin(th)
        v = np.stack([v[:, 0] * c + v[:, 2] * s_, v[:, 1], -v[:, 0] * s_ + v[:, 2] * c], axis=1)
    return v, t


def side_panel(p):
    """허리에 걸려 옆에 늘어지는 얇은 판. 위 가장자리는 허리띠 높이(z=0 위 top), 아래로 length. x는 위 x_top에서 아래 x_bot로 벌어진다.
    p: top, length, x_top, x_bot, w_top, w_bot, thick, hem_wave, hem_amp, cols, rows, side(+1 왼쪽 +X / -1)."""
    top, length = p.get("top", 0.065), p.get("length", 0.44)
    xt, xb = p.get("x_top", 0.205), p.get("x_bot", 0.255)
    wt, wb = p.get("w_top", 0.20), p.get("w_bot", 0.27)
    thick = p.get("thick", 0.010)
    amp, waves = p.get("hem_amp", 0.025), p.get("hem_wave", 3)
    C, R = int(p.get("cols", 9)), int(p.get("rows", 6))
    cy = p.get("cy", 0.0)
    pts = np.zeros((R, C, 3))
    for r in range(R):
        tz = r / (R - 1)
        for c in range(C):
            u = c / (C - 1) - 0.5
            w = wt + (wb - wt) * tz
            hem = 0.0
            if r == R - 1:
                hem = amp * math.sin(2 * math.pi * waves * (u + 0.5)) * (0.4 + 0.6 * abs(2 * u))
            elif r == R - 2:
                hem = 0.5 * amp * math.sin(2 * math.pi * waves * (u + 0.5)) * 0.5
            x = xt + (xb - xt) * tz + p.get("curve", 0.012) * (1 - 4 * u * u) * tz
            pts[r, c] = (x, cy + u * w, top - length * tz + hem)
    n_front = np.array([1.0, 0.0, 0.0])
    # 앞면(바깥)·뒷면(안쪽) 두 장 + 옆 테두리로 닫는다
    fa = pts + n_front * thick / 2
    fb = pts - n_front * thick / 2
    v = np.concatenate([fa.reshape(-1, 3), fb.reshape(-1, 3)])
    nA = R * C
    tris = []
    for r in range(R - 1):
        for c in range(C - 1):
            a, b, cc, d = r * C + c, r * C + c + 1, (r + 1) * C + c, (r + 1) * C + c + 1
            tris += [(a, cc, d), (a, d, b)]
            tris += [(nA + a, nA + d, nA + cc), (nA + a, nA + b, nA + d)]
    # 테두리: 위·아래·좌·우
    def edge(idx):
        for i in range(len(idx) - 1):
            a0, a1 = idx[i], idx[i + 1]
            tris.append((a0, a1, nA + a1))
            tris.append((a0, nA + a1, nA + a0))
    edge([c for c in range(C)])                                         # 위(r=0)
    edge([(R - 1) * C + c for c in range(C)][::-1])                      # 아래
    edge([r * C for r in range(R)][::-1])                                # 한쪽 옆
    edge([r * C + C - 1 for r in range(R)])                              # 다른 옆
    t = _fix_outward(v, np.array(tris, int))
    return v, t


def hem_tube(p):
    """side_panel과 같은 변수로 아랫단 모서리를 따라 가는 관."""
    top, length = p.get("top", 0.065), p.get("length", 0.44)
    xt, xb = p.get("x_top", 0.205), p.get("x_bot", 0.255)
    wb = p.get("w_bot", 0.27)
    amp, waves = p.get("hem_amp", 0.025), p.get("hem_wave", 3)
    rad = p.get("tube", 0.008)
    cy = p.get("cy", 0.0)
    C = int(p.get("cols", 9)) * 2
    S = 6
    centers = []
    for c in range(C):
        u = c / (C - 1) - 0.5
        hem = amp * math.sin(2 * math.pi * waves * (u + 0.5)) * (0.4 + 0.6 * abs(2 * u))
        centers.append((xb + p.get("curve", 0.012) * (1 - 4 * u * u) + 0.004, cy + u * wb, top - length + hem))
    centers = np.array(centers)
    verts = []
    for i, c in enumerate(centers):
        T = centers[min(i + 1, C - 1)] - centers[max(i - 1, 0)]
        T /= np.linalg.norm(T) + 1e-12
        a = np.array([1.0, 0, 0])
        a = a - T * np.dot(a, T)
        a /= np.linalg.norm(a) + 1e-12
        b = np.cross(T, a)
        for s in range(S):
            th = 2 * math.pi * s / S
            verts.append(c + math.cos(th) * rad * a + math.sin(th) * rad * b)
    v = np.array(verts)
    tris = _grid_tris(C, S, True).tolist()
    n0 = len(v)
    v = np.concatenate([v, centers[:1], centers[-1:]])
    tris += _cap(n0, 0, S, True)
    tris += _cap(n0 + 1, (C - 1) * S, S, False)
    t = _fix_outward(v, np.array(tris, int))
    return v, t


SHAPES = {"fur_collar": fur_collar, "pauldron": pauldron, "side_panel": side_panel, "hem_tube": hem_tube}


def build(kind, params, scale=1.0, mirror=False):
    """모양을 만들고 키 비율(scale)로 늘린다. mirror면 x를 뒤집고 감김도 뒤집어 법선을 바깥으로 유지한다."""
    if kind not in SHAPES:
        raise KeyError("모르는 부품 모양: %s (있는 것: %s)" % (kind, ", ".join(SHAPES)))
    v, t = SHAPES[kind](params)
    v = np.asarray(v, float) * scale
    if mirror:
        v = v * np.array([-1.0, 1.0, 1.0])
        t = t[:, ::-1].copy()
    return v, t
