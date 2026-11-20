#!/usr/bin/env python3
"""팔 단면 재기(Blender 5.3). 위팔·아래팔·손목 근처의 단면(뼈 축에 수직인 평면에 정점을 내려 2차원 주성분으로 긴 폭·짧은 폭, 볼록 껍질 넓이)을 쉬는 자세와 지정한 동작 프레임에서 잰다.

  python tools/art/arm_section.py --blend X.blend [--gltf 원본.gltf] [--pose run:10] [--side l] [--json out.json]
- 몸 메시는 이름이 body 이거나 Superhero_Female 인 것. 뼈 이름은 우리 이름(upper_arm_cr_l)과 원본 이름(upperarm_l)을 모두 받는다.
- 정점은 마디(위팔·아래팔)의 지배 가중치로 고르고, 마디 길이의 중간 40%에서만 잰다(어깨·팔꿈치 이음 빼고).
- 팔꿈치 이음 넓이: 굽혔을 때 위팔 끝(70~100%)과 아래팔 시작(0~30%)의 단면 넓이 최솟값을 쉬는 자세 값과 비교한다(꺼짐 검사).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402

NAMES = {"upper": ("upper_arm_cr_%s", "upperarm_%s"), "fore": ("forearm_cr_%s", "lowerarm_%s"), "hand": ("hand_cr_%s", "hand_%s"), "clav": ("shoulder_cr_%s", "clavicle_%s")}


def hull_area(pts):
    import numpy as np
    p = sorted(set(map(tuple, np.round(pts, 5))))
    if len(p) < 3:
        return 0.0

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for q in p:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], q) <= 0:
            lo.pop()
        lo.append(q)
    for q in reversed(p):
        while len(up) >= 2 and cross(up[-2], up[-1], q) <= 0:
            up.pop()
        up.append(q)
    h = lo[:-1] + up[:-1]
    return abs(sum(h[i][0] * h[(i + 1) % len(h)][1] - h[(i + 1) % len(h)][0] * h[i][1] for i in range(len(h)))) / 2.0


def section(P, head, tail, lo, hi):
    """P(N,3) 정점 중 뼈 축 위 비율 lo~hi 인 것의 단면: (긴 폭, 짧은 폭, 볼록 껍질 넓이, 개수)."""
    import numpy as np
    ax = tail - head
    L = float(np.linalg.norm(ax))
    ax = ax / L
    t = (P - head) @ ax / L
    sel = P[(t >= lo) & (t <= hi)]
    if len(sel) < 6:
        return None
    ref = np.array([0, 1.0, 0]) if abs(ax[1]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(ax, ref)
    u /= np.linalg.norm(u)
    v = np.cross(ax, u)
    q = np.stack([(sel - head) @ u, (sel - head) @ v], 1)
    q = q - q.mean(0)
    w, vec = np.linalg.eigh(np.cov(q.T))
    pr = q @ vec
    ext = pr.max(0) - pr.min(0)
    return {"major": float(ext[1]), "minor": float(ext[0]), "area": hull_area(q), "n": int(len(sel)), "len": L}


def find_bone(arm, key, side):
    for n in NAMES[key]:
        b = arm.data.bones.get(n % side)
        if b is not None:
            return b
    return None


def measure(arm, body, side, deformed):
    import numpy as np
    import bpy
    dg = bpy.context.evaluated_depsgraph_get()
    if deformed:
        me = body.evaluated_get(dg).to_mesh()
        P = np.array([body.matrix_world @ v.co for v in me.vertices])
    else:
        P = np.array([body.matrix_world @ v.co for v in body.data.vertices])
    gname = {g.index: g.name for g in body.vertex_groups}
    dom = []
    for v in body.data.vertices:
        dom.append(gname[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else "")
    dom = np.array(dom)
    out = {}
    for key in ("upper", "fore", "hand"):
        b = find_bone(arm, key, side)
        if b is None:
            continue
        sel = P[dom == b.name]
        if deformed:
            pb = arm.pose.bones[b.name]
            head = np.array(arm.matrix_world @ pb.head)
            tail = np.array(arm.matrix_world @ pb.tail)
        else:
            head, tail = np.array(arm.matrix_world @ b.head_local), np.array(arm.matrix_world @ b.tail_local)
        out[key] = {"mid": section(sel, head, tail, 0.3, 0.7), "end": section(sel, head, tail, 0.7, 1.0), "start": section(sel, head, tail, 0.0, 0.3)}
        out[key]["bone"] = b.name
    return out


def main(argv):
    import bpy
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend")
    ap.add_argument("--gltf")
    ap.add_argument("--pose", action="append", help="동작:프레임 (여러 번)")
    ap.add_argument("--side", default="l")
    ap.add_argument("--json")
    a = ap.parse_args(argv)
    if a.blend:
        bpy.ops.wm.open_mainfile(filepath=a.blend)
    else:
        rc.reset_scene(60)
        bpy.ops.import_scene.gltf(filepath=a.gltf)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH" and o.name in ("body", "Superhero_Female"))
    res = {"rest": measure(arm, body, a.side, False)}
    for p in a.pose or []:
        name, fr = p.split(":")
        act = bpy.data.actions.get(name)
        ad = arm.animation_data_create()
        ad.action = act
        if hasattr(ad, "action_slot") and len(act.slots):
            ad.action_slot = act.slots[0]
        bpy.context.scene.frame_set(int(fr))
        res[p] = measure(arm, body, a.side, True)
    for k, v in res.items():
        print("ARMSEC", k)
        for key, d in v.items():
            for part in ("start", "mid", "end"):
                s = d[part]
                if s:
                    print("ARMSEC   %-5s %-5s major %.3f minor %.3f ratio %.2f area %.5f n %d" % (key, part, s["major"], s["minor"], s["minor"] / max(s["major"], 1e-9), s["area"], s["n"]))
    if a.json:
        Path(a.json).write_text(json.dumps(res), encoding="utf-8")
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
