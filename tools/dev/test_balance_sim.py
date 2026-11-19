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
    mod = b.simulate(cfg_of(sets=["rhythm.beats[1].amount=2"]), "synergy:basic_ring", "ember", 11)
    check("--set 이 결과를 바꾼다(위협 하나 줄이면 다름)", (base["secs"], base["kills"]) != (mod["secs"], mod["kills"]))

    # 5 위협이 늘면 같은 빌드의 살아 있는 적이 늘고 승률은 늘지 않는다
    lo = b.simulate(cfg_of(sets=["rhythm.beats[1].amount=4"]), "synergy:basic_A", "frost", 11)
    hi = b.simulate(cfg_of(sets=["rhythm.beats[1].amount=14"]), "synergy:basic_A", "frost", 11)
    a_lo = lo["per"]["승1"]["alive"] / max(lo["per"]["승1"]["secs"], 1)
    a_hi = hi["per"]["승1"]["alive"] / max(hi["per"]["승1"]["secs"], 1)
    check("승 1 생성이 늘면 살아 있는 적이 는다", a_hi > a_lo, (a_lo, a_hi))

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

    # 11 (2차) 병렬 = 직렬(판마다 독립 시드), 장비 묶음, 윌슨 구간, 따옴표 키, 진행도
    cs = cfg_of()
    tasks = [(p, w, s, None) for p in ("synergy", "narrow", "random") for w in ("ember", "frost") for s in range(11, 21)]
    b.set_jobs(1)
    ser = b.run_many(cs, tasks)
    b.set_jobs(4)
    par = b.run_many(cs, tasks)
    b.close_pool()
    b.set_jobs(1)
    check("병렬 실행이 직렬과 같은 답", [(r["secs"], r["kills"], r["win"], r["picks"]) for r in ser] == [(r["secs"], r["kills"], r["win"], r["picks"]) for r in par])
    g0 = b.parse_gear(None)
    g1 = b.parse_gear("kit.d1_end")
    check("kit.none = 장비 없음", g0 == {"dmg": 1.0, "hp": 1.0, "dr": 1.0})
    check("kit.d1_end 힘 x1.55, 버팀 x1.55(hp/dr)", abs(g1["dmg"] - 1.55) < 1e-9 and abs(g1["hp"] / g1["dr"] - 1.55) < 1e-9, g1)
    g2 = b.parse_gear("kit.d1_end+tree.lv20")
    check("묶음을 +로 곱한다", abs(g2["dmg"] - 1.55 * 1.35) < 1e-9, g2)
    cg = cfg_of()
    cg2 = b.derive(cg, gear="kit.d2_mid")
    r_n = b.simulate(cg, "narrow", "ember", 11)
    r_g = b.simulate(cg2, "narrow", "ember", 11)
    check("장비 묶음이 진행도를 올린다(진행도 단조)", r_g["prog"] >= r_n["prog"], (r_n["prog"], r_g["prog"]))
    p0, lo, hi = b.wilson(0, 50)
    p5, lo5, hi5 = b.wilson(25, 50)
    check("윌슨 구간: 0/50은 0 아래로 안 내려가고 상한이 0보다 크다", lo == 0.0 and hi > 0.0)
    check("윌슨 구간: 25/50은 대칭에 가깝다", abs((hi5 - 0.5) - (0.5 - lo5)) < 0.01)
    check("점이 든 키 따옴표 경로", b._tok('model_extras["reactions"]["react.steam"].dmg') == ["model_extras", "reactions", "react.steam", "dmg"])
    cr = cfg_of(sets=['spells.model_extras["reactions"]["react.steam"].dmg=1.7'])
    check("--set 따옴표 경로가 먹는다", cr.spells["model_extras"]["reactions"]["react.steam"]["dmg"] == 1.7)
    check("진행도: 승리 1, 아니면 1 미만", all((r["prog"] == 1.0) == r["win"] for r in ser))
    # 같은 인수면 같은 답: 서로 다른 프로세스 시드(PYTHONHASHSEED)에도 같다는 것은 셋 이상의 집합 순회가 결과에 안 쓰인다는 뜻이다
    r_a = b.simulate(cfg_of(), "synergy", "arc", 13)
    r_b = b.simulate(cfg_of(), "synergy", "arc", 13)
    check("같은 인수면 같은 답(두 번)", (r_a["secs"], r_a["picks"], r_a["prog"]) == (r_b["secs"], r_b["picks"], r_b["prog"]))

    # 12 (팩터 확장) 기본값이면 1차판과 같다 = 팩터를 명시적 0/빈 값으로 적어도 결과가 같다
    zero = ["spells.ember.crit_bps=0", "spells.frost.extra.elem_bps=0", "spells.arc.dot.dps_bps=0", "spells.ember_ring.cc.slow_bps=0",
            "spells.frost_ring.vuln.bps=0", "spells.arc_ring.utility.lifesteal_bps=0", "spells.ember.on_kill.dmg_bps=0"]
    czero = cfg_of(sets=zero)
    base_r = [b.simulate(c, p, w, 12) for p, w in (("synergy", "ember"), ("narrow", "frost"), ("random", "arc"))]
    zero_r = [b.simulate(czero, p, w, 12) for p, w in (("synergy", "ember"), ("narrow", "frost"), ("random", "arc"))]
    key = lambda rs: [(r["secs"], r["kills"], r["win"], r["picks"], r["det_share"], r["dmg_total"]) for r in rs]
    check("새 팩터가 기본값(0)이면 결과가 같다", key(base_r) == key(zero_r))
    check("--set으로 새 팩터 키를 처음 적을 수 있다", czero.spells["spells"]["chapter1.skill.ember"]["crit_bps"] == 0)
    try:
        cfg_of(sets=["spells.ember.nonsense_field=1"])
        check("모르는 팩터 이름은 거부", False)
    except KeyError:
        check("모르는 팩터 이름은 거부", True)

    # 13 팩터의 방향: 치명타·군중 제어·표식·흡수는 힘/버팀을 올린다
    bdb = b.Build(c, "ember")
    pwr = b.Power(c)
    t0 = pwr.evaluate(bdb, 40)[2]
    cc1 = cfg_of(sets=["spells.ember.crit_bps=6000", "spells.ember.crit_dmg_bps=30000"])
    b1 = b.Build(cc1, "ember")
    t1 = b.Power(cc1).evaluate(b1, 40)[2]
    check("치명타율·치명타 피해를 올리면 피해/s가 는다", t1 > t0, (t0, t1))
    ccs = cfg_of(sets=["spells.ember.cc.freeze_s=1.0", "spells.ember.cc.chance_bps=10000"])
    pw2 = b.Power(ccs)
    pw2.evaluate(b.Build(ccs, "ember"), 40)
    check("빙결(군중 제어)이 접촉 배율을 1 밑으로 낮춘다", pw2.last_cc["contact"] < 1.0, pw2.last_cc)
    cvu = cfg_of(sets=["spells.ember.vuln.bps=3000", "spells.ember.vuln.secs=5"])
    t3 = b.Power(cvu).evaluate(b.Build(cvu, "ember"), 40)[2]
    check("표식(취약)이 피해/s를 올린다", t3 > t0, (t0, t3))
    cgr = b.derive(c, gear="crit=0.3,range=1.3,count=1")
    gb = b.Build(cgr, "ember")
    check("장비 팩터(치명타·범위·갯수)가 주문에 얹힌다", gb.eff()[0]["crit"] > 0.29 and gb.eff()[0]["k"] == 2, gb.eff()[0]["crit"])
    cl = cfg_of()
    cl2 = b.cfg_from_spec({"preset": "spec1p", "spells": str(b.HERE / "balance_sim_spells_lab.json"), "dt": 1.0, "sets": [], "gear": None, "skills": None, "mode": None})
    rr = [b.simulate(cl2, "kit:" + k, "frost", 11) for k in cl2.spells["kits"]]
    check("시험 묶음의 kit 정책이 전부 한 판을 끝낸다", all(r["secs"] > 0 for r in rr), len(rr))
    raw0 = cl2.spells["spells"]["chapter1.skill.lab_marker"]["base"]["damage_raw"]
    cl3 = b.derive(cl2, sets=["spells.lab_marker.base.damage_raw=1"])
    cl4 = b.cfg_from_spec(cl2.spec)
    check("시험 묶음 파일이 캐시에서 오염되지 않는다(set이 다른 cfg에 새지 않음)", cl3.spells["spells"]["chapter1.skill.lab_marker"]["base"]["damage_raw"] == 1
          and cl4.spells["spells"]["chapter1.skill.lab_marker"]["base"]["damage_raw"] == raw0)
    d = b.describe(cl2, argparse.Namespace())
    check("--describe: 키 목록과 팩터 표", len(d["keys"]) > 100 and len(d["factors"]) >= 30 and all(k in d["keys"][0] for k in ("key", "value", "min", "max", "step", "desc", "group", "in_core")))
    import json as _j
    _j.dumps(d, ensure_ascii=False)

    # 시험장 실측 맞춤(power-bench)의 불변식
    cp = cfg_of()
    cp.mode = "s"
    check("원형 안 적 수: r0가 밀도에 따라 커지면 같은 N에서 안의 수가 줄어든다", b.ring_inside({"r0_hero_m": 8.0, "r0_per_alive": 0.05}, 60, 3.0) < b.ring_inside({"r0_hero_m": 8.0, "r0_per_alive": 0.0}, 60, 3.0))
    pw0 = b.Power(cp)
    bx = b.power_build(cp, "ember", "A:d3r1+X:d1r1")
    on, off = dict(cp.cal, reactions_on=1.0), dict(cp.cal, reactions_on=0.0)
    p_on = b.Power(b._PCfg(cp, on)).evaluate(bx, 60)[2]
    p_off = b.Power(b._PCfg(cp, off)).evaluate(bx, 60)[2]
    check("원소 반응 스위치: 끄면 대여 빌드의 처리량이 줄거나 같다", p_off <= p_on + 1e-9, (p_on, p_off))
    ba = b.power_build(cp, "ember", "A:d2r1+R")
    check("power_build: 약호가 Build로(기본기+원형)", len(ba.sp) == 2 and b.SK + "ember_ring" in ba.sp)
    mk = dict(cp.cal, mark_eff=1.0)
    m_on = b.Power(b._PCfg(cp, mk)).evaluate(bx, 60)[2]
    m_off = b.Power(b._PCfg(cp, dict(cp.cal, mark_eff=0.0))).evaluate(bx, 60)[2]
    check("표식 공명: 켜면 대여 빌드 처리량이 늘거나 같다", m_on >= m_off - 1e-9, (m_on, m_off))
    h, pct = b.taken_model(cp, dict(cp.cal, hit_per_contact_stand=2.0, hit_dmg_taken=1.0), 0.5, [74, 18, 8], 1, 120)
    check("받는 피해 모델: 접촉 몫 0.5 x 초당 2회 = 1회/s", abs(h - 1.0) < 1e-9 and pct > 0, (h, pct))

    print("\n검사 %d건, 실패 %d" % (N_CHECK, len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
