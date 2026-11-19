#!/usr/bin/env python3
"""같은 뼈대에 별도 메시(뼈에 단단히 붙는 소품)를 묶어 한 glb로 내보낸다(Blender 5.3 명령줄).

  python tools/art/rig_parts.py --blend WITH_CLIPS.blend --parts parts.json --out-glb OUT.glb [--report r.json] [--out-blend x.blend]
  (rig_clips.py --out-blend 로 만든 .blend가 입력이다. 동작은 그대로 glb에 같이 나간다)

parts.json (예는 tools/art/rig_configs/parts_demo.json)
  {"parts": [
     {"name": "acc_pauldrons", "bone": "upper_arm_cr_l", "mirror_bone": "upper_arm_cr_r",   # mirror_bone이 있으면 x를 뒤집은 짝도 만든다(같은 메시 노드에 합침)
      "kind": "ellipsoid", "at": 0.12, "radius": [0.045, 0.05, 0.025], "offset": [0, 0, 0], "color": "#8a6a3a"},
     {"name": "acc_head", "bone": "head_cr", "source": "hat.glb", "scale": 1.0, "offset": [0, 0, 0.9], "rotate_deg": [0, 0, 0], "color": "#444444"}
  ]}
  at: 뼈 머리에서 꼬리까지의 비율 위치. radius·offset: 키(H) 대비 비율(뼈대 공간, 정면 -Y). source가 있으면 그 메시를 가져와 한 덩어리로 합친다.

묶는 방식: 부품 정점 전부가 그 뼈 하나에 가중치 1(뼈에 단단히 붙음). 몸 위에 맞춰 늘어지는 옷은 이 방식으로 안 된다(달릴 때 밑 옷과 어긋남. 실증 문서 6.2절).
재질: 부품마다 8x8 단색 텍스처 재질을 입힌다. 게임의 재질 처리가 모든 메시의 albedo_color를 덮어쓰므로 질감이 없으면 색이 사라진다.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def make_ellipsoid(name, center, radius, seg=16, rings=8):
    import bmesh
    import bpy
    from mathutils import Matrix, Vector
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(radius), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def import_part_mesh(path, name, min_vertices=0):
    """부품 메시 파일을 가져와 새로 생긴 메시만 한 덩어리로(월드 좌표를 구워) 합친다."""
    import bpy
    before = set(bpy.data.objects)
    rc.import_any(path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH" and len(o.data.vertices) >= min_vertices]
    if not meshes:
        raise SystemExit("부품 파일에 메시가 없다: " + path)
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in new:
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.name = name
    return obj


def bind_rigid(obj, arm, bone, mat):
    import bpy
    obj.vertex_groups.clear()
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    for m in list(obj.modifiers):
        obj.modifiers.remove(m)
    obj.parent = arm
    obj.matrix_parent_inverse.identity()
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def add_part(spec, arm, rig, H):
    import bpy
    from mathutils import Matrix, Vector
    name, bone = spec["name"], spec["bone"]
    color = spec.get("color", "#808080")
    pieces = []
    sides = [(bone, 1)]
    if spec.get("mirror_bone"):
        sides.append((spec["mirror_bone"], -1))
    for b, sx in sides:
        if b not in rig.head:
            raise SystemExit("뼈가 없다: " + b)
        off = Vector(spec.get("offset", (0, 0, 0))) * H
        off.x *= sx
        if spec.get("source"):
            obj = import_part_mesh(spec["source"], name + "_" + b)
            me = obj.data
            me.transform(Matrix.Scale(spec.get("scale", 1.0), 4))
            r = spec.get("rotate_deg", (0, 0, 0))
            from math import radians
            from mathutils import Euler
            me.transform(Euler((radians(r[0]), radians(r[1]), radians(r[2]))).to_matrix().to_4x4())
            if sx < 0:
                me.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
                me.flip_normals()
            me.transform(Matrix.Translation(rig.head[b] + off))
        else:
            c = rig.head[b] + (rig.tail[b] - rig.head[b]) * spec.get("at", 0.0) + off
            rad = [x * H for x in spec.get("radius", (0.04, 0.04, 0.04))]
            obj = make_ellipsoid(name + "_" + b, c, rad)
        pieces.append((obj, b))
    mat = rc.solid_texture_material(name + "_mat", rc.hex_rgba(color))
    for obj, b in pieces:
        bind_rigid(obj, arm, b, mat)
    objs = [o for o, _ in pieces]
    if len(objs) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()          # 두 쪽의 정점 그룹(뼈 이름)이 한 메시 노드에 합쳐진다
    out = bpy.context.view_layer.objects.active if len(objs) > 1 else objs[0]
    out.name = name
    out.data.name = name
    return out


def main(argv):
    import bpy
    ap = argparse.ArgumentParser(description="같은 뼈대에 소품 메시를 묶어 한 glb로")
    ap.add_argument("--blend", required=True)
    ap.add_argument("--parts", required=True)
    ap.add_argument("--out-glb", required=True)
    ap.add_argument("--out-blend")
    ap.add_argument("--report")
    ap.add_argument("--fps", type=int, default=60)
    a = ap.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=a.blend)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]
    rig = rc.Rig(arm)
    H = max(v.co.z for o in body for v in o.data.vertices)
    spec = rc.read_json(a.parts)
    added = []
    for p in spec["parts"]:
        added.append(add_part(p, arm, rig, H))
    meshes = body + added
    rc.export_glb(a.out_glb, arm, meshes, fps=a.fps)
    rep = {"tool": "rig_parts.py", "out_glb": a.out_glb, "body_meshes": [o.name for o in body],
           "parts": [{"name": o.name, "triangles": rc.triangle_count(o), "vertices": len(o.data.vertices),
                      "bones": sorted({vg.name for vg in o.vertex_groups}), "material": o.data.materials[0].name if o.data.materials else None}
                     for o in added],
           "total_triangles": sum(rc.triangle_count(o) for o in meshes), "actions": [x.name for x in bpy.data.actions]}
    if a.out_blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.out_blend, compress=True)
    if a.report:
        rc.write_json(a.report, rep)
    print("RIG_PARTS", {"parts": [p["name"] for p in rep["parts"]], "triangles": rep["total_triangles"]})
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
