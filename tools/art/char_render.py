#!/usr/bin/env python3
"""char_from_sheets 결과를 같은 조건으로 렌더한다(Blender 작업대 엔진, 평면 조명 + 텍스처 색. 게임 화면이 아니다).

  views : 원본 그림과 같은 틀(px/m, 중심)로 정사영 렌더 -> 원본과 나란히 놓기 쉽다
          python tools/art/char_render.py views --model final.glb --views views.json --out DIR [--tag v2]
          views.json = [{"name":"front","az":0,"s":715.6,"cx":511,"cy":1469,"w":1024,"h":1536}, ...]
  poses : 동작 장면 렌더(3/4 카메라) --clip run --frames 0,4,9,13   (모델이 .blend이고 동작이 이름으로 들어 있어야 한다)
  game  : 게임 카메라 조건(직교, Godot 오프셋 (11,19,14) -> Blender (11,-14,19), 크기 24, 배율 1.32, 1080p 화면 밀도) 320x180 렌더.
          --model 여러 개(왼쪽부터) --labels는 파일 이름만 쓴다. 가장자리 배율은 --scale(기본 1.32)
(Blender 바깥에서 부르면 스스로 Blender 안에서 다시 돈다.)
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402


def setup_scene(bg=(0.44, 0.44, 0.45), light="FLAT"):
    import bpy
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = light
    sh.color_type = "TEXTURE"
    sh.show_object_outline = False
    sc.render.film_transparent = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.color = bg
    sc.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.sensor_fit = "VERTICAL"
    return sc, cam


def load_model(path):
    import bpy
    if str(path).lower().endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=str(path))
        return [o for o in bpy.data.objects]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def view_cam(cam, az, s, cx, cy, w, h):
    """원점(발 아래 중심)이 그림 (cx, cy) 에 오도록 정사영 카메라를 놓는다."""
    a = math.radians(az)
    d = (math.sin(a), -math.cos(a), 0.0)
    r = (math.cos(a), math.sin(a), 0.0)
    # 원점이 그림 cx에, 그림 중심이 w/2에 있다: 중심 = 원점 + r*(w/2-cx)/s, 높이는 (cy-h/2)/s
    center = (r[0] * (w / 2 - cx) / s, r[1] * (w / 2 - cx) / s, (cy - h / 2) / s)
    cam.location = (center[0] + d[0] * 10, center[1] + d[1] * 10, center[2])
    cam.rotation_euler = (math.pi / 2, 0, a)
    cam.data.ortho_scale = h / s


def render(sc, path, w, h):
    import bpy
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def pose_to(clip, frame):
    import bpy
    rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if rig is None:
        return
    act = bpy.data.actions.get(clip)
    if act is None:
        return
    if rig.animation_data is None:
        rig.animation_data_create()
    for t in rig.animation_data.nla_tracks:
        t.mute = True
    rig.animation_data.action = act
    bpy.context.scene.frame_set(frame)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["views", "poses", "game"])
    ap.add_argument("--model", action="append", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--views")
    ap.add_argument("--tag", default="")
    ap.add_argument("--clip")
    ap.add_argument("--frames", default="0")
    ap.add_argument("--az", type=float, default=-35)
    ap.add_argument("--scale", type=float, default=1.32)
    ap.add_argument("--xs", help="game: 모델별 x 위치(쉼표). 기본 모델 순서대로 -1.3, 0, 1.3 ...")
    ap.add_argument("--game-frame", default="idle:0")
    a = ap.parse_args(argv)
    import bpy
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    if a.mode == "game":
        rc.reset_scene(60)
        sc, cam = setup_scene((0.03, 0.04, 0.045))
        xs = [float(v) for v in a.xs.split(",")] if a.xs else [(-1.3 + 1.3 * i) for i in range(len(a.model))]
        for path, x in zip(a.model, xs):
            objs = load_model(path)
            for o in objs:
                if o.parent is None:
                    o.location.x += x
        clip, fr = a.game_frame.split(":")
        pose_to(clip, int(fr))
        scale_crop = 24 / a.scale * (180 / 1080)
        loc = (11, -14, 19)
        from mathutils import Vector
        tgt = Vector((0, 0, 1.0))
        cam.location = (loc[0], loc[1], loc[2] + 1.0)
        cam.rotation_euler = (tgt - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = scale_crop
        w = 160 * max(2, len(a.model))
        render(sc, out / ("game_%s%s.png" % (a.game_frame.replace(":", "_"), a.tag)), w, 180)
        # 배율 4배 확대본은 같은 픽셀을 키운 것(별도 렌더 아님) -> 호출하는 쪽이 만든다
        print("GAME_RENDER_OK")
        return 0
    if not a.model[0].lower().endswith(".blend"):
        rc.reset_scene(60)   # 공장 시작 장면의 기본 상자를 지운다(안 지우면 키 1m 아래를 가린다)
    objs = load_model(a.model[0])
    sc, cam = setup_scene()
    if a.mode == "views":
        for v in json.loads(Path(a.views).read_text(encoding="utf-8")):
            view_cam(cam, v["az"], v["s"], v["cx"], v["cy"], v["w"], v["h"])
            render(sc, out / ("%s%s.png" % (v["name"], a.tag)), v["w"], v["h"])
    else:
        frames = [int(f) for f in a.frames.split(",")]
        for f in frames:
            pose_to(a.clip, f)
            ang = math.radians(a.az)
            h = 1.1
            cam.location = (10 * math.sin(ang), -10 * math.cos(ang), h)
            cam.rotation_euler = (math.pi / 2, 0, ang)
            cam.data.ortho_scale = 2.3
            render(sc, out / ("pose_%s_%d%s.png" % (a.clip, f, a.tag)), 384, 576)
    print("CHAR_RENDER_OK")
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
