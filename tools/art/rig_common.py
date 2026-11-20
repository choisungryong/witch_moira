#!/usr/bin/env python3
"""3D 캐릭터 도구 묶음(rig_build / rig_clips / rig_parts)의 공용 모듈. 따로 돌리지 않는다.

Blender 안에서만 도는 부분(bpy가 필요한 함수)과 Blender 없이 도는 부분(설정 읽기·인수·보고서)이 한 파일에 있다.
Blender 바깥에서 rig_build.py 같은 진입 스크립트를 부르면 `blender --background --python <스크립트> -- <인수>`로 자기를 다시 부른다.
Blender 경로: 환경변수 BLENDER_EXE, 없으면 D:/Blender Foundation/Blender 5.3/blender.exe.

좌표 약속(Blender 안): Z가 위, 정면이 -Y, 캐릭터의 왼쪽(`_l`)이 +X. glTF로 내보내면 정면이 +Z가 된다(게임이 기대하는 방향).
단위는 미터. 뼈대는 게임이 기대하는 뼈 이름을 쓴다(docs/reviews/3D-GEN-TOOLS-20261117.ko.md 1.2절).
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
BLENDER_DEFAULT = "D:/Blender Foundation/Blender 5.3/blender.exe"

# 게임이 기대하는 뼈 이름 24개(origin 하나, 몸통, 팔·다리 4+4, 지팡이 자리 빈 뼈 하나).
BONE_ORDER = [
    "origin", "pelvis_cr", "spine_cr_01", "spine_cr_02", "spine_cr_03", "neck_cr", "head_cr",
    "shoulder_cr_l", "upper_arm_cr_l", "forearm_cr_l", "hand_cr_l",
    "shoulder_cr_r", "upper_arm_cr_r", "forearm_cr_r", "hand_cr_r", "finger_middle.01.r",
    "thigh_cr_l", "shin_cr_l", "tarsal_cr_l", "toe_cr_l",
    "thigh_cr_r", "shin_cr_r", "tarsal_cr_r", "toe_cr_r",
]
BONE_PARENT = {
    "origin": None, "pelvis_cr": "origin", "spine_cr_01": "pelvis_cr", "spine_cr_02": "spine_cr_01", "spine_cr_03": "spine_cr_02",
    "neck_cr": "spine_cr_03", "head_cr": "neck_cr",
    "shoulder_cr_l": "spine_cr_03", "upper_arm_cr_l": "shoulder_cr_l", "forearm_cr_l": "upper_arm_cr_l", "hand_cr_l": "forearm_cr_l",
    "shoulder_cr_r": "spine_cr_03", "upper_arm_cr_r": "shoulder_cr_r", "forearm_cr_r": "upper_arm_cr_r", "hand_cr_r": "forearm_cr_r",
    "finger_middle.01.r": "hand_cr_r",
    "thigh_cr_l": "pelvis_cr", "shin_cr_l": "thigh_cr_l", "tarsal_cr_l": "shin_cr_l", "toe_cr_l": "tarsal_cr_l",
    "thigh_cr_r": "pelvis_cr", "shin_cr_r": "thigh_cr_r", "tarsal_cr_r": "shin_cr_r", "toe_cr_r": "tarsal_cr_r",
}
NO_WEIGHT_BONES = ("origin", "finger_middle.01.r")
CLIP_NAMES = ["idle", "run", "cast", "hit", "death", "dodge"]


# ------------------------------------------------------------------ Blender 호출

def have_bpy() -> bool:
    try:
        import bpy  # noqa: F401
        return True
    except ImportError:
        return False


def blender_exe() -> str:
    return os.environ.get("BLENDER_EXE", BLENDER_DEFAULT)


def relaunch(script: str) -> int:
    """Blender 바깥에서 불렸을 때: 같은 스크립트를 Blender 안에서 다시 돌린다."""
    exe = blender_exe()
    if not Path(exe).is_file():
        print("Blender를 찾지 못했다: %s (환경변수 BLENDER_EXE로 지정)" % exe, file=sys.stderr)
        return 2
    cmd = [exe, "--background", "--factory-startup", "--python", str(Path(script).resolve()), "--"] + sys.argv[1:]
    return subprocess.call(cmd)


def script_args() -> list[str]:
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return sys.argv[1:]


def entry(script: str, main) -> None:
    if not have_bpy():
        sys.exit(relaunch(script))
    sys.exit(main(script_args()) or 0)


# ------------------------------------------------------------------ 설정

def deep_merge(base: dict, over: dict) -> dict:
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config(path: str | None) -> dict:
    """기본 설정(rig_configs/default.json) 위에 사용자 설정을 덮는다. 모르는 키는 그대로 둔다(경고하지 않음)."""
    base = json.loads((HERE / "rig_configs" / "default.json").read_text(encoding="utf-8"))
    if path:
        base = deep_merge(base, json.loads(Path(path).read_text(encoding="utf-8")))
    return base


def write_json(path: str | Path, data) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def read_json(path: str | Path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


# ------------------------------------------------------------------ Blender 안: 장면·메시

def reset_scene(fps: int = 60) -> None:
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps
    bpy.context.scene.render.fps_base = 1.0


def import_any(path: str) -> None:
    import bpy
    ext = Path(path).suffix.lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        raise SystemExit("모르는 형식: " + ext)


def single_mesh_from_import(cfg: dict):
    """가져온 것 가운데 메시만 남겨 월드 좌표로 구워 한 덩어리로 합친다. 뼈대·동작·가중치·모양 키·보조 물체는 버린다."""
    import bpy
    mc = cfg["mesh"]
    keep = []
    for o in list(bpy.data.objects):
        if o.type == "MESH" and len(o.data.vertices) >= mc["min_vertices"] and o.name not in mc["drop_names"]:
            keep.append(o)
    if not keep:
        raise SystemExit("메시가 없다(정점 %d 이상인 메시 0개)" % mc["min_vertices"])
    for o in keep:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.vertex_groups.clear()
        if o.data.shape_keys:
            o.shape_key_clear()
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    if len(keep) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data
    import mathutils
    if mc["facing"] == "+Y":
        me.transform(mathutils.Matrix.Rotation(math.pi, 4, "Z"))
    elif mc["facing"] == "+X":
        me.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, "Z"))   # +X를 보는 모델을 -Y로
    elif mc["facing"] == "-X":
        me.transform(mathutils.Matrix.Rotation(-math.pi / 2, 4, "Z"))
    obj.name = "body"
    me.name = "body"
    return obj


def mesh_coords(obj):
    import numpy as np
    me = obj.data
    arr = np.zeros(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", arr)
    return arr.reshape(-1, 3)


def mesh_edges(obj):
    import numpy as np
    me = obj.data
    arr = np.zeros(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", arr)
    return arr.reshape(-1, 2)


def triangle_count(obj) -> int:
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# ------------------------------------------------------------------ 뼈대 정보와 자세 풀이

class Rig:
    """뼈대 하나의 쉬는 자세 정보. 모든 행렬은 뼈대(armature) 공간, 단위 미터."""

    def __init__(self, arm_obj):
        import mathutils
        self.arm = arm_obj
        data = arm_obj.data
        names = [b.name for b in data.bones]

        def depth(n):
            d, b = 0, data.bones[n]
            while b.parent:
                d, b = d + 1, b.parent
            return d
        self.order = sorted(names, key=lambda n: (depth(n), names.index(n)))
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in data.bones}
        self.rest = {b.name: b.matrix_local.copy() for b in data.bones}
        self.head = {b.name: b.head_local.copy() for b in data.bones}
        self.tail = {b.name: b.tail_local.copy() for b in data.bones}
        self.rel = {}
        for n in self.order:
            p = self.parent[n]
            self.rel[n] = (self.rest[p].inverted() @ self.rest[n]) if p else self.rest[n].copy()
        self.rest_rot = {n: self.rest[n].to_3x3() for n in self.order}
        self.rest_dir = {n: (self.tail[n] - self.head[n]).normalized() for n in self.order}
        self.length = {n: (self.tail[n] - self.head[n]).length for n in self.order}
        self.Matrix = mathutils.Matrix

    def solver(self) -> "PoseSolver":
        return PoseSolver(self)


class PoseSolver:
    """뼈를 부모부터 하나씩 놓아 뼈대 공간의 자세 행렬 P를 얻고, 그에 맞는 뼈 기저(회전 4원수와 이동)를 낸다.

    P_b = P_부모 @ Rel_b @ B_b  (Rel_b = 쉬는 자세에서 부모 대비 행렬, B_b = 뼈의 기저 행렬 = 위치·회전)
    놓는 방법 셋(뼈마다 하나):
      fk   : 부모에서 물려받은 방향 위에 월드 축 회전을 한 번 더 한다(몸통·머리처럼 쌓이는 동작).
      absd : 쉬는 자세 대비 월드 회전을 직접 준다(팔다리 방향 지정, 발 자세).
      아무것도 없음: 부모를 그대로 따른다.
    trans : 머리 위치를 직접 준다(골반·origin의 이동).
    """

    def __init__(self, rig: Rig):
        self.rig = rig
        self.P = {}
        self.basis = {}

    def inherited(self, name):
        rig = self.rig
        p = rig.parent[name]
        base = (self.P[p] if p else rig.Matrix.Identity(4)) @ rig.rel[name]
        return base

    def head_pos(self, name):
        return self.inherited(name).translation.copy()

    def place(self, name, fk=None, absd=None, trans=None):
        rig = self.rig
        M = rig.Matrix
        base = self.inherited(name)
        if absd is not None:
            R = absd
        elif fk is not None:
            R = fk @ base.to_3x3()
        else:
            R = base.to_3x3()
        t = trans if trans is not None else base.translation
        target = M.Translation(t) @ R.to_4x4()
        B = base.inverted() @ target
        q = B.to_quaternion()
        loc = B.to_translation() if trans is not None else None
        self.basis[name] = (q, loc)
        p = rig.parent[name]
        self.P[name] = (self.P[p] if p else M.Identity(4)) @ rig.rel[name] @ B
        return self.P[name]

    def finish(self):
        for n in self.rig.order:
            if n not in self.P:
                self.place(n)
        return self.P


def delta_between(a, b):
    """월드 벡터 a를 b로 돌리는 최소 회전(3x3 행렬)."""
    return a.normalized().rotation_difference(b.normalized()).to_matrix()


def rot(axis: str, deg: float):
    import mathutils
    return mathutils.Matrix.Rotation(math.radians(deg), 3, axis)


def rot_about(vec, deg: float):
    import mathutils
    return mathutils.Matrix.Rotation(math.radians(deg), 3, vec)


# ------------------------------------------------------------------ 피부(스킨) 자료와 변형 계산

class Skin:
    """정점마다 최대 4개 영향. 변형 결과와 변 늘어남을 numpy로 계산한다(Blender의 평가를 거치지 않는다)."""

    def __init__(self, rest, idx, w, bone_names, edges):
        import numpy as np
        self.rest = rest
        self.idx = idx
        self.w = w
        self.bones = bone_names
        self.edges = edges
        L = np.linalg.norm(rest[edges[:, 0]] - rest[edges[:, 1]], axis=1)
        ok = L > 1e-6
        self.edges = edges[ok]
        self.rest_len = L[ok]
        self.hom = np.concatenate([rest, np.ones((len(rest), 1))], axis=1)

    @staticmethod
    def from_blender(mesh_obj, rig: Rig):
        import numpy as np
        me = mesh_obj.data
        names = [vg.name for vg in mesh_obj.vertex_groups]
        bone_names = [n for n in rig.order if n in names]
        bi = {n: i for i, n in enumerate(bone_names)}
        gname = {vg.index: vg.name for vg in mesh_obj.vertex_groups}
        V = len(me.vertices)
        idx = np.zeros((V, 4), dtype=np.int64)
        w = np.zeros((V, 4))
        for v in me.vertices:
            gs = sorted(((g.weight, gname[g.group]) for g in v.groups if g.weight > 1e-6 and gname[g.group] in bi), reverse=True)[:4]
            for k, (ww, nm) in enumerate(gs):
                idx[v.index, k] = bi[nm]
                w[v.index, k] = ww
        return Skin(mesh_coords(mesh_obj), idx, w, bone_names, mesh_edges(mesh_obj))

    def matrices(self, rig: Rig, P: dict):
        import numpy as np
        out = np.zeros((len(self.bones), 4, 4))
        for i, n in enumerate(self.bones):
            out[i] = np.array(P[n] @ rig.rest[n].inverted())
        return out

    def deform(self, mats):
        import numpy as np
        res = np.zeros_like(self.rest)
        for k in range(4):
            m = mats[self.idx[:, k]]
            pts = np.einsum("vij,vj->vi", m, self.hom)[:, :3]
            res += pts * self.w[:, k:k + 1]
        return res

    def stretch(self, pos):
        import numpy as np
        L = np.linalg.norm(pos[self.edges[:, 0]] - pos[self.edges[:, 1]], axis=1)
        return L / self.rest_len


def np_array(m):
    import numpy as np
    return np.array(m)


# ------------------------------------------------------------------ 내보내기와 미리보기

def export_glb(path: str, arm_obj, mesh_objs, fps: int = 60, animations: bool = True) -> None:
    import bpy
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.context.scene.render.fps = fps
    kw = dict(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
              export_animations=animations, export_skins=True, export_def_bones=False, export_extras=False)
    if animations:
        kw.update(export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
                  export_optimize_animation_size=False, export_anim_slide_to_zero=False, export_bake_animation=False)
    bpy.ops.export_scene.gltf(**kw)


def solid_texture_material(name: str, rgba, size: int = 8):
    """단색 텍스처를 입힌 재질. 게임의 재질 처리가 albedo_color를 덮어쓰므로 질감이 있어야 색이 남는다."""
    import bpy
    img = bpy.data.images.new(name + "_tex", size, size, alpha=True)
    img.pixels = [c for _ in range(size * size) for c in rgba]
    img.pack()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def hex_rgba(s: str):
    s = s.lstrip("#")
    return [int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


def render_sheet(arm_obj, mesh_objs, frames: list[float], out_png: str, view: str = "front", size: int = 360) -> None:
    """작업대(workbench) 엔진으로 정면/옆 6컷 시트를 한 장에 렌더한다(자세 확인용. 게임 화면이 아니다)."""
    import bpy
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.render.resolution_x = size
    sc.render.resolution_y = int(size * 1.25)
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("w") if sc.world is None else sc.world
    sc.world.color = (0.55, 0.57, 0.6)
    cam = bpy.data.objects.get("rigcam")
    if cam is None:
        cd = bpy.data.cameras.new("rigcam")
        cd.type = "ORTHO"
        cam = bpy.data.objects.new("rigcam", cd)
        bpy.context.scene.collection.objects.link(cam)
    sc.camera = cam
    import mathutils
    for o in mesh_objs:
        pass
    tmp = []
    H = max(v.co.z for v in mesh_objs[0].data.vertices)      # 쉬는 자세의 키(변형된 크기를 쓰면 누운 자세에서 확대된다)
    cam.data.ortho_scale = H * 1.3
    if view == "front":
        cam.location = (0, -10, H * 0.5)
        cam.rotation_euler = (math.radians(90), 0, 0)
    else:
        cam.location = (10, 0, H * 0.5)
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    paths = []
    for i, f in enumerate(frames):
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        p = str(Path(out_png).with_suffix("")) + "_%02d.png" % i
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    return paths


# ------------------------------------------------------------------ 손가락 자세(A7-6)

# 손 모양: 마디마다 굽힘 각(도). 손가락 셋 마디(.01 .02 .03)와 엄지 셋 마디. 쥔 손 = 지팡이 쥔 오른손, 가볍게 쥔 손 = 나머지.
HAND_POSES = {
    "open": {"finger": [0, 0, 0], "thumb": [0, 0, 0]},
    "relaxed": {"finger": [30, 42, 30], "thumb": [10, 12, 8]},
    "grip": {"finger": [50, 68, 48], "thumb": [22, 26, 16]},
}
FINGER_SCALE = {"index": 0.85, "middle": 1.0, "ring": 1.1, "pinky": 1.2}
DEFAULT_HANDS = {"l": "relaxed", "r": "grip"}


def finger_bone_names(side):
    """[(뼈 이름, 마디 번호 0~2, 손가락 이름)] 손가락 넷과 엄지."""
    out = []
    for f in ("index", "middle", "ring", "pinky"):
        for k in range(3):
            out.append(("finger_%s.%02d.%s" % (f, k + 1, side), k, f))
    for k in range(3):
        out.append(("thumb.%02d.%s" % (k + 1, side), k, "thumb"))
    return out


def curl_signs(rig, side):
    """뼈마다 굽힘 방향 부호(뼈 로컬 X축 회전의 +/-). 쉬는 자세가 T자·손바닥 아래이므로 손가락은 끝이 아래(-Z)로, 엄지는 끝이 검지 둘째 마디 쪽으로 가는 방향."""
    import mathutils
    cache = getattr(rig, "_curl_sign", None)
    if cache is None:
        cache = rig._curl_sign = {}
    if side in cache:
        return cache[side]
    sg = {}
    tgt_name = "finger_index.02." + side
    for name, k, f in finger_bone_names(side):
        if name not in rig.head:
            continue
        a = rig.rest_rot[name].col[0].copy()
        d = rig.rest_dir[name]
        if f == "thumb" and tgt_name in rig.head:
            tgt = rig.head[tgt_name]
            best, bs = None, 1.0
            for s in (1.0, -1.0):
                R = mathutils.Matrix.Rotation(s * 0.3, 3, a)
                tip = rig.head[name] + (R @ d) * rig.length[name]
                dist = (tip - tgt).length
                if best is None or dist < best:
                    best, bs = dist, s
            sg[name] = bs
        else:
            sg[name] = -1.0 if a.cross(d).z > 0 else 1.0
    cache[side] = sg
    return sg


def place_hand(S, rig, side, mode="relaxed", scale=1.0):
    """손가락 뼈를 mode 모양으로 놓는다(부모부터 하나씩). 손 뼈가 먼저 놓여 있어야 한다. 손가락 뼈가 없으면 아무것도 안 한다.
    finger_middle.01.<쪽>은 게임이 지팡이 자리 계산에 쓰는 뼈지만 머리 위치는 안 움직이므로(자기 관절 둘레 회전) 지팡이 위치는 그대로다."""
    pose = HAND_POSES.get(mode, HAND_POSES["relaxed"])
    sg = curl_signs(rig, side)
    for name, k, f in finger_bone_names(side):
        if name not in rig.head:
            continue
        deg = (pose["thumb"] if f == "thumb" else pose["finger"])[k] * (1.0 if f == "thumb" else FINGER_SCALE[f]) * scale
        base = S.inherited(name)
        R = base.to_3x3() @ rot("X", sg[name] * deg)
        S.place(name, absd=R)
