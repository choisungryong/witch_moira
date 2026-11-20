#!/usr/bin/env python3
"""gen3d_ingame.py가 저장한 강제 동작 캡처(<동작>_NN_tTTT.png, 1920x1080)를 주인공 둘레로 잘라 2배 키워 한 장 판으로 잇는다(PIL만).

  python tools/art/gen3d_sheet.py --out sheet.png --box 300 --xy 935,455 --cols 4 --tile DIR:동작 --tile DIR:동작 ...
  --tile 은 폴더:동작 이름(파일 <동작>_*_t*.png를 시각 순으로 모두). 타일 위에 파일 이름과 --label을 적는다.
  --pair OLD_DIR:NEW_DIR:동작 이면 같은 시각의 옛 주인공(위)과 새 모델(아래)을 위아래로 짝지어 놓는다(비교용).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def crop(f, cx, cy, box, scale=2):
    im = Image.open(f).convert("RGB").crop((cx - box // 2, cy - box // 2, cx + box // 2, cy + box // 2))
    return im.resize((box * scale, box * scale), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--box", type=int, default=300)
    ap.add_argument("--xy", default="935,455")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--tile", action="append", default=[])
    ap.add_argument("--pair", action="append", default=[])
    a = ap.parse_args()
    cx, cy = [int(v) for v in a.xy.split(",")]
    tiles = []
    for t in a.tile:
        d, clip = t.rsplit(":", 1)
        for f in sorted(Path(d).glob(clip + "_*_t*.png")):
            im = crop(f, cx, cy, a.box)
            ImageDraw.Draw(im).text((8, 6), "%s %s" % (Path(d).name, f.stem), fill=(255, 255, 0))
            tiles.append(im)
    for pr in a.pair:
        od, nd, clip = pr.split(":")
        for fo, fn in zip(sorted(Path(od).glob(clip + "_*_t*.png")), sorted(Path(nd).glob(clip + "_*_t*.png"))):
            col = Image.new("RGB", (a.box * 2, a.box * 4))
            for i, (f, lab) in enumerate(((fo, "OLD"), (fn, "NEW"))):
                im = crop(f, cx, cy, a.box)
                ImageDraw.Draw(im).text((8, 6), "%s %s" % (lab, f.stem), fill=(255, 255, 0))
                col.paste(im, (0, i * a.box * 2))
            tiles.append(col)
    if not tiles:
        sys.exit("타일이 없다")
    w, h = tiles[0].size
    rows = (len(tiles) + a.cols - 1) // a.cols
    sh = Image.new("RGB", (a.cols * w, rows * h))
    for i, t in enumerate(tiles):
        sh.paste(t, ((i % a.cols) * w, (i // a.cols) * h))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sh.save(a.out)
    print("SHEET", a.out, sh.size, len(tiles))


if __name__ == "__main__":
    main()
