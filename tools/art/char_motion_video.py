#!/usr/bin/env python3
"""동작 미리보기 영상: 마디(segment)를 이어 붙여 mp4 하나로 만든다(Blender + ffmpeg 필요, 한 번에 하나).

  python tools/art/char_motion_video.py --work DIR --out x.mp4 --mult 3 \
      --seg "glb|game|run|39|3.0"  --seg "glb|side|run|39|3.0"  --seg "glb|game|idle|150|2.0"
마디 = 모델 glb | 카메라(game/side/front) | 동작 이름 | 한 번에 렌더할 프레임 수 | 영상 길이(초, 짧으면 반복·길면 자름). 60fps 실시간.
순환 동작은 프레임 수를 한 주기(끝의 중복 프레임 뺀 것)로 준다. --label이 있으면 마디마다 왼쪽 위에 글자를 얹는다(ffmpeg drawtext, 글꼴이 없으면 생략).
Blender 작업대 평면 조명 렌더라 게임 장면·손맛이 아니다. 발 미끄러짐·팔다리 엇갈림 같은 움직임의 결을 프레임으로 보는 용도다.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def render_seq(model, d, cam, clip, n, mult):
    d.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([sys.executable, str(HERE / "char_render.py"), "game", "--model", str(model), "--xs", "0", "--out", str(d), "--game-frame", "%s:0" % clip,
                        "--seq", "%s:0:%d" % (clip, n - 1), "--cam", cam, "--res-mult", str(mult), "--bg", "0.18,0.19,0.2"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise SystemExit("렌더 실패 %s %s: %s" % (cam, clip, r.stdout[-500:]))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--seg", action="append", required=True, help="glb|카메라|동작|프레임수|초")
    ap.add_argument("--out", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--mult", type=int, default=3)
    a = ap.parse_args(argv)
    ff = shutil.which("ffmpeg")
    if not ff:
        raise SystemExit("ffmpeg가 없다")
    work = Path(a.work)
    parts = []
    for k, seg in enumerate(a.seg):
        glb, cam, clip, n, secs = seg.split("|")
        n, secs = int(n), float(secs)
        d = work / ("seg%02d_%s_%s" % (k, cam, clip))
        render_seq(glb, d, cam, clip, n, a.mult)
        outp = work / ("seg%02d.mp4" % k)
        loops = max(1, int(-(-secs * 60 // n)))
        vf = "loop=loop=%d:size=%d:start=0,trim=duration=%.3f,scale=trunc(iw/2)*2:trunc(ih/2)*2" % (loops - 1, n, secs)
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "60", "-i", str(d / "seq_%03d.png"), "-vf", vf,
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "60", str(outp)], check=True)
        parts.append(outp)
    lst = work / "concat.txt"
    lst.write_text("".join("file '%s'\n" % str(p).replace("\\", "/") for p in parts), encoding="utf-8")
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", a.out], check=True)
    print("MOTION_VIDEO_OK", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
