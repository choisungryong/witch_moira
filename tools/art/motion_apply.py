#!/usr/bin/env python3
"""고름 기록(관리 툴 「캐릭터」 화면에서 저장)을 게임 자리표(chapter1/art/asset_slots.json)의 그 캐릭터 칸으로 옮긴다.

사용:
  python tools/art/motion_apply.py --pick <기록 id>             # 보기만: 바뀔 줄의 앞과 뒤를 보여 준다(파일을 쓰지 않는다)
  python tools/art/motion_apply.py --pick <기록 id> --write      # 그 칸의 값 글자만 바꾼다
  python tools/art/motion_apply.py --pick <기록 id> --check      # 자리표의 v x L / stride 가 고름의 배율과 1e-3 안인지(종료 코드 0/1)
  --slots <경로>   다른 자리표 파일을 준다(시험용)   --picks <경로>   다른 고름 파일을 준다(기본 tools/manager/local-picks.json)

고치는 것(그 칸 안에서만): contract.clips.run(클립 이름), contract.pose.run_time_scale(= 한 주기의 길이 L),
contract.pose.stride_world_m(= v x L / 배율), 그리고 source 글의 걸음 문장 한 구간.
JSON을 읽어 통째로 다시 쓰지 않는다(다른 줄의 모양이 바뀐다). 글자만 바꾸고 줄바꿈 바이트는 그대로 둔다(.gitattributes 가 * -text).
이동 속도 제안(proposals)은 적용하지 않는다. 그것은 design-lead 의 몫이다.
"""
import argparse, difflib, json, os, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import motion_math  # noqa: E402

ROOT = HERE.parents[1]
SLOTS = ROOT / "chapter1" / "art" / "asset_slots.json"
PICKS = ROOT / "tools" / "manager" / "local-picks.json"
RATE_TOL = 1e-3
NUM = r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"


class ApplyError(Exception):
    pass


def load_pick(picks_path, pick_id):
    p = Path(picks_path)
    if not p.is_file():
        raise ApplyError("고름 파일이 없다: %s" % p)
    doc = json.loads(p.read_text(encoding="utf-8"))
    rec = (doc.get("records") or {}).get(pick_id)
    if rec is None:
        raise ApplyError("고름 기록이 없다: %s" % pick_id)
    if rec.get("verdict") != "pick":
        raise ApplyError("이 기록의 판정이 '이걸로(pick)'가 아니다: %s" % rec.get("verdict"))
    return rec


def pick_values(rec):
    """기록에서 적용에 쓸 값을 꺼낸다. 필요한 칸이 없으면 지어내지 않고 멈춘다."""
    v = rec.get("values") or {}
    need = ["slot", "clip", "rate", "L"]
    missing = [k for k in need if v.get(k) in (None, "")]
    if missing:
        raise ApplyError("고름 기록 values 에 빠진 칸: %s" % ", ".join(missing))
    stride = v.get("contract_now", v.get("stride_world_m"))
    if stride in (None, ""):
        raise ApplyError("고름 기록에 보폭 값(contract_now 또는 stride_world_m)이 없다")
    speed = v.get("speed_game", v.get("speed_seen"))
    if speed in (None, ""):
        raise ApplyError("고름 기록에 게임 이동 속도(speed_game)가 없다")
    return {"slot": v["slot"], "clip": v["clip"], "rate": float(v["rate"]), "L": float(v["L"]),
            "stride": float(stride), "speed_game": float(speed), "clip_source": v.get("clip_source", "body")}


def fmt(x, digits):
    s = ("%." + str(digits) + "f") % x
    return s.rstrip("0").rstrip(".") if "." in s else s


def block_span(text, slot):
    """"<slot>": { ... } 한 칸의 [시작, 끝) 글자 범위. 문자열 안의 중괄호는 세지 않는다."""
    m = re.search(r'"%s"\s*:\s*\{' % re.escape(slot), text)
    if not m:
        raise ApplyError("자리표에 칸이 없다: %s" % slot)
    depth, i, in_str, esc = 0, m.end() - 1, False, False
    while i < len(text):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return m.start(), i + 1
        i += 1
    raise ApplyError("칸의 끝을 찾지 못했다: %s" % slot)


def sub_once(block, pattern, repl, what):
    found = re.findall(pattern, block, flags=re.S)
    if len(found) != 1:
        raise ApplyError("%s: 바꿀 자리가 정확히 하나여야 하는데 %d개" % (what, len(found)))
    return re.sub(pattern, repl, block, count=1, flags=re.S)


def walk_sentence(vals, pick_id):
    return ("run = clip '%s' (rate x%s, in place), stride_world_m = move speed %s m/s x clip length %s s / rate %s "
            "(pick %s, tools/art/motion_apply.py)" % (vals["clip"], fmt(vals["rate"], 3), fmt(vals["speed_game"], 3),
                                                      fmt(vals["L"], 7), fmt(vals["rate"], 3), pick_id))


