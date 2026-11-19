#!/usr/bin/env python3
"""balance_search.py — 균형 시뮬레이터 위의 값 탐색(모델의 답이지 게임의 답이 아니다. 재미는 평가하지 않는다).

D12 P7의 목표와의 거리를 줄이는 값을 찾는다. 두 단계: 1단계는 힘 쪽 값만(주문 피해·쿨타임·반경, 축 이득 곡선, 터뜨림 배율, 강한 적 감쇠,
진화 조건과 배율, 보호 카드), 2단계는 그 힘에 위협 쪽 값(리듬 양·체력·봉인 처치 수·정예 체력)을 맞춘다(사용자 지시: 힘 먼저, 위협은 그다음).
좌표 하강 + 무작위 짝 이동, 시드 고정(같은 인수면 같은 답). 공통 시드로 후보를 비교하고, 마지막에 다른 시드(홀드아웃)로 다시 잰다.

예시(저장소 루트에서):
  python tools/dev/balance_search.py --stage power --plan A --rounds 3 --out _local/balsim2/s1A
  python tools/dev/balance_search.py --stage threat --init _local/balsim2/s1A.json --out _local/balsim2/s2A
  python tools/dev/balance_search.py --sensitivity --init _local/balsim2/s1A.json
  python tools/dev/balance_search.py --eval --init _local/balsim2/s2A.json --seeds 100 --seed0 101
쓴 파일: <out>.json(바꾼 값 묶음: sets=--set에 바로 넣는 꼴), <out>.args(한 줄), <out>.log
"""
import argparse
import json
import math
import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import balance_sim as bs  # noqa: E402

SPELLS = ["ember", "frost", "arc", "ember_ring", "frost_ring", "arc_ring"]
RINGS = ["ember_ring", "frost_ring", "arc_ring"]
POLICIES = ["synergy"] + ["synergy:" + r for r in bs.PAIR_ROLES] + ["narrow", "narrow_ring", "random", "spread", "worst"]
RING_FREE = ("basic_A", "basic_B", "A_B")


class Param:
    def __init__(self, name, stage, kind, lo, hi, base, hyp=False, note=""):
        self.name, self.stage, self.kind, self.lo, self.hi, self.base, self.hyp, self.note = name, stage, kind, lo, hi, base, hyp, note


def make_params(base_cfg):
    """탐색할 값 목록. mul = 첫 값에 곱하는 배율(첫 값 1), abs = 절댓값, int = 정수. hyp=True는 명세에 값이 없어 모델이 가설로 둔 상수(플랜 B에서 뺀다)."""
    P = []
    add = lambda *a, **k: P.append(Param(*a, **k))
    add("dmg_all", "power", "mul", 0.5, 3.0, 1.0, note="여섯 주문 base.damage_raw 공통 배율")
    for s in SPELLS:
        add("dmg:" + s, "power", "mul", 0.5, 2.5, 1.0, note="주문 하나의 base.damage_raw 배율")
    for s in SPELLS:
        add("cd:" + s, "power", "mul", 0.6, 1.6, 1.0, note="주문 하나의 base.cooldown_ticks 배율")
    for s in RINGS:
        add("radius:" + s, "power", "mul", 0.7, 1.7, 1.0, note="원형 반경(base와 reach[1..4]의 ring_radius_cm) 배율")
    add("axis_dmg_G", "power", "abs", 0.6, 3.5, 1.25, note="축 피해 이득: 4점에서 +G(첫 값 +125%)")
    add("axis_dmg_gamma", "power", "abs", 1.0, 3.0, 1.55, note="축 피해 이득의 앞 몰림(클수록 처음 점이 값짐)")
    add("axis_cd_R", "power", "abs", 0.10, 0.50, 0.20, note="축 쿨타임 감소: 4점에서 -R(첫 값 -20%)")
    add("axis_cd_gamma", "power", "abs", 1.0, 3.0, 1.77, note="축 쿨타임 감소의 앞 몰림")
    add("det:ember_ring", "power", "abs", 1500, 12000, 4000, note="잿불 고리의 열 스택당 터뜨림 가산(bps)")
    add("det:frost", "power", "abs", 3000, 20000, 8000, note="서리창의 냉각 터뜨림 가산(bps)")
    add("det:arc_ring", "power", "abs", 3000, 25000, 10000, note="번개 고리의 감전 터뜨림 가산(bps)")
    add("vs_strong", "power", "abs", 3000, 12000, 5000, note="원형의 강한 적 앞 피해 비율(bps, '강한 적 감쇠')")
    add("partner_det", "power", "abs", 10000, 30000, 15000, note="진화 짝이 있을 때 터뜨림 배율(bps)")
    add("evolve_axis_sum", "power", "int", 4, 6, 5, note="진화 조건: 주문의 축 점수 합")
    add("partner_axis_sum", "power", "int", 1, 3, 2, note="진화 조건: 짝의 축 점수 합")
    add("protect_open_hi", "power", "int", 4, 8, 5, note="보호 카드: 짝 열기를 보장하는 마지막 레벨(첫 값 [3,5])")
    add("react_dmg", "power", "mul", 0.5, 3.0, 1.0, hyp=True, note="원소 반응 셋의 피해 배율(모델 가설 상수)")
    add("evolve_damage_mul", "power", "abs", 1.0, 2.2, 1.35, hyp=True, note="진화 피해 배율(명세에 값 없음)")
    add("evolve_cd_mul", "power", "abs", 0.5, 1.0, 0.8, hyp=True, note="진화 쿨타임 배율(명세에 값 없음)")
    add("evolve_k_add", "power", "int", 0, 3, 1, hyp=True, note="진화 탄 발수 가산(명세에 값 없음)")
    add("evolve_reach_mul", "power", "abs", 1.0, 1.6, 1.15, hyp=True, note="진화 반경·연쇄 배율(명세에 값 없음)")
    add("evolve_budget_mul", "power", "abs", 1.0, 2.5, 1.4, hyp=True, note="진화 예산 배율(명세에 값 없음)")
    T = base_cfg.tuning
    for i, b in enumerate(T["rhythm"]["beats"]):
        add("beat_amount:%d" % i, "threat", "mul", 0.5, 2.0, 1.0, note="마디 %s 생성 양" % b["id"])
        add("beat_hp:%d" % i, "threat", "mul", 0.6, 1.6, 1.0, note="마디 %s 체력 배율 hp_bps(시작·끝)" % b["id"])
        add("beat_cap:%d" % i, "threat", "mul", 0.6, 1.3, 1.0, note="마디 %s 살아 있는 적 상한" % b["id"])
    for z in range(3):
        add("seal:%d" % z, "threat", "mul", 0.6, 1.5, 1.0, note="구역 %d 봉인 처치 수" % (z + 1))
    for i in range(3):
        add("champ_hp:%d" % i, "threat", "mul", 0.5, 1.6, 1.0, note="수호자·우두머리 %d 체력" % (i + 1))
        add("champ_dmg:%d" % i, "threat", "mul", 0.5, 1.5, 1.0, note="수호자·우두머리 %d 공격 피해" % (i + 1))
    add("trial_amount", "threat", "mul", 0.5, 1.6, 1.0, note="버티기 생성 양")
    add("trial_hp", "threat", "mul", 0.6, 1.5, 1.0, note="버티기 체력 hp_bps")
    add("trial_hold", "threat", "mul", 0.5, 1.5, 1.0, note="버티기 지속 틱")
    add("boss_amount", "threat", "mul", 0.5, 1.6, 1.0, note="우두머리 전 생성 양")
    return {p.name: p for p in P}


