"""Blender 안에서 도는 몸통 일(gen3d_mixamo_pack.py가 부른다). 직접 부르지 않는다.

  blender -b -P tools/art/gen3d_mixamo_blender.py -- <config.json> <out.glb> <report.json>

몸 FBX(뼈대 붙음)와 동작 FBX들을 읽어 동작 이름을 논리 이름으로 붙이고, 제자리로 만들 동작은 엉덩이 뼈의 수평 이동 추세를 지우고,
프레임 범위가 있으면 그 구간만 남기고(0초부터), 질감 두 장(색·법선)을 단 하나의 머티리얼(금속 0, 거칠기 설정값)로 입힌 glb 한 개를 낸다.
몸의 쉬는 자세(A자)와 동작 FBX의 쉬는 자세(T자)가 다르므로 동작의 뼈 회전을 그대로 옮기지 않고, 뼈마다 세계 방향이 동작과 같아지게 옮긴다
(retarget_rest, 설정 rest_retarget=false로 끄면 옛 방식: 뼈 이름으로 회전 복사). report.json에는 동작마다 길이(초), 엉덩이 수평 이동, 지면 속도 추정, 오른손 뻗음·머리 흔들림 정점 시각을 적는다.
"""
import json
import math
import sys

import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
cfg = json.load(open(argv[0], encoding="utf-8"))
out_glb, out_report = argv[1], argv[2]
HIPS = cfg.get("hips_bone", "mixamorig:Hips")
FPS = int(cfg.get("fps", 30))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=cfg["body"], automatic_bone_orientation=False)
arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
sc = bpy.context.scene
sc.render.fps = FPS
if not arm.animation_data:
    arm.animation_data_create()


