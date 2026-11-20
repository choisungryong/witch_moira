#!/usr/bin/env python3
"""사람 동작(다른 뼈대의 glb 동작)을 우리 24뼈 뼈대로 옮긴다. rig_clips.py가 부른다(Blender 5.3 안에서). 순수 계산 부분(디딤 구간 찾기, 디딤 고정)은 Blender 없이 검사된다.

옮기는 법(설정 `clips.mocap`, 짝 표 `rig_configs/mocap_ual.json`)
  몸통·머리 : 뼈마다 원본의 월드 회전 변화량(쉬는 자세 대비)을 우리 쉬는 자세에 얹는다(방향이 거의 같은 뼈).
  팔·어깨·손·발 : 방향 기준. 원본 뼈 머리->꼬리(또는 다음 뼈 머리) 월드 방향을 우리 뼈 방향으로 준다(쉬는 자세가 T자와 A자로 다른 것을 흡수).
  골반 이동 : 원본 쉬는 자세 대비 이동을 다리 길이 비(k)로 늘린다.
  다리 : 두 뼈 IK. 발목 목표 = 우리 골반 + k * (원본 발목 - 원본 골반). 무릎 방향은 원본 무릎이 있는 쪽.
  발 디딤 고정(lock) : 발목이 낮은 연속 프레임을 디딤으로 보고, 그 동안 발목 앞뒤를 땅 속도 v_g로 정확히 뒤로 흘린다(미끄러짐 0). 뜨는 동안은 양 끝의 어긋남을 부드럽게 나눠 이어 붙인다.
  바닥 맞춤 : 클립 전체에 상수 높이 하나를 더해 가장 낮은 정점이 바닥(+여유)에 놓이게 한다(걷기·서기는 위아래도 맞춤, 구르기·사망은 올리기만).
손가락 등 우리 뼈대에 없는 뼈는 버린다. 원본이 CC0여도 출처·라이선스는 원장에 적는다.
"""
from __future__ import annotations

import math

import numpy as np


# ------------------------------------------------------------------ 순수 계산(Blender 없음)

def detect_stance(z, thresh):
    """발목 높이 z(순환 배열)에서 바닥 근처(최저 + thresh 이하)인 프레임. 반환: bool 배열."""
    z = np.asarray(z, float)
    return z <= z.min() + thresh


def stance_segments(mask):
    """순환 bool 배열의 참 구간 목록 [(시작, 끝 포함)]; 끝이 시작보다 작을 수 있다(0을 넘어 이어짐). 전부 참이거나 전부 거짓이면 빈 목록."""
    n = len(mask)
    if mask.all() or not mask.any():
        return []
    start0 = int(np.argmin(mask))            # 첫 거짓 위치에서 시작해 한 바퀴
    segs, cur = [], None
    for k in range(n):
        i = (start0 + k) % n
        if mask[i] and cur is None:
            cur = i
        if cur is not None and (not mask[i]):
            segs.append((cur, (i - 1) % n))
            cur = None
    if cur is not None:
        segs.append((cur, (start0 - 1) % n))
    return segs


def _idx(seg, n):
    a, b = seg
    ln = (b - a) % n + 1
    return [(a + k) % n for k in range(ln)], ln


def lock_foot(y, mask, dt, v_g):
    """발목 앞뒤(y, +가 뒤) 배열을 디딤 동안 속도 v_g의 직선으로 바꾼다. 뜨는 동안은 양 끝 보정량을 부드럽게 이어 붙인다. 새 배열과 구간 목록을 돌려준다."""
    y = np.asarray(y, float).copy()
    n = len(y)
    segs = stance_segments(mask)
    if not segs:
        return y, segs
    shift = np.zeros(n)
    ends = []
    for seg in segs:
        ids, ln = _idx(seg, n)
        t = (np.arange(ln) - (ln - 1) / 2.0) * dt
        c = float(np.mean(y[ids]))
        new = c + v_g * t
        shift[ids] = new - y[ids]
        ends.append((ids[0], ids[-1], new[0] - y[ids[0]], new[-1] - y[ids[-1]]))
    # 뜨는 동안: 앞 구간 끝 보정 -> 다음 구간 시작 보정으로 이음
    m = len(segs)
    for k in range(m):
        a_end = ends[k][1]
        b_start = ends[(k + 1) % m][0]
        d0, d1 = ends[k][3], ends[(k + 1) % m][2]
        gap = (b_start - a_end) % n
        if gap <= 1:
            continue
        for j in range(1, gap):
            u = j / gap
            e = u * u * (3 - 2 * u)
            shift[(a_end + j) % n] = d0 + (d1 - d0) * e
    return y + shift, segs


