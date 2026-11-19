#!/usr/bin/env python3
"""균형 시뮬레이터 (1차판) — 코어를 돌리지 않고 스킬 구성의 힘과 적의 위협을 흐름 모델로 맞물려 본다.

이 도구의 답은 모델의 답이지 게임의 답이 아니다. 서열("어느 정책이 더 센가")과 값을 바꿨을 때의 방향을 보는 데 쓰고,
정확한 승률·시각은 실제 코어(sim_builds.gd, measure_rhythm.gd)로 마지막에 확인한다. 재미는 평가하지 않는다.

예시(저장소 루트에서, Python 3.10, 표준 라이브러리만):
  1) python tools/dev/balance_sim.py --calibrate                       # 지금 게임의 실측과 모델의 오차 표
  2) python tools/dev/balance_sim.py --preset spec1p --seeds 10 --out _local/balsim/first.json   # 명세 첫 값, 정책 전부 x 마녀 셋
  3) python tools/dev/balance_sim.py --preset spec1p --set rhythm.beats[2].amount=6 --set spells.ember_ring.base.ring_radius_cm=450
  4) python tools/dev/balance_sim.py --preset spec1p --sweep rhythm.beats[2].amount=5,6,7,8 --seeds 6
  5) python tools/dev/balance_sim.py --fit                             # 자유 상수를 실측에 맞춰 보기(결과 출력만, 파일은 안 고침)

키 접두사: rhythm./enemies./spawn./... = combat_tuning.json, spells. = 주문 데이터(run_spells.json 또는 초안), calib. = balance_sim_calib.json의 값.
주문 id는 chapter1.skill.을 떼고 쓴다(spells.ember_ring.base.ring_radius_cm).
"""
import argparse, copy, json, math, os, random, re, sys, time, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SK = "chapter1.skill."
ELEMS = ("ember", "frost", "arc")
STATUS_OF = {"ember": "heat", "frost": "chill", "arc": "shock"}
# 마녀별 대여 A, B(D12 B0.10 표)
WITCH_AB = {"ember": ("frost", "arc"), "frost": ("ember", "arc"), "arc": ("ember", "frost")}
PAIR_ROLES = ["basic_ring", "basic_A", "basic_B", "ring_A", "ring_B", "A_B"]
ZONE_ENTRY_BEATS = None

# ---- 목표(명세) -----------------------------------------------------------
P7_WIN = {"synergy": (0.9, 1.0), "narrow": (0.2, 0.4), "narrow_ring": (0.1, 0.3), "random": (0.15, 0.35),
          "spread": (0.0, 0.15), "worst": (0.0, 0.05)}
P4_R = {  # 마디 -> {정책류: (하한, 상한)} (None = 제한 없음)
    "기": {"synergy": (2.0, 3.0), "narrow": (1.8, None), "random": (1.6, None), "spread": (1.5, None), "worst": (1.2, None)},
    "승1": {"synergy": (2.0, 2.8), "narrow": (1.5, 2.0), "random": (1.2, 1.7), "spread": (1.1, 1.5), "worst": (0.9, None)},
    "승2": {"synergy": (1.8, 2.5), "narrow": (1.1, 1.4), "random": (0.9, 1.2), "spread": (0.8, 1.1), "worst": (0.6, 0.9)},
    "전A": {"synergy": (1.5, 2.2), "narrow": (0.8, 1.0), "random": (0.7, 0.95), "spread": (0.6, 0.9), "worst": (None, 0.7)},
    "전B": {"synergy": (1.3, 1.8), "narrow": (0.7, 0.9), "random": (0.6, 0.85), "spread": (None, 0.75), "worst": (None, 0.6)},
}
LEGACY_BEATS = [("기", 0, 60), ("승1", 60, 130), ("승2", 130, 285), ("전A", 285, 345), ("전B", 345, 390), ("전C", 390, 1e9)]
RHY_LABEL = {"gi": "기", "seung1": "승1", "seung2": "승2", "jeon_a": "전A", "trial": "전B", "boss": "전C"}
WINDOW_S = [25.0, 30.0, 40.0]  # 수호자 1, 2, 3구역(우두머리) 허용 창(D12 P2 가설)
CAP_S = 600.0


# ---- 설정 -----------------------------------------------------------------
_JSON_CACHE = {}


def load_json(p):
    """읽기 전용 문서는 캐시(훑기·맞춤에서 반복 읽기). 호출한 쪽이 고치는 문서는 copy를 쓴다."""
    key = str(p)
    if key not in _JSON_CACHE:
        with open(p, encoding="utf-8") as f:
            _JSON_CACHE[key] = json.load(f)
    return copy.deepcopy(_JSON_CACHE[key]) if key.endswith(("combat_tuning.json", "run_spells.json", "draft.json", "calib.json", "growth_quality37.json")) else _JSON_CACHE[key]


def _tok(path):
    return [int(t) if t.isdigit() else t for t in re.findall(r"[^.\[\]]+", path)]


def _walk_alias(cur, t):
    if isinstance(cur, dict) and t not in cur and (SK + str(t)) in cur:
        return SK + str(t)
    return t


def set_path(doc, path, val):
    toks = _tok(path)
    cur = doc
    for t in toks[:-1]:
        t = _walk_alias(cur, t)
        cur = cur[t]
    t = _walk_alias(cur, toks[-1])
    if isinstance(cur, dict) and t not in cur:
        raise KeyError("키가 없다: " + path)
    cur[t] = val


def parse_val(s):
    try:
        return json.loads(s)
    except Exception:
        return s


class Cfg:
    pass


def find_real_dir():
    for base in [ROOT] + list(ROOT.parents):
        d = base / "_local"
        if (d / "builds" / "sim-off.json").exists():
            return d
    return None


def load_cfg(args, sets=None, preset=None):
    c = Cfg()
    c.tuning = load_json(ROOT / "chapter1" / "data" / "combat_tuning.json")
    c.gq = load_json(ROOT / "chapter1" / "data" / "growth_quality37.json")
    sp_path = args.spells if getattr(args, "spells", None) else None
    real = ROOT / "chapter1" / "data" / "run_spells.json"
    if sp_path is None:
        sp_path = str(real) if real.exists() else str(HERE / "balance_sim_spells_draft.json")
    c.spells_path = sp_path
    c.spells = load_json(sp_path)
    draft = load_json(HERE / "balance_sim_spells_draft.json")
    if "model_extras" not in c.spells:
        c.spells["model_extras"] = draft["model_extras"]
    cal = load_json(HERE / "balance_sim_calib.json")
    c.calib_doc = cal
    c.cal = {k: v["value"] for k, v in cal["params"].items()}
    c.mode = getattr(args, "skills", None) or "s"
    c.dt = getattr(args, "dt", 1.0)
    gear = getattr(args, "gear", None)
    c.gear = parse_gear(gear)
    pre = preset or getattr(args, "preset", None)
    if pre:
        apply_preset(c, pre)
    for s in (sets or []):
        k, v = s.split("=", 1)
        apply_set(c, k.strip(), parse_val(v))
    return c


def apply_set(c, key, val):
    head, _, rest = key.partition(".")
    if head == "calib":
        if rest not in c.cal:
            raise KeyError("calib 키가 없다: " + rest)
        c.cal[rest] = val
    elif head == "spells":
        if rest.split(".")[0] in c.spells or not rest:
            set_path(c.spells, rest, val)
        else:
            set_path(c.spells["spells"], rest, val)
    else:
        set_path(c.tuning, key, val)


def apply_preset(c, name):
    t = c.tuning
    if name in ("spec1", "spec1p"):
        t["rhythm"]["enabled"] = True
        t["rhythm"]["trial"]["enabled"] = True
        t["seal_kills"] = [350, 950, 650]
        t["xp_thresholds"] = [0, 12, 80, 125, 260, 460, 625, 1005, 1385, 1775, 2380, 9000]
        c.mode = "s"
    if name == "spec1p":
        t["rhythm"]["pressure"] = {"enabled": True, "on_bps": 8500, "off_bps": 6000, "rise_per_s": 1, "fall_per_s": 2, "max": 40,
                                   "contact_per_point_bps": 500, "ranged_interval_per_point_bps": 125, "potion_cut_from": 20, "potion_bps": 5000}
        t["rhythm"]["boss"]["enrage"] = [{"after_ticks": 5400, "ward_interval_bps": 5000}, {"after_ticks": 9000, "ward_interval_bps": 5000}]
    if name == "current_on":  # 지금 값 + 리듬만 켬(W1b와 같은 조건, 시계 배율은 코어가 뺀다)
        t["rhythm"]["enabled"] = True
        t["rhythm"]["trial"]["enabled"] = True
        c.mode = "legacy"
    if name not in ("spec1", "spec1p", "current_on", "current"):
        raise SystemExit("알 수 없는 preset: " + name)


def parse_gear(g):
    if not g:
        return {"dmg": 1.0, "hp": 1.0}
    out = {"dmg": 1.0, "hp": 1.0}
    if re.fullmatch(r"[0-9.]+", g):
        x = float(g)
        return {"dmg": x, "hp": 1 + 0.5 * (x - 1)}
    for part in g.split(","):
        k, v = part.split("=")
        out[k.strip()] = float(v)
    return out


# ---- 주문 효과값 ----------------------------------------------------------
class Sp:
    __slots__ = ("dmg", "reach", "evolved", "partner", "rank")

    def __init__(self):
        self.dmg = 0
        self.reach = 0
        self.evolved = False
        self.partner = None
        self.rank = 1


def s_eff(cfg, sid, sp):
    d = cfg.spells["spells"][sid]
    b = dict(d["base"])
    b.update(d["reach"][sp.reach])
    ax = cfg.spells["axis"]["power"]
    dmg = b["damage_raw"] / 256.0 * ax["damage_bps"][sp.dmg] / 1e4
    cd = b["cooldown_ticks"] / 60.0 * ax["cooldown_bps"][sp.dmg] / 1e4
    role = d["role"]
    chain = b.get("chain_targets", 0)
    st = dict(id=sid, role=role, elem=d["element"], dmg=dmg, cd=cd, k=b.get("projectiles", 1), pierce=b.get("pierce", 0),
              r=b.get("radius_cm", 0) / 100.0, budget=b.get("hit_budget", 1), chain=chain, branches=b.get("branches", 1),
              R=b.get("ring_radius_cm", 0) / 100.0, rt=b.get("ring_targets", 0), pulses=b.get("ring_pulses", 1),
              vs=d.get("vs_strong_bps", 10000) / 1e4, applies=d.get("applies", {}), det=d.get("detonates", {}),
              prefer=d.get("prefer"), burst=0, shatter=0)
    st["kind"] = "ring" if role == "ring" else ("chain" if chain > 0 else "proj")
    if sp.evolved:
        cal = cfg.cal
        st["dmg"] *= cal["evolve_damage_mul"]
        st["cd"] *= cal["evolve_cd_mul"]
        st["budget"] = int(st["budget"] * cal["evolve_budget_mul"])
        if st["kind"] == "proj":
            st["k"] += int(cal["evolve_k_add"])
            st["r"] *= cal["evolve_reach_mul"]
        elif st["kind"] == "chain":
            st["chain"] = int(round(st["chain"] * 1.4))
            st["branches"] += 1
        else:
            st["R"] *= cal["evolve_reach_mul"]
            if st["rt"]:
                st["rt"] = int(st["rt"] * 1.3)
    return st


