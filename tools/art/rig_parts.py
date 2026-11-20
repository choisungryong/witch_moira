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
  kind: "ellipsoid"(기본) 또는 part_shapes.py의 모양("fur_collar" 털 목도리, "pauldron" 어깨 갑옷, "side_panel" 허리 자락 판, "hem_tube" 판 아랫단 테).
        모양 변수는 "params"(미터, 키 2.0 m 기준), "smooth": true면 부드러운 음영. 위치는 뼈 머리 + (꼬리-머리)*at + offset*키.
  --check-clips run,idle,cast: 각 동작 프레임에서 부품 정점이 몸 메시 안으로 들어간 깊이를 잰다(보고서 penetration). 쉬는 자세에서 이미 겹친 만큼은 뺀다.
  at: 뼈 머리에서 꼬리까지의 비율 위치. radius·offset: 키(H) 대비 비율(뼈대 공간, 정면 -Y). source가 있으면 그 메시를 가져와 한 덩어리로 합친다.

묶는 방식: 부품 정점 전부가 그 뼈 하나에 가중치 1(뼈에 단단히 붙음). 몸 위에 맞춰 늘어지는 옷은 이 방식으로 안 된다(달릴 때 밑 옷과 어긋남. 실증 문서 6.2절).
재질: 부품마다 8x8 단색 텍스처 재질을 입힌다. 게임의 재질 처리가 모든 메시의 albedo_color를 덮어쓰므로 질감이 없으면 색이 사라진다.
"""
from __future__ import annotations

import argparse
import math
import sys

import numpy as np
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402
import part_shapes  # noqa: E402
import part_textures  # noqa: E402


def mesh_from_arrays(name, verts, tris, smooth=False, uv=None):
    import bpy
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in verts], [], [tuple(int(i) for i in t) for t in tris])
    me.update()
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        me.update()
    if uv is not None:   # 정점별 uv(v=0이 위) -> 모서리별. Blender uv는 v가 위로 커지므로 뒤집는다
        uvl = me.uv_layers.new(name="UVMap")
        loops = np.array([l.vertex_index for l in me.loops])
        arr = np.asarray(uv, np.float32)[loops].copy()
        arr[:, 1] = 1.0 - arr[:, 1]
        uvl.data.foreach_set("uv", arr.reshape(-1))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def textured_material(name, spec):
    """part_textures의 무늬를 64x64 이미지로 올려 재질에 건다(이미지 이름 = 재질 이름 + _tex, 부품 이름이 마녀별로 유일해야 한다)."""
    import bpy
    arr = part_textures.make(spec, 64)
    img = bpy.data.images.new(name + "_tex", 64, 64, alpha=True)
    px = np.ones((64, 64, 4), np.float32)
    px[..., :3] = arr[::-1]                      # Blender 이미지는 아래 행이 먼저
    img.pixels = px.reshape(-1).tolist()
    img.pack()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    return mat


def penetration_report(arm, body, parts, clip_names, step=3, margin=0.004, max_depth=0.05):
    """부품 정점이 몸 메시 안(법선 뒤쪽)으로 들어간 깊이(m). 쉬는 자세 값은 따로 적고, 동작 값에서 빼서 판단한다.
    반환 {부품: {"rest_max", "rest_count", "clips": {동작: {"max", "count_over", "worst_frame"}}}}. count_over는 margin(기본 4mm)보다 깊은 정점 수의 프레임 최대.
    max_depth(기본 5cm)보다 먼 값은 버린다: 몸 메시는 겹친 관들이라 먼 곳에서 '가장 가까운 면의 법선 뒤쪽' 판정이 거짓으로 나온다(어깨 갑옷이 목 쪽 면에 14cm로 잡힌 것을 확인)."""
    import bpy
    from mathutils.bvhtree import BVHTree
    sc = bpy.context.scene
    ad = arm.animation_data_create()

    def set_action(act):
        ad.action = act
        if hasattr(ad, "action_slot") and len(act.slots):
            ad.action_slot = act.slots[0]

    def depths(frame):
        sc.frame_set(frame)
        dg = bpy.context.evaluated_depsgraph_get()
        bev = body.evaluated_get(dg)
        bvh = BVHTree.FromObject(body, dg)
        res = {}
        for p in parts:
            pev = p.evaluated_get(dg)
            me = pev.to_mesh()
            mw = pev.matrix_world
            worst, cnt = 0.0, 0
            for v in me.vertices:
                co = mw @ v.co
                hit = bvh.find_nearest(co)
                if hit[0] is None:
                    continue
                d = hit[3]
                inside = (co - hit[0]).dot(hit[1]) < 0
                if inside and d <= max_depth:
                    worst = max(worst, d)
                    if d > margin:
                        cnt += 1
            pev.to_mesh_clear()
            res[p.name] = (worst, cnt)
        return res
    rep = {p.name: {"clips": {}} for p in parts}
    first = bpy.data.actions.get(clip_names[0]) if clip_names else None
    if first is not None:
        set_action(first)
    r0 = depths(0)
    for p in parts:
        rep[p.name]["rest_max"], rep[p.name]["rest_count"] = r0[p.name]
    for cn in clip_names:
        act = bpy.data.actions.get(cn)
        if act is None:
            continue
        set_action(act)
        last = int(act.frame_range[1])
        best = {p.name: (0.0, 0, 0) for p in parts}
        for f in range(0, last + 1, step):
            r = depths(f)
            for p in parts:
                w, c = r[p.name]
                if w > best[p.name][0]:
                    best[p.name] = (w, c, f)
        for p in parts:
            rep[p.name]["clips"][cn] = {"max": best[p.name][0], "count_over": best[p.name][1], "worst_frame": best[p.name][2]}
    return rep


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
        elif spec.get("kind") in part_shapes.SHAPES:
            c = rig.head[b] + (rig.tail[b] - rig.head[b]) * spec.get("at", 0.0) + off
            v, t, uv = part_shapes.build_uv(spec["kind"], spec.get("params", {}), scale=H / 2.0, mirror=sx < 0)
            obj = mesh_from_arrays(name + "_" + b, v + np.array([c.x, c.y, c.z]), t, spec.get("smooth", False), uv)
        else:
            c = rig.head[b] + (rig.tail[b] - rig.head[b]) * spec.get("at", 0.0) + off
            rad = [x * H for x in spec.get("radius", (0.04, 0.04, 0.04))]
            obj = make_ellipsoid(name + "_" + b, c, rad)
        pieces.append((obj, b))
    mat = textured_material(name + "_mat", spec["texture"]) if spec.get("texture") else rc.solid_texture_material(name + "_mat", rc.hex_rgba(color))
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
    ap.add_argument("--check-clips", default="", help="쉼표로 이은 동작 이름: 부품이 몸을 뚫는지 잰다(느림: 부품 정점 x 프레임 수)")
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
    if a.check_clips:
        rep["penetration"] = penetration_report(arm, body[0], added, [c for c in a.check_clips.split(",") if c])
    if a.out_blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.out_blend, compress=True)
    if a.report:
        rc.write_json(a.report, rep)
    print("RIG_PARTS", {"parts": [p["name"] for p in rep["parts"]], "triangles": rep["total_triangles"]})
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