def edited_text(text, vals, pick_id, body_clips=None):
    s, e = block_span(text, vals["slot"])
    block = text[s:e]
    if body_clips is not None and vals["clip"] not in body_clips:
        raise ApplyError("클립 '%s' 이 지금 몸에 없다(몸의 클립: %s). 후보 묶음의 클립은 먼저 몸에 넣어야 한다(T9 B1-d 2단계)." % (vals["clip"], ", ".join(sorted(body_clips))))
    block = sub_once(block, r'("clips"\s*:\s*\{[^}]*?"run"\s*:\s*)"[^"]*"', lambda m: m.group(1) + '"%s"' % vals["clip"], "clips.run")
    block = sub_once(block, r'("run_time_scale"\s*:\s*)' + NUM, lambda m: m.group(1) + fmt(vals["L"], 7), "pose.run_time_scale")
    block = sub_once(block, r'("stride_world_m"\s*:\s*)' + NUM, lambda m: m.group(1) + fmt(vals["stride"], 3), "pose.stride_world_m")
    sent = walk_sentence(vals, pick_id)
    block = sub_once(block, r'(?<="source": ")(.*?)(run = clip .*?)(?=; idle = )', lambda m: m.group(1) + sent, "source 걸음 문장")
    return text[:s] + block + text[e:]


def body_clip_names(slots_path, slot):
    """자리표가 가리키는 몸 옆의 pack-report 에서 클립 이름. 파일이 없으면 None(검사 생략하고 알림)."""
    try:
        doc = json.loads(Path(slots_path).read_text(encoding="utf-8"))
        rel = doc["slots"][slot]["file"]
    except (OSError, ValueError, KeyError):
        return None
    base = Path(slots_path).resolve().parent
    rep = (base / rel).with_suffix(".pack-report.json")
    if not rep.is_file():
        return None
    try:
        return set((json.loads(rep.read_text(encoding="utf-8")).get("clips") or {}).keys())
    except ValueError:
        return None


def show_diff(old, new):
    a, b = old.splitlines(keepends=True), new.splitlines(keepends=True)
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        for k in range(i1, i2):
            out.append("- %5d  %s" % (k + 1, a[k].rstrip("\r\n")[:200]))
        for k in range(j1, j2):
            out.append("+ %5d  %s" % (k + 1, b[k].rstrip("\r\n")[:200]))
    return out


def verify_after(path, vals, original_text):
    """다시 읽어 세 값이 기대와 같은지, 바뀐 줄이 그 칸 안의 넷 이하인지."""
    raw = Path(path).read_bytes().decode("utf-8")
    doc = json.loads(raw)
    c = doc["slots"][vals["slot"]]["contract"]
    ok = (c["clips"]["run"] == vals["clip"] and abs(c["pose"]["run_time_scale"] - vals["L"]) < 1e-6
          and abs(c["pose"]["stride_world_m"] - vals["stride"]) < 1e-3)
    changed = [l for l in show_diff(original_text, raw)]
    return ok and len(changed) <= 8, changed


def check(slots_path, vals):
    doc = json.loads(Path(slots_path).read_text(encoding="utf-8"))
    c = doc["slots"][vals["slot"]]["contract"]
    rate = motion_math.rate_from_contract(vals["speed_game"], c["pose"]["run_time_scale"], c["pose"]["stride_world_m"])
    problems = []
    if c["clips"]["run"] != vals["clip"]:
        problems.append("클립 이름: 자리표 %s, 고름 %s" % (c["clips"]["run"], vals["clip"]))
    if abs(c["pose"]["run_time_scale"] - vals["L"]) > 1e-5:
        problems.append("주기 길이 L: 자리표 %s, 고름 %s" % (c["pose"]["run_time_scale"], vals["L"]))
    if abs(rate - vals["rate"]) > RATE_TOL:
        problems.append("배율: 자리표에서 읽은 v x L / stride = %.4f, 고름 %.4f (허용 %g)" % (rate, vals["rate"], RATE_TOL))
    return rate, problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pick", required=True)
    ap.add_argument("--slots", default=str(SLOTS))
    ap.add_argument("--picks", default=str(PICKS))
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--write", action="store_true")
    g.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    try:
        rec = load_pick(a.picks, a.pick)
        vals = pick_values(rec)
        if a.check:
            rate, problems = check(a.slots, vals)
            print("자리표에서 읽은 배율 %.4f / 고름 %.4f" % (rate, vals["rate"]))
            for p in problems:
                print("어긋남: " + p)
            print("결과: " + ("같음" if not problems else "다름"))
            return 0 if not problems else 1
        raw = Path(a.slots).read_bytes().decode("utf-8")
        clips = body_clip_names(a.slots, vals["slot"])
        if clips is None:
            print("알림: 몸 옆의 pack-report 를 읽지 못해 클립 이름 확인을 건너뜀")
        new = edited_text(raw, vals, a.pick, clips)
        lines = show_diff(raw, new)
        print("칸 %s  클립 %s  배율 %s  L %s  보폭 %s  (게임 이동 속도 %s)" % (vals["slot"], vals["clip"], fmt(vals["rate"], 3), fmt(vals["L"], 7), fmt(vals["stride"], 3), fmt(vals["speed_game"], 3)))
        print("\n".join(lines) if lines else "바뀔 줄 없음(이미 같은 값)")
        if not a.write:
            print("\n보기만 했다. 쓰려면 --write")
            return 0
        if new == raw:
            return 0
        tmp = Path(a.slots).with_name(Path(a.slots).name + ".tmp")
        tmp.write_bytes(new.encode("utf-8"))
        os.replace(tmp, a.slots)
        ok, changed = verify_after(a.slots, vals, raw)
        print("다시 읽어 확인: " + ("세 값이 기대와 같고 바뀐 줄 %d개" % len(changed) if ok else "어긋남"))
        return 0 if ok else 1
    except ApplyError as e:
        print("멈춤: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
