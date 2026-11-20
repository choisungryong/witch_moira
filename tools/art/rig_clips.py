#!/usr/bin/env python3
"""rig_build가 만든 뼈대에 동작 6개(idle, run, cast, hit, death, dodge)를 코드로 찍어 glb로 내보낸다(Blender 5.3 명령줄).

  python tools/art/rig_clips.py --blend RIGGED.blend --out-glb OUT.glb [--config my.json] [--report r.json] [--fps 60] [--preview DIR]
  python tools/art/rig_clips.py --blend RIGGED.blend --out-glb OUT.glb --retarget-from SOURCE.glb [--retarget-map map.json]
      (SOURCE의 동작을 새 뼈대로 옮긴다. 뼈 이름이 같으면 대응표 없이 된다. 이름이 다르면 {"새뼈":"원본뼈"} JSON)

길이는 게임이 기대하는 값: idle 1.2초(순환), run 0.6초(한 걸음 주기, 순환), cast 0.6초(게임은 0.15~0.6 구간을 씀), hit 0.3초, death 0.9초, dodge 0.5초.
달리기 한 주기의 이동 거리는 게임의 HERO_STRIDE(2.15)를 모델 배율로 나눈 값에 맞춘다(발 미끄러짐을 줄이려는 것).
보고서(JSON)에 클립마다 변 늘어남 비율(0.6배 미만·1.5배 초과), 발 미끄러짐, 바닥 아래 깊이, 다리 과신장 프레임 수를 적는다. 모델의 계산이며 보이는 품질이 아니다.
절차식 동작은 읽히는 수준의 자리표시자다. 손맛(무게 이동, 팔 휘두름)은 사람이 다듬어야 한다.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def keys(t, pts):
    """(시간, 값) 목록을 부드럽게 이은 값."""
    if t <= pts[0][0]:
        return pts[0][1]
    for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * smooth((t - t0) / (t1 - t0))
    return pts[-1][1]


class Ctx:
    def __init__(self, rig: rc.Rig, H: float, cfg: dict):
        from mathutils import Vector
        self.rig, self.H, self.cfg = rig, H, cfg
        self.V = Vector
        cc = cfg["clips"]
        self.stride = cc["game_hero_stride"] * H / cc["game_target_height"]
        self.hip = {s: rig.head["thigh_cr_" + s].copy() for s in "lr"}
        self.knee = {s: rig.head["shin_cr_" + s].copy() for s in "lr"}
        self.ankle = {s: rig.head["tarsal_cr_" + s].copy() for s in "lr"}
        self.l1 = {s: (self.knee[s] - self.hip[s]).length for s in "lr"}
        self.l2 = {s: (self.ankle[s] - self.knee[s]).length for s in "lr"}
        self.Ltot = self.l1["l"] + self.l2["l"]
        # 쉬는 자세의 팔이 수평에 가까운 T자세면 모든 동작의 팔을 40도 아래로 내려 시작한다(A자세는 그대로)
        u0 = rig.rest_dir["upper_arm_cr_l"]
        self.rest_arm_drop = math.degrees(math.asin(max(min(-u0.z, 1.0), -1.0)))
        want = cfg["clips"].get("arm_rest_drop_deg", 40.0)
        self.arm_offset = -(want - self.rest_arm_drop) if (self.rest_arm_drop < want - 5 and cfg["clips"].get("arm_auto_drop", True)) else 0.0
        self.overext = 0
        self.reach_max = 0.0
        self.frame_reach = 0.0
        self.min_z = 0.0

    # --- 다리 2-뼈 IK
    def leg_ik(self, s, hip, target, pole=(0, -1, 0)):
        V = self.V
        l1, l2 = self.l1[s], self.l2[s]
        d = target - hip
        dist = d.length
        top = (l1 + l2) * 0.9995
        self.frame_reach = max(self.frame_reach, dist / (l1 + l2))
        if dist > top:
            d = d.normalized() * top
            dist = top
        dist = max(dist, abs(l1 - l2) + 1e-4)
        dn = d.normalized()
        a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        pv = V(pole)
        perp = pv - dn * pv.dot(dn)
        if perp.length < 1e-3:
            perp = V((0, 0, 1)) - dn * dn.z
        perp.normalize()
        knee = hip + dn * a + perp * h
        return knee, hip + dn * dist

    def arm_rots(self, s, pitch, abduct, bend):
        """쉬는 A자세 대비 팔 회전(월드 3x3) 셋: 위팔, 아래팔·손."""
        V, rig = self.V, self.rig
        sgn = 1 if s == "l" else -1
        up, fo = "upper_arm_cr_" + s, "forearm_cr_" + s
        u0 = rig.rest_dir[up]
        out = V((sgn, 0, 0))
        axis = u0.cross(out)
        if axis.length < 1e-6:
            axis = V((0, 1, 0))
        Ra = rc.rot_about(axis.normalized(), abduct + self.arm_offset)
        Rp = rc.rot("X", -pitch)
        Rup = Rp @ Ra
        f_dir = Rup @ rig.rest_dir[fo]
        bax = f_dir.cross(V((0, -1, 0)))
        if bax.length < 1e-6:
            bax = V((1, 0, 0))
        Rb = rc.rot_about(bax.normalized(), bend)
        return Rup, Rb @ Rup

    def solve(self, spec):
        """자세를 풀고, 다리가 끝까지 펴져도 모자라면(1.0005배 초과) 골반을 낮춰 다시 푼다."""
        spec.setdefault("sink", 0.0)
        for _ in range(14):
            self.frame_reach = 0.0
            S = self._solve(spec)
            if self.frame_reach <= 1.0005 or spec.get("no_sink"):
                break
            spec["sink"] -= (self.frame_reach - 1.0) * self.Ltot * 1.6
            spec["sink"] = max(spec["sink"], -0.6 * self.Ltot)
        self.reach_max = max(self.reach_max, self.frame_reach)
        if self.frame_reach > 1.001:
            self.overext += 1
        return S

    def _solve(self, spec):
        V, rig = self.V, self.rig
        S = rig.solver()
        S.place("origin")
        pt = V(spec.get("pelvis_t", (0, 0, 0)))
        lift = spec.get("lift", 0.0)
        pt = pt + V((0, 0, lift + spec.get("sink", 0.0)))
        S.place("pelvis_cr", fk=spec.get("pelvis_fk"), trans=rig.head["pelvis_cr"] + pt)
        sp = spec.get("spine", [(0, 0, 0)] * 3)
        for i, n in enumerate(("spine_cr_01", "spine_cr_02", "spine_cr_03")):
            p, r, y = sp[i]
            S.place(n, fk=rc.rot("Z", y) @ rc.rot("Y", r) @ rc.rot("X", p))
        hp, hr, hy = spec.get("head", (0, 0, 0))
        S.place("neck_cr", fk=rc.rot("Z", hy * 0.4) @ rc.rot("X", hp * 0.4))
        S.place("head_cr", fk=rc.rot("Z", hy * 0.6) @ rc.rot("Y", hr) @ rc.rot("X", hp * 0.6))
        arms = spec.get("arms", {})
        for s in "lr":
            S.place("shoulder_cr_" + s)
            pitch, abd, bend = arms.get(s, (0, 0, 0))
            Rup, Rfo = self.arm_rots(s, pitch, abd, bend)
            S.place("upper_arm_cr_" + s, absd=Rup @ rig.rest_rot["upper_arm_cr_" + s])
            S.place("forearm_cr_" + s, absd=Rfo @ rig.rest_rot["forearm_cr_" + s])
            S.place("hand_cr_" + s, absd=Rfo @ rig.rest_rot["hand_cr_" + s])
        S.place("finger_middle.01.r")
        feet = spec.get("feet", {})
        for s in "lr":
            hip = S.head_pos("thigh_cr_" + s)
            f = feet.get(s, {})
            tgt = self.ankle[s] + V(f.get("d", (0, 0, 0))) + V((0, 0, lift))
            if "hip_rel" in f:
                blend, rel = f["hip_rel"]
                tgt = tgt.lerp(hip + V(rel), blend)
            knee, ankle = self.leg_ik(s, hip, tgt, f.get("pole", (0, -1, 0)))
            Dt = rc.delta_between(rig.rest_dir["thigh_cr_" + s], knee - hip)
            Ds = rc.delta_between(rig.rest_dir["shin_cr_" + s], ankle - knee)
            S.place("thigh_cr_" + s, absd=Dt @ rig.rest_rot["thigh_cr_" + s])
            S.place("shin_cr_" + s, absd=Ds @ rig.rest_rot["shin_cr_" + s])
            S.place("tarsal_cr_" + s, absd=rc.rot("X", f.get("pitch", 0.0)) @ rig.rest_rot["tarsal_cr_" + s])
            S.place("toe_cr_" + s)
        S.finish()
        return S


# ------------------------------------------------------------------ 클립 정의(시간 t초 -> 자세 명세)

def cc(c, key, default):
    return c.cfg["clips"].get(key, default)


def elem_sides(c):
    """원소 팔(마녀마다 다름)과 지팡이 쥔 팔의 쪽. 설정 clips.elem_arm = 'l' | 'r'."""
    e = cc(c, "elem_arm", "l")
    return e, ("r" if e == "l" else "l")


def spec_idle(c, t):
    """숨(한 주기 1.2초) + 아주 느린 머리 갸웃(두 주기). 길이는 계약(1.2초)이라 긴 무게 이동 겹은 못 넣는다."""
    T = 1.2
    s, co = math.sin(2 * math.pi * t / T), math.cos(2 * math.pi * t / T)
    s2 = math.sin(4 * math.pi * t / T + 0.7)
    H = c.H
    e, o = elem_sides(c)
    sg = 1 if e == "l" else -1
    return {
        "pelvis_t": (0.003 * H * s, 0, -0.004 * H * (0.5 + 0.5 * co)),
        "spine": [(0.6 * s, 0.5 * co, 0), (0.8 * s, 0.4 * co, 0), (1.0 * s, 0, 0)],
        "head": (-1.4 * s + 0.4 * s2, 0.3 * s2, 0),
        "arms": {e: (2.0 * s * sg, 1.5 * co * sg, 2.0), o: (-2.0 * s * sg, -1.5 * co * sg, 2.0)},
    }


def spec_run(c, t):
    """몸을 세운 가벼운 뜀. 한 주기(0.6초) = 걸음 둘, 딛는 비율 stance(<0.5)라 두 발이 다 뜨는 구간이 있다.
    골반은 딛는 중간에 가장 낮고(다리가 굽혀 용수철처럼 눌림, 몸 높이의 약 6%) 뜨는 순간 가장 높다. 몸통 앞 기울기 약 7도.
    원소 팔은 크게, 지팡이 팔은 굽혀 작게 흔든다."""
    T = 0.6
    H, Lt = c.H, c.Ltot
    ph = (t / T) % 1.0
    st = cc(c, "run_stance_fraction", 0.38)
    a = c.stride * st / 2.0
    comp = cc(c, "run_comp", 0.06) * H
    lift_h = cc(c, "run_lift", 0.20) * Lt
    feet = {}
    for s, off in (("l", 0.0), ("r", 0.5)):
        pl = (ph + off) % 1.0
        if pl < st:
            u = pl / st
            f, dz, pit = a * (1 - 2 * u), 0.0, 0.0
        else:
            w = (pl - st) / (1 - st)
            f = -a + 2 * a * smooth(w)
            dz = lift_h * math.sin(math.pi * w) ** 1.2
            pit = 24.0 * math.sin(math.pi * w)
        feet[s] = {"d": (0, -f, dz), "pitch": pit}
    # 눌림: 딛는 중간(ph = st/2, 0.5 + st/2)에 1, 뜬 순간에 0
    press = 0.5 + 0.5 * math.cos(4 * math.pi * (ph - st / 2.0))
    yaw = 6.0 * math.cos(2 * math.pi * ph)
    roll = 2.5 * math.sin(2 * math.pi * ph)
    swing = math.cos(2 * math.pi * ph)
    e, o = elem_sides(c)
    sgl = {"l": -1.0, "r": 1.0}      # 왼팔은 왼발이 앞일 때(ph=0) 뒤로
    amp_e, amp_o = cc(c, "run_arm_elem", 42.0), cc(c, "run_arm_other", 15.0)
    arms = {
        e: (sgl[e] * amp_e * swing, -10.0, 70.0 + 18.0 * (1 + sgl[e] * swing * -1) * 0.5),
        o: (sgl[o] * amp_o * swing + 10.0, -10.0, 95.0),
    }
    return {
        "pelvis_t": (0.008 * H * math.sin(2 * math.pi * ph), 0, -0.02 * H - comp * press),
        "pelvis_fk": rc.rot("Z", yaw) @ rc.rot("Y", roll),
        "spine": [(2.8, -roll * 0.4, -yaw * 0.4), (2.6, -roll * 0.4, -yaw * 0.5), (2.2, 0, -yaw * 0.6)],
        "head": (-6.0 + 1.0 * press, 0, -yaw * 0.3),
        "arms": arms,
        "feet": feet,
    }


# ---------- 키 자세 방식: (시간, 값) 이정표 -> 값마다 부드럽게 잇는다
NEUTRAL = dict(lean=0.0, twist=0.0, pyaw=0.0, sink=0.0, fwd=0.0, lunge=0.0, head_p=0.0, E=(2.0, 0.0, 2.0), O=(2.0, 0.0, 2.0))


def key_pose(t, marks):
    """marks: [(t, {값 일부})]. 빠진 값은 NEUTRAL. 값은 숫자 또는 숫자 묶음."""
    full = []
    for tt, d in marks:
        p = dict(NEUTRAL)
        p.update(d)
        full.append((tt, p))
    if t <= full[0][0]:
        return full[0][1]
    for (t0, p0), (t1, p1) in zip(full, full[1:]):
        if t <= t1:
            k = smooth((t - t0) / max(t1 - t0, 1e-9))
            out = {}
            for key, v0 in p0.items():
                v1 = p1[key]
                if isinstance(v0, tuple):
                    out[key] = tuple(a + (b - a) * k for a, b in zip(v0, v1))
                else:
                    out[key] = v0 + (v1 - v0) * k
            return out
    return full[-1][1]


def pose_to_spec(c, p, lift=False):
    H, Lt = c.H, c.Ltot
    e, o = elem_sides(c)
    sp_w = (0.3, 0.35, 0.35)
    spec = {
        "pelvis_t": (0, -p["fwd"] * H, -p["sink"] * Lt),
        "pelvis_fk": rc.rot("Z", p["pyaw"]),
        "spine": [(p["lean"] * w, 0, p["twist"] * w) for w in sp_w],
        "head": (p["head_p"], 0, -p["twist"] * 0.3),
        "arms": {e: p["E"], o: p["O"]},
    }
    if abs(p["lunge"]) > 1e-6:
        spec["feet"] = {"l": {"d": (0, -p["lunge"] * Lt, 0)}, "r": {"d": (0, p["lunge"] * Lt, 0)}}
    if lift:
        spec["lift_to_ground"] = True
    return spec


# 기본기 시전 셋: 모두 0.28초. 예비 0.03초 -> 뻗음 0.07초(이벤트 뒤 4프레임) -> 머묾 -> 되돌아옴 0.28초
def _marks_frost():      # 곧은 창: 원소 팔을 가슴에서 곧게(몸 가운데 선으로) 앞으로 찌름
    return [(0.0, {}), (0.03, dict(E=(30, -10, 120), O=(18, 10, 70), lean=-3, twist=-6, head_p=2)),
            (0.07, dict(E=(90, -32, 3), O=(32, 12, 60), lean=9, twist=8, fwd=0.01, head_p=-4)),
            (0.12, dict(E=(92, -32, 2), O=(32, 12, 60), lean=9, twist=8, fwd=0.01, head_p=-4)), (0.28, {})]


def _marks_storm():      # 꺾인 줄기: 낮게 웅크린 팔을 위로 튕겨 올리고(0.07초) 손목을 꺾으며 아래로 내리긋는다(0.18초)
    return [(0.0, {}), (0.03, dict(E=(8, 30, 55), O=(10, 20, 80), lean=-4, twist=-3, head_p=3)),
            (0.07, dict(E=(130, 26, 22), O=(10, 20, 80), lean=5, twist=4, head_p=8)),
            (0.12, dict(E=(104, 24, 24), O=(10, 20, 80), lean=8, twist=6, head_p=0)),
            (0.18, dict(E=(58, 16, 34), O=(10, 20, 80), lean=10, twist=7, head_p=-6)), (0.28, {})]


def _marks_ember():      # 덩어리 던지기: 팔을 뒤로 젖히며 몸통을 비틀었다가 어깨 위로 던져 몸 전체가 따라감
    return [(0.0, {}), (0.03, dict(E=(-45, 8, 75), O=(20, 20, 60), lean=-8, twist=-16, pyaw=-10, sink=0.03)),
            (0.07, dict(E=(105, -10, 15), O=(20, 22, 60), lean=14, twist=14, pyaw=12, sink=0.05, fwd=0.03, lunge=0.08, head_p=-6)),
            (0.12, dict(E=(125, -8, 5), O=(20, 22, 60), lean=16, twist=16, pyaw=14, sink=0.05, fwd=0.03, lunge=0.08, head_p=-6)), (0.28, {})]


def _marks_ring():       # 둘레 주문: 원소 팔을 옆으로 수평으로 펴고 몸을 한 바퀴(약 75도) 돌며 휘두름, 낮게 앉음
    return [(0.0, {}), (0.06, dict(E=(25, 90, 20), O=(10, 30, 60), twist=-35, pyaw=-20, sink=0.08, lean=4)),
            (0.16, dict(E=(25, 90, 10), O=(10, 30, 60), twist=40, pyaw=25, sink=0.08, lean=4)),
            (0.20, dict(E=(25, 90, 10), O=(10, 30, 60), twist=40, pyaw=25, sink=0.08, lean=4)), (0.32, {})]


_CALL = dict(E=(175, 18, 3), O=(20, 25, 50), lean=-10, head_p=12)


def _marks_call():       # 강림 부름: 원소 팔을 하늘로 올리고(0.4초) 거기서 머문다(0.4~0.9초, 끝이 0.4초 자세와 같아 반복 가능)
    return [(0.0, {}), (0.4, dict(_CALL)), (0.65, dict(E=(179, 20, 3), O=(20, 25, 50), lean=-11, head_p=13)), (0.9, dict(_CALL))]


def _marks_strike():     # 강림 내려침: 시작은 부름의 머문 자세, 뒤로 젖혔다가 땅으로 내리치며 깊이 앉는다
    return [(0.0, dict(_CALL)), (0.20, dict(E=(185, 10, 0), O=(20, 25, 50), lean=-16, head_p=14, sink=0.03)),
            (0.32, dict(E=(40, 6, 5), O=(20, 25, 50), lean=26, head_p=-10, sink=0.20, lunge=0.22, fwd=0.05, pyaw=15, twist=12)),
            (0.50, dict(E=(40, 6, 5), O=(20, 25, 50), lean=26, head_p=-10, sink=0.20, lunge=0.22, fwd=0.05, pyaw=15, twist=12)), (0.9, {})]


def _marks_dash():       # 돌진: 몸을 낮추고 앞으로 미끄러짐(구르기 아님), 팔은 뒤로
    return [(0.0, {}), (0.06, dict(lean=22, sink=0.22, fwd=0.06, lunge=0.28, E=(-40, 20, 30), O=(-35, 20, 30), head_p=-12)),
            (0.14, dict(lean=22, sink=0.22, fwd=0.06, lunge=0.28, E=(-40, 20, 30), O=(-35, 20, 30), head_p=-12)),
            (0.2, dict(lean=12, sink=0.10, fwd=0.02, lunge=0.14, E=(-10, 10, 40), O=(-10, 10, 40), head_p=-6))]


MARKS = {"cast_basic_frost": _marks_frost, "cast_basic_storm": _marks_storm, "cast_basic_ember": _marks_ember,
         "cast_ring": _marks_ring, "descent_call": _marks_call, "descent_strike": _marks_strike, "dash": _marks_dash}
LENGTHS_NEW = {"cast_basic_frost": 0.28, "cast_basic_storm": 0.28, "cast_basic_ember": 0.28, "cast_ring": 0.32,
               "descent_call": 0.9, "descent_strike": 0.9, "dash": 0.2}


def make_marks_spec(name):
    fn = MARKS[name]
    marks = fn()

    def spec(c, t):
        return pose_to_spec(c, key_pose(t, marks), lift=name in ("dash", "descent_strike"))
    return spec


def spec_cast(c, t):
    H = c.H
    r = keys(t, [(0, 0.0), (0.15, 0.6), (0.32, 1.0), (0.6, 0.0)])
    lean = keys(t, [(0, 0.0), (0.15, -5.0), (0.32, 10.0), (0.6, 0.0)])
    return {
        "pelvis_t": (0, -0.01 * H * r, -0.02 * c.Ltot * r),
        "spine": [(lean * 0.3, 0, 0), (lean * 0.35, 0, 0), (lean * 0.35, 0, 0)],
        "head": (-lean * 0.5, 0, 0),
        "arms": {"r": (80 * r, 6 * r, 15 * r), "l": (65 * r, 16 * r, 35 * r)},
    }


def spec_hit(c, t):
    H = c.H
    r = keys(t, [(0, 0.0), (0.1, 1.0), (0.3, 0.0)])
    return {
        "pelvis_t": (0, 0.02 * H * r, -0.01 * H * r),
        "spine": [(-5 * r, 0, 0), (-5 * r, 0, 0), (-4 * r, 0, 0)],
        "head": (-10 * r, 0, 0),
        "arms": {"l": (-15 * r, 22 * r, 10 * r), "r": (-15 * r, 22 * r, 10 * r)},
    }


def spec_death(c, t):
    H = c.H
    u = t / 0.9
    k = smooth(u / 0.5)
    f = smooth((u - 0.3) / 0.7)
    pz = c.rig.head["pelvis_cr"].z
    dz = -0.40 * c.Ltot * k * (1 - f) - (pz - 0.06 * H) * f
    return {
        "pelvis_t": (0, 0.30 * H * f, dz),
        "pelvis_fk": rc.rot("X", -90.0 * f),
        "spine": [(4 * k * (1 - f), 0, 0), (6 * k * (1 - f), 0, 0), (4 * k * (1 - f), 0, 0)],
        "head": (-8 * f, 0, 0),
        "arms": {"l": (-20 * f, 55 * f, 25 * f), "r": (-20 * f, 55 * f, 25 * f)},
        "feet": {s: {"hip_rel": (smooth((u - 0.45) / 0.55), (0, -0.95 * c.Ltot, 0)), "d": (0, 0, 0)} for s in "lr"},
        "lift_to_ground": True,
    }


def spec_dodge(c, t):
    H = c.H
    u = t / 0.5
    e = math.sin(math.pi * min(max(u, 0), 1)) ** 0.8
    Lt = c.Ltot
    return {
        "pelvis_t": (0, -0.08 * H * e, -0.34 * Lt * e),
        "spine": [(11 * e, 0, 0), (11 * e, 0, 0), (9 * e, 0, 0)],
        "head": (-12 * e, 0, 0),
        "arms": {"l": (30 * e, 35 * e, 20 * e), "r": (-25 * e, 35 * e, 10 * e)},
        "lift_to_ground": True,
        "feet": {"r": {"d": (0, -0.50 * Lt * e, 0), "pitch": 0},
                 "l": {"d": (0, 0.45 * Lt * e, 0.09 * Lt * e), "pitch": 12 * e}},
    }


CLIPS = {"idle": spec_idle, "run": spec_run, "cast": spec_cast, "hit": spec_hit, "death": spec_death, "dodge": spec_dodge}
for _n in LENGTHS_NEW:
    CLIPS[_n] = make_marks_spec(_n)
ALL_CLIPS = list(rc.CLIP_NAMES) + list(LENGTHS_NEW)   # 앞 여섯은 계약 이름, 뒤는 A7-2에서 늘린 것(계약 밖: 주의로만 나온다)
LOOPING = ("idle", "run")


# ------------------------------------------------------------------ 굽기와 측정

def foot_slide(c, ankles, fps, expect_speed):
    """디딤(발목이 쉬는 높이 근처인 연속 두 프레임) 구간의 앞뒤 속도가 땅 속도와 얼마나 다른가. 반환: 평균/최대(땅 속도 대비)와 디딤 속도 중앙값."""
    out = {}
    rest_z = {s: c.ankle[s].z for s in "lr"}
    for s in "lr":
        diffs, spd = [], []
        for i in range(1, len(ankles)):
            a0, a1 = ankles[i - 1][s], ankles[i][s]
            if a0.z - rest_z[s] < 0.001 * c.H and a1.z - rest_z[s] < 0.001 * c.H:
                v = (a1.y - a0.y) * fps          # +Y = 뒤. 땅 속도로 뒤로 간다
                spd.append(v)
                diffs.append(abs(v - expect_speed))
        if diffs:
            spd_sorted = sorted(spd)
            out[s] = {"stance_frames": len(diffs), "mean_err": sum(diffs) / len(diffs), "max_err": max(diffs),
                      "median_speed": spd_sorted[len(spd_sorted) // 2]}
    return out


def bake_clip(c: Ctx, skin, name, T, fps, cfg, make_spec=None, frames_basis=None, expect_speed=None):
    """한 클립의 모든 프레임을 풀어 (프레임별 기저)와 측정값을 얻는다. frames_basis: 이미 계산된 기저(리타깃)."""
    import numpy as np
    sc = cfg["stretch"]
    n = int(round(T * fps))
    basis_list, ankles = [], []
    lo = hi = tot = 0
    emax = 0.0
    emin = 9.0
    minz = 1e9
    c.overext = 0
    c.reach_max = 0.0
    for i in range(n + 1):
        t = i / fps
        if frames_basis is not None:
            S = frames_basis[i]
        else:
            spec = make_spec(c, t)
            S = c.solve(spec)
            if spec.get("lift_to_ground"):
                mats = skin.matrices(c.rig, S.P)
                zmin = float(skin.deform(mats)[:, 2].min())
                need = cfg["clips"]["ground_clearance"] - zmin
                if need > 0:
                    spec["lift"] = min(need, 0.3 * c.H)
                    S = c.solve(spec)
        basis_list.append(S.basis)
        mats = skin.matrices(c.rig, S.P)
        pos = skin.deform(mats)
        r = skin.stretch(pos)
        lo += int((r < sc["low"]).sum())
        hi += int((r > sc["high"]).sum())
        tot += len(r)
        emax = max(emax, float(r.max()))
        emin = min(emin, float(r.min()))
        minz = min(minz, float(pos[:, 2].min()))
        ankles.append({s: S.P["tarsal_cr_" + s].translation.copy() for s in "lr"})
    expect = expect_speed if expect_speed is not None else (c.stride / 0.6 if name == "run" else 0.0)
    rep = {
        "seconds": n / fps, "frames": n + 1, "fps": fps,
        "edge_outside_ratio": (lo + hi) / max(tot, 1), "edge_too_short": lo / max(tot, 1), "edge_too_long": hi / max(tot, 1),
        "edge_max": emax, "edge_min": emin, "min_z": minz, "leg_overextended_frames": c.overext, "leg_reach_max_ratio": c.reach_max,
        "foot_slide": foot_slide(c, ankles, fps, expect),
        "ground_speed": expect,
    }
    return basis_list, rep


def write_action(arm, rig, name, basis_list, fps):
    import bpy
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad = arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and len(act.slots) == 0:
        pass
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for i, basis in enumerate(basis_list):
        for n, (q, loc) in basis.items():
            pb = arm.pose.bones[n]
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=i, group=n)
            if loc is not None:
                pb.location = loc
                pb.keyframe_insert("location", frame=i, group=n)
    return act


def assign_action(arm, act):
    ad = arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and len(act.slots):
        ad.action_slot = act.slots[0]


def verify_solver(arm, rig, S):
    """내 풀이(P)와 Blender 평가가 같은 자세인지 한 프레임에서 확인(가장 큰 위치 차이, 미터)."""
    import bpy
    bpy.context.view_layer.update()
    worst = 0.0
    for n in rig.order:
        d = (arm.pose.bones[n].matrix.translation - S.P[n].translation).length
        worst = max(worst, d)
    return worst


def make_all(arm, mesh_obj, rig, skin, cfg, out_glb, preview_dir, only=None, retarget=None):
    import bpy
    fps = int(cfg["clips"]["fps"])
    bpy.context.scene.render.fps = fps
    H = float(skin.rest[:, 2].max())
    c = Ctx(rig, H, cfg)
    st = cfg["clips"].get("run_stance_fraction", 0.38)
    gstride = cfg["clips"]["game_hero_stride"]
    report = {"fps": fps, "height": H, "stride_model_m": c.stride, "rest_arm_drop_deg": c.rest_arm_drop, "arm_offset_deg": c.arm_offset, "clips": {},
              "run_cycle": {"cycle_seconds": 0.6, "steps_per_cycle": 2, "stride_game_m": gstride, "stride_model_m": c.stride,
                            "stance_fraction": st, "flight_fraction_per_step": 0.5 - st,
                            "steps_per_second_at_5.8mps": 5.8 / gstride * 2.0, "elem_arm": cfg["clips"].get("elem_arm", "l"),
                            "note": "게임이 위상 = 이동거리 / stride_game_m 로 돌리면 한 걸음 = stride/2. 클립 길이 0.6초는 계약값일 뿐 속도는 위상이 정한다."},
              "cast_timing_s": {"windup_peak": 0.03, "extend_peak": 0.07, "hold_until": 0.12, "return_done": 0.28,
                                "note": "기본기: 이벤트(탄 생성)가 클립 시작이면 뻗음은 4프레임 뒤. 사크라타는 뻗은 뒤 1~2프레임에 탄이므로 게임은 클립을 이벤트 0.03~0.05초 앞에서 시작하는 것을 권한다"}}
    mocap_cfg = cfg["clips"].get("mocap")
    mocap_names = set((mocap_cfg or {}).get("clips", {}))
    for name in ALL_CLIPS:
        if only and name not in only:
            continue
        if name in mocap_names or (mocap_cfg and name in LENGTHS_NEW):
            continue      # 사람 동작으로 바꾸는 클립은 절차식으로 만들지 않는다
        T = cfg["clips"]["lengths"].get(name, LENGTHS_NEW.get(name))
        if retarget and name in retarget:
            basis_list, rep = bake_clip(c, skin, name, T, fps, cfg, frames_basis=retarget[name])
            rep["method"] = "retarget"
        else:
            basis_list, rep = bake_clip(c, skin, name, T, fps, cfg, make_spec=CLIPS[name])
            rep["method"] = "procedural"
        act = write_action(arm, rig, name, basis_list, fps)
        if name == "run" and not retarget:
            fi = len(basis_list) // 3
            S = c.solve(CLIPS["run"](c, fi / fps))
            assign_action(arm, act)
            bpy.context.scene.frame_set(fi)
            report["solver_vs_blender_max_m"] = verify_solver(arm, rig, S)
        report["clips"][name] = rep
    if mocap_cfg:
        import rig_mocap
        def _map(pth):
            mpath = Path(pth)
            if not mpath.is_absolute():
                mpath = Path(__file__).resolve().parents[2] / mpath
            return rc.read_json(mpath)
        srcs = {}   # 이름 -> (원본, 짝 표). 단일 원본(source/map)이거나, 여러 원본(sources: {이름: {type: glb|fbx_dir, path, map, files}})
        if "sources" in mocap_cfg:
            for sn, sd in mocap_cfg["sources"].items():
                if sd.get("type") == "fbx_dir":
                    srcs[sn] = (rig_mocap.FbxSource(sd["path"], sd.get("files"), sd.get("src_fps", 30.0)), _map(sd["map"]))
                else:
                    srcs[sn] = (rig_mocap.Source(sd["path"]), _map(sd["map"]))
        else:
            srcs["default"] = (rig_mocap.Source(mocap_cfg["source"]), _map(mocap_cfg["map"]))
        src, mp = srcs.get("default", (None, None))
        vg = float(mocap_cfg.get("ground_mps_game", 5.8)) * H / cfg["clips"]["game_target_height"]
        report["mocap"] = {"source": str(mocap_cfg.get("source") or mocap_cfg.get("sources")), "ground_mps_model": vg}
        made = {}
        for name, cclip in mocap_cfg["clips"].items():
            if only and name not in only:
                continue
            vgc = float(cclip.get("ground_mps_game", mocap_cfg.get("ground_mps_game", 5.8))) * H / cfg["clips"]["game_target_height"]
            src_c, mp_c = srcs[cclip.get("src", "default")]
            frames, mrep = rig_mocap.retarget_clip(c, skin, src_c, mp_c, name, cclip, fps, vgc)
            T = (len(frames) - 1) / float(fps)
            _bl, rep = bake_clip(c, skin, name, T, fps, cfg, frames_basis=frames, expect_speed=(mrep["ground_mps_model"] if cclip.get("lock") else 0.0))
            rep["method"] = "mocap"
            rep["mocap"] = mrep
            rep["leg_reach_max_ratio"] = mrep["leg_reach_max"]
            rep["leg_overextended_frames"] = mrep["leg_overextended_frames"]
            write_action(arm, rig, name, [S.basis for S in frames], fps)
            made[name] = [S.basis for S in frames]
            report["clips"][name] = rep
        for comp in mocap_cfg.get("composites", []):   # 뼈 무리 섞기 확인용(달리며 시전 등): 아래는 lower 클립, 위는 upper 클립(start초부터)
            bl = compose_blend(made, comp, fps)
            write_action(arm, rig, comp["name"], bl, fps)
            report["clips"][comp["name"]] = {"method": "composite", "seconds": comp["seconds"], "frames": len(bl), "parts": comp}
        for sc_, _mp in srcs.values():
            sc_.cleanup()
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    if preview_dir:
        report["preview"] = preview(arm, mesh_obj, cfg, preview_dir)
    if out_glb:
        # 마지막 클립이 붙어 있는 채로 내보낸다. 모든 동작이 glb에 들어간다.
        rc.export_glb(out_glb, arm, [mesh_obj], fps=fps)
        report["out_glb"] = str(out_glb)
    return report


UPPER_W = {"spine_cr_01": 0.5, "spine_cr_02": 1.0, "spine_cr_03": 1.0, "neck_cr": 1.0, "head_cr": 1.0}


def compose_blend(made, comp, fps):
    """뼈 무리 섞기: 위 뼈(위 척추 100%, 아래 척추 50%, 어깨·팔·손·목·머리 100%)는 upper 클립, 나머지(골반·다리)는 lower 클립. 게임 쪽 상체 덮기와 같은 규칙."""
    lo, up = made[comp["lower"]], made[comp["upper"]]
    n = int(round(comp["seconds"] * fps)) + 1
    t0 = int(round(comp.get("start", 0.0) * fps))
    out = []
    for i in range(n):
        b_lo = lo[i % (len(lo) - 1)]
        j = i - t0
        b_up = up[min(max(j, 0), len(up) - 1)] if j >= 0 else None
        d = dict(b_lo)
        if b_up is not None:
            for name in b_lo:
                w = UPPER_W.get(name)
                if w is None and name.startswith(("shoulder_", "upper_arm_", "forearm_", "hand_", "finger_")):
                    w = 1.0
                if w:
                    q0, l0 = b_lo[name]
                    q1, l1 = b_up[name]
                    d[name] = (q0.slerp(q1, w), l0)
        out.append(d)
    return out


def preview(arm, mesh_obj, cfg, d):
    import bpy
    Path(d).mkdir(parents=True, exist_ok=True)
    fps = cfg["clips"]["fps"]
    out = {}
    for name in rc.CLIP_NAMES:
        act = bpy.data.actions.get(name)
        if act is None:
            continue
        assign_action(arm, act)
        T = cfg["clips"]["lengths"][name]
        fr = [fps * T * k / 5.0 for k in range(6)]
        for view in ("front", "side"):
            out[name + "_" + view] = rc.render_sheet(arm, [mesh_obj], fr, str(Path(d) / (name + "_" + view)), view)
    return out


# ------------------------------------------------------------------ 리타깃(기존 glb의 동작을 새 뼈대로)

def retarget_frames(arm, rig, skin, cfg, src_path, name_map, only=None):
    """원본 glb를 가져와 뼈마다 월드 회전 변화량(쉬는 자세 대비)을 새 뼈대의 쉬는 자세에 얹는다. 골반 이동은 키 비율로 늘린다.
    같은 이름의 뼈만 옮긴다(나머지는 부모를 따름). 반환: {클립: [PoseSolver ...]}  (60fps 등 cfg fps로 표본)"""
    import bpy
    from mathutils import Matrix, Vector
    fps = int(cfg["clips"]["fps"])
    before = set(bpy.data.objects)
    before_act = set(bpy.data.actions)
    rc.import_any(src_path)
    new_objs = [o for o in bpy.data.objects if o not in before]
    src_arm = next((o for o in new_objs if o.type == "ARMATURE"), None)
    if src_arm is None:
        raise SystemExit("원본에 뼈대가 없다")
    src_meshes = [o for o in new_objs if o.type == "MESH" and len(o.data.vertices) > 200]
    zs = []
    for o in src_meshes:
        zs += [(o.matrix_world @ v.co).z for v in o.data.vertices]
    src_h = max(zs) - min(zs) if zs else 1.0
    H = float(skin.rest[:, 2].max())
    k = H / src_h
    Mw = src_arm.matrix_world
    Rw = Mw.to_3x3().normalized()
    mapping = {n: name_map.get(n, n) for n in rig.order}
    src_names = {b.name for b in src_arm.data.bones}
    mapping = {t: s for t, s in mapping.items() if s in src_names}
    src_rest = {s: (Mw @ src_arm.data.bones[s].matrix_local).to_3x3().normalized() for s in mapping.values()}
    src_rest_head = {s: (Mw @ src_arm.data.bones[s].head_local) for s in mapping.values()}
    c = Ctx(rig, H, cfg)
    out = {}
    meta = {"source_height": src_h, "scale": k, "mapped_bones": len(mapping), "unmapped": [n for n in rig.order if n not in mapping]}
    acts = [a for a in bpy.data.actions if a not in before_act]
    for act in acts:
        if act.name not in rc.CLIP_NAMES or (only and act.name not in only):
            continue
        assign_action(src_arm, act)
        T = cfg["clips"]["lengths"][act.name]
        src_T = act.frame_range[1] / fps
        n = int(round(T * fps))
        frames = []
        for i in range(n + 1):
            f = i
            bpy.context.scene.frame_set(f)
            S = rig.solver()
            for b in rig.order:
                if b in mapping:
                    s = mapping[b]
                    pb = src_arm.pose.bones[s]
                    Rp = (Mw @ pb.matrix).to_3x3().normalized()
                    delta = Rp @ src_rest[s].inverted()
                    kw = {"absd": delta @ rig.rest_rot[b]}
                    if b == "pelvis_cr":
                        pp = (Mw @ pb.matrix).translation
                        kw["trans"] = rig.head[b] + (pp - src_rest_head[s]) * k
                    S.place(b, **kw)
                else:
                    S.place(b)
            S.finish()
            frames.append(S)
        out[act.name] = frames
        meta.setdefault("source_seconds", {})[act.name] = src_T
    # 원본 개체와 동작을 지운다(내보내기에 섞이지 않게)
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in acts:
        bpy.data.actions.remove(a)
    for a in list(bpy.data.armatures):
        if a.users == 0:
            bpy.data.armatures.remove(a)
    return out, meta


def main(argv):
    import bpy
    import json
    ap = argparse.ArgumentParser(description="뼈대에 동작 6개를 찍어 glb로 낸다")
    ap.add_argument("--blend", required=True, help="rig_build의 결과 .blend")
    ap.add_argument("--out-glb", required=True)
    ap.add_argument("--out-blend", help="동작이 든 .blend도 저장(rig_parts 입력)")
    ap.add_argument("--config")
    ap.add_argument("--report")
    ap.add_argument("--fps", type=int)
    ap.add_argument("--only", help="쉼표로 나눈 클립 이름만")
    ap.add_argument("--preview", help="이 폴더에 클립마다 6컷 렌더(정면·옆, 작업대 엔진)")
    ap.add_argument("--retarget-from", help="이 glb의 동작을 옮긴다")
    ap.add_argument("--retarget-map", help="{새 뼈: 원본 뼈} JSON")
    a = ap.parse_args(argv)
    cfg = rc.load_config(a.config)
    if a.fps:
        cfg["clips"]["fps"] = a.fps
    bpy.ops.wm.open_mainfile(filepath=a.blend)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next((o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm and o.name == "body"), None) or next(o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm)
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    rig = rc.Rig(arm)
    skin = rc.Skin.from_blender(mesh, rig)
    only = a.only.split(",") if a.only else None
    retarget = None
    meta = None
    if a.retarget_from:
        nm = rc.read_json(a.retarget_map) if a.retarget_map else {}
        retarget, meta = retarget_frames(arm, rig, skin, cfg, a.retarget_from, nm, only)
    rep = make_all(arm, mesh, rig, skin, cfg, a.out_glb, a.preview, only, retarget)
    if meta:
        rep["retarget"] = meta
    if a.out_blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.out_blend, compress=True)
    if a.report:
        rc.write_json(a.report, rep)
    for n, r in rep["clips"].items():
        print("RIG_CLIP", n, r["method"], "%.3fs" % r["seconds"], "edge_out=%.2f%%" % (100 * r["edge_outside_ratio"]),
              "overext=%d" % r["leg_overextended_frames"], "minz=%.3f" % r["min_z"])
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
