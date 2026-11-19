#!/usr/bin/env python3
"""char_from_sheets의 기하 부분(numpy만, Blender 없이 돈다).

그림 면별 마스크에서 뽑은 행 구간표(rows)와 캐릭터 설정(config)으로 부위별 메시(높이별 타원 단면을 이은 관)를 만든다.
좌표: Blender와 같다(Z 위, 정면 -Y, 캐릭터 왼쪽 _l 이 +X, 단위 m, 발바닥 z=0).
부위(dict): name, verts(N,3), tris(M,3), S(고리 분할), cum(고리 중심선 누적 길이), uvg(M,3,2 격자 좌표), w(둘레), h(길이),
            group(body/arm/hand/head/hair/skirt/boot...), dens(텍스처 밀도 배율), caps(위 끝/아래 끝 막음 여부)
"""
from __future__ import annotations

import math

import numpy as np


def norm(v):
    v = np.asarray(v, float)
    return v / (np.linalg.norm(v) + 1e-12)


def smooth(a, k=2):
    a = np.asarray(a, float)
    out = a.copy()
    for i in range(len(a)):
        lo, hi = max(0, i - k), min(len(a), i + k + 1)
        out[i] = a[lo:hi].mean()
    return out


def intervals(row, gap=3):
    """불리언 한 행에서 이어진 구간 [(시작, 끝)]을 뽑는다."""
    xs = np.where(row)[0]
    if len(xs) == 0:
        return []
    out = []
    s = p = xs[0]
    for x in xs[1:]:
        if x - p > gap:
            out.append((int(s), int(p)))
            s = x
        p = x
    out.append((int(s), int(p)))
    return out


def make_rings(centers, rb, ra, a_axis=(0, 1, 0), S=16):
    """centers (R,3), rb/ra (R,) 가 b/a 축 반지름. 고리 점 (R,S,3)."""
    centers = np.asarray(centers, float)
    R = len(centers)
    pts = np.zeros((R, S, 3))
    for r in range(R):
        T = centers[r + 1] - centers[r] if r < R - 1 else centers[r] - centers[r - 1]
        T = norm(T)
        a = np.asarray(a_axis, float)
        a = norm(a - T * np.dot(a, T))
        b = norm(np.cross(T, a))
        for s in range(S):
            th = 2 * math.pi * s / S
            pts[r, s] = centers[r] + math.cos(th) * rb[r] * b + math.sin(th) * ra[r] * a
    return pts


def part_from_rings(name, pts, centers, caps=(True, True), group="body", dens=1.0):
    R, S, _ = pts.shape
    verts = [pts[r, s] for r in range(R) for s in range(S)]
    tris, uvg = [], []
    vi = lambda r, s: r * S + (s % S)
    for r in range(R - 1):
        for s in range(S):
            a, b, c, d = (vi(r, s), vi(r, s + 1), vi(r + 1, s), vi(r + 1, s + 1))
            tris.append((a, c, d)); uvg.append(((s, r), (s, r + 1), (s + 1, r + 1)))
            tris.append((a, d, b)); uvg.append(((s, r), (s + 1, r + 1), (s + 1, r)))
    if caps[0]:
        c0 = len(verts); verts.append(centers[0])
        for s in range(S):
            tris.append((c0, vi(0, s), vi(0, s + 1))); uvg.append(((s + .5, 0), (s, 0), (s + 1, 0)))
    if caps[1]:
        c1 = len(verts); verts.append(centers[-1])
        for s in range(S):
            tris.append((c1, vi(R - 1, s + 1), vi(R - 1, s))); uvg.append(((s + .5, R - 1), (s + 1, R - 1), (s, R - 1)))
    # 고리 사이 간격: 중심 거리와 변 거리 가운데 큰 쪽(밑단 접힘 띠처럼 중심이 같은 고리도 UV에서 높이를 가지게)
    step = np.maximum(np.linalg.norm(np.diff(centers, axis=0), axis=1), np.linalg.norm(np.diff(pts, axis=0), axis=2).mean(axis=1))
    cum = np.concatenate([[0], np.cumsum(np.maximum(step, 1e-5))])
    circ =float(np.mean([np.linalg.norm(pts[r, 0] - pts[r, 1]) * S for r in range(R)]))
    p = dict(name=name, verts=np.array(verts), tris=np.array(tris), uvg=np.array(uvg, float), S=S, R=R, cum=cum,
             w=circ, h=float(cum[-1]), group=group, dens=dens, ring_pts=pts)
    orient_outward(p)
    return p