def legacy_eff(cfg, sid, rank, evo, primary):
    skills = {s["id"]: s for s in cfg.gq["skills"]}
    s = skills[sid]
    b = dict(s["evolution"] if evo else s["ranks"][rank - 1])
    pb_all = cfg.tuning.get("primary_bonus", {})
    sec = cfg.tuning.get("secondary", {})
    dmg_raw = b["damage_raw"]
    cdt = b["cooldown_ticks"]
    if primary and sid in pb_all:
        pb = pb_all[sid].get("evo" if evo else "r%d" % rank)
        if pb:
            for k, v in pb.get("add", {}).items():
                b[k] = b.get(k, 0) + v
            cdt = cdt * pb.get("cooldown_bps", 10000) / 1e4
            dmg_raw = dmg_raw * pb.get("mul_bps", {}).get("damage_raw", 10000) / 1e4
    elif not primary:
        dmg_raw = dmg_raw * sec.get("damage_bps", 10000) / 1e4
        cdt = cdt * 10000 / sec.get("cooldown_bps", 10000)
        b["chain_targets"] = min(b.get("chain_targets", 0), sec.get("max_chain_targets", 4))
        b["branches"] = min(b.get("branches", 1), sec.get("max_branches", 2))
    b["hit_budget"] = max(1, b.get("hit_budget", 1))
    chain = b.get("chain_targets", 0)
    elem = sid.split(".")[-1]
    st = dict(id=sid, role="basic", elem=elem, dmg=dmg_raw / 256.0, cd=cdt / 60.0, k=max(1, b.get("projectiles", 1)),
              pierce=b.get("pierce", 0), r=max(0, b.get("radius_cm", 0)) / 100.0 if chain == 0 else 0.0, budget=b["hit_budget"],
              chain=chain, branches=b.get("branches", 1), R=0.0, rt=0, pulses=1, vs=1.0, applies={}, det={}, prefer=None,
              burst=b.get("death_burst", 0), shatter=b.get("shatter_count", 0))
    st["kind"] = "chain" if (chain > 0 and b.get("projectiles", 0) == 0) else "proj"
    return st


class Build:
    def __init__(self, cfg, witch):
        self.cfg = cfg
        self.witch = witch
        self.sp = {}
        self.passives = set()
        self.vigor = 0
        self.flasks = 0
        self.guard = 0
        self._eff = None
        basic = SK + witch
        self.sp[basic] = Sp()
        self.primary = basic

    def clone(self):
        b = Build.__new__(Build)
        b.cfg, b.witch, b.primary = self.cfg, self.witch, self.primary
        b.sp = {}
        for k, v in self.sp.items():
            n = Sp()
            n.dmg, n.reach, n.evolved, n.partner, n.rank = v.dmg, v.reach, v.evolved, v.partner, v.rank
            b.sp[k] = n
        b.passives = set(self.passives)
        b.vigor, b.flasks, b.guard = self.vigor, self.flasks, self.guard
        b._eff = None
        return b

    def eff(self):
        if self._eff is None:
            c = self.cfg
            if c.mode == "legacy":
                self._eff = [legacy_eff(c, k, v.rank, v.evolved, k == self.primary) for k, v in self.sp.items()]
            else:
                self._eff = [s_eff(c, k, v) for k, v in self.sp.items()]
            gd = c.gear["dmg"]
            if gd != 1.0:
                for e in self._eff:
                    e["dmg"] *= gd
        return self._eff

    def dirty(self):
        self._eff = None

    def axis_sum(self, sid):
        s = self.sp[sid]
        return s.dmg + s.reach


# ---- 위협 쪽 규칙 ----------------------------------------------------------
class Rules:
    """한 순간의 생성·체력·섞임. 리듬이 켜지면 마디 표, 아니면 지금 게임의 생성 규칙."""

    def __init__(self, cfg):
        self.c = cfg
        t = cfg.tuning
        self.T = t
        self.rh = t.get("rhythm", {})
        self.on = bool(self.rh.get("enabled"))
        self.trial_on = bool(self.rh.get("trial", {}).get("enabled"))
        self.beats = self.rh.get("beats", [])
        self.seal = t["seal_kills"]

    def zone_beats(self, z):
        return [i for i, b in enumerate(self.beats) if b["zone"] == z]


def hp_list(T, zone, mix, hp_mult, opening=False):
    e = T["enemies"]
    w, r, ch = mix
    hw = e["walker"]["hp"][zone]
    if opening:
        hw = e["walker"].get("opening_hp", hw)
    return [(w, hw * hp_mult), (r, e["ranged"]["hp"][zone] * hp_mult), (ch, e["charger"]["hp"][zone] * hp_mult)]


def legacy_mix(T, zone, t):
    m = T["spawn"]["mix"]
    step = m.get("zone_step", 3)
    ch = max(0.0, (100 - m["charger_roll"]) + step * zone * 0.5) if t >= m["charger_from_s"] else 0.0
    rg = max(0.0, (m["charger_roll"] - m["ranged_roll"]) + step * zone * 0.5) if t >= m["ranged_from_s"] else 0.0
    w = max(0.0, 100.0 - ch - rg)
    s = w + rg + ch
    return (w / s, rg / s, ch / s)


# ---- 힘 -------------------------------------------------------------------
def spell_hits(st, N, c):
    """주문 하나가 N마리 앞에서 초당 내는 명중 수(깊이 0)."""
    if N <= 0.0:
        return 0.0
    kind = st["kind"]
    if kind == "proj":
        phi = min(0.9, c["phi_base"] + c["phi_per_alive"] * N)
        rho = c["cluster"] * N / (math.pi * c["field_r_m"] ** 2)
        n = st["k"] * (1 + st["pierce"] * phi) * (1 + rho * math.pi * st["r"] ** 2)
        n = min(n, st["budget"] * max(1, st["k"]) if st["budget"] < st["k"] else st["budget"], st["k"] + N)
        n = max(n, 1.0)
        return min(1.0, N) / st["cd"] * n
    if kind == "chain":
        n = min(st["budget"], st["chain"] * st["branches"], N)
        return min(1.0, N) / st["cd"] * max(n, 1.0) * 1.0
    m = N * (1 - math.exp(-(st["R"] / c["r0_hero_m"]) ** 2))
    cap = st["rt"] if st["rt"] else st["budget"]
    cap = min(cap, st["budget"])
    return st["pulses"] * min(cap * (1 - math.exp(-m)), m) / st["cd"]