def build_sets(P, base_cfg, vals):
    """값 묶음 -> (키, 값) 목록. 첫 값과 같은 항목은 내지 않는다."""
    sp = base_cfg.spells["spells"]
    T = base_cfg.tuning
    out = []
    g = lambda n: vals.get(n, P[n].base)
    ch = lambda n: abs(g(n) - P[n].base) > 1e-9
    for s in SPELLS:
        d = sp[bs.SK + s]
        m = g("dmg_all") * g("dmg:" + s)
        if abs(m - 1) > 1e-9:
            out.append(("spells.%s.base.damage_raw" % s, int(round(d["base"]["damage_raw"] * m))))
        if ch("cd:" + s):
            out.append(("spells.%s.base.cooldown_ticks" % s, max(6, int(round(d["base"]["cooldown_ticks"] * g("cd:" + s))))))
    for s in RINGS:
        if ch("radius:" + s):
            d = sp[bs.SK + s]
            m = g("radius:" + s)
            out.append(("spells.%s.base.ring_radius_cm" % s, int(round(d["base"]["ring_radius_cm"] * m))))
            for i, r in enumerate(d["reach"]):
                if "ring_radius_cm" in r:
                    out.append(("spells.%s.reach[%d].ring_radius_cm" % (s, i), int(round(r["ring_radius_cm"] * m))))
    if ch("axis_dmg_G") or ch("axis_dmg_gamma"):
        G, gm = g("axis_dmg_G"), g("axis_dmg_gamma")
        for i in range(1, 5):
            out.append(("spells.axis.power.damage_bps[%d]" % i, int(round(10000 * (1 + G * (1 - (1 - i / 4.0) ** gm))))))
    if ch("axis_cd_R") or ch("axis_cd_gamma"):
        R, gm = g("axis_cd_R"), g("axis_cd_gamma")
        for i in range(1, 5):
            out.append(("spells.axis.power.cooldown_bps[%d]" % i, int(round(10000 * (1 - R * (1 - (1 - i / 4.0) ** gm))))))
    if ch("det:ember_ring"):
        out.append(("spells.ember_ring.detonates.heat.per_stack_bps", int(round(g("det:ember_ring")))))
    if ch("det:frost"):
        out.append(("spells.frost.detonates.chill.bonus_bps", int(round(g("det:frost")))))
    if ch("det:arc_ring"):
        out.append(("spells.arc_ring.detonates.shock.bonus_bps", int(round(g("det:arc_ring")))))
    if ch("vs_strong"):
        for s in RINGS:
            out.append(("spells.%s.vs_strong_bps" % s, int(round(g("vs_strong")))))
    if ch("partner_det"):
        out.append(("spells.evolve.partner_detonate_bps", int(round(g("partner_det")))))
    if ch("evolve_axis_sum"):
        out.append(("spells.evolve.axis_sum", int(g("evolve_axis_sum"))))
    if ch("partner_axis_sum"):
        out.append(("spells.evolve.partner_axis_sum", int(g("partner_axis_sum"))))
    if ch("protect_open_hi"):
        out.append(("spells.protect.pair_open_levels", [3, int(g("protect_open_hi"))]))
    if ch("react_dmg"):
        for rn, rx in base_cfg.spells["model_extras"]["reactions"].items():
            out.append(('spells.model_extras["reactions"]["%s"].dmg' % rn, round(rx["dmg"] * g("react_dmg"), 3)))
    for n in ("evolve_damage_mul", "evolve_cd_mul", "evolve_reach_mul", "evolve_budget_mul"):
        if ch(n):
            out.append(("calib." + n, round(g(n), 4)))
    if ch("evolve_k_add"):
        out.append(("calib.evolve_k_add", int(g("evolve_k_add"))))
    # 위협 쪽
    for i, b in enumerate(T["rhythm"]["beats"]):
        if ch("beat_amount:%d" % i):
            out.append(("rhythm.beats[%d].amount" % i, round(b["amount"] * g("beat_amount:%d" % i), 2)))
        if ch("beat_hp:%d" % i):
            m = g("beat_hp:%d" % i)
            out.append(("rhythm.beats[%d].hp_bps" % i, [int(round(b["hp_bps"][0] * m)), int(round(b["hp_bps"][1] * m))]))
        if ch("beat_cap:%d" % i):
            out.append(("rhythm.beats[%d].alive_cap" % i, max(8, int(round(b["alive_cap"] * g("beat_cap:%d" % i))))))
    for z in range(3):
        if ch("seal:%d" % z):
            out.append(("seal_kills[%d]" % z, int(round(T["seal_kills"][z] * g("seal:%d" % z)))))
    for i in range(3):
        if ch("champ_hp:%d" % i):
            out.append(("champions[%d].hp" % i, int(round(T["champions"][i]["hp"] * g("champ_hp:%d" % i)))))
        if ch("champ_dmg:%d" % i):
            out.append(("champions[%d].damage" % i, int(round(T["champions"][i]["damage"] * g("champ_dmg:%d" % i)))))
    tr = T["rhythm"]["trial"]
    if ch("trial_amount"):
        out.append(("rhythm.trial.amount", round(tr["amount"] * g("trial_amount"), 2)))
    if ch("trial_hp"):
        out.append(("rhythm.trial.hp_bps", int(round(tr["hp_bps"] * g("trial_hp")))))
    if ch("trial_hold"):
        out.append(("rhythm.trial.hold_ticks", int(round(tr["hold_ticks"] * g("trial_hold")))))
    if ch("boss_amount"):
        out.append(("spawn.boss_phase.amount", round(T["spawn"]["boss_phase"]["amount"] * g("boss_amount"), 2)))
    return out