def make_material():
    mat = bpy.data.materials.new(cfg.get("material_name", "hero_body"))
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    color = nt.nodes.new("ShaderNodeTexImage")
    color.image = bpy.data.images.load(cfg["texture_color"])
    color.image.colorspace_settings.name = "sRGB"
    nt.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    if cfg.get("texture_normal"):
        normal = nt.nodes.new("ShaderNodeTexImage")
        normal.image = bpy.data.images.load(cfg["texture_normal"])
        normal.image.colorspace_settings.name = "Non-Color"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(normal.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = float(cfg.get("metallic", 0.0))
    bsdf.inputs["Roughness"].default_value = float(cfg.get("roughness", 0.8))
    return mat


mat = make_material()
for m in meshes:
    m.data.materials.clear()
    m.data.materials.append(mat)

hips_pb = arm.pose.bones[HIPS]
hips_rest3 = hips_pb.bone.matrix_local.to_3x3()
world3 = arm.matrix_world.to_3x3()


def wpos(pb):
    return arm.matrix_world @ pb.head


def bone(name):
    return arm.pose.bones.get(name)


def assign(act):
    ad = arm.animation_data
    ad.action = act
    if hasattr(ad, "action_slot") and act.slots:
        ad.action_slot = act.slots[0]


def facing_axis():
    """몸이 바라보는 수평 방향(발끝 - 발목)의 평균. 동작을 얹기 전의 쉬는 자세에서 한 번만 잰다."""
    d = mathutils.Vector((0, 0, 0))
    for side in ("Left", "Right"):
        foot, toe = bone("mixamorig:%sFoot" % side), bone("mixamorig:%sToeBase" % side)
        if foot and toe:
            d += wpos(toe) - wpos(foot)
    d.z = 0
    return d.normalized() if d.length > 1e-6 else mathutils.Vector((0, -1, 0))


def strip_trend(f0, f1):
    """엉덩이 수평 이동의 직선 추세(시작 프레임 → 끝 프레임)를 지운다. 좌우 흔들림은 남는다."""
    sc.frame_set(f0)
    bpy.context.view_layer.update()
    h0 = wpos(hips_pb)
    sc.frame_set(f1)
    bpy.context.view_layer.update()
    h1 = wpos(hips_pb)
    trend = h1 - h0
    trend.z = 0
    if trend.length < 1e-4:
        return 0.0
    n = max(1, f1 - f0)
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        d_world = trend * ((f - f0) / n)
        d_arm = world3.inverted() @ d_world
        d_loc = hips_rest3.inverted() @ d_arm
        hips_pb.location = hips_pb.location - d_loc
        hips_pb.keyframe_insert("location", frame=f)
    return trend.length


def measure(f0, f1, clip_speed=None):
    """엉덩이 수평 이동, 지면 속도(디딘 발이 엉덩이 기준으로 뒤로 가는 속도), 오른손 뻗음·머리 흔들림 정점 프레임."""
    face = FACE
    rec = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        row = {"f": f, "hips": wpos(hips_pb).copy()}
        for key, name in (("rh", "mixamorig:RightHand"), ("head", "mixamorig:Head"), ("lf", "mixamorig:LeftFoot"), ("rf", "mixamorig:RightFoot"), ("lt", "mixamorig:LeftToeBase"), ("rt", "mixamorig:RightToeBase")):
            pb = bone(name)
            row[key] = wpos(pb).copy() if pb else None
        rec.append(row)
    dt = 1.0 / FPS
    hxy = [(r["hips"].x, r["hips"].y) for r in rec]
    span = max(math.dist(a, b) for a in hxy for b in hxy)
    # 지면 속도: 디딘 프레임(발 높이가 그 발의 최저 + 한계 이하)에서 발이 엉덩이 기준으로 뒤로 가는 속도의 평균
    def ground_speed(keys, margin):
        speeds = []
        for key in keys:
            zs = [r[key].z for r in rec]
            zmin = min(zs)
            for a, b in zip(rec, rec[1:]):
                if a[key].z < zmin + margin and b[key].z < zmin + margin:
                    ra = (a[key] - a["hips"]).dot(face)
                    rb = (b[key] - b["hips"]).dot(face)
                    speeds.append(-(rb - ra) / dt)
        return (sum(speeds) / len(speeds), len(speeds)) if speeds else (None, 0)

    ground, gn = ground_speed(("lf", "rf"), 0.04)
    ground_toe, tn = ground_speed(("lt", "rt"), 0.03)
    speed_profile = [round(math.dist(a, b) / dt, 3) for a, b in zip(hxy, hxy[1:])]
    reach = max(rec, key=lambda r: ((r["rh"] - r["hips"]).x ** 2 + (r["rh"] - r["hips"]).y ** 2) if r["rh"] else 0)
    h0 = rec[0]["head"] - rec[0]["hips"]
    sway = max(rec, key=lambda r: (r["head"] - r["hips"] - h0).length if r["head"] else 0)
    rh_rel = [(r["rh"] - r["hips"]) for r in rec]
    hand_speed = [round((b - a).length / dt, 3) for a, b in zip(rh_rel, rh_rel[1:])]
    head_dev = [round((r["head"] - r["hips"] - h0).length, 4) for r in rec]
    slip = None
    if clip_speed:
        diffs = []
        for key in ("lt", "rt"):
            zmin = min(r[key].z for r in rec)
            for a, b in zip(rec, rec[1:]):
                if a[key].z < zmin + 0.03 and b[key].z < zmin + 0.03:
                    ra = (a[key] - a["hips"]).dot(face)
                    rb = (b[key] - b["hips"]).dot(face)
                    diffs.append(-(rb - ra) / dt - clip_speed)
        slip = round(math.sqrt(sum(d * d for d in diffs) / len(diffs)), 4) if diffs else None
    return {
        "hand_speed_mps": hand_speed,
        "head_dev_m": head_dev,
        "stance_slip_rms_mps": slip,
        "hips_span_m": round(span, 4),
        "ground_speed_mps": round(ground, 4) if ground is not None else None,
        "ground_samples": gn,
        "ground_speed_toe_mps": round(ground_toe, 4) if ground_toe is not None else None,
        "hips_speed_profile_mps": speed_profile,
        "hand_reach_frame": reach["f"],
        "head_sway_frame": sway["f"],
        "hips_height_start_m": round(rec[0]["hips"].z, 4),
        "hips_height_mean_m": round(sum(r["hips"].z for r in rec) / len(rec), 4),
    }


def depth(pb):
    d = 0
    while pb.parent:
        pb = pb.parent
        d += 1
    return d


def sample_clip_pose(carm, f0, f1):
    """동작 FBX 자신의 뼈대로 재생한 뼈마다의 자세(뼈대 공간 3x3)를 프레임마다 읽어 둔다."""
    out = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        out[f] = {pb.name: pb.matrix.to_3x3().normalized() for pb in carm.pose.bones}
    return out


def retarget_rest(carm, clip_pose, f0, f1):
    """몸 뼈대(A자 쉬는 자세)에 동작 뼈대(T자 쉬는 자세)의 동작을 얹는다.
    뼈마다 W = D @ S @ Rbody. D = 동작이 쉬는 자세에서 얼마나 돌았나(세계 회전), S = 몸 뼈의 쉬는 방향을 동작 뼈의 쉬는 방향으로 보내는 최단 회전.
    그러면 W의 뼈 방향 = 동작 뼈의 그 순간 방향이다(팔이 T자에서 내려온 만큼 A자에서 더 안쪽으로 돌지 않는다).
    부모부터 W를 정해 가며 뼈 자기 회전(rotation_quaternion)을 거꾸로 풀어 키로 넣는다. 위치 채널(엉덩이 이동)은 그대로 둔다."""
    order = sorted(arm.pose.bones, key=depth)
    rb = {pb.name: arm.data.bones[pb.name].matrix_local.to_3x3().normalized() for pb in order}
    rc = {pb.name: carm.data.bones[pb.name].matrix_local.to_3x3().normalized() for pb in order if pb.name in carm.data.bones}
    shortest = {n: rb[n].col[1].rotation_difference(rc[n].col[1]).to_matrix() for n in rc}
    prev = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        want = {}
        for pb in order:
            n = pb.name
            if n in rc and n in clip_pose[f]:
                want[n] = (clip_pose[f][n] @ rc[n].inverted()) @ shortest[n] @ rb[n]
            else:
                par = want[pb.parent.name] if pb.parent else mathutils.Matrix.Identity(3)
                rel = (rb[pb.parent.name].inverted() @ rb[n]) if pb.parent else rb[n]
                want[n] = par @ rel @ pb.rotation_quaternion.to_matrix()
            par = want[pb.parent.name] if pb.parent else mathutils.Matrix.Identity(3)
            rel = (rb[pb.parent.name].inverted() @ rb[n]) if pb.parent else rb[n]
            q = ((par @ rel).inverted() @ want[n]).to_quaternion()
            if n in prev and prev[n].dot(q) < 0:
                q.negate()
            prev[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)


report = {"body": cfg["body"], "clips": {}}
mn = mathutils.Vector((1e9,) * 3)
mx = mathutils.Vector((-1e9,) * 3)
for m in meshes:
    for c in m.bound_box:
        p = m.matrix_world @ mathutils.Vector(c)
        mn = mathutils.Vector(map(min, mn, p))
        mx = mathutils.Vector(map(max, mx, p))
report["body_height_m"] = round((mx - mn).z, 4)

FACE = facing_axis()
actions = {}
for clip in cfg["clips"]:
    before = set(bpy.data.actions)
    before_objs = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=clip["fbx"], automatic_bone_orientation=False)
    new = [a for a in bpy.data.actions if a not in before]
    carm = [o for o in bpy.context.scene.objects if o not in before_objs and o.type == "ARMATURE"]
    if not new:
        raise SystemExit("no action in " + clip["fbx"])
    act = new[0]
    act.name = clip["name"]
    sc.render.fps = FPS
    a0, a1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
    f0, f1 = (int(clip["frames"][0]), int(clip["frames"][1])) if clip.get("frames") else (a0, a1)
    clip_pose = None
    if cfg.get("rest_retarget", True) and carm:
        if not carm[0].animation_data:
            carm[0].animation_data_create()
        carm[0].animation_data.action = act
        if hasattr(carm[0].animation_data, "action_slot") and act.slots:
            carm[0].animation_data.action_slot = act.slots[0]
        clip_pose = sample_clip_pose(carm[0], f0, f1)
    assign(act)
    if clip_pose is not None:
        retarget_rest(carm[0], clip_pose, f0, f1)
    for o in list(bpy.context.scene.objects):
        if o not in before_objs:
            bpy.data.objects.remove(o, do_unlink=True)
    info = {"fbx": clip["fbx"].split("/")[-1], "source_frames": [a0, a1], "used_frames": [f0, f1]}
    if clip.get("in_place"):
        info["trend_removed_m"] = round(strip_trend(f0, f1), 4)
    info.update(measure(f0, f1, clip.get("ground_speed_mps")))
    info["length_s"] = round((f1 - f0) / FPS, 5)
    report["clips"][clip["name"]] = info
    actions[clip["name"]] = (act, f0, f1)

arm.animation_data.action = None
for clip in cfg["clips"]:
    act, f0, f1 = actions[clip["name"]]
    tr = arm.animation_data.nla_tracks.new()
    tr.name = clip["name"]
    strip = tr.strips.new(clip["name"], f0, act)
    if hasattr(strip, "action_slot") and act.slots:
        strip.action_slot = act.slots[0]
    strip.action_frame_start = f0
    strip.action_frame_end = f1
    strip.frame_start = 1
    strip.use_sync_length = False

for o in bpy.context.scene.objects:
    o.select_set(False)
bpy.ops.export_scene.gltf(
    filepath=out_glb, export_format="GLB", export_yup=True, export_apply=False, export_skins=True,
    export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
    export_anim_slide_to_zero=True, export_optimize_animation_size=False, export_frame_step=1,
    export_image_format="AUTO", export_materials="EXPORT", export_normals=True, export_tangents=False,
)
json.dump(report, open(out_report, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print("PACK_DONE", out_glb)
