"""녹화 영상의 구간을 원래 프레임률로 뽑아 잘라 확대하고, 프레임 번호를 붙여 가로 띠(판)로 이어 붙인다.

기준작 녹화를 눈으로 셀 때 쓴다(걸음 박자, 꺾기, 시전 앞뒤 프레임 등). 결과는 _local/ 아래에만 둔다.
Godot를 쓰지 않는다. ffmpeg와 Pillow가 필요하다.

예:
  python tools/dev/video_strip.py _local/ref/sacrata/yt/sacrata-yt-0-21m.mp4 --start 342 --dur 2 \
      --crop 760,300,400,300 --scale 2 --cols 10 --out _local/art/a7/sacrata/strip-0542.png
  # 전체 화면을 한 장 보고 주인공 위치를 찾을 때: --dur 0.04 --scale 0.5
  # 매 N번째 프레임만: --step 2
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


def find_ffmpeg():
    p = shutil.which("ffmpeg")
    if p:
        return p
    sys.exit("ffmpeg를 찾지 못했다")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--start", type=float, required=True, help="시작 초")
    ap.add_argument("--dur", type=float, required=True, help="길이 초")
    ap.add_argument("--crop", default="", help="x,y,w,h (원본 화소). 없으면 전체")
    ap.add_argument("--scale", type=float, default=1.0, help="자른 뒤 배율")
    ap.add_argument("--cols", type=int, default=10, help="한 줄 칸 수")
    ap.add_argument("--step", type=int, default=1, help="N프레임마다 한 장")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    vf = []
    # 녹화가 가변 프레임률(30틱 기준으로 프레임이 드문드문 빠짐)이라 30fps 고정으로 다시 뽑아 시간 눈금을 맞춘다.
    # 빠진 틱은 앞 프레임이 반복된다(띠에서 같은 그림이 두 칸).
    vf.append("fps=30")
    if a.crop:
        x, y, w, h = [int(v) for v in a.crop.split(",")]
        vf.append(f"crop={w}:{h}:{x}:{y}")
    if a.step > 1:
        vf.append(f"select='not(mod(n\\,{a.step}))'")
    if a.scale != 1.0:
        vf.append(f"scale=iw*{a.scale}:ih*{a.scale}:flags=lanczos")
    with tempfile.TemporaryDirectory() as tmp:
        cmd = [find_ffmpeg(), "-v", "error", "-ss", str(a.start), "-t", str(a.dur), "-i", a.video]
        if vf:
            cmd += ["-vf", ",".join(vf)]
        cmd += ["-vsync", "0", f"{tmp}/f%04d.png"]
        subprocess.run(cmd, check=True)
        files = sorted(Path(tmp).glob("f*.png"))
        if not files:
            sys.exit("뽑힌 프레임이 없다")
        fps = 30.0
        probe = subprocess.run([shutil.which("ffprobe"), "-v", "error", "-select_streams", "v:0", "-show_entries",
                                "stream=r_frame_rate", "-of", "csv=p=0", a.video], capture_output=True, text=True)
        try:
            n, d = probe.stdout.strip().split("/")
            fps = float(n) / float(d)
        except Exception:
            pass
        imgs = [Image.open(f).convert("RGB") for f in files]
        w, h = imgs[0].size
        cols = max(1, min(a.cols, len(imgs)))
        rows = (len(imgs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * h), (0, 0, 0))
        dr = ImageDraw.Draw(sheet)
        for i, im in enumerate(imgs):
            cx, cy = (i % cols) * w, (i // cols) * h
            sheet.paste(im, (cx, cy))
            t = a.start + i * a.step / 30.0
            dr.rectangle([cx, cy, cx + 74, cy + 12], fill=(0, 0, 0))
            dr.text((cx + 2, cy + 1), f"{i * a.step:03d} {t:.2f}s", fill=(255, 255, 0))
            dr.rectangle([cx, cy, cx + w - 1, cy + h - 1], outline=(60, 60, 60))
        sheet.save(out)
        print(f"{out}  {len(imgs)}프레임  칸 {w}x{h}  판 {sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