def vertex_normals(verts, tris):
    n = np.zeros_like(verts)
    a, b, c = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, tris[:, k], fn)
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)


def orient_outward(p):
    """고리 면의 법선이 관 바깥을 향하게 감김 방향을 맞춘다(고리 가운데 기준). 접힌 겹(속)은 호출하는 쪽이 따로 둔다."""
    ring = p["ring_pts"]
    R, S, _ = ring.shape
    n = vertex_normals(p["verts"], p["tris"])
    mid = R // 2
    out = ring[mid, 0] - ring[mid].mean(axis=0)
    p["flipped"] = False
    if np.dot(n[mid * S], out) < 0:
        p["tris"] = p["tris"][:, ::-1].copy()
        p["uvg"] = p["uvg"][:, ::-1].copy()
        p["flipped"] = True
    p["normals"] = vertex_normals(p["verts"], p["tris"])


class Rows:
    """면별 마스크의 행 구간표와 그림 좌표 <-> 미터 변환(정면 x, 측면 앞뒤, 정면 행)."""

    def __init__(self, cfg, rows):
        self.cfg = cfg
        self.rows = rows
        self.H = float(cfg["height"])
        v = cfg["views"]
        self.feet = {k: float(v[k]["feet"]) for k in ("front", "side", "back")}
        self.top = {k: float(v[k]["top"]) for k in ("front", "side", "back")}
        self.sc = {k: self.H / (self.feet[k] - self.top[k]) for k in self.feet}
        self.xc = float(v["front"]["cx"])
        self.zc = float(v["side"]["cx"])
        self.side_az = float(v["side"].get("az", 90))   # 90: 측면 그림이 캐릭터 왼쪽(+X)에서 본 것(얼굴이 그림 왼쪽). -90: 오른쪽에서 본 것(얼굴이 그림 오른쪽)
        self.side_sign = 1.0 if self.side_az > 0 else -1.0
        self.sf, self.ss, self.sb = self.sc["front"], self.sc["side"], self.sc["back"]

    def t_of_front_y(self, y):
        return (self.feet["front"] - y) / (self.feet["front"] - self.top["front"])

    def row(self, view, t):
        y = int(round(self.feet[view] - t * (self.feet[view] - self.top[view])))
        return self.rows[view][max(0, min(len(self.rows[view]) - 1, y))]

    def frow(self, yf):
        return self.rows["front"][int(yf)]

    def srow(self, yf):
        return self.row("side", self.t_of_front_y(yf))

    def front_y_of_side_y(self, ys):
        """측면 그림의 행 -> 같은 높이의 정면 그림 행(발바닥·키를 기준으로)."""
        t = (self.feet["side"] - ys) / (self.feet["side"] - self.top["side"])
        return self.feet["front"] - t * (self.feet["front"] - self.top["front"])

    def X(self, px):
        return (px - self.xc) * self.sf

    def Z(self, yf):
        return (self.feet["front"] - yf) * self.sf

    def Yw(self, zs):
        return self.side_sign * (zs - self.zc) * self.ss

    def central(self, ivs, x=None):
        x = self.xc if x is None else x
        for a, b in ivs:
            if a <= x <= b:
                return (a, b)
        return min(ivs, key=lambda i: min(abs(i[0] - x), abs(i[1] - x)))

    def envelope(self, yf, lo=300, hi=720):
        """몸통 쪽 구간(중심이 lo..hi 열)의 바깥 둘레. 치마 밑단에서 다리가 갈라져도 한 덩어리로 본다."""
        ivs = [i for i in self.frow(yf) if lo <= (i[0] + i[1]) / 2 <= hi]
        if not ivs:
            return self.central(self.frow(yf))
        return (min(i[0] for i in ivs), max(i[1] for i in ivs))

    def senvelope(self, yf):
        ivs = self.srow(yf)
        return (min(i[0] for i in ivs), max(i[1] for i in ivs))

    def vtube(self, name, rows_y, cx_px, rx_px, zc_px, rz_px, S=16, caps=(True, True), group="body", dens=1.0):
        """몸을 따라 내려가는 타원 고리 관. 입력은 정면 픽셀(x, 반폭)과 측면 픽셀(앞뒤 중심, 반두께)."""
        centers = np.array([[self.X(c), self.Yw(z), self.Z(y)] for y, c, z in zip(rows_y, cx_px, zc_px)])
        pts = make_rings(centers, np.asarray(rx_px) * self.sf, np.asarray(rz_px) * self.ss, (0, 1, 0), S)
        return part_from_rings(name, pts, centers, caps, group, dens)


