#!/usr/bin/env python3
"""달리기 앞뒤 판: char_render game --seq 대신 프레임별 렌더(cmp.sh 형식 game_run_<f>_<이름>_<카메라>_<f>.png)를 모아 한 장으로 붙인다(PIL만).

  python tools/art/char_limbs_sheet.py --dir DIR --names before,after,lean03 --frames 0,5,10,... --out sheet.png
행 = (카메라 측면/게임) x (이름), 열 = 프레임. 게임 칸은 게임 카메라 화면 높이 1080 밀도의 3배 확대(--res-mult 3)로 찍은 것이다.
"""
from __future__ import annotations

import argparse
from pathlib import Path


def main(argv=None):
    from PIL import Image, ImageDraw
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--names", required=True)
    ap.add_argument("--frames", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--clip", default="run", help="파일 이름의 동작 이름(game_<clip>_<f>_...)")
    ap.add_argument("--cams", default="side,game")
    a = ap.parse_args(argv)
    names = a.names.split(",")
    frames = [int(f) for f in a.frames.split(",")]
    d = Path(a.dir)
    spec = {"side": ((200, 0, 760, 540), (280, 270)), "game": ((330, 60, 630, 540), (170, 270))}
    rows = []
    for cam in a.cams.split(","):
        box, sz = spec[cam]
        for n in names:
            row = Image.new("RGB", (sz[0] * len(frames), sz[1]), (60, 62, 64))
            for k, f in enumerate(frames):
                im = Image.open(d / ("game_%s_%d_%s_%s_%d.png" % (a.clip, f, n, cam, f))).convert("RGB").crop(box).resize(sz)
                row.paste(im, (k * sz[0], 0))
            ImageDraw.Draw(row).text((4, 4), "%s / %s" % (cam, n), fill=(255, 255, 255))
            rows.append(row)
    sheet = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print("LIMBS_SHEET_OK", sheet.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
