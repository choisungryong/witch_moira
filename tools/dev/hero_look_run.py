"""주인공 겉모습 값(look)을 게임 조명에서 맞춰 보는 실행: 마녀 여러 명을 같은 장면 조건(시드 11, 틱 600·1500·2400)으로 찍고 잰 값과 판 A·B를 낸다.

rig_game_probe.gd(--hero-look, --hero-mask, --hero-crop-ticks)를 마녀마다 한 번씩 부르고, 끝나면 shot_review.py --hero-sheet로 측정한다. 창 실행이다(한 번에 하나).

  python tools/dev/hero_look_run.py --out=_local/art/a7/A7-look/run1 --res=1920x1080 \\
      --case frost=frost:D:/.../frost/final.glb:_local/.../frost.look.json --case storm=arc:D:/.../storm/final.glb:_local/.../storm.look.json
  --case 이름=주력(ember|frost|arc):glb(없으면 비움):look json(없으면 비움).  이름은 측정 폴더 이름이자 판의 마녀 이름(ember|frost|arc 중 주력과 같게 쓰는 것을 권한다)
  --measure-name 이름=ember|frost|arc   측정에서 쓸 마녀(원소색 기준). 기본은 주력
출력: <out>/<이름>-<해상도>/(crop_t*.png, 가면, full_t*.png), <out>/measure-<해상도>/(hero-measure.md/json, 판 A·B)
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PRIMARY = {"ember": "chapter1.skill.ember", "frost": "chapter1.skill.frost", "arc": "chapter1.skill.arc"}


def parse_case(text):
    name, _, rest = text.partition("=")
    parts = rest.split(":")
    # Windows 경로의 "D:/" 때문에 앞에서부터 주력, 나머지는 glb와 look을 ".glb:"로 가른다.
    primary = parts[0]
    tail = ":".join(parts[1:])
    glb, look = "", ""
    if ".glb" in tail:
        i = tail.index(".glb") + 4
        glb = tail[:i]
        look = tail[i + 1:] if len(tail) > i + 1 else ""
    else:
        look = tail.lstrip(":")
    return name, primary, glb, look


def user_sheet(out, res, labels, tick, path, zoom=2, full_width=480):
    """사용자에게 보낼 한 장: 마녀마다 자르기(240x240 x zoom)와 같은 틱의 전체 화면(축소)을 세로로 붙인다. labels = [(폴더 이름, 표시 이름)]."""
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    cell = 240 * zoom
    cols = []
    for name, text in labels:
        folder = os.path.join(out, "%s-%s" % (name, res))
        crop = Image.open(os.path.join(folder, "crop_t%04d.png" % tick)).convert("RGB").resize((cell, cell), Image.NEAREST)
        full = Image.open(os.path.join(folder, "full_t%04d.png" % tick)).convert("RGB")
        full = full.resize((cell, int(full.height * cell / full.width)), Image.LANCZOS)
        col = Image.new("RGB", (cell, 34 + cell + 4 + full.height), (40, 40, 44))
        ImageDraw.Draw(col).text((8, 4), text, fill=(240, 230, 200), font=font)
        col.paste(crop, (0, 34))
        col.paste(full, (0, 34 + cell + 4))
        cols.append(col)
    sheet = Image.new("RGB", (sum(c.width for c in cols) + 6 * (len(cols) - 1), max(c.height for c in cols)), (20, 20, 22))
    x = 0
    for c in cols:
        sheet.paste(c, (x, 0))
        x += c.width + 6
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sheet.save(path)
    return sheet.size


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--res", default="1920x1080")
    ap.add_argument("--case", action="append", required=True)
    ap.add_argument("--ticks", default="600,1500,2400")
    ap.add_argument("--seed", default="11")
    ap.add_argument("--probe-arg", action="append", default=[], help="rig_game_probe.gd에 그대로 넘기는 인수(여러 번). 예: --probe-arg=--vp-exp=glow=0")
    ap.add_argument("--keep-hud", action="store_true", help="HUD를 숨기지 않는다(기본은 숨김: 머리 위 표시가 흰 화소로 세어지는 것을 막는다)")
    ap.add_argument("--user-sheet", default=None, help="사용자에게 보낼 한 장(png 경로). --user-label 폴더이름=표시이름 을 열마다 준다")
    ap.add_argument("--user-label", action="append", default=[])
    ap.add_argument("--user-tick", default="1500")
    ap.add_argument("--no-run", action="store_true", help="찍지 않고 이미 있는 폴더만 측정")
    ap.add_argument("--measure-name", action="append", default=[])
    a = ap.parse_args(argv)
    until = int(a.ticks.split(",")[-1])
    out = os.path.abspath(a.out)
    names = dict(x.split("=") for x in a.measure_name)
    specs = []
    for item in a.case:
        name, primary, glb, look = parse_case(item)
        folder = os.path.join(out, "%s-%s" % (name, a.res))
        specs.append((names.get(name, primary), folder))
        if a.no_run:
            continue
        cmd = [sys.executable, os.path.join(ROOT, "tools", "dev", "godot.py"), "--fixed-fps", "60", "--resolution", a.res, "--path", ".",
               "--script", "res://chapter1/tests/rig_game_probe.gd", "--", "--chapter1-pilot", "--chapter1-profile-off", "--chapter1-qa-ignore-focus",
               "--chapter1-seed=" + a.seed, "--primary=" + PRIMARY[primary], "--hero-boost=0", "--hero-mask", "--hero-crop-ticks=" + a.ticks,
               "--shots=" + folder, "--until=%d" % (until + 20)]
        if not a.keep_hud:
            cmd.append("--vp-exp=hud=0")   # 머리 위 소유자 표시(HUD가 그림)가 주인공 화소를 덮지 않게
        cmd += a.probe_arg
        if not glb and not look:
            cmd.remove("--hero-boost=0")   # 옛 마법사 견줌용: 게임 그대로
        if glb:
            cmd.append("--model-glb=" + glb)
        if look:
            cmd.append("--hero-look=" + look)
            cmd.append("--hero-emit")   # 가면이 켜진 화소 비율(emit_pct)을 재려고 크롭 다음 프레임에 발광만 그린다
        print("RUN", name, flush=True)
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        for line in r.stdout.splitlines():
            if line.startswith(("PROBE_LOOK", "PROBE_ARGS")) or "SCRIPT ERROR" in line or "Parse Error" in line:
                print("  ", line[:300])
    if a.user_sheet:
        labels = [tuple(x.split("=", 1)) for x in a.user_label]
        print("user sheet", user_sheet(out, a.res, labels, int(a.user_tick), a.user_sheet))
    sheet = [sys.executable, os.path.join(ROOT, "tools", "dev", "shot_review.py"), "--out=" + os.path.join(out, "measure-" + a.res)]
    for n, f in specs:
        sheet += ["--hero-sheet", "%s=%s" % (n, f)]
    subprocess.run(sheet, cwd=ROOT, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