def interp_table(y, ys, vs):
    return float(np.interp(y, ys, vs))


# ------------------------------------------------------------------ 부위

def build_torso(R: Rows, c):
    t = c["torso"]
    ty = np.arange(t["y0"], t["y1"], t.get("step", 12))
    KY, KHW, KZF, KZB = t["key_y"], t["key_half_width"], t["key_zf"], t["key_zb"]
    ymask = t.get("mask_from", 440)  # 이 행부터 폭은 마스크, 앞뒤는 아래 hip 표
    hip = t.get("hip", {})
    cx, rx, zc, rz = [], [], [], []
    for y in ty:
        if y < ymask:
            cx.append(R.xc)
            rx.append(np.interp(y, KY, KHW))
        elif y <= t.get("hip_from", 10 ** 6):
            a, b = R.central(R.frow(y)); cx.append((a + b) / 2); rx.append((b - a) / 2)
        else:
            cx.append(R.xc); rx.append(np.interp(y, hip["y"], hip["half_width"]))
        if y < t.get("side_from", 410):
            zf, zb = np.interp(y, KY, KZF), np.interp(y, KY, KZB)
        elif y <= t.get("hip_from", 10 ** 6):
            zf, zb = R.srow(y)[0]
        else:
            zf, zb = np.interp(y, hip["y"], hip["zf"]), np.interp(y, hip["y"], hip["zb"])
        zc.append((zf + zb) / 2); rz.append((zb - zf) / 2)
    return R.vtube("torso", ty, smooth(cx), smooth(rx, 1), smooth(zc), smooth(rz, 1), S=t.get("S", 24),
                   caps=(True, True), group="body")


def build_neck(R: Rows, c):
    n = c["neck"]
    ny = np.array(n["y"])
    k = len(ny)
    return R.vtube("neck", ny, [R.xc] * k, n["half_width"], [n["zc"]] * k, n["half_depth"], S=12, group="body")


def build_head(R: Rows, c):
    h = c["head"]
    hy = np.concatenate([h["top_rows"], np.arange(h["top_rows"][-1] + 10, h["y1"], h.get("step", 7))])
    cx, rx, zc, rz = [], [], [], []
    for y in hy:
        iv = R.central(R.frow(y), h.get("x_pick", 500))
        cx.append((iv[0] + iv[1]) / 2); rx.append(max(8, (iv[1] - iv[0]) / 2))
        a, b = R.senvelope(y)
        zc.append((a + b) / 2); rz.append(max(8, (b - a) / 2))
    cx, rx, zc, rz = smooth(cx, 1), smooth(rx, 1), smooth(zc, 1), smooth(rz, 1)
    tp = h.get("taper")
    if tp:   # 머리 아래 끝을 목 굵기로 좁힌다(머리카락 폭 그대로 두면 턱 밑에 넓은 판이 보인다. 늘어진 머리카락은 locks가 맡는다)
        for i, y in enumerate(hy):
            t = float(np.clip((y - tp["from_y"]) / float(tp["to_y"] - tp["from_y"]), 0, 1)) ** 1.5
            rx[i] = rx[i] * (1 - t) + tp["hw_end"] * t
            rz[i] = rz[i] * (1 - t) + tp["hd_end"] * t
            cx[i] = cx[i] * (1 - t) + R.xc * t
            zc[i] = zc[i] * (1 - t) + tp["zc_end"] * t
    return R.vtube("head", hy, cx, rx, zc, rz, S=h.get("S", 20),
                   group="head", dens=h.get("dens", 2.0))


