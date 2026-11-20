#!/usr/bin/env python3
"""기본 몸(Quaternius Universal Base Characters 같은 사람 몸 glTF)을 열어 점검하고, 같은 뼈대의 동작 묶음(UAL glb)의 동작을 붙여 .blend로 저장한다(Blender 5.3).

  python tools/art/base_prep.py --body body.gltf --actions ual.glb --out-blend body_ual.blend --report report.json
보고서: 메시(삼각형 수, 정점, 재질, UV), 키(H), 뼈 수와 이름, 키 대비 비율(팔·다리·어깨폭·골반폭), 팔꿈치·무릎 가중치 섞임 폭.
몸의 뼈대와 동작 묶음의 뼈대가 같은 이름이면 동작이 그대로 맞는다(동작은 뼈 이름으로 묶인다). 내려받은 파일은 믿을 수 없는 데이터로 다룬다: 경로만 받고 그 폴더에 아무것도 쓰지 않는다.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def main(argv):
    import bpy
    import numpy as np
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True)
    ap.add_argument("--actions")
    ap.add_argument("--out-blend")
    ap.add_argument("--out-glb", help="몸 + 모든 동작을 glb로(char_render가 읽는다)")
    ap.add_argument("--report", required=True)
    a = ap.parse_args(argv)
    rc.reset_scene(60)
    bpy.ops.import_scene.gltf(filepath=a.body)
    objs = list(bpy.data.objects)
    arm = next(o for o in objs if o.type == "ARMATURE")
    for o in [o for o in objs if o.type == "MESH" and len(o.vertex_groups) == 0]:   # 뼈에 안 묶인 보조 물체(구 등)는 지운다
        bpy.data.objects.remove(o, do_unlink=True)
    objs = list(bpy.data.objects)
    meshes = [o for o in objs if o.type == "MESH"]
    rep = {"objects": [(o.type, o.name) for o in objs]}
    allv = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
    H = float(allv[:, 2].max() - allv[:, 2].min())
    rep["height_m"] = H
    rep["bbox"] = [allv.min(0).tolist(), allv.max(0).tolist()]
    rep["meshes"] = []
    for o in meshes:
        o.data.calc_loop_triangles()
        rep["meshes"].append({"name": o.name, "tris": len(o.data.loop_triangles), "verts": len(o.data.vertices), "uv_layers": [u.name for u in o.data.uv_layers],
                              "materials": [m.name for m in o.data.materials], "vertex_groups": len(o.vertex_groups)})
    rep["tris_total"] = sum(m["tris"] for m in rep["meshes"])
    bones = {b.name: (np.array(b.head_local), np.array(b.tail_local), b.parent.name if b.parent else None) for b in arm.data.bones}
    rep["bones"] = len(bones)
    rep["bone_names"] = list(bones)
    g = lambda n: bones[n][0]
    z0 = float(allv[:, 2].min())
    rep["ratios_vs_H"] = {
        "shoulder_width_joint": float(abs(g("upperarm_l")[0] - g("upperarm_r")[0]) / H),
        "hip_width_joint": float(abs(g("thigh_l")[0] - g("thigh_r")[0]) / H),
        "upper_arm": float(np.linalg.norm(g("lowerarm_l") - g("upperarm_l")) / H),
        "forearm": float(np.linalg.norm(g("hand_l") - g("lowerarm_l")) / H),
        "arm_joint_to_hand": float((np.linalg.norm(g("lowerarm_l") - g("upperarm_l")) + np.linalg.norm(g("hand_l") - g("lowerarm_l"))) / H),
        "thigh": float(np.linalg.norm(g("calf_l") - g("thigh_l")) / H),
        "calf": float(np.linalg.norm(g("foot_l") - g("calf_l")) / H),
        "hip_height": float((g("thigh_l")[2] - z0) / H),
        "neck_height": float((g("neck_01")[2] - z0) / H),
        "pelvis_to_neck": float((g("neck_01")[2] - g("pelvis")[2]) / H),
    }
    if a.actions:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=a.actions)
        new = [o for o in bpy.data.objects if o not in before]
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        for act in bpy.data.actions:
            act.use_fake_user = True
        rep["actions"] = sorted(x.name for x in bpy.data.actions)
        ad = arm.animation_data_create()
        act = bpy.data.actions.get("Jog_Fwd_Loop")
        if act:
            ad.action = act
            if hasattr(ad, "action_slot") and len(act.slots):
                ad.action_slot = act.slots[0]
    if a.out_glb:
        rc.export_glb(a.out_glb, arm, meshes, fps=60)
    if a.out_blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.out_blend, compress=True)
    rc.write_json(a.report, rep)
    print("BASE_PREP tris %d bones %d H %.3f" % (rep["tris_total"], rep["bones"], H), {k: round(v, 3) for k, v in rep["ratios_vs_H"].items()})
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