def fmt_sets(pairs):
    return ["%s=%s" % (k, json.dumps(v, ensure_ascii=False)) for k, v in pairs]


# ---- 목표 함수 ---------------------------------------------------------------
def soft_win(rs):
    return sum(1.0 if r["win"] else 0.25 * r.get("prog", 0.0) for r in rs) / len(rs)


def hard_win(rs):
    return sum(1 for r in rs if r["win"]) / len(rs)


def band(soft, hard, lo, hi):
    """아래쪽 위반은 보조 승률(진행도 가산)로, 위쪽 위반은 실제 승률로 잰다."""
    return max(0.0, lo - soft), max(0.0, hard - hi)


def distance(matrix, witches, cfg, detail=False):
    parts = {}
    A = lambda k, v: parts.__setitem__(k, parts.get(k, 0.0) + v / len(witches))
    for w in witches:
        def cls(c):
            return [(p, rs) for (p, ww), rs in matrix.items() if ww == w and bs.policy_class(p) == c]
        paths = [(p.split(":")[1], rs) for p, rs in cls("synergy") if ":" in p]
        gen = [rs for p, rs in cls("synergy") if ":" not in p]
        ps = sorted(paths, key=lambda x: -soft_win(x[1]))
        for i, (role, rs) in enumerate(ps):
            A("길 승률(<90)", (1.0 if i < 3 else 0.35) * 4 * max(0.0, 0.9 - soft_win(rs)) ** 2)
        if gen:
            A("일반형 synergy(<93)", 4 * max(0.0, 0.93 - soft_win(gen[0])) ** 2)
        for c, lo, hi in (("narrow", .2, .4), ("narrow_ring", .1, .3), ("random", .15, .35), ("spread", 0.0, .15), ("worst", 0.0, .05)):
            for p, rs in cls(c):
                lo_v, hi_v = band(soft_win(rs), hard_win(rs), lo, hi)
                A(c + " 대역", 4 * (lo_v ** 2 + hi_v ** 2))
        if gen and cls("narrow"):
            gap = hard_win(gen[0]) - hard_win(cls("narrow")[0][1])
            A("synergy−narrow(>=50p)", 4 * max(0.0, 0.5 - gap) ** 2)
        if paths:
            hw = [hard_win(rs) for _, rs in paths]
            A("길 사이 승률 차(<=10p)", 2 * max(0.0, (max(hw) - min(hw)) - 0.10) ** 2)
            ts = [bs.med([r["secs"] for r in rs if r["win"]]) for _, rs in paths]
            ts = [t for t in ts if t]
            if len(ts) > 1:
                A("길 사이 승리 시각 차(<=15%)", 2 * max(0.0, (max(ts) - min(ts)) / max(ts) - 0.15) ** 2)
            q = [role for (role, rs) in paths if hard_win(rs) >= 0.9]
            A("목표 채운 길 3개 이상", 2 * ((3 - min(3, len(q))) / 3.0) ** 2)
            if any(r in bs.PAIR_ROLES for r, _ in paths):
                A("원형 없는 길 채움", 1.0 if not any(r in RING_FREE for r in q) else 0.0)
            # 승리 시간 6:30~7:30
            wins = [r["secs"] for _, rs in paths for r in rs if r["win"]]
            if wins:
                m = bs.med(wins)
                A("판 길이 390~450초", 0.5 * (max(0.0, 390 - m, m - 450) / 60.0) ** 2)
            else:
                A("판 길이 390~450초", 0.5)
            # 터뜨림 몫
            ds = [r["det_share"] for _, rs in paths for r in rs]
            m = sum(ds) / len(ds)
            A("터뜨림 몫 30~50%(시너지)", 0.5 * (max(0.0, .3 - m, m - .5) / 0.2) ** 2)
            # 수호자 허용 창
            for idx in (0, 1):
                durs = [x[2] for _, rs in paths for r in rs for x in r["single_R"] if x[0] == idx]
                if durs:
                    m = bs.med(durs)
                    A("수호자%d 허용 창" % (idx + 1), 1.0 * max(0.0, m / bs.WINDOW_S[idx] - 1.0) ** 2)
                else:
                    A("수호자%d 허용 창" % (idx + 1), 1.0)
        for p, rs in cls("narrow"):
            m = sum(r["det_share"] for r in rs) / len(rs)
            A("터뜨림 몫 narrow<=5%", 0.5 * (max(0.0, m - 0.05) / 0.2) ** 2)
        stall = [sum(1 for r in rs if r["stall"]) / len(rs) for (p, ww), rs in matrix.items() if ww == w]
        A("정체", 5 * (sum(stall) / len(stall)))
        # P4 R 표
        for b in ["기", "승1", "승2", "전A", "전B"]:
            for c in ("synergy", "narrow", "random", "spread", "worst"):
                tg = bs.P4_R[b].get(c)
                if not tg:
                    continue
                vals = []
                for p, rs in cls(c):
                    for r in rs:
                        pr = r["per"].get(b)
                        if pr and pr["Tsum"] > 0:
                            vals.append(pr["Psum"] / pr["Tsum"])
                if vals:
                    v = sum(vals) / len(vals)
                    lo_, hi_ = tg
                    d_ = max(0.0 if lo_ is None else lo_ - v, 0.0 if hi_ is None else v - hi_, 0.0)
                    A("P4 R 표", 0.1 * (d_ / 1.0) ** 2)
    tot = sum(parts.values())
    return (tot, parts) if detail else tot


