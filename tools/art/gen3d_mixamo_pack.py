#!/usr/bin/env python3
"""Mixamo 뼈대 몸 + 동작 FBX들 -> 클립 이름이 논리 이름인 glb 한 개(번개·화염에도 같은 설정 꼴로 되풀이한다).

  python tools/art/gen3d_mixamo_pack.py tools/art/gen3d_mixamo_configs/frost.json [--out chapter1/art/actors/hero/frost/model.glb]

설정 JSON 칸
  body            몸 FBX(뼈대 붙은 쉬는 자세)          texture_color / texture_normal   질감 PNG        metallic, roughness  머티리얼 값
  clips[]         {name 논리 이름, fbx, in_place(엉덩이 수평 이동 추세 제거), frames [처음, 끝](없으면 전체)}
  fps             30
  hero_json       게임이 읽는 곁 JSON(look·staff)의 원본. 결과 glb 옆에 hero.json으로 복사한다
결과 glb 옆에 <out>.pack-report.json(클립 길이·엉덩이 이동·지면 속도 추정 ...)을 쓴다. 생성물의 이용 약관을 확인하기 전에는
chapter1/art/actors/hero/ 아래 결과를 git에 올리지 않는다(.gitignore).
Blender: D:/Blender Foundation/Blender 5.3/blender.exe (환경 변수 BLENDER로 바꾼다).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BLENDER = os.environ.get("BLENDER", "D:/Blender Foundation/Blender 5.3/blender.exe")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--out", help="glb 경로(기본: 설정의 out)")
    a = ap.parse_args()
    cfg = json.loads(Path(a.config).read_text(encoding="utf-8"))
    out = Path(a.out or cfg["out"])
    if not out.is_absolute():
        out = REPO / out
    out.parent.mkdir(parents=True, exist_ok=True)
    report = out.with_suffix(".pack-report.json")
    cmd = [BLENDER, "-b", "-P", str(REPO / "tools/art/gen3d_mixamo_blender.py"), "--", str(Path(a.config).resolve()), str(out), str(report)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    tail = [l for l in r.stdout.splitlines() if "PACK_DONE" in l or "Error" in l or "Traceback" in l]
    print("\n".join(tail[-12:]))
    if r.returncode != 0 or not out.exists():
        sys.stderr.write((r.stdout + r.stderr)[-2500:])
        return 1
    if cfg.get("hero_json"):
        src = Path(cfg["hero_json"])
        src = src if src.is_absolute() else REPO / src
        (out.parent / "hero.json").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    rep = json.loads(report.read_text(encoding="utf-8"))
    print("body_height_m", rep["body_height_m"], "| glb", out, "%.1f MB" % (out.stat().st_size / 1e6))
    for name, c in rep["clips"].items():
        print("%-10s %6.3fs frames %s  hips_span %.3f  ground %s  reach_f %s  sway_f %s  trend_removed %s" % (
            name, c["length_s"], c["used_frames"], c["hips_span_m"], c["ground_speed_mps"], c["hand_reach_frame"], c["head_sway_frame"], c.get("trend_removed_m", "-")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
