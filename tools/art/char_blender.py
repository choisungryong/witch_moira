#!/usr/bin/env python3
"""char_from_sheets의 Blender 쪽: mesh.npz + 텍스처 -> 메시 한 덩어리 glb(뼈 없음). rig_build가 이어 받는다.

  python tools/art/char_blender.py --npz mesh.npz --albedo albedo.png --out-glb mesh.glb [--name frost] [--blend out.blend]
(Blender 바깥에서 부르면 스스로 Blender 안에서 다시 돈다.)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz", required=True)
    ap.add_argument("--albedo", required=True)
    ap.add_argument("--out-glb", required=True)
    ap.add_argument("--name", default="char")
    ap.add_argument("--blend")
    a = ap.parse_args(argv)
    import bpy
    import numpy as np
    rc.reset_scene(60)
    d = np.load(a.npz)
    V, T, UV = d["verts"], d["tris"], d["uv"]
    me = bpy.data.meshes.new(a.name)
    me.from_pydata([tuple(v) for v in V], [], [tuple(t) for t in T])
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    uvl.data.foreach_set("uv", UV.reshape(-1, 2).astype(np.float32).reshape(-1))
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.update()
    ob = bpy.data.objects.new(a.name, me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(a.name + "_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(Path(a.albedo).resolve()))
    img.name = a.name + "_albedo"
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    me.materials.append(mat)
    Path(a.out_glb).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=str(a.out_glb), export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False, export_skins=False)
    if a.blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.blend, compress=True)
    print("CHAR_BLENDER_OK vertices", len(V), "triangles", len(T))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
