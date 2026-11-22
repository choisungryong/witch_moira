#!/usr/bin/env python3
"""게임 안 걸음 측정(chapter1/tests/hero_motion_probe.gd)을 돌려 캐릭터 화면의 계산과 견준다.

사용(저장소 루트에서):
  python tools/art/motion_verify.py --current                      # 지금 계약(달리기)
  python tools/art/motion_verify.py --clip walk --rate 1.3         # 덮어쓴 값으로(이 프로세스 안에서만, 제품 파일은 그대로)
  python tools/art/motion_verify.py --pick <고름 id>               # 고름 기록의 clip / rate / L / stride_world_m
  공통: --until <틱>(기본 840: 장비 이동 속도 보정이 붙기 전이라 v = 5.8) --speed <게임 이동 속도, 기본 5.8>
        --screen-slip <m/s>(화면이 잰 미끄러짐을 직접 준다)  --window(창 실행. 기본은 헤드리스)  --tag <이름>  --no-run <프로브 JSON>(이미 있는 결과를 견준다)

출력: 표 한 장(배율·미끄러짐: 계산, 화면, 게임 안 측정)과 종료 코드. 0 = 같음(배율 2% 안, 미끄러짐 0.15 m/s 안), 1 = 어긋남, 2 = 측정을 못 함.
허용치 2%, 0.15 m/s 는 [짐작]이다(T9 지시서 3.6절). 값을 맞추려고 고치지 않는다: 숫자를 보고 tech-lead 가 정한다.
계산은 tools/art/motion_math.py 를 부른다(식을 여기에 다시 쓰지 않는다).
측정 원시는 _local/t9-b1b/raw/ 아래. 사용자 저장은 읽지도 쓰지도 않는다(--chapter1-profile-off, godot.py 가 APPDATA 를 격리).
"""
import argparse, json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import motion_math as mm  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = HERE.parents[1]
REPORT = ROOT / "chapter1" / "art" / "actors" / "hero" / "frost" / "model.pack-report.json"
PICKS = ROOT / "tools" / "manager" / "local-picks.json"
RAW = ROOT / "_local" / "t9-b1b" / "raw"
SCALE = 1.32
GAME_SPEED = 5.8
RATE_TOL = 0.02       # [짐작]
SLIP_TOL = 0.15       # [짐작]
# 화면이 잰 값(B1-a 보고. 이번에 다시 재지 않았다). 키: (클립, 배율)
SCREEN_REPORTED = {("run", 0.606): 0.38, ("walk", 1.3): 1.95}


def clip_numbers(name, report_path=REPORT):
    """몸 보고서의 클립 길이 L 과 발끝 지면 속도 g(배율 전, 모델 공간)."""
    doc = json.loads(Path(report_path).read_text(encoding="utf-8"))
    row = doc["clips"][name]
    return float(row["length_s"]), float(row["ground_speed_toe_mps"])


def parse_probe_line(text):
    for line in text.splitlines():
        if line.startswith("HERO_MOTION_PROBE "):
            return json.loads(line[len("HERO_MOTION_PROBE "):])
    return None


def compare(measured, v_game, length_s, stride, g, scale, screen_slip=None, screen_label="계산값"):
    """프로브 결과 한 벌과 계산을 견준다. 표(rows)와 판정을 돌려준다. 순수 함수(시험이 부른다)."""
    rate_game = mm.rate_from_contract(v_game, length_s, stride)
    v_seen = measured["avg_speed_mps"]
    rate_at_seen = mm.rate_from_contract(v_seen, length_s, stride)
    slip_calc = mm.slip(v_game, rate_game, g, scale)
    rate_m = measured["rate_measured"]
    slip_m = measured["slip_rms_mps"]
    rate_diff = (rate_m - rate_game) / rate_game
    ref_slip = slip_calc if screen_slip is None else screen_slip
    slip_diff = slip_m - ref_slip
    rate_ok = abs(rate_diff) <= RATE_TOL
    slip_ok = abs(slip_diff) <= SLIP_TOL
    rows = [
        ("이동 속도 v (m/s)", "%.3f" % v_game, "", "%.3f" % v_seen),
        ("동작 배율 r", "%.4f" % rate_game, "", "%.4f" % rate_m),
        ("  게임 안 속도로 환산한 r", "%.4f" % rate_at_seen, "", ""),
        ("  r 차이(게임 안 - 계산, 비율)", "", "", "%+.2f%% (허용 %.0f%%)" % (rate_diff * 100, RATE_TOL * 100)),
        ("미끄러짐 (m/s)", "%.3f 계산" % slip_calc, "%s %.3f" % (screen_label, ref_slip), "%.3f RMS(앞뒤) / %.3f(수평 전체)" % (slip_m, measured["slip_rms_horiz_mps"])),
        ("  미끄러짐 차이(게임 안 - 화면)", "", "", "%+.3f (허용 %.2f)" % (slip_diff, SLIP_TOL)),
        ("표본", "", "", "디딤 %d, 곧은 1초 구간 %d/%d" % (measured["stance_samples"], measured["windows_used"], measured["windows_total"])),
    ]
    return {"rows": rows, "rate_game": rate_game, "rate_diff": rate_diff, "slip_calc": slip_calc, "slip_diff": slip_diff,
            "rate_ok": rate_ok, "slip_ok": slip_ok, "same": rate_ok and slip_ok}