def build_hair(R: Rows, c):
    """머리카락 부위: 굵은 관 여러 개(locks) + 땋은 머리(braid). 설정에 없으면 만들지 않는다."""
    out = []
    hr = c.get("hair") or {}
    for i, lk in enumerate(hr.get("locks", [])):
        n = int(lk.get("rings", 12))
        ys = np.linspace(lk["y_top"], lk["y_end"], n)
        u = np.linspace(0, 1, n)
        x = lk["x"] + lk.get("sway", 0) * np.sin(u * math.pi * lk.get("waves", 1)) + lk.get("drift", 0) * u
        z = np.interp(ys, hr["z_y"], hr["z_c"]) + lk.get("z_off", 0)
        centers = np.array([[R.X(a), R.Yw(zz), R.Z(y)] for a, zz, y in zip(x, z, ys)])
        r = np.interp(u, [0, 0.15, 0.6, 0.85, 1.0], [lk["r"] * 0.9, lk["r"], lk["r"] * 0.9, lk["r"] * 0.55, lk["r"] * 0.12]) * R.sf
        ra = r * lk.get("flat", 0.75)
        pts = make_rings(centers, r, ra, (0, 1, 0), lk.get("S", 8))
        out.append(part_from_rings("hair_lock_%d" % i, pts, centers, (False, True), "hair", hr.get("dens", 1.0)))
    br = hr.get("braid")
    if br:
        bp = np.array(br["points"], float)
        bc = np.array([[R.X(x), R.Yw(z), R.Z(y)] for x, y, z in bp])
        brad = np.array(br["radius"], float) * R.sf
        idx = np.linspace(0, len(bc) - 1, br.get("rings", 14))
        bcd = np.array([[np.interp(i, range(len(bc)), bc[:, k]) for k in range(3)] for i in idx])
        brd = np.interp(idx, range(len(bc)), brad)
        pts = make_rings(bcd, brd, brd, (0, 1, 0), 10)
        out.append(part_from_rings("braid", pts, bcd, (True, True), "hair", hr.get("dens", 1.0)))
    return out


def arm_centerline(R: Rows, c, side_name, sgn):
    a = c["arm"]
    ys = list(range(a["y0"], a["y1"], 12))
    pts_c, rad = [], []
    for y in ys:
        ivs = R.frow(y)
        cen = R.central(ivs)
        if sgn > 0:
            sel = [i for i in ivs if i[0] > cen[1] + 4 and (i[0] + i[1]) / 2 > R.xc + a["min_dx"]]
        else:
            sel = [i for i in ivs if i[1] < cen[0] - 4 and (i[0] + i[1]) / 2 < R.xc - a["min_dx"]]
        if not sel:
            break
        lo = min(i[0] for i in sel); hi = max(i[1] for i in sel)
        pts_c.append(((lo + hi) / 2, y)); rad.append((hi - lo) / 2)
    pts_c = np.array(pts_c, float)
    pts_c[:, 0] = smooth(pts_c[:, 0], 1)
    rad = smooth(rad, 1)
    slope = (pts_c[4, 0] - pts_c[0, 0]) / (pts_c[4, 1] - pts_c[0, 1])
    top = [(pts_c[0, 0] + slope * (y - pts_c[0, 1]), y) for y in a["top_extrap"]]
    allc = np.vstack([np.array(top), pts_c])
    rr = np.concatenate([a["top_r"], rad])
    ang = np.arctan2(np.gradient(allc[:, 0]), np.gradient(allc[:, 1]))
    rr_p = np.maximum(rr * np.cos(ang), 7)
    return allc, rr_p


