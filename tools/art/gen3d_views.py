#!/usr/bin/env python3
"""glb 몇 개를 같은 각도·같은 빛으로 렌더해 한 장 판으로 묶는다(Blender 5.3 Eevee). 줄이기 전후 비교, 뼈대 입힌 모델의 자세 확인에 쓴다.

  python tools/art/gen3d_views.py --model A.glb --label 줄이기전 --model B.glb --label 줄인뒤 --views front,q,side,back,face,hand,legs --out out.png [--size 420]
  --pose-clip run --pose-time 0.15 : 뼈대 있는 glb의 동작 한 순간(초)을 입혀 그린다(없으면 기본 자세)
  --focus-hands : 손 뼈가 아닌 메시 끝점으로 손을 찾는다(기본)
시점: front, q(3/4), side, back, face(머리 정면), faceq(머리 3/4), hand(손 둘레, 캐릭터 오른쪽=-X), legs(치마·다리), torso, top.
행 = 모델, 열 = 시점. 키는 모델마다 다를 수 있어 시점별 화면 높이를 키 비율로 정한다.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402

VIEW_SPEC = {   # (방위각 도, 고도 도, 화면 높이 = 키 x, 타깃 높이 = 키 x)
    "front": (0, 4, 1.12, 0.5), "q": (40, 8, 1.12, 0.5), "side": (90, 4, 1.12, 0.5), "back": (180, 4, 1.12, 0.5),
    "face": (0, 0, 0.26, 0.9), "faceq": (35, 0, 0.26, 0.9), "torso": (0, 0, 0.5, 0.72), "legs": (0, 0, 0.5, 0.42),
    "hand": (0, 0, 0.2, None), "top": (0, 80, 1.0, 0.5), "game": (35, 50, 1.12, 0.5),
}


def render_all(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", required=True)
    ap.add_argument("--label", action="append", default=[])
    ap.add_argument("--views", default="front,q,side,back,face,hand,legs")
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=420)
    ap.add_argument("--pose-clip")
    ap.add_argument("--pose-time", type=float, default=0.0)
    ap.add_argument("--times", help="쉼표로 나눈 동작 시각(초) 여럿: 행 = 시점, 열 = 시각(첫 모델만)")
    ap.add_argument("--tmp")
    a, _ = ap.parse_known_args(argv)
    import bpy
    import mathutils
    import numpy as np
    tmp = Path(a.tmp or (Path(a.out).parent / "_views_tmp"))
    tmp.mkdir(parents=True, exist_ok=True)
    views = a.views.split(",")
    for mi, path in enumerate(a.model):
        rc.reset_scene(30)
        bpy.ops.import_scene.gltf(filepath=path)
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH" and len(o.data.vertices) > 500]   # 뼈 모양 구슬 같은 보조 메시는 뺀다
        arm = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
        times = [float(t) for t in a.times.split(',')] if a.times else [None]
        for o in objs:
            for p in o.data.polygons:
                p.use_smooth = True
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        pts = []
        for o in objs:
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            n = len(me.vertices)
            arr = np.zeros(n * 3)
            me.vertices.foreach_get("co", arr)
            arr = arr.reshape(-1, 3)
            M = np.array(o.matrix_world)
            pts.append(arr @ M[:3, :3].T + M[:3, 3])
            ev.to_mesh_clear()
        P = np.concatenate(pts)
        mn, mx = P.min(0), P.max(0)
        H = float(mx[2] - mn[2])
        cx = float((mx[0] + mn[0]) / 2)
        cy = float((mx[1] + mn[1]) / 2)
        if arm and a.pose_clip and a.pose_clip in bpy.data.actions:
            act = bpy.data.actions[a.pose_clip]
            arm.animation_data_create().action = act
            if hasattr(arm.animation_data, "action_slot") and len(act.slots):
                arm.animation_data.action_slot = act.slots[0]
            bpy.context.scene.frame_set(int(round(a.pose_time * bpy.context.scene.render.fps)))
        bpy.context.view_layer.update()
        sc = bpy.context.scene
        eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
        sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in eng else "BLENDER_EEVEE"
        sc.render.resolution_x = a.size
        sc.render.resolution_y = int(a.size * 1.25)
        w = bpy.data.worlds.new("w")
        sc.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (.45, .45, .47, 1)
        w.node_tree.nodes["Background"].inputs[1].default_value = 1.3
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 2.5
        sun.rotation_euler = (math.radians(55), 0, math.radians(30))
        sc.collection.objects.link(sun)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam.data.type = "ORTHO"
        # 손: 캐릭터 오른쪽(-X) 끝점 둘레
        m = (P[:, 2] > mn[2] + 0.25 * H) & (P[:, 0] < cx)
        idx = np.where(m)[0]
        hand = P[idx[np.argsort(P[idx, 0])[:max(30, len(idx) // 200)]]].mean(axis=0)
        for ti, tm in enumerate(times):
            if tm is not None and arm and a.pose_clip in bpy.data.actions:
                bpy.context.scene.frame_set(int(round(tm * bpy.context.scene.render.fps)))
                bpy.context.view_layer.update()
                dg2 = bpy.context.evaluated_depsgraph_get()
                q = []
                for o in objs:
                    ev = o.evaluated_get(dg2)
                    me2 = ev.to_mesh()
                    arr = np.zeros(len(me2.vertices) * 3)
                    me2.vertices.foreach_get("co", arr)
                    arr = arr.reshape(-1, 3)
                    M = np.array(o.matrix_world)
                    q.append(arr @ M[:3, :3].T + M[:3, 3])
                    ev.to_mesh_clear()
                Q = np.concatenate(q)
                cx = float((Q[:, 0].max() + Q[:, 0].min()) / 2)      # 걸음 따라 몸이 앞뒤로 흔들려도 화면 가운데에 둔다
                cy = float((Q[:, 1].max() + Q[:, 1].min()) / 2)
            for v in views:
                az, el, hs, tz = VIEW_SPEC[v]
                tgt = mathutils.Vector((cx, cy, mn[2] + H * tz)) if tz is not None else mathutils.Vector(tuple(hand))
                cam.data.ortho_scale = H * hs * 0.8
                r, azr, elr = H * 4, math.radians(az), math.radians(el)
                d = mathutils.Vector((math.sin(azr) * math.cos(elr), -math.cos(azr) * math.cos(elr), math.sin(elr))) * r
                cam.location = tgt + d
                cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
                sc.render.filepath = str(tmp / ("m%d_%s%s.png" % (mi, v, "" if tm is None else "_t%d" % ti)))
                bpy.ops.render.render(write_still=True)
    return 0


def montage(a):
    from PIL import Image, ImageDraw
    views = a.views.split(",")
    if a.times:
        tl = a.times.split(",")
        tmp = Path(a.tmp or (Path(a.out).parent / "_views_tmp"))
        W, Hh = a.size, int(a.size * 1.25)
        sheet = Image.new("RGB", (W * len(tl), Hh * len(views)), (115, 115, 120))
        dr = ImageDraw.Draw(sheet)
        for vi, v in enumerate(views):
            for ti, t in enumerate(tl):
                sheet.paste(Image.open(tmp / ("m0_%s_t%d.png" % (v, ti))).convert("RGB"), (ti * W, vi * Hh))
                dr.text((ti * W + 6, vi * Hh + 4), "%s %ss" % (v, t), fill=(255, 255, 0))
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        sheet.save(a.out)
        print("VIEWS", a.out, sheet.size)
        return
    tmp = Path(a.tmp or (Path(a.out).parent / "_views_tmp"))
    W = a.size
    Hh = int(a.size * 1.25)
    sheet = Image.new("RGB", (W * len(views), Hh * len(a.model)), (115, 115, 120))
    dr = ImageDraw.Draw(sheet)
    for mi in range(len(a.model)):
        for vi, v in enumerate(views):
            im = Image.open(tmp / ("m%d_%s.png" % (mi, v))).convert("RGB")
            sheet.paste(im, (vi * W, mi * Hh))
        lab = a.label[mi] if mi < len(a.label) else Path(a.model[mi]).name
        dr.text((8, mi * Hh + 6), lab, fill=(255, 255, 0))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print("VIEWS", a.out, sheet.size)


def main(argv):
    return render_all(argv)


if __name__ == "__main__":
    if rc.have_bpy():
        sys.exit(render_all(rc.script_args()))
    code = rc.relaunch(__file__)
    if code == 0:
        ap = argparse.ArgumentParser()
        ap.add_argument("--model", action="append")
        ap.add_argument("--label", action="append", default=[])
        ap.add_argument("--views", default="front,q,side,back,face,hand,legs")
        ap.add_argument("--out")
        ap.add_argument("--size", type=int, default=420)
        ap.add_argument("--pose-clip")
        ap.add_argument("--pose-time", type=float, default=0.0)
        ap.add_argument("--times")
        ap.add_argument("--tmp")
        a, _ = ap.parse_known_args(sys.argv[1:])
        montage(a)
    sys.exit(code)
