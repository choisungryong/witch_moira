#!/usr/bin/env python3
"""프레임 PNG 묶음을 이어 붙여 구간(6초 넘게)으로 만들고 한 mp4로 잇는다(ffmpeg 필요). 한 주기 프레임을 되풀이해 길이를 채운다.

  python tools/art/gen3d_video.py --out out.mp4 --seg "이름|fps|최소초|패턴1[;패턴2;...]" [--seg ...] [--height 540]
  패턴은 %d나 * 가 든 PNG 경로(정수 순서 정렬). 패턴이 여럿이면 가로로 붙인다(같은 프레임 수여야 함). 구간마다 이름을 화면 위에 적는다.
  예) --seg "run side-front-game|30|7|D:/x/m0_side_t*.png;D:/x/m0_front_t*.png"
"""
from __future__ import annotations

import argparse
import glob
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


def natural(p):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", p)]


def build_seg(name, fps, min_s, patterns, height, tmp):
    cols = [sorted(glob.glob(p), key=natural) for p in patterns]
    n = min(len(c) for c in cols)
    if n == 0:
        sys.exit("프레임이 없다: %s" % patterns)
    d = Path(tmp) / re.sub(r"\W+", "_", name)
    d.mkdir(parents=True, exist_ok=True)
    loops = max(1, math.ceil(min_s * fps / n))
    for i in range(n):
        ims = []
        for c in cols:
            im = Image.open(c[i]).convert("RGB")
            ims.append(im.resize((int(im.width * height / im.height) // 2 * 2, height // 2 * 2), Image.LANCZOS))
        w = sum(i2.width for i2 in ims)
        fr = Image.new("RGB", (w, ims[0].height))
        x = 0
        for i2 in ims:
            fr.paste(i2, (x, 0))
            x += i2.width
        ImageDraw.Draw(fr).text((8, 6), name, fill=(255, 255, 0))
        fr.save(d / ("f%04d.png" % i))
    out = Path(tmp) / (d.name + ".mp4")
    # 한 주기를 loops번 되풀이: 프레임 목록을 이어서 입력
    lst = Path(tmp) / (d.name + ".txt")
    lines = []
    for _ in range(loops):
        for i in range(n):
            lines.append("file '%s'\nduration %f" % ((d / ("f%04d.png" % i)).as_posix(), 1.0 / fps))
    lst.write_text("\n".join(lines), encoding="utf-8")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-r", str(fps), "-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "18", str(out)], check=True)
    return out, n, loops, n * loops / fps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seg", action="append", required=True)
    ap.add_argument("--height", type=int, default=540)
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="gen3d_video_")
    segs = []
    for s in a.seg:
        name, fps, min_s, pats = s.split("|")
        out, n, loops, secs = build_seg(name, float(fps), float(min_s), pats.split(";"), a.height, tmp)
        print("SEG", name, "frames", n, "loops", loops, "seconds %.2f" % secs)
        segs.append(out)
    # 구간 이음: 크기가 다르면 첫 구간 폭에 맞춰 레터박스
    W = max(Image.open(next(Path(tmp).glob(re.sub(r"\W+", "_", s.split("|")[0]) + "/f0000.png"))).width for s in a.seg)
    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    for sgm in segs:
        cmd += ["-i", str(sgm)]
    flt = "".join("[%d:v]scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v%d];" % (i, W, a.height, W, a.height, i) for i in range(len(segs)))
    flt += "".join("[v%d]" % i for i in range(len(segs))) + "concat=n=%d:v=1:a=0[o]" % len(segs)
    cmd += ["-filter_complex", flt, "-map", "[o]", "-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "18", a.out]
    subprocess.run(cmd, check=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print("VIDEO", a.out)


if __name__ == "__main__":
    main()
