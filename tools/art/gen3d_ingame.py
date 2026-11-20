#!/usr/bin/env python3
"""gen3d 모델을 게임 화면(rig_game_probe.gd)에 끼워 캡처하고 화소 잘림(hero_burn)을 잰다. 제품 파일은 바꾸지 않는다. 창이 필요하다.

  python tools/art/gen3d_ingame.py --glb final.glb --look look.json --out _local/art/gen3d/shots/NAME [--cam 14|19.5] [--ticks 300,330,360] [--primary frost]
  python tools/art/gen3d_ingame.py --glb final.glb --look look.json --out DIR --force-clip run --force-times 0,0.1,... [--cam 14]
rig_game_probe.gd의 --hero-look(꼭 준다: 없으면 게임의 어두운 마법사용 보정이 남아 하얗게 탄다), --hero-mask, --hero-crop-size 480을 붙이고,
끝나면 hero_burn으로 잘린 화소 비율(clip: 한 채널이라도 254 이상, white: 세 채널 모두 240 이상)을 DIR/burn.json에 적는다.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PY = sys.executable


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", help="없으면 게임의 옛 주인공 그대로(비교용)")
    ap.add_argument("--look", help="없으면 게임 값 그대로")
    ap.add_argument("--out", required=True, help="_local 아래 폴더(저장소 상대 또는 절대)")
    ap.add_argument("--cam", type=float, default=0.0, help="직교 카메라 크기(게임 19.5, 작을수록 크게). 0이면 게임 그대로")
    ap.add_argument("--ticks", default="300,330,360")
    ap.add_argument("--until", type=int, default=420)
    ap.add_argument("--primary", default="frost")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--force-clip")
    ap.add_argument("--force-times")
    ap.add_argument("--force-start", type=int, default=240)
    ap.add_argument("--crop", type=int, default=480)
    ap.add_argument("--hero-models", action="store_true", help="본체의 스위치 --chapter1-hero-models를 켠다(자리표의 마녀 몸. --glb 없이 쓴다)")
    ap.add_argument("--sheet", help="강제 동작 캡처(--force-clip)를 주인공 둘레로 잘라 2배 키워 한 장 판으로 이은 PNG 경로")
    ap.add_argument("--hero-xy", default="935,455", help="--sheet 자르기 가운데(화면 화소). 같은 시드·틱이면 판마다 같은 자리")
    ap.add_argument("--sheet-box", type=int, default=360, help="--sheet 자르는 한 변(화소). 2배로 키워 붙인다")
    ap.add_argument("--sheet-cols", type=int, default=4)
    a = ap.parse_args()
    out = Path(a.out)
    rel = out if not out.is_absolute() else out.relative_to(REPO)
    cmd = [PY, "tools/dev/godot.py", "--fixed-fps", "60", "--resolution", "1920x1080", "--path", ".", "--script", "res://chapter1/tests/rig_game_probe.gd", "--",
           "--chapter1-pilot", "--chapter1-profile-off", "--chapter1-qa-ignore-focus", "--chapter1-seed=%d" % a.seed, "--primary=chapter1.skill." + a.primary,
           "--hero-mask", "--hero-crop-size=%d" % a.crop, "--shots=" + str(rel).replace("\\", "/")]
    if a.hero_models:
        cmd += ["--chapter1-hero-models"]
    if a.glb:
        cmd += ["--model-glb=" + a.glb, "--hero-boost=0"]
    if a.look:
        cmd += ["--hero-look=" + a.look]
    if a.force_clip:
        cmd += ["--force-clip=" + a.force_clip, "--force-times=" + a.force_times, "--force-start=%d" % a.force_start, "--force-shots=" + str(rel).replace("\\", "/")]
        cmd += ["--until=%d" % max(a.until, a.force_start + 400)]
    else:
        cmd += ["--hero-crop-ticks=" + a.ticks, "--until=%d" % a.until]
    if a.cam:
        cmd += ["--vp-exp=cam=%g" % a.cam]
    r = subprocess.run(cmd, cwd=str(REPO), capture_output=True, text=True)
    sys.stdout.write("\n".join(l for l in r.stdout.splitlines() if "PROBE" in l or "ERROR: Parse" in l or "SCRIPT ERROR" in l)[:3000] + "\n")
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-1500:])
    burn = subprocess.run([PY, "tools/art/hero_burn.py", str(rel)], cwd=str(REPO), capture_output=True, text=True)
    print(burn.stdout)
    (REPO / rel / "burn.txt").write_text(burn.stdout, encoding="utf-8")
    if a.sheet and a.force_clip:
        from PIL import Image, ImageDraw
        cx, cy = [int(v) for v in a.hero_xy.split(",")]
        bx = a.sheet_box
        files = sorted((REPO / rel).glob(a.force_clip + "_*_t*.png"))
        tiles = []
        for f in files:
            im = Image.open(f).convert("RGB").crop((cx - bx // 2, cy - bx // 2, cx + bx // 2, cy + bx // 2)).resize((bx * 2, bx * 2), Image.LANCZOS)
            ImageDraw.Draw(im).text((8, 6), f.stem, fill=(255, 255, 0))
            tiles.append(im)
        cols = a.sheet_cols
        rows = (len(tiles) + cols - 1) // cols
        sh = Image.new("RGB", (cols * bx * 2, rows * bx * 2))
        for i, t in enumerate(tiles):
            sh.paste(t, ((i % cols) * bx * 2, (i // cols) * bx * 2))
        Path(a.sheet).parent.mkdir(parents=True, exist_ok=True)
        sh.save(a.sheet)
        print("SHEET", a.sheet, sh.size, len(tiles))
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
