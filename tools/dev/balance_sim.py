#!/usr/bin/env python3
"""균형 시뮬레이터 (2차판) — 코어를 돌리지 않고 스킬 구성의 힘과 적의 위협을 흐름 모델로 맞물려 본다.

2차 추가: --jobs(판 병렬), 승률 옆 표본 오차(95% 윌슨 구간), --gear kit.*(장비 층, P10), --calibrate2(builds2 실측 장비 없음/켬 두 조건),
--fit2 [--write-calib], --sensitivity, 탐색은 tools/dev/balance_search.py. 같은 인수면 같은 답(시드 고정, 병렬이어도 판마다 독립 시드).

이 도구의 답은 모델의 답이지 게임의 답이 아니다. 서열("어느 정책이 더 센가")과 값을 바꿨을 때의 방향을 보는 데 쓰고,
정확한 승률·시각은 실제 코어(sim_builds.gd, measure_rhythm.gd)로 마지막에 확인한다. 재미는 평가하지 않는다.

예시(저장소 루트에서, Python 3.10, 표준 라이브러리만):
  1) python tools/dev/balance_sim.py --calibrate                       # 지금 게임의 실측과 모델의 오차 표
  2) python tools/dev/balance_sim.py --preset spec1p --seeds 10 --out _local/balsim/first.json   # 명세 첫 값, 정책 전부 x 마녀 셋
  3) python tools/dev/balance_sim.py --preset spec1p --set rhythm.beats[2].amount=6 --set spells.ember_ring.base.ring_radius_cm=450
  4) python tools/dev/balance_sim.py --preset spec1p --sweep rhythm.beats[2].amount=5,6,7,8 --seeds 6
  5) python tools/dev/balance_sim.py --fit                             # 자유 상수를 실측에 맞춰 보기(결과 출력만, 파일은 안 고침)

팩터 확장(스킬 정의에 범위·갯수·공격력·추가 피해·군중 제어·치명타·흡수·표식 등을 적어 본다. 표는 FACTORS, 키 목록은 --describe):
  6) python tools/dev/balance_sim.py --describe --spells tools/dev/balance_sim_spells_lab.json --out _local/balsim2/describe.json   # 바꿔 볼 수 있는 키(JSON)
  7) python tools/dev/balance_sim.py --preset spec1p --spells tools/dev/balance_sim_spells_lab.json --policies kit:b_crit_mark,kit:c_freeze_nova,narrow,random --seeds 50
  8) python tools/dev/balance_sim.py --preset spec1p --set spells.ember.crit_bps=3000 --set spells.frost.cc.freeze_s=1.0 --policies synergy,narrow --seeds 40
  9) python tools/dev/balance_sim.py --preset spec1p --gear crit=0.1,range=1.2,count=1 --policies narrow --seeds 40     # 장비 팩터. 묶음은 --gear kit.d1_end+tree.lv20
 10) python tools/dev/balance_search.py --approach --spells tools/dev/balance_sim_spells_lab.json --init _local/balsim2/s1A.json   # 접근 (가)(나)(다)(섞음) 견주기
 11) python tools/dev/balance_sim.py --calibrate2 | --fit2 [--write-calib]     # 실측 builds2에 다시 맞춤(--fit2는 기본으로 파일을 안 고침)
 12) python tools/dev/balance_search.py --sensitivity | --shake | --stage power|threat --out ...   # 민감도 / 가설 상수 흔들기 / 값 탐색
새 팩터는 기본값이면 효과가 없다(1차판과 같은 결과, test_balance_sim.py가 지킴).

키 접두사: rhythm./enemies./spawn./... = combat_tuning.json, spells. = 주문 데이터(run_spells.json 또는 초안), calib. = balance_sim_calib.json의 값.
주문 id는 chapter1.skill.을 떼고 쓴다(spells.ember_ring.base.ring_radius_cm).
"""
import argparse, copy, hashlib, json, math, multiprocessing, os, random, re, sys, time, zlib
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
    # 고치는 문서(주문·튜닝·calib)는 복사본을 준다. 주문 묶음 파일은 이름에 spells가 들어 있으면 전부 복사(--spells로 고른 시험 묶음이 캐시에서 오염되지 않게)
    if key.endswith(("combat_tuning.json", "run_spells.json", "draft.json", "calib.json", "growth_quality37.json")) or "spells" in Path(key).name:
        return copy.deepcopy(_JSON_CACHE[key])
    return _JSON_CACHE[key]


def _tok(path):
    """점 경로. 배열 색인은 [2], 점이 든 키는 ["react.steam"]처럼 따옴표로 쓴다."""
    out = []
    for q, t in re.findall(r'\["([^"]+)"\]|([^.\[\]]+)', path):
        out.append(q if q else (int(t) if t.isdigit() else t))
    return out


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
    c.gear = parse_gear(gear, c.cal)
    pre = preset or getattr(args, "preset", None)
    c.spec = {"preset": pre, "skills": getattr(args, "skills", None), "spells": getattr(args, "spells", None), "gear": gear,
              "dt": c.dt, "sets": list(sets or []), "mode": None}
    if pre:
        apply_preset(c, pre)
    for s in (sets or []):
        k, v = s.split("=", 1)
        apply_set(c, k.strip(), parse_val(v))
    c.gear = parse_gear(gear, c.cal)
    c.spells_sha = hashlib.sha1(json.dumps(c.spells, sort_keys=True).encode("utf-8")).hexdigest()[:8]
    return c


def set_mode(cfg, mode):
    cfg.mode = mode
    cfg.spec["mode"] = mode


def cfg_from_spec(spec):
    a = argparse.Namespace(spells=spec.get("spells"), skills=spec.get("skills"), dt=spec.get("dt", 1.0), gear=spec.get("gear"),
                           preset=spec.get("preset"), real_dir=None, set=[])
    c = load_cfg(a, sets=spec.get("sets"), preset=spec.get("preset"))
    if spec.get("mode"):
        set_mode(c, spec["mode"])
    return c


def derive(cfg, sets=(), gear=None, mode=None):
    """cfg의 사본에 --set 묶음을 더해 새 cfg를 만든다(spec에서 다시 읽어 병렬에도 쓸 수 있다)."""
    sp = copy.deepcopy(cfg.spec)
    sp["sets"] = list(sp["sets"]) + list(sets)
    if gear is not None:
        sp["gear"] = gear
    if mode:
        sp["mode"] = mode
    return cfg_from_spec(sp)


# ---- 병렬 실행 --------------------------------------------------------------
JOBS = 1
_POOL = None
_WCFG = {}


def set_jobs(n):
    global JOBS
    JOBS = max(1, int(n))


def default_jobs():
    return max(1, min(14, (os.cpu_count() or 2) - 2))


def _get_pool():
    global _POOL
    if _POOL is None:
        _POOL = multiprocessing.Pool(JOBS)
    return _POOL


def close_pool():
    global _POOL
    if _POOL is not None:
        _POOL.close()
        _POOL.join()
        _POOL = None


def _run_task(t):
    spec_json, pol, w, seed, replay = t
    c = _WCFG.get(spec_json)
    if c is None:
        if len(_WCFG) > 6:
            _WCFG.clear()
        c = _WCFG[spec_json] = cfg_from_spec(json.loads(spec_json))
    return simulate(c, pol, w, seed, replay=replay)