class Evaluator:
    def __init__(self, base_cfg, P, args, seeds, witches):
        self.base_cfg, self.P, self.args, self.seeds, self.witches = base_cfg, P, args, seeds, witches
        self.cache = {}
        self.n = 0

    def cfg_for(self, vals):
        return bs.derive(self.base_cfg, sets=fmt_sets(build_sets(self.P, self.base_cfg, vals)))

    def key(self, vals):
        return json.dumps({k: round(v, 5) for k, v in sorted(vals.items()) if abs(v - self.P[k].base) > 1e-9}, sort_keys=True)

    def score(self, vals, detail=False):
        k = self.key(vals)
        if k in self.cache and not detail:
            return self.cache[k]
        cfg = self.cfg_for(vals)
        mx = bs.run_matrix(cfg, POLICIES, self.witches, self.seeds)
        d = distance(mx, self.witches, cfg, detail=detail)
        self.n += 1
        s = d[0] if detail else d
        self.cache[k] = s
        return d


def clampv(p, v):
    v = min(p.hi, max(p.lo, v))
    return int(round(v)) if p.kind == "int" else v


def candidates(p, cur, rnd, rng):
    if p.kind == "int":
        return [cur - 1, cur + 1]
    fs = (0.7, 1.4, 0.85, 1.18) if rnd == 0 else ((0.85, 1.18, 0.93, 1.08) if rnd == 1 else (0.93, 1.08, 0.97, 1.03))
    return [cur * f for f in fs]


