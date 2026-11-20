#!/usr/bin/env python3
"""그림 여러 장을 한 장에 격자로 붙인다(원본 그림과 렌더 나란히 보기용). Blender 필요 없음.

  python tools/art/char_montage.py --out sheet.png --height 640 --row front.png,r/front.png,... --row 3q.png,...
행(--row)마다 쉼표로 이은 그림들을 높이 --height 로 맞춰 가로로 붙이고, 행을 세로로 쌓는다. 파일이 없으면 회색 칸.
"""
from __future__ import annotations

import argparse
from pathlib import Path


def montage(rows, height, out, gap=4, bg=(70, 70, 74), crop=None, gray=False):
    """crop = (x0, y0, x1, y1) 0..1 비율. 모든 그림에 같은 비율 구간을 잘라 쓴다(같은 틀로 찍은 그림끼리 확대 비교)."""
    from PIL import Image
    imgs_rows = []
    for row in rows:
        ims = []
        for p in row:
            if p and Path(p).is_file():
                im = Image.open(p).convert("RGB")
                if gray:
                    im = im.convert("L").convert("RGB")
                if crop:
                    im = im.crop((int(crop[0] * im.width), int(crop[1] * im.height), int(crop[2] * im.width), int(crop[3] * im.height)))
                w = int(round(im.width * height / im.height))
                ims.append(im.resize((w, height), Image.LANCZOS))
            else:
                ims.append(Image.new("RGB", (height // 2, height), (128, 128, 128)))
        imgs_rows.append(ims)
    W = max(sum(i.width for i in r) + gap * (len(r) - 1) for r in imgs_rows)
    H = len(imgs_rows) * height + gap * (len(imgs_rows) - 1)
    sheet = Image.new("RGB", (W, H), bg)
    y = 0
    for r in imgs_rows:
        x = 0
        for im in r:
            sheet.paste(im, (x, y))
            x += im.width + gap
        y += height + gap
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return sheet.size


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--height", type=int, default=640)
    ap.add_argument("--row", action="append", required=True)
    ap.add_argument("--crop", help="x0,y0,x1,y1 (0..1 비율)")
    ap.add_argument("--gray", action="store_true", help="회색조로")
    a = ap.parse_args(argv)
    crop = tuple(float(v) for v in a.crop.split(",")) if a.crop else None
    print("montage", montage([r.split(",") for r in a.row], a.height, a.out, crop=crop, gray=a.gray))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
