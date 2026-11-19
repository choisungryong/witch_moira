#!/usr/bin/env python3
"""balance_sim.py 자체 검사(모델의 불변식). 실행: python tools/dev/test_balance_sim.py
표준 라이브러리만. 실제 코어를 돌리지 않는다."""
import argparse
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import balance_sim as b  # noqa: E402

FAILS = []
N_CHECK = 0


def check(name, cond, detail=""):
    global N_CHECK
    N_CHECK += 1
    if not cond:
        FAILS.append(name + (" :: " + str(detail) if detail else ""))
        print("FAIL", name, detail)
    else:
        print("ok  ", name)


def cfg_of(preset="spec1p", sets=None):
    a = argparse.Namespace(spells=None, skills=None, dt=1.0, gear=None, preset=preset, real_dir=None, set=sets or [])
    return b.load_cfg(a, sets=sets, preset=preset)


def main():
    # 1 결정론: 같은 시드·같은 정책이면 같은 결과, 다른 시드는 다를 수 있다
    c = cfg_of()
    r1 = b.simulate(c, "synergy:basic_A", "frost", 11)
    r2 = b.simulate(copy.deepcopy(c), "synergy:basic_A", "frost", 11)
    check("결정론: 같은 시드 같은 결과", (r1["secs"], r1["kills"], r1["picks"], r1["win"]) == (r2["secs"], r2["kills"], r2["picks"], r2["win"]))
    r3 = b.simulate(c, "random", "ember", 11)
    r4 = b.simulate(c, "random", "ember", 12)
    check("random 정책은 시드에 따라 다른 선택", r3["picks"] != r4["picks"])

    # 2 피해가 없으면(주인공 무적) 모든 정책이 정체 없이 끝나거나 죽지 않는다
    c0 = cfg_of(sets=["calib.hit_rate_per_alive=0", "calib.champ_p_hit=0", "calib.ward_p_hit=0"])
    deaths = 0
    for pol in ("synergy:basic_A", "narrow", "random", "worst"):
        r = b.simulate(c0, pol, "ember", 11)
        deaths += 1 if r["death"] else 0
    check("피해 0이면 아무도 죽지 않는다", deaths == 0, deaths)

    # 3 힘이 0이면 이길 수 없다
    cp = cfg_of()
    cp.gear = {"dmg": 1e-6, "hp": 1.0}
    wins = sum(1 for pol in ("synergy", "narrow", "random") for s in (11, 12) if b.simulate(cp, pol, "ember", s)["win"])
    check("힘 0이면 승리 0", wins == 0, wins)

    # 4 --set이 먹는다(점 경로, 배열 색인, 주문 약칭, calib)
    c2 = cfg_of(sets=["rhythm.beats[2].amount=6", "spells.ember_ring.base.ring_radius_cm=450", "calib.eta_aim=0.5"])
    check("--set rhythm 배열 색인", c2.tuning["rhythm"]["beats"][2]["amount"] == 6)
    check("--set spells 약칭", c2.spells["spells"]["chapter1.skill.ember_ring"]["base"]["ring_radius_cm"] == 450)
    check("--set calib", c2.cal["eta_aim"] == 0.5)
    try:
        cfg_of(sets=["rhythm.nope.x=1"])
        check("--set 없는 키는 거부", False)
    except KeyError:
        check("--set 없는 키는 거부", True)
    base = b.simulate(cfg_of(), "synergy:basic_ring", "ember", 11)
    mod = b.simulate(cfg_of(sets=["rhythm.beats[2].amount=2"]), "synergy:basic_ring", "ember", 11)
    check("--set 이 결과를 바꾼다(위협 하나 줄이면 다름)", (base["secs"], base["kills"]) != (mod["secs"], mod["kills"]))

    # 5 위협이 늘면 같은 빌드의 살아 있는 적이 늘고 승률은 늘지 않는다
    lo = b.simulate(cfg_of(sets=["rhythm.beats[2].amount=4"]), "synergy:basic_A", "frost", 11)
    hi = b.simulate(cfg_of(sets=["rhythm.beats[2].amount=14"]), "synergy:basic_A", "frost", 11)
    a_lo = lo["per"]["승2"]["alive"] / max(lo["per"]["승2"]["secs"], 1)
    a_hi = hi["per"]["승2"]["alive"] / max(hi["per"]["승2"]["secs"], 1)
    check("승 2 생성이 늘면 살아 있는 적이 는다", a_hi > a_lo, (a_lo, a_hi))

    # 6 자기가 건 상태는 터뜨리지 못한다: 서리창만(고리 없음)이면 터뜨림 몫 0
    cb = cfg_of()
    bd = b.Build(cb, "frost")
    pw = b.Power(cb)
    _, _, tot, det = pw.evaluate(bd, 40)
    check("자기가 건 상태는 못 터뜨림(서리창 혼자 터뜨림 0)", det == 0.0, det)
    bd.sp[b.ring_id("frost")] = b.Sp()
    bd.dirty()
    _, _, tot2, det2 = pw.evaluate(bd, 40)
    check("고리가 냉각을 깔면 창이 터뜨린다(몫>0)", det2 > 0, det2)

    # 7 서열 판정 계산
    def fake(wr):
        return [{"win": i < wr * 10} for i in range(10)]
    mx = {}
    for w in ("ember", "frost", "arc"):
        mx[("synergy", w)] = fake(0.9)
        mx[("narrow", w)] = fake(0.3)
        mx[("random", w)] = fake(0.2)
        mx[("spread", w)] = fake(0.1)
        mx[("worst", w)] = fake(0.0)
    ok, lines = b.verdict_order(mx, ["ember", "frost", "arc"])
    check("서열 판정: 서열이 서면 성립", ok)
    check("서열 판정: 차이 %p", abs(lines[0][2] - 60.0) < 1e-6, lines[0][2])
    mx[("narrow", "ember")] = fake(0.95)
    ok2, _ = b.verdict_order(mx, ["ember", "frost", "arc"])
    check("서열 판정: 하나만 쌓기가 앞서면 깨짐", not ok2)

    # 8 정책 유효성: 모든 정책이 한 판을 끝낸다
    for pol in b.default_policies("s"):
        r = b.simulate(c, pol, "arc", 11)
        check("정책 %s 한 판 완주" % pol, r["secs"] > 0 and r["level"] >= 2)

    # 9 축 상한: 어떤 판도 주문 하나의 축 합이 6을 넘지 않는다
    ok_cap = True
    for pol in ("synergy", "narrow", "random"):
        r = b.simulate(c, pol, "ember", 11)
        for k, (d, rr, ev) in r["build"].items():
            if d > 4 or rr > 4 or d + rr > 6:
                ok_cap = False
    check("축 상한(축 4, 주문 합 6)", ok_cap)

    # 10 진화는 짝 조건이 있다: 짝 없이 축 5 + 결정이어도 진화 카드 없음
    bd = b.Build(c, "ember")
    bd.sp[b.basic_id("ember")].dmg = 3
    bd.sp[b.basic_id("ember")].reach = 2
    bd.passives.add("ember")
    check("짝이 없으면 진화 불가", not b.evolve_ok(c, bd, b.basic_id("ember"), 8))
    bd.sp[b.ring_id("ember")] = b.Sp()
    bd.sp[b.ring_id("ember")].dmg = 2
    check("짝 축 2면 진화 가능", b.evolve_ok(c, bd, b.basic_id("ember"), 8))

    print("\n검사 %d건, 실패 %d" % (N_CHECK, len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