def search(args, base_cfg, P, vals, stage_names, log):
    seeds = list(range(args.seed0, args.seed0 + args.seeds))
    ev = Evaluator(base_cfg, P, args, seeds, args.witches.split(","))
    rng = random.Random(args.rng)
    names = [p.name for p in P.values() if p.name in stage_names]
    best, parts = ev.score(vals, detail=True)
    log("시작 거리 %.3f  %s" % (best, " ".join("%s %.2f" % kv for kv in sorted(parts.items(), key=lambda kv: -kv[1])[:6])))
    t0 = time.time()
    for rnd in range(args.rounds):
        order = names[:]
        rng.shuffle(order)
        for n in order:
            p = P[n]
            cur = vals.get(n, p.base)
            for c in candidates(p, cur, rnd, rng):
                c = clampv(p, c)
                if abs(c - cur) < 1e-9:
                    continue
                cur0 = cur
                trial = dict(vals)
                trial[n] = c
                s = ev.score(trial)
                if s < best - 1e-6:
                    best, vals, cur = s, trial, c
                    log("  r%d %-16s -> %-8.4g 거리 %.3f  (%d평가, %.0fs)" % (rnd, n, c, s, ev.n, time.time() - t0))
                    # 같은 방향으로 더 나아갈 수 있는 동안 간다(선 탐색)
                    while True:
                        nxt = clampv(p, cur + (1 if cur > cur0 else -1) if p.kind == "int" else cur * (c / cur0))
                        if abs(nxt - cur) < 1e-9:
                            break
                        t2 = dict(vals)
                        t2[n] = nxt
                        s2 = ev.score(t2)
                        if s2 < best - 1e-6:
                            best, vals, cur = s2, t2, nxt
                            log("  r%d %-16s -> %-8.4g 거리 %.3f  (선 탐색)" % (rnd, n, nxt, s2))
                        else:
                            break
        for _ in range(args.pair_moves):
            k = rng.choice([2, 3])
            trial = dict(vals)
            for n in rng.sample(names, k):
                p = P[n]
                cur = trial.get(n, p.base)
                trial[n] = clampv(p, cur + rng.choice([-1, 1]) if p.kind == "int" else cur * rng.choice([0.8, 0.9, 1.1, 1.25]))
            s = ev.score(trial)
            if s < best - 1e-6:
                best, vals = s, trial
                log("  r%d 짝 이동 -> 거리 %.3f" % (rnd, s))
        log("라운드 %d 끝 거리 %.3f (%d평가, %.0fs)" % (rnd, best, ev.n, time.time() - t0))
    return vals, best


def load_init(path, P):
    if not path:
        return {}
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    return {k: v for k, v in doc.get("values", {}).items() if k in P}


def write_out(out, args, P, base_cfg, vals, score, parts, extra):
    pairs = build_sets(P, base_cfg, vals)
    changed = [(p.name, p.base, vals[p.name], p.note, p.hyp) for p in P.values() if p.name in vals and abs(vals[p.name] - p.base) > 1e-9]
    doc = {"model_answer_not_game_answer": True, "preset": args.preset, "plan": args.plan, "stage": args.stage, "score": score,
           "parts": parts, "values": vals, "sets": fmt_sets(pairs), "changes": [
               {"name": n, "first": b, "recommended": v, "note": nt, "model_hypothesis_constant": h} for n, b, v, nt, h in changed], **extra}
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out + ".json").write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    Path(out + ".args").write_text(" ".join('--set "%s"' % s for s in doc["sets"]) + "\n", encoding="utf-8", newline="\n")
    return doc


def plan_names(P, args):
    st = {"power": ["power"], "threat": ["threat"], "both": ["power", "threat"]}[args.stage]
    return [p.name for p in P.values() if p.stage in st and not (args.plan == "B" and p.hyp)]


