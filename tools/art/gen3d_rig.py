#!/usr/bin/env python3
"""gen3d_prepare가 만든 저폴리 glb에 뼈대와 가중치를 입히고, 뼈 자리를 메시 위에 그려 확인한다(Blender 5.3 명령줄).
rig_build.py를 그대로 쓰되 (1) 관절 높이·팔 길이를 이 몸에 맞춘 설정(--joints)으로 덮고 (2) 뼈를 반투명 메시 위에 그린 판을 만든다.

  python tools/art/gen3d_rig.py --in low.glb --out-blend rigged.blend --joints joints_frost.json --overlay DIR [--report r.json]
  python tools/art/gen3d_rig.py --in low.glb --joints j.json --overlay DIR --overlay-only      # 가중치 없이 뼈 자리만 빨리 보기(고치는 동안)
joints JSON = rig_build 설정의 일부(키 대비 비율). 예: {"proportions": {"hip_z": 0.505, "knee_z": 0.38, "ankle_z": 0.055, ...}, "weights": {...}, "bone_overrides": {...}}
  기본값과 키 설명은 tools/art/rig_configs/default.json. 새 몸에서는 overlay 그림을 보고 12개쯤(어깨·팔꿈치·손목·엉덩·무릎·발목·목·머리 높이)을 고친다.
출력: DIR/rig_front.png, rig_side.png(뼈 위치), rigged.blend, 보고서(뼈 24, 무가중치, 최대 영향 수).
다음 걸음: gen3d_clips.py(동작).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402
import rig_build as rb  # noqa: E402


def render_overlay(obj, arm, outdir, size=640):
    import bpy
    import mathutils
    import numpy as np
    sc = bpy.context.scene
    eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = size
    sc.render.resolution_y = int(size * 1.5)
    sc.display.shading.light = "STUDIO"
    sc.display.shading.show_xray = True
    sc.display.shading.xray_alpha = 0.45
    sc.display.shading.color_type = "SINGLE"
    sc.display.shading.single_color = (0.8, 0.8, 0.85)
    arm.data.display_type = "STICK"
    arm.show_in_front = True
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    P = rc.mesh_coords(obj)
    H = float(P[:, 2].max())
    bones = {b.name: [[round(float(v), 4) for v in b.head_local], [round(float(v), 4) for v in b.tail_local]] for b in arm.data.bones}
    (Path(outdir) / "bones.json").write_text(json.dumps({"height": H, "size": size, "bones": bones}), encoding="utf-8")
    for name, az in (("front", 0), ("side", 90)):
        cam.data.ortho_scale = H * 1.12
        tgt = mathutils.Vector((0, 0, H * 0.5))
        r = math.radians(az)
        cam.location = tgt + mathutils.Vector((math.sin(r), -math.cos(r), 0)) * H * 4
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(Path(outdir) / ("rig_%s.png" % name))
        bpy.ops.render.render(write_still=True)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="input", required=True)
    ap.add_argument("--out-blend")
    ap.add_argument("--joints", help="관절 비율 JSON(rig_build --config 형식)")
    ap.add_argument("--overlay", help="뼈 자리 그림을 쓸 폴더")
    ap.add_argument("--overlay-only", action="store_true", help="가중치 계산을 건너뛴다")
    ap.add_argument("--report")
    ap.add_argument("--clips", action="store_true", help="이어서 사람 동작(Mixamo·UAL)을 옮겨 --out-glb로 내보낸다(동작 이름·길이는 --clips-config)")
    ap.add_argument("--clips-config", default=str(Path(__file__).resolve().parent / "rig_configs" / "mocap_clips_gen3d.json"))
    ap.add_argument("--out-glb")
    ap.add_argument("--only", help="쉼표로 나눈 동작만 만든다(조정할 때)")
    ap.add_argument("--stride", type=float, default=3.5, help="clips.game_hero_stride(걸음 폭 계약). 지금 세 마녀 몸과 같은 3.5")
    a = ap.parse_args(argv)
    cfg = rc.load_config(a.joints)
    if a.clips:
        cfg["clips"]["mocap"] = json.loads(Path(a.clips_config).read_text(encoding="utf-8"))
        cfg["clips"]["game_hero_stride"] = a.stride
        cfg["clips"]["run_stance_fraction"] = 0.38
        cfg["clips"]["elem_arm"] = "l"
    if a.overlay_only:
        import bpy
        import numpy as np
        rc.reset_scene(cfg["clips"]["fps"])
        rc.import_any(a.input)
        obj = rc.single_mesh_from_import(cfg)
        P = rc.mesh_coords(obj)
        from mathutils import Matrix, Vector
        sh = Vector((0, 0, -float(P[:, 2].min())))
        pre = rb.measure(P + np.array([0, 0, sh.z]), cfg)
        if pre["feet"]["l"]["found"] and pre["feet"]["r"]["found"]:
            sh.x = -0.5 * (pre["feet"]["l"]["cx"] + pre["feet"]["r"]["cx"])
        obj.data.transform(Matrix.Translation(sh))
        P = rc.mesh_coords(obj)
        m = rb.measure(P, cfg)
        pos = rb.bone_positions(m, cfg)
        arm = rb.make_armature(pos)
        Path(a.overlay).mkdir(parents=True, exist_ok=True)
        render_overlay(obj, arm, a.overlay)
        print("GEN3D_RIG overlay only", a.overlay)
        return 0
    if not a.out_blend:
        raise SystemExit("--out-blend 가 필요하다(또는 --overlay-only)")

    class A:
        pass
    b = A()
    b.input, b.out_blend, b.config = a.input, a.out_blend, a.joints
    report, rig, skin, obj, arm = rb.build(b, cfg)
    if a.overlay:
        Path(a.overlay).mkdir(parents=True, exist_ok=True)
        render_overlay(obj, arm, a.overlay)
    if a.clips:
        import rig_clips
        import bpy
        report["clips"] = rig_clips.make_all(arm, obj, rig, skin, cfg, a.out_glb, None, only=(a.only.split(',') if a.only else None))
        bpy.ops.wm.save_as_mainfile(filepath=str(a.out_blend), compress=True)
    if a.report:
        rc.write_json(a.report, report)
    print("GEN3D_RIG", {k: report[k] for k in ("bones", "deform_bones", "weights")})
    return 0


def draw_overlay(outdir):
    """Blender가 쓴 rig_front/side.png 위에 bones.json의 뼈를 선·점으로 그려 rig_<시점>_bones.png와 두 장을 이은 rig_bones.png를 만든다."""
    from PIL import Image, ImageDraw
    d = json.loads((Path(outdir) / "bones.json").read_text(encoding="utf-8"))
    H, size = d["height"], d["size"]
    ppm = size * 1.5 / (H * 1.12)
    ims = []
    for name in ("front", "side"):
        im = Image.open(Path(outdir) / ("rig_%s.png" % name)).convert("RGB")
        dr = ImageDraw.Draw(im)
        for bn, (h, t) in d["bones"].items():
            def uv(p):
                u = (p[0] if name == "front" else p[1]) * ppm + size / 2
                return (u, size * 0.75 - (p[2] - H / 2) * ppm)
            col = (255, 80, 80) if bn.endswith("_l") else ((80, 160, 255) if bn.endswith("_r") else (255, 230, 60))
            dr.line([uv(h), uv(t)], fill=col, width=2)
            x, y = uv(h)
            dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 255, 255))
        im.save(Path(outdir) / ("rig_%s_bones.png" % name))
        ims.append(im)
    s = Image.new("RGB", (ims[0].width * 2, ims[0].height))
    s.paste(ims[0], (0, 0))
    s.paste(ims[1], (ims[0].width, 0))
    s.save(Path(outdir) / "rig_bones.png")
    print("GEN3D_RIG overlay", Path(outdir) / "rig_bones.png")


if __name__ == "__main__":
    if rc.have_bpy():
        sys.exit(main(rc.script_args()) or 0)
    code = rc.relaunch(__file__)
    if code == 0 and "--overlay" in sys.argv:
        draw_overlay(sys.argv[sys.argv.index("--overlay") + 1])
    sys.exit(code)
