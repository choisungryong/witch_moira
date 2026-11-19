#!/usr/bin/env python3
"""그림→3D 생성 도구가 준 고폴리 메시를 게임용 저폴리로 줄인다(Blender 5.3 명령줄).

  python tools/art/mesh_reduce.py --in HIGH.glb --out-glb OUT.glb --profile game [--target N] [--height 2.0] [--report r.json] [--work DIR]
  python tools/art/mesh_reduce.py --in HIGH.glb --out-glb OUT.glb --profile showcase        # 크게 보여 줄 때(약 5만)
  (Blender 바깥에서 부르면 스스로 Blender를 부른다. 환경변수 BLENDER_EXE)

차례: 가져오기 → 한 덩어리로 합침 → 축·크기 맞춤(정면 -Y, 바닥 z=0, 높이 --height m) → 겹친 정점·떨어진 작은 조각 정리 →
      (선택) 보이지 않는 안쪽 면 지우기 → 데시메이트(얼굴·손은 덜 줄임, UV 이음매·재질 경계 보존) → 새 UV 펼치기 →
      고폴리의 색을 새 UV 텍스처로, 고폴리의 굴곡을 저폴리의 노멀 맵으로 굽기(Cycles, CPU) → glb(메시 + 재질, 뼈대 없음) 내보내기.
단계별 목표 삼각형은 tools/art/rig_configs/reduce_profiles.json(game 약 1만2천, showcase 약 5만).
보고서(JSON): 전후 삼각형·정점 수, 실루엣 차이(8방향 정사영 렌더의 윤곽 겹침 IoU와 어긋난 픽셀 비율), 텍스처 크기, 정리한 조각 수, 게임 배율(2.67÷높이).
이어서 rig_build → rig_clips → rig_parts → rig_check. 라이선스를 판단하지 않는다.
시험용: --subdivide N 은 입력을 세분화해 가짜 고폴리를 만든다(저장소에 고폴리 메시가 없어서 쓴 방법).
"""
from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


_T0 = time.time()


def log(msg):
    print("REDUCE_STEP %6.1fs %s" % (time.time() - _T0, msg), flush=True)


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def normalize_pose(obj, height, facing):
    import numpy as np
    from mathutils import Matrix
    me = obj.data
    import math as m
    rot = {"+Y": 180, "+X": 90, "-X": -90}.get(facing)
    if rot:
        me.transform(Matrix.Rotation(m.radians(rot), 4, "Z"))
    P = rc.mesh_coords(obj)
    k = height / float(P[:, 2].max() - P[:, 2].min())
    me.transform(Matrix.Scale(k, 4))
    P = rc.mesh_coords(obj)
    cx = float((P[:, 0].max() + P[:, 0].min()) / 2)
    me.transform(Matrix.Translation((-cx, 0, -float(P[:, 2].min()))))
    return k