def main(argv=None):
    ap = argparse.ArgumentParser(description="균형 시뮬레이터 값 탐색(모델의 답)")
    ap.add_argument("--preset", default="spec1p")
    ap.add_argument("--stage", default="power", choices=["power", "threat", "both"])
    ap.add_argument("--plan", default="A", choices=["A", "B"], help="A=힘 쪽 값 전부, B=모델 가설 상수(진화 배율·반응 피해)를 빼고")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--pair-moves", type=int, default=12)
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--seed0", type=int, default=11)
    ap.add_argument("--rng", type=int, default=7, help="탐색 난수 시드")
    ap.add_argument("--witches", default="ember,frost,arc")
    ap.add_argument("--init", default=None, help="앞 단계의 .json(values)에서 이어서")
    ap.add_argument("--set", action="append", default=[], help="추가 --set(고정 조건)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--jobs", type=int, default=None)
    ap.add_argument("--eval", action="store_true", help="탐색 없이 --init의 값을 잰다")
    ap.add_argument("--sensitivity", action="store_true")
    ap.add_argument("--shake", action="store_true", help="--init의 값을 고정하고 모델 가설 상수를 -20%%/+20%% 흔들어 본다")
    ap.add_argument("--gear", default=None)
    ap.add_argument("--spells", default=None, help="주문 묶음 파일(시험 묶음: tools/dev/balance_sim_spells_lab.json)")
    ap.add_argument("--approach", action="store_true", help="접근 (가)(나)(다)를 시험 묶음에서 견준다(--spells lab 필요). --init의 힘 값을 공통 바닥으로")
    ap.add_argument("--plan-approach", default=None, choices=list(APPROACHES), help="그 접근의 정책·주문으로 탐색(--spells lab 필요)")
    ap.add_argument("--report", action="store_true", help="--init의 값으로 balance_sim 결과표를 낸다(--seeds 판)")
    ap.add_argument("--final-seeds", type=int, default=60)
    args = ap.parse_args(argv)
    bs.set_jobs(args.jobs if args.jobs else bs.default_jobs())
    a = argparse.Namespace(spells=args.spells, skills=None, dt=1.0, gear=args.gear, preset=args.preset, real_dir=None, set=args.set)
    base_cfg = bs.load_cfg(a, sets=args.set, preset=args.preset)
    global POLICIES, SPELLS, RINGS
    if args.plan_approach:
        g = APPROACHES[args.plan_approach]
        POLICIES = g["policies"] + (["narrow_ring"] if args.plan_approach.startswith("a_") else []) + COMPARATORS
        SPELLS = list(g["spells"])
        RINGS = [x for x in SPELLS if base_cfg.spells["spells"][bs.SK + x]["role"] == "ring"]
    P = make_params(base_cfg)
    vals = load_init(args.init, P)
    logf = open(args.out + ".log", "w", encoding="utf-8", newline="\n") if args.out else None

    def log(s):
        print(s, flush=True)
        if logf:
            logf.write(s + "\n")
            logf.flush()
    t0 = time.time()
    if args.sensitivity:
        sensitivity(args, base_cfg, P, vals, log)
        bs.close_pool()
        return 0
    if args.report:
        cfg = bs.derive(base_cfg, sets=fmt_sets(build_sets(P, base_cfg, vals)))
        mx = bs.run_matrix(cfg, POLICIES, witches_ := args.witches.split(","), seeds_ := list(range(args.seed0, args.seed0 + args.seeds)))
        log(bs.report(cfg, mx, POLICIES, witches_, seeds_, label=args.init or ""))
        bs.close_pool()
        return 0
    if args.approach:
        init_sets = []
        if args.init:
            init_sets = list(json.loads(Path(args.init).read_text(encoding="utf-8")).get("sets", []))
        approach_eval(args, base_cfg, log, init_sets)
        bs.close_pool()
        return 0
    if args.shake:
        shake(args, base_cfg, P, vals, log)
        bs.close_pool()
        return 0
    seeds = list(range(args.seed0, args.seed0 + args.seeds))
    witches = args.witches.split(",")
    if args.eval:
        ev = Evaluator(base_cfg, P, args, seeds, witches)
        s, parts = ev.score(vals, detail=True)
        log("거리 %.3f  %s" % (s, " ".join("%s %.2f" % kv for kv in sorted(parts.items(), key=lambda kv: -kv[1]))))
        bs.close_pool()
        return 0
    names = plan_names(P, args)
    log("탐색 %s 단계, 플랜 %s, 값 %d개, 시드 %d..%d, 마녀 %s, 판 수 %d/평가" % (
        args.stage, args.plan, len(names), seeds[0], seeds[-1], args.witches, len(POLICIES) * len(witches) * len(seeds)))
    vals, best = search(args, base_cfg, P, vals, set(names), log)
    ev = Evaluator(base_cfg, P, args, seeds, witches)
    s, parts = ev.score(vals, detail=True)
    log("최종 거리 %.3f (%.0f초)" % (s, time.time() - t0))
    if args.out:
        write_out(args.out, args, P, base_cfg, vals, s, parts, {"seeds": [seeds[0], seeds[-1]], "rng": args.rng, "rounds": args.rounds})
    bs.close_pool()
    return 0


