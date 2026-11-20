#!/usr/bin/env python3
"""게임 안 캡처에서 주인공 영역의 밝기 잘림을 잰다(PIL·numpy). rig_game_probe.gd --hero-mask --hero-crop-ticks 의 crop_tNNNN.png + crop_tNNNN.mask.png 가 입력이다.

  python tools/art/hero_burn.py <캡처 폴더> [--out burn.json]
출력: 틱마다 주인공 화소 수, 한 채널이라도 255 근처(>=254)인 비율(clip), 세 채널 모두 240 이상인 비율(white), 평균 밝기. 마스크 알파 > 0.5 가 주인공 화소.
"""
from __future__ import annotations

import argparse
import glob
import json
import os

import numpy as np
from PIL import Image


def measure(folder):
    rows = []
    for p in sorted(glob.glob(os.path.join(folder, "crop_t*.png"))):
        if p.endswith(".mask.png") or p.endswith(".emit.png"):
            continue
        mp = p[:-4] + ".mask.png"
        if not os.path.exists(mp):
            continue
        im = np.asarray(Image.open(p).convert("RGB")).astype(int)
        al = np.asarray(Image.open(mp).convert("RGBA"))[..., 3] > 127
        n = int(al.sum())
        if n == 0:
            rows.append({"file": os.path.basename(p), "pixels": 0})
            continue
        px = im[al]
        ys = np.where(al.any(1))[0]
        cut = ys.min() + 0.72 * (ys.max() - ys.min() + 1)      # 발밑 고리(게임이 겹쳐 그림)를 뺀 윗부분
        up = al.copy()
        up[int(cut):] = False
        pu = im[up]
        rows.append({"file": os.path.basename(p), "pixels": n, "clip": float((px.max(1) >= 254).mean()), "white": float((px.min(1) >= 240).mean()), "mean": float(px.mean()),
                     "clip_upper": float((pu.max(1) >= 254).mean()) if len(pu) else 0.0})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--out")
    a = ap.parse_args()
    rows = measure(a.folder)
    for r in rows:
        print(r)
    ok = [r for r in rows if r["pixels"] > 0]
    if ok:
        print("MEAN clip %.3f clip_upper %.3f white %.3f over %d crops" % (np.mean([r["clip"] for r in ok]), np.mean([r["clip_upper"] for r in ok]), np.mean([r["white"] for r in ok]), len(ok)))
    if a.out:
        json.dump(rows, open(a.out, "w"))


if __name__ == "__main__":
    main()
