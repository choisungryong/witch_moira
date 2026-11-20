#!/usr/bin/env python3
"""세 마녀를 나란히 놓은 판과 잰 값(Blender 렌더 기준, Blender 필요 없음).

  python tools/art/char_board.py --out DIR --names ember,frost,storm \
      --color idle=DIR/game_idle_0_c.png --sil idle=DIR/game_idle_0_s.png [--color run=... --sil run=...] [--shuffle-seed 7]

입력은 `char_render.py game`이 낸 가로 한 줄 판(마녀 N명, 같은 간격)과 실루엣 판(--silhouette). 낸 것:
  board_color.png / board_gray.png / board_sil.png : 행 = 동작, 열 = 마녀(1배 그대로 + 3배 확대본 *_x3.png)
  board_color_shuffled.png (+ shuffle_key.json)    : 열 순서를 행마다 섞은 눈가림 판(이름 없음)
  board_stats.json                                  : 마녀 x 동작 별 주인공 화소 수, 평균 명도, 0.85 넘는 화소 비율, 원소 색상 화소 비율(자기 것과 남의 것)
주의: Blender 작업대 평면 조명 렌더이고 게임 조명·림 빛이 없다. 명도는 그 화면의 값이지 게임 안 값이 아니다.
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

import numpy as np

# 원소 색상 범위(도): 화염 주황, 냉기 청록~하늘, 번개 보라
ELEMENT_HUE = {"ember": (8.0, 45.0), "frost": (170.0, 225.0), "storm": (255.0, 305.0)}


def lum(a):
    return a @ np.array([0.299, 0.587, 0.114], np.float32)


def hue_sat_val(a):
    mx, mn = a.max(-1), a.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    rc, gc = nz & (mx == r), nz & (mx == g) & (mx != r)
    bc = nz & ~rc & ~gc
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    return h * 60.0, np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0), mx


def split_slots(img_w, n):
    """가로 한 줄 판을 n칸으로 가른 x 구간(칸 중심은 판 가운데에서 대칭)."""
    edges = np.linspace(0, img_w, n + 1)
    return [(int(edges[i]), int(edges[i + 1])) for i in range(n)]


def slot_stats(color, sil, names, sat_min=0.35, bright=0.85, mask_view=None, mask_thresh=0.12):
    """color: (H,W,3) float 0..1, sil: (H,W) bool(주인공 화소). 칸마다 잰 값."""
    out = {}
    H, W = sil.shape
    for name, (x0, x1) in zip(names, split_slots(W, len(names))):
        m = sil[:, x0:x1]
        c = color[:, x0:x1][m]
        if len(c) == 0:
            out[name] = {"pixels": 0}
            continue
        l = lum(c)
        h, s, v = hue_sat_val(c)
        st = {"pixels": int(len(c)), "height_px": int(np.ptp(np.where(m.any(1))[0]) + 1), "mean_luma": float(l.mean()),
              "frac_over_%.2f" % bright: float((l > bright).mean())}
        for el, (h0, h1) in ELEMENT_HUE.items():
            st["frac_hue_" + el] = float(((h >= h0) & (h <= h1) & (s >= sat_min)).mean())
        if mask_view is not None:   # 발광 가면만 입힌 렌더: 켜진 화소 / 주인공 화소 = 원소 자리 면적
            mv = lum(mask_view[:, x0:x1][m])
            st["frac_emission_mask"] = float((mv > mask_thresh).mean())
        out[name] = st
    return out


def load(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert("RGB"), np.float32) / 255.0


def main(argv=None):
    from PIL import Image
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--names", required=True, help="왼쪽부터 마녀 이름(쉼표)")
    ap.add_argument("--color", action="append", required=True, help="동작=색 판 경로")
    ap.add_argument("--sil", action="append", required=True, help="동작=실루엣 판 경로(같은 동작 이름)")
    ap.add_argument("--mask", action="append", default=[], help="동작=발광 가면만 입힌 판 경로(char_render --emission-mode only)")
    ap.add_argument("--shuffle-seed", type=int, default=7)
    ap.add_argument("--bg-thresh", type=float, default=0.35, help="실루엣 판에서 검정으로 칠한 화소의 밝기 기준")
    a = ap.parse_args(argv)
    names = a.names.split(",")
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    colors = dict(kv.split("=", 1) for kv in a.color)
    sils = dict(kv.split("=", 1) for kv in a.sil)
    masks = dict(kv.split("=", 1) for kv in a.mask)
    acts = list(colors)
    rng = random.Random(a.shuffle_seed)
    stats, rows_c, rows_g, rows_s, rows_sh, key = {}, [], [], [], [], {}
    for act in acts:
        c = load(colors[act])
        s = load(sils[act])
        mask = lum(s) < a.bg_thresh
        stats[act] = slot_stats(c, mask, names, mask_view=load(masks[act]) if act in masks else None)
        rows_c.append(c)
        g = np.repeat(lum(c)[..., None], 3, axis=2)
        rows_g.append(g)
        rows_s.append(np.repeat(mask[..., None].astype(np.float32) * 0.0 + (~mask)[..., None].astype(np.float32), 3, axis=2))
        slots = split_slots(c.shape[1], len(names))
        order = list(range(len(names)))
        rng.shuffle(order)
        key[act] = [names[i] for i in order]
        rows_sh.append(np.concatenate([c[:, slots[i][0]:slots[i][1]] for i in order], axis=1))

    def save(rows, name):
        sheet = np.concatenate(rows, axis=0)
        im = Image.fromarray((np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8))
        im.save(out / (name + ".png"))
        im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(out / (name + "_x3.png"))

    save(rows_c, "board_color")
    save(rows_g, "board_gray")
    save(rows_s, "board_sil")
    save(rows_sh, "board_color_shuffled")
    (out / "shuffle_key.json").write_text(json.dumps(key, ensure_ascii=False, indent=1), encoding="utf-8")
    (out / "board_stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({act: {n: {k: round(v, 3) if isinstance(v, float) else v for k, v in st.items()} for n, st in d.items()} for act, d in stats.items()}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
