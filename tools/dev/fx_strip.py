"""Contact strip of effect captures: crops every frame around its fire-coloured pixels (or a fixed box) and enlarges them.

  python tools/dev/fx_strip.py <out.png> <scale> <crop> <frame> [<frame> ...]    (frames: files or globs, in order)
  crop = "auto:<size>" (centre on the orange pixels' centroid, keep the last when none; size in px) or "x,y,w,h" (fixed box)
Used by the fireball before/after panels (_local/art/fireball). Needs Pillow.
"""
import glob, sys
from PIL import Image, ImageDraw


def centroid(img):
    px = img.convert("RGB").load()
    w, h = img.size
    sx = sy = n = 0
    for y in range(0, h - 140, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if r > 215 and 0.28 < g / max(r, 1) < 0.62 and b < 90:
                sx += x; sy += y; n += 1
    return (sx // n, sy // n) if n > 3 else None


def main():
    out, scale, crop = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    files = []
    for a in sys.argv[4:]:
        files += sorted(glob.glob(a)) or [a]
    tiles, last = [], None
    for f in files:
        im = Image.open(f).convert("RGB")
        if crop.startswith("auto:"):
            s = int(crop[5:])
            c = centroid(im) or last or (im.width // 2, im.height // 2)
            last = c
            box = (c[0] - s // 2, c[1] - s // 2, c[0] + s // 2, c[1] + s // 2)
        else:
            x, y, w, h = [int(v) for v in crop.split(",")]
            box = (x, y, x + w, y + h)
        t = im.crop(box).resize((int((box[2] - box[0]) * scale), int((box[3] - box[1]) * scale)), Image.LANCZOS)
        ImageDraw.Draw(t).text((4, 2), f.replace("\\", "/").split("/")[-1][-22:-4], fill=(255, 255, 255))
        tiles.append(t)
    W = sum(t.width for t in tiles) + 4 * (len(tiles) - 1)
    sheet = Image.new("RGB", (W, max(t.height for t in tiles)), (0, 0, 0))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0)); x += t.width + 4
    sheet.save(out)
    print(out, sheet.size)


main()