def finger_parts(side_name, sgn, centers, h, S=6):
    """손가락 다섯: 팔 끝 방향 u 를 따라 부채꼴(앞뒤 방향 Y 로 벌어짐, A자세에서 손바닥은 몸쪽(±X)을 봄).
    치수는 손 클로즈업 그림(hands-r1)에서 잰 비율: 손바닥 길이 대비 중지 0.94, 약지 0.87, 검지 0.82, 소지 0.70, 엄지 0.66(m는 h['palm_len']에 곱)."""
    u = centers[-1] - centers[-3]
    u = u / (np.linalg.norm(u) + 1e-9)
    base = centers[-1] - u * h["overlap"]
    yv = np.array([0.0, 1.0, 0.0])
    out = []
    # (이름, 시작 Y 오프셋, 부채 각도(도, +Y 쪽), 길이/손바닥, 굵기 m, 시작 위치(손바닥 안쪽으로 되돌림 m))
    spec = [("index", -0.026, -5, 0.82, 0.0085, 0.0), ("middle", -0.009, 0, 0.94, 0.0090, 0.0),
            ("ring", 0.009, 5, 0.87, 0.0085, 0.0), ("pinky", 0.026, 12, 0.70, 0.0072, 0.006),
            ("thumb", -0.038, -42, 0.66, 0.0100, 0.040)]
    for k, (nm, yo, ang, ln, rad, back) in enumerate(spec):
        th = math.radians(ang)
        # u 를 Y 축 쪽으로 th 만큼 눕힌 방향(u 는 거의 아래쪽이라 x-z 평면, 눕히는 평면은 u 와 Y)
        d = u * math.cos(th) + yv * math.sin(th)
        d = d / np.linalg.norm(d)
        p0 = base - u * back + yv * yo
        L = ln * h["palm_len"]
        n = 4
        cs = np.array([p0 + d * L * t for t in np.linspace(0, 1, n)])
        rr = np.array([rad, rad * 0.95, rad * 0.8, rad * 0.55])
        pts = make_rings(cs, rr, rr, (1, 0, 0), S)
        out.append(part_from_rings("hand_%s_%s" % (side_name, nm), pts, cs, (False, True), "hand", h.get("dens", 1.0)))
    return out


def build_arms(R: Rows, c):
    a = c["arm"]
    out, info = [], {}
    for side_name, sgn in (("l", +1), ("r", -1)):
        allc, rr_p = arm_centerline(R, c, side_name, sgn)
        zs = np.interp(allc[:, 1], a["depth_y"], a["depth_z"])
        centers = np.array([[R.X(x), R.Yw(z), R.Z(y)] for (x, y), z in zip(allc, zs)])
        rb = rr_p * R.sf
        ra = np.maximum(rr_p * a.get("flat", 0.85), 7) * R.ss
        h = a.get("hand")
        fingers = []
        if h:
            # 손: 팔 관의 끝을 손바닥으로(앞뒤로 넓고 몸쪽으로 얇게) 두고 손가락 다섯을 따로 단다
            dist_end = np.concatenate([np.cumsum(np.linalg.norm(np.diff(centers[::-1], axis=0), axis=1))[::-1], [0.0]])
            keep = dist_end >= h["trim"]
            n_keep = int(np.argmax(~keep)) if (~keep).any() else len(keep)
            centers, rb, ra, dist_end = centers[:n_keep], rb[:n_keep], ra[:n_keep], dist_end[:n_keep] - dist_end[n_keep - 1]
            palm = dist_end <= h["palm_len"]
            t = np.clip(1.0 - dist_end[palm] / h["palm_len"], 0, 1)
            ra[palm] = np.interp(t, [0, 0.5, 1.0], [h["wrist_half"], h["palm_half"], h["palm_half"] * 0.95])
            rb[palm] = np.maximum(rb[palm] * 0.8, h["thick_half"])
            fingers = finger_parts(side_name, sgn, centers, h)
        else:
            k = a.get("hand_rings", 6)
            ra[-k:] = np.maximum(ra[-k:] * 0.55, 4 * R.ss)
        pts = make_rings(centers, rb, ra, (0, 1, 0), 12)
        out.append(part_from_rings("arm_" + side_name, pts, centers, (True, True), "arm", a.get("dens", 1.0)))
        out += fingers
        info[side_name] = dict(allc=allc.tolist(), rad=rr_p.tolist())
    return out, info