def run_many(cfg, tasks):
    """tasks = [(정책, 마녀, 시드, replay 또는 None)] -> 결과 목록(같은 순서). 병렬이어도 판마다 시드가 독립이라 결과가 같다."""
    if JOBS <= 1 or len(tasks) < 60 or not getattr(cfg, "spec", None):
        return [simulate(cfg, p, w, s, replay=rp) for p, w, s, rp in tasks]
    spec_json = json.dumps(cfg.spec, sort_keys=True, ensure_ascii=False)
    items = [(spec_json, p, w, s, rp) for p, w, s, rp in tasks]
    return _get_pool().map(_run_task, items, chunksize=max(1, len(items) // (JOBS * 4)))


def wilson(k, n, z=1.96):
    """승률의 95% 윌슨 구간의 반폭(%p 아님, 0~1)과 중심."""
    if n <= 0:
        return 0.0, 0.0, 0.0
    p = k / n
    d = 1 + z * z / n
    ctr = (p + z * z / (2 * n)) / d
    hw = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return p, max(0.0, ctr - hw), min(1.0, ctr + hw)


def apply_set(c, key, val):
    head, _, rest = key.partition(".")
    if head == "calib":
        if rest not in c.cal:
            raise KeyError("calib 키가 없다: " + rest)
        c.cal[rest] = val
    elif head == "spells":
        root = c.spells if (not rest or _tok(rest)[0] in c.spells) else c.spells["spells"]
        try:
            set_path(root, rest, val)
        except KeyError:
            # 새 팩터는 주문에 처음 적을 때 키가 없다: 알려진 팩터 이름만 새로 만든다
            toks = _tok(rest)
            groups = ("extra", "dot", "on_kill", "cc", "vuln", "utility", "zone", "summon")
            leafs = ("crit_bps", "crit_dmg_bps", "shape", "evolve_free", "vs_strong_bps", "range_cm", "width_cm")
            if root is c.spells or not (toks[1] in groups or toks[-1] in leafs or (toks[1] in ("base",) and (toks[2] in groups or toks[-1] in leafs))):
                raise
            cur = root
            for t in toks[:-1]:
                t = _walk_alias(cur, t)
                cur = cur.setdefault(t, {})
            cur[toks[-1]] = val
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


# 장비 층(P10): 묶음마다 (힘 증가 p, 버팀 증가 s). dmg=1+p, 최대 생명 x sqrt(1+s), 받는 피해 x 1/sqrt(1+s) -> 버팀 S는 정확히 (1+s)배.
# 값은 P10 표 가운데 값(가설). kit.now(지금 장비가 덮는 몫)는 실측 sim-equip에 맞춘 값(calib.gear_now_p / gear_now_s).
GEAR_KITS = {
    "kit.none": (0.0, 0.0),
    "kit.d1_start": (0.225, 0.30),
    "kit.d1_end": (0.55, 0.55),
    "kit.d2_mid": (1.05, 0.80),
    "tree.lv20": (0.35, 0.175),
}


def _kit_pair(name, cal=None):
    if name == "kit.now":
        cal = cal or {}
        return (cal.get("gear_now_p", 0.5), cal.get("gear_now_s", 0.5))
    if name in GEAR_KITS:
        return GEAR_KITS[name]
    raise SystemExit("알 수 없는 장비 묶음: " + name + " (kit.none|kit.now|kit.d1_start|kit.d1_end|kit.d2_mid|tree.lv20, +로 묶음, 또는 dmg=1.2,hp=1.1,dr=0.9)")


def parse_gear(g, cal=None):
    out = {"dmg": 1.0, "hp": 1.0, "dr": 1.0}
    if not g:
        return out
    if re.fullmatch(r"[0-9.]+", g):
        x = float(g)
        out.update(dmg=x, hp=1 + 0.5 * (x - 1))
        return out
    if g.startswith(("kit.", "tree.")):
        p, s = 0.0, 0.0
        P, S = 1.0, 1.0
        for nm in g.split("+"):
            pp, ss = _kit_pair(nm.strip(), cal)
            P *= 1 + pp
            S *= 1 + ss
        out.update(dmg=P, hp=math.sqrt(S), dr=1 / math.sqrt(S))
        return out
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
    # ---- 확장 팩터(전부 선택 필드, 없으면 효과 없음). 표는 balance_sim.py 머리 주석의 FACTORS와 REPORT 참조
    shape = d.get("shape") or b.get("shape")
    if shape:
        st["kind"] = shape  # proj | chain | ring | line | zone | summon
    st["rng"] = b.get("range_cm", 0) / 100.0
    st["wid"] = b.get("width_cm", 0) / 100.0
    st["zone"] = dict(b.get("zone", {}))
    st["summon"] = dict(b.get("summon", {}))
    st["crit"] = (d.get("crit_bps", 0) + b.get("crit_bps", 0)) / 1e4
    st["critm"] = d.get("crit_dmg_bps", 15000) / 1e4
    st["ex"] = dict(d.get("extra", {}))
    st["dot"] = dict(d.get("dot", {}))
    st["onkill"] = dict(d.get("on_kill", {}))
    st["cc"] = dict(d.get("cc", {}))
    st["vuln"] = dict(d.get("vuln", {}))
    st["util"] = dict(d.get("utility", {}))
    if sp.evolved:
        cal = cfg.cal
        st["dmg"] *= cal.get("evolve_damage_mul_" + d["element"], cal["evolve_damage_mul"])
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
            g = c.gear
            for e in self._eff:
                for k, v in (("rng", 0.0), ("wid", 0.0), ("crit", 0.0), ("critm", 1.5)):
                    e.setdefault(k, v)
                for k in ("zone", "summon", "ex", "dot", "onkill", "cc", "vuln", "util"):
                    e.setdefault(k, {})
                if g["dmg"] != 1.0:
                    e["dmg"] *= g["dmg"]
                if g.get("cd", 1.0) != 1.0:
                    e["cd"] *= g["cd"]
                if g.get("crit", 0.0):
                    e["crit"] += g["crit"]
                if g.get("critdmg", 0.0):
                    e["critm"] += g["critdmg"]
                rm = g.get("range", 1.0)
                if rm != 1.0:
                    for k in ("r", "R", "rng", "wid"):
                        e[k] = e[k] * rm
                    if e["zone"]:
                        e["zone"]["radius_cm"] = e["zone"].get("radius_cm", 0) * rm
                if g.get("count", 0):
                    n = int(g["count"])
                    if e["kind"] in ("proj", "line"):
                        e["k"] += n
                    elif e["kind"] == "chain":
                        e["chain"] += n
                    elif e["kind"] == "ring" and e["rt"]:
                        e["rt"] += n
                    elif e["kind"] == "summon" and e["summon"]:
                        e["summon"]["count"] = e["summon"].get("count", 1) + n
                if g.get("pierce", 0):
                    e["pierce"] += int(g["pierce"])
                if g.get("extra", 0.0):
                    e["ex"]["elem_bps"] = e["ex"].get("elem_bps", 0) + g["extra"] * 1e4
                if g.get("dot", 1.0) != 1.0 and e["dot"]:
                    e["dot"]["dps_bps"] = e["dot"].get("dps_bps", 0) * g["dot"]
                if g.get("cc", 1.0) != 1.0 and e["cc"]:
                    for k in ("slow_s", "freeze_s", "stun_s", "root_s", "knock_cm", "pull_cm"):
                        if k in e["cc"]:
                            e["cc"][k] *= g["cc"]
                if g.get("vuln", 0.0) and e["vuln"]:
                    e["vuln"]["bps"] = e["vuln"].get("bps", 0) + g["vuln"] * 1e4
        return self._eff

    def util(self):
        """판 안 방어·회복 팩터 합(주문의 utility 필드 + 장비)."""
        u = {"lifesteal": 0.0, "heal_on_kill": 0.0, "shield_per_s": 0.0, "dr": 0.0, "move": 0.0, "cd_refund": 0.0}
        for e in self.eff():
            x = e.get("util") or {}
            u["lifesteal"] += x.get("lifesteal_bps", 0) / 1e4
            u["heal_on_kill"] += x.get("heal_on_kill", 0)
            u["shield_per_s"] += x.get("shield_per_s", 0)
            u["dr"] += x.get("dr_bps", 0) / 1e4
            u["move"] += x.get("move_bps", 0) / 1e4
            u["cd_refund"] += x.get("cd_refund_bps", 0) / 1e4
        g = self.cfg.gear
        u["lifesteal"] += g.get("lifesteal", 0.0)
        u["heal_on_kill"] += g.get("heal_kill", 0.0)
        u["dr"] += g.get("dr_add", 0.0)
        u["move"] += g.get("move", 0.0)
        u["cd_refund"] += g.get("cd_refund", 0.0)
        return u

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
def ring_inside(c, N, R):
    """반경 R 원형 안에 있는 적 수의 기대값. 척도 r0는 밀도에 따라 커진다(시험장 실측: 9~14m, calib r0_hero_m + r0_per_alive*N)."""
    r0 = c["r0_hero_m"] + c.get("r0_per_alive", 0.0) * N
    return N * (1 - math.exp(-(R / r0) ** 2))


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
    if kind in ("line", "zone", "summon"):
        rho = c["cluster"] * N / (math.pi * c["field_r_m"] ** 2)
        if kind == "line":  # 관통 선: 발수 x (관통 + 선 면적 안의 적)
            phi = min(0.9, c["phi_base"] + c["phi_per_alive"] * N)
            n = st["k"] * (1 + st["pierce"] * phi + rho * st["wid"] * st["rng"])
            n = max(1.0, min(n, st["budget"] if st["budget"] > 1 else n, N))
            return min(1.0, N) / st["cd"] * n
        if kind == "zone":  # 장판: 한 번 깔면 duration 동안 tick마다 안의 적 모두
            z = st["zone"]
            rad = z.get("radius_cm", 150) / 100.0
            zones = max(1.0, z.get("duration_s", 4.0) / st["cd"]) * z.get("count", 1)
            tick = max(1, z.get("tick_ticks", 30)) / 60.0
            mm = min(max(st["budget"], 1), 1 + rho * math.pi * rad * rad)
            return min(1.0, N) * zones * mm / tick
        s = st["summon"]  # 소환·포탑: 지속 동안 마리마다 attack_ticks마다 한 번(조준 없음)
        up = min(1.0, s.get("duration_s", 8.0) / st["cd"])
        mm = 1 + rho * math.pi * st["r"] ** 2
        return min(1.0, N) * s.get("count", 1) * up / (max(1, s.get("attack_ticks", 60)) / 60.0) * mm
    m = ring_inside(c, N, st["R"])
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
        fac = [1.0] * len(effs)  # 확장 팩터(치명타·추가 피해·지속 피해·표식)의 피해 배율
        extra = []  # (hits/s, dmg per hit)
        det_dmg = 0.0
        self.last_cc = {"contact": 1.0, "dens": 0.0, "strong": 1.0, "cov": 0.0}
        self.last_crit = (0.0, 1.5)
        if cfg.mode == "s" and N > 0:
            self.last_cc = self._cc(effs, H, N)
            ut = build.util()
            for i, st in enumerate(effs):
                if st["kind"] == "ring" and self.last_cc["dens"] > 0:
                    H[i] *= 1 + self.last_cc["dens"]
                if ut["cd_refund"] > 0:
                    H[i] *= min(2.0, 1 + ut["cd_refund"] * self.kill_rate * st["cd"])
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
                            mR = ring_inside(c, N, st["R"])
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
                if pr["kind"] != "reaction" or c.get("reactions_on", 1.0) <= 0:
                    continue  # 코어는 원소 반응 짝에 효과를 내지 않는다(시험장 실측 0%). calib.reactions_on=1로 켜 볼 수 있다
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
            # ---- 확장 팩터
            stk = {}
            for (sn, src), r in rate.items():
                stk[sn] = stk.get(sn, 0.0) + r * stat[sn]["expire_ticks"] / 60.0
            vul_add = 0.0
            for st, h in zip(effs, H):
                v = st["vuln"]
                if v:
                    rt_ = h * v.get("chance_bps", 10000) / 1e4 / max(N, 1.0)
                    vul_add += v.get("bps", 0) / 1e4 * (1 - math.exp(-rt_ * v.get("secs", 4.0)))
            vul = 1 + min(1.5, vul_add)
            rho = c["cluster"] * N / (math.pi * c["field_r_m"] ** 2)
            for i, st in enumerate(effs):
                f = 1.0
                ex_ = st["ex"]
                if ex_:
                    f += ex_.get("elem_bps", 0) / 1e4
                    vs = ex_.get("vs_status")
                    if vs:
                        f += vs.get("bps", 0) / 1e4 * (1 - math.exp(-min(stat[vs["status"]]["max"], stk.get(vs["status"], 0.0))))
                    f += ex_.get("vs_low_hp_bps", 0) / 1e4 * c["p_low_hp"]
                    f += ex_.get("vs_near_bps", 0) / 1e4 * c["p_near"] + ex_.get("vs_far_bps", 0) / 1e4 * (1 - c["p_near"])
                    f += ex_.get("vs_cc_bps", 0) / 1e4 * self.last_cc["cov"]
                dt_ = st["dot"]
                if dt_:
                    f += dt_.get("dps_bps", 0) / 1e4 * min(dt_.get("secs", 0.0), c["dot_cap_s"]) * c["dot_eff"]
                f *= vul
                if st["crit"] > 0:
                    f *= 1 + min(1.0, st["crit"]) * (st["critm"] - 1)
                fac[i] = f
                ok_ = st["onkill"]
                if ok_ and ok_.get("dmg_bps", 10000) > 0 and H[i] > 0:
                    htk = max(1.0, math.ceil(c["ref_enemy_hp"] / max(st["dmg"] * f, 1e-6)))
                    nb = min(ok_.get("budget", 6), 1 + rho * math.pi * (ok_.get("radius_cm", 150) / 100.0) ** 2)
                    extra.append((H[i] / htk * nb, st["dmg"] * ok_.get("dmg_bps", 10000) / 1e4))
            wsum = sum(h * st["dmg"] * f for st, h, f in zip(effs, H, fac))
            if wsum > 0:
                pc = sum(h * st["dmg"] * f * min(1.0, st["crit"]) for st, h, f in zip(effs, H, fac)) / wsum
                mc = sum(h * st["dmg"] * f * min(1.0, st["crit"]) * st["critm"] for st, h, f in zip(effs, H, fac)) / max(wsum * pc, 1e-9) if pc > 0 else 1.5
                self.last_crit = (pc, mc)
        tot_h = 0.0
        tot_dmg = 0.0
        mkf = self._mark_factor(build, effs, H, N) if (cfg.mode == "s" and N > 0) else 1.0
        for st, h, m, f in zip(effs, H, mult, fac):
            tot_h += h
            tot_dmg += h * st["dmg"] * m * f * (mkf if st["id"] == build.primary else 1.0)
            det_dmg += h * st["dmg"] * (m - 1) * f
        for h, d in extra:
            tot_h += h
            tot_dmg += h * d
            det_dmg += h * d
        dbar = tot_dmg / tot_h if tot_h > 0 else 0.0
        return tot_h, dbar, tot_dmg, det_dmg

    kill_rate = 0.0
    last_strong_keep = 1.0

    def _mark_factor(self, build, effs, H, N):
        """표식 공명(코어 규칙, tuning.marks): 주력 명중이 표식 낀 적을 맞히면 표식 하나당 mark_bps 더. 표식은 다른 주문이 명중한 적에게 mark_ticks 동안 붙는다.
        calib.mark_eff가 0이면(없으면) 꺼짐. 무리에서는 표식 낀 적의 몫이 작다(시험장 실측: 보조 피해 0~6%)."""
        c = self.c
        eff = c.get("mark_eff", 0.0)
        if eff <= 0:
            return 1.0
        mk = self.cfg.tuning.get("marks", {})
        bps, secs = mk.get("mark_bps", 0) / 1e4, mk.get("mark_ticks", 0) / 60.0
        if bps <= 0:
            return 1.0
        p = sum(1 - math.exp(-h * secs / max(N, 1.0)) for st, h in zip(effs, H) if st["id"] != build.primary)
        return 1 + eff * bps * min(p, 2.0)

    def _cc(self, effs, H, N):
        """군중 제어가 위협 쪽에 주는 효과. contact: 접촉 피해 배율(0.15~1), dens: 끌어당김으로 원형 명중 가산,
        strong: 강한 적의 공격이 맞을 배율(지속은 cc_strong_mult로 줄어듦), cov: 제어 중인 적의 몫."""
        c = self.c
        hard_keep, slow_cov, pull = 1.0, 0.0, 0.0
        s_keep = 1.0
        for st, h in zip(effs, H):
            cc = st["cc"]
            if not cc:
                continue
            ch = cc.get("chance_bps", 10000) / 1e4
            rate = h * ch / max(N, 1.0)
            hd = cc.get("freeze_s", 0) + cc.get("stun_s", 0) + cc.get("root_s", 0) + cc.get("knock_cm", 0) / 100.0 / c["enemy_speed_m"]
            if hd > 0:
                hard_keep *= math.exp(-rate * hd)
                s_keep *= 1 - min(1.0, ch / max(st["cd"], 0.1) * hd * c["cc_strong_mult"])
            if cc.get("slow_s", 0) > 0 and cc.get("slow_bps", 0) > 0:
                slow_cov += (1 - math.exp(-rate * cc["slow_s"])) * cc["slow_bps"] / 1e4
                s_keep *= 1 - min(1.0, ch / max(st["cd"], 0.1) * cc["slow_s"] * c["cc_strong_mult"]) * cc["slow_bps"] / 1e4 * 0.5
            if cc.get("pull_cm", 0) > 0:
                pull += (1 - math.exp(-rate)) * cc["pull_cm"] / 100.0 / c["field_r_m"]
        slow_cov = min(0.7, slow_cov)
        return {"contact": max(0.15, hard_keep * (1 - slow_cov)), "dens": min(0.5, pull), "strong": max(0.2, s_keep),
                "cov": min(1.0, (1 - hard_keep) + slow_cov)}

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
        self.last_strong_keep = 1.0
        if self.cfg.mode == "s":
            self.last_strong_keep = self._cc(effs, self.hits_table(build, N)[1], max(N, 1.0))["strong"]
        for st in effs:
            for sn in st["applies"]:
                has_applier.setdefault(sn, set()).add(st["id"])
        for st in effs:
            base = st["dmg"] / st["cd"]
            if st["kind"] == "proj":
                v = base * st["k"] * c["single_proj_acc"] * s * (1 + (c["single_splash"] if st["r"] > 0 else 0.0))
            elif st["kind"] == "chain":
                v = base * min(1.0, st["chain"] * st["branches"] / (1.0 + N)) if N > 0 else base
            elif st["kind"] == "line":
                v = base * st["k"] * c["single_proj_acc"] * s
            elif st["kind"] == "zone":
                z = st["zone"]
                zones = max(1.0, z.get("duration_s", 4.0) / st["cd"]) * z.get("count", 1)
                v = st["dmg"] * zones * 60.0 / max(1, z.get("tick_ticks", 30)) * 0.8
            elif st["kind"] == "summon":
                sm = st["summon"]
                up = min(1.0, sm.get("duration_s", 8.0) / st["cd"])
                v = st["dmg"] * sm.get("count", 1) * up * 60.0 / max(1, sm.get("attack_ticks", 60)) * 0.7 * (1.0 / (1.0 + 0.5 * c["single_kappa"] * N))
            else:
                if "ring_in_r0" in c:  # 시험장 실측: 정예와의 거리 분포에 맞춘 선형 오름(r0 이하 0, r0+span 이상 1)
                    pin = min(1.0, max(0.0, (st["R"] - c["ring_in_r0"]) / max(c["ring_in_span"], 0.1)))
                else:
                    pin = min(1.0, st["R"] / c["ring_in_r_m"])
                v = base * st["vs"] * pin * st["pulses"]
            m = 1.0
            if self.cfg.mode == "s":
                ex_ = st.get("ex") or {}
                f = 1.0 + ex_.get("elem_bps", 0) / 1e4 + ex_.get("vs_strong_bps", 0) / 1e4 + ex_.get("vs_cc_bps", 0) / 1e4 * (1 - self.last_strong_keep)
                f += ex_.get("vs_near_bps", 0) / 1e4 * 0.5
                if st.get("dot"):
                    f += st["dot"].get("dps_bps", 0) / 1e4 * min(st["dot"].get("secs", 0.0), c["dot_cap_s"] * 2) * 0.9
                if st.get("crit", 0) > 0:
                    f *= 1 + min(1.0, st["crit"]) * (st["critm"] - 1)
                m *= f
                if st["id"] == build.primary and c.get("mark_eff", 0.0) > 0:  # 표식 공명: 곁의 다른 주문이 정예에 건 표식(조준 몫 s로 줄어든다)
                    nsec = sum(1 for e3 in effs if e3["id"] != build.primary and e3["kind"] != "ring")  # 맞춤은 대여 기본기 빌드(원형 없음)로 했다
                    m *= 1 + c["mark_eff"] * self.cfg.tuning.get("marks", {}).get("mark_bps", 0) / 1e4 * min(2, nsec) * c.get("p_mark_single", 0.0) * s
                vul = 0.0
                for e2 in effs:
                    if e2.get("vuln"):
                        vul += e2["vuln"].get("bps", 0) / 1e4 * min(1.0, e2["vuln"].get("secs", 4.0) / e2["cd"]) * c["p_status_single"]
                m *= 1 + min(1.5, vul)
                mm = 1.0
                for sn, dd in st["det"].items():
                    if any(x != st["id"] for x in has_applier.get(sn, ())):
                        bonus = dd.get("bonus_bps", dd.get("per_stack_bps", 0) * 2) / 1e4
                        mm = max(mm, 1 + bonus * c["p_status_single"])
                m *= mm
                tot += v * m * c["eta_aim"]
                continue
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
    if not ev.get("needs_partner", True) or cfg.spells["spells"][sid].get("evolve_free"):
        return True  # 시험 묶음의 주문은 evolve_free(짝 없이 진화)로 적을 수 있다
    p, ps = partner_of(cfg, build, sid)
    return p is not None and ps >= ev["partner_axis_sum"]


def unlockable(cfg, build, witch):
    out = []
    if len(build.sp) >= cfg.spells["slots"]:
        return out
    for k, d in cfg.spells["spells"].items():
        if k in build.sp:
            continue
        if "owner" in d:
            if d["owner"] != "chapter1.character." + witch:
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
        if k == "kit":
            return self.kit(build, offer, level)
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

    def kit(self, build, offer, level):
        """시험 묶음의 kits[이름] = 주문 id 목록($basic = 그 마녀의 기본기, $ring = 그 마녀의 원형). 열기 -> 축 점수를 번갈아(첫째 5, 나머지 3) -> 진화 -> 결정 -> 생존."""
        cfg = self.cfg
        tok = {"$basic": basic_id(self.witch), "$ring": ring_id(self.witch)}
        members = [tok.get(m) or (SK + m if not m.startswith(SK) else m) for m in cfg.spells["kits"][self.role]]
        for m in members:
            if m not in build.sp:
                for c in offer:
                    if c[0] == "unlock" and c[1] == m:
                        return c
        have = [m for m in members if m in build.sp]
        thr = {m: (5 if i == 0 else 3) for i, m in enumerate(members)}
        need = [m for m in have if build.axis_sum(m) < thr[m]]
        ax = [c for c in offer if c[0] == "axis" and c[1] in need]
        if ax:
            return min(ax, key=lambda c: (build.axis_sum(c[1]) / thr[c[1]], build.sp[c[1]].dmg if c[2] == "damage" else build.sp[c[1]].reach))
        for c in offer:
            if c[0] == "evolve" and c[1] in have:
                return c
        for c in offer:
            if c[0] == "passive" and c[1] in {cfg.spells["spells"][m]["element"] for m in have}:
                return c
        for c in offer:
            if c[0] == "axis" and c[1] in have:
                return c
        for c in offer:
            if c[0] == "survival":
                return c
        return self.best(build, offer, level)

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
        cc_now, crit_now = pw.last_cc, pw.last_crit
        utl = build.util() if cfg.mode == "s" else None
        dens = luck / (1.0 + c.get("eta_dense", 0.0) * N / 100.0)  # 포위당할수록 자동 조작이 덜 맞힌다(맞춤으로 정함)
        tot_h *= dens
        tot_dmg *= dens
        det_dmg *= dens
        if tot_h > 0 and dbar > 0:
            pc_, mc_ = crit_now
            if pc_ > 0:  # 치명타는 처치당 명중 수의 계단을 바꾼다: 치명이면 d*mc, 아니면 d0
                d0 = dbar / (1 + pc_ * (mc_ - 1))
                htk = sum(w * ((1 - pc_) * max(1.0, math.ceil(h / d0 - 1e-9)) + pc_ * max(1.0, math.ceil(h / (d0 * mc_) - 1e-9))) for w, h in hl)
            else:
                htk = sum(w * max(1.0, math.ceil(h / dbar - 1e-9)) for w, h in hl)
            kill_cap = tot_h / htk * dt
        else:
            kill_cap = 0.0
        eff_n = N + 0.5 * spawn
        kill = min(kill_cap, eff_n * (1 - math.exp(-dt / c["tau_min_s"])))
        N_before = N
        N = max(0.0, N - kill)
        kills_total += kill
        pw.kill_rate = kill / dt
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
        hits = c["hit_rate_per_alive"] * 50.0 * (N / 50.0) ** c.get("hit_alive_exp", 1.0) * dt * noise
        mult = 1.0
        if pres_on:
            mult += pressure * pres_cfg["contact_per_point_bps"] / 1e4
        gmul = (1 - 0.08 * build.guard) * cfg.gear.get("dr", 1.0)
        shield_abs = 0.0
        heal_now = 0.0
        if utl is not None:
            gmul *= 1 - min(0.8, utl["dr"])
            hits /= 1 + 0.5 * min(1.0, utl["move"])  # 이동 속도: 접촉을 덜 허용
            shield_abs = utl["shield_per_s"] * dt
            heal_now = utl["lifesteal"] * tot_dmg * dt * (kill / kill_cap if kill_cap > 0 else 0) + utl["heal_on_kill"] * kill
        hits *= cc_now["contact"]  # 군중 제어: 접근·접촉이 줄어든다(위협 쪽 효과)
        d_contact = max(0.0, hits * dmg_avg * c["hit_dmg_scale"] * mult * gmul - shield_abs)
        pr["hits"] += hits
        d_champ = 0.0
        # ---- 강한 적
        if phase in ("champ", "boss") and champ is not None:
            ps = pw.p_single(build, N) * luck
            champ["hp"] -= ps * dt
            cs = T["champions"][champ["idx"]]
            cyc = (cs["windup"] + cs["recover"]) / 60.0
            dd = cs["damage"] * c["champ_p_hit"] / cyc * dt * pw.last_strong_keep
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
        if heal_now > 0:
            hp = min(maxhp, hp + heal_now)
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
    # 진행도(0~1): 승리 1, 아니면 (구역 + 봉인 진행)/3, 우두머리 싸움이면 남은 체력 몫을 더한다. 승률이 0 근처인 곳에서 탐색의 기울기를 주려는 보조 지표다.
    _zi = min(zone, 2)
    if res["win"]:
        res["prog"] = 1.0
    elif phase in ("boss",) and champ is not None:
        res["prog"] = round((2 + 0.8 + 0.19 * (1 - max(0.0, champ["hp"]) / T["champions"][2]["hp"])) / 3.0, 3)
    else:
        res["prog"] = round(min(0.79, (_zi + min(1.0, zk / max(1.0, T["seal_kills"][_zi]))) / 3.0), 3)
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
    k = name.split(":")[0]
    return "synergy" if k == "kit" else k  # kit:<이름>은 시험 묶음의 "짝을 맞춘 조합" 길


def run_matrix(cfg, policies, witches, seeds):
    tasks = [(pol, w, s, None) for pol in policies for w in witches for s in seeds]
    rs = run_many(cfg, tasks)
    out = {}
    i = 0
    for pol in policies:
        for w in witches:
            out[(pol, w)] = rs[i:i + len(seeds)]
            i += len(seeds)
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
    A("스킬 구성 %s, 주문 데이터 %s(%s), 리듬 %s, 시드 %s, dt %.1fs, 장비 %s" % (
        cfg.mode, Path(cfg.spells_path).name, cfg.spells_sha, "켬" if cfg.tuning["rhythm"].get("enabled") else "꺼짐",
        "%d~%d(%d판)" % (seeds[0], seeds[-1], len(seeds)), cfg.dt,
        (cfg.spec.get("gear") or cfg.gear) if (cfg.gear["dmg"] != 1 or cfg.gear["hp"] != 1) else "없음"))
    A("")
    A("정책 x 마녀 | 승률(±95%) | P7 | 판 길이 중앙 | 죽은 마디(원인) | 진화 시각(중앙) | 레벨 | 터뜨림 몫 | 남은생명(승)")
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
            wk = sum(1 for r in rs if r["win"])
            _p, lo_, hi_ = wilson(wk, len(rs))
            A("%-18s %-6s %s±%-2.0f %s %6.0fs  %-34s %s  L%.1f  %4.0f%%  %s" % (
                pol, w, fmt_pct(wr_), 100 * (hi_ - lo_) / 2, m, med([r["secs"] for r in rs]) or 0, dtxt,
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


# ---- 맞춤 2차: builds2 실측(장비 없음 / 장비 켬) -------------------------------
GROUPS2 = [("강(pilot·narrow)", ("pilot", "narrow")), ("중(synergy_now)", ("synergy_now",)), ("약(random·spread·worst)", ("random", "spread", "worst"))]
BEATS2 = ["기", "승1", "승2", "전A"]
FIT2_PARAMS = {  # 이름: (하한, 상한) — 곱셈 걸음. gear_now_*는 덧셈 걸음
    "hit_rate_per_alive": (0.0005, 0.02), "hit_dmg_scale": (0.03, 1.0), "tau_min_s": (1.0, 8.0), "cluster": (1.0, 8.0),
    "eta_aim": (0.4, 1.0), "xp_mult": (0.5, 1.5), "eta_dense": (0.0, 3.0), "hit_alive_exp": (0.3, 1.6), "noise_sigma": (0.05, 0.6),
    "power_luck_sigma": (0.0, 0.3), "potion_use_frac": (0.2, 0.7), "champ_p_hit": (0.01, 0.3), "single_kappa": (0.005, 0.2),
    "champ_time_scale": (0.0, 1.0), "single_proj_acc": (0.3, 1.0), "ward_p_hit": (0.05, 0.8),
}
FIT2_GEAR = {"gear_now_p": (0.0, 3.0), "gear_now_s": (0.0, 3.0)}


def find_real_dir2():
    for base in [ROOT] + list(ROOT.parents):
        d = base / "_local"
        if (d / "builds2" / "sim-noequip.json").exists():
            return d
    return None


def load_real2(real_dir):
    return {c: load_json(real_dir / "builds2" / ("sim-%s.json" % c))["runs"] for c in ("noequip", "equip")}


def _wname(r):
    return r["primary"].split(".")[-1]


def model_pairs(real_runs, cond, extra_sets=()):
    spec = {"preset": "current", "skills": None, "spells": None, "gear": "kit.now" if cond == "equip" else None, "dt": 1.0,
            "sets": list(extra_sets), "mode": "legacy"}
    cfg = cfg_from_spec(spec)
    tasks = [(r["policy"], _wname(r), int(r["seed"]), r["picks"]) for r in real_runs]
    return list(zip(real_runs, run_many(cfg, tasks)))


def _rate(xs):
    return sum(1 for x in xs if x) / len(xs) if xs else 0.0


def pol_stats(pairs):
    out = {}
    pols = []
    for r, m in pairs:
        if r["policy"] not in pols:
            pols.append(r["policy"])
    for p in pols:
        rr = [(r, m) for r, m in pairs if r["policy"] == p]
        out[p] = dict(n=len(rr), rw=_rate([r["mode"] == "victory" for r, m in rr]), mw=_rate([m["win"] for r, m in rr]),
                      rt=_rate([r["mode"] == "playing" for r, m in rr]), mt=_rate([m["stall"] for r, m in rr]),
                      rsec=med([r["secs"] for r, m in rr]), msec=med([m["secs"] for r, m in rr]),
                      rk=sum(r["kills"] for r, m in rr) / len(rr), mk=sum(m["kills"] for r, m in rr) / len(rr),
                      rd=sum(r["dmg_total"] for r, m in rr) / len(rr), md=sum(m["dmg_total"] for r, m in rr) / len(rr),
                      rp=sum(r["potions"] for r, m in rr) / len(rr), mp=sum(m["potions"] for r, m in rr) / len(rr))
    return out


def group_beats(pairs):
    out = {}
    for gname, gp in GROUPS2:
        rr = [(r, m) for r, m in pairs if r["policy"] in gp]
        if not rr:
            continue
        for lab in BEATS2:
            a = beat_agg([r["beats"] for r, m in rr], lab)
            m_ = model_beat_agg([m for r, m in rr], lab)
            if a and m_:
                out[(gname, lab)] = (a, m_)
    return out


def _lg(m, r, floor=1e-3):
    return math.log(max(m, floor) / max(r, floor))


def score2(real2, extra_sets, parts=False):
    """맞춤 목적함수(작을수록 좋다). 장비 없음: 정책별 승·정체 비율, 판 길이, 처치·받은 피해·회수약, 마디별 처치/살아 있는 적/피격.
    장비 켬: 정책별 승률, 판 길이, 처치."""
    s_ne = model_pairs(real2["noequip"], "noequip", extra_sets)
    s_eq = model_pairs(real2["equip"], "equip", extra_sets)
    sc = {"noequip_win": 0.0, "noequip_stall": 0.0, "noequip_len": 0.0, "noequip_vol": 0.0, "noequip_beats": 0.0, "equip_win": 0.0, "equip_len": 0.0}
    for p, x in pol_stats(s_ne).items():
        sc["noequip_win"] += 4 * (x["rw"] - x["mw"]) ** 2
        sc["noequip_stall"] += 2 * (x["rt"] - x["mt"]) ** 2
        sc["noequip_len"] += 1.0 * _lg(x["msec"], x["rsec"]) ** 2
        sc["noequip_vol"] += 0.5 * (_lg(x["mk"], x["rk"]) ** 2 + _lg(x["md"], x["rd"]) ** 2 + 0.5 * _lg(x["mp"], x["rp"]) ** 2)
    for (g, lab), (a, m) in group_beats(s_ne).items():
        sc["noequip_beats"] += 0.4 * _lg(m["kpm"], a["kpm"]) ** 2 + 0.4 * _lg(m["alive"], a["alive"]) ** 2 + 0.15 * _lg(m["hpm"], a["hpm"]) ** 2
    for p, x in pol_stats(s_eq).items():
        sc["equip_win"] += 6 * (x["rw"] - x["mw"]) ** 2
        sc["equip_len"] += 1.0 * _lg(x["msec"], x["rsec"]) ** 2 + 0.5 * _lg(x["mk"], x["rk"]) ** 2
    tot = sum(sc.values())
    return (tot, sc, s_ne, s_eq) if parts else tot


def calib2_table(real2, extra_sets, title=""):
    tot, sc, s_ne, s_eq = score2(real2, extra_sets, parts=True)
    L = []
    A = L.append
    A("== 맞춤 2차 %s ==  실측: _local/builds2/sim-noequip.json(270판, 정책 6 x 마녀 3 x 15), sim-equip.json(135판, 정책 3 x 3 x 15)" % title)
    A("모델: 지금 게임 값(legacy 구성, 리듬 꺼짐), 실측의 은총 선택 순서를 되먹임, 시드는 실측과 같음. 장비 켬 조건은 --gear kit.now")
    A("목적함수 %.3f  구성: %s" % (tot, ", ".join("%s %.2f" % kv for kv in sc.items())))
    A("")
    A("[표 A] 장비 없음 — 정책별. 승률/정체(600초 시간 상한) 비율/판 길이 중앙/처치/받은 피해(최대 생명 배수)/회수약")
    A("정책         | 승 실측 모델 | 정체 실측 모델 | 길이(초) 실측 모델 오차 | 처치 실측 모델 오차 | 받은피해 실측 모델 오차 | 약 실측 모델")
    for p, x in pol_stats(s_ne).items():
        A("%-12s | %4.0f%% %4.0f%% | %4.0f%% %4.0f%% | %6.0f %6.0f %+4.0f%% | %5.0f %5.0f %+4.0f%% | %5.2f %5.2f %+4.0f%% | %4.1f %4.1f" % (
            p, x["rw"] * 100, x["mw"] * 100, x["rt"] * 100, x["mt"] * 100, x["rsec"], x["msec"], err(x["rsec"], x["msec"]) or 0,
            x["rk"], x["mk"], err(x["rk"], x["mk"]) or 0, x["rd"], x["md"], err(x["rd"], x["md"]) or 0, x["rp"], x["mp"]))
    A("")
    A("[표 B] 장비 없음 — 정책 묶음 x 마디. 처치/분, 살아 있는 적 평균, 분당 피격 (실측 모델 오차%)")
    for (g, lab), (a, m) in group_beats(s_ne).items():
        A("%-22s %-3s | 처치 %4.0f %4.0f %+4.0f%% | 살아있는적 %5.1f %5.1f %+4.0f%% | 피격 %5.1f %5.1f %+4.0f%%" % (
            g, lab, a["kpm"], m["kpm"], err(a["kpm"], m["kpm"]) or 0, a["alive"], m["alive"], err(a["alive"], m["alive"]) or 0,
            a["hpm"], m["hpm"], err(a["hpm"], m["hpm"]) or 0))
    A("")
    A("[표 C] 장비 켬(kit.now: 힘 x%.2f, 버팀 x%.2f) — 정책별 승률/판 길이/처치" % (
        1 + load_calib_value("gear_now_p", extra_sets), 1 + load_calib_value("gear_now_s", extra_sets)))
    A("정책         | 승 실측 모델 | 길이(초) 실측 모델 오차 | 처치 실측 모델 오차")
    for p, x in pol_stats(s_eq).items():
        A("%-12s | %4.0f%% %4.0f%% | %6.0f %6.0f %+4.0f%% | %5.0f %5.0f %+4.0f%%" % (
            p, x["rw"] * 100, x["mw"] * 100, x["rsec"], x["msec"], err(x["rsec"], x["msec"]) or 0, x["rk"], x["mk"], err(x["rk"], x["mk"]) or 0))
    nr = [x for x in pol_stats(s_ne).values()]
    A("")
    A("[표 D] 서열(정책별 승률 순위 상관, 장비 없음은 전부 0이라 정체 비율의 역수로 대신 본다)")
    pols = list(pol_stats(s_ne).keys())
    ps = pol_stats(s_ne)
    A("  정체 비율 순위 상관(실측 vs 모델, 정책 %d): %.2f" % (len(pols), spearman([ps[p]["rt"] for p in pols], [ps[p]["mt"] for p in pols])))
    pe = pol_stats(s_eq)
    pl2 = list(pe.keys())
    A("  장비 켬 승률 순위 상관(정책 %d): %.2f" % (len(pl2), spearman([pe[p]["rw"] for p in pl2], [pe[p]["mw"] for p in pl2])))
    return "\n".join(L)


def load_calib_value(name, extra_sets=()):
    v = load_json(HERE / "balance_sim_calib.json")["params"][name]["value"]
    for s in extra_sets:
        if s.startswith("calib." + name + "="):
            v = float(s.split("=", 1)[1])
    return v


def write_calib_doc(p, doc):
    """한 상수가 한 줄인 꼴로 쓴다(손으로 읽고 diff를 보기 쉽게)."""
    lines = ["{", '  "schema_version": %s,' % json.dumps(doc["schema_version"]), '  "note": %s,' % json.dumps(doc["note"], ensure_ascii=False), '  "params": {']
    if doc.get("fit_summary"):
        lines.insert(3, '  "fit_summary": %s,' % json.dumps(doc["fit_summary"], ensure_ascii=False))
    ks = list(doc["params"].keys())
    for i, k in enumerate(ks):
        v = doc["params"][k]
        lines.append('    %s: %s%s' % (json.dumps(k), json.dumps(v, ensure_ascii=False), "," if i + 1 < len(ks) else ""))
    lines += ["  }", "}"]
    Path(p).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def do_fit2(args):
    real_dir = Path(args.real_dir) if args.real_dir else find_real_dir2()
    real2 = load_real2(real_dir)
    cur = {}
    sets = []
    for k in list(FIT2_PARAMS) + list(FIT2_GEAR):
        cur[k] = load_calib_value(k)

    def mk():
        return ["calib.%s=%r" % (k, v) for k, v in cur.items()]
    best = score2(real2, mk())
    print("fit2 시작 목적함수 %.3f" % best, flush=True)
    for rnd in range(3):
        for k, (lo, hi) in list(FIT2_PARAMS.items()) + list(FIT2_GEAR.items()):
            for f in ((0.6, 1.5, 0.85, 1.18) if rnd < 2 else (0.92, 1.08)):
                old = cur[k]
                if k in FIT2_GEAR:
                    new = min(hi, max(lo, old * f if old > 0.05 else old + 0.1 * (f - 1) / abs(f - 1)))
                else:
                    new = min(hi, max(lo, old * f if old > 0 else 0.05))
                if new == old:
                    continue
                cur[k] = new
                v = score2(real2, mk())
                if v < best - 1e-6:
                    best = v
                    print("  r%d %s -> %.5g  (%.3f)" % (rnd, k, new, v), flush=True)
                else:
                    cur[k] = old
    print("fit2 끝 목적함수 %.3f" % best)
    print(json.dumps({k: round(v, 5) for k, v in cur.items()}, ensure_ascii=False))
    if args.write_calib:
        p = HERE / "balance_sim_calib.json"
        doc = json.loads(p.read_text(encoding="utf-8"))
        for k, v in cur.items():
            doc["params"][k]["value"] = round(v, 5)
            doc["params"][k]["source"] = "fit2(builds2)"
        write_calib_doc(p, doc)
        print("balance_sim_calib.json에 썼다(--write-calib)")
    else:
        print("파일은 고치지 않았다(--write-calib을 주면 balance_sim_calib.json에 쓴다)")
    return cur


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


# ---- 팩터 표(스킬 정의에 쓸 수 있는 옵션) -------------------------------------------
# (id, 갈래, 설명, 주문 데이터 필드, 모델의 식, 지금 코어에 있는가 — combat_core.gd를 grep으로 본 한도)
FACTORS = [
    ("damage", "공격력", "기본 피해(raw, 256=1 HP)", "base.damage_raw", "d_eff = raw/256 x 축 피해 배율; 모든 처리량 식", "있음"),
    ("cooldown", "쿨타임·시전 속도", "쿨타임 틱", "base.cooldown_ticks", "초당 시전 = 1/cd; 축 쿨타임 배율", "있음"),
    ("projectiles", "갯수", "발수", "base.projectiles", "탄: n = k x (1 + 관통 x phi) x (1 + 밀도 x 폭발 넓이)", "있음"),
    ("pierce", "갯수", "관통", "base.pierce", "위 식의 phi(줄에 다음 적이 있을 확률)", "있음"),
    ("radius", "범위", "맞은 자리 폭발 반경", "base.radius_cm", "폭발 넓이 pi r^2 x 맞은 자리 밀도", "있음"),
    ("chain", "갯수", "연쇄 수·갈래", "base.chain_targets/branches", "n = min(예산, 연쇄 x 갈래, 살아 있는 수)", "있음"),
    ("ring", "범위", "주인공 둘레 원형 반경·대상 수·파동 수", "base.ring_radius_cm/ring_targets/ring_pulses", "m = N(1-exp(-(R/r0)^2)), 예산 상한", "없음(D12 B0 새 구성)"),
    ("budget", "갯수", "한 시전이 맞힐 수 있는 상한", "base.hit_budget", "모든 n의 상한", "있음"),
    ("range", "범위", "사거리", "base.range_cm", "선: 면적 = 폭 x 사거리", "있음(투사체 속도·수명)"),
    ("width", "범위", "선 폭", "base.width_cm (shape=line)", "line: n = k x (1 + 관통 x phi + 밀도 x 폭 x 사거리)", "코어에 새로 필요"),
    ("zone", "지속", "장판(반경·지속 초·틱 간격·개수)", "base.zone{radius_cm,duration_s,tick_ticks,count} (shape=zone)", "hits/s = 활성 장판 수 x 장판 안 적 수 / 틱", "코어에 새로 필요"),
    ("summon", "개수", "소환·포탑(마릿수·지속·공격 간격)", "base.summon{count,duration_s,attack_ticks} (shape=summon)", "hits/s = 수 x 가동률 x 1/공격 간격(조준 없음)", "코어에 새로 필요"),
    ("crit", "치명타", "치명타율(bps)", "crit_bps, base/reach.crit_bps", "기대 배율 1 + p(m-1); 처치당 명중 수의 계단은 두 점 분포로(치명이면 d x m)", "코어에 새로 필요"),
    ("crit_dmg", "치명타", "치명타 피해(bps, 기본 15000)", "crit_dmg_bps", "위 식의 m", "코어에 새로 필요"),
    ("extra_elem", "추가 피해", "원소 추가 피해(bps 가산)", "extra.elem_bps", "피해 배율에 가산", "코어에 새로 필요"),
    ("extra_status", "추가 피해", "상태 걸린 적에게 추가(bps)", "extra.vs_status{status,bps}", "x p(상태 있음)=1-exp(-스택)", "있음(표식 공명 일부)"),
    ("extra_strong", "추가 피해", "강한 적에게 추가(bps)", "extra.vs_strong_bps", "단일 처리량 식에만", "코어에 새로 필요"),
    ("extra_low", "추가 피해", "생명 낮은 적에게 추가(bps)", "extra.vs_low_hp_bps", "x calib.p_low_hp", "코어에 새로 필요"),
    ("extra_near_far", "추가 피해", "가까운/먼 적에게 추가(bps)", "extra.vs_near_bps / vs_far_bps", "x calib.p_near / (1-p_near)", "코어에 새로 필요"),
    ("extra_cc", "추가 피해", "제어 중인 적에게 추가(bps)", "extra.vs_cc_bps", "x 제어 중 몫(cc 계산)", "코어에 새로 필요"),
    ("dot", "추가 피해", "지속 피해(초당 명중 피해 비율 bps, 초)", "dot{dps_bps,secs}", "가산 = dps x min(secs, dot_cap_s) x dot_eff(죽은 적에 낭비 제외)", "코어에 새로 필요"),
    ("on_kill", "추가 피해", "처치 때 폭발(반경, 피해 bps, 예산)", "on_kill{radius_cm,dmg_bps,budget}", "추가 명중 = 처치 수 x 폭발 안 적 수", "있음(death_burst)"),
    ("cc_slow", "군중 제어", "둔화(%, 초)", "cc{chance_bps,slow_bps,slow_s}", "접촉 배율 x (1 - 둔화 몫); 강한 적은 지속 x cc_strong_mult", "있음(slow_bps)"),
    ("cc_freeze_stun_root", "군중 제어", "빙결·기절·묶음(초)", "cc{freeze_s,stun_s,root_s}", "접촉 배율 x exp(-맞히는 속도 x 초)", "있음(freeze·stun)/묶음은 새로 필요"),
    ("cc_knock", "군중 제어", "밀어냄(cm)", "cc.knock_cm", "되돌아오는 초 = 거리/적 속도를 제어 시간에 더함", "코어에 새로 필요"),
    ("cc_pull", "군중 제어", "끌어당김(cm)", "cc.pull_cm", "원형 명중 x (1 + 끌림 몫), 상한 +50%", "코어에 새로 필요"),
    ("vuln", "표식·취약", "받는 피해 증가(bps, 초, 확률)", "vuln{bps,secs,chance_bps}", "모든 명중 x (1 + sum bps x p_표식)", "있음(marks 일부)"),
    ("lifesteal", "방어·회복", "생명 흡수(bps)", "utility.lifesteal_bps", "회복/s = 흡수 x 준 피해/s", "코어에 새로 필요"),
    ("heal_kill", "방어·회복", "처치 회복(HP)", "utility.heal_on_kill", "회복 = 처치 수 x HP", "코어에 새로 필요"),
    ("shield", "방어·회복", "보호막(HP/s)", "utility.shield_per_s", "접촉 피해에서 초당 차감", "코어에 새로 필요"),
    ("dr", "방어·회복", "피해 감소(bps)", "utility.dr_bps", "받는 피해 x (1-dr)", "있음(생존 카드 guard)"),
    ("move", "방어·회복", "이동 속도(bps)", "utility.move_bps", "접촉 횟수 / (1 + 0.5 x move)", "있음(이동)"),
    ("cd_refund", "자원·쿨타임 환급", "처치 때 쿨타임 환급(bps)", "utility.cd_refund_bps", "명중 x min(2, 1 + 환급 x 처치/s x cd)", "코어에 새로 필요"),
    ("evolve_free", "진화", "짝 없이 진화(시험 묶음용 표시)", "evolve_free", "진화 조건에서 짝 조건을 건너뜀", "(도구 전용)"),
]
GEAR_KEYS = [  # (키, 뜻, 기본값, 권하는 범위)
    ("dmg", "모든 주문 피해 배율", 1.0, (0.5, 3.0, 0.05)), ("cd", "쿨타임 배율(작을수록 빠름)", 1.0, (0.5, 1.2, 0.02)),
    ("hp", "최대 생명 배율", 1.0, (0.5, 3.0, 0.05)), ("dr", "받는 피해 배율(작을수록 단단)", 1.0, (0.3, 1.0, 0.02)),
    ("crit", "치명타율 가산(0.1 = +10%p)", 0.0, (0.0, 0.6, 0.01)), ("critdmg", "치명타 피해 가산(0.5 = +50%)", 0.0, (0.0, 2.0, 0.05)),
    ("range", "범위(반경·사거리·폭) 배율", 1.0, (0.7, 2.0, 0.05)), ("count", "발수·연쇄·대상·소환 수 가산(정수)", 0, (0, 4, 1)),
    ("pierce", "관통 가산", 0, (0, 4, 1)), ("extra", "원소 추가 피해 가산(0.2 = +20%)", 0.0, (0.0, 1.0, 0.02)),
    ("dot", "지속 피해 배율", 1.0, (0.5, 3.0, 0.1)), ("cc", "군중 제어 지속·거리 배율", 1.0, (0.5, 3.0, 0.1)),
    ("vuln", "표식 취약 가산(0.1 = +10%)", 0.0, (0.0, 0.6, 0.02)), ("lifesteal", "생명 흡수(0.05 = 5%)", 0.0, (0.0, 0.3, 0.01)),
    ("heal_kill", "처치당 회복 HP", 0.0, (0.0, 3.0, 0.1)), ("dr_add", "피해 감소 가산(0.1 = 10%)", 0.0, (0.0, 0.5, 0.02)),
    ("move", "이동 속도 가산(0.2 = +20%)", 0.0, (0.0, 1.0, 0.02)), ("cd_refund", "처치 쿨타임 환급 가산", 0.0, (0.0, 1.0, 0.02)),
]
FACTOR_TEMPLATES = {  # 주문에 새로 적어 볼 수 있는 팩터(키 접미사: 기본값, 범위)
    "crit_bps": (0, 0, 8000, 250), "crit_dmg_bps": (15000, 12000, 40000, 1000), "extra.elem_bps": (0, 0, 8000, 250), "extra.vs_strong_bps": (0, 0, 15000, 500),
    "extra.vs_low_hp_bps": (0, 0, 15000, 500), "extra.vs_near_bps": (0, 0, 10000, 500), "extra.vs_far_bps": (0, 0, 10000, 500), "extra.vs_cc_bps": (0, 0, 10000, 500),
    "dot.dps_bps": (0, 0, 8000, 250), "dot.secs": (0, 0, 8, 0.5), "on_kill.dmg_bps": (0, 0, 15000, 500), "on_kill.radius_cm": (0, 0, 500, 25),
    "cc.chance_bps": (10000, 500, 10000, 500), "cc.slow_bps": (0, 0, 8000, 500), "cc.slow_s": (0, 0, 6, 0.25), "cc.freeze_s": (0, 0, 3, 0.1), "cc.stun_s": (0, 0, 3, 0.1),
    "cc.root_s": (0, 0, 4, 0.25), "cc.knock_cm": (0, 0, 600, 25), "cc.pull_cm": (0, 0, 800, 25), "vuln.bps": (0, 0, 8000, 250), "vuln.secs": (0, 0, 10, 0.5),
    "utility.lifesteal_bps": (0, 0, 3000, 100), "utility.heal_on_kill": (0, 0, 3, 0.1), "utility.shield_per_s": (0, 0, 3, 0.1), "utility.dr_bps": (0, 0, 5000, 250),
    "utility.move_bps": (0, 0, 5000, 250), "utility.cd_refund_bps": (0, 0, 5000, 250),
}
TRUST = {  # 시험장(sim_power.gd) 실측 재맞춤 뒤(2026-11-19, power-bench). 모두 모델의 답이다. 자동 조작의 결과로 맞췄고 재미는 평가하지 않는다
    "ok": ["정책 사이 서열(어느 선택이 더 센가)", "값을 바꿨을 때의 방향(위협·힘을 올리면 어디서 막히는가)", "시너지 길 사이의 상대 차", "속도가 필요한 훑기·민감도", "장비를 켜고 끌 때의 대략의 크기(kit.now에 맞춤)",
           "원형 안의 적 수(시험장 실측에 맞춤: 실/모 0.99~1.11)", "원형+기본기 짝 빌드의 열린 곳 처리량(실/모 0.95~1.09, 맞춘 칸 안)", "접촉 시간 몫에서 받은 피해로 가는 길(stand 실/모 0.8~1.2, pilot 0.8~0.9)"],
    "not_ok": ["정확한 승률·초 단위 시각", "기본기 한 발·피해만 빌드의 열린 곳 처리량(실측이 모델의 1.2~1.5배: eta_aim이 장비 켠 판에서 맞춘 값이라 장비 없는 시험장과 다르다. 안 고침)",
               "수호자·우두머리 앞의 단일 처리량 절대값(맞춘 뒤에도 로그 오차 0.5~0.6, 곁 잡몹이 있을 때 빌드별 실/모 0.2~4)", "터뜨림 몫(화염·냉기는 모델이 1.5~2배 높고 번개는 낮다)",
               "진화·결정의 처리량 몫(모델이 실측의 1.8~2.9배. 맞춤 실패로 값을 안 씀)", "접촉 시간 몫이 어떻게 정해지는가(빌드·밀도에서 접촉 몫을 내는 모델이 없다. 실측 입력이 필요)",
               "원소 반응(코어에 효과가 없어 기본은 끔. calib.reactions_on=1로 켤 수 있다)", "차단(밀어냄·빙결·경련)의 효과 크기(0단계 시험장: 접촉 시간 몫이 거의 안 줄었다. 모델의 군중 제어 팩터(접촉 배율 0.15~1)는 이 실측으로 맞추지 않았다)",
               "분당 피격의 마디별 모양", "진화한 주문의 수치(명세에 값이 없음)", "재미(모든 것이 미평가)"],
}


def calib_summary_text(real_dir=None):
    d = load_json(HERE / "balance_sim_calib.json")
    return d.get("fit_summary") or "맞춤 요약 없음(--fit2 --write-calib을 돌리면 balance_sim_calib.json에 들어간다)"


def describe(cfg, args):
    """바꿔 볼 수 있는 키 목록(관리 툴의 입력 칸용). 각 항목: key, value, min, max, step, desc, group, in_core."""
    keys = []

    def add(key, value, lo, hi, step, desc, group, core="확인 안 함"):
        keys.append({"key": key, "value": value, "min": lo, "max": hi, "step": step, "desc": desc, "group": group, "in_core": core})

    def rng_of(v, integer=False):
        if v == 0:
            return 0, 1, 1
        lo, hi = (v * 0.5, v * 2.5)
        st = max(1, round(v / 20)) if integer or isinstance(v, int) else v / 20
        return (int(lo) if isinstance(v, int) else round(lo, 4)), (int(hi) if isinstance(v, int) else round(hi, 4)), st
    labels = {"damage_raw": "피해(raw)", "cooldown_ticks": "쿨타임(틱)", "projectiles": "발수", "pierce": "관통", "radius_cm": "폭발 반경(cm)", "hit_budget": "명중 상한",
              "chain_targets": "연쇄 수", "branches": "갈래", "ring_radius_cm": "원형 반경(cm)", "ring_targets": "원형 대상 수", "ring_pulses": "원형 파동 수",
              "range_cm": "사거리(cm)", "width_cm": "선 폭(cm)"}
    for sid, d in cfg.spells["spells"].items():
        sh = sid.replace(SK, "")
        for k, v in d["base"].items():
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                lo, hi, st = rng_of(v)
                add("spells.%s.base.%s" % (sh, k), v, lo, hi, st, "%s의 %s" % (sh, labels.get(k, k)), "스킬 팩터", "있음" if k in ("damage_raw", "cooldown_ticks", "projectiles", "pierce", "radius_cm", "chain_targets", "branches", "hit_budget", "range_cm") else "코어에 새로 필요")
        for fld in ("vs_strong_bps", "crit_bps", "crit_dmg_bps"):
            if fld in d:
                lo, hi, st = rng_of(d[fld])
                add("spells.%s.%s" % (sh, fld), d[fld], lo, hi, st, "%s: %s" % (sh, fld), "스킬 팩터", "코어에 새로 필요")
        for grp in ("extra", "dot", "on_kill", "cc", "vuln", "utility"):
            for k, v in (d.get(grp) or {}).items():
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    lo, hi, st = rng_of(v)
                    add("spells.%s.%s.%s" % (sh, grp, k), v, lo, hi, st, "%s: %s.%s" % (sh, grp, k), "스킬 팩터", "코어에 새로 필요")
        for dk, bpf in (("detonates", None),):
            for sn, dd in (d.get("detonates") or {}).items():
                for k, v in dd.items():
                    if isinstance(v, int) and not isinstance(v, bool):
                        lo, hi, st = rng_of(v)
                        add("spells.%s.detonates.%s.%s" % (sh, sn, k), v, lo, hi, st, "%s가 %s를 터뜨리는 배율" % (sh, sn), "스킬 팩터", "없음(D12 B0 새 구성)")
    ax = cfg.spells["axis"]["power"]
    for nm in ("damage_bps", "cooldown_bps"):
        for i in range(1, len(ax[nm])):
            add("spells.axis.power.%s[%d]" % (nm, i), ax[nm][i], 4000 if nm == "cooldown_bps" else 10000, 10000 if nm == "cooldown_bps" else 45000, 250, "축 %d점의 %s" % (i, "피해 배율" if nm == "damage_bps" else "쿨타임 배율"), "스킬 팩터", "없음(D12 B0 새 구성)")
    for k in ("axis_sum", "partner_axis_sum", "partner_detonate_bps"):
        v = cfg.spells["evolve"][k]
        add("spells.evolve.%s" % k, v, 1 if v < 100 else 10000, 6 if v < 100 else 30000, 1 if v < 100 else 500, "진화 조건·배율: " + k, "스킬 팩터", "없음(D12 B0 새 구성)")
    T = cfg.tuning
    for i, b in enumerate(T["rhythm"]["beats"]):
        add("rhythm.beats[%d].amount" % i, b["amount"], round(b["amount"] * 0.5, 2), round(b["amount"] * 2, 2), 0.5, "마디 %s 생성 양" % b["id"], "리듬", "있음(rhythm)")
        add("rhythm.beats[%d].alive_cap" % i, b["alive_cap"], 8, 140, 1, "마디 %s 살아 있는 적 상한" % b["id"], "리듬", "있음(rhythm)")
        add("rhythm.beats[%d].hp_bps" % i, b["hp_bps"], 5000, 60000, 500, "마디 %s 체력 배율 [시작, 끝] bps" % b["id"], "리듬", "있음(rhythm)")
    for z, v in enumerate(T["seal_kills"]):
        add("seal_kills[%d]" % z, v, int(v * 0.5), int(v * 1.6), 10, "구역 %d 봉인 처치 수" % (z + 1), "리듬", "있음")
    for i, ch in enumerate(T["champions"]):
        add("champions[%d].hp" % i, ch["hp"], int(ch["hp"] * 0.5), int(ch["hp"] * 1.8), 50, "수호자·우두머리 %d 체력" % (i + 1), "리듬", "있음")
        add("champions[%d].damage" % i, ch["damage"], int(ch["damage"] * 0.5), int(ch["damage"] * 1.5), 1, "수호자·우두머리 %d 공격 피해" % (i + 1), "리듬", "있음")
    for k in ("amount", "hp_bps", "hold_ticks"):
        v = T["rhythm"]["trial"][k]
        add("rhythm.trial.%s" % k, v, v * 0.5, v * 1.6, v / 20, "버티기 " + k, "리듬", "있음(trial)")
    for k, desc, dv, (lo, hi, st) in GEAR_KEYS:
        add("gear." + k, dv, lo, hi, st, "장비 묶음: " + desc, "장비", "(장비 접사 한도는 D12 D2)")
    for k, v in cfg.cal.items():
        meta = cfg.calib_doc["params"][k]
        add("calib." + k, v, round(v * 0.5, 5) if v else 0, round(v * 2, 5) if v else 1, round(abs(v) / 20, 5) if v else 0.05, "모델 상수(%s): %s" % (meta["source"], meta["note"][:60]), "모델 상수", "(모델 가설)")
    return {"schema": 1, "preset": cfg.spec.get("preset"), "mode": cfg.mode, "spells_file": Path(cfg.spells_path).name, "spells_sha": cfg.spells_sha,
            "gear_kits": list(GEAR_KITS) + ["kit.now"], "keys": keys, "factor_templates": {k: {"default": v[0], "min": v[1], "max": v[2], "step": v[3]} for k, v in FACTOR_TEMPLATES.items()},
            "factors": [dict(zip(("id", "group", "desc", "field", "model", "core"), f)) for f in FACTORS], "spell_ids": [s.replace(SK, "") for s in cfg.spells["spells"]],
            "kits": list(cfg.spells.get("kits", {}).keys()), "policies": default_policies(cfg.mode) + ["kit:" + k for k in cfg.spells.get("kits", {})],
            "set_syntax": "--set <key>=<json>. 주문은 spells.<짧은 id>..., 배열은 [i], 점이 든 키는 [\"react.steam\"]. 장비는 --gear kit.d1_end 또는 dmg=1.2,crit=0.1,range=1.2"}


# ---- 시험장(chapter1/tests/sim_power.gd) 실측에 맞춤 -----------------------------------------------------
# 입력: sim_power.gd가 쓴 JSON(--out). --power-data=파일,폴더,글롭(쉼표로 여러 개). 모델 상수를 코어의 실측에 맞춘다.
# 자동 조작의 결과다. 안정성·밸런스 참고 자료이고 재미는 평가하지 않는다. 표의 모델 값은 "모델의 답"이다.
import glob as _glob

WITCHES_ALL = ("ember", "frost", "arc")
POWER_CLASSES = [
    ("기본기 한 발(A, 축 0)", ["base"]), ("기본기 피해만(A_d4)", ["A_d4"]),
    ("기본기 넓이·섞임", ["A_r4", "A_d2r2", "A_d3r3", "A_d4r2", "A_d2r4", "A_cap6c"]),
    ("원형+기본기 짝", ["AR_4", "AR_4fit", "AR_6", "AR_6fit", "AR_7", "AR_evo7"]),
    ("원형만 쌓기", ["R_d2r2", "R_d3r3"]), ("대여 기술 낌", ["AX_4", "AX_6", "ARX_4", "ARX_6", "A_cap6X1"]),
]
POWER_GROUPS = {"T4": (["AR_4", "AR_4fit"], ["A_d4", "A_r4", "A_d2r2"]), "T6": (["AR_6", "AR_6fit"], ["A_d3r3", "A_d4r2", "A_d2r4"]), "T7": (["AR_evo7"], ["A_cap6c", "A_cap6X1"])}


def load_power_cells(spec):
    """sim_power.gd 결과 JSON을 칸 목록으로. 값을 덮어쓴 실행(--set, --pretag, --ring-*, --borrow, --speed-mult, --tally)은 c['_plain']=False(맞춤에서 뺀다)."""
    paths = []
    for part in str(spec).split(","):
        part = part.strip()
        if not part:
            continue
        pp = Path(part)
        if pp.is_dir():
            paths += sorted(pp.rglob("*.json"))
        elif any(ch in part for ch in "*?["):
            paths += [Path(x) for x in sorted(_glob.glob(part))]
        else:
            paths.append(pp)
    cells = []
    for p in paths:
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(d, dict) or "cells" not in d or "meta" not in d:
            continue
        m = d["meta"]
        plain = not (m.get("overrides") or m.get("pretag") or m.get("ring_knobs") or m.get("borrow") or m.get("tally") or m.get("mix") or float(m.get("speed_mult", 1.0)) != 1.0)
        mx = str(m.get("mix") or "")
        for c in d["cells"]:
            c["_mix"] = [int(x) for x in mx.split(":")] if mx.count(":") == 2 else None
            c["_plain"] = plain
            cells.append(c)
    return cells


def _pm(xs):
    xs = [x for x in xs if x is not None and x == x]
    return sum(xs) / len(xs) if xs else float("nan")


def _lg(m, r):
    return math.log(max(m, 1e-6) / max(r, 1e-6))


def power_agg(cells, test, keyf, field):
    g = {}
    for c in cells:
        if c.get("test") != test or not c.get("_plain") or c.get("beat") not in (None, "seung2") or c.get("aborted"):
            continue
        g.setdefault(keyf(c), []).append(c.get(field, 0.0))
    return {k: _pm(v) for k, v in g.items()}


def power_build(cfg, witch, spec, mod=None):
    """sim_power.gd의 빌드 약호(A, R, X, AP, DT, crystal, evo)를 모델의 Build로."""
    M = mod or sys.modules[__name__]
    b = M.Build(cfg, witch)
    x = M.WITCH_AB[witch][0]
    pair = None
    for pr in cfg.spells["pairs"]:
        if pr["kind"] == "detonate" and (pr["a"] in (SK + witch, SK + witch + "_ring") or pr["b"] in (SK + witch, SK + witch + "_ring")):
            pair = pr
    keymap = {"A": SK + witch, "R": SK + witch + "_ring", "X": SK + x, "AP": pair["a"], "DT": pair["b"]}
    crystal = evo = False
    for tok in spec.split("+"):
        tok = tok.strip()
        if tok == "crystal":
            crystal = True
        elif tok == "evo":
            evo = True
        else:
            key, _, ax = tok.partition(":")
            d = re.search(r"d(\d)", ax)
            r = re.search(r"r(\d)", ax)
            s = M.Sp()
            s.dmg, s.reach = (int(d.group(1)) if d else 0), (int(r.group(1)) if r else 0)
            b.sp[keymap[key]] = s
    if crystal or evo:
        b.passives.add(SK + witch)
    if evo:
        a = b.sp[SK + witch]
        a.evolved = True
        a.partner = SK + witch + "_ring"
    b.dirty()
    return b


def _spec_of(cells):
    return {c["build"]: c["spec"] for c in cells}


class _PCfg:
    """cfg의 얕은 사본(상수만 바꿔 Power를 만들 때)."""

    def __init__(self, cfg, cal):
        self.cal, self.mode, self.spells, self.gear, self.tuning = cal, cfg.mode, cfg.spells, cfg.gear, cfg.tuning


def power_fit(cfg, cells, mod=None):
    """시험장 실측에서 상수를 맞춘다. 돌려준다: ({상수: 값}, [진단 줄]). cfg.cal은 고치지 않는다."""
    M = mod or sys.modules[__name__]
    out, log = {}, []
    cal = dict(cfg.cal)
    specs = _spec_of(cells)
    plain = [c for c in cells if c.get("_plain") and c.get("beat") in (None, "seung2") and not c.get("aborted")]
    crowd = [c for c in plain if c.get("test") == "crowd"]
    single = [c for c in plain if c.get("test") == "single"]
    pts = []  # (1) 원형 안 적 수
    for c in crowd:
        for rid, row in (c.get("rings") or {}).items():
            R = (c.get("effects", {}).get(rid, {}).get("ring_radius_cm") or 0) / 100.0
            if R > 0 and row.get("casts", 0) >= 5:
                pts.append((int(c["density"]), R, float(row["inside_mean"]), float(row["casts"])))
    if pts:
        best = None
        for ia in range(12, 90):
            for ib in range(0, 71):
                a, b = ia * 0.25, ib * 0.005
                loss = 0.0
                for N, R, real, w in pts:
                    m = ring_inside({"r0_hero_m": a, "r0_per_alive": b}, N, R)
                    mc = m / (1 - math.exp(-m)) if m > 1e-6 else 1.0
                    loss += w * _lg(mc, real) ** 2
                if best is None or loss < best[0]:
                    best = (loss, a, b)
        out["r0_hero_m"], out["r0_per_alive"] = round(best[1], 3), round(best[2], 4)
        log.append("원형 안 적 수: r0 = %.2f + %.4f*N (표본 %d칸)" % (best[1], best[2], len(pts)))

    def hits_cast_pts(w):
        res = []
        for c in crowd:
            row = (c.get("spells") or {}).get(w)
            if c["witch"] == w and row and row.get("casts", 0) >= 20 and c["build"] in specs:
                res.append((c["build"], int(c["density"]), float(row["hits_per_cast"]), float(row["casts"])))
        return res

    def model_n(c_, witch, build_name, N):
        bd = power_build(cfg, witch, specs[build_name], M)
        for st in bd.eff():
            if st["id"] == SK + witch:
                return spell_hits(st, N, c_) * st["cd"] / min(1.0, max(N, 1e-9))
        return 1.0
    data = hits_cast_pts("ember")
    if data:
        best = None
        for i in range(2, 90):
            c2 = dict(cal)
            c2["cluster"] = i * 0.05
            loss = sum(t[3] * _lg(model_n(c2, "ember", t[0], t[1]), t[2]) ** 2 for t in data)
            if best is None or loss < best[0]:
                best = (loss, c2["cluster"])
        out["cluster"] = round(best[1], 3)
        log.append("화염 기본기 폭발 군집 cluster = %.2f (표본 %d칸)" % (best[1], len(data)))
    data = hits_cast_pts("frost")
    if data:
        best = None
        for ib in range(0, 41):
            for ip in range(0, 41):
                c2 = dict(cal)
                c2["phi_base"], c2["phi_per_alive"] = ib * 0.01, ip * 0.0005
                loss = sum(t[3] * _lg(model_n(c2, "frost", t[0], t[1]), t[2]) ** 2 for t in data)
                if best is None or loss < best[0]:
                    best = (loss, c2["phi_base"], c2["phi_per_alive"])
        out["phi_base"], out["phi_per_alive"] = round(best[1], 3), round(best[2], 5)
        log.append("냉기 창 관통 phi = %.2f + %.4f*N (표본 %d칸)" % (best[1], best[2], len(data)))
    cal.update(out)
    pin = []  # (3) 원형이 정예에 닿는 몫(pilot, 곁 잡몹 0)
    for c in single:
        if c.get("mode") != "pilot" or int(c["mobs"]) != 0:
            continue
        for rid, row in (c.get("rings") or {}).items():
            R = (c.get("effects", {}).get(rid, {}).get("ring_radius_cm") or 0) / 100.0
            if R > 0 and "elite_inside_pct" in row:
                pin.append((R, float(row["elite_inside_pct"]) / 100.0))
    if pin:
        best = None
        for i0 in range(0, 41):
            for isp in range(2, 41):
                r0, sp_ = i0 * 0.2, isp * 0.25
                loss = sum((min(1.0, max(0.0, (R - r0) / sp_)) - p) ** 2 for R, p in pin)
                if best is None or loss < best[0]:
                    best = (loss, r0, sp_)
        out["ring_in_r0"], out["ring_in_span"] = round(best[1], 2), round(best[2], 2)
        log.append("원형이 정예에 닿는 몫(pilot): clip((R-%.1f)/%.2f, 0, 1) (표본 %d점)" % (best[1], best[2], len(pin)))
    cal.update(out)
    ps = power_agg(single, "single", lambda c: (c["witch"], c["build"], int(c["mobs"]), c["mode"]), "elite_dps_hp")
    narrow = [k for k in ps if k[3] == "pilot" and k[1] in specs and ps[k] > 0 and not re.search(r"(^|\+)(R|X|AP|DT)|evo|crystal", specs[k[1]])]
    if narrow:
        best = None
        for ia in range(2, 40):
            for ik in range(0, 61):
                c2 = dict(cal)
                c2["single_proj_acc"], c2["single_kappa"] = ia * 0.05, ik * 0.01
                pw_ = M.Power(_PCfg(cfg, c2))
                loss = sum(_lg(pw_.p_single(power_build(cfg, k[0], specs[k[1]], M), k[2]), ps[k]) ** 2 for k in narrow)
                if best is None or loss < best[0]:
                    best = (loss, c2["single_proj_acc"], c2["single_kappa"])
        out["single_proj_acc"], out["single_kappa"] = round(best[1], 3), round(best[2], 3)
        log.append("단일 처리량(탄 빌드만, 곁 잡몹 0/10/30, pilot): single_proj_acc = %.2f, single_kappa = %.2f (표본 %d칸)" % (best[1], best[2], len(narrow)))
    cal.update(out)
    xs = [k for k in ps if k[3] == "pilot" and k[1] in specs and ps[k] > 0 and re.search(r"(^|\+)X", specs[k[1]]) and not re.search(r"(^|\+)R", specs[k[1]])]
    if xs:
        best = None
        for ip in range(0, 41):
            c2 = dict(cal)
            c2["mark_eff"], c2["p_mark_single"] = 1.0, ip * 0.025
            pw_ = M.Power(_PCfg(cfg, c2))
            loss = sum(_lg(pw_.p_single(power_build(cfg, k[0], specs[k[1]], M), k[2]), ps[k]) ** 2 for k in xs)
            if best is None or loss < best[0]:
                best = (loss, c2["p_mark_single"])
        out["mark_eff"], out["p_mark_single"] = 1.0, round(best[1], 3)
        log.append("표식 공명(정예 단일): p_mark_single = %.3f (대여 빌드 %d칸). mark_eff=1은 켬. 무리 쪽 몫은 모델이 작게 잡는다" % (best[1], len(xs)))
    cal.update(out)
    pc = power_agg(crowd, "crowd", lambda c: (c["witch"], c["build"], int(c["density"])), "power_hp_s")
    for w in WITCHES_ALL:  # (5) 진화 배율
        ks = [(w, "AR_evo7", n) for n in (35, 60, 85)]
        bs_ = [(w, "AR_7", n) for n in (35, 60, 85)]
        if not all(k in pc for k in ks + bs_) or "AR_evo7" not in specs or "AR_7" not in specs:
            continue
        real = _pm([pc[a] / pc[b] for a, b in zip(ks, bs_)])
        best = None
        for iv in range(60, 300):
            c2 = dict(cal)
            c2["evolve_damage_mul_" + w] = iv * 0.01
            # 코어의 진화는 깃발과 짝 터뜨림 배율뿐이다(시험장 보고): 쿨타임·발수·범위·예산의 가설 배율은 1로 두고 피해 배율 하나로 맞춘다
            c2["evolve_cd_mul"], c2["evolve_k_add"], c2["evolve_reach_mul"], c2["evolve_budget_mul"] = 1.0, 0, 1.0, 1.0
            pw_ = M.Power(_PCfg(cfg, c2))
            mr = _pm([pw_.evaluate(power_build(cfg, w, specs["AR_evo7"], M), n)[2] / max(pw_.evaluate(power_build(cfg, w, specs["AR_7"], M), n)[2], 1e-9) for n in (35, 60, 85)])
            loss = abs(math.log(mr / real))
            if best is None or loss < best[0]:
                best = (loss, c2["evolve_damage_mul_" + w], mr)
        if best[0] > 0.15:  # 격자 끝에 붙고도 모델 비가 실측과 15% 넘게 어긋나면 맞춘 값을 쓰지 않는다(다른 곳이 진화 몫을 만들고 있다)
            log.append("진화 배율 %s: 맞춤 실패. 실측 evo7/AR_7 = %.2f, 모델 최선 비 %.2f(피해 배율 %.2f). 쓰지 않는다 — 모델의 결정(passives)·짝 터뜨림 쪽 몫이 실측보다 크다" % (w, real, best[2], best[1]))
            continue
        out["evolve_damage_mul_" + w] = round(best[1], 2)
        out["evolve_cd_mul"], out["evolve_k_add"], out["evolve_reach_mul"], out["evolve_budget_mul"] = 1.0, 0, 1.0, 1.0
        log.append("진화 배율 %s: 실측 evo7/AR_7 = %.2f, 모델이 닿는 피해 배율 = %.2f (모델 비 %.2f; 다른 진화 팩터는 가설 그대로)" % (w, real, best[1], best[2]))
    return out, log


def power_tables(cfg, cells, title, mod=None):
    """모델(cfg.cal) 대 시험장 실측 오차 표: 빌드 x 밀도 처리량, 터뜨림 몫, 시너지/하나만 비, 원형 안 적 수, 정예 단일."""
    M = mod or sys.modules[__name__]
    specs = _spec_of(cells)
    pw = M.Power(cfg)
    L = ["=" * 78, title, "=" * 78]
    crowd = [c for c in cells if c.get("test") == "crowd" and c.get("_plain")]
    dens = sorted({int(c["density"]) for c in crowd})
    pc = power_agg(cells, "crowd", lambda c: (c["witch"], c["build"], int(c["density"])), "power_hp_s")
    pd = power_agg(cells, "crowd", lambda c: (c["witch"], c["build"], int(c["density"])), "det_share_dealt_pct")
    mrows = {}
    for (w, b, n) in pc:
        if b in specs:
            tot_h, dbar, tot, det = pw.evaluate(power_build(cfg, w, specs[b], M), n)
            mrows[(w, b, n)] = (tot, 100.0 * det / tot if tot else 0.0)
    L.append("[A] 빌드 종류 x 밀도: 실측 처리량 / 모델 처리량 (마녀 3 평균, 1.00이면 맞음)")
    L.append("%-26s " % "종류" + " ".join("%7s" % ("N%d" % n) for n in dens))
    allerr = []
    for label, names in POWER_CLASSES:
        row = []
        for n in dens:
            rs = [pc[(w, b, n)] / mrows[(w, b, n)][0] for w in WITCHES_ALL for b in names if (w, b, n) in mrows and mrows[(w, b, n)][0] > 0]
            row.append(_pm(rs))
            allerr += [abs(math.log(r)) for r in rs]
        L.append("%-26s " % label + " ".join("%7.2f" % r if r == r else "%7s" % "-" for r in row))
    L.append("  -> 로그 오차 평균 |ln(실/모)| = %.2f (0이 완전, 0.69가 2배 어긋남)" % _pm(allerr))
    L.append("")
    L.append("[B] 터뜨림 몫(%): 실측/모델, 짝 빌드 AR_6 AR_6fit AR_evo7, 밀도 35·85")
    for w in WITCHES_ALL:
        cs = ["%s@%d %4.1f/%4.1f" % (b, n, pd[(w, b, n)], mrows[(w, b, n)][1]) for b in ("AR_6", "AR_6fit", "AR_evo7") for n in (35, 85) if (w, b, n) in mrows]
        L.append("  %-5s " % w + "  ".join(cs))
    L.append("")
    L.append("[C] 시너지 ÷ 하나만(같은 축 점수) 처리량 비, 시너지 쪽 최대 / 하나만 쪽 최대: 실측|모델")
    L.append("%-4s %-6s " % ("묶음", "마녀") + " ".join("%11s" % ("N%d" % n) for n in dens))
    for g, (syn, nar) in POWER_GROUPS.items():
        for w in WITCHES_ALL:
            vals = []
            for n in dens:
                try:
                    rs = max(pc[(w, b, n)] for b in syn if (w, b, n) in pc) / max(pc[(w, b, n)] for b in nar if (w, b, n) in pc)
                    ms = max(mrows[(w, b, n)][0] for b in syn if (w, b, n) in mrows) / max(mrows[(w, b, n)][0] for b in nar if (w, b, n) in mrows)
                    vals.append("%4.2f|%4.2f" % (rs, ms))
                except ValueError:
                    vals.append("-")
            L.append("%-4s %-6s " % (g, w) + " ".join("%11s" % v for v in vals))
    L.append("")
    L.append("[D] 원형 안의 적 수(시전 때 평균), 반경 2.7~4.1 m 원형: 실측 / 모델(안에 한 마리 이상 조건)")
    pts = {}
    for c in crowd:
        for rid, row in (c.get("rings") or {}).items():
            R = (c.get("effects", {}).get(rid, {}).get("ring_radius_cm") or 0) / 100.0
            if 2.7 <= R <= 4.1 and row.get("casts", 0) >= 5:
                pts.setdefault(int(c["density"]), []).append((R, float(row["inside_mean"])))
    L.append("%5s %8s %8s %8s" % ("N", "실측", "모델", "실/모"))
    for n in sorted(pts):
        real = _pm([x[1] for x in pts[n]])
        mod_ = _pm([(lambda m: m / (1 - math.exp(-m)) if m > 1e-6 else 1.0)(ring_inside(cfg.cal, n, x[0])) for x in pts[n]])
        L.append("%5d %8.2f %8.2f %8.2f" % (n, real, mod_, real / mod_))
    L.append("")
    L.append("[E] 정예 단일 처리량(HP/s), pilot, 곁 잡몹 0·30: 실측 / 모델")
    ps = power_agg(cells, "single", lambda c: (c["witch"], c["build"], int(c["mobs"]), c["mode"]), "elite_dps_hp")
    L.append("%-6s %-9s %9s %9s %6s | %9s %9s %6s" % ("마녀", "빌드", "실+0", "모델+0", "실/모", "실+30", "모델+30", "실/모"))
    e_all = []
    for w in WITCHES_ALL:
        for b in ("A_d4", "A_r4", "AR_6", "AX_6", "A_cap6X1", "AR_evo7", "R_d3r3"):
            if (w, b, 0, "pilot") not in ps or b not in specs:
                continue
            bd = power_build(cfg, w, specs[b], M)
            m0, m30 = pw.p_single(bd, 0), pw.p_single(bd, 30)
            r0, r30 = ps[(w, b, 0, "pilot")], ps.get((w, b, 30, "pilot"), float("nan"))
            if r30 == r30:
                e_all += [abs(math.log(max(r0, 1e-3) / max(m0, 1e-3))), abs(math.log(max(r30, 1e-3) / max(m30, 1e-3)))]
            L.append("%-6s %-9s %9.1f %9.1f %6.2f | %9.1f %9.1f %6.2f" % (w, b, r0, m0, r0 / max(m0, 1e-9), r30, m30, r30 / max(m30, 1e-9)))
    L.append("  -> 로그 오차 평균 |ln(실/모)| = %.2f" % _pm(e_all))
    return "\n".join(L)


def taken_model(cfg, cal, contact_share, mix, zone, hero_hp, mode="stand"):
    """받는 피해 쪽(모델의 답): 초당 맞는 횟수 = 접촉 시간 몫 x hit_per_contact_stand|pilot (맞은 뒤 24틱 무적이라 붙은 적의 수가 아니라 이 몫을 따른다),
    한 번의 피해 = 마디 섞임의 평균 접촉 피해(구역 zone) x hit_dmg_taken. 돌려준다: (맞은 횟수/s, 최대 생명 대비 %/s)."""
    e = cfg.tuning["enemies"]
    tot = float(sum(mix)) or 1.0
    dmg = sum(w / tot * e[k]["damage"][min(zone, 2)] for w, k in zip(mix, ("walker", "ranged", "charger")))
    hits = cal.get("hit_per_contact_" + ("stand" if mode == "stand" else "pilot"), 1.0) * contact_share  # pilot: 움직이면 붙어도 준비 동작이 빗나간다
    return hits, hits * dmg * cal.get("hit_dmg_taken", 1.0) / float(hero_hp) * 100.0


def _mix_of(c, cfg):
    if c.get("_mix"):
        return c["_mix"]
    for b in cfg.tuning["rhythm"]["beats"]:
        if b["id"] == c.get("beat"):
            return [b["mix"]["walker"], b["mix"]["ranged"], b["mix"]["charger"]]
    return [74, 18, 8]


def power_taken_fit(cfg, cells):
    """접촉 시간 몫 -> 받은 피해. tally 칸에서 상수 둘(hit_per_contact_s, hit_dmg_taken)을 맞춘다."""
    tl = [c for c in cells if c.get("test") == "crowd" and "contact_share_pct" in c and c.get("hero_hits_per_s") is not None and not c.get("aborted")]
    if not tl:
        return {}, ["받은 피해: tally 칸이 없어 못 맞춤(sim_power.gd --tally 결과를 --power-data에 더하라)"]
    ks = {}
    for md in ("stand", "pilot"):
        sub = [c for c in tl if (c.get("crowd_mode") or "pilot") == md]
        if sub:
            ks[md] = sum(c["contact_share_pct"] / 100.0 * c["hero_hits_per_s"] for c in sub) / (sum((c["contact_share_pct"] / 100.0) ** 2 for c in sub) or 1.0)
    cal = dict(cfg.cal)
    cal["hit_per_contact_stand"], cal["hit_per_contact_pilot"], cal["hit_dmg_taken"] = ks.get("stand", 2.4), ks.get("pilot", 0.8), 1.0
    sr, sm = 0.0, 0.0
    for c in tl:
        zone = {"gi": 0, "seung1": 1, "seung2": 1, "jeon_a": 2}.get(c.get("beat"), 1)
        h, pct = taken_model(cfg, cal, c["contact_share_pct"] / 100.0, _mix_of(c, cfg), zone, c.get("hero_max_hp", 120), c.get("crowd_mode") or "pilot")
        sr += c["taken_pct_s"]
        sm += pct
    dm = sr / sm if sm > 0 else 1.0  # 합의 비(맞은 횟수가 많은 stand 칸이 이끈다)
    out = {"hit_per_contact_stand": round(cal["hit_per_contact_stand"], 3), "hit_per_contact_pilot": round(cal["hit_per_contact_pilot"], 3), "hit_dmg_taken": round(dm if dm == dm and dm > 0 else 1.0, 3)}
    return out, ["받은 피해: 맞은 횟수/s = 접촉 시간 몫 x (stand %.2f | pilot %.2f) (tally %d칸), 한 번 피해 배율 %.2f (실측 합/모델 합)" % (out["hit_per_contact_stand"], out["hit_per_contact_pilot"], len(tl), out["hit_dmg_taken"])]


def taken_table(cfg, cells, cal, title):
    """tally 칸: 접촉 시간 몫으로 모델이 낸 받은 피해 대 실측(마디·움직임별 평균)."""
    tl = [c for c in cells if c.get("test") == "crowd" and "contact_share_pct" in c and not c.get("aborted")]
    g = {}
    for c in tl:
        g.setdefault((c.get("beat"), c.get("crowd_mode"), int(c["density"])), []).append(c)
    L = [title, "%-8s %-6s %4s | %6s %8s %8s | %8s %8s %6s" % ("마디", "움직임", "밀도", "접촉%", "맞음/s실", "맞음/s모", "받은%/s실", "받은%/s모", "실/모")]
    for k in sorted(g, key=lambda x: (str(x[0]), str(x[1]), x[2])):
        cs = g[k]
        zone = {"gi": 0, "seung1": 1, "seung2": 1, "jeon_a": 2}.get(k[0], 1)
        sh = _pm([c["contact_share_pct"] for c in cs])
        hm = _pm([taken_model(cfg, cal, c["contact_share_pct"] / 100.0, _mix_of(c, cfg), zone, c.get("hero_max_hp", 120), k[1])[0] for c in cs])
        pm =_pm([taken_model(cfg, cal, c["contact_share_pct"] / 100.0, _mix_of(c, cfg), zone, c.get("hero_max_hp", 120), k[1])[1] for c in cs])
        hr, pr = _pm([c["hero_hits_per_s"] for c in cs]), _pm([c["taken_pct_s"] for c in cs])
        L.append("%-8s %-6s %4d | %6.1f %8.2f %8.2f | %8.1f %8.1f %6.2f" % (k[0], k[1], k[2], sh, hr, hm, pr, pm, pr / pm if pm else float("nan")))
    return "\n".join(L)


def _calib_text(doc):
    """balance_sim_calib.json의 꼴(최상위 키는 한 줄씩, params는 상수마다 한 줄)을 지킨다."""
    lines = ["{"]
    keys = list(doc.keys())
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        if k == "params":
            lines.append('  "params": {')
            ps = list(doc["params"].items())
            for j, (pk, pv) in enumerate(ps):
                lines.append("    %s: %s%s" % (json.dumps(pk, ensure_ascii=False), json.dumps(pv, ensure_ascii=False), "," if j < len(ps) - 1 else ""))
            lines.append("  }" + comma)
        else:
            lines.append("  %s: %s%s" % (json.dumps(k, ensure_ascii=False), json.dumps(doc[k], ensure_ascii=False), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


def do_calibrate_power(args):
    """--calibrate-power --power-data=...: 맞춤 전/후 오차 표. --write-calib이면 balance_sim_calib.json에 쓴다(기본은 쓰지 않음)."""
    cells = load_power_cells(args.power_data)
    if not cells:
        raise SystemExit("--power-data에서 칸을 못 읽었다: %s" % args.power_data)
    cfg = load_cfg(args, preset=args.preset)
    cfg.mode = "s"
    T = []
    T.append("시험장 실측 칸 %d개(맞춤에 쓰는 것 %d개), 마녀 %s, 시드 %s. 자동 조작의 결과: 밸런스·안정성 참고 자료, 재미는 평가하지 않는다." % (
        len(cells), sum(1 for c in cells if c.get("_plain")), sorted({c["witch"] for c in cells}), sorted({c.get("seed") for c in cells})))
    T.append(power_tables(cfg, cells, "맞춤 전: 지금 balance_sim_calib.json의 상수 (모델의 답)"))
    new, log = power_fit(cfg, cells)
    tnew, tlog = power_taken_fit(cfg, cells)
    new.update(tnew)
    log += tlog
    T.append("")
    T.append("맞춘 값:")
    T += ["  - " + l for l in log]
    T.append("  새 상수: " + json.dumps(new, ensure_ascii=False))
    cfg2 = copy.copy(cfg)
    cfg2.cal = dict(cfg.cal)
    cfg2.cal.update(new)
    if tnew:
        T.append("")
        T.append(taken_table(cfg, cells, dict(cfg.cal, hit_per_contact_stand=1.0, hit_per_contact_pilot=1.0, hit_dmg_taken=1.0), "[F] 받는 피해 맞춤 전(상수 없음: 접촉 몫 1.0에 초당 1회, 배율 1): 모델은 믿을 수 없음"))
        T.append(taken_table(cfg, cells, cfg2.cal, "[F] 받는 피해 맞춤 뒤(접촉 시간 몫 -> 맞은 횟수 -> 피해). 모델의 답"))
    T.append(power_tables(cfg2, cells, "맞춤 뒤: 위 상수를 넣은 모델 (모델의 답. 맞춘 칸과 같은 칸이므로 표본 안 오차다)"))
    if getattr(args, "write_calib", False):
        p = HERE / "balance_sim_calib.json"
        doc = json.loads(p.read_text(encoding="utf-8"))
        for k, v in new.items():
            doc["params"][k] = {"value": v, "source": "power-bench", "note": "시험장 실측에 맞춤(--calibrate-power): " + k}
        doc["params"].setdefault("reactions_on", {"value": 0.0, "source": "core", "note": "원소 반응 모델을 켠다(1). 코어는 반응 짝에 효과를 내지 않으므로(시험장 실측 0%) 기본은 끔"})
        p.write_text(_calib_text(doc), encoding="utf-8", newline="\n")
        T.append("balance_sim_calib.json에 썼다(source=power-bench).")
    txt = "\n".join(T)
    print(txt)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(txt + "\n", encoding="utf-8", newline="\n")
    return 0


def grade_dist_model(g, runs=20000, offers=11, slots=2.4, seed=1):
    """D13 4.11.3 등급 굴림만의 모델(모델의 답). 코어 run_growth.gd의 규칙을 그대로 옮겼다: 제안마다 굴리는 칸 수(평균 slots)에
    칸마다 기연 확률(기본+부드러운 천장), 기연이 없으면 천장 셈 +1, hard_after_spins번째 제안은 한 칸이 반드시 기연.
    칸 수는 정수로 floor(slots) 또는 +1을 확률 slots-floor로 낸다. 판 승패·빌드는 모르는 모델이다."""
    rng = random.Random(seed)
    base, step = int(g["jackpot_bps"]), int(g["pity"]["soft_step_bps"])
    hard, cap = int(g["pity"]["hard_after_spins"]), int(g["cap_bps"])
    hist, first = {}, []
    for _ in range(runs):
        pity, shown, first_offer = 0, 0, 0
        for o in range(offers):
            n = int(slots) + (1 if rng.random() < slots - int(slots) else 0)
            if n <= 0:
                continue
            p = min(cap, base + step * pity) / 10000.0
            hit = any(rng.random() < p for _ in range(n))
            if not hit and hard > 0 and pity + 1 >= hard:
                hit = True
            if hit:
                shown += 1
                first_offer = first_offer or o + 2
                pity = 0
            else:
                pity += 1
        hist[shown] = hist.get(shown, 0) + 1
        if first_offer:
            first.append(first_offer)
    mean = sum(k * v for k, v in hist.items()) / runs
    return {"runs": runs, "offers": offers, "slots_per_offer": slots, "mean": round(mean, 3),
            "zero": round(hist.get(0, 0) / runs, 4), "three_or_more": round(sum(v for k, v in hist.items() if k >= 3) / runs, 4),
            "histogram": {str(k): round(hist[k] / runs, 4) for k in sorted(hist)}, "median_first_level": sorted(first)[len(first) // 2] if first else 0,
            "model_answer_not_game_answer": True}


def do_grade_dist(args):
    tuning = json.loads((Path(__file__).resolve().parents[2] / "chapter1" / "data" / "combat_tuning.json").read_text(encoding="utf-8"))
    g = copy.deepcopy(tuning["grace"]["grades"])
    for s in args.set or []:
        k, v = s.split("=", 1)
        if k.startswith("grace.grades."):
            k = k[len("grace.grades."):]
        cur = g
        parts = k.split(".")
        for q in parts[:-1]:
            cur = cur[q]
        cur[parts[-1]] = int(v)
    res = grade_dist_model(g, slots=args.grade_slots)
    print(json.dumps(res, ensure_ascii=False))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="균형 시뮬레이터 (모델의 답이지 게임의 답이 아니다)")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--fit", action="store_true")
    ap.add_argument("--calibrate2", action="store_true", help="builds2 실측(장비 없음/켬)과 모델의 오차 표")
    ap.add_argument("--calibrate-power", action="store_true", help="시험장(sim_power.gd) 실측(--power-data)에 모델을 맞추기 전/후 오차 표(--write-calib이면 상수를 파일에 씀)")
    ap.add_argument("--power-data", default=None, help="sim_power.gd의 --out JSON 파일·폴더·글롭(쉼표로 여러 개)")
    ap.add_argument("--fit2", action="store_true", help="builds2 실측에 자유 상수를 맞춘다(결과 출력만)")
    ap.add_argument("--write-calib", action="store_true", help="--fit2 결과를 balance_sim_calib.json에 쓴다(기본은 쓰지 않음)")
    ap.add_argument("--sensitivity", action="store_true", help="서열 간격(synergy−narrow, narrow−random)을 가장 크게 움직이는 값을 순서대로(balance_search.py의 값 목록으로). --set은 고정 조건")
    ap.add_argument("--describe", action="store_true", help="고른 주문 묶음·프리셋에서 바꿔 볼 수 있는 키 목록을 JSON으로 낸다(관리 툴 입력 칸용)")
    ap.add_argument("--grade-dist", action="store_true", help="D13 4.11 은총 등급 굴림만의 분포(판당 기연이 뜬 횟수). --set grace.grades.jackpot_bps=300 처럼 바꿔 본다. 모델의 답")
    ap.add_argument("--grade-slots", type=float, default=2.4, help="--grade-dist: 제안마다 굴리는 칸 수의 평균(실제 코어 측정값 test_grace.gd GRACE_DIST)")
    ap.add_argument("--jobs", type=int, default=None, help="병렬 프로세스 수(기본: 코어-2, 최대 14)")
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
    if args.grade_dist:
        return do_grade_dist(args)
    set_jobs(args.jobs if args.jobs else default_jobs())
    if args.sensitivity:
        import balance_search
        av = ["--sensitivity", "--preset", args.preset or "spec1p", "--seeds", str(args.seeds), "--seed0", str(args.seed0), "--witches", args.witches]
        for s in args.set or []:
            av += ["--set", s]
        if args.gear:
            av += ["--gear", args.gear]
        if args.out:
            av += ["--out", args.out]
        return balance_search.main(av)
    if args.calibrate_power:
        if not args.power_data:
            raise SystemExit("--calibrate-power에는 --power-data가 필요하다")
        return do_calibrate_power(args)
    if args.calibrate2 or args.fit2:
        real_dir = Path(args.real_dir) if args.real_dir else find_real_dir2()
        if not real_dir:
            raise SystemExit("실측 폴더(_local/builds2/sim-noequip.json)를 찾지 못했다. --real-dir로 알려 달라")
        if args.fit2:
            do_fit2(args)
        else:
            txt = calib2_table(load_real2(real_dir), list(args.set or []))
            print(txt)
            if args.out:
                Path(args.out).parent.mkdir(parents=True, exist_ok=True)
                Path(args.out).write_text(txt + "\n", encoding="utf-8", newline="\n")
        print("걸린 시간 %.1fs" % (time.time() - t0))
        close_pool()
        return 0
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
    if args.describe:
        doc = describe(cfg, args)
        txt = json.dumps(doc, ensure_ascii=False, indent=1)
        print(txt)
        if args.out:
            Path(args.out).parent.mkdir(parents=True, exist_ok=True)
            Path(args.out).write_text(txt + "\n", encoding="utf-8", newline="\n")
        return 0
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
        Path(args.out).write_text(json.dumps({"preset": args.preset, "mode": cfg.mode, "set": args.set, "results": summarize_for_json(mx),
                                              # 2차에서 더한 키(1차의 키는 그대로)
                                              "meta": {"version": 2, "spells_file": Path(cfg.spells_path).name, "spells_sha": cfg.spells_sha, "gear": cfg.spec.get("gear"),
                                                       "seeds": [seeds[0], seeds[-1]], "n_seeds": len(seeds), "jobs": JOBS, "policies": pols, "witches": witches,
                                                       "model_answer_not_game_answer": True, "fun": "미평가"},
                                              "calibration": calib_summary_text(), "trust": TRUST,
                                              "win_ci95": {"%s|%s" % k: [round(x, 3) for x in wilson(sum(1 for r in v if r["win"]), len(v))[1:]] for k, v in mx.items()}},
                                             ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
        Path(args.out).with_suffix(".txt").write_text(txt + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