def usable(measured):
    return bool(measured) and "error" not in measured and measured.get("rate_measured") is not None and measured.get("slip_rms_mps") is not None


def table(result, title):
    out = [title, "%-34s %-18s %-22s %s" % ("", "계산(모델의 답)", "화면", "게임 안 측정")]
    for a, b, c, d in result["rows"]:
        out.append("%-34s %-18s %-22s %s" % (a, b, c, d))
    out.append("판정: 배율 %s, 미끄러짐 %s -> %s" % ("같음" if result["rate_ok"] else "어긋남", "같음" if result["slip_ok"] else "어긋남", "같음" if result["same"] else "어긋남"))
    return "\n".join(out)


def build_probe_args(override, until, tag, window):
    args = [sys.executable, str(ROOT / "tools" / "dev" / "godot.py")]
    if not window:
        args.append("--headless")
    args += ["--fixed-fps", "60", "--path", str(ROOT), "--script", "res://chapter1/tests/hero_motion_probe.gd", "--",
             "--chapter1-profile-off", "--chapter1-qa-ignore-focus", "--chapter1-hero-models", "--chapter1-primary=chapter1.skill.frost",
             "--chapter1-seed=11", "--primary=chapter1.skill.frost", "--until=%d" % (until + 100), "--stop-tick=%d" % until, "--drive=square",
             "--motion-json=_local/t9-b1b/raw/%s.json" % tag]
    if override:
        args.append("--pose-override=" + json.dumps(override, separators=(",", ":")))
    return args


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--current", action="store_true")
    g.add_argument("--clip")
    g.add_argument("--pick")
    ap.add_argument("--rate", type=float)
    ap.add_argument("--until", type=int, default=840)
    ap.add_argument("--speed", type=float, default=GAME_SPEED)
    ap.add_argument("--screen-slip", type=float, default=None)
    ap.add_argument("--window", action="store_true")
    ap.add_argument("--tag", default=None)
    ap.add_argument("--no-run", default=None)
    ap.add_argument("--picks", default=str(PICKS))
    a = ap.parse_args(argv)
    if a.clip and a.rate is None:
        ap.error("--clip 은 --rate 와 함께")
    v = a.speed
    screen_label = "화면(받은 값)"
    try:
        if a.current:
            slots = json.loads((ROOT / "chapter1" / "art" / "asset_slots.json").read_text(encoding="utf-8"))
            c = slots["slots"]["actor.hero.frost.model"]["contract"] if "slots" in slots else slots["actor.hero.frost.model"]["contract"]
            clip = c["clips"]["run"]
            length_s = float(c["pose"]["run_time_scale"])
            stride = float(c["pose"]["stride_world_m"])
            override = {}
            tag = a.tag or "current"
            _, gnum = clip_numbers(clip)
        elif a.clip:
            clip = a.clip
            length_s, gnum = clip_numbers(clip)
            stride = mm.stride_for(v, length_s, a.rate)
            override = {"clip": clip, "run_time_scale": length_s, "stride_world_m": round(stride, 4)}
            tag = a.tag or "%s-%s" % (clip, ("%g" % a.rate).replace(".", "p"))
        else:
            rec = json.loads(Path(a.picks).read_text(encoding="utf-8"))["records"][a.pick]
            vals = rec["values"]
            clip = vals["clip"]
            length_s, gnum = clip_numbers(clip)
            length_s = float(vals.get("L", length_s))
            stride = float(vals["stride_world_m"])
            override = {"clip": clip, "run_time_scale": length_s, "stride_world_m": stride}
            tag = a.tag or "pick-" + a.pick
            if a.screen_slip is None and vals.get("slip_measured_mps") is not None:
                a.screen_slip = float(vals["slip_measured_mps"])
                screen_label = "화면(고름 기록)"
    except (OSError, KeyError, ValueError) as e:
        print("입력을 읽지 못함:", repr(e))
        return 2
    rate_nominal = mm.rate_from_contract(v, length_s, stride)
    if a.screen_slip is None:
        known = SCREEN_REPORTED.get((clip, round(rate_nominal, 3))) or SCREEN_REPORTED.get((clip, round(rate_nominal, 2)))
        if known is not None:
            a.screen_slip = known
            screen_label = "화면(B1-a 보고)"
    if a.no_run:
        measured = json.loads(Path(a.no_run).read_text(encoding="utf-8"))
    else:
        RAW.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(build_probe_args(override, a.until, tag, a.window), cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8", errors="replace")
        (RAW / (tag + ".log")).write_text(proc.stdout + "\n--- stderr ---\n" + proc.stderr, encoding="utf-8")
        measured = parse_probe_line(proc.stdout)
        if proc.returncode != 0 and not usable(measured):
            print("프로브가 실패함: 종료 코드 %d, 로그 %s" % (proc.returncode, RAW / (tag + ".log")))
            return 2
    if not usable(measured):
        print("측정 결과를 쓸 수 없음:", json.dumps(measured, ensure_ascii=False)[:300] if measured else "HERO_MOTION_PROBE 줄이 없음")
        return 2
    result = compare(measured, v, length_s, stride, gnum, SCALE, a.screen_slip, screen_label)
    print(table(result, "클립 %s, v=%.2f, L=%.5f, 보폭 %.4f, g=%.4f, 몸 배율 %.2f, 표시 %s" % (clip, v, length_s, stride, gnum, SCALE, measured.get("display"))))
    return 0 if result["same"] else 1


if __name__ == "__main__":
    sys.exit(main())