def build_legs(R: Rows, c, side_mask_loader=None):
    lg = c["leg"]
    out, info = [], {}
    for side_name, sgn in (("l", +1), ("r", -1)):
        ys = list(range(lg["y0"], lg["y1"], lg.get("step", 14)))
        cxs, rxs, zcs, rzs = [], [], [], []
        for y in ys:
            ivs = R.frow(y)
            ivs2 = [i for i in ivs if ((i[0] + i[1]) / 2 - R.xc) * sgn > lg.get("min_dx", 20)]
            i = max(ivs2, key=lambda i: i[1] - i[0])
            cxs.append((i[0] + i[1]) / 2); rxs.append((i[1] - i[0]) / 2)
            a, b = R.senvelope(y)
            zcs.append((a + b) / 2); rzs.append((b - a) / 2 * lg.get("depth_k", 0.96))
        cxs = smooth(cxs, 1); rxs = smooth(rxs, 1); zcs = smooth(zcs, 1); rzs = smooth(rzs, 1)
        up = lg.get("extend_up", [700, 722])
        ys_full = list(up) + ys
        n = len(up)
        cxs = np.concatenate([[cxs[0]] * n, cxs]); rxs = np.concatenate([[rxs[0]] * n, rxs])
        zcs = np.concatenate([[zcs[0]] * n, zcs]); rzs = np.concatenate([[rzs[0]] * n, rzs])
        out.append(R.vtube("leg_" + side_name, ys_full, cxs, rxs, zcs, rzs, S=14, group="leg", dens=lg.get("dens", 1.0)))
        info[side_name] = dict(ys=ys_full, cx=cxs.tolist())
    return out, info


def build_feet(R: Rows, c, side_mask, leg_info, sole=None):
    """장화 발: 발끝에서 뒤꿈치로 이어지는 관. 위아래 높이는 측면 마스크의 열 단면, 폭은 설정의 표(sole_width)."""
    f = c["foot"]
    out = []
    xs_all = np.linspace(f["x0"], f["x1"], int(abs(f["x1"] - f["x0"]) / f.get("step", 12)) + 1)   # x0 = 발끝 열, x1 = 뒤꿈치 열(어느 쪽이 커도 된다)
    wx = f["width_x"]; wv = f["width"]
    for side_name, sgn in (("l", +1), ("r", -1)):
        cxl = leg_info[side_name]["cx"][-1]
        centers, rb, ra = [], [], []
        for xs in xs_all:
            col = np.where(side_mask[f["y0"]:f["y1"], int(round(xs))])[0]
            if len(col) == 0:
                continue
            yt, yb = col.min() + f["y0"], col.max() + f["y0"]
            zmid = (yt + yb) / 2
            hh = max(f.get("min_half_height", 6), (yb - yt) / 2)
            if sole:   # 밑창 그림에서 잰 폭 곡선(발끝 -> 뒤꿈치)
                t = (xs - f["x0"]) / float(f["x1"] - f["x0"])
                hw = f["wmax"] * np.interp(t, np.linspace(0, 1, len(sole)), sole)
                hw = max(hw, 3.5)
            else:
                hw = np.interp(xs, wx, wv)
            centers.append([R.X(cxl), R.Yw(xs), R.Z(R.front_y_of_side_y(zmid))])
            rb.append(hw * R.sf); ra.append(hh * R.sf)
        centers = np.array(centers)
        pts = make_rings(centers, np.array(rb), np.array(ra), (0, 0, 1), f.get("S", 12))
        out.append(part_from_rings("foot_" + side_name, pts, centers, (True, True), "boot", f.get("dens", 1.0)))
    return out


