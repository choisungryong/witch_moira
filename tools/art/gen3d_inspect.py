#!/usr/bin/env python3
"""이미지→3D 생성 모델(glb)을 게임용으로 만들기 전에 살펴본다(Blender 5.3 명령줄). 읽기 전용.

  python tools/art/gen3d_inspect.py --in MODEL.glb [--report r.json] [--dump-tex DIR]
적는 것: 삼각형·정점, 키와 폭(좌우 비대칭: x 중심 치우침), 연결 덩어리(한 껍질인지, 작은 떠 있는 조각 수),
머티리얼(PBR 채널: 바탕색·거칠기·금속·노멀·발광 이미지와 크기, 머티리얼 상수값), 열린 가장자리(경계 변) 수,
얼굴 높이의 질감 이음 의심(UV 이음 변 위치 요약). --dump-tex DIR이면 glb 안 이미지를 DIR에 풀어 쓴다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="input", required=True)
    ap.add_argument("--report")
    ap.add_argument("--dump-tex")
    a = ap.parse_args(argv)
    import bpy
    import bmesh
    import numpy as np
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=a.input)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    rep = {"objects": len(objs)}
    o = objs[0]
    me = o.data
    me.calc_loop_triangles()
    P = rc.mesh_coords(o)
    mn, mx = P.min(0), P.max(0)
    rep["triangles"] = len(me.loop_triangles)
    rep["vertices"] = len(me.vertices)
    rep["bbox_min"] = [round(float(v), 4) for v in mn]
    rep["bbox_max"] = [round(float(v), 4) for v in mx]
    rep["center_x_offset"] = round(float((mx[0] + mn[0]) / 2), 4)
    # 연결 덩어리
    bm = bmesh.new()
    bm.from_mesh(me)
    rep["vertices_before_weld"] = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)   # glb는 UV 이음마다 정점이 갈라져 있어 위치로 붙여야 진짜 덩어리가 보인다
    rep["vertices_after_weld"] = len(bm.verts)
    bm.faces.ensure_lookup_table()
    seen, comps = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, n, zs = [f], 0, []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            n += 1
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        comps.append(n)
    comps.sort(reverse=True)
    rep["components"] = len(comps)
    rep["component_faces_top"] = comps[:8]
    rep["components_under_200_faces"] = sum(1 for c in comps if c < 200)
    rep["boundary_edges"] = sum(1 for e in bm.edges if e.is_boundary)
    rep["nonmanifold_edges"] = sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
    bm.free()
    # 머티리얼
    mats = []
    for m in me.materials:
        d = {"name": m.name, "images": {}}
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    d["roughness_const"] = round(float(n.inputs["Roughness"].default_value), 3)
                    d["metallic_const"] = round(float(n.inputs["Metallic"].default_value), 3)
                    for sock in ("Base Color", "Roughness", "Metallic", "Normal", "Emission Color", "Alpha"):
                        s = n.inputs.get(sock)
                        if s is not None and s.is_linked:
                            src = s.links[0].from_node
                            while src.type not in ("TEX_IMAGE",) and src.inputs and any(i.is_linked for i in src.inputs):
                                src = next(i for i in src.inputs if i.is_linked).links[0].from_node
                            if src.type == "TEX_IMAGE" and src.image:
                                d["images"][sock] = {"name": src.image.name, "size": list(src.image.size), "colorspace": src.image.colorspace_settings.name}
        mats.append(d)
    rep["materials"] = mats
    if a.dump_tex:
        Path(a.dump_tex).mkdir(parents=True, exist_ok=True)
        for im in bpy.data.images:
            if im.size[0] > 0:
                im.filepath_raw = str(Path(a.dump_tex) / (im.name.replace("/", "_") + ".png"))
                im.file_format = "PNG"
                im.save()
    # UV 이음(얼굴 가로선 의심): UV 섬 경계 변의 높이 분포
    uv = me.uv_layers.active
    if uv:
        UV = np.empty(len(me.loops) * 2)
        uv.data.foreach_get("uv", UV)
        UV = UV.reshape(-1, 2)
        V = np.empty(len(me.loops), int)
        me.loops.foreach_get("vertex_index", V)
        # 정점별 UV가 둘 이상이면 이음 정점
        key = {}
        for vi, u in zip(V, map(tuple, np.round(UV, 4))):
            key.setdefault(int(vi), set()).add(u)
        seam = np.array([i for i, s in key.items() if len(s) > 1])
        rep["uv_seam_vertices"] = int(len(seam))
        if len(seam):
            z = P[seam, 2]
            H = mx[2] - mn[2]
            head = z > mn[2] + H * 0.86
            rep["uv_seam_vertices_in_head_zone"] = int(head.sum())
            hz = z[head]
            hist, edges = np.histogram((hz - mn[2]) / H, bins=14, range=(0.86, 1.0)) if len(hz) else ([], [])
            rep["uv_seam_head_hist"] = [int(v) for v in hist]
    out = json.dumps(rep, ensure_ascii=False, indent=1)
    print(out)
    if a.report:
        Path(a.report).parent.mkdir(parents=True, exist_ok=True)
        Path(a.report).write_text(out, encoding="utf-8")
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
