#!/usr/bin/env python3
"""뼈 없는 인간형 메시 한 덩어리에서 뼈대를 세우고 가중치를 입힌다(Blender 5.3 명령줄).

  python tools/art/rig_build.py --in MESH.glb --out-blend D:/.../rigged.blend [--config my.json] [--report report.json] [--clips]
  (Blender 바깥에서 부르면 스스로 `blender --background --python`으로 다시 부른다. 환경변수 BLENDER_EXE로 경로 지정)

하는 일
  1. 메시(glb/obj/fbx)를 가져와 메시만 남기고 한 덩어리로 합친다(뼈대·동작·가중치는 버림). 정면이 -Y여야 한다(config mesh.facing).
  2. 메시 치수(키, 양손 끝, 장화 바닥, 몸통 앞면)와 키 대비 비율로 뼈 24개의 자리를 계산해 세운다. 뼈 이름은 게임이 기대하는 이름.
  3. 가중치: 뼈 선분까지 거리의 역수 제곱 + 메시 변 평활화 + 3차원 공간 평활화. 정점당 최대 4개, 무가중치 0.
     (Blender 자동 가중치는 겹옷 모델에서 실패해 쓰지 않는다. docs/reviews/3D-CHARACTER-PIPELINE-PROOF-20261120.ko.md 3절)
  4. 결과를 .blend로 저장하고 보고서(JSON: 뼈 수, 무가중치, 정점당 영향 수, 측정값)를 쓴다. --clips를 주면 rig_clips까지 이어서 돌린다.
설정(JSON)으로 비율·예외를 준다. 기본값과 키 설명은 tools/art/rig_configs/default.json.

이 도구는 라이선스를 판단하지 않는다. 입력 모델이 CC BY-SA 같은 조건이면 파생물도 그 조건이다.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


# ------------------------------------------------------------------ 순수 계산(numpy만. Blender 없이도 돈다)

def measure(P, cfg):
    """정점 좌표(N,3; 바닥 z=0, 정면 -Y)에서 키·발·손·몸통 중심을 잰다."""
    import numpy as np
    pr = cfg["proportions"]
    H = float(P[:, 2].max())
    out = {"height": H, "vertices": int(len(P))}
    band = P[:, 2] < pr["foot_band"] * H
    feet = {}
    for side, sgn in (("l", 1), ("r", -1)):
        m = band & (sgn * P[:, 0] > 0.01 * H)
        if m.sum() >= 3:
            pts = P[m]
            feet[side] = {"cx": float(pts[:, 0].mean()), "cy": float(pts[:, 1].mean()), "toe_y": float(pts[:, 1].min()),
                          "heel_y": float(pts[:, 1].max()), "n": int(m.sum()), "found": True}
        else:
            feet[side] = {"cx": sgn * 0.05 * H, "cy": 0.0, "toe_y": -0.08 * H, "heel_y": 0.04 * H, "n": 0, "found": False}
    out["feet"] = feet
    hands = {}
    upper = P[:, 2] > 0.35 * H
    k = max(8, int(pr["hand_extreme_fraction"] * len(P)))
    for side, sgn in (("l", 1), ("r", -1)):
        cand = P[upper & (sgn * P[:, 0] > 0)]
        if len(cand) >= k:
            sel = cand[np.argsort(-sgn * cand[:, 0])[:k]]
            hands[side] = {"tip": [float(v) for v in sel.mean(axis=0)], "found": True}
        else:
            hands[side] = {"tip": [sgn * 0.3 * H, 0.0, 0.45 * H], "found": False}
    out["hands"] = hands
    zlo, zhi = pr["pelvis_z"] * H, pr["shoulder_z"] * H
    m = (np.abs(P[:, 0]) < 0.12 * H) & (P[:, 2] > zlo) & (P[:, 2] < zhi)
    front = float(np.percentile(P[m, 1], pr["torso_front_percentile"])) if m.sum() > 20 else float(P[:, 1].min())
    out["torso_front_y"] = front
    out["torso_center_y"] = front + pr["torso_half_depth"] * H
    return out


def bone_positions(m, cfg):
    """측정값과 비율에서 뼈마다 (head, tail) 미터 좌표를 낸다. bone_overrides가 마지막에 덮는다."""
    import numpy as np
    pr = cfg["proportions"]
    H = m["height"]
    yc = m["torso_center_y"]
    V = lambda x, y, z: np.array([x, y, z], dtype=float)
    pz = pr["pelvis_z"] * H
    s = [z * H for z in pr["spine_z"]]
    nt = pr["neck_top_z"] * H
    ht = min(pr["head_top_z"] * H, H)
    pos = {}
    pos["origin"] = (V(0, yc, 0), V(0, yc, 0.1 * H))
    pos["pelvis_cr"] = (V(0, yc, pz), V(0, yc, pz - 0.05 * H))
    pos["spine_cr_01"] = (V(0, yc, pz), V(0, yc, s[0]))
    pos["spine_cr_02"] = (V(0, yc, s[0]), V(0, yc, s[1]))
    pos["spine_cr_03"] = (V(0, yc, s[1]), V(0, yc, s[2]))
    pos["neck_cr"] = (V(0, yc, s[2]), V(0, yc, nt))
    pos["head_cr"] = (V(0, yc, nt), V(0, yc, ht))
    for side, sgn in (("l", 1), ("r", -1)):
        sh = V(sgn * pr["shoulder_x"] * H, yc, pr["shoulder_z"] * H)
        tip = np.array(m["hands"][side]["tip"])
        d = tip - sh
        elbow, wrist = sh + d * pr["elbow_t"], sh + d * pr["wrist_t"]
        pos["shoulder_cr_" + side] = (V(sgn * pr["clavicle_x"] * H, yc, pr["clavicle_z"] * H), sh)
        pos["upper_arm_cr_" + side] = (sh, elbow)
        pos["forearm_cr_" + side] = (elbow, wrist)
        pos["hand_cr_" + side] = (wrist, tip)
        if side == "r":
            fh = wrist + (tip - wrist) * pr["finger_t"]
            pos["finger_middle.01.r"] = (fh, tip + (tip - wrist) * 0.1)
        f = m["feet"][side]
        L = max(f["heel_y"] - f["toe_y"], 0.02 * H)
        ay = f["heel_y"] - pr["foot_ankle_back"] * L
        az = pr["ankle_z"] * H
        ankle = V(f["cx"], ay, az)
        bz = max(0.003, 0.15 * az)
        ball = V(f["cx"], f["toe_y"] + pr["foot_ball_from_toe"] * L, bz)
        toe = V(f["cx"], f["toe_y"], bz * 0.9)
        hip = V(sgn * pr["hip_x_of_foot_x"] * abs(f["cx"]), yc, pr["hip_z"] * H)
        t = (pr["hip_z"] - pr["knee_z"]) / (pr["hip_z"] - pr["ankle_z"])
        knee = hip + (ankle - hip) * t
        knee[2] = pr["knee_z"] * H
        pos["thigh_cr_" + side] = (hip, knee)
        pos["shin_cr_" + side] = (knee, ankle)
        pos["tarsal_cr_" + side] = (ankle, ball)
        pos["toe_cr_" + side] = (ball, toe)
    for n, ov in (cfg.get("bone_overrides") or {}).items():
        if n in pos and isinstance(ov, dict):
            h, t = pos[n]
            pos[n] = (np.array(ov.get("head", h), dtype=float), np.array(ov.get("tail", t), dtype=float))
    return pos


def weight_segments(pos, H, cfg):
    """가중치용 선분. 머리는 메시 꼭대기까지, 골반·척추는 그대로."""
    import numpy as np
    seg = {n: (np.array(h), np.array(t)) for n, (h, t) in pos.items() if n not in rc.NO_WEIGHT_BONES}
    h, t = seg["head_cr"]
    seg["head_cr"] = (h, np.array([t[0], t[1], H]))
    return seg


def seg_distance(P, a, b):
    import numpy as np
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def compute_weights(P, edges, pos, cfg, kd_neighbors):
    """P (N,3), edges (E,2) -> (idx (N,4), w (N,4), bone_names, info). 같은 자리 정점은 같은 가중치를 받는다."""
    import numpy as np
    wc = cfg["weights"]
    H = float(P[:, 2].max())
    key = np.round(P * 1e5).astype(np.int64)
    U, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    Pu = np.zeros((len(U), 3))
    Pu[inv] = P
    seg = weight_segments(pos, H, cfg)
    names = [n for n in rc.BONE_ORDER if n in seg]
    D = np.zeros((len(Pu), len(names)))
    margin = wc["leg_side_margin"] * H
    for j, n in enumerate(names):
        a, b = seg[n]
        d = seg_distance(Pu, a, b)
        r = wc["radius"].get(n, 0.0) * H
        if r:
            d = np.maximum(d - r, 0.0)
        side = 1 if n.endswith("_l") else (-1 if n.endswith("_r") else 0)
        if side and wc["leg_side_penalty"] != 1.0:
            wrong = (-side * Pu[:, 0]) > margin
            d = np.where(wrong, d * wc["leg_side_penalty"], d)
        D[:, j] = d * wc["bias"].get(n, 1.0)
    eps = wc["eps"] * H
    dmin = D.min(axis=1, keepdims=True)
    keep = D <= wc["cutoff"] * dmin + eps
    W = np.where(keep, 1.0 / (D + eps) ** wc["power"], 0.0)
    W /= W.sum(axis=1, keepdims=True)

    # 메시 변 평활화(같은 자리 정점으로 합친 그래프)
    e = inv[edges]
    e = e[e[:, 0] != e[:, 1]]
    e = np.unique(np.sort(e, axis=1), axis=0)
    src = np.concatenate([e[:, 0], e[:, 1]])
    dst = np.concatenate([e[:, 1], e[:, 0]])
    cnt = np.bincount(src, minlength=len(Pu)).astype(float)

    def smooth(W, src, dst, cnt, alpha):
        acc = np.zeros_like(W)
        np.add.at(acc, src, W[dst])
        has = cnt > 0
        out = W.copy()
        out[has] = (1 - alpha) * W[has] + alpha * acc[has] / cnt[has, None]
        return out
    for _ in range(wc["mesh_smooth"]):
        W = smooth(W, src, dst, cnt, wc["mesh_smooth_alpha"])
    # 3차원 공간 평활화(겉옷·안감·망토가 닿는 것끼리 함께 움직이게)
    if wc["space_smooth"] > 0:
        s2, d2 = kd_neighbors(Pu, wc["space_radius"] * H)
        c2 = np.bincount(s2, minlength=len(Pu)).astype(float)
        for _ in range(wc["space_smooth"]):
            W = smooth(W, s2, d2, c2, wc["space_smooth_alpha"])
    # 정점당 최대 4개, 정규화
    order = np.argsort(-W, axis=1)[:, :4]
    top = np.take_along_axis(W, order, axis=1)
    top /= np.maximum(top.sum(axis=1, keepdims=True), 1e-12)
    idx_u, w_u = order, top
    return idx_u[inv], w_u[inv], names, {"unique_positions": int(len(Pu))}


# ------------------------------------------------------------------ Blender 안

def kd_neighbors_blender(Pu, radius):
    import numpy as np
    from mathutils import kdtree
    kd = kdtree.KDTree(len(Pu))
    for i, p in enumerate(Pu):
        kd.insert(p, i)
    kd.balance()
    src, dst = [], []
    for i, p in enumerate(Pu):
        for (_co, j, _d) in kd.find_range(p, radius):
            if j != i:
                src.append(i)
                dst.append(j)
    return np.array(src, dtype=np.int64), np.array(dst, dtype=np.int64)


def make_armature(pos):
    import bpy
    from mathutils import Vector
    data = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = {}
    for n in rc.BONE_ORDER:
        h, t = pos[n]
        eb = data.edit_bones.new(n)
        eb.head = Vector(h)
        eb.tail = Vector(t)
        if (eb.tail - eb.head).length < 1e-3:
            eb.tail = eb.head + Vector((0, 0, 1e-2))
        ebs[n] = eb
    for n in rc.BONE_ORDER:
        p = rc.BONE_PARENT[n]
        if p:
            ebs[n].parent = ebs[p]
            ebs[n].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for n in rc.NO_WEIGHT_BONES:
        data.bones[n].use_deform = False
    return arm


def write_weights(mesh_obj, idx, w, names):
    for n in names:
        mesh_obj.vertex_groups.new(name=n)
    groups = [mesh_obj.vertex_groups[n] for n in names]
    for v in range(len(idx)):
        for k in range(4):
            if w[v, k] > 1e-6:
                groups[idx[v, k]].add([v], float(w[v, k]), "REPLACE")


def attach(mesh_obj, arm):
    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def build(args, cfg):
    import bpy
    import numpy as np
    t0 = time.time()
    rc.reset_scene(cfg["clips"]["fps"])
    rc.import_any(args.input)
    obj = rc.single_mesh_from_import(cfg)
    me = obj.data
    P = rc.mesh_coords(obj)
    mc = cfg["mesh"]
    from mathutils import Matrix, Vector
    shift = Vector((0, 0, 0))
    if mc["ground"]:
        shift.z = -float(P[:, 2].min())
    if mc["target_height"]:
        k = float(mc["target_height"]) / float(P[:, 2].max() - P[:, 2].min())
        me.transform(Matrix.Scale(k, 4))
        P = rc.mesh_coords(obj)
        shift.z = -float(P[:, 2].min()) if mc["ground"] else 0.0
    if mc["center_x"]:
        # 장화 중심의 좌우 한가운데를 x=0으로(발을 못 찾으면 옮기지 않음)
        pre = measure(P + np.array([0, 0, shift.z]), cfg)
        if pre["feet"]["l"]["found"] and pre["feet"]["r"]["found"]:
            shift.x = -0.5 * (pre["feet"]["l"]["cx"] + pre["feet"]["r"]["cx"])
    if shift.length > 0:
        me.transform(Matrix.Translation(shift))
    P = rc.mesh_coords(obj)
    m = measure(P, cfg)
    pos = bone_positions(m, cfg)
    arm = make_armature(pos)
    edges = rc.mesh_edges(obj)
    idx, w, names, info = compute_weights(P, edges, pos, cfg, kd_neighbors_blender)
    write_weights(obj, idx, w, names)
    attach(obj, arm)
    out = Path(args.out_blend)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out), compress=True)
    # 검사: 블렌더 쪽에 쓴 가중치를 다시 읽어 센다
    rig = rc.Rig(arm)
    skin = rc.Skin.from_blender(obj, rig)
    wsum = skin.w.sum(axis=1)
    nz = (skin.w > 1e-6).sum(axis=1)
    report = {
        "tool": "rig_build.py", "blender": bpy.app.version_string,
        "input": str(args.input), "config": args.config or "(기본)", "seconds": round(time.time() - t0, 1),
        "mesh": {"vertices": len(me.vertices), "triangles": rc.triangle_count(obj), "height": m["height"]},
        "measure": {"feet": m["feet"], "hands": m["hands"], "torso_center_y": m["torso_center_y"], "torso_front_y": m["torso_front_y"]},
        "bones": len(rig.order), "deform_bones": len(names), "bone_names": rig.order,
        "weights": {"unweighted_vertices": int((wsum < 1e-6).sum()), "max_influences": int(nz.max()),
                    "max_sum_error": float(abs(wsum - 1).max()), "unique_positions": info["unique_positions"]},
        "out_blend": str(out),
    }
    return report, rig, skin, obj, arm


def main(argv):
    ap = argparse.ArgumentParser(description="뼈 없는 메시에서 뼈대와 가중치를 만든다")
    ap.add_argument("--in", dest="input", required=True, help="메시 glb/obj/fbx")
    ap.add_argument("--out-blend", required=True, help="결과 .blend (큰 파일은 D:/Project/witch-moira-work/ 아래에)")
    ap.add_argument("--config", help="설정 JSON(기본 rig_configs/default.json 위에 덮음)")
    ap.add_argument("--report", help="보고서 JSON 경로")
    ap.add_argument("--clips", action="store_true", help="이어서 rig_clips로 동작 6개를 만들고 glb를 내보낸다")
    ap.add_argument("--out-glb", help="--clips와 함께: 내보낼 glb")
    a = ap.parse_args(argv)
    cfg = rc.load_config(a.config)
    report, rig, skin, obj, arm = build(a, cfg)
    if a.clips:
        import rig_clips
        creport = rig_clips.make_all(arm, obj, rig, skin, cfg, a.out_glb, None)
        report["clips"] = creport
        import bpy
        bpy.ops.wm.save_as_mainfile(filepath=str(a.out_blend), compress=True)
    if a.report:
        rc.write_json(a.report, report)
    print("RIG_BUILD", {k: report[k] for k in ("bones", "deform_bones", "weights")})
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