def fold_ring_sequence(rings_outer, rings_inner):
    return np.concatenate([rings_outer, rings_inner[::-1]], axis=0)


def build_skirt(R: Rows, c):
    """치마: 겹마다 바깥 껍질 + 속 껍질(두께). 위 겹이 아래 겹 위로 덮이고 밑단에서 속이 보여도 비지 않는다."""
    sk = c.get("skirt")
    if not sk:
        return []
    S = sk.get("S", 28)
    thick = sk.get("thick", 4.0)
    t = c["torso"]
    out = []
    for ti, tier in enumerate(sk["tiers"]):
        ys = np.linspace(tier["y0"], tier["y1"], tier.get("rings", 9))
        cxs, rxs, zcs, rzs = [], [], [], []
        for y in ys:
            env = R.envelope(y)
            e_c, e_hw = (env[0] + env[1]) / 2, (env[1] - env[0]) / 2
            sa, sb = R.senvelope(y)
            f = np.interp(y, tier["k_y"], tier["k"])
            ramp = 1.0
            if "ramp_y" in tier:
                ramp = np.clip((y - tier["ramp_y"][0]) / (tier["ramp_y"][1] - tier["ramp_y"][0]), 0, 1)
            top_hw = tier.get("top_hw", e_hw)
            hw = (top_hw * (1 - ramp) + e_hw * ramp) * f
            hd = ((sb - sa) / 2) * f
            if "ramp_y" in tier:
                hd = tier.get("top_hd", hd) * (1 - ramp) + hd * ramp
            cxs.append(e_c if ramp > 0 else R.xc); rxs.append(hw); zcs.append((sa + sb) / 2); rzs.append(hd)
        cxs = smooth(cxs, 1); rxs = smooth(rxs, 1); zcs = smooth(zcs, 1); rzs = smooth(rzs, 1)
        def rings(dr):
            centers = np.array([[R.X(cx), R.Yw(z), R.Z(y)] for y, cx, z in zip(ys, cxs, zcs)])
            return centers, make_rings(centers, (rxs - dr) * R.sf, (rzs - dr) * R.ss, (0, 1, 0), S)
        cen_o, ro = rings(0.0)
        cen_i, ri = rings(thick)
        # 바깥 껍질: 위 -> 밑단 -> 밑단 속 고리(테두리 띠)
        seq = np.concatenate([ro, ri[-1:]], axis=0)
        cens = np.concatenate([cen_o, cen_i[-1:]], axis=0)
        p = part_from_rings("skirt%d" % ti, seq, cens, (False, False), "skirt", sk.get("dens", 1.0))
        out.append(p)
        # 속 껍질: 밑단 -> 위 (법선이 안쪽을 향함 -> 바깥 쪽과 감김 방향이 반대가 되게 다시 만든다)
        seq_i = ri[::-1]
        cens_i = cen_i[::-1]
        q = part_from_rings("skirt%d_in" % ti, seq_i, cens_i, (False, False), "skirt_in", sk.get("dens_in", 0.25))
        # 속 껍질은 법선이 축 쪽을 향해야 하므로 orient_outward가 바깥으로 맞춘 것을 뒤집는다
        q["tris"] = q["tris"][:, ::-1].copy(); q["uvg"] = q["uvg"][:, ::-1].copy()
        q["normals"] = vertex_normals(q["verts"], q["tris"])
        out.append(q)
    return out


def build_all(R: Rows, c, side_mask=None, extra=None):
    parts = [build_torso(R, c), build_neck(R, c), build_head(R, c)]
    parts += build_hair(R, c)
    arms, ainfo = build_arms(R, c)
    legs, linfo = build_legs(R, c)
    parts += arms + legs
    parts += build_skirt(R, c)
    if side_mask is not None and c.get("foot"):
        parts += build_feet(R, c, side_mask, linfo, (extra or {}).get("sole"))
    return parts, dict(arm=ainfo, leg=linfo)
