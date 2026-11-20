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
    idx = {n: i for i, n in enumerate(bnames)}
    h_fit, t_fit = fit["bones_head"], fit["bones_tail"]
    if cfg.get("arm_restore", True):   # 맞춤이 눌러 납작해진 팔(위팔·아래팔·손) 단면을 원본 굵기로 되돌린다(arm_restore.py)
        import arm_restore as ar
        gnm = {vg.index: vg.name for vg in body.vertex_groups}
        W = {}
        for gi, gn in gnm.items():
            col = np.zeros(len(orig))
            W[gn] = col
        for vi, v in enumerate(body.data.vertices):
            for g in v.groups:
                W[gnm[g.group]][vi] = g.weight
        arm_cfg = cfg.get("arm_restore_opts", {})
        rest_new = np.array(rest_fit)
        arm_rep = {}
        for side in ("l", "r"):
            segs = {"upper": ["upperarm_" + side], "fore": ["lowerarm_" + side],
                    "hand": ["hand_" + side] + [n for n in W if n.endswith("_" + side) and n.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb")]}
            wts = {k: sum(W[n] for n in v if n in W) for k, v in segs.items()}
            main = {"upper": "upperarm_" + side, "fore": "lowerarm_" + side, "hand": "hand_" + side}
            bo = {k: (np.array(arm.data.bones[n].head_local), np.array(arm.data.bones[n].tail_local)) for k, n in main.items()}
            bf = {k: (h_fit[idx[n]], t_fit[idx[n]]) for k, n in main.items()}
            rest_new, rep = ar.restore(orig, rest_new, wts, bo, bf, ["upper", "fore", "hand"], cap=float(arm_cfg.get("cap", 1.9)))
            arm_rep[side] = rep
        # 팔꿈치·어깨 가중치: 굽힘에서 단면이 꺼지지 않게 매끈한 이음으로 다시 깐다(arm_restore.elbow_blend / smooth_region)
        if arm_cfg.get("weights", True):
            edges_b = np.array([(e.vertices[0], e.vertices[1]) for e in body.data.edges])
            for side in ("l", "r"):
                up, fo = "upperarm_" + side, "lowerarm_" + side
                n_el = ar.elbow_blend(rest_new, W, up, fo, h_fit[idx[fo]], t_fit[idx[fo]] - h_fit[idx[fo]], float(arm_cfg.get("elbow_band", 0.07)))
                n_sh = ar.smooth_region(rest_new, W, edges_b, h_fit[idx[up]], float(arm_cfg.get("shoulder_radius", 0.12)), int(arm_cfg.get("shoulder_iters", 4)))
                print("ARM_WEIGHTS", side, "elbow verts", n_el, "shoulder verts", n_sh)
            if arm_cfg.get("hand_shells", True):   # 손이 두 겹 껍질이면 작은 껍질의 가중치를 가까운 큰 껍질 정점에서 복사(손가락이 같이 굽게)
                for side in ("l", "r"):
                    hn = [n for n in W if n == "hand_" + side or (n.endswith("_" + side) and n.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb"))]
                    hw = sum(W[n] for n in hn)
                    hv = np.where(hw > 0.5)[0]
                    hs = set(hv.tolist())
                    par = {i: i for i in hv.tolist()}

                    def find(x):
                        while par[x] != x:
                            par[x] = par[par[x]]
                            x = par[x]
                        return x
                    for a_, b_ in edges_b:
                        if a_ in hs and b_ in hs:
                            par[find(int(a_))] = find(int(b_))
                    comp = {}
                    for i in hv.tolist():
                        comp.setdefault(find(i), []).append(i)
                    comps = sorted(comp.values(), key=len, reverse=True)
                    if len(comps) < 2:
                        continue
                    src = np.array(comps[0])
                    for c_ in comps[1:]:
                        if len(c_) < 100:
                            continue
                        c_ = np.array(c_)
                        dd = np.linalg.norm(rest_new[c_][:, None, :] - rest_new[src][None, :, :], axis=2)
                        near = src[np.argmin(dd, axis=1)]
                        for n in W:
                            W[n][c_] = W[n][near]
                    print("ARM_HAND_SHELLS", side, [len(c_) for c_ in comps])
            for vg in body.vertex_groups:
                vg.remove(list(range(len(orig))))
            gidx = {vg.name: vg for vg in body.vertex_groups}
            for gn, col in W.items():
                for vi in np.where(col > 1e-4)[0]:
                    gidx[gn].add([int(vi)], float(col[vi]), "REPLACE")
        print("ARM_RESTORE", {s: {k: round(v["k"], 3) for k, v in r.items()} for s, r in arm_rep.items()})
        rest_fit = rest_new
        disp = rest_fit - orig
    for i, v in enumerate(body.data.vertices):
        v.co = Vector(rest_fit[i])
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
    albedo_path = cfg["albedo"]
    shade = cfg.get("arm_shade")
    afix = cfg.get("albedo_fix")
    if shade or afix:   # 얼음 소매처럼 한 색으로 구운 팔에 원통 음영을 굽는다(arm_shade.py). 설정 arm_shade: {"sides": ["l"], "strength": 1.0}
        import arm_shade as ash
        tu, tf = [], []
        if shade:
            gnm2 = {vg.index: vg.name for vg in body.vertex_groups}
            domn = []
            for v in body.data.vertices:
                domn.append(gnm2[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else "")
            domn = np.array(domn)
            posr = np.array([v.co[:] for v in body.data.vertices])
            shade_sides = shade.get("sides", ["l"])
            segs = []
            for sd in shade_sides:
                for gname_, kind in (("upperarm_" + sd, "upper"), ("lowerarm_" + sd, "fore"), ("hand_" + sd, "hand")):
                    segs.append((h_fit[idx[gname_]], t_fit[idx[gname_]], domn == gname_, kind))
            fv = ash.vertex_factor(posr, segs, float(shade.get("strength", 1.0)), float(shade.get("streaks", 0.07)), float(shade.get("ring", 0.22)))
            inarm = np.zeros(len(posr), bool)
            for s_ in segs:
                inarm |= s_[2]
            uvl = body.data.uv_layers.active
            tu, tf = [], []
            for poly in body.data.polygons:
                vs = list(poly.vertices)
                if not all(inarm[i] for i in vs):
                    continue
                uvs = [uvl.data[li].uv[:] for li in poly.loop_indices]
                for k in range(1, len(vs) - 1):
                    tu.append([uvs[0], uvs[k], uvs[k + 1]])
                    tf.append([fv[vs[0]], fv[vs[k]], fv[vs[k + 1]]])
        tmp = bpy.data.images.load(cfg["albedo"], check_existing=False)
        iw, ih = tmp.size
        buf = np.empty(iw * ih * 4, np.float32)
        tmp.pixels.foreach_get(buf)
        arr = buf.reshape(ih, iw, 4)[::-1].copy()          # Blender 픽셀은 아래가 첫 줄 -> 위가 첫 줄로
        rgb = arr[..., :3].astype(np.float64)
        if shade:
            rgb = ash.apply(rgb, np.array(tu), np.array(tf))
        if afix:
            import albedo_fix as afx
            for fx in afix:
                fmask = None
                if fx.get("groups"):   # 이 가중치 마디가 지배하는 면의 uv 섬만(예: 맨살 팔의 얼룩덜룩한 투영 조각 고르게)
                    gset = set(fx["groups"])
                    gn3 = {vg.index: vg.name for vg in body.vertex_groups}
                    dom3 = [gn3[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else "" for v in body.data.vertices]
                    uvl3 = body.data.uv_layers.active
                    tris3 = []
                    for poly in body.data.polygons:
                        vs = list(poly.vertices)
                        if all(dom3[i] in gset for i in vs):
                            uvs = [uvl3.data[li].uv[:] for li in poly.loop_indices]
                            for k in range(1, len(vs) - 1):
                                tris3.append([uvs[0], uvs[k], uvs[k + 1]])
                    fmask = ash.raster_mask(rgb.shape[:2], np.array(tris3))
                bx = tuple(fx["box"]) if fx.get("box") else (0, 0, rgb.shape[1], rgb.shape[0])
                n_fx = afx.fix(rgb, bx, float(fx.get("sigma", 30.0)), fx.get("mode", "all"), fmask)
                print("ALBEDO_FIX", fx.get("box") or fx.get("groups"), n_fx)
        arr[..., :3] = np.clip(rgb, 0, 1)
        tmp.pixels.foreach_set(arr[::-1].reshape(-1))
        albedo_path = str(Path(a.out_blend).with_name(cfg["name"] + "_albedo_shaded.png"))
        tmp.filepath_raw = albedo_path
        tmp.file_format = "PNG"
        tmp.save()
        bpy.data.images.remove(tmp)
        print("ARM_SHADE tris", len(tu), "->", albedo_path)
    img = bpy.data.images.load(albedo_path, check_existing=False)
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
        head_uv = []
        neck_z = None
        for k, nm in enumerate(names):
            if nm == "neck":
                neck_z = float(V[rng[k][0]:rng[k][1]][:, 2].min())
        for k, nm in enumerate(names):
            if any(nm.startswith(q) for q in cfg.get("transplant", ["skirt"])):
                sel_tris.append(T[starts[k]:starts[k + 1]])
                sel_uv.append(UV[starts[k]:starts[k + 1]])
                if nm.startswith(("head", "hair", "braid")):
                    head_uv.append(UV[starts[k]:starts[k + 1]])
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
        skirt_albedo_path = cfg["skirt_albedo"]
        hc = cfg.get("head_cap")
        if hc and head_uv:   # 머리·머리카락 그림의 흰 부분이 게임 조명에서 255로 타는 것을 막는다: 밝기 knee 위를 slope 배로 눌러 부드럽게 모은다(arm_shade.raster_mask로 머리 섬만)
            import arm_shade as ash2
            hi = bpy.data.images.load(cfg["skirt_albedo"], check_existing=False)
            hw, hh = hi.size
            hb = np.empty(hw * hh * 4, np.float32)
            hi.pixels.foreach_get(hb)
            harr = hb.reshape(hh, hw, 4)[::-1].copy()
            hmask = ash2.raster_mask((hh, hw), np.concatenate(head_uv))
            rgb_ = harr[..., :3]
            mx = rgb_.max(axis=2)
            knee, slope = float(hc.get("knee", 0.6)), float(hc.get("slope", 0.4))
            new_mx = np.where(mx > knee, knee + (mx - knee) * slope, mx)
            sc = np.where(mx > 1e-6, new_mx / np.maximum(mx, 1e-6), 1.0)
            rgb_[hmask] = (rgb_ * sc[..., None])[hmask]
            harr[..., :3] = rgb_
            hi.pixels.foreach_set(harr[::-1].reshape(-1))
            skirt_albedo_path = str(Path(a.out_blend).with_name(cfg["name"] + "_outfit_albedo_capped.png"))
            hi.filepath_raw = skirt_albedo_path
            hi.file_format = "PNG"
            hi.save()
            bpy.data.images.remove(hi)
            print("HEAD_CAP pixels", int(hmask.sum()))
        i2 = bpy.data.images.load(skirt_albedo_path, check_existing=False)
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
        orn = cfg.get("skirt_ornament")
        if orn:   # 허리 장식(원화의 엉덩이 옆 걸이 장식)이 허리 위로 솟는 것: 파란 그림 삼각형 중 영역 안의 것만 골라 z_cut 위를 squash 비율로 눌러 허리 아래로 접고, 아래쪽은 넓적다리를 follow 비율까지 따르게 한다
            oi = bpy.data.images.load(cfg["skirt_albedo"], check_existing=False)
            ow, oh = oi.size
            obuf = np.empty(ow * oh * 4, np.float32)
            oi.pixels.foreach_get(obuf)
            opx = obuf.reshape(oh, ow, 4)               # Blender: 행 0이 아래(v=0)
            bpy.data.images.remove(oi)
            rx, ry = orn.get("x", [0.10, 0.25]), orn.get("y", [-0.05, 0.03])
            bset = set()
            for tri, u in zip(Ts, UVs):
                cu = u.mean(0)
                p_ = opx[int(np.clip(cu[1], 0, 1) * (oh - 1)), int(np.clip(cu[0], 0, 1) * (ow - 1))]
                if p_[2] > p_[0] + 0.14 and p_[2] > 0.55:
                    c3 = V[tri].mean(0)
                    if rx[0] <= abs(c3[0]) <= rx[1] and ry[0] <= c3[1] <= ry[1]:
                        for vi_ in tri:
                            bset.add(int(remap[vi_]))
            zc, sq, fol = float(orn.get("z_cut", 1.20)), float(orn.get("squash", 0.15)), float(orn.get("follow", 0.6))
            for vi_, v_ in enumerate(me.vertices):   # 장식 자리의 안쪽 겹·이웃 정점도 같이 눌러 안쪽 겹 조각이 허리 위로 남지 않게 한다
                c_ = v_.co
                if c_.x > 0 and rx[0] <= c_.x <= rx[1] and ry[0] <= c_.y <= ry[1] and c_.z > zc:
                    bset.add(vi_)
            for vi_ in bset:
                co_ = me.vertices[vi_].co
                if co_.z > zc:
                    co_.z = zc + (co_.z - zc) * sq
            gmap = {}
            for g_, lst_ in groups.items():
                for vi_, w_ in lst_:
                    if vi_ in bset:
                        continue
                    gmap.setdefault(g_, []).append((vi_, w_))
            for vi_ in bset:
                co_ = me.vertices[vi_].co
                u_ = min(max((zc - co_.z) / 0.10, 0.0), 1.0)
                s_ = fol * u_ * u_ * (3 - 2 * u_)
                side_ = "thigh_l" if co_.x >= 0 else "thigh_r"
                gmap.setdefault("pelvis", []).append((vi_, 1.0 - s_))
                if s_ > 1e-4:
                    gmap.setdefault(side_, []).append((vi_, s_))
            groups = gmap
            print("SKIRT_ORNAMENT verts", len(bset))
        if cfg.get("skirt_to_pelvis", True):   # 치마·허리띠 메시의 척추 가중치를 골반으로 옮긴다: 달릴 때 윗몸 숙임·꼬임에 치마 장식띠가 허리 위로 솟는 것을 막는다
            moved = {}
            for g in ("spine_01", "spine_02", "spine_03"):
                for vi, w in groups.pop(g, []):
                    moved[vi] = moved.get(vi, 0.0) + w
            acc = {}
            for vi, w in groups.get("pelvis", []):
                acc[vi] = acc.get(vi, 0.0) + w
            for vi, w in moved.items():
                acc[vi] = acc.get(vi, 0.0) + w
            groups["pelvis"] = list(acc.items())
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
