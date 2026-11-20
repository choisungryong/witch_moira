#!/usr/bin/env python3
"""원본 동작과 우리 뼈대를 막대 그림으로 같은 프레임에 나란히 놓는다(PIL만, Blender 필요 없음). rig_mocap의 `dump` 결과를 읽는다.

  python tools/art/limb_stick.py --dump run_dump.json --out sticks.png [--frames 0,5,10,...] [--src-scale 1.216]
각 프레임: 칸 넷 = 원본 측면(y,z), 우리 측면, 원본 정면(x,z), 우리 정면. 왼팔·왼다리는 빨강·주황, 오른쪽은 파랑·초록, 몸통은 흰색.
원본은 다리 길이 비(--src-scale)로 키워 같은 크기로 보인다. 팔꿈치·무릎이 같은 방향으로 꺾이는지, 팔꿈치가 옆이나 앞으로 꺾이는 프레임이 있는지를 눈으로 본다.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

CHAINS_SRC = {
    "arm_l": ("upperarm_l", "lowerarm_l", "hand_l"), "arm_r": ("upperarm_r", "lowerarm_r", "hand_r"),
    "leg_l": ("thigh_l", "calf_l", "foot_l", "ball_l"), "leg_r": ("thigh_r", "calf_r", "foot_r", "ball_r"),
    "spine": ("pelvis", "spine_03", "Head"),
}
CHAINS_OUR = {
    "arm_l": ("upper_arm_cr_l", "forearm_cr_l", "hand_cr_l"), "arm_r": ("upper_arm_cr_r", "forearm_cr_r", "hand_cr_r"),
    "leg_l": ("thigh_cr_l", "shin_cr_l", "tarsal_cr_l", "toe_cr_l"), "leg_r": ("thigh_cr_r", "shin_cr_r", "tarsal_cr_r", "toe_cr_r"),
    "spine": ("pelvis_cr", "spine_cr_03", "head_cr"),
}
COLORS = {"arm_l": (230, 70, 60), "leg_l": (240, 160, 40), "arm_r": (70, 120, 240), "leg_r": (60, 200, 90), "spine": (240, 240, 240)}


def draw_panel(dr, ox, oy, frame, chains, axes, scale, src_scale, ground_z, size):
    """axes = (가로 좌표 인덱스, 부호). 세로는 z(위)."""
    ax, sg = axes
    w, h = size
    cx = ox + w // 2
    base = oy + h - 24
    # 바닥선
    dr.line([(ox + 6, base), (ox + w - 6, base)], fill=(90, 90, 90))
    pelvis_key = chains["spine"][0]
    px0 = frame[pelvis_key][ax]
    for name, bones in chains.items():
        pts = []
        for b in bones:
            p = frame[b]
            pts.append((cx + sg * (p[ax] - px0) * scale * src_scale, base - (p[2] - ground_z) * scale * src_scale))
        dr.line(pts, fill=COLORS[name], width=3)
        for q in pts:
            dr.ellipse((q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3), fill=(255, 255, 255))


def main(argv=None):
    from PIL import Image, ImageDraw
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", default="0,5,10,15,20,25,30,35")
    ap.add_argument("--src-scale", type=float, default=1.216)
    a = ap.parse_args(argv)
    d = json.loads(Path(a.dump).read_text(encoding="utf-8"))
    frames = [int(f) for f in a.frames.split(",")]
    W, H = 150, 230
    scale = 105.0
    sheet = Image.new("RGB", (W * 4 * 2, H * ((len(frames) + 1) // 2)), (30, 30, 34))
    dr = ImageDraw.Draw(sheet)
    for k, f in enumerate(frames):
        col, row = k % 2, k // 2
        ox, oy = col * W * 4, row * H
        src, ours = d["src"][f], d["ours"][f]
        zs = min(min(p[2] for p in src.values()), 0.0) if False else min(src["foot_l"][2], src["foot_r"][2], src["ball_l"][2], src["ball_r"][2])
        zo = min(ours["tarsal_cr_l"][2], ours["tarsal_cr_r"][2], ours["toe_cr_l"][2], ours["toe_cr_r"][2])
        # 측면: 가로 = y(앞이 -y라 부호를 뒤집어 앞이 오른쪽), 정면: 가로 = x
        draw_panel(dr, ox, oy, src, CHAINS_SRC, (1, -1), scale, a.src_scale, zs, (W, H))
        draw_panel(dr, ox + W, oy, ours, CHAINS_OUR, (1, -1), scale, 1.0, zo, (W, H))
        draw_panel(dr, ox + 2 * W, oy, src, CHAINS_SRC, (0, 1), scale, a.src_scale, zs, (W, H))
        draw_panel(dr, ox + 3 * W, oy, ours, CHAINS_OUR, (0, 1), scale, 1.0, zo, (W, H))
        dr.text((ox + 4, oy + 3), "frame %d  [원본 측면 | 우리 측면 | 원본 정면 | 우리 정면]" % f, fill=(200, 200, 200))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print("STICK_OK", sheet.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
