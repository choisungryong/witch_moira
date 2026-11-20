#!/usr/bin/env python3
"""사람 동작(다른 뼈대의 glb 동작)을 우리 24뼈 뼈대로 옮긴다. rig_clips.py가 부른다(Blender 5.3 안에서). 순수 계산 부분(디딤 구간 찾기, 디딤 고정)은 Blender 없이 검사된다.

옮기는 법(설정 `clips.mocap`, 짝 표 `rig_configs/mocap_ual.json`)
  몸통·머리 : 뼈마다 원본의 월드 회전 변화량(쉬는 자세 대비)을 우리 쉬는 자세에 얹는다(방향이 거의 같은 뼈).
  팔·어깨·손·발 : 방향 기준. 원본 뼈 머리->꼬리(또는 다음 뼈 머리) 월드 방향을 우리 뼈 방향으로 준다(쉬는 자세가 T자와 A자로 다른 것을 흡수).
  골반 이동 : 원본 쉬는 자세 대비 이동을 다리 길이 비(k)로 늘린다.
  다리 : 두 뼈 IK. 발목 목표 = 우리 골반 + k * (원본 발목 - 원본 골반). 무릎 방향은 원본 무릎이 있는 쪽.
  발 디딤 고정(lock) : 발목이 낮은 연속 프레임을 디딤으로 보고, 그 동안 발목 앞뒤를 땅 속도 v_g로 정확히 뒤로 흘린다(미끄러짐 0). 뜨는 동안은 양 끝의 어긋남을 부드럽게 나눠 이어 붙인다.
  바닥 맞춤 : 클립 전체에 상수 높이 하나를 더해 가장 낮은 정점이 바닥(+여유)에 놓이게 한다(걷기·서기는 위아래도 맞춤, 구르기·사망은 올리기만).
원본 종류: Source(glb 한 파일, 여러 동작) / FbxSource(Mixamo식 FBX 폴더, 파일 하나 = 동작 하나, 월드 좌표·앞 방향 -Y로 맞춤). rig_clips의 mocap.sources로 둘을 섞어 쓴다.
클립 설정 추가 항목: seconds=null(원본 길이) / "auto"(자연 박자에서 게임 속도 발 미끄러짐 0이 되는 배속, scale_range 안일 때만), range_s=[시작,끝](원본 구간만),
  k_mode="leg"(다리 길이 비), ik_hip=true(발목 목표를 우리 엉덩 관절 기준으로: 관절 위치가 다른 뼈대에서 다리가 과하게 펴지는 것을 막음).
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


class FbxSource:
    """Mixamo식 FBX 폴더(파일 하나 = 동작 하나, 뼈대 이름 'mixamorig:Hips')를 읽어 Source와 같은 모양으로 표본한다.
    월드 좌표(뼈대 물체의 크기 0.01·회전 90도를 반영)로 바꾸고, 발->발끝 방향이 -Y(우리 앞)가 되게 Z축 회전 F를 한 번 곱한다.
    동작 이름 = 파일 이름(확장자 뺀 것). 프레임률은 src_fps(FBX는 30)."""

    def __init__(self, directory, files=None, src_fps=30.0, prefix="mixamorig:"):
        import bpy
        from pathlib import Path as _P
        from mathutils import Matrix
        self.src_fps = float(src_fps)
        self.prefix = prefix
        fps_keep = bpy.context.scene.render.fps
        self.objs, self.arms, self.actions = [], {}, {}
        paths = sorted(_P(directory).glob("*.fbx")) if not files else [_P(directory) / f for f in files]
        for p in paths:
            before, before_act = set(bpy.data.objects), set(bpy.data.actions)
            bpy.ops.import_scene.fbx(filepath=str(p))
            new = [o for o in bpy.data.objects if o not in before]
            arm = next(o for o in new if o.type == "ARMATURE")
            act = next(a for a in bpy.data.actions if a not in before_act)
            act.name = p.stem
            ad = arm.animation_data_create()
            ad.action = act
            if hasattr(ad, "action_slot") and len(act.slots):
                ad.action_slot = act.slots[0]
            self.objs += new
            self.arms[p.stem] = arm
            self.actions[p.stem] = act
        bpy.context.scene.render.fps = fps_keep
        first = next(iter(self.arms.values()))
        Mw3 = first.matrix_world.to_3x3().normalized()
        h = lambda n: first.matrix_world @ first.data.bones[prefix + n].head_local
        fwd = h("LeftToeBase") - h("LeftFoot")
        ang = math.atan2(fwd.y, fwd.x)
        target = math.atan2(-1.0, 0.0)
        self.F = Matrix.Rotation(target - ang, 3, "Z")
        self.rest_rot = {self._n(b.name): (self.F @ Mw3 @ b.matrix_local.to_3x3()).normalized() for b in first.data.bones}
        self.rest_head = {self._n(b.name): self.F @ (first.matrix_world @ b.head_local) for b in first.data.bones}

    def _n(self, name):
        return name[len(self.prefix):] if name.startswith(self.prefix) else name

    def length_frames(self, name):
        f0, f1 = self.actions[name].frame_range
        return f1 - f0

    def seconds(self, name):
        return self.length_frames(name) / self.src_fps

    def pose(self, name, frame):
        import bpy
        arm, act = self.arms[name], self.actions[name]
        f = act.frame_range[0] + frame
        fi = int(math.floor(f))
        bpy.context.scene.frame_set(fi, subframe=f - fi)
        Mw, Mw3 = arm.matrix_world, arm.matrix_world.to_3x3().normalized()
        out = {}
        for pb in arm.pose.bones:
            out[self._n(pb.name)] = (self.F @ (Mw @ pb.head), self.F @ (Mw @ pb.tail), (self.F @ Mw3 @ pb.matrix.to_3x3()).normalized())
        return out

    def cleanup(self):
        import bpy
        for o in self.objs:
            try:
                bpy.data.objects.remove(o, do_unlink=True)
            except ReferenceError:
                pass
        for a in list(self.actions.values()):
            try:
                bpy.data.actions.remove(a)
            except ReferenceError:
                pass


def end_point(P, spec):
    """spec = 'bone' 또는 'bone:head' / 'bone:tail' -> 원본 뼈의 머리·꼬리 위치."""
    name, _, which = spec.partition(":")
    h, t, _r = P[name]
    return t if which == "tail" else h


def measure_natural(src, mp, act, L, src_T, k, loop, cfg_clip):
    """원본 걷기·달리기의 자연 박자: 디딤 동안 발목이 골반 대비 뒤로 흐르는 평균 속도(우리 크기 m/s)와 한 주기의 이동 거리, 걸음 수."""
    nfr = int(round(L))
    legs = mp["legs"]
    fr = [src.pose(act, float(i)) for i in range(nfr + 1)]
    dt = src_T / L
    pel = np.array([f[mp["pelvis"][1]][0] for f in fr])
    out = {"source_seconds": src_T, "frames": nfr}
    vs, steps = [], 0
    for s in "lr":
        a = np.array([f[legs[s]["ankle"]][0] for f in fr])
        z = a[:, 2]
        cyc = z[:-1] if loop else z
        mask = detect_stance(cyc, float(cfg_clip.get("stance_thresh", 0.035)))
        segs = stance_segments(mask)
        steps += len(segs)
        rel_y = (a[:, 1] - pel[:, 1])
        for seg in segs:
            ids, ln = _idx(seg, len(cyc))
            for u_, w_ in zip(ids, ids[1:]):
                vs.append(abs(rel_y[w_] - rel_y[u_]) / dt)
    v_src = float(np.mean(vs)) if vs else 0.0
    out["v_nat_src_mps"] = v_src
    out["v_nat_model"] = v_src * k
    out["steps_per_cycle"] = steps
    out["stride_per_cycle_src_m"] = v_src * src_T
    return out


def retarget_clip(c, skin, src, mp, name, cfg_clip, fps, ground_mps_model, sink_clear=0.002, log=print):
    """한 클립을 만든다. 반환: (PoseSolver 목록(n+1), 보고 dict). c = rig_clips.Ctx."""
    import rig_common as rc
    V = c.V
    rig = c.rig
    act = cfg_clip["action"]
    loop = cfg_clip.get("loop", False)
    L = src.length_frames(act)
    import bpy
    src_T = src.seconds(act) if hasattr(src, "seconds") else L / float(bpy.context.scene.render.fps)   # glb 동작의 프레임은 장면 프레임률(60), FBX는 원본 프레임률
    off = 0.0
    if cfg_clip.get("range_s"):      # 원본의 한 구간만 쓴다(초). 긴 시전·피격에서 필요한 부분만 잘라 낸다
        r0, r1 = cfg_clip["range_s"]
        off = r0 / src_T * L
        L = (r1 - r0) / src_T * L
        src_T = r1 - r0
    k = float(cfg_clip.get("k_override", 0.0)) or (rig.head["thigh_cr_l"].z / src.rest_head[mp["legs"]["l"]["hip"]].z)
    if cfg_clip.get("k_mode") == "leg":     # 다리 길이(엉덩->무릎->발목) 비. 기본은 엉덩이 높이 비(발목이 낮은 원본은 다리 길이가 더 짧아 비가 달라진다)
        lg_ = mp["legs"]["l"]
        rh_ = src.rest_head
        k = c.Ltot / float((rh_[lg_["knee"]] - rh_[lg_["hip"]]).length + (rh_[lg_["ankle"]] - rh_[lg_["knee"]]).length)
    auto = None
    gmps = ground_mps_model
    if str(cfg_clip["seconds"]) == "auto":     # 원본의 자연 박자로 두되, 게임 속도에서 발이 안 미끄러지는 배속이 범위 안이면 그 배속을 쓴다
        auto = measure_natural(src, mp, act, L, src_T, k, loop, cfg_clip)
        s_need = ground_mps_model / auto["v_nat_model"]
        lo_, hi_ = cfg_clip.get("scale_range", [0.85, 1.25])
        auto["scale_needed"] = s_need
        auto["applied"] = bool(lo_ <= s_need <= hi_)
        T = src_T / s_need if auto["applied"] else src_T
        gmps = ground_mps_model if auto["applied"] else auto["v_nat_model"]
        auto["seconds_used"] = T
    else:
        T = float(cfg_clip["seconds"]) if cfg_clip.get("seconds") is not None else src_T
    ground_mps_model = gmps
    n = int(round(T * fps))
    lean = float(cfg_clip.get("lean_scale", 1.0))
    hold_after = float(cfg_clip.get("hold_seconds", 0.0))        # 끝에 마지막 자세를 붙들어 길이를 채울 때(원본이 계약 길이보다 짧은 시전 등)
    n_act = int(round(min(T, T - hold_after) * fps)) if hold_after else n
    frames_src = []
    for i in range(n + 1):
        if hold_after and i > n_act:
            frames_src.append(frames_src[-1])
            continue
        u = i / float(n_act if hold_after else n)
        frames_src.append(src.pose(act, off + min(u, 1.0) * L))
    P0 = src.pose(act, off)
    nf = len(frames_src)
    pel_src = mp["pelvis"][1]
    rest_pel = src.rest_head[pel_src]
    # 다리 발목·골반 원본 궤적
    legs = mp["legs"]
    traj = {s: {"ankle": np.array([f[legs[s]["ankle"]][0] for f in frames_src]), "knee": np.array([f[legs[s]["knee"]][0] for f in frames_src]), "hip": np.array([f[legs[s]["hip"]][0] for f in frames_src])} for s in "lr"}
    pelv = np.array([f[pel_src][0] for f in frames_src])
    dt = 1.0 / fps
    lock = bool(cfg_clip.get("lock", False))
    rel = {s: (traj[s]["ankle"] - pelv) * k for s in "lr"}            # 골반 대비 발목(우리 크기)
    ay = {s: rel[s][:, 1].copy() for s in "lr"}
    ik_hip = bool(cfg_clip.get("ik_hip", False))    # 발목 목표를 골반이 아니라 우리 엉덩 관절 기준(원본 엉덩 관절 대비 발목 x k)으로 준다: 관절 위치가 다른 뼈대에서 다리가 과하게 펴지는 것을 막는다
    dl = {s: np.zeros(len(pelv)) for s in "lr"}
    if ik_hip:
        rel = {s: (traj[s]["ankle"] - traj[s]["hip"]) * k for s in "lr"}
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
            dl[s][: len(cyc)] = newy - world_y
            if loop:
                dl[s][-1] = dl[s][0]
            segs_info[s] = [(int(a), int(b)) for a, b in segs]
    from mathutils import Matrix
    tp = float(cfg_clip.get("trunk_pitch_deg", 0.0))      # 윗몸 전체에 더할 앞기울임(도). 척추 셋에 1/3씩 쌓고 어깨는 전부
    pitch_w = {"spine_cr_01": tp / 3, "spine_cr_02": 2 * tp / 3, "spine_cr_03": tp, "shoulder_cr_l": tp, "shoulder_cr_r": tp} if tp else {}

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
                if tgt in pitch_w:   # 윗몸 앞기울임 덧붙이기(머리는 원본 그대로라 시선은 그대로): 월드 X축 회전, +가 앞(-Y)으로 숙임
                    Rd = Matrix.Rotation(math.radians(pitch_w[tgt]), 3, "X") @ Rd
                S.place(tgt, absd=Rd @ rig.rest_rot[tgt])
            for tgt, (a, b) in mp["dir"].items():
                if tgt.startswith(("thigh", "shin", "tarsal", "toe")):
                    continue
                d = V(tuple(end_point(P, b) - end_point(P, a)))
                hold = (cfg_clip.get("hold") or {}).get(tgt[-1])
                if hold and d.length > 1e-6:   # 지팡이 쥔 팔: 원본 방향을 고정 자세 방향 쪽으로 k만큼 끌어당긴다(달릴 때 흔들림을 줄이고 손목을 세움)
                    key = "upper" if tgt.startswith("upper_arm") else ("fore" if tgt.startswith("forearm") else "hand")
                    hd = V(tuple(hold[key]))
                    kk = float(hold.get("k_" + key, hold["k"]))   # 마디별 세기(k_upper·k_fore·k_hand)가 있으면 그것을 쓴다: 달리기에서 팔 흔들림은 살리고 손목만 쥔 꼴로 세운다
                    d = (d.normalized() * (1 - kk) + hd.normalized() * kk).normalized()
                if d.length < 1e-6:
                    S.place(tgt)
                    continue
                S.place(tgt, absd=rc.delta_between(rig.rest_dir[tgt], d) @ rig.rest_rot[tgt])
            hands = {**rc.DEFAULT_HANDS, **(cfg_clip.get("hands") or {})}   # 손 모양: 지팡이 쥔 오른손 grip, 왼손 relaxed(클립 설정 hands로 덮음)
            for s_ in "lr":
                rc.place_hand(S, rig, s_, hands[s_])
            for s in "lr":
                lg = legs[s]
                hip = S.head_pos("thigh_cr_" + s)
                a_rel = rel[s][i].copy()
                if ik_hip:
                    a_rel[1] += dl[s][i]
                    tgt_w = hip + V(tuple(a_rel))
                    kn_w = hip + V(tuple((traj[s]["knee"][i] - traj[s]["hip"][i]) * k))
                else:
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
        keys_src = list(mp["dump_src"]) if mp.get("dump_src") else ["pelvis", "spine_03", "Head", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
        keys_our = ["pelvis_cr", "spine_cr_03", "head_cr", "upper_arm_cr_l", "forearm_cr_l", "hand_cr_l", "upper_arm_cr_r", "forearm_cr_r", "hand_cr_r", "thigh_cr_l", "shin_cr_l", "tarsal_cr_l", "toe_cr_l", "thigh_cr_r", "shin_cr_r", "tarsal_cr_r", "toe_cr_r"]
        alias = mp["dump_src"] if mp.get("dump_src") else {k_: k_ for k_ in keys_src}   # 별칭(막대 그림이 쓰는 이름) -> 원본 뼈
        dump = {"src": [{a_: [round(float(x), 4) for x in f[b_][0]] for a_, b_ in alias.items()} for f in frames_src],
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
           "ground_shift_m": shift, "stance_segments": segs_info, "ground_mps_model": ground_mps_model if lock else None, "auto": auto,
           "stance_slide_max_mps": slide, "leg_reach_max": max(reach) if reach else 0.0, "leg_overextended_frames": int(sum(1 for r_ in reach if r_ > 1.001))}
    return frames, rep
