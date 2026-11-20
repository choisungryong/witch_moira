#!/usr/bin/env python3
"""A7-2 동작 시트: 마녀마다 final.glb의 새 동작을 정면·측면 프레임 띠로 렌더하고(char_render poses) 한 장씩 붙인다(Blender 필요, 한 번에 하나씩 돈다).

  python tools/art/char_motion_sheets.py --work D:/Project/witch-moira-work/char3d/a7 --out _local/art/a7/A7-2 [--names ember,frost,storm]
낸 것(--out):
  <마녀>_run.png              달리기 한 주기 6컷 x (정면, 측면)
  <마녀>_cast.png             그 마녀의 기본기 시전 6컷 x (정면, 측면)
  <마녀>_misc.png             둘레 주문·강림 부름·강림 내려침·돌진 각 4컷(3/4 시점)
  cast_gray_compare.png       세 마녀 기본기 시전의 뻗은 순간(0.07초)과 머묾 순간(0.12초)을 정면·측면 회색조로 나란히(실루엣으로 갈리는지)
미리보기는 Blender 작업대 평면 조명이다. 게임 장면이 아니고 손맛 평가도 아니다.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import char_montage  # noqa: E402

OWN_CAST = {"ember": "cast_basic_ember", "frost": "cast_basic_frost", "storm": "cast_basic_storm"}
RUN_FRAMES = "0,6,12,18,24,30"
CAST_FRAMES = "0,2,4,7,12,17"
MISC = [("cast_ring", "0,4,9,13"), ("descent_call", "0,15,25,40"), ("descent_strike", "0,12,20,30"), ("dash", "0,3,7,12")]


def render(model, out, clip, frames, az, tag):
    r = subprocess.run([sys.executable, str(HERE / "char_render.py"), "poses", "--model", str(model), "--out", str(out), "--clip", clip,
                        "--frames", frames, "--az", str(az), "--tag", tag], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise SystemExit("렌더 실패 %s %s: %s" % (clip, az, r.stdout[-500:]))
    return [str(Path(out) / ("pose_%s_%s%s.png" % (clip, f, tag))) for f in frames.split(",")]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--names", default="ember,frost,storm")
    a = ap.parse_args(argv)
    out = Path(a.out)
    (out / "frames").mkdir(parents=True, exist_ok=True)
    fr = out / "frames"
    names = a.names.split(",")
    gray_rows = {"front": [], "side": []}
    for n in names:
        model = Path(a.work) / n / "final.glb"
        rows = [render(model, fr, "run", RUN_FRAMES, 0, "_%s_f" % n), render(model, fr, "run", RUN_FRAMES, 90, "_%s_s" % n)]
        char_montage.montage(rows, 400, out / ("%s_run.png" % n))
        cast = OWN_CAST[n]
        rows = [render(model, fr, cast, CAST_FRAMES, 0, "_%s_f" % n), render(model, fr, cast, CAST_FRAMES, 90, "_%s_s" % n)]
        char_montage.montage(rows, 400, out / ("%s_cast.png" % n))
        gray_rows["front"] += [rows[0][2], rows[0][4]]
        gray_rows["side"] += [rows[1][2], rows[1][4]]
        row = []
        for clip, frames in MISC:
            row += render(model, fr, clip, frames, -35, "_%s_m" % n)
        char_montage.montage([row[:8], row[8:]], 330, out / ("%s_misc.png" % n))
    char_montage.montage([gray_rows["front"], gray_rows["side"]], 520, out / "cast_gray_compare.png", gray=True)
    print("MOTION_SHEETS_OK", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
