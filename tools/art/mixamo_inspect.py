#!/usr/bin/env python3
"""Mixamo FBX 동작을 열어 살핀다(Blender 5.3): 길이, 프레임 수, 원본 프레임률 추정, 엉덩이가 앞으로 나아가는지(제자리 여부), 반복 이음 오차, 뼈 이름, 손 뻗음 최댓값 시각.

  python tools/art/mixamo_inspect.py --dir DIR --out report.json [--files "Running.fbx,Idle.fbx"] [--src-fps 30]
FBX는 받은 폴더에서 읽기만 한다(믿을 수 없는 데이터). 시간 = 프레임 / 원본 프레임률(FBX 가져오기가 장면 프레임률과 어긋나게 프레임을 놓을 수 있어 --src-fps로 준다).
보고서 항목: frames, seconds, hips_net_xy(첫~끝 수평 이동 m), hips_speed_mps, in_place(순이동 < 0.15m), loop_gap(첫 프레임과 끝 프레임의 뼈 위치 차 평균 m),
reach_peak_s(손이 엉덩이에서 가장 멀어지는 시각: 쏘는 순간 후보), wrist_speed_peak_s(손목 속도 최대 시각).
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
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--files")
    ap.add_argument("--src-fps", type=float, default=30.0)
    a = ap.parse_args(argv)
    files = a.files.split(",") if a.files else sorted(p.name for p in Path(a.dir).glob("*.fbx"))
    out = {}
    for fn in files:
        rc.reset_scene(60)
        bpy.ops.import_scene.fbx(filepath=str(Path(a.dir) / fn))
        arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        act = next(iter(bpy.data.actions))
        f0, f1 = act.frame_range
        n = int(round(f1 - f0)) + 1
        ad = arm.animation_data_create()
        ad.action = act
        if hasattr(ad, "action_slot") and len(act.slots):
            ad.action_slot = act.slots[0]
        Mw = arm.matrix_world
        names = [b.name for b in arm.data.bones]
        hips = next(n_ for n_ in names if n_.endswith("Hips"))
        lh = next(n_ for n_ in names if n_.endswith(":LeftHand"))
        rh = next(n_ for n_ in names if n_.endswith(":RightHand"))
        sc = bpy.context.scene
        P_h, P_lh, P_rh = [], [], []
        for fr in range(int(f0), int(f1) + 1):
            sc.frame_set(fr)
            P_h.append(np.array((Mw @ arm.pose.bones[hips].head)[:]))
            P_lh.append(np.array((Mw @ arm.pose.bones[lh].head)[:]))
            P_rh.append(np.array((Mw @ arm.pose.bones[rh].head)[:]))
        P_h, P_lh, P_rh = np.array(P_h), np.array(P_lh), np.array(P_rh)
        dt = 1.0 / a.src_fps
        secs = (n - 1) * dt
        net = (P_h[-1] - P_h[0])
        net_xy = float(np.linalg.norm(net[:2]))
        # 손 뻗음: 엉덩이 대비 수평 거리 최대, 손목 속도 최대
        rel_l = np.linalg.norm((P_lh - P_h)[:, :2], axis=1)
        rel_r = np.linalg.norm((P_rh - P_h)[:, :2], axis=1)
        vl = np.linalg.norm(np.diff(P_lh, axis=0), axis=1) / dt
        vr = np.linalg.norm(np.diff(P_rh, axis=0), axis=1) / dt
        out[fn] = {
            "frames": n, "frame_range": [float(f0), float(f1)], "scene_fps": sc.render.fps, "assumed_src_fps": a.src_fps, "seconds": secs,
            "bones": len(names), "arm_scale": [round(v, 4) for v in arm.scale], "arm_rot_deg": [round(float(np.degrees(v)), 1) for v in arm.rotation_euler],
            "hips_height_m": float(P_h[0, 2]), "hips_net_xy_m": net_xy, "hips_speed_mps": net_xy / max(secs, 1e-6), "in_place": net_xy < 0.15,
            "hips_z_range_m": float(P_h[:, 2].max() - P_h[:, 2].min()),
            "loop_gap_hand_m": float(np.linalg.norm(P_lh[-1] - P_h[-1] - (P_lh[0] - P_h[0]))),
            "reach_peak_s": {"left": float(np.argmax(rel_l) * dt), "right": float(np.argmax(rel_r) * dt), "left_m": float(rel_l.max()), "right_m": float(rel_r.max())},
            "wrist_speed_peak_s": {"left": float(np.argmax(vl) * dt), "right": float(np.argmax(vr) * dt), "left_mps": float(vl.max()), "right_mps": float(vr.max())},
            "bone_sample": names[:6],
        }
    rc.write_json(a.out, out)
    for k, v in out.items():
        print("MIXAMO %-24s %3d fr %.2fs bones %d net_xy %.2fm in_place %s hips_z %.2fm scale %s rot %s" % (k, v["frames"], v["seconds"], v["bones"], v["hips_net_xy_m"], v["in_place"], v["hips_z_range_m"], v["arm_scale"], v["arm_rot_deg"]))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
