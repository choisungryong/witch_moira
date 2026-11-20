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


def activate_image_nodes():
    """작업대(Workbench) 렌더용 재질 준비. 큰 텍스처는 활성 이미지 노드로 두고, 8x8 단색 부품 재질(rig_parts)은 흰색으로 나오므로
    이미지 노드를 지우고 표시색(diffuse_color)에 그 색을 넣는다(TEXTURE 모드는 이미지 없는 재질에 표시색을 쓴다)."""
    import bpy
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        for n in list(m.node_tree.nodes):
            if n.type == "TEX_IMAGE" and n.image is not None:
                if max(n.image.size) <= 16:
                    px = [(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in n.image.pixels[:3]]   # 이미지 값(sRGB) -> 선형(표시색 칸은 선형)
                    m.diffuse_color = (px[0], px[1], px[2], 1.0)
                    m.node_tree.nodes.remove(n)
                else:
                    m.node_tree.nodes.active = n


def apply_emission(new_images, mask_path, mode, gain):
    """몸 텍스처(가장 큰 새 이미지)에 발광 가면을 더하거나(add) 가면만 남긴다(only). Blender 이미지는 아래가 먼저이고 선형 색이다.
    게임의 발광은 조명 위에 더해지므로 평면 조명 렌더에서는 단순 더하기로 근사한다(게임 값이 아니다)."""
    import bpy
    import numpy as np
    big = [i for i in new_images if min(i.size) >= 256]
    if not big:
        return
    img = big[0]
    w, h = img.size
    mimg = bpy.data.images.load(str(mask_path), check_existing=False)   # Blender 안에는 PIL이 없다. 이미지는 아래가 먼저·선형 색으로 읽힌다
    mimg.scale(w, h)
    mbuf = np.empty(w * h * 4, np.float32)
    mimg.pixels.foreach_get(mbuf)
    mk = mbuf.reshape(h, w, 4)[..., :3] * gain
    buf = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(buf)
    px = buf.reshape(h, w, 4)
    if mode == "replace":
        px[..., :3] = np.clip(mk, 0, 1)
    elif mode == "add":
        px[..., :3] = np.clip(px[..., :3] + mk, 0, 1)
    else:
        px[..., :3] = np.clip(mk / max(gain, 1e-6), 0, 1)
    img.pixels.foreach_set(px.reshape(-1))
    img.update()
    if mode == "only":   # 부품(단색 재질)은 가면이 없으니 검정
        import bpy
        for m in bpy.data.materials:
            if m.use_nodes and not any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes):
                m.diffuse_color = (0.0, 0.0, 0.0, 1.0)


