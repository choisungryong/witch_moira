#!/usr/bin/env python3
"""팔다리 점검(Blender 안): 키 대비 비율, 관절(팔꿈치·무릎)에서 가중치가 섞이는 폭, 팔다리 굵기를 잰다. 보고서 JSON과 표를 낸다.

  python tools/art/limb_audit.py --blend rigged.blend --out audit.json [--side l]
읽는 것: rig_build의 결과(.blend, 뼈대와 몸 메시 `body`). 모든 값은 모델의 계산이다.
  proportions : 키 H(메시 최대 z), 위팔·아래팔·손 길이와 팔 전체(어깨 관절~손 뼈 끝), 허벅지·종아리·발목 높이, 모두 H 비율
  blend_width : 관절 양쪽 뼈 사이에서 가중치가 0.1 -> 0.9로 넘어가는 뼈 축 방향 폭(m)과 짧은 쪽 뼈 길이 대비 비율. 작을수록 한 점에서 꺾인다
  radii       : 뼈 축에서 정점까지의 평균 거리(굵기 반지름, cm)를 뼈를 따라 몇 곳에서
사람 보통값(Drillis-Contini 비례): 팔 전체 0.44 H(위팔 0.186, 아래팔 0.146, 손 0.108), 다리(엉덩이 관절~바닥) 0.53 H(허벅지 0.245, 종아리 0.246).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402

HUMAN = {"arm_total": 0.44, "upper_arm": 0.186, "forearm": 0.146, "hand": 0.108, "leg_hip_to_floor": 0.53, "thigh": 0.245, "calf": 0.246}


def main(argv):
    import bpy
    import numpy as np
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=a.blend)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm and o.name == "body")
    rig = rc.Rig(arm)
    skin = rc.Skin.from_blender(mesh, rig)
    H = float(skin.rest[:, 2].max())
    res = {"H": H, "proportions": {}, "blend_width": {}, "radii": {}}
    side = "l"
    up, fo, hd = "upper_arm_cr_" + side, "forearm_cr_" + side, "hand_cr_" + side
    L = lambda n: float(rig.length[n])
    pr = res["proportions"]
    pr["upper_arm"] = L(up) / H
    pr["forearm"] = L(fo) / H
    pr["hand"] = L(hd) / H
    pr["arm_total"] = (L(up) + L(fo) + L(hd)) / H
    th, sh, ta = "thigh_cr_" + side, "shin_cr_" + side, "tarsal_cr_" + side
    pr["thigh"] = L(th) / H
    pr["calf"] = L(sh) / H
    pr["leg_hip_to_floor"] = float(rig.head[th].z) / H
    pr["hip_to_ankle"] = (L(th) + L(sh)) / H
    pr["torso_pelvis_to_neck"] = float(rig.head["neck_cr"].z - rig.head["pelvis_cr"].z) / H
    pr["human_ref"] = HUMAN
    V = skin.rest
    names = skin.bones
    bi = {n: i for i, n in enumerate(names)}

    def weight_of(bone):
        w = np.zeros(len(V))
        i = bi.get(bone)
        if i is None:
            return w
        for k in range(4):
            w += np.where(skin.idx[:, k] == i, skin.w[:, k], 0.0)
        return w

    def blend(b0, b1, label):
        w0, w1 = weight_of(b0), weight_of(b1)
        sel = (w0 + w1) > 0.98
        joint = rig.head[b1]
        d0 = (rig.tail[b0] - rig.head[b0]).normalized()
        d1 = (rig.tail[b1] - rig.head[b1]).normalized()
        pts = V[sel] - np.array(joint)
        # 관절점에서 두 뼈 방향의 이등분 축으로 투영한 거리 t(양수 = b1 쪽)
        axis = np.array((d0 + d1).normalized())
        t = pts @ axis
        wf = w1[sel]
        lo = t[wf < 0.1]
        hi = t[wf > 0.9]
        tlo = float(lo.max()) if len(lo) else float("nan")
        thi = float(hi.min()) if len(hi) else float("nan")
        width = thi - tlo
        shorter = min(rig.length[b0], rig.length[b1])
        res["blend_width"][label] = {"t_below_0.1": tlo, "t_above_0.9": thi, "width_m": width, "width_vs_shorter_bone": float(width / shorter), "vertices": int(sel.sum())}

    blend(up, fo, "elbow_" + side)
    blend(fo, hd, "wrist_" + side)
    blend(th, sh, "knee_" + side)
    blend(sh, ta, "ankle_" + side)
    # 굵기: 뼈를 따라 위치 s(0..1)에서 그 뼈 가중치 0.9 이상인 정점의 축까지 평균 거리
    def radius(bone, fracs):
        w = weight_of(bone)
        h, t = np.array(rig.head[bone]), np.array(rig.tail[bone])
        d = (t - h) / np.linalg.norm(t - h)
        ln = float(np.linalg.norm(t - h))
        out = {}
        for f in fracs:
            c = h + d * ln * f
            sel = (w > 0.9) & (np.abs((V - h) @ d - ln * f) < 0.015)
            if sel.sum() >= 3:
                pts = V[sel] - c
                perp = pts - np.outer(pts @ d, d)
                out["%.2f" % f] = float(np.linalg.norm(perp, axis=1).mean() * 100.0)
        return out
    for b in (up, fo, hd, th, sh, ta):
        res["radii"][b] = radius(b, (0.1, 0.3, 0.5, 0.7, 0.9))
    # 사슬을 따라 가중치 프로필: 사슬 위치 s(0=처음 뼈 머리, 1=마지막 뼈 꼬리)를 10칸으로 나눠 칸마다 뼈별 평균 가중치(그 칸에서 해당 사슬 뼈 가중치 합이 0.9 넘는 정점만)
    def profile(chain, label):
        pts = [np.array(rig.head[chain[0]])] + [np.array(rig.tail[b]) for b in chain]
        seg = [np.linalg.norm(pts[i + 1] - pts[i]) for i in range(len(chain))]
        tot = sum(seg)
        ws = np.stack([weight_of(b) for b in chain])
        sel = ws.sum(0) > 0.9
        # 각 정점을 사슬(꺾인 선)에 투영해 s를 얻는다
        s_all = np.zeros(len(V))
        best = np.full(len(V), 1e9)
        acc = 0.0
        for i in range(len(chain)):
            d = (pts[i + 1] - pts[i]) / max(seg[i], 1e-9)
            tt = np.clip((V - pts[i]) @ d, 0, seg[i])
            dist = np.linalg.norm(V - (pts[i] + np.outer(tt, d)), axis=1)
            upd = dist < best
            best = np.where(upd, dist, best)
            s_all = np.where(upd, (acc + tt) / tot, s_all)
            acc += seg[i]
        sel &= best < 0.12
        out = []
        for k in range(10):
            m = sel & (s_all >= k / 10.0) & (s_all < (k + 1) / 10.0)
            out.append([round(float(ws[j][m].mean()), 2) if m.sum() else None for j in range(len(chain))])
        res.setdefault("profile", {})[label] = {"bones": chain, "bin_lengths_m": [round(float(x), 3) for x in seg], "bins": out}
    profile([up, fo, hd], "arm_" + side)
    profile([th, sh, ta], "leg_" + side)
    rc.write_json(a.out, res)
    pr_ = res["proportions"]
    print("LIMB_AUDIT H=%.3f arm_total=%.3f (human %.2f) upper=%.3f fore=%.3f hand=%.3f | leg hip->floor=%.3f (human %.2f) thigh=%.3f calf=%.3f" % (
        H, pr_["arm_total"], HUMAN["arm_total"], pr_["upper_arm"], pr_["forearm"], pr_["hand"], pr_["leg_hip_to_floor"], HUMAN["leg_hip_to_floor"], pr_["thigh"], pr_["calf"]))
    for lab, pf in res["profile"].items():
        print("LIMB_PROFILE", lab, pf["bones"], pf["bin_lengths_m"])
        for k, row in enumerate(pf["bins"]):
            print("   s %.1f-%.1f %s" % (k / 10.0, (k + 1) / 10.0, row))
    for k, v in res["blend_width"].items():
        print("LIMB_BLEND %s width %.3f m (%.0f%% of shorter bone)" % (k, v["width_m"], 100 * v["width_vs_shorter_bone"]))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
