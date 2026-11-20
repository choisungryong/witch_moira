#!/usr/bin/env python3
"""선명도 앞뒤 판: 같은 각도·같은 크기로 전신, 상체 확대, 머리 확대를 렌더해 모델 여러 개를 가로로 나란히 놓는다(Blender 필요, 평면 조명 작업대 렌더).

  python tools/art/char_sharpness.py --out sheet.png --work DIR --model before=a.glb --model after=b.glb [--model 4k=c.glb] [--az 0]
행 = 전신(2.1 m가 900px), 상체(1.25~1.75 m, 1400 px/m), 머리(3200 px/m). 열 = 모델. 라벨은 위에 글자로 붙는다.
Blender 평면 조명이라 게임 장면이 아니고, 선명도는 텍스처·형상에서 오는 것만 비교한다.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VIEWS = [("full", 700, 1000, 430.0, 350.0, 960.0), ("upper", 900, 700, 1400.0, 450.0, 350 + 1.5 * 1400.0), ("head", 700, 700, 3200.0, 350.0, 350 + 1.84 * 3200.0)]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--model", action="append", required=True, help="라벨=glb 경로")
    ap.add_argument("--az", type=float, default=0.0)
    ap.add_argument("--pose", help="렌더 전 자세 clip:frame (예: idle:0)")
    a = ap.parse_args(argv)
    from PIL import Image, ImageDraw
    work = Path(a.work)
    work.mkdir(parents=True, exist_ok=True)
    views = [dict(name=n, az=a.az, s=s, cx=cx, cy=cy, w=w, h=h) for n, w, h, s, cx, cy in VIEWS]
    (work / "views.json").write_text(json.dumps(views), encoding="utf-8")
    cols = []
    for lab_path in a.model:
        label, path = lab_path.split("=", 1)
        r = subprocess.run([sys.executable, str(HERE / "char_render.py"), "views", "--model", path, "--views", str(work / "views.json"),
                            "--out", str(work / label)] + (["--pose", a.pose] if a.pose else []), capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0:
            raise SystemExit("렌더 실패 %s: %s" % (label, r.stdout[-400:]))
        cols.append((label, [Image.open(work / label / (v["name"] + ".png")).convert("RGB") for v in views]))
    H = [v["h"] for v in views]
    # 열 폭은 행마다 다르므로 행별로 붙이고 가장 넓은 행에 맞춘다
    rows = []
    for i, v in enumerate(views):
        ims = [c[1][i] for c in cols]
        row = Image.new("RGB", (sum(im.width for im in ims) + 6 * (len(ims) - 1), v["h"]), (60, 60, 64))
        x = 0
        for im in ims:
            row.paste(im, (x, 0))
            x += im.width + 6
        rows.append(row)
    W = max(r.width for r in rows)
    sheet = Image.new("RGB", (W, sum(r.height for r in rows) + 6 * (len(rows) - 1) + 24), (30, 30, 34))
    dr = ImageDraw.Draw(sheet)
    dr.text((6, 4), "  |  ".join(c[0] for c in cols) + "   (같은 각도·같은 크기, Blender 평면 조명)", fill=(230, 230, 230))
    y = 24
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height + 6
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print("SHARPNESS_OK", sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