def slide_error(y, mask, dt, v_g):
    """디딤 동안 (발 이동 속도 - v_g)의 최대 절댓값(m/s). 고정이 잘 됐는지 보는 자체 검사."""
    n = len(y)
    worst = 0.0
    for seg in stance_segments(mask):
        ids, ln = _idx(seg, n)
        for a, b in zip(ids, ids[1:]):
            worst = max(worst, abs((y[b] - y[a]) / dt - v_g))
    return worst


# ------------------------------------------------------------------ Blender 쪽

def _scaled(R, f):
    """3x3 회전 R의 회전 각도를 f배로(단위 회전에서 구면 보간)."""
    if abs(f - 1.0) < 1e-6:
        return R
    from mathutils import Quaternion
    return Quaternion().slerp(R.to_quaternion(), f).to_matrix()


class Source:
    """원본 glb를 가져와 동작 이름으로 자세를 표본한다."""

    def __init__(self, path):
        import bpy
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(path))
        new = [o for o in bpy.data.objects if o not in before]
        self.arm = next(o for o in new if o.type == "ARMATURE")
        self.objs = new
        self.rest_rot = {b.name: b.matrix_local.to_3x3().normalized() for b in self.arm.data.bones}
        self.rest_head = {b.name: b.head_local.copy() for b in self.arm.data.bones}
        self.actions = {a.name: a for a in bpy.data.actions}

    def length_frames(self, name):
        return self.actions[name].frame_range[1]

    def pose(self, name, frame):
        import bpy
        act = self.actions[name]
        ad = self.arm.animation_data_create()
        ad.action = act
        if hasattr(ad, "action_slot") and len(act.slots):
            ad.action_slot = act.slots[0]
        f = int(math.floor(frame))
        bpy.context.scene.frame_set(f, subframe=frame - f)
        out = {}
        for pb in self.arm.pose.bones:
            out[pb.name] = (pb.head.copy(), pb.tail.copy(), pb.matrix.to_3x3().normalized())
        return out

    def cleanup(self):
        import bpy
        for o in self.objs:
            bpy.data.objects.remove(o, do_unlink=True)
        for a in list(self.actions.values()):
            bpy.data.actions.remove(a)


def end_point(P, spec):
    """spec = 'bone' 또는 'bone:head' / 'bone:tail' -> 원본 뼈의 머리·꼬리 위치."""
    name, _, which = spec.partition(":")
    h, t, _r = P[name]
    return t if which == "tail" else h


