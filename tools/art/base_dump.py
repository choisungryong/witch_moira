#!/usr/bin/env python3
"""기본 몸을 쉬는 자세(T자)와 A자세 두 벌 좌표로 덤프한다(Blender 5.3). 그림 투영은 A자세에서 하고(원화가 A자세), 뼈대·동작은 T자 쉬는 자세 그대로 쓴다.

  python tools/art/base_dump.py --body body.gltf --out dump.npz [--arm-angle 38] [--mesh Superhero_Female]
npz: rest (N,3), apose (N,3), tris (M,3), uv (M,3,2: 삼각형 모서리 uv, 첫 uv 층), group (N: 정점이 가장 크게 묶인 뼈 이름), bones_head/bones_tail (이름 -> 좌표는 json 문자열)
팔은 위팔 뼈를 어깨 관절을 축으로 arm-angle도 아래로 돌려 A자세를 만든다(아래팔·손은 위팔을 따라간다).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def main(argv):
    import bpy
    import numpy as np
    from mathutils import Matrix
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--arm-angle", type=float, default=38.0)
    ap.add_argument("--mesh", default="Superhero_Female")
    ap.add_argument("--hair", help="머리카락 glTF(Origin at 0 판): 메시를 같이 덤프한다")
    a = ap.parse_args(argv)
    rc.reset_scene(60)
    bpy.ops.import_scene.gltf(filepath=a.body)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = bpy.data.objects[a.mesh]
    eyes_z = float("nan")
    if "Eyes" in bpy.data.objects:
        ez = [(bpy.data.objects["Eyes"].matrix_world @ v.co).z for v in bpy.data.objects["Eyes"].data.vertices]
        eyes_z = float(sum(ez) / len(ez))
    me = mesh.data
    n = len(me.vertices)
    rest = np.array([(mesh.matrix_world @ v.co)[:] for v in me.vertices])
    gname = {vg.index: vg.name for vg in mesh.vertex_groups}
    dom = []
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight) if v.groups else None
        dom.append(gname[best.group] if best else "")
    me.calc_loop_triangles()
    tris = np.array([t.vertices[:] for t in me.loop_triangles], np.int64)
    uvl = me.uv_layers[0]
    uv = np.array([[uvl.data[l].uv[:] for l in t.loops] for t in me.loop_triangles], np.float64)
    heads = {b.name: list(b.head_local) for b in arm.data.bones}
    tails = {b.name: list(b.tail_local) for b in arm.data.bones}
    # A자세
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    th = math.radians(a.arm_angle)
    for side, sg in (("l", 1.0), ("r", -1.0)):
        pb = arm.pose.bones["upperarm_" + side]
        R = Matrix.Rotation(sg * th, 4, "Y")
        head = pb.bone.head_local.copy()
        M = Matrix.Translation(head) @ R @ Matrix.Translation(-head) @ pb.bone.matrix_local
        pb.matrix = M
        bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    em = ev.to_mesh()
    apose = np.array([(ev.matrix_world @ v.co)[:] for v in em.vertices])
    ev.to_mesh_clear()
    extra = {}
    if a.hair:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=a.hair)
        hm = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
        hme = hm.data
        hme.calc_loop_triangles()
        extra = dict(hair_rest=np.array([(hm.matrix_world @ v.co)[:] for v in hme.vertices]),
                     hair_tris=np.array([t.vertices[:] for t in hme.loop_triangles], np.int64),
                     hair_uv=np.array([[hme.uv_layers[0].data[l].uv[:] for l in t.loops] for t in hme.loop_triangles], np.float64))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(a.out, eyes_z=eyes_z, **extra, rest=rest, apose=apose, tris=tris, uv=uv, group=np.array(dom), bones_head=json.dumps(heads), bones_tail=json.dumps(tails))
    print("BASE_DUMP verts %d tris %d uv_layer %s arm_shift_max %.3f" % (n, len(tris), uvl.name, float(np.abs(apose - rest).max())))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
