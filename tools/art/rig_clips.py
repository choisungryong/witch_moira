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

def spec_idle(c, t):
    T = 1.2
    s, co = math.sin(2 * math.pi * t / T), math.cos(2 * math.pi * t / T)
    H = c.H
    return {
        "pelvis_t": (0.003 * H * s, 0, -0.004 * H * (0.5 + 0.5 * co)),
        "spine": [(0.6 * s, 0.5 * co, 0), (0.8 * s, 0.4 * co, 0), (1.0 * s, 0, 0)],
        "head": (-1.4 * s, 0.4 * co, 0),
        "arms": {"l": (2.0 * s, 1.5 * co, 2.0), "r": (-2.0 * s, -1.5 * co, 2.0)},
    }


def spec_run(c, t):
    T = 0.6
    H = c.H
    ph = (t / T) % 1.0
    st = c.cfg["clips"]["run_stance_fraction"]
    a = c.stride * st / 2.0
    Lt = c.Ltot
    dx = abs(c.hip['l'].x - c.ankle['l'].x)
    drop = Lt - math.sqrt(max((0.90 * Lt) ** 2 - a * a - dx * dx - (0.012 * H) ** 2, 0.0))
    lift_h = 0.18 * Lt
    feet = {}
    for s, off in (("l", 0.0), ("r", 0.5)):
        pl = (ph + off) % 1.0
        if pl < st:
            u = pl / st
            f, dz, pit = a * (1 - 2 * u), 0.0, -12.0 * smooth((u - 0.7) / 0.3) * 0
        else:
            w = (pl - st) / (1 - st)
            f = -a + 2 * a * smooth(w)
            dz = lift_h * math.sin(math.pi * w) ** 1.2
            pit = 22.0 * math.sin(math.pi * w)
        feet[s] = {"d": (0, -f, dz), "pitch": pit}
    yaw = 5.0 * math.cos(2 * math.pi * ph)
    swing = 35.0 * math.cos(2 * math.pi * ph)
    return {
        "pelvis_t": (0.01 * H * math.sin(2 * math.pi * ph), 0, -drop + 0.012 * Lt * (1 + math.cos(4 * math.pi * ph))),
        "pelvis_fk": rc.rot("Z", yaw) @ rc.rot("Y", 2.0 * math.sin(2 * math.pi * ph)),
        "spine": [(3.5, 0, -yaw * 0.4), (3.0, 0, -yaw * 0.5), (2.5, 0, -yaw * 0.6)],
        "head": (-5.0, 0, -yaw * 0.3),
        "arms": {"l": (-swing, -14.0, 80.0), "r": (swing, -14.0, 80.0)},
        "feet": feet,
    }


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


def bake_clip(c: Ctx, skin, name, T, fps, cfg, make_spec=None, frames_basis=None):
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
    expect = c.stride / 0.6 if name == "run" else 0.0
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
    report = {"fps": fps, "height": H, "stride_model_m": c.stride, "rest_arm_drop_deg": c.rest_arm_drop, "arm_offset_deg": c.arm_offset, "clips": {}}
    for name in rc.CLIP_NAMES:
        if only and name not in only:
            continue
        T = cfg["clips"]["lengths"][name]
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
    mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm)
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