def cleanup(obj, H, min_frac=0.03, min_faces=60):
    """겹친 정점을 합치고, 아주 작고 떨어진 조각(면 min_faces 미만이고 크기가 키의 min_frac 미만)을 지운다."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    before_v = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=H * 1e-5)
    seen, comps = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        stack, comp = [f], []
        seen.add(f)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf not in seen:
                        seen.add(nf)
                        stack.append(nf)
        comps.append(comp)
    removed = 0
    for comp in comps:
        if len(comp) >= min_faces:
            continue
        vs = {v for f in comp for v in f.verts}
        xs = [v.co.x for v in vs]
        ys = [v.co.y for v in vs]
        zs = [v.co.z for v in vs]
        diag = math.sqrt((max(xs) - min(xs)) ** 2 + (max(ys) - min(ys)) ** 2 + (max(zs) - min(zs)) ** 2)
        if diag < min_frac * H and len(comps) > 1:
            bmesh.ops.delete(bm, geom=comp, context="FACES")
            removed += 1
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    info = {"merged_vertices": before_v - len(bm.verts), "components": len(comps), "loose_pieces_removed": removed}
    bm.free()
    return info


def cull_interior(obj, H, rays=14, eps_frac=2e-4):
    """안쪽 면 지우기(보수적): 면 중심에서 법선 쪽 반구로 쏜 광선이 전부 다른 면에 막히면 안 보이는 면으로 본다."""
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    dirs = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(rays):                       # 반구 위 거의 고른 방향(법선 기준 좌표)
        z = 1 - (i + 0.5) / rays * 0.9
        r = math.sqrt(max(1 - z * z, 0))
        dirs.append((r * math.cos(ga * i), r * math.sin(ga * i), z))
    kill = []
    eps = H * eps_frac
    for f in bm.faces:
        n = f.normal
        if n.length < 1e-9:
            continue
        c = f.calc_center_median() + n * eps
        t1 = n.orthogonal().normalized()
        t2 = n.cross(t1)
        blocked = True
        for dx, dy, dz in dirs:
            d = t1 * dx + t2 * dy + n * dz
            hit = tree.ray_cast(c, d, H * 2)
            if hit[0] is None:
                blocked = False
                break
        if blocked:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    return len(kill)


def protect_group(obj, H, regions):
    """얼굴(머리 높이)·손(양쪽 가장 먼 점 군)을 덜 줄이도록 정점 그룹을 만든다. 반환: 보호 정점 수."""
    import numpy as np
    P = rc.mesh_coords(obj)
    w = np.zeros(len(P))
    if "head" in regions:
        w[P[:, 2] > 0.86 * H] = 1.0
    if "hands" in regions:
        k = max(30, int(0.01 * len(P)))
        for sgn in (1, -1):
            m = (P[:, 2] > 0.35 * H) & (sgn * P[:, 0] > 0)
            idx = np.where(m)[0]
            if len(idx) > k:
                sel = idx[np.argsort(-sgn * P[idx, 0])[:k]]
                c = P[sel].mean(axis=0)
                near = np.linalg.norm(P - c, axis=1) < 0.09 * H
                w[near] = 1.0
    vg = obj.vertex_groups.new(name="protect")
    ids = np.where(w > 0)[0]
    if len(ids):
        vg.add([int(i) for i in ids], 1.0, "REPLACE")
    return int(len(ids))


def _decimate_once(obj, ratio, protect, keep_seams):
    import bpy
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(min(ratio, 1.0), 0.001)
    mod.use_collapse_triangulate = True
    if keep_seams:
        mod.delimit = {"UV", "MATERIAL"}
    if protect and "protect" in obj.vertex_groups:
        mod.vertex_group = "protect"
        mod.invert_vertex_group = False
        mod.vertex_group_factor = 2.0
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return tri_count(obj)


def decimate(obj, target, protect, keep_seams=True):
    """목표 삼각형 수로 줄인다. 보호 그룹을 쓰면 한 번에 목표에 못 미치므로(보호 부위가 덜 줄어듦) 여러 번 돌리고, 끝내 못 맞추면 보호 없이 한 번 더."""
    cur = tri_count(obj)
    for _ in range(6):
        if cur <= target * 1.03:
            return cur
        cur = _decimate_once(obj, target / cur, protect, keep_seams)
        if not protect:
            break
    if cur > target * 1.03:
        cur = _decimate_once(obj, target / cur, False, keep_seams)
    return cur


def make_material(name, tex_img, normal_img):
    import bpy
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = tex_img
    t.name = "color_tex"
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = normal_img
    n.name = "normal_tex"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat, t, n


def bake_pair(high, low, color_px, normal_px, extrusion, work, base):
    """고폴리 -> 저폴리의 새 UV로 색과 노멀을 굽는다. 반환: (색 이미지, 노멀 이미지, 메모)."""
    import bpy
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 2
    sc.cycles.use_denoising = False
    bk = sc.render.bake
    bk.use_selected_to_active = True
    bk.cage_extrusion = extrusion
    bk.max_ray_distance = 0.0
    bk.margin = 12
    bk.use_clear = True
    notes = []
    img_c = bpy.data.images.new(base + "_color", color_px, color_px, alpha=False)
    img_n = bpy.data.images.new(base + "_normal", normal_px, normal_px, alpha=False)
    img_n.colorspace_settings.name = "Non-Color"
    low.data.materials.clear()
    mat, tex_c, tex_n = make_material(base + "_mat", img_c, img_n)
    low.data.materials.append(mat)
    nt = mat.node_tree

    def select_pair():
        bpy.ops.object.select_all(action="DESELECT")
        high.select_set(True)
        low.select_set(True)
        bpy.context.view_layer.objects.active = low

    has_color_src = any(s.material for s in high.material_slots)
    if has_color_src:
        nt.nodes.active = tex_c
        select_pair()
        bk.use_pass_direct = False
        bk.use_pass_indirect = False
        bk.use_pass_color = True
        bpy.ops.object.bake(type="DIFFUSE")
    else:
        notes.append("고폴리에 재질이 없어 색은 굽지 않았다(회색 그대로)")
        img_c.pixels = [0.6] * (color_px * color_px * 4)
    nt.nodes.active = tex_n
    select_pair()
    bk.normal_space = "TANGENT"
    bpy.ops.object.bake(type="NORMAL")
    for img, suf in ((img_c, "color"), (img_n, "normal")):
        p = str(Path(work) / ("%s_%s.png" % (base, suf)))
        img.filepath_raw = p
        img.file_format = "PNG"
        img.save()
        img.pack()
    return img_c, img_n, notes


def silhouette_compare(a_obj, b_obj, H, views, res=384):
    """같은 자리에 둔 두 메시를 8방향(+위) 정사영으로 렌더해 윤곽을 견준다. 반환: 방향별 IoU와 어긋난 픽셀 비율."""
    import bpy
    import numpy as np
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "SINGLE"
    sc.display.shading.single_color = (1, 1, 1)
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    cd = bpy.data.cameras.new("sil")
    cd.type = "ORTHO"
    cd.ortho_scale = H * 1.25
    cam = bpy.data.objects.new("sil", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    from mathutils import Euler
    out = []
    angles = [i * 360.0 / views for i in range(views)] + ["top"]
    for ang in angles:
        if ang == "top":
            cam.location = (0, 0, 10)
            cam.rotation_euler = (0, 0, 0)
        else:
            r = math.radians(ang)
            cam.location = (10 * math.sin(r), -10 * math.cos(r), H * 0.5)
            cam.rotation_euler = (math.radians(90), 0, r)
        masks = []
        for o in (a_obj, b_obj):
            for p in (a_obj, b_obj):
                p.hide_render = (p is not o)
            sc.render.filepath = str(Path(bpy.app.tempdir) / "sil.png")
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(sc.render.filepath, check_existing=False)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(res, res, 4)[:, :, 3] > 0.5
            bpy.data.images.remove(img)
            masks.append(px)
        inter = float((masks[0] & masks[1]).sum())
        union = float((masks[0] | masks[1]).sum())
        out.append({"view": ang, "iou": inter / max(union, 1), "mismatch_ratio": float((masks[0] ^ masks[1]).sum()) / max(float(masks[0].sum()), 1)})
    a_obj.hide_render = b_obj.hide_render = False
    return out


def main(argv):
    import bpy
    ap = argparse.ArgumentParser(description="고폴리 메시를 게임용으로 줄인다")
    ap.add_argument("--in", dest="input", required=True)
    ap.add_argument("--out-glb", required=True)
    ap.add_argument("--profile", default="game", choices=["game", "showcase"])
    ap.add_argument("--target", type=int, help="목표 삼각형 수(프로필 값을 덮음)")
    ap.add_argument("--height", type=float, help="맞출 키(미터). 기본 2.0")
    ap.add_argument("--facing", default="-Y", help="입력 모델이 보는 쪽(-Y 정면이 기본. +Y면 180도 돌림)")
    ap.add_argument("--tex", type=int, help="색 텍스처 한 변(px)")
    ap.add_argument("--normal-tex", type=int, help="노멀 텍스처 한 변(px)")
    ap.add_argument("--cage", type=float, default=0.02, help="굽기 때 저폴리 표면에서 바깥으로 밀어 광선을 쏘는 거리(키 대비). 겹옷이 두껍게 겹치면 작게")
    ap.add_argument("--uv-angle", type=float, default=80.0, help="새 UV를 펼칠 때 조각을 가르는 각도(도). 클수록 조각이 큼")
    ap.add_argument("--min-vertices", type=int, default=200, help="이보다 정점이 적은 물체는 버린다(구슬 같은 보조 물체)")
    ap.add_argument("--no-bake", action="store_true", help="굽지 않는다(데시메이트만. 원래 UV·재질은 그대로)")
    ap.add_argument("--uv", default="new", choices=["new", "keep"], help="new: 새로 펼침(기본), keep: 데시메이트가 남긴 UV 그대로")
    ap.add_argument("--protect", default="head,hands", help="덜 줄일 부위(head,hands). 빈 값이면 없음")
    ap.add_argument("--cull-interior", action="store_true", help="안 보이는 안쪽 면 지우기(느림)")
    ap.add_argument("--subdivide", type=int, default=0, help="시험용: 입력을 N번 세분화해 가짜 고폴리를 만든다")
    ap.add_argument("--work", default=str(Path(rc.REPO) / "_local" / "char3d" / "reduce"), help="텍스처 PNG·중간 파일 폴더")
    ap.add_argument("--report")
    ap.add_argument("--blend", help="결과 .blend도 저장")
    ap.add_argument("--compare-original", help="줄이기 전의 원래 모델 파일(시험용 가짜 고폴리가 아닌 것). 실루엣을 이것과도 견준다")
    ap.add_argument("--no-silhouette", action="store_true")
    a = ap.parse_args(argv)
    prof_all = rc.read_json(Path(__file__).resolve().parent / "rig_configs" / "reduce_profiles.json")
    prof = prof_all["profiles"][a.profile]
    target = a.target or prof["triangles"]
    height = a.height or prof_all["height_m"]
    tex = a.tex or prof["texture"]
    ntex = a.normal_tex or prof["normal"]
    t0 = time.time()
    Path(a.work).mkdir(parents=True, exist_ok=True)
    rc.reset_scene(30)
    rc.import_any(a.input)
    cfg = {"mesh": {"min_vertices": a.min_vertices, "drop_names": [], "facing": "-Y"}}
    obj = rc.single_mesh_from_import(cfg)
    rep = {"tool": "mesh_reduce.py", "input": a.input, "profile": a.profile, "target": target}
    if a.subdivide:
        bpy.context.view_layer.objects.active = obj
        sub = obj.modifiers.new("sub", "SUBSURF")
        sub.levels = a.subdivide
        sub.render_levels = a.subdivide
        bpy.ops.object.modifier_apply(modifier=sub.name)
        rep["fake_highpoly_subdivide"] = a.subdivide
    log("가져옴 삼각형 %d" % tri_count(obj))
    k = normalize_pose(obj, height, a.facing)
    H = height
    rep["input_triangles"] = tri_count(obj)
    rep["input_vertices"] = len(obj.data.vertices)
    rep["input_materials"] = len(obj.data.materials)
    rep["scale_applied"] = k
    rep["cleanup"] = cleanup(obj, H)
    log("정리 끝")
    high = obj
    high.name = "high"
    # 저폴리 복제본에서 작업
    low = high.copy()
    low.data = high.data.copy()
    low.name = "low"
    bpy.context.scene.collection.objects.link(low)
    bpy.context.view_layer.update()
    bpy.context.view_layer.objects.active = low
    if a.cull_interior:
        rep["interior_faces_removed"] = cull_interior(low, H) if tri_count(low) < 400000 else "건너뜀(면이 너무 많다: 먼저 줄인다)"
    protect = [s for s in a.protect.split(",") if s]
    rep["protected_vertices"] = protect_group(low, H, protect) if protect else 0
    # 단계적으로 줄인다(한 번에 비율이 너무 작으면 모양이 깨진다)
    cur = tri_count(low)
    guard = 0
    while cur > target * 4 and guard < 6:
        guard += 1
        cur = decimate(low, max(int(cur / 3), target * 3), protect, True)
    if a.cull_interior and rep.get("interior_faces_removed") == "건너뜀(면이 너무 많다: 먼저 줄인다)":
        rep["interior_faces_removed"] = cull_interior(low, H)
    final = decimate(low, target, protect, True)
    log("중간 줄임 %d" % cur)
    rep["output_triangles"] = final
    log("줄임 끝 %d" % final)
    rep["output_vertices"] = len(low.data.vertices)
    rep["within_profile"] = prof["triangles_min"] * 0.9 <= final <= prof["triangles_max"]
    low.vertex_groups.clear()
    notes = []
    if a.no_bake:
        mats = list(low.data.materials)
    else:
        if a.uv == "new" or not low.data.uv_layers:
            bpy.ops.object.select_all(action="DESELECT")
            low.select_set(True)
            bpy.context.view_layer.objects.active = low
            for n in list(low.data.uv_layers):
                low.data.uv_layers.remove(n)
            low.data.uv_layers.new(name="UVMap")
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=math.radians(a.uv_angle), island_margin=0.004)
            bpy.ops.object.mode_set(mode="OBJECT")
        base = Path(a.out_glb).stem
        log('굽기 시작')
        img_c, img_n, notes = bake_pair(high, low, tex, ntex, a.cage * H, a.work, base)
        rep["textures"] = {"color": "%dx%d" % (tex, tex), "normal": "%dx%d" % (ntex, ntex), "files": [str(Path(a.work) / (base + "_color.png")), str(Path(a.work) / (base + "_normal.png"))]}
    rep["notes"] = notes
    log("굽기 끝")
    # 실루엣: 줄이기 전(고폴리)과 후
    if not a.no_silhouette:
        views = prof_all["silhouette_views"]
        sil = silhouette_compare(high, low, H, views)
        rep["silhouette"] = {"views": sil, "iou_min": min(s["iou"] for s in sil), "iou_mean": sum(s["iou"] for s in sil) / len(sil),
                             "mismatch_max": max(s["mismatch_ratio"] for s in sil)}
    if a.compare_original and not a.no_silhouette:
        import rig_parts
        orig = rig_parts.import_part_mesh(a.compare_original, "orig", a.min_vertices)
        normalize_pose(orig, height, a.facing)
        sil2 = silhouette_compare(orig, low, H, prof_all["silhouette_views"])
        rep["silhouette_vs_original"] = {"file": a.compare_original, "triangles_original": tri_count(orig), "views": sil2,
                                         "iou_min": min(s_["iou"] for s_ in sil2), "iou_mean": sum(s_["iou"] for s_ in sil2) / len(sil2),
                                         "mismatch_max": max(s_["mismatch_ratio"] for s_ in sil2)}
        bpy.data.objects.remove(orig, do_unlink=True)
    rep["game_scale"] = prof_all["game_target_height"] / height
    rep["height_m"] = height
    # 내보내기: 고폴리는 빼고 저폴리만
    bpy.data.objects.remove(high, do_unlink=True)
    low.name = Path(a.out_glb).stem
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    Path(a.out_glb).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=a.out_glb, export_format="GLB", use_selection=True, export_yup=True, export_animations=False,
                              export_apply=False, export_extras=False)
    rep["out_glb"] = a.out_glb
    rep["seconds"] = round(time.time() - t0, 1)
    if a.blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.blend, compress=True)
    if a.report:
        rc.write_json(a.report, rep)
    print("MESH_REDUCE", {k2: rep[k2] for k2 in ("input_triangles", "output_triangles") if k2 in rep}, rep.get("silhouette", {}).get("iou_mean"))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