class Power:
    """주어진 빌드·밀도에서 처리량(HP/s), 명중 수, 터뜨림 몫."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.c = cfg.cal

    def hits_table(self, build, N):
        c = self.c
        eta = c["eta_aim"]
        effs = build.eff()
        H = []
        for st in effs:
            h = spell_hits(st, N, c) * eta
            if build.cfg.mode == "legacy":
                m = 1.0
                if st["burst"]:
                    m *= c["burst_mult_legacy"]
                if st["shatter"]:
                    m *= 1 + c["shatter_per_legacy"] * st["shatter"]
                h *= m
            H.append(h)
        return effs, H

    def evaluate(self, build, N):
        """돌려준다: (총 명중/s, 평균 명중 피해, 총 피해/s, 터뜨림·반응 피해/s)"""
        cfg = self.cfg
        c = self.c
        effs, H = self.hits_table(build, N)
        mult = [1.0] * len(effs)
        extra = []  # (hits/s, dmg per hit)
        det_dmg = 0.0
        if cfg.mode == "s" and N > 0:
            ex = cfg.spells["model_extras"]
            stat = cfg.spells["statuses"]
            partner_bps = cfg.spells["evolve"]["partner_detonate_bps"] / 1e4
            # 상태 누적률: (status, src) -> 적 한 마리당 초당 스택
            rate = {}
            for st, h in zip(effs, H):
                for s_name, n in st["applies"].items():
                    rate[(s_name, st["id"])] = h * n / max(N, 1.0)
            for i, st in enumerate(effs):
                for s_name, dd in st["det"].items():
                    sm = stat[s_name]
                    win = sm["expire_ticks"] / 60.0
                    if dd.get("consume"):
                        win = min(win, st["cd"])
                    stacks = 0.0
                    boosted = False
                    for (sn, src), r in rate.items():
                        if sn == s_name and src != st["id"]:
                            stacks += r * win
                            if self._paired_evolved(build, st["id"], src):
                                boosted = True
                    stacks = min(sm["max"], stacks)
                    p_has = 1 - math.exp(-stacks)
                    if "per_stack_bps" in dd:
                        m = 1 + dd["per_stack_bps"] / 1e4 * stacks
                    else:
                        pe = p_has
                        if st["prefer"] == s_name and st["rt"]:
                            mR = N * (1 - math.exp(-(st["R"] / c["r0_hero_m"]) ** 2))
                            pe = min(1.0, mR * p_has / max(1, st["rt"]))
                        m = 1 + dd["bonus_bps"] / 1e4 * pe
                    if boosted:
                        m = 1 + (m - 1) * partner_bps
                    mult[i] = max(mult[i], m)
            # 원소 반응
            elems = {}
            for i, st in enumerate(effs):
                e = elems.setdefault(st["elem"], {"h": 0.0, "d": 0.0, "n": 0})
                e["h"] += H[i]
                e["d"] += st["dmg"]
                e["n"] += 1
            pst = {}
            for e in elems:
                stacks = 0.0
                for (sn, src), r in rate.items():
                    if sn == STATUS_OF[e]:
                        stacks += r * stat[sn]["expire_ticks"] / 60.0
                pst[e] = (1 - math.exp(-min(stat[STATUS_OF[e]]["max"], stacks)), min(stat[STATUS_OF[e]]["max"], stacks))
            for pr in cfg.spells["pairs"]:
                if pr["kind"] != "reaction":
                    continue
                X, Y = pr["elements"]
                if X not in elems or Y not in elems:
                    continue
                rx = ex["reactions"][pr["reaction"]]
                gate = rx["gate_s"]
                evr = elems[X]["h"] * pst[Y][0] + elems[Y]["h"] * pst[X][0]
                evr = min(evr, N * max(pst[X][0], pst[Y][0]) / gate)
                dref = (elems[X]["d"] / elems[X]["n"] + elems[Y]["d"] / elems[Y]["n"]) / 2
                rho = c["cluster"] * N / (math.pi * c["field_r_m"] ** 2)
                if "radius_m" in rx:
                    nb = min(rx["budget"], 1 + rho * math.pi * rx["radius_m"] ** 2)
                else:
                    nb = min(rx["targets"], max(1.0, N * pst[X][0] if X == "frost" else N * pst[Y][0]))
                dmg = rx["dmg"] * dref * (1 + rx.get("per_stack", 0) * pst["ember"][1] if "ember" in pst else 1)
                amp = 1.0
                if build.passives & set(rx["status_elements"]):
                    amp *= ex["passive_reaction_bps"] / 1e4
                if any(build.sp[k].evolved for k in build.sp if build.sp[k].partner and
                       cfg.spells["spells"][k]["element"] in rx["status_elements"]):
                    amp *= partner_bps
                extra.append((evr * nb * c["eta_aim"] / c["eta_aim"], dmg * amp))
        tot_h = 0.0
        tot_dmg = 0.0
        for st, h, m in zip(effs, H, mult):
            tot_h += h
            tot_dmg += h * st["dmg"] * m
            det_dmg += h * st["dmg"] * (m - 1)
        for h, d in extra:
            tot_h += h
            tot_dmg += h * d
            det_dmg += h * d
        dbar = tot_dmg / tot_h if tot_h > 0 else 0.0
        return tot_h, dbar, tot_dmg, det_dmg

    def _paired_evolved(self, build, a, b):
        sa, sb = build.sp.get(a), build.sp.get(b)
        return bool((sa and sa.evolved and sa.partner == b) or (sb and sb.evolved and sb.partner == a))

    def p_single(self, build, N):
        """강한 적 하나에게 주는 초당 피해(D12 P3). N은 그 곁의 일반 적 수."""
        c = self.c
        s = 1.0 / (1.0 + c["single_kappa"] * N)
        tot = 0.0
        has_applier = {}
        effs = build.eff()
        for st in effs:
            for sn in st["applies"]:
                has_applier.setdefault(sn, set()).add(st["id"])
        for st in effs:
            base = st["dmg"] / st["cd"]
            if st["kind"] == "proj":
                v = base * st["k"] * c["single_proj_acc"] * s * (1 + (c["single_splash"] if st["r"] > 0 else 0.0))
            elif st["kind"] == "chain":
                v = base * min(1.0, st["chain"] * st["branches"] / (1.0 + N)) if N > 0 else base
            else:
                pin = min(1.0, st["R"] / c["ring_in_r_m"])
                v = base * st["vs"] * pin * st["pulses"]
            m = 1.0
            if self.cfg.mode == "s":
                for sn, dd in st["det"].items():
                    if any(x != st["id"] for x in has_applier.get(sn, ())):
                        bonus = dd.get("bonus_bps", dd.get("per_stack_bps", 0) * 2) / 1e4
                        m = max(m, 1 + bonus * c["p_status_single"])
            tot += v * m * c["eta_aim"]
        return tot


# ---- 카드와 정책 ------------------------------------------------------------
def basic_id(w):
    return SK + w


def ring_id(w):
    return SK + w + "_ring"


def pair_members(cfg, witch, role):
    a, b = WITCH_AB[witch]
    ids = {"basic": basic_id(witch), "ring": ring_id(witch), "A": basic_id(a), "B": basic_id(b)}
    x, y = role.split("_")
    return ids[x], ids[y]


def spells_paired(cfg, x, y):
    ex, ey = cfg.spells["spells"][x]["element"], cfg.spells["spells"][y]["element"]
    for pr in cfg.spells["pairs"]:
        if pr["kind"] == "detonate" and {pr["a"], pr["b"]} == {x, y}:
            return True
        if pr["kind"] == "reaction" and ex != ey and {ex, ey} == set(pr["elements"]):
            return True
    return False


def partner_of(cfg, build, sid):
    best, bs = None, -1
    for k in build.sp:
        if k != sid and spells_paired(cfg, sid, k) and build.axis_sum(k) > bs:
            best, bs = k, build.axis_sum(k)
    return best, bs


def axis_ok(cfg, build, sid, which, amt=1):
    ax = cfg.spells["axis"]
    s = build.sp[sid]
    cur = s.dmg if which == "damage" else s.reach
    return cur + 1 <= ax["cap_per_axis"] and build.axis_sum(sid) + 1 <= ax["cap_per_spell"]


def evolve_ok(cfg, build, sid, level):
    ev = cfg.spells["evolve"]
    s = build.sp.get(sid)
    if not s or s.evolved or level < cfg.cal["evolve_min_level"]:
        return False
    if build.axis_sum(sid) < ev["axis_sum"]:
        return False
    if ev.get("needs_passive", True) and cfg.spells["spells"][sid]["element"] not in build.passives:
        return False
    p, ps = partner_of(cfg, build, sid)
    return p is not None and ps >= ev["partner_axis_sum"]


def unlockable(cfg, build, witch):
    out = []
    if len(build.sp) >= cfg.spells["slots"]:
        return out
    for k, d in cfg.spells["spells"].items():
        if k in build.sp:
            continue
        if d["role"] == "ring":
            if d.get("owner") != "chapter1.character." + witch:
                continue
        out.append(k)
    return out


def pool_cards(cfg, build, witch, level):
    cal = cfg.cal
    cards = []
    for k in unlockable(cfg, build, witch):
        cards.append(("unlock", k, 100))
    for k in build.sp:
        for wh in ("damage", "reach"):
            if axis_ok(cfg, build, k, wh):
                cards.append(("axis", k, wh, 100))
        if evolve_ok(cfg, build, k, level):
            cards.append(("evolve", k, 300))
    if level >= cal["passive_from_level"] and len(build.passives) < 3:
        for e in sorted({cfg.spells["spells"][k]["element"] for k in build.sp} - build.passives):
            cards.append(("passive", e, 100))
    if level >= cal["survival_from_level"]:
        if build.vigor < 2:
            cards.append(("survival", "vigor", 50))
        if build.flasks < 1:
            cards.append(("survival", "flasks", 50))
        if build.guard < 2:
            cards.append(("survival", "guard", 50))
    return cards


def card_key(c):
    return c[:-1]


def protected_card(cfg, build, witch, level, final=False):
    pr = cfg.spells["protect"]
    cards = pool_cards(cfg, build, witch, level)
    keys = {card_key(c): c for c in cards}
    unl = [c for c in cards if c[0] == "unlock"]

    def best_axis(sid):
        s = build.sp[sid]
        wh = "damage" if s.dmg <= s.reach else "reach"
        for w in (wh, "reach" if wh == "damage" else "damage"):
            if ("axis", sid, w) in keys:
                return keys[("axis", sid, w)]
        return None

    if final:
        for c in cards:
            if c[0] == "evolve":
                return c
        for c in cards:
            if c[0] == "passive":
                return c
    if level == pr["ring_at_level"]:
        r = ring_id(witch)
        if ("unlock", r) in keys:
            return keys[("unlock", r)]
    lo, hi = pr["pair_open_levels"]
    if lo <= level <= hi:
        for c in unl:
            if any(spells_paired(cfg, c[1], k) for k in build.sp):
                return c
        pairs = [(a, b) for a in build.sp for b in build.sp if a < b and spells_paired(cfg, a, b)]
        if pairs:
            a, b = min(pairs, key=lambda p: min(build.axis_sum(p[0]), build.axis_sum(p[1])))
            t = a if build.axis_sum(a) <= build.axis_sum(b) else b
            return best_axis(t)
    if pr.get("toward_evolve") and level > hi:
        order = sorted(build.sp, key=lambda k: -build.axis_sum(k))
        for k in order:
            s = build.sp[k]
            if s.evolved:
                continue
            if ("evolve", k) in keys:
                return keys[("evolve", k)]
            if build.axis_sum(k) < cfg.spells["evolve"]["axis_sum"]:
                return best_axis(k)
            if cfg.spells["spells"][k]["element"] not in build.passives:
                if ("passive", cfg.spells["spells"][k]["element"]) in keys:
                    return keys[("passive", cfg.spells["spells"][k]["element"])]
            p, ps = partner_of(cfg, build, k)
            if p is None:
                for c in unl:
                    if spells_paired(cfg, c[1], k):
                        return c
            elif ps < cfg.spells["evolve"]["partner_axis_sum"]:
                return best_axis(p)
            break
    return None


def apply_card(cfg, build, card, rng, level, rare=False):
    kind = card[0]
    if kind == "unlock":
        build.sp[card[1]] = Sp()
    elif kind == "axis":
        s = build.sp[card[1]]
        ax = cfg.spells["axis"]
        amt = 2 if rare else 1
        for _ in range(amt):
            if axis_ok(cfg, build, card[1], card[2]):
                if card[2] == "damage":
                    s.dmg += 1
                else:
                    s.reach += 1
    elif kind == "passive":
        build.passives.add(card[1])
    elif kind == "evolve":
        s = build.sp[card[1]]
        s.evolved = True
        s.partner = partner_of(cfg, build, card[1])[0]
    elif kind == "survival":
        if card[1] == "vigor":
            build.vigor += 1
        elif card[1] == "flasks":
            build.flasks += 1
        else:
            build.guard += 1
    build.dirty()


class Policy:
    def __init__(self, name, cfg, witch, rng, power):
        self.name, self.cfg, self.witch, self.rng, self.pw = name, cfg, witch, rng, power
        self.kind = name.split(":")[0]
        self.role = name.split(":")[1] if ":" in name else None
        self.pair = None  # (X, Y) 주문 id

    def dP(self, build, card, level):
        b = build.clone()
        apply_card(self.cfg, b, card, self.rng, level)
        ref = self.cfg.cal["ref_density_n"]
        return self.pw.evaluate(b, ref)[2] + 0.05 * self.pw.p_single(b, 5) - (self.pw.evaluate(build, ref)[2] + 0.05 * self.pw.p_single(build, 5))

    def choose(self, build, offer, level):
        cfg = self.cfg
        k = self.kind
        if k == "random":
            return self.rng.choice(offer)
        if k == "worst":
            return min(offer, key=lambda c: (self.dP(build, c, level), c[0] == "unlock"))
        if k == "spread":
            return self.spread(build, offer, level)
        if k == "narrow":
            return self.narrow(build, offer, level, basic_id(self.witch))
        if k == "narrow_ring":
            return self.narrow(build, offer, level, ring_id(self.witch))
        if k == "synergy":
            return self.synergy(build, offer, level)
        raise SystemExit("알 수 없는 정책: " + self.name)

    def lowest(self, build, offer, level):
        return min(offer, key=lambda c: self.dP(build, c, level))

    def best(self, build, offer, level):
        return max(offer, key=lambda c: self.dP(build, c, level))

    def spread(self, build, offer, level):
        un = [c for c in offer if c[0] == "unlock"]
        if un:
            return un[0]
        ax = [c for c in offer if c[0] == "axis"]
        if ax:
            return min(ax, key=lambda c: (build.axis_sum(c[1]), build.sp[c[1]].dmg if c[2] == "damage" else build.sp[c[1]].reach))
        for kd in ("passive", "evolve", "survival"):
            x = [c for c in offer if c[0] == kd]
            if x:
                return x[0]
        return offer[0]

    def narrow(self, build, offer, level, target):
        if target not in build.sp:
            un = [c for c in offer if c == ("unlock", target, 100) or (c[0] == "unlock" and c[1] == target)]
            if un:
                return un[0]
            return self.lowest(build, offer, level)
        el = self.cfg.spells["spells"][target]["element"]
        for c in offer:
            if c[0] == "evolve" and c[1] == target:
                return c
        for c in offer:
            if c[0] == "passive" and c[1] == el:
                return c
        ax = [c for c in offer if c[0] == "axis" and c[1] == target]
        if ax:
            return min(ax, key=lambda c: build.sp[target].dmg if c[2] == "damage" else build.sp[target].reach)
        return self.lowest(build, offer, level)

    def commit_pair(self, build, offer):
        if self.pair:
            return
        order = [self.role] if self.role else PAIR_ROLES
        for role in order:
            x, y = pair_members(self.cfg, self.witch, role)
            ok = True
            for m in (x, y):
                if m in build.sp:
                    continue
                if not any(c[0] == "unlock" and c[1] == m for c in offer):
                    ok = False
            if ok:
                self.pair = (x, y)
                return
        if self.role:
            self.pair = pair_members(self.cfg, self.witch, self.role)

    def synergy(self, build, offer, level):
        cfg = self.cfg
        self.commit_pair(build, offer)
        if not self.pair:
            return self.best(build, offer, level)
        x, y = self.pair
        # 우선순위가 높은 쪽(기본기 > 원형 > A > B)이 5, 짝이 2
        pri = {basic_id(self.witch): 0, ring_id(self.witch): 1}
        for e in ELEMS:
            pri.setdefault(basic_id(e), 2)
        if pri.get(x, 3) > pri.get(y, 3):
            x, y = y, x
        # 1 짝의 빈 쪽 열기
        for m in (x, y):
            if m not in build.sp:
                for c in offer:
                    if c[0] == "unlock" and c[1] == m:
                        return c
        if x not in build.sp or y not in build.sp:
            return self.best(build, offer, level)
        ev = cfg.spells["evolve"]
        thr = {x: ev["axis_sum"], y: ev["partner_axis_sum"]}
        # 2 축 점수를 문턱까지 번갈아
        need = [m for m in (x, y) if build.axis_sum(m) < thr[m]]
        ax = [c for c in offer if c[0] == "axis" and c[1] in need]
        if ax:
            return min(ax, key=lambda c: (build.axis_sum(c[1]) / thr[c[1]], build.sp[c[1]].dmg if c[2] == "damage" else build.sp[c[1]].reach))
        # 3 결정, 4 진화
        for c in offer:
            if c[0] == "evolve" and c[1] == x:
                return c
        for c in offer:
            if c[0] == "passive" and c[1] == cfg.spells["spells"][x]["element"]:
                return c
        # 둘째 길: 짝이 진화
        if build.sp[x].evolved:
            for c in offer:
                if c[0] == "evolve" and c[1] == y:
                    return c
            for c in offer:
                if c[0] == "passive" and c[1] == cfg.spells["spells"][y]["element"]:
                    return c
            ax = [c for c in offer if c[0] == "axis" and c[1] == y]
            if ax:
                return ax[0]
        # 5 남은 점수는 터뜨리는 쪽의 넓이 축
        det = x if cfg.spells["spells"][x]["detonates"] else y
        for c in offer:
            if c[0] == "axis" and c[1] == det and c[2] == "reach":
                return c
        for c in offer:
            if c[0] == "axis" and c[1] in (x, y):
                return c
        for c in offer:
            if c[0] == "survival":
                return c
        return self.best(build, offer, level)


def make_offer(cfg, build, witch, level, rng, final=False):
    cal = cfg.cal
    pool = pool_cards(cfg, build, witch, level)
    if not pool:
        return []
    size = int(cal["offer_size"])
    prot = protected_card(cfg, build, witch, level, final)
    offer = []
    if prot is not None:
        offer.append(prot)
        pool = [c for c in pool if card_key(c) != card_key(prot)]
    while pool and len(offer) < size:
        ws = [c[-1] for c in pool]
        r = rng.random() * sum(ws)
        acc = 0.0
        pick = pool[-1]
        for c, w in zip(pool, ws):
            acc += w
            if r <= acc:
                pick = c
                break
        offer.append(pick)
        pool = [c for c in pool if card_key(c) != card_key(pick)]
    return offer


# ---- 한 판 ----------------------------------------------------------------
def legacy_apply_pick(build, pick):
    parts = pick.split(":")
    kind = parts[0]
    sid = SK + parts[1].split(".")[-1] if kind in ("unlock", "rank", "evolve") else None
    if kind == "unlock":
        build.sp.setdefault(sid, Sp())
    elif kind == "rank":
        s = build.sp.setdefault(sid, Sp())
        s.rank = max(s.rank, int(parts[2]))
    elif kind == "evolve":
        build.sp.setdefault(sid, Sp()).evolved = True
    elif kind == "passive":
        build.passives.add(parts[1].split(".")[-1])
    build.dirty()


def simulate(cfg, policy, witch, seed, replay=None, trace=False):
    T = cfg.tuning
    c = cfg.cal
    R = Rules(cfg)
    dt = cfg.dt
    rng = random.Random(seed * 100003 + zlib.crc32((policy + witch).encode()))
    luck = math.exp(rng.gauss(0, c["power_luck_sigma"]))
    pw = Power(cfg)
    build = Build(cfg, witch)
    pol = Policy(policy, cfg, witch, rng, pw) if cfg.mode == "s" else None
    replay = list(replay or [])
    heroHP = (c["hero_hp"]) * cfg.gear["hp"]
    maxhp = heroHP
    hp = maxhp
    potions = T["potion"]["start"]
    pot_cd = 0.0
    pcap = T["potion"]["carry_max"]
    pot_acc = 0.0
    level = 1
    xp = 0.0
    thr = T["xp_thresholds"]
    rh, on = R.rh, R.on
    pres_cfg = rh.get("pressure", {}) if on else {}
    pres_on = bool(pres_cfg.get("enabled"))
    enrage = rh.get("boss", {}).get("enrage", []) if on else []
    pressure = 0.0
    N = float(rh.get("initial_pack", 6) if on else 12)
    zone = 0
    zk = 0.0
    beat_i = R.zone_beats(0)[0] if on else -1
    beat_t = 0.0
    phase = "zone"  # zone, champ, rest, trial, boss
    rest_left = 0.0
    champ = None
    champ_idx = 0
    boss_t = 0.0
    trial_t = 0.0
    t = 0.0
    kills = 0.0
    kills_total = 0.0
    taken = {"contact": 0.0, "champ": 0.0}
    hist = []  # 최근 20초 피해
    res = {"policy": policy, "witch": witch, "seed": seed, "win": False, "death": None, "cause": None, "stall": False}
    per = {}
    grace_times = []
    picks = []
    single_R = []
    det_total = 0.0
    dmg_total = 0.0
    crest_done = set()
    taste_done = False
    crest_phase_last = -1
    evolve_level = [None, None]
    last_beat_label = None
    boss_spawned = False
    wave_n = 0
    trace_rows = []
    pend_levels = 0
    potions_used = 0

    def label():
        if on:
            if phase == "boss":
                return "전C"
            if phase == "trial":
                return "전B"
            if beat_i < 0:
                return "기"
            return RHY_LABEL.get(R.beats[beat_i]["id"], R.beats[beat_i]["id"])
        for nm, a, b in LEGACY_BEATS:
            if a <= t < b:
                return nm
        return "전C"

    def do_level():
        nonlocal level
        level += 1
        grace_times.append(round(t, 1))
        if cfg.mode == "legacy":
            if replay:
                p = replay.pop(0)
                picks.append(p)
                legacy_apply_pick(build, p)
            return
        final = level >= len(thr)
        offer = make_offer(cfg, build, witch, level, rng, final)
        if not offer:
            return
        card = pol.choose(build, offer, level)
        rare = card[0] == "axis" and rng.random() < c["rare_axis_p"]
        apply_card(cfg, build, card, rng, level, rare)
        picks.append("%s:%s%s" % (card[0], card[1].split(".")[-1], (":" + card[2]) if card[0] == "axis" else ""))
        if card[0] == "evolve":
            evolve_level[0 if evolve_level[0] is None else 1] = round(t, 1)

    while t < CAP_S:
        lab = label()
        # ---- 규칙: 생성, 상한, 체력, 섞임
        opening = False
        wave_crest = 0
        cap_b = T["alive_cap"]
        if phase == "rest":
            lam = 0.0
            cap_b = T["alive_cap"]
        if on:
            if phase == "boss":
                bp = T["spawn"]["boss_phase"]
                lam = bp["amount"] / (bp["interval_ticks"] / 60.0)
                cap_b = c["boss_alive_cap"]
                mix = (0.69, 0.2, 0.11)
                hpm = rh["beats"][-1]["hp_bps"][1] / 1e4
                zhp = 2
            elif phase == "trial":
                tr = rh["trial"]
                lam = tr["amount"] / (tr["interval_ticks"] / 60.0)
                cap_b = tr["alive_cap"]
                m = tr["mix"]
                s_ = float(sum(m.values()))
                mix = (m["walker"] / s_, m["ranged"] / s_, m["charger"] / s_)
                hpm = tr["hp_bps"] / 1e4
                zhp = 2
            else:
                b = R.beats[beat_i]
                zhp = b["zone"]
                nxt = R.zone_beats(zhp)
                pk = nxt.index(beat_i)
                to_from = R.beats[nxt[pk + 1]]["from_bps"] if pk + 1 < len(nxt) else 10000
                p_bps = min(10000.0, zk / R.seal[zhp] * 10000.0)
                f = 0.0 if to_from <= b["from_bps"] else min(1.0, max(0.0, (p_bps - b["from_bps"]) / (to_from - b["from_bps"])))
                hpm = (b["hp_bps"][0] + (b["hp_bps"][1] - b["hp_bps"][0]) * f) / 1e4
                lam = b["amount"] / (b["interval_ticks"] / 60.0)
                cap_b = b["alive_cap"]
                m = dict(b["mix"])
                if "ranged_from_ticks" in b and beat_t * 60 < b["ranged_from_ticks"]:
                    m["walker"] += m["ranged"]
                    m["ranged"] = 0
                if "charger_from_ticks" in b and beat_t * 60 < b["charger_from_ticks"]:
                    m["walker"] += m["charger"]
                    m["charger"] = 0
                s_ = float(sum(m.values()))
                mix = (m["walker"] / s_, m["ranged"] / s_, m["charger"] / s_)
                wv = b.get("wave")
                if wv:
                    per_t = wv["period_ticks"] / 60.0
                    ph = beat_t % per_t
                    if ph >= per_t - wv["lull_ticks"] / 60.0:
                        lam *= wv["lull_amount_bps"] / 1e4
                        cap_b = int(cap_b * wv["lull_cap_bps"] / 1e4)
                    cyc = int(beat_t // per_t)
                    if (beat_i, cyc) not in crest_done and ph < dt:
                        crest_done.add((beat_i, cyc))
                        wave_crest = wv["crest"]["count"]
                if b.get("taste_crest") and not taste_done and beat_t * 60 >= b["taste_crest"]["at_ticks"]:
                    taste_done = True
                    wave_crest = b["taste_crest"]["count"]
        else:
            if phase == "boss":
                bp = T["spawn"]["boss_phase"]
                lam = bp["amount"] / (bp["interval_ticks"] / 60.0)
                zhp = 2
            else:
                zhp = zone
                zs = T["spawn"]["zones"][zone]
                lam = zs["amount"] / (zs["interval_ticks"] / 60.0)
                if zone == 0:
                    for o in T["spawn"]["opening"]:
                        if t < o["until_s"]:
                            lam = o["amount"] / (T["spawn"]["zones"][0]["interval_ticks"] / 60.0)
                            break
            opening = zone == 0 and t < T["enemies"]["walker"].get("opening_until_s", 30)
            mix = legacy_mix(T, zhp, t)
            hpm = 1 + max(0.0, t - T["hp_time_from_s"]) * T["hp_time_bps_per_s"] / 1e4
        if phase == "rest":
            lam = 0.0
        hl = hp_list(T, zhp, mix, hpm, opening)
        hbar = sum(w * h for w, h in hl)
        # ---- 생성
        spawn = min(lam * dt, max(0.0, cap_b - N))
        N += spawn + wave_crest * (1 if N < cap_b else 0)
        N = min(N, T["alive_cap"])
        # ---- 처리량과 처치
        tot_h, dbar, tot_dmg, det_dmg = pw.evaluate(build, N)
        tot_h *= luck
        tot_dmg *= luck
        det_dmg *= luck
        if tot_h > 0 and dbar > 0:
            htk = sum(w * max(1.0, math.ceil(h / dbar - 1e-9)) for w, h in hl)
            kill_cap = tot_h / htk * dt
        else:
            kill_cap = 0.0
        eff_n = N + 0.5 * spawn
        kill = min(kill_cap, eff_n * (1 - math.exp(-dt / c["tau_min_s"])))
        N_before = N
        N = max(0.0, N - kill)
        kills_total += kill
        if phase in ("zone", "champ"):
            zk += kill
        # 처리량 효율: 실제로 쓴 피해 비율
        used = kill * hbar
        dmg_total += tot_dmg * dt * (kill / kill_cap if kill_cap > 0 else 0)
        det_total += det_dmg * dt * (kill / kill_cap if kill_cap > 0 else 0)
        # 경험치
        xpk = (mix[0] * 1 + mix[1] * 2 + mix[2] * 3) * c["xp_mult"]
        xp += kill * xpk
        while level < len(thr) - 1 and xp >= thr[level]:
            do_level()
        # 힘 ÷ 위협(참고 표시)
        if int(t / dt) % 3 == 0:
            ph_, _, pd_, _ = pw.evaluate(build, cap_b)
            pot_ = pd_ * luck
            pr = per.setdefault(lab, {"secs": 0.0, "kills": 0.0, "alive": 0.0, "hits": 0.0, "dmg": 0.0, "Psum": 0.0, "Tsum": 0.0, "w": 0.0, "mx": 0.0})
            pr["Psum"] += pot_ * 3
            pr["Tsum"] += lam * hbar * 3 if lam > 0 else 0
        pr = per.setdefault(lab, {"secs": 0.0, "kills": 0.0, "alive": 0.0, "hits": 0.0, "dmg": 0.0, "Psum": 0.0, "Tsum": 0.0, "w": 0.0, "mx": 0.0})
        pr["secs"] += dt
        pr["kills"] += kill
        pr["alive"] += 0.5 * (N + N_before) * dt
        pr["mx"] = max(pr["mx"], N)
        # ---- 포위 압력
        if pres_on:
            if N >= pres_cfg["on_bps"] / 1e4 * cap_b:
                pressure = min(pres_cfg["max"], pressure + pres_cfg["rise_per_s"] * dt)
            elif N < pres_cfg["off_bps"] / 1e4 * cap_b:
                pressure = max(0.0, pressure - pres_cfg["fall_per_s"] * dt)
        # ---- 받는 피해
        e = T["enemies"]
        zi = min(zhp, 2)
        dmg_avg = sum(w * e[n]["damage"][zi] for w, n in zip(mix, ("walker", "ranged", "charger")))
        noise = math.exp(rng.gauss(0, c["noise_sigma"]) - c["noise_sigma"] ** 2 / 2)
        hits = c["hit_rate_per_alive"] * N * dt * noise
        mult = 1.0
        if pres_on:
            mult += pressure * pres_cfg["contact_per_point_bps"] / 1e4
        gmul = (1 - 0.08 * build.guard)
        d_contact = hits * dmg_avg * c["hit_dmg_scale"] * mult * gmul
        pr["hits"] += hits
        d_champ = 0.0
        # ---- 강한 적
        if phase in ("champ", "boss") and champ is not None:
            ps = pw.p_single(build, N) * luck
            champ["hp"] -= ps * dt
            cs = T["champions"][champ["idx"]]
            cyc = (cs["windup"] + cs["recover"]) / 60.0
            dd = cs["damage"] * c["champ_p_hit"] / cyc * dt
            if champ["idx"] == 2:
                boss_t += dt
                interval = c["ward_interval_s"]
                for en in enrage:
                    if boss_t * 60 >= en["after_ticks"]:
                        interval *= en["ward_interval_bps"] / 1e4
                dd += T["boss_ward"]["damage"] * c["ward_p_hit"] / interval * dt
            d_champ = dd * gmul
            if champ["hp"] <= 0:
                single_R.append((champ["idx"], round(champ["R"], 2), round(t - champ["t0"], 1)))
                xp += cs["xp"]
                while level < len(thr) - 1 and xp >= thr[level]:
                    do_level()
                if champ["idx"] == 2:
                    res["win"] = True
                    t += dt
                    break
                champ = None
                phase = "rest"
                rest_left = rh.get("gate_rest_ticks", 480) / 60.0 if on else 6.0
                potions = min(pcap, potions + T["potion"]["seal_drops"])
                N *= 0.4
        # ---- 체력, 회수약
        dmg_now = d_contact + d_champ
        hp -= dmg_now
        hist.append((d_contact, d_champ, N, pressure, boss_t))
        if len(hist) > int(20 / dt):
            hist.pop(0)
        pot_acc += kill / T["potion"]["drop_one_in"]
        if pot_acc >= 1:
            potions = min(pcap, potions + int(pot_acc))
            pot_acc -= int(pot_acc)
        pot_cd = max(0.0, pot_cd - dt)
        maxhp = heroHP + 20 * build.vigor
        if hp < c["potion_use_frac"] * maxhp and potions > 0 and pot_cd <= 0:
            heal = T["potion"]["heal_bps"] / 1e4 * maxhp
            if pres_on and pressure >= pres_cfg.get("potion_cut_from", 99):
                heal *= pres_cfg["potion_bps"] / 1e4
            hp = min(maxhp, hp + heal)
            potions -= 1
            potions_used += 1
            pot_cd = T["potion"]["cooldown_ticks"] / 60.0
        pr["dmg"] += dmg_now / maxhp
        if hp <= 0:
            res["death"] = lab
            sc = sum(h[0] for h in hist)
            sch = sum(h[1] for h in hist)
            avgN = sum(h[2] for h in hist) / len(hist)
            tot = sc + sch + 1e-9
            in_champ = champ is not None
            if sch / tot >= 0.5 or (in_champ and champ["idx"] == 2 and hist[-1][4] * 60 >= (enrage[0]["after_ticks"] if enrage else 1e9)):
                res["cause"] = "강한 적에 막힘"
            elif hist[-1][3] >= 20 or (avgN >= 0.8 * cap_b and sc / tot >= 0.6):
                res["cause"] = "깔림"
            else:
                res["cause"] = "그 밖"
            t += dt
            break
        # ---- 구역과 마디 진행
        t += dt
        if phase == "rest":
            rest_left -= dt
            if rest_left <= 0:
                phase = "zone"
                zone += 1
                zk = 0.0
                if on:
                    beat_i = R.zone_beats(zone)[0]
                    beat_t = 0.0
                    taste_done = True
                champ = None
        elif phase == "trial":
            trial_t += dt
            if trial_t >= (rh["trial"]["hold_ticks"] + rh["trial"]["clear_ticks"]) / 60.0:
                phase = "boss"
                boss_spawned = True
                champ = {"hp": T["champions"][2]["hp"], "idx": 2, "t0": t, "R": 0.0}
                champ["R"] = pw.p_single(build, 5) / (champ["hp"] / WINDOW_S[2])
                while level < len(thr) - 1 and thr[-1] and level < 12:
                    do_level()
        elif phase == "zone":
            beat_t += dt
            if on:
                zb = R.zone_beats(zone)
                pk = zb.index(beat_i)
                if pk + 1 < len(zb):
                    nb = R.beats[zb[pk + 1]]
                    if zk / R.seal[zone] * 10000 >= nb["from_bps"] or beat_t * 60 >= R.beats[beat_i]["max_ticks"]:
                        beat_i = zb[pk + 1]
                        beat_t = 0.0
            if zk >= R.seal[zone]:
                if zone < 2:
                    idx = zone
                    mh = T["champions"][idx]["hp"] * (1 + c["champ_time_scale"] * max(0.0, t - 30) * T["hp_time_bps_per_s"] / 1e4 if not on else 1)
                    champ = {"hp": mh, "idx": idx, "t0": t}
                    champ["R"] = pw.p_single(build, N) * luck / (mh / WINDOW_S[idx])
                    phase = "champ"
                elif on and R.trial_on:
                    phase = "trial"
                    trial_t = 0.0
                else:
                    phase = "boss"
                    mh = T["champions"][2]["hp"] * (1 + c["champ_time_scale"] * max(0.0, t - 30) * T["hp_time_bps_per_s"] / 1e4 if not on else 1)
                    champ = {"hp": mh, "idx": 2, "t0": t}
                    champ["R"] = pw.p_single(build, N) * luck / (mh / WINDOW_S[2])
                    while level < len(thr) - 1 and level < 12:
                        do_level()
        elif phase == "champ":
            beat_t += dt
        if trace:
            trace_rows.append((round(t, 1), lab, round(N, 1), round(kill / dt, 1), round(hp, 1), round(pressure, 1), level))
    else:
        res["stall"] = True
    res["secs"] = round(t, 1)
    res["kills"] = round(kills_total)
    res["level"] = level
    res["hp_end"] = round(max(0.0, hp) / maxhp, 3)
    res["per"] = per
    res["grace_times"] = grace_times
    res["picks"] = picks
    res["single_R"] = single_R
    res["evolve_t"] = [x for x in evolve_level if x is not None]
    res["det_share"] = round(det_total / dmg_total, 3) if dmg_total > 0 else 0.0
    res["potions"] = potions_used
    res["dmg_total"] = round(sum(x["dmg"] for x in per.values()), 3)
    res["build"] = {k.split(".")[-1]: (v.dmg, v.reach, v.evolved) if cfg.mode == "s" else (v.rank, v.evolved) for k, v in build.sp.items()}
    if trace:
        res["trace"] = trace_rows
    return res


# ---- 집계와 서열 -----------------------------------------------------------
def policy_class(name):
    return name.split(":")[0]


def run_matrix(cfg, policies, witches, seeds):
    out = {}
    for pol in policies:
        for w in witches:
            out[(pol, w)] = [simulate(cfg, pol, w, s) for s in seeds]
    return out


def med(xs):
    xs = sorted(xs)
    if not xs:
        return None
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def win_rate(rs):
    return sum(1 for r in rs if r["win"]) / len(rs) if rs else 0.0


def verdict_order(matrix, witches):
    """서열 판정: 마녀마다 synergy류(최댓값 길과 평균) > narrow >= random > spread > worst 이 성립하는가, 차이 %p."""
    lines = []
    ok_all = True
    for w in witches:
        def wr(p):
            return win_rate(matrix[(p, w)]) if (p, w) in matrix else None
        syn = [win_rate(v) for (p, ww), v in matrix.items() if ww == w and policy_class(p) == "synergy"]
        syn_mean = sum(syn) / len(syn) if syn else None
        syn_min = min(syn) if syn else None
        cls = {k: wr(k) for k in ("narrow", "narrow_ring", "random", "spread", "worst")}
        seq = [("synergy(평균)", syn_mean), ("narrow", cls["narrow"]), ("random", cls["random"]), ("spread", cls["spread"]), ("worst", cls["worst"])]
        seq = [(n, v) for n, v in seq if v is not None]
        ok = all(seq[i][1] >= seq[i + 1][1] for i in range(len(seq) - 1)) and (len(seq) < 2 or seq[0][1] > seq[1][1])
        gap = (syn_mean - cls["narrow"]) * 100 if syn_mean is not None and cls["narrow"] is not None else None
        ok_all &= ok
        lines.append((w, ok, gap, syn_min, seq))
    return ok_all, lines


def fmt_pct(x):
    return "  -  " if x is None else "%4.0f%%" % (x * 100)


def mark(v, rng):
    if rng is None or v is None:
        return " "
    lo, hi = rng
    if lo is not None and v < lo:
        return "<"
    if hi is not None and v > hi:
        return ">"
    return "o"


def report(cfg, matrix, policies, witches, seeds, label=""):
    lines = []
    A = lines.append
    A("== 균형 시뮬레이터 결과 %s ==  [모델의 답이지 게임의 답이 아니다. 재미는 미평가]" % label)
    A("스킬 구성 %s, 주문 데이터 %s, 리듬 %s, 시드 %s, dt %.1fs, 장비 %s" % (
        cfg.mode, Path(cfg.spells_path).name, "켬" if cfg.tuning["rhythm"].get("enabled") else "꺼짐",
        "%d~%d(%d판)" % (seeds[0], seeds[-1], len(seeds)), cfg.dt, cfg.gear if cfg.gear["dmg"] != 1 else "없음"))
    A("")
    A("정책 x 마녀 | 승률 | P7 | 판 길이 중앙 | 죽은 마디(원인) | 진화 시각(중앙) | 레벨 | 터뜨림 몫 | 남은생명(승)")
    for pol in policies:
        for w in witches:
            rs = matrix[(pol, w)]
            wr_ = win_rate(rs)
            cl = policy_class(pol)
            tg = P7_WIN.get(cl)
            m = mark(wr_, tg)
            deaths = {}
            for r in rs:
                if r["death"]:
                    k = "%s(%s)" % (r["death"], r["cause"])
                    deaths[k] = deaths.get(k, 0) + 1
                elif r["stall"]:
                    deaths["정체"] = deaths.get("정체", 0) + 1
            dtxt = ", ".join("%s %d" % kv for kv in sorted(deaths.items(), key=lambda kv: -kv[1])[:3]) or "-"
            ev = [r["evolve_t"][0] for r in rs if r["evolve_t"]]
            wins = [r for r in rs if r["win"]]
            A("%-18s %-6s %s %s %6.0fs  %-34s %s  L%.1f  %4.0f%%  %s" % (
                pol, w, fmt_pct(wr_), m, med([r["secs"] for r in rs]) or 0, dtxt,
                ("%5.0fs(%d/%d)" % (med(ev), len(ev), len(rs))) if ev else "   -  ",
                sum(r["level"] for r in rs) / len(rs), 100 * sum(r["det_share"] for r in rs) / len(rs),
                ("%.0f%%" % (100 * sum(r["hp_end"] for r in wins) / len(wins))) if wins else "-"))
    A("(P7 열: o=목표 범위 안, <, >=밖)")
    A("")
    # 힘 ÷ 위협 표
    A("마디별 힘 ÷ 위협 (무리: 상한 밀도에서의 처리량 / 들어오는 적 체력 합. 정책류 x 마녀 평균. P4 목표 옆 o/</>) ")
    beats = ["기", "승1", "승2", "전A", "전B"]
    A("%-12s" % "정책류" + "".join("%12s" % b for b in beats))
    classes = []
    for p in policies:
        cl = policy_class(p)
        if cl not in classes:
            classes.append(cl)
    for cl in classes:
        row = "%-12s" % cl
        for b in beats:
            vals = []
            for (p, w), rs in matrix.items():
                if policy_class(p) != cl:
                    continue
                for r in rs:
                    pr = r["per"].get(b)
                    if pr and pr["Tsum"] > 0:
                        vals.append(pr["Psum"] / pr["Tsum"])
            v = sum(vals) / len(vals) if vals else None
            tg = P4_R.get(b, {}).get(cl if cl in P4_R[b] else ("narrow" if cl == "narrow_ring" else cl))
            row += "%12s" % (("%.2f%s" % (v, mark(v, tg))) if v is not None else "-")
        A(row)
    A("")
    # 단일 R
    sr = {}
    for (p, w), rs in matrix.items():
        for r in rs:
            for idx, R_, dur in r["single_R"]:
                sr.setdefault((policy_class(p), idx), []).append((R_, dur))
    A("강한 적 단일 R (P_single ÷ 체력/허용창, 수호자1·수호자2·우두머리) 와 처치에 든 초(중앙)")
    for cl in classes:
        row = "%-12s" % cl
        for idx in range(3):
            v = sr.get((cl, idx))
            row += "%20s" % (("R %.2f / %3.0fs(n=%d)" % (sum(x[0] for x in v) / len(v), med([x[1] for x in v]), len(v))) if v else "-")
        A(row)
    A("")
    ok, vl = verdict_order(matrix, witches)
    A("서열 판정(P4): synergy > narrow >= random > spread > worst  => %s" % ("성립" if ok else "성립하지 않음"))
    for w, okw, gap, smin, seq in vl:
        A("  %-6s %s | %s | synergy−narrow %s | synergy 길 최저 %s" % (
            w, "성립" if okw else "깨짐", " > ".join("%s %.0f%%" % (n, v * 100) for n, v in seq),
            ("%+.0f%%p (목표 >=50)" % gap) if gap is not None else "-", fmt_pct(smin)))
    # 길 사이 차
    for w in witches:
        wrs = [(p, win_rate(matrix[(p, w)]), med([r["secs"] for r in matrix[(p, w)] if r["win"]])) for p in policies if policy_class(p) == "synergy" and ":" in p]
        if len(wrs) > 1:
            ts = [x[2] for x in wrs if x[2]]
            spread = (max(ts) - min(ts)) / max(ts) * 100 if len(ts) > 1 else None
            wl = max(x[1] for x in wrs) - min(x[1] for x in wrs)
            A("  길 사이(%s): 승률 최대-최소 %.0f%%p(목표 판수 1 이내=10%%p), 승리 시각 중앙값 차 %s(목표 15%% 이내)" % (
                w, wl * 100, ("%.0f%%" % spread) if spread is not None else "-"))
    stalls = sum(1 for rs in matrix.values() for r in rs if r["stall"])
    n = sum(len(rs) for rs in matrix.values())
    A("정체(600초): %d / %d판 (목표 0)" % (stalls, n))
    return "\n".join(lines)


def default_policies(mode):
    return ["synergy"] + ["synergy:" + r for r in PAIR_ROLES] + ["narrow", "narrow_ring", "random", "spread", "worst"]


def summarize_for_json(matrix):
    out = {}
    for (p, w), rs in matrix.items():
        out["%s|%s" % (p, w)] = {
            "win_rate": win_rate(rs), "n": len(rs), "secs_median": med([r["secs"] for r in rs]),
            "deaths": [{"beat": r["death"], "cause": r["cause"], "secs": r["secs"]} for r in rs if r["death"]],
            "stalls": sum(1 for r in rs if r["stall"]), "det_share_mean": sum(r["det_share"] for r in rs) / len(rs),
            "evolve_t": [r["evolve_t"] for r in rs], "builds": [r["build"] for r in rs],
            "per_beat": {b: {"secs": sum(r["per"].get(b, {}).get("secs", 0) for r in rs) / len(rs),
                             "R": (lambda a, b_: a / b_ if b_ else None)(sum(r["per"].get(b, {}).get("Psum", 0) for r in rs),
                                                                       sum(r["per"].get(b, {}).get("Tsum", 0) for r in rs))}
                         for b in ["기", "승1", "승2", "전A", "전B", "전C"]},
        }
    return out


# ---- 맞춤 -----------------------------------------------------------------
def beat_agg(rs_real_beats, label):
    k = a_n = a_s = h = d = tk = 0.0
    for b in rs_real_beats:
        x = b.get(label)
        if not x:
            continue
        k += x["kills"]
        a_n += x["alive_n"]
        a_s += x["alive_sum"]
        h += x["hits"]
        d += x["dmg"]
        tk += x["ticks"]
    if tk <= 0:
        return None
    return {"kpm": k / tk * 3600, "alive": a_s / max(a_n, 1), "hpm": h / tk * 3600, "secs": tk / 60}


def model_beat_agg(results, label):
    k = a = h = d = s = 0.0
    for r in results:
        x = r["per"].get(label)
        if not x:
            continue
        k += x["kills"]
        a += x["alive"]
        h += x["hits"]
        s += x["secs"]
    if s <= 0:
        return None
    return {"kpm": k / s * 60, "alive": a / s, "hpm": h / s * 60, "secs": s}


def err(a, b):
    if a is None or b is None or a == 0:
        return None
    return (b - a) / a * 100


def calibrate_data(cfg, real_dir, sub=None):
    sim = load_json(real_dir / "builds" / "sim-off.json")
    runs = sim["runs"]
    if sub:
        runs = [r for r in runs if sub(r)]
    mres = []
    for r in runs:
        res = simulate(cfg, r["policy"], r["primary"], int(r["seed"]), replay=r["picks"])
        mres.append((r, res))
    return mres


def calib_table(cfg, args):
    real_dir = Path(args.real_dir) if args.real_dir else find_real_dir()
    if not real_dir:
        raise SystemExit("실측 폴더(_local/builds/sim-off.json)를 찾지 못했다. --real-dir로 알려 달라")
    L = []
    A = L.append
    cfg.mode = "legacy"
    t0 = time.time()
    mres = calibrate_data(cfg, real_dir)
    A("== 맞춤: 지금 게임(스킬 재구성 전, 리듬 꺼짐)의 값을 모델에 넣고 실측과 비교 ==")
    A("실측: _local/builds/sim-off.json (정책 8 x 마녀 3 x 5판 = 120판, 같은 은총 선택 순서를 모델에 되먹임), 모델 시드는 실측과 같은 시드")
    A("")
    A("[표 1] 마디별 (120판 합산). 처치 분당 / 살아 있는 적 평균 / 분당 피격")
    A("마디   | 처치/분 실측 모델 오차 | 살아있는적 실측 모델 오차 | 피격/분 실측 모델 오차 | 판단")
    rb = [r["beats"] for r, _ in mres]
    mr = [m for _, m in mres]
    big = []
    for lab in ["기", "승1", "승2", "전A"]:
        a = beat_agg(rb, lab)
        m = model_beat_agg(mr, lab)
        if not a or not m:
            continue
        e1, e2, e3 = err(a["kpm"], m["kpm"]), err(a["alive"], m["alive"]), err(a["hpm"], m["hpm"])
        flag = "".join("!" if (e is not None and abs(e) > 30) else "." for e in (e1, e2, e3))
        if "!" in flag:
            big.append((lab, flag))
        A("%-5s | %8.0f %6.0f %+5.0f%% | %8.1f %6.1f %+5.0f%% | %7.1f %6.1f %+5.0f%% | %s" % (
            lab, a["kpm"], m["kpm"], e1 or 0, a["alive"], m["alive"], e2 or 0, a["hpm"], m["hpm"], e3 or 0, flag))
    A("(판단: 각 항목 오차 30% 초과면 !)")
    A("")
    A("[표 2] 정책별 승률과 판 길이(실측 5판 x 마녀 3 = 15판, 모델 같은 15판)")
    A("정책          | 승률 실측 모델 | 판 길이 중앙(초) 실측 모델 오차")
    pols = sorted({r["policy"] for r, _ in mres})
    for p in pols:
        rr = [(r, m) for r, m in mres if r["policy"] == p]
        rw = sum(1 for r, _ in rr if r["mode"] == "victory") / len(rr)
        mw = sum(1 for _, m in rr if m["win"]) / len(rr)
        rs_ = med([r["secs"] for r, _ in rr])
        ms_ = med([m["secs"] for _, m in rr])
        A("%-13s | %5.0f%% %5.0f%%    | %8.0f %8.0f %+5.0f%%" % (p, rw * 100, mw * 100, rs_, ms_, err(rs_, ms_) or 0))
    rw = sum(1 for r, _ in mres if r["mode"] == "victory") / len(mres)
    mw = sum(1 for _, m in mres if m["win"]) / len(mres)
    A("전체          | %5.0f%% %5.0f%%" % (rw * 100, mw * 100))
    # 서열 비교
    def pw(p):
        rr = [(r, m) for r, m in mres if r["policy"] == p]
        return (sum(1 for r, _ in rr if r["mode"] == "victory") / len(rr), sum(1 for _, m in rr if m["win"]) / len(rr))
    A("")
    A("[표 3] 서열 일치(정책별 승률의 순위 상관 — 모델이 \"어느 정책이 더 센가\"를 맞히는가)")
    xs = [pw(p)[0] for p in pols]
    ys = [pw(p)[1] for p in pols]
    A("  Spearman 순위 상관(실측 승률 vs 모델 승률, 정책 %d개): %s" % (len(pols), "%.2f" % spearman(xs, ys)))
    # 한 마녀별 판 길이
    A("")
    A("[표 4] 마녀별 판 길이 중앙(초), 처치 수, 마신 회수약, 받은 피해(최대 생명 대비 합)")
    for w in ("ember", "frost", "arc"):
        rr = [(r, m) for r, m in mres if r["primary"] == w]
        A("  %-6s 판길이 실측 %.0f 모델 %.0f | 처치 실측 %.0f 모델 %.0f | 회수약 실측 %.1f 모델 %.1f | 받은 피해 실측 %.2f 모델 %.2f" % (
            w, med([r["secs"] for r, _ in rr]), med([m["secs"] for _, m in rr]), med([r["kills"] for r, _ in rr]),
            med([m["kills"] for _, m in rr]), sum(r["potions"] for r, _ in rr) / len(rr), sum(m["potions"] for _, m in rr) / len(rr),
            sum(r["dmg_total"] for r, _ in rr) / len(rr), sum(m["dmg_total"] for _, m in rr) / len(rr)))
    # w0 / 첫 은총 시각
    w0 = load_json(real_dir / "w0" / "rhythm_9.json")
    A("")
    A("[표 5] 은총 시각(초). w0 화염/11 실측: 5.0 12.7 27.8 39.9 58.0 75.0 100.8 132.4 163.1 218.8 347.1")
    pil = [m for r, m in mres if r["policy"] == "pilot" and r["primary"] == "ember" and int(r["seed"]) == 11]
    if pil:
        A("  모델(pilot/ember/11):  " + " ".join("%.1f" % x for x in pil[0]["grace_times"]))
    # w0 마디별 처치/살아있는 적 (9판, 지금 게임 pilot)
    A("")
    A("[표 6] w0 9판(지금 게임 pilot 정책, 화염·냉기·번개 각 시드 11~13) 마디별 중앙값 vs 모델 pilot 15판")
    A("마디 | 처치/분 실측중앙 모델 | 살아있는적 실측중앙 모델")
    mp = [m for r, m in mres if r["policy"] == "pilot"]
    for lab in ["기", "승1", "승2", "전A"]:
        x = w0["cross"][lab]["metrics"]
        mm = model_beat_agg(mp, lab)
        if mm:
            A("%-4s | %8.0f %8.0f %+4.0f%% | %8.1f %8.1f %+4.0f%%" % (lab, x["kpm"]["median"], mm["kpm"], err(x["kpm"]["median"], mm["kpm"]) or 0,
                                                              x["alive_avg"]["median"], mm["alive"], err(x["alive_avg"]["median"], mm["alive"]) or 0))
    # 리듬 켠 3판
    A("")
    A("[표 8] 수호자·우두머리 처치에 든 초(중앙). 실측 w0 9판(pilot) 표지 'champN' -> 'gate'/끝, 모델 pilot 15판")
    rd = real_champ_durations(w0)
    for idx, nm in enumerate(("수호자1", "수호자2", "우두머리")):
        md = [x[2] for m in mp for x in m["single_R"] if x[0] == idx]
        A("  %-7s 실측 %s  모델 %s  (모델 R=%s)" % (nm, ("%.0fs" % med(rd[idx])) if rd[idx] else "-", ("%.0fs" % med(md)) if md else "-",
                                          ("%.2f" % (sum(x[1] for m in mp for x in m["single_R"] if x[0] == idx) / len(md))) if md else "-"))
    A("")
    A("[표 7] 리듬 켠 지금 값(W1b, 화염·냉기·번개 시드 11 한 판씩)과 모델(pilot 정책의 은총 선택 되먹임)")
    on = load_json(real_dir / "w1b" / "rhythm_on_3.json")
    c2 = load_cfg(args, preset="current_on", sets=args.set)
    c2.mode = "legacy"
    A("판   | 실측 길이 처치 | 모델 길이 처치 | 마디(실측 초 / 모델 초)  처치/분(실측 / 모델) 살아있는적(실측 / 모델)")
    pick_src = {r["primary"]: r["picks"] for r, _ in mres if r["policy"] == "pilot" and int(r["seed"]) == 11}
    for r in on["runs"]:
        res = simulate(c2, "pilot", r["primary"], int(r["seed"]), replay=pick_src.get(r["primary"]))
        A("%-5s| %6.0f %5d | %6.0f %5d | %s" % (r["primary"], r["secs"], r["kills"], res["secs"], res["kills"], "승" if res["win"] else "패"))
        labs = {"기": "기", "승1": "승1", "승2": "승2", "전A": "전A", "전B": "전B", "전C": "전C"}
        for b in r["beats"]:
            lb = b["label"]
            mb = res["per"].get(lb)
            if mb and mb["secs"] > 0:
                A("      %-4s %5.0fs / %5.0fs | %5.0f / %5.0f | %5.1f / %5.1f" % (
                    lb, b["secs"], mb["secs"], b["kpm"], mb["kills"] / mb["secs"] * 60, b["alive_avg"], mb["alive"] / mb["secs"]))
    A("")
    A("맞춤 걸린 시간 %.1fs" % (time.time() - t0))
    if big:
        A("오차 30% 넘는 항목: " + ", ".join("%s(%s)" % b for b in big))
    return "\n".join(L), mres


def real_champ_durations(w0):
    out = [[], [], []]
    for r in w0["runs"]:
        m = {}
        for x in r["marks"]:
            sec, name = x.split("s ", 1)
            m[name] = float(sec)
        for idx, (a, b) in enumerate((("champ0", "gate1"), ("champ1", "gate2"))):
            if a in m and b in m:
                out[idx].append(m[b] - m[a])
        if "champ2" in m:
            out[2].append(r["secs"] - m["champ2"])
    return out


def spearman(xs, ys):
    def rank(v):
        order = sorted(range(len(v)), key=lambda i: v[i])
        r = [0.0] * len(v)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
                j += 1
            for k in range(i, j + 1):
                r[order[k]] = (i + j) / 2.0
            i = j + 1
        return r
    rx, ry = rank(xs), rank(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
    return num / den if den else 0.0


FIT_PARAMS = ["r0_hero_m", "eta_aim", "tau_min_s", "hit_rate_per_alive", "hit_dmg_scale", "xp_mult", "cluster", "champ_p_hit", "single_proj_acc", "champ_time_scale", "single_kappa"]


def fit_objective(cfg, real_dir):
    sub = lambda r: r["policy"] in ("pilot", "narrow", "random", "worst") and int(r["seed"]) <= 13
    cfg.mode = "legacy"
    mres = calibrate_data(cfg, real_dir, sub)
    rb = [r["beats"] for r, _ in mres]
    mr = [m for _, m in mres]
    s = 0.0
    n = 0
    for lab in ["기", "승1", "승2", "전A"]:
        a, m = beat_agg(rb, lab), model_beat_agg(mr, lab)
        if a and m:
            for k in ("kpm", "alive", "hpm"):
                if a[k] > 0 and m[k] > 0:
                    s += math.log(m[k] / a[k]) ** 2
                    n += 1
    for r, m in mres:
        pass
    rs_ = med([r["secs"] for r, _ in mres])
    ms_ = med([m["secs"] for _, m in mres])
    s += 2 * math.log(ms_ / rs_) ** 2
    rd = real_champ_durations(load_json(real_dir / "w0" / "rhythm_9.json"))
    for idx in range(3):
        md = [x[2] for _, m in mres if m["policy"] == "pilot" for x in m["single_R"] if x[0] == idx]
        if md and rd[idx]:
            s += 0.5 * math.log(max(med(md), 1) / max(med(rd[idx]), 1)) ** 2
    on = load_json(real_dir / "w1b" / "rhythm_on_3.json")
    c2 = copy.deepcopy(cfg)
    apply_preset(c2, "current_on")
    c2.mode = "legacy"
    pick_src = {r["primary"]: r["picks"] for r, _ in mres if r["policy"] == "pilot" and int(r["seed"]) == 11}
    for r in on["runs"]:
        res = simulate(c2, "pilot", r["primary"], int(r["seed"]), replay=pick_src.get(r["primary"]))
        for b in r["beats"][:4]:
            mb = res["per"].get(b["label"])
            if mb and mb["secs"] > 0 and b["alive_avg"] > 0:
                s += 0.25 * math.log(max(mb["alive"] / mb["secs"], 0.5) / b["alive_avg"]) ** 2
                s += 0.25 * math.log(max(mb["secs"], 1) / b["secs"]) ** 2
    w0 = load_json(real_dir / "w0" / "rhythm_9.json")
    for i in range(1, 9):
        rv = [r["summary"]["grace_times"][i] for r in w0["runs"] if len(r["summary"]["grace_times"]) > i]
        mv = [m["grace_times"][i] for _, m in mres if m["policy"] == "pilot" and len(m["grace_times"]) > i]
        if rv and mv:
            s += 0.5 * math.log(max(med(mv), 1) / max(med(rv), 1)) ** 2
    rd_ = sum(r["dmg_total"] for r, _ in mres) / len(mres)
    md_ = sum(m["dmg_total"] for _, m in mres) / len(mres)
    s += 2 * math.log(max(md_, 0.01) / rd_) ** 2
    rw = sum(1 for r, _ in mres if r["mode"] == "victory") / len(mres)
    mw = sum(1 for _, m in mres if m["win"]) / len(mres)
    s += 4 * (rw - mw) ** 2
    return s


def do_fit(cfg, args):
    real_dir = Path(args.real_dir) if args.real_dir else find_real_dir()
    best = fit_objective(cfg, real_dir)
    print("fit 시작 목적함수 %.3f" % best)
    for p in range(2):
        for k in FIT_PARAMS:
            for f in (0.7, 1.4, 0.88, 1.14):
                old = cfg.cal[k]
                cfg.cal[k] = old * f
                if k == "eta_aim":
                    cfg.cal[k] = min(1.0, cfg.cal[k])
                v = fit_objective(cfg, real_dir)
                if v < best - 1e-6:
                    best = v
                    print("  %s -> %.4g  (%.3f)" % (k, cfg.cal[k], v))
                else:
                    cfg.cal[k] = old
    print("fit 끝 목적함수 %.3f" % best)
    print(json.dumps({k: round(cfg.cal[k], 5) for k in FIT_PARAMS}, ensure_ascii=False))


# ---- 훑기 ------------------------------------------------------------------
def do_sweep(args, policies, witches, seeds):
    spec = args.sweep
    key, vals = spec.split("=", 1)
    vs = [parse_val(v) for v in vals.split(",")]
    rows = []
    cls_pol = [p for p in policies]
    print("훑기 %s : %s   (마녀 %s, 시드 %d, 정책 %d)" % (key, vs, ",".join(witches), len(seeds), len(cls_pol)))
    print("%-10s | %s | synergy−narrow | 서열 | 정체판 | synergy 길 최저" % ("값", " | ".join("%-9s" % c for c in ("synergy", "narrow", "narrow_ring", "random", "spread", "worst"))))
    out = []
    for v in vs:
        cfg = load_cfg(args, sets=list(args.set or []) + ["%s=%s" % (key, json.dumps(v))], preset=args.preset)
        mx = run_matrix(cfg, cls_pol, witches, seeds)
        row = {}
        for cl in ("synergy", "narrow", "narrow_ring", "random", "spread", "worst"):
            xs = [win_rate(rs) for (p, w), rs in mx.items() if policy_class(p) == cl]
            row[cl] = sum(xs) / len(xs) if xs else None
        ok, _ = verdict_order(mx, witches)
        st = sum(1 for rs in mx.values() for r in rs if r["stall"])
        syn = [win_rate(rs) for (p, w), rs in mx.items() if policy_class(p) == "synergy"]
        gap = (row["synergy"] - row["narrow"]) * 100 if row["synergy"] is not None and row["narrow"] is not None else None
        print("%-10s | %s | %+8.0f%%p | %s | %6d | %s" % (
            str(v), " | ".join("%-9s" % fmt_pct(row[c]) for c in ("synergy", "narrow", "narrow_ring", "random", "spread", "worst")),
            gap if gap is not None else 0, "성립" if ok else "깨짐", st, fmt_pct(min(syn) if syn else None)))
        out.append({"value": v, "win": row, "order_ok": ok, "stalls": st, "gap_pp": gap})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="균형 시뮬레이터 (모델의 답이지 게임의 답이 아니다)")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--fit", action="store_true")
    ap.add_argument("--preset", default=None, help="spec1 | spec1p(압력·격앙 포함) | current_on")
    ap.add_argument("--skills", default=None, choices=["s", "legacy"])
    ap.add_argument("--spells", default=None)
    ap.add_argument("--set", action="append", default=[])
    ap.add_argument("--sweep", default=None)
    ap.add_argument("--policies", default=None)
    ap.add_argument("--witches", default="ember,frost,arc")
    ap.add_argument("--seeds", type=int, default=10)
    ap.add_argument("--seed0", type=int, default=11)
    ap.add_argument("--dt", type=float, default=1.0)
    ap.add_argument("--gear", default=None)
    ap.add_argument("--real-dir", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--trace", default=None, help="정책:마녀:시드 — 한 판의 초별 흔적 출력")
    args = ap.parse_args(argv)
    t0 = time.time()
    if args.calibrate or args.fit:
        cfg = load_cfg(args, sets=args.set, preset="current")
        if args.fit:
            do_fit(cfg, args)
        else:
            txt, mres = calib_table(cfg, args)
            print(txt)
            if args.out:
                Path(args.out).parent.mkdir(parents=True, exist_ok=True)
                Path(args.out).write_text(txt + "\n", encoding="utf-8", newline="\n")
        return 0
    cfg = load_cfg(args, sets=args.set, preset=args.preset)
    witches = args.witches.split(",")
    seeds = list(range(args.seed0, args.seed0 + args.seeds))
    pols = args.policies.split(",") if args.policies else default_policies(cfg.mode)
    if args.trace:
        p, w, s = args.trace.split(":")[0:1] + args.trace.split(":")[-2:]
        pol_name = ":".join(args.trace.split(":")[:-2])
        r = simulate(cfg, pol_name, w, int(s), trace=True)
        for row in r["trace"][::5]:
            print(row)
        print({k: v for k, v in r.items() if k not in ("trace", "per")})
        return 0
    if args.sweep:
        out = do_sweep(args, pols, witches, seeds)
        print("걸린 시간 %.1fs" % (time.time() - t0))
        return 0
    mx = run_matrix(cfg, pols, witches, seeds)
    txt = report(cfg, mx, pols, witches, seeds, label=args.preset or "")
    print(txt)
    print("걸린 시간 %.1fs (%d판)" % (time.time() - t0, sum(len(v) for v in mx.values())))
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps({"preset": args.preset, "mode": cfg.mode, "set": args.set, "results": summarize_for_json(mx)},
                                             ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
        Path(args.out).with_suffix(".txt").write_text(txt + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