APPROACHES = {  # 접근 = 짝을 맞춘 길들(정책)과 그 접근이 쓰는 주문
    "a_pair_detonate": {"policies": ["synergy:" + r for r in bs.PAIR_ROLES], "spells": ["ember", "frost", "arc", "ember_ring", "frost_ring", "arc_ring"],
                        "text": "(가) 짝 터뜨림: 기본기가 깐 상태를 원형·대여 주문이 터뜨린다(명세)"},
    "b_multiplicative": {"policies": ["kit:b_crit_mark", "kit:b_exec_mark", "kit:b_crit_burn", "kit:b_volatile_crit"],
                         "spells": ["lab_marker", "lab_crit_bolt", "lab_exec", "lab_burner", "lab_volatile"],
                         "text": "(나) 곱연산: 표식(받는 피해 +30%) x 치명타 x 조건부 추가 피해 x 지속 피해·처치 폭발"},
    "c_control": {"policies": ["kit:c_freeze_nova", "kit:c_push_field", "kit:c_pull_guard", "kit:c_freeze_turret"],
                  "spells": ["lab_freezer", "lab_nova", "lab_pusher", "lab_field", "lab_puller", "lab_guard", "lab_turret"],
                  "text": "(다) 군중 제어: 둔화·빙결·기절·밀어냄·끌어당김으로 접촉을 줄이고 원형·장판·포탑이 처리"},
    "m_mixed": {"policies": ["kit:m_ring_mark", "kit:m_ring_crit", "kit:m_ring_exec", "kit:m_ring_burn", "synergy:basic_ring"],
                "spells": ["ember", "frost", "arc", "ember_ring", "frost_ring", "arc_ring", "lab_marker", "lab_crit_bolt", "lab_exec", "lab_burner"],
                "text": "(가)+(나) 섞음: 마녀 고유 원형 + 공용 표식·치명타·추가 피해·지속 피해"},
}
COMPARATORS = ["narrow", "random", "spread", "worst"]


def approach_sets(base_cfg, group, m):
    out = []
    for s in group["spells"]:
        d = base_cfg.spells["spells"][bs.SK + s]
        out.append(("spells.%s.base.damage_raw" % s, int(round(d["base"]["damage_raw"] * m))))
    return fmt_sets(out)


def approach_eval(args, base_cfg, log, init_sets):
    """접근마다 자기 주문의 피해 배율 하나만 맞춰 최상 길 셋의 평균 승률이 85% 근처가 되게 한 뒤(힘의 값), 서열·길 사이 차·약점을 낸다."""
    seeds = list(range(args.seed0, args.seed0 + args.seeds))
    witches = args.witches.split(",")
    res = {}
    for name, g in APPROACHES.items():
        pols = g["policies"] + COMPARATORS
        chosen = None
        for m in (0.6, 0.8, 1.0, 1.25, 1.6, 2.0, 2.5, 3.2, 4.0, 5.0):
            cfg = bs.derive(base_cfg, sets=init_sets + approach_sets(base_cfg, g, m))
            mx = bs.run_matrix(cfg, g["policies"], witches, seeds[:12])
            ws = sorted([hard_win(rs) for rs in mx.values()], reverse=True)
            top = sum(ws[:3 * len(witches)]) / (3 * len(witches))
            chosen = m
            if top >= 0.85:
                break
        cfg = bs.derive(base_cfg, sets=init_sets + approach_sets(base_cfg, g, chosen))
        fseeds = list(range(args.seed0 + 1000, args.seed0 + 1000 + args.final_seeds))
        mx = bs.run_matrix(cfg, pols, witches, fseeds)
        res[name] = (chosen, mx, cfg, fseeds)
        log("== %s  [%s]  이 접근의 주문 피해 배율 x%.2f (최상 길 셋 평균 승률 85%%까지의 값 = 이 접근의 힘 값), 시드 %d판" % (name, g["text"], chosen, len(fseeds)))
        log(bs.report(cfg, mx, pols, witches, fseeds, label=name).split("\n\n마디별")[0])
        ok, lines = bs.verdict_order(mx, witches)
        for w in witches:
            ps = [(p, hard_win(mx[(p, w)])) for p in g["policies"]]
            nar = hard_win(mx[("narrow", w)])
            rnd = hard_win(mx[("random", w)])
            spr = hard_win(mx[("spread", w)])
            wor = hard_win(mx[("worst", w)])
            ts = [bs.med([r["secs"] for r in mx[(p, w)] if r["win"]]) for p, _ in ps]
            ts = [t for t in ts if t]
            log("  %-6s 길 승률 %s | narrow %.0f%% random %.0f%% spread %.0f%% worst %.0f%% | 길 사이 승률 차 %.0f%%p, 승리 시각 차 %s" % (
                w, " ".join("%s=%.0f%%" % (p.split(":")[1][:14], v * 100) for p, v in ps), nar * 100, rnd * 100, spr * 100, wor * 100,
                (max(v for _, v in ps) - min(v for _, v in ps)) * 100, ("%.0f%%" % ((max(ts) - min(ts)) / max(ts) * 100)) if len(ts) > 1 else "-"))
        log("  서열(synergy류 평균 > narrow >= random > spread > worst) %s" % ("성립" if ok else "깨짐"))
        log("")
    return res


SHAKE = ["r0_hero_m", "ring_in_r_m", "cluster", "phi_base", "single_kappa", "single_proj_acc", "single_splash", "p_status_single", "eta_aim",
         "tau_min_s", "hit_rate_per_alive", "hit_dmg_scale", "champ_p_hit", "ward_p_hit", "xp_mult", "hero_hp"]