def load_model(path):
    import bpy
    if str(path).lower().endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=str(path))
        activate_image_nodes()
        return [o for o in bpy.data.objects]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    activate_image_nodes()
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
    ap.add_argument("--emission", action="append", help="game: 모델과 같은 순서의 발광 가면 png(없으면 none). --emission-mode와 함께")
    ap.add_argument("--emission-mode", choices=["off", "add", "only"], default="off",
                    help="game: add = 몸 텍스처에 가면을 더해(발광 근사) 렌더, only = 가면만(원소 자리 면적 재기용)")
    ap.add_argument("--emission-gain", type=float, default=0.9)
    ap.add_argument("--albedo-override", action="append", help="game: 모델과 같은 순서로 몸 텍스처를 이 png로 바꿔 찍는다(재질과 형상을 가르는 시험, 없으면 none)")
    ap.add_argument("--screen-h", type=int, default=1080, help="game: 화면 높이(1080 또는 720). 판 높이 180px가 화면의 몇 분의 몇인지 정한다(720이면 주인공이 2/3 크기)")
    ap.add_argument("--seq", help="game: 동작 연속 렌더 clip:첫프레임:끝프레임(포함). 파일은 out/seq<tag>_NNN.png")
    ap.add_argument("--cam", choices=["game", "side", "front"], default="game", help="game 카메라 각도: 게임(기본) / 측면 / 정면(직교, 키 맞춤)")
    ap.add_argument("--res-mult", type=int, default=1, help="game: 같은 화면 범위를 N배 해상도로(영상용)")
    ap.add_argument("--pose", help="views: 렌더 전에 clip:frame 자세를 잡는다(쉬는 자세가 T자인 몸에 idle 등)")
    ap.add_argument("--bg", help="game: 바탕색 r,g,b (0..1). 기본 어두운 바닥 0.03,0.04,0.045")
    ap.add_argument("--silhouette", action="store_true", help="game: 단색 검정 실루엣을 밝은 바탕에(회색조 판의 실루엣 기준 판)")
    a = ap.parse_args(argv)
    import bpy
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    if a.mode == "game":
        rc.reset_scene(60)
        sc, cam = setup_scene((0.82, 0.82, 0.82) if a.silhouette else (tuple(float(v) for v in a.bg.split(",")) if a.bg else (0.03, 0.04, 0.045)))
        if a.silhouette:
            sc.display.shading.color_type = "SINGLE"
            sc.display.shading.single_color = (0.0, 0.0, 0.0)
        xs = [float(v) for v in a.xs.split(",")] if a.xs else [(-1.3 + 1.3 * i) for i in range(len(a.model))]
        clip, fr = a.game_frame.split(":")
        for mi, (path, x) in enumerate(zip(a.model, xs)):
            acts_before = set(bpy.data.actions)
            imgs_before = set(bpy.data.images)
            objs = load_model(path)
            if a.albedo_override and mi < len(a.albedo_override) and a.albedo_override[mi] != "none":
                apply_emission([i for i in bpy.data.images if i not in imgs_before], a.albedo_override[mi], "replace", 1.0)
            if a.emission_mode != "off" and a.emission and mi < len(a.emission) and a.emission[mi] != "none":
                apply_emission([i for i in bpy.data.images if i not in imgs_before], a.emission[mi], a.emission_mode, a.emission_gain)
            for o in objs:
                if o.parent is None:   # 화면 가로 방향(카메라 오른쪽 = (0.786, 0.618))으로 x미터 옮겨 한 줄로 세운다
                    o.location.x += x * 0.786
                    o.location.y += x * 0.618
            # 모델마다 동작 이름이 같아(run, run.001 ...) 방금 들어온 동작에서 고른다
            rig = next((o for o in objs if o.type == "ARMATURE"), None)
            act = next((x for x in bpy.data.actions if x not in acts_before and (x.name == clip or x.name.startswith(clip + "."))), None)
            if rig is not None and act is not None:
                ad = rig.animation_data_create()
                ad.action = act
                if hasattr(ad, "action_slot") and len(act.slots):
                    ad.action_slot = act.slots[0]
        bpy.context.scene.frame_set(int(fr))
        scale_crop = 24 / a.scale * (180 / a.screen_h)
        from mathutils import Vector
        if a.cam == "game":
            loc = (11, -14, 19)
            tgt = Vector((0, 0, 1.0))
            cam.location = (loc[0], loc[1], loc[2] + 1.0)
            cam.rotation_euler = (tgt - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = scale_crop
        else:   # 측면(캐릭터 왼쪽에서)·정면 직교. 키 2.4 m 범위, 가운데 높이 1.05 m
            if a.cam == "side":
                cam.location, cam.rotation_euler = (10, 0, 1.05), (math.pi / 2, 0, math.pi / 2)
            else:
                cam.location, cam.rotation_euler = (0, -10, 1.05), (math.pi / 2, 0, 0)
            cam.data.ortho_scale = 2.4
        w = 160 * max(2, len(a.model)) * a.res_mult
        hgt = 180 * a.res_mult
        if a.seq:
            sclip, s0, s1 = a.seq.split(":")
            seq_act = None
            for o in bpy.data.objects:
                if o.type == "ARMATURE" and o.animation_data and o.animation_data.action:
                    seq_act = o
            for f in range(int(s0), int(s1) + 1):
                bpy.context.scene.frame_set(f)
                render(sc, out / ("seq%s_%03d.png" % (a.tag, f - int(s0))), w, hgt)
            print("GAME_SEQ_OK")
            return 0
        render(sc, out / ("game_%s%s.png" % (a.game_frame.replace(":", "_"), a.tag)), w, hgt)
        # 배율 4배 확대본은 같은 픽셀을 키운 것(별도 렌더 아님) -> 호출하는 쪽이 만든다
        print("GAME_RENDER_OK")
        return 0
    if not a.model[0].lower().endswith(".blend"):
        rc.reset_scene(60)   # 공장 시작 장면의 기본 상자를 지운다(안 지우면 키 1m 아래를 가린다)
    objs = load_model(a.model[0])
    sc, cam = setup_scene()
    if a.mode == "views":
        if a.pose:
            pc, pf = a.pose.split(":")
            pose_to(pc, int(pf))
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
