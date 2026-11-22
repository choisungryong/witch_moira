"""턴어라운드 시트 한 장을 보기별 낱장으로 나눈다(그림→3D 서비스의 여러 면 입력용).

시트의 바탕은 한 가지 색이라고 본다. 세로 줄마다 바탕과 다른 화소를 세어, 빈 띠로 갈라진 덩어리를
왼쪽부터 --names 순서로 잘라 낸다. 덩어리 수가 이름 수와 다르면 아무것도 쓰지 않고 종료 코드 1.

    python tools/art/sheet_split.py <시트.png> --out <폴더> [--names front,left,back] [--pad 0.06] [--square]

표준 출력: 낱장마다 이름, 잘라 낸 상자, 크기(JSON 한 줄).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def find_runs(counts: list[int], min_fill: int, min_gap: int) -> list[tuple[int, int]]:
    """바탕 아닌 화소가 min_fill 넘는 세로 줄의 연속 구간. min_gap보다 좁은 틈은 한 덩어리로 잇는다."""
    runs: list[tuple[int, int]] = []
    start = None
    for x, c in enumerate(counts):
        if c > min_fill and start is None:
            start = x
        elif c <= min_fill and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, len(counts)))
    merged: list[tuple[int, int]] = []
    for run in runs:
        if merged and run[0] - merged[-1][1] < min_gap:
            merged[-1] = (merged[-1][0], run[1])
        else:
            merged.append(run)
    return merged


def split(sheet: Path, out: Path, names: list[str], pad: float, square: bool, threshold: int) -> list[dict]:
    im = Image.open(sheet).convert("RGB")
    w, h = im.size
    bg = im.getpixel((4, 4))
    diff = ImageChops.difference(im, Image.new("RGB", im.size, bg)).convert("L")
    mask = diff.point(lambda v: 255 if v > threshold else 0)
    # 세로 줄마다 바탕 아닌 화소 수: 높이 1로 줄여 평균을 얻고 높이를 곱한다.
    cols = mask.resize((w, 1), Image.BOX).getdata()
    counts = [round(v / 255 * h) for v in cols]
    runs = [r for r in find_runs(counts, max(2, h // 400), max(8, w // 60)) if r[1] - r[0] > w // 40]
    if len(runs) != len(names):
        raise SystemExit(f"덩어리 {len(runs)}개를 찾았는데 이름은 {len(names)}개다: {runs}")
    out.mkdir(parents=True, exist_ok=True)
    result = []
    for name, (x0, x1) in zip(names, runs):
        box_mask = mask.crop((x0, 0, x1, h)).getbbox()
        y0, y1 = (box_mask[1], box_mask[3]) if box_mask else (0, h)
        px = round((x1 - x0) * pad)
        py = round((y1 - y0) * pad)
        box = (max(0, x0 - px), max(0, y0 - py), min(w, x1 + px), min(h, y1 + py))
        piece = im.crop(box)
        if square:
            side = max(piece.size)
            canvas = Image.new("RGB", (side, side), bg)
            canvas.paste(piece, ((side - piece.width) // 2, (side - piece.height) // 2))
            piece = canvas
        path = out / f"{name}.png"
        piece.save(path)
        result.append({"name": name, "file": str(path), "box": box, "size": piece.size})
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sheet", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--names", default="front,left,back")
    ap.add_argument("--pad", type=float, default=0.06)
    ap.add_argument("--square", action="store_true")
    ap.add_argument("--threshold", type=int, default=18)
    a = ap.parse_args()
    for row in split(a.sheet, a.out, a.names.split(","), a.pad, a.square, a.threshold):
        print(json.dumps(row, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