def retarget_clip(c, skin, src, mp, name, cfg_clip, fps, ground_mps_model, sink_clear=0.002, log=print):
    """한 클립을 만든다. 반환: (PoseSolver 목록(n+1), 보고 dict). c = rig_clips.Ctx."""
    import rig_common as rc
    V = c.V
    rig = c.rig
    act = cfg_clip["action"]
    T = float(cfg_clip["seconds"])
    loop = cfg_clip.get("loop", False)
    L = src.length_frames(act)
    n = int(round(T * fps))
    lean = float(cfg_clip.get("lean_scale", 1.0))
    hold_after = float(cfg_clip.get("hold_seconds", 0.0))        # 끝에 마지막 자세를 붙들어 길이를 채울 때(원본이 계약 길이보다 짧은 시전 등)
    import bpy
    src_T = L / float(bpy.context.scene.render.fps)   # 가져온 동작의 프레임은 장면 프레임률(60) 기준
    n_act = int(round(min(T, T - hold_after) * fps)) if hold_after else n
    k = float(cfg_clip.get("k_override", 0.0)) or (rig.head["thigh_cr_l"].z / src.rest_head[mp["legs"]["l"]["hip"]].z)
    frames_src = []
    for i in range(n + 1):
        if hold_after and i > n_act:
            frames_src.append(frames_src[-1])
            continue
        u = i / float(n_act if hold_after else n)
        frames_src.append(src.pose(act, min(u, 1.0) * L))
    P0 = src.pose(act, 0.0)
    nf = len(frames_src)
    pel_src = mp["pelvis"][1]
    rest_pel = src.rest_head[pel_src]
    # 다리 발목·골반 원본 궤적
    legs = mp["legs"]
    traj = {s: {"ankle": np.array([f[legs[s]["ankle"]][0] for f in frames_src]), "knee": np.array([f[legs[s]["knee"]][0] for f in frames_src])} for s in "lr"}
    pelv = np.array([f[pel_src][0] for f in frames_src])
    dt = 1.0 / fps
    lock = bool(cfg_clip.get("lock", False))
    rel = {s: (traj[s]["ankle"] - pelv) * k for s in "lr"}            # 골반 대비 발목(우리 크기)
    ay = {s: rel[s][:, 1].copy() for s in "lr"}
    segs_info = {}
    if lock:
        thr = float(cfg_clip.get("stance_thresh", 0.035))
        for s in "lr":
            z = traj[s]["ankle"][:, 2]
            cyc = z[:-1] if loop else z
            mask = detect_stance(cyc, thr)
            # 골반이 앞뒤로 흔들리는 만큼은 발이 땅에 있으려면 보정해야 하므로 세계 좌표(골반 포함)에서 고정한다
            world_y = ay[s][: len(cyc)] + (pelv[: len(cyc), 1] - rest_pel.y) * k
            newy, segs = lock_foot(world_y, mask, dt, ground_mps_model)
            ay[s][: len(cyc)] = newy - (pelv[: len(cyc), 1] - rest_pel.y) * k
            if loop:
                ay[s][-1] = ay[s][0]
            segs_info[s] = [(int(a), int(b)) for a, b in segs]
    def build(shift):
        out = []
        for i in range(nf):
            P = frames_src[i]
            S = rig.solver()
            c.frame_reach = 0.0
            S.place("origin")
            dp = (pelv[i] - rest_pel) * k
            pel_world = rig.head["pelvis_cr"] + V(tuple(dp)) + V((0, 0, shift))
            R_p = _scaled(P[pel_src][2] @ src.rest_rot[pel_src].inverted(), lean)
            S.place("pelvis_cr", absd=R_p @ rig.rest_rot["pelvis_cr"], trans=pel_world)
            for tgt, sname in mp["rot"].items():
                Rd = P[sname][2] @ src.rest_rot[sname].inverted()
                S.place(tgt, absd=Rd @ rig.rest_rot[tgt])
            for tgt, (a, b) in mp["dir"].items():
                if tgt.startswith(("thigh", "shin", "tarsal", "toe")):
                    continue
                d = V(tuple(end_point(P, b) - end_point(P, a)))
                if d.length < 1e-6:
                    S.place(tgt)
                    continue
                S.place(tgt, absd=rc.delta_between(rig.rest_dir[tgt], d) @ rig.rest_rot[tgt])
            S.place("finger_middle.01.r")
            for s in "lr":
                lg = legs[s]
                hip = S.head_pos("thigh_cr_" + s)
                a_rel = rel[s][i].copy()
                a_rel[1] = ay[s][i]
                tgt_w = pel_world + V(tuple(a_rel))
                knee_rel = (traj[s]["knee"][i] - pelv[i]) * k
                kn_w = pel_world + V(tuple(knee_rel))
                line = (tgt_w - hip)
                line_n = line.normalized() if line.length > 1e-6 else V((0, 0, -1))
                pole = (kn_w - hip) - line_n * (kn_w - hip).dot(line_n)
                if pole.length < 1e-4:
                    pole = V((0, -1, 0))
                knee, ankle = c.leg_ik(s, hip, tgt_w, tuple(pole.normalized()))
                Dt = rc.delta_between(rig.rest_dir["thigh_cr_" + s], knee - hip)
                Ds = rc.delta_between(rig.rest_dir["shin_cr_" + s], ankle - knee)
                S.place("thigh_cr_" + s, absd=Dt @ rig.rest_rot["thigh_cr_" + s])
                S.place("shin_cr_" + s, absd=Ds @ rig.rest_rot["shin_cr_" + s])
                for tgt_b, key in (("tarsal_cr_" + s, "foot"), ("toe_cr_" + s, "ball")):
                    a_n, b_n = mp["foot_dirs"][s][key]
                    d = V(tuple(end_point(P, b_n) - end_point(P, a_n)))
                    S.place(tgt_b, absd=rc.delta_between(rig.rest_dir[tgt_b], d) @ rig.rest_rot[tgt_b])
            S.finish()
            reach.append(c.frame_reach)
            out.append(S)
        return out

    reach = []

    frames = build(0.0)
    minz = min(float(skin.deform(skin.matrices(rig, S.P))[:, 2].min()) for S in frames)
    shift = sink_clear - minz
    mode = cfg_clip.get("ground", "both")
    if mode == "lift":
        shift = max(0.0, shift)
    if abs(shift) > 1e-6:
        reach.clear()
        frames = build(shift)
    if cfg_clip.get("dump"):   # 원본과 우리 뼈대의 관절 위치를 프레임마다 적는다(막대 그림 비교용, tools/art/limb_stick.py)
        import json as _json
        keys_src = ["pelvis", "spine_03", "Head", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
        keys_our = ["pelvis_cr", "spine_cr_03", "head_cr", "upper_arm_cr_l", "forearm_cr_l", "hand_cr_l", "upper_arm_cr_r", "forearm_cr_r", "hand_cr_r", "thigh_cr_l", "shin_cr_l", "tarsal_cr_l", "toe_cr_l", "thigh_cr_r", "shin_cr_r", "tarsal_cr_r", "toe_cr_r"]
        dump = {"src": [{k: [round(float(x), 4) for x in f[k][0]] for k in keys_src} for f in frames_src],
                "ours": [{k: [round(float(x), 4) for x in F.P[k].translation] for k in keys_our} for F in frames],
                }
        Path_ = __import__("pathlib").Path
        Path_(cfg_clip["dump"]).write_text(_json.dumps(dump), encoding="utf-8")
    # 디딤 미끄러짐: 디딤 구간 안 연속 프레임의 발목 앞뒤 속도와 땅 속도의 차(m/s, 우리 크기). 고정을 켠 클립만
    slide = None
    if lock:
        slide = 0.0
        for s_, segs in segs_info.items():
            ys = [float(F.P["tarsal_cr_" + s_].translation.y) for F in frames]
            for a_, b_ in segs:
                ids, ln = _idx((a_, b_), len(frames) - 1 if loop else len(frames))
                for u_, w_ in zip(ids, ids[1:]):
                    slide = max(slide, abs((ys[w_] - ys[u_]) / dt - ground_mps_model))
    rep = {"source_action": act, "source_seconds": src_T, "clip_seconds": T, "k_leg": k, "speed_factor": src_T / T if not hold_after else src_T / (T - hold_after),
           "ground_shift_m": shift, "stance_segments": segs_info, "ground_mps_model": ground_mps_model if lock else None,
           "stance_slide_max_mps": slide, "leg_reach_max": max(reach) if reach else 0.0, "leg_overextended_frames": int(sum(1 for r_ in reach if r_ > 1.001))}
    return frames, rep