def summarize(mx, witches):
    out = {}
    for c in ("synergy", "narrow", "narrow_ring", "random", "spread", "worst"):
        xs = [hard_win(rs) for (p, w), rs in mx.items() if bs.policy_class(p) == c]
        out[c] = sum(xs) / len(xs) if xs else 0.0
    paths = [hard_win(rs) for (p, w), rs in mx.items() if ":" in p]
    out["path_min"], out["path_max"] = min(paths), max(paths)
    ok, lines = bs.verdict_order(mx, witches)
    out["order_ok_witches"] = sum(1 for l in lines if l[1])
    out["stall"] = sum(1 for rs in mx.values() for r in rs if r["stall"])
    return out


def shake(args, base_cfg, P, vals, log):
    """권고 값을 고정한 채 모델의 가설 상수 하나씩을 -20% / +20% 흔들어 결과가 뒤집히는지 본다."""
    seeds = list(range(args.seed0, args.seed0 + args.seeds))
    witches = args.witches.split(",")
    ev = Evaluator(base_cfg, P, args, seeds, witches)
    sets0 = fmt_sets(build_sets(P, base_cfg, vals))
    rows = []

    def run(extra, label):
        cfg = bs.derive(base_cfg, sets=sets0 + extra)
        mx = bs.run_matrix(cfg, POLICIES, witches, seeds)
        d, parts = distance(mx, witches, cfg, detail=True)
        sm = summarize(mx, witches)
        rows.append((label, d, sm))
        log("%-26s 거리 %6.2f | synergy %3.0f%% narrow %3.0f%% n_ring %3.0f%% random %3.0f%% spread %3.0f%% worst %3.0f%% | 길 최저 %3.0f%% 최고 %3.0f%% | 서열 성립 마녀 %d/3 | 정체 %d" % (
            label, d, 100 * sm["synergy"], 100 * sm["narrow"], 100 * sm["narrow_ring"], 100 * sm["random"], 100 * sm["spread"], 100 * sm["worst"],
            100 * sm["path_min"], 100 * sm["path_max"], sm["order_ok_witches"], sm["stall"]))
    run([], "권고 그대로")
    for k in SHAKE:
        cur = base_cfg.cal[k]
        for f in (0.8, 1.2):
            run(["calib.%s=%r" % (k, cur * f)], "%s x%.1f" % (k, f))
    return rows


def sensitivity(args, base_cfg, P, vals, log):
    """각 값을 -20% / +25%(정수는 -1/+1) 움직여 서열 간격 G1=synergy−narrow, G2=narrow−random(보조 승률)의 변화를 잰다."""
    seeds = list(range(args.seed0, args.seed0 + args.seeds))
    witches = args.witches.split(",")
    pols = ["synergy", "narrow", "random"]
    ev = Evaluator(base_cfg, P, args, seeds, witches)

    def gaps(v):
        cfg = ev.cfg_for(v)
        mx = bs.run_matrix(cfg, pols, witches, seeds)
        sw = lambda c: sum(soft_win(mx[(c, w)]) for w in witches) / len(witches)
        hw = lambda c: sum(hard_win(mx[(c, w)]) for w in witches) / len(witches)
        return sw("synergy") - sw("narrow"), sw("narrow") - sw("random"), hw("synergy") - hw("narrow"), hw("narrow") - hw("random")
    g0 = gaps(vals)
    log("기준: 보조 승률 간격 synergy−narrow %+.3f, narrow−random %+.3f | 실제 승률 간격 %+.3f, %+.3f (시드 %d, 마녀 %s)" % (g0 + (len(seeds), args.witches)))
    rows = []
    for p in P.values():
        cur = vals.get(p.name, p.base)
        ups = [cur - 1, cur + 1] if p.kind == "int" else [cur * 0.8, cur * 1.25]
        res = []
        for c in ups:
            c = clampv(p, c)
            if abs(c - cur) < 1e-9:
                res.append(None)
                continue
            t = dict(vals)
            t[p.name] = c
            res.append(gaps(t))
        eff = 0.0
        for r in res:
            if r:
                eff = max(eff, abs(r[0] - g0[0]) + abs(r[1] - g0[1]))
        rows.append((eff, p, res))
    rows.sort(key=lambda x: -x[0])
    log("민감도(보조 승률 간격의 변화 |ΔG1|+|ΔG2| 가 큰 순). 열: 값 | 낮춤(-20%%) ΔG1 ΔG2 | 높임(+25%%) ΔG1 ΔG2")
    for eff, p, res in rows[:20]:
        def f(r):
            return "   -     -  " if r is None else "%+.3f %+.3f" % (r[0] - g0[0], r[1] - g0[1])
        log("%-18s [%s] 효과 %.3f | %s | %s   %s" % (p.name, p.stage, eff, f(res[0]), f(res[1]), p.note))
    return rows


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
