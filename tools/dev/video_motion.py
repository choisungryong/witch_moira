"""녹화 영상의 화면 흐름(카메라가 주인공을 따라가므로 = 주인공의 이동 속도)을 프레임마다 잰다.

위상 상관으로 연속 두 프레임 사이의 배경 이동(원본 화소 단위)을 구해 CSV로 저장하고, 속도 구간(달림/섬)을 요약한다.
이동 구간·정지 구간·꺾기를 찾은 뒤 video_strip.py로 그 구간의 띠를 본다. 메뉴·은총 화면은 값이 의미 없다.
ffmpeg, numpy가 필요하다. Godot를 쓰지 않는다. 가변 프레임률 녹화는 30fps로 다시 맞춘다.

예: python tools/dev/video_motion.py VIDEO --start 342 --dur 120 --out _local/art/a7/sacrata/motion.csv
"""
import argparse
import shutil
import subprocess
import sys

import numpy as np

W, H = 960, 540  # 분석 해상도(원본 1920x1080의 1/2)
K = 1920 // W
# 분석 영역(분석 해상도 기준): 우측 목표 틀, 하단 HUD를 피한다
RX, RY, RW, RH = 180, 100, 512, 256


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--dur", type=float, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--region", default="", help="x,y,w,h 원본 화소. 없으면 전투 화면의 중앙 배경 영역. 은총 화면 인물 같은 고정 화면의 작은 움직임은 인물 영역을 준다")
    ap.add_argument("--still", type=float, default=0.6, help="이 값(원본 화소/프레임) 이하면 선 것으로 본다")
    a = ap.parse_args()
    global RX, RY, RW, RH
    if a.region:
        rx, ry, rw, rh = [int(v) // K for v in a.region.split(",")]
        RX, RY, RW, RH = rx, ry, rw // 2 * 2, rh // 2 * 2
    ff = shutil.which("ffmpeg")
    if not ff:
        sys.exit("ffmpeg를 찾지 못했다")
    cmd = [ff, "-v", "error", "-ss", str(a.start), "-t", str(a.dur), "-i", a.video,
           "-vf", f"fps=30,scale={W}:{H},format=gray", "-f", "rawvideo", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    win = np.outer(np.hanning(RH), np.hanning(RW))
    prev = None
    rows = []
    n = 0
    while True:
        buf = p.stdout.read(W * H)
        if len(buf) < W * H:
            break
        f = np.frombuffer(buf, np.uint8).reshape(H, W).astype(np.float32)[RY:RY + RH, RX:RX + RW]
        f = (f - f.mean()) * win
        if prev is not None:
            r = np.fft.fft2(prev) * np.conj(np.fft.fft2(f))
            r /= np.abs(r) + 1e-6
            c = np.real(np.fft.ifft2(r))
            iy, ix = np.unravel_index(np.argmax(c), c.shape)
            if iy > RH // 2:
                iy -= RH
            if ix > RW // 2:
                ix -= RW
            conf = float(c.max())
            # 부화소 보정(포물선)
            y0, x0 = np.unravel_index(np.argmax(c), c.shape)
            def sub(m, z, p):
                d = m - 2 * z + p
                return 0.0 if abs(d) < 1e-9 else 0.5 * (m - p) / d
            fx = sub(c[y0, (x0 - 1) % RW], c[y0, x0], c[y0, (x0 + 1) % RW])
            fy = sub(c[(y0 - 1) % RH, x0], c[y0, x0], c[(y0 + 1) % RH, x0])
            rows.append((a.start + n / 30.0, (ix + fx) * K, (iy + fy) * K, conf))
        prev = f
        n += 1
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write("t,dx,dy,conf\n")
        for t, dx, dy, cf in rows:
            fh.write(f"{t:.3f},{dx:.1f},{dy:.1f},{cf:.3f}\n")
    sp = np.array([np.hypot(r[1], r[2]) for r in rows])
    print(f"{a.out}  {len(rows)}프레임  평균 속도 {sp.mean():.1f}px/프레임")
    # 구간 요약: 선 구간(연속 6프레임 이상)
    still = sp <= a.still
    i = 0
    while i < len(still):
        if still[i]:
            j = i
            while j < len(still) and still[j]:
                j += 1
            if j - i >= 6:
                print(f"선 구간 {rows[i][0]:.2f}~{rows[j - 1][0]:.2f}s ({j - i}프레임)")
            i = j
        else:
            i += 1


if __name__ == "__main__":
    main()
