#!/usr/bin/env python3
"""맞춘 기본 몸 + 구운 그림 + 부품(치마, 머리) + 사람 동작을 한 개의 리깅된 glb로 묶는다(Blender 5.3). base_dump -> base_bake 다음 걸음.

  python tools/art/base_build.py --config tools/art/base_configs/frost_build.json --out-blend X.blend --out-glb Y.glb
하는 일
  - 몸 메시 좌표와 뼈 위치를 body_fit.npz(맞춤 결과)로 바꾼다(눈·머리카락은 머리 뼈 기준 닮음 변환).
  - 몸 재질의 색 텍스처를 구운 albedo.png로 바꾸고 노멀·거칠기 맵은 버린다.
  - 치마: 실루엣 방식 모델의 치마 부위(mesh.npz의 skirt*)를 가져와 가장 가까운 몸 정점의 가중치를 복사한다(자기 uv·알베도 그대로).
  - 머리카락: 묶음의 머리 모양을 머리 뼈 하나에 묶고, 색은 은백으로 칠한다.
  - 동작: 동작 묶음(UAL)의 동작을 시간만 늘여 새 이름(run, idle, cast, hit, death, dodge ...)으로 굽는다. 원본 뼈 이름으로 표본한 뒤 우리 뼈 이름 규칙으로 바꾼다.
  - 뼈 이름: 24뼈는 우리 이름(pelvis_cr ...), 손가락은 finger_<이름>.NN.<쪽>, 엄지는 thumb.NN.<쪽>, 나머지(root 등)는 그대로.
설정 json(키): body, hair, fit(npz), albedo, skirt_mesh_npz, skirt_albedo, actions, clips(목록), name_map(선택). 내려받은 원본은 읽기만 한다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402

OUR = {"root": "origin", "pelvis": "pelvis_cr", "spine_01": "spine_cr_01", "spine_02": "spine_cr_02", "spine_03": "spine_cr_03", "neck_01": "neck_cr", "Head": "head_cr",
       "clavicle_l": "shoulder_cr_l", "clavicle_r": "shoulder_cr_r", "upperarm_l": "upper_arm_cr_l", "upperarm_r": "upper_arm_cr_r",
       "lowerarm_l": "forearm_cr_l", "lowerarm_r": "forearm_cr_r", "hand_l": "hand_cr_l", "hand_r": "hand_cr_r",
       "thigh_l": "thigh_cr_l", "thigh_r": "thigh_cr_r", "calf_l": "shin_cr_l", "calf_r": "shin_cr_r", "foot_l": "tarsal_cr_l", "foot_r": "tarsal_cr_r",
       "ball_l": "toe_cr_l", "ball_r": "toe_cr_r", "ball_leaf_l": "toe_end_cr_l", "ball_leaf_r": "toe_end_cr_r"}


def our_name(n):
    """원본(UAL/UBC) 뼈 이름 -> 우리 규칙 이름."""
    if n in OUR:
        return OUR[n]
    for f in ("index", "middle", "ring", "pinky"):
        if n.startswith(f + "_"):
            parts = n.split("_")            # index_01_l, index_04_leaf_l
            num = parts[1]
            tail = ".%s.%s" % (num + ("_leaf" if "leaf" in parts else ""), parts[-1])
            return "finger_%s%s" % (f, tail)
    if n.startswith("thumb_"):
        parts = n.split("_")
        return "thumb.%s%s.%s" % (parts[1], "_leaf" if "leaf" in parts else "", parts[-1])
    return n


def main(argv):
    import bpy
    import numpy as np
    from mathutils import Vector, kdtree
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--out-blend", required=True)
    ap.add_argument("--out-glb")
    a = ap.parse_args(argv)
    cfg = json.loads(Path(a.config).read_text(encoding="utf-8"))
    rc.reset_scene(60)
    bpy.ops.import_scene.gltf(filepath=cfg["body"])
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in [o for o in bpy.data.objects if o.type == "MESH" and len(o.vertex_groups) == 0]:
        bpy.data.objects.remove(o, do_unlink=True)
    body = bpy.data.objects["Superhero_Female"]
    eyes = bpy.data.objects.get("Eyes")
    brows = bpy.data.objects.get("Eyebrows")
    if brows is not None:
        bpy.data.objects.remove(brows, do_unlink=True)
    if cfg.get("drop_eyes") and eyes is not None:   # 원화 얼굴 그림에 눈이 그려져 있어 눈알 메시(갈색)를 쓰지 않는다
        bpy.data.objects.remove(eyes, do_unlink=True)
        eyes = None
    fit = np.load(cfg["fit"], allow_pickle=False)
    bnames = [str(x) for x in fit["bones"]]
    # 1) 몸 메시와 뼈 위치
    head0 = np.array(arm.data.bones["Head"].head_local)
    tail0 = np.array(arm.data.bones["Head"].tail_local)
    rest_fit = fit["rest_fit"]
    orig = np.array([v.co[:] for v in body.data.vertices])
    disp = rest_fit - orig
    kd0 = kdtree.KDTree(len(orig))
    for i, c0 in enumerate(orig):
        kd0.insert(Vector(c0), i)
    kd0.balance()

    def follow(co):
        """몸 메시가 맞춤으로 움직인 만큼 가까운 정점 4개의 평균으로 따라간다(눈·머리카락처럼 몸 위에 얹힌 메시용)."""
        near = kd0.find_n(Vector(co), 4)
        w = np.array([1.0 / (d + 1e-3) for (_, _, d) in near])
        dd = sum(disp[i] * wi for (_, i, _), wi in zip(near, w)) / w.sum()
        return Vector(np.array(co) + dd)
    for i, v in enumerate(body.data.vertices):
        v.co = Vector(rest_fit[i])
    idx = {n: i for i, n in enumerate(bnames)}
    h_fit, t_fit = fit["bones_head"], fit["bones_tail"]
    s_head = float(np.linalg.norm(t_fit[idx["Head"]] - h_fit[idx["Head"]]) / np.linalg.norm(tail0 - head0))

    def head_affine(co):
        return Vector(h_fit[idx["Head"]] + (np.array(co) - head0) * s_head)
    if eyes is not None:
        for v in eyes.data.vertices:
            v.co = follow(v.co)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for b in eb:
        b.use_connect = False
    for b in eb:
        b.head = Vector(h_fit[idx[b.name]])
        b.tail = Vector(t_fit[idx[b.name]])
    bpy.ops.object.mode_set(mode="OBJECT")
    # 2) 재질
    mat = body.data.materials[0]
    nt = mat.node_tree
    img = bpy.data.images.load(cfg["albedo"], check_existing=False)
    img.name = cfg["name"] + "_a8_albedo"
    bsdf = nt.nodes.get("Principled BSDF")
    for l in list(nt.links):
        if l.to_node == bsdf and l.to_socket.name in ("Normal", "Roughness", "Metallic"):
            nt.links.remove(l)
    tex = None
    for n in nt.nodes:
        if n.type == "TEX_IMAGE":
            if any(l.to_socket.name == "Base Color" for l in n.outputs[0].links):
                tex = n
    if tex is None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    tex.image = img
    bsdf.inputs["Roughness"].default_value = 0.75
    # 3) 치마
    objs_new = []
    kd = kdtree.KDTree(len(body.data.vertices))
    for i, v in enumerate(body.data.vertices):
        kd.insert(v.co, i)
    kd.balance()
    gname = {vg.index: vg.name for vg in body.vertex_groups}
    wsrc = [[(gname[g.group], g.weight) for g in v.groups] for v in body.data.vertices]
    neck_z = None
    if cfg.get("skirt_mesh_npz"):
        d = np.load(cfg["skirt_mesh_npz"], allow_pickle=False)
        names = [str(x) for x in d["names"]]
        V, T, UV, rng, pt = d["verts"], d["tris"], d["uv"], d["ranges"], d["part_tris"]
        starts = np.concatenate([[0], np.cumsum(pt)])
        sel_tris, sel_uv = [], []
        neck_z = None
        for k, nm in enumerate(names):
            if nm == "neck":
                neck_z = float(V[rng[k][0]:rng[k][1]][:, 2].min())
        for k, nm in enumerate(names):
            if any(nm.startswith(q) for q in cfg.get("transplant", ["skirt"])):
                sel_tris.append(T[starts[k]:starts[k + 1]])
                sel_uv.append(UV[starts[k]:starts[k + 1]])
        Ts, UVs = np.concatenate(sel_tris), np.concatenate(sel_uv)
        used = np.unique(Ts)
        remap = -np.ones(len(V), np.int64)
        remap[used] = np.arange(len(used))
        me = bpy.data.meshes.new(cfg["name"] + "_outfit")
        me.from_pydata([tuple(map(float, V[u])) for u in used], [], [tuple(int(remap[x]) for x in t) for t in Ts])
        me.update()
        uvl = me.uv_layers.new(name="UVMap")
        uvl.data.foreach_set("uv", UVs.reshape(-1, 2).astype(np.float32).reshape(-1))
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        sk = bpy.data.objects.new(cfg["name"] + "_outfit", me)
        bpy.context.scene.collection.objects.link(sk)
        m2 = bpy.data.materials.new(cfg["name"] + "_skirt_mat")
        m2.use_nodes = True
        t2 = m2.node_tree.nodes.new("ShaderNodeTexImage")
        i2 = bpy.data.images.load(cfg["skirt_albedo"], check_existing=False)
        i2.name = cfg["name"] + "_a8_skirt_albedo"
        t2.image = i2
        m2.node_tree.links.new(t2.outputs["Color"], m2.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        m2.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.75
        me.materials.append(m2)
        groups = {}
        for vi, v in enumerate(me.vertices):
            co, j, dist = kd.find(v.co)
            for g, w in wsrc[j]:
                groups.setdefault(g, []).append((vi, w))
        for g, lst in groups.items():
            vg = sk.vertex_groups.new(name=g)
            for vi, w in lst:
                vg.add([vi], w, "REPLACE")
        objs_new.append(sk)
    # 3b) 옛 모델에서 가져온 부위가 대신하는 몸 쪽을 지운다: 머리, 발, 목 윗부분(neck_z 위)
    drop = set(cfg.get("drop_groups", []))
    if drop:
        import bmesh
        dom = [max(wsrc[i], key=lambda t: t[1])[0] if wsrc[i] else "" for i in range(len(body.data.vertices))]
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bm.verts.ensure_lookup_table()
        kill = [bm.verts[i] for i in range(len(dom)) if dom[i] in drop or (neck_z is not None and dom[i] == "neck_01" and body.data.vertices[i].co.z > neck_z)]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        bm.to_mesh(body.data)
        bm.free()
    body.name = "body"
    body.data.name = "body"
    # 4) 머리카락
    if cfg.get("hair"):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=cfg["hair"])
        new = [o for o in bpy.data.objects if o not in before]
        hair = next(o for o in new if o.type == "MESH")
        for o in new:
            if o is not hair:
                bpy.data.objects.remove(o, do_unlink=True)
        hair.parent = None
        hair.matrix_world = hair.matrix_world.copy()
        for v in hair.data.vertices:
            v.co = follow(v.co)
        hair.vertex_groups.clear()
        vg = hair.vertex_groups.new(name="Head")
        vg.add(list(range(len(hair.data.vertices))), 1.0, "REPLACE")
        tint = cfg.get("hair_tint", [0.8, 0.8, 0.88])
        for m in hair.data.materials:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image is not None and n.image.size[0] > 16:
                    w, h = n.image.size
                    buf = np.empty(w * h * 4, np.float32)
                    n.image.pixels.foreach_get(buf)
                    px = buf.reshape(h, w, 4)
                    if cfg.get("hair_albedo"):   # 그림에서 구운 색(uv가 같다) + 원래 알파
                        bi = bpy.data.images.load(cfg["hair_albedo"], check_existing=False)
                        bi.scale(w, h)
                        bb = np.empty(w * h * 4, np.float32)
                        bi.pixels.foreach_get(bb)
                        px[..., :3] = bb.reshape(h, w, 4)[..., :3]
                    else:
                        lum = px[..., :3].mean(-1, keepdims=True)
                        px[..., :3] = np.clip(lum * float(cfg.get("hair_gain", 1.0)) * np.array(tint, np.float32), 0, 1)
                    img2 = bpy.data.images.new(cfg["name"] + "_a8_hair", w, h, alpha=True)
                    img2.pixels.foreach_set(px.reshape(-1))
                    img2.pack()
                    n.image = img2
        objs_new.append(hair)
    for o in objs_new:
        o.parent = arm
        o.matrix_parent_inverse.identity()
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    # 5) 동작: 원본 이름으로 표본 -> 이름 바꾸기 -> 새 동작으로 굽기
    before_o = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=cfg["actions"])
    for o in [o for o in bpy.data.objects if o not in before_o]:
        bpy.data.objects.remove(o, do_unlink=True)
    for act in list(bpy.data.actions):
        act.use_fake_user = True
    scene = bpy.context.scene
    ad = arm.animation_data_create()
    sampled = {}
    pbs = list(arm.pose.bones)
    for c in cfg["clips"]:
        act = bpy.data.actions[c["src"]]
        ad.action = act
        if hasattr(ad, "action_slot") and len(act.slots):
            ad.action_slot = act.slots[0]
        L = act.frame_range[1] - act.frame_range[0]
        n = int(round(float(c["seconds"]) * 60))
        frames = []
        for i in range(n + 1):
            f = act.frame_range[0] + (i / n) * L
            fi = int(np.floor(f))
            scene.frame_set(fi, subframe=f - fi)
            frames.append({pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in pbs})
        sampled[c["name"]] = frames
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    ad.action = None
    # 뼈 이름 바꾸기(정점 그룹은 같이 바뀐다)
    ren = {b.name: our_name(b.name) for b in arm.data.bones}
    for old, new in ren.items():
        if old != new:
            arm.data.bones[old].name = new
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    key_loc = {"pelvis_cr", "root"}
    for name, frames in sampled.items():
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        ad.action = act
        for i, fr in enumerate(frames):
            for old, (q, loc) in fr.items():
                pb = arm.pose.bones[ren[old]]
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=i, group=pb.name)
                if pb.name in key_loc:
                    pb.location = loc
                    pb.keyframe_insert("location", frame=i, group=pb.name)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    ad.action = bpy.data.actions[cfg["clips"][0]["name"]]
    if hasattr(ad, "action_slot") and len(ad.action.slots):
        ad.action_slot = ad.action.slots[0]
    bpy.ops.wm.save_as_mainfile(filepath=a.out_blend, compress=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if a.out_glb:
        rc.export_glb(a.out_glb, arm, meshes, fps=60)
    print("BASE_BUILD meshes %s clips %d" % ([m.name for m in meshes], len(sampled)))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
