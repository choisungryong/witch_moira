#!/usr/bin/env python3
"""경제·성장 시뮬레이터 — 판과 판 사이의 흐름(영구 경험치·레벨·스킬 포인트·트리·재·장비·상점·퀘스트·균열 깊이)을 계산하는 모델.

모델의 답이며 게임의 답이 아니다. 재미는 평가하지 않는다. 게임 코어를 돌리지 않는다(Godot 없음, 표준 라이브러리만).
balance_sim.py가 한 판 안의 균형을 보는 도구라면 이 도구는 그 판이 N번 이어질 때의 흐름을 본다. balance_sim.py는 고치지 않고,
그 결과(승률-힘 표, --from-balsim으로 받는 결과 JSON)만 입력으로 쓴다.

모델의 구조(자세한 것은 REPORT와 docs의 D11 D·E, D12 P10·C4, D6 1~3, G1 2):
  판 하나 = (플레이어 유형, 마녀, 깊이, 힘 M) -> 승패, 진행 f(0~1), 보상 단계, 처치한 정예·상자·사당·의식·운반자
            -> 경험치(G1 2.1 식)·드랍(loot.json 문법)·재(해체 + 보상 단계 + 퀘스트)·퀘스트 진행
  마을    = 트리 투자(정책) -> 상점·도박·강화(보류, 꺼짐) -> 다음 판의 착용(요구 레벨을 지킴)
  되먹임  = 장비와 트리가 올린 힘 M = (1+p_gear)(1+p_tree) sqrt((1+s_gear)(1+s_tree)) 가 다음 판 승률을 정한다
            승률 = cap × sigmoid(a + k ln(M / 깊이 위협)). a·k는 balance_sim의 --gear 표(win.table.*)에 맞춘다
상수는 tools/dev/sim_economy_calib.json 한 파일에 출처와 함께 있다(--list-params). 데이터 파일(chapter1/data)은 읽기만 한다.

예시(저장소 루트, Python 3.10):
  python tools/dev/sim_economy.py                                  # 명세 첫 값, 100판 흐름 표
  python tools/dev/sim_economy.py --preset now --runs 30           # 지금 게임 데이터
  python tools/dev/sim_economy.py --calibrate                      # sim_progression·sim_loot·P10 예산과 대조
  python tools/dev/sim_economy.py --set forge.enabled=true --set players.average.p_ritual=0.6
  python tools/dev/sim_economy.py --sweep shop.price.rare=80,160,320 --runs 60
  python tools/dev/sim_economy.py --sensitivity                    # 흐름을 가장 크게 움직이는 값
  python tools/dev/sim_economy.py --from-balsim _local/balsim2/some.json --out _local/economy/run.json
"""
import argparse
import bisect
import copy
import json
import math
import multiprocessing
import os
import random
import re
import statistics
import sys
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CALIB_PATH = HERE / "sim_economy_calib.json"
BANNER = "모델의 답이며 게임의 답이 아니다. 재미는 평가하지 않는다."
QUAL = ["common", "magic", "rare", "legendary", "unique"]
SLOTS = ["weapon", "head", "body", "hands", "feet", "charm", "ring"]
SLOT_IDX = {s: i for i, s in enumerate(SLOTS)}
TYPES = ["skilled", "average", "poor"]
TYPE_KO = {"skilled": "잘함", "average": "보통", "poor": "못함"}
TYPE_POLICY = {"skilled": "synergy", "average": "random", "poor": "narrow"}
WITCHES = ["ember", "frost", "arc"]
WITCH_KO = {"ember": "화염", "frost": "서리", "arc": "번개"}
CHECKPOINTS = [1, 2, 3, 5, 10, 20, 30, 50, 100]


# ----------------------------------------------------------------------------------------------- 설정
def parse_val(s):
    try:
        return json.loads(s)
    except Exception:
        return s


def find_local():
    for p in [ROOT] + list(ROOT.parents):
        if (p / "_local").is_dir():
            return p / "_local"
    return ROOT / "_local"


def read_json(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def load_data(root=ROOT):
    """게임 데이터에서 읽는 값. 파일이 없으면 None을 돌려 calib 값을 쓰게 한다."""
    d = {}
    prog = read_json(root / "chapter1/data/character_progression.json")
    d["data.xp_thresholds"] = prog["xp_thresholds"]
    d["data.level_cap"] = prog["level_cap"]
    d["data.points_per_level"] = prog["points_per_level"]
    d["data.seal_xp"] = prog["sources"]["seal_xp"]
    d["data.champion_xp"] = prog["sources"]["champion_xp"]
    d["data.boss_xp"] = prog["sources"]["boss_xp"]
    d["data.victory_xp"] = prog["sources"]["victory_xp"]
    d["data.first_kill_points"] = sum(prog["first_rewards"].values())
    loot = read_json(root / "chapter1/data/loot.json")
    d["loot.data"] = loot
    uniq = {}
    for u in loot.get("uniques", []):
        uniq[u["element"].split(".")[-1]] = u["slot"]
    d["data.unique_slot"] = uniq
    d["data.tree"] = read_json(root / "chapter1/data/skill_trees.json")["trees"][0]
    try:
        txt = (root / "chapter1/core/chapter_profile.gd").read_text(encoding="utf-8")
        m = re.search(r"const ESSENCE := (\{[^}]*\})", txt)
        d["data.salvage"] = json.loads(m.group(1)) if m else None
    except Exception:
        d["data.salvage"] = None
    return d


class Cfg:
    """평평한 점 이름 -> 값. 프리셋을 적용하고 데이터를 읽고 --set을 얹는다."""

    def __init__(self, preset="spec", sets=(), calib_path=CALIB_PATH, root=ROOT, extra=None):
        doc = read_json(calib_path)
        self.meta = {k: (v["source"], v["note"]) for k, v in doc["params"].items()}
        self.p = {k: copy.deepcopy(v["value"]) for k, v in doc["params"].items()}
        if preset not in doc["presets"]:
            raise SystemExit("알 수 없는 프리셋: %s (%s)" % (preset, ",".join(doc["presets"])))
        self.preset = preset
        self.p.update(copy.deepcopy(doc["presets"][preset]))
        self.data = load_data(root)
        for k, v in self.data.items():
            if k.startswith("data.") and k not in ("data.tree", "data.salvage", "data.unique_slot"):
                self.p[k] = copy.deepcopy(v)
        if self.data["data.salvage"]:
            self.p["essence.salvage"] = dict(self.data["data.salvage"])
        for w, s in self.data["data.unique_slot"].items():
            if "unique.slot." + w in self.p:
                self.p["unique.slot." + w] = s
        for k, v in (extra or {}).items():
            self.p[k] = v
        for s in sets:
            k, v = s.split("=", 1)
            if k not in self.p:
                raise SystemExit("알 수 없는 키: %s (--list-params로 목록)" % k)
            self.p[k] = parse_val(v)
        self._cache = {}

    def __getitem__(self, k):
        return self.p[k]

    def with_sets(self, sets):
        c = copy.copy(self)
        c.p = copy.deepcopy(self.p)
        for s in sets:
            k, v = s.split("=", 1)
            if k not in c.p:
                raise SystemExit("알 수 없는 키: %s" % k)
            c.p[k] = parse_val(v)
        c._cache = {}
        return c

    def with_value(self, k, v):
        c = copy.copy(self)
        c.p = dict(self.p)
        if k not in c.p:
            raise SystemExit("알 수 없는 키: %s" % k)
        c.p[k] = v
        c._cache = {}
        return c

    def cached(self, key, fn):
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]


# ----------------------------------------------------------------------------------------------- 승률 곡선
def sigmoid(z):
    if z > 40:
        return 1.0
    if z < -40:
        return 0.0
    return 1.0 / (1.0 + math.exp(-z))


def logit(p):
    p = min(max(p, 1e-6), 1 - 1e-6)
    return math.log(p / (1 - p))


def kit_power(p, s):
    """힘 M. balance_sim.parse_gear와 같은 합성: 힘 P, 버팀 S -> M = P × sqrt(S)."""
    return (1 + p) * math.sqrt(1 + s)


_FIT_MEMO = {}


def fit_win(table, cap):
    """(힘 M, 승률) 표에 cap × sigmoid(a + k ln M)을 맞춘다(격자, 결정론). 같은 입력은 한 번만 푼다."""
    key = (json.dumps(table), cap)
    if key in _FIT_MEMO:
        return dict(_FIT_MEMO[key])
    best = None
    pts = [(math.log(m), w) for m, w in table]
    for ai in range(-90, 70):
        a = ai / 10.0
        for ki in range(2, 100):
            k = ki / 10.0
            err = 0.0
            for lm, w in pts:
                err += (cap * sigmoid(a + k * lm) - w) ** 2
            if best is None or err < best[0]:
                best = (err, a, k)
    _FIT_MEMO[key] = {"a": best[1], "k": best[2], "cap": cap, "rmse": math.sqrt(best[0] / len(pts))}
    return dict(_FIT_MEMO[key])


def win_fit(cfg, t):
    def build():
        f = fit_win(cfg["win.table." + t], cfg["players.%s.cap" % t])
        if cfg["players.%s.k" % t] is not None:
            f["k"] = float(cfg["players.%s.k" % t])
        f["k"] *= cfg["players.%s.k_scale" % t]
        bw = cfg["players.%s.base_win" % t]
        if bw is not None:
            f["a"] = logit(min(0.999, float(bw) / f["cap"]))
        return f
    return cfg.cached("winfit." + t, build)


# ----------------------------------------------------------------------------------------------- 드랍
class Loot:
    """loot.json 문법과 D11 D2·D3 변경을 한 표로. 품질·칸 누적 가중과 출처별 뽑기."""

    def __init__(self, cfg):
        self.cfg = cfg
        data = cfg.data["loot.data"]["treasure_classes"]
        self.mode = cfg["loot.mode"]
        self.classes = {}
        sw = cfg.data["loot.data"]["slot_weights"]
        self.base_slots = [sw[s] for s in SLOTS]
        for name, tc in data.items():
            self.classes[name] = {
                "picks": int(tc["picks"]), "p_drop": tc["drop"] / float(tc["drop"] + tc["no_drop"]),
                "bonus": int(tc["level_bonus"]), "guar": list(tc.get("guaranteed", [])),
                "quality": [tc["quality"].get(q, 0) for q in QUAL],
                "slots": [tc["slot_weights"][s] for s in SLOTS] if "slot_weights" in tc else self.base_slots,
            }
        car_slots = self.classes["carrier"]["slots"]
        if self.mode == "spec":
            c = self.classes
            c["normal"]["p_drop"] = cfg["loot.spec.normal_drop"] / 10000.0
            c["elite"]["p_drop"] = 1.0
            c["champion"]["picks"] = int(cfg["loot.spec.champion_picks"])
            c["chest"] = {"picks": 1, "p_drop": 1.0, "bonus": int(cfg["loot.spec.chest_level_bonus"]), "guar": [],
                          "quality": list(cfg["loot.spec.chest_quality"]), "slots": car_slots}
            c["ritual_chest"] = {"picks": 2, "p_drop": 1.0, "bonus": int(cfg["loot.spec.ritual_level_bonus"]), "guar": [],
                                 "quality": list(cfg["loot.spec.ritual_quality"]), "slots": car_slots}
        self.qcum = {}
        self.scum = {}
        for name, c in self.classes.items():
            self.scum[name] = self._cum(c["slots"])
            self.qcum[name] = []
            for depth in (1, 2, 3):
                w = list(c["quality"])
                w[2] *= cfg["loot.depth_rare_mult"][depth - 1]
                w[3] *= cfg["loot.depth_top_mult"][depth - 1]
                w[4] *= cfg["loot.depth_top_mult"][depth - 1]
                self.qcum[name].append(self._cum(w))
        self.zone_kills_now = cfg["counts.normal_kills_now"]
        if self.mode == "spec":
            tot = float(sum(self.zone_kills_now))
            self.zone_kills = [cfg["counts.normal_kills_spec_total"] * k / tot for k in self.zone_kills_now]
        else:
            self.zone_kills = list(self.zone_kills_now)
        self.max_ilvl = int(cfg.data["loot.data"]["max_item_level"])

    @staticmethod
    def _cum(w):
        out, s = [], 0.0
        for x in w:
            s += x
            out.append(s)
        return out

    def quality(self, rng, cname, di):
        cum = self.qcum[cname][di]
        return bisect.bisect_right(cum, rng.random() * cum[-1])

    def slot(self, rng, cname):
        cum = self.scum[cname]
        return bisect.bisect_right(cum, rng.random() * cum[-1])

    def roll_class(self, rng, cname, zone_level, di, uslot, src, out, picks=None, guar=None):
        """loot.gd roll_class를 따른다: 확정 칸이 먼저, 나머지는 (no_drop, drop)으로 거른 뒤 품질."""
        c = self.classes[cname]
        level = min(self.max_ilvl, max(1, zone_level + c["bonus"]))
        n = c["picks"] if picks is None else picks
        g = c["guar"] if guar is None else guar
        for i in range(n):
            if i < len(g):
                q = QUAL.index(g[i]) if g[i] in QUAL else 4
                s = uslot if q == 4 else self.slot(rng, cname)
            else:
                if c["p_drop"] < 1.0 and rng.random() >= c["p_drop"]:
                    continue
                q = self.quality(rng, cname, di)
                s = uslot if q == 4 else self.slot(rng, cname)
            out.append((src, s, q, level))

    def poisson(self, rng, mu):
        if mu <= 0:
            return 0
        if mu > 30:
            return max(0, int(round(rng.gauss(mu, math.sqrt(mu)))))
        L, k, p = math.exp(-mu), 0, 1.0
        while True:
            p *= rng.random()
            if p <= L:
                return k
            k += 1


def zone_of(cfg, f):
    zs = cfg["run.zone_start"]
    z = 0
    for i in (1, 2):
        if f >= zs[i]:
            z = i
    return z


def run_events(cfg, loot, rng, ptype, witch, depth, f, win, first_boss):
    """한 판의 드랍·사건 요약. f는 판 진행(0~1, 이기면 1)."""
    pp = lambda k: cfg["players.%s.%s" % (ptype, k)]
    di = depth - 1
    zl = cfg["depth.zone_levels"][di]
    zs = cfg["run.zone_start"]
    ze = [zs[1], zs[2], 1.0]
    uslot = SLOT_IDX[cfg["unique.slot." + witch]]
    mode = loot.mode
    out = []
    summ = {"elites": 0, "chests": 0, "shrines": 0, "rituals": 0, "carrier": 0, "grade": 1, "champion0": f >= cfg["run.champ_t"][0],
            "champion1": f >= cfg["run.champ_t"][1], "boss": win}
    # 일반 처치와 정예
    elites_per_zone = {"sim_loot": 2, "now": 0, "spec": int(cfg["run.elite_total"]) // 3}[mode]
    for z in range(3):
        span = ze[z] - zs[z]
        frac = min(1.0, max(0.0, (f - zs[z]) / span)) if span > 0 else 0.0
        n = loot.poisson(rng, loot.zone_kills[z] * frac * loot.classes["normal"]["p_drop"])
        c = loot.classes["normal"]
        for _ in range(n):
            q = loot.quality(rng, "normal", di)
            out.append(("normal", uslot if q == 4 else loot.slot(rng, "normal"), q, min(loot.max_ilvl, zl[z] + c["bonus"])))
        for k in range(elites_per_zone):
            t = zs[z] + (k + 0.5) / elites_per_zone * span
            if t <= f and (mode == "sim_loot" or rng.random() < pp("p_elite")):
                summ["elites"] += 1
                loot.roll_class(rng, "elite", zl[z], di, uslot, "elite", out)
    # 초반 확정 4개(지금 코드에 있다. sim_loot.gd 가정에는 없다)
    if mode != "sim_loot":
        for t in cfg["run.forced_thresholds"]:
            if f >= t:
                q = loot.quality(rng, "normal", di)
                out.append(("forced", uslot if q == 4 else loot.slot(rng, "normal"), q, zl[0]))
    # 수호자
    for i in (0, 1):
        if f >= cfg["run.champ_t"][i]:
            loot.roll_class(rng, "champion", zl[i], di, uslot, "champion", out)
    # 운반자
    if mode == "sim_loot":
        loot.roll_class(rng, "carrier", zl[1], di, uslot, "carrier", out)
        summ["carrier"] = 1
    elif mode == "spec" and f >= cfg["run.carrier_t"] and rng.random() < pp("p_carrier"):
        summ["carrier"] = 1
        loot.roll_class(rng, "carrier", zl[zone_of(cfg, cfg["run.carrier_t"])], di, uslot, "carrier", out)
    # 상자·사당·의식·위험 카드(spec에만 있는 출처)
    if mode == "spec":
        nch = int(cfg["run.chests_mean"]) + (1 if rng.random() < cfg["run.chests_mean"] - int(cfg["run.chests_mean"]) else 0)
        for i in range(nch):
            t = 0.03 + (0.87 * (i + 0.5) / nch)
            if t <= f and rng.random() < pp("p_chest"):
                summ["chests"] += 1
                loot.roll_class(rng, "chest", zl[zone_of(cfg, t)], di, uslot, "chest", out)
        nsh = int(cfg["run.shrines_mean"]) + (1 if rng.random() < cfg["run.shrines_mean"] - int(cfg["run.shrines_mean"]) else 0)
        for i in range(nsh):
            t = 0.08 + (0.8 * (i + 0.5) / nsh)
            if t <= f and rng.random() < pp("p_shrine"):
                summ["shrines"] += 1
        for t in cfg["run.ritual_t"][:int(cfg["run.rituals"])]:
            if f >= t + 0.04 and rng.random() < pp("p_ritual"):
                summ["rituals"] += 1
                loot.roll_class(rng, "ritual_chest", zl[zone_of(cfg, t)], di, uslot, "ritual", out)
        greed = 1 if (f >= 0.30 and rng.random() < pp("p_greed")) else 0
        summ["grade"] = min(4, 1 + summ["rituals"] + summ["carrier"] + greed)
    # 우두머리
    if win:
        g = summ["grade"]
        if mode == "spec":
            nrare = int(cfg["loot.spec.boss_rares"][g - 1])
            loot.roll_class(rng, "boss", zl[2], di, uslot, "boss", out, picks=int(cfg["loot.spec.boss_picks"][g - 1]), guar=["rare"] * nrare)
        else:
            loot.roll_class(rng, "boss", zl[2], di, uslot, "boss", out)
        if first_boss and mode != "sim_loot":
            out.append(("first_kill", uslot, 4, min(loot.max_ilvl, zl[2] + loot.classes["boss_first_kill"]["bonus"])))
    return out, summ


# ----------------------------------------------------------------------------------------------- 장비
class Gear:
    """장비 한 점 = [uid, 칸, 기본 가치, 등급, 아이템 레벨, 강화]. 가치 = 등급 가치 × (ilvl/기준)^지수 × 굴림."""

    def __init__(self, cfg):
        self.qv = [cfg["gear.qv." + q] for q in QUAL]
        self.sp = [cfg["gear.spread." + q] for q in QUAL]
        ref, ex = cfg["gear.ilvl_ref"], cfg["gear.ilvl_exp"]
        self.ilf = [0.0] + [(i / ref) ** ex for i in range(1, 41)]
        self.w = [cfg["gear.slot_w." + s] for s in SLOTS]
        self.p_max, self.gamma = cfg["gear.p_max"], cfg["gear.gamma"]
        self.sa, self.sb = cfg["gear.stay_a"], cfg["gear.stay_b"]
        self.fb = cfg["forge.step_bonus"] * cfg["forge.numeric_share"]
        self.keep = int(cfg["gear.keep_per_slot"])
        self.uid = 0

    def make(self, rng, slot, q, ilvl):
        self.uid += 1
        roll = 1.0 + self.sp[q] * (rng.random() * 2 - 1)
        return [self.uid, slot, self.qv[q] * self.ilf[ilvl] * roll, q, ilvl, 0]

    def eff(self, it):
        return it[2] * (1.0 + self.fb * it[5]) if it[5] else it[2]

    def power(self, items):
        s = 0.0
        for it in items:
            s += self.w[it[1]] * self.eff(it)
        if s <= 0:
            return 0.0, 0.0
        p = self.p_max * s ** self.gamma
        return p, self.sa * (p / 0.225) ** self.sb


class Pool:
    """보관함: 칸마다 점수 순으로 상위 K개만 둔다(나머지는 해체)."""

    def __init__(self, gear):
        self.g = gear
        self.top = [[] for _ in SLOTS]

    def add(self, it):
        lst = self.top[it[1]]
        e = self.g.eff(it)
        evicted = None
        i = 0
        while i < len(lst) and self.g.eff(lst[i]) >= e:
            i += 1
        if i >= self.g.keep:
            return it
        lst.insert(i, it)
        if len(lst) > self.g.keep:
            evicted = lst.pop()
        return evicted

    def loadout(self, level):
        res = []
        for s in range(len(SLOTS)):
            need = 2 if s == 6 else 1
            for it in self.top[s]:
                if max(1, it[4] - 3) <= level:
                    res.append(it)
                    need -= 1
                    if need == 0:
                        break
        return res

    def chosen_in(self, slot, level):
        need = 2 if slot == 6 else 1
        out = []
        for it in self.top[slot]:
            if max(1, it[4] - 3) <= level:
                out.append(it)
                if len(out) == need:
                    break
        return out, need


def slot_gain(gear, pool, slot, v, ilvl, level):
    """새 장비(가치 v)를 끼면 힘의 몫(칸 가중 × 가치)이 얼마나 느는가. 요구 레벨을 못 채우면 0."""
    if max(1, ilvl - 3) > level:
        return 0.0
    ch, need = pool.chosen_in(slot, level)
    weakest = gear.eff(ch[-1]) if len(ch) == need else 0.0
    return max(0.0, gear.w[slot] * (v - weakest))


# ----------------------------------------------------------------------------------------------- 트리
class Tree:
    """skill_trees.json(서리)의 모양을 그대로 쓴다. 트리가 없는 마녀는 spec 프리셋에서 같은 모양을 가정한다."""

    def __init__(self, cfg):
        t = cfg.data["data.tree"]
        self.nodes = {}
        for n in t["nodes"]:
            self.nodes[n["id"]] = {"tier": n["tier"], "branch": n["branch"], "max": n["max_rank"], "req": n["requires"], "min_spent": n["min_spent"]}
        self.branches = [b["id"] for b in t["branches"] if b["id"] != "oath"]
        self.by_branch = {b: sorted([i for i, n in self.nodes.items() if n["branch"] == b], key=lambda i: self.nodes[i]["tier"]) for b in self.branches}
        self.common = {i: n for i, n in self.nodes.items() if n["branch"] == "oath"}
        self.tier_levels = [x["level"] for x in t["tiers"]] if cfg["tree.levels_mode"] == "data" else list(cfg["tree.levels_spec"])
        self.w = cfg["tree.tier_w"]
        self.total_ranks = sum(n["max"] for n in self.nodes.values())
        self._ref = {}

    def keystone(self):
        return max(self.common, key=lambda i: self.nodes[i]["tier"])

    def by_tier_common(self, tier):
        return [i for i, n in self.common.items() if n["tier"] == tier]

    def plan(self, policy, fb):
        b = self.branches[fb % len(self.branches)]
        mine = self.by_branch[b]
        others = [self.by_branch[o] for o in self.branches if o != b]
        n = self.nodes
        vig = self.by_tier_common(1)
        t2c = self.by_tier_common(2)
        ks = self.keystone()
        ward = [i for i in t2c if n[i]["req"]]
        favor = [i for i in t2c if not n[i]["req"]]
        full = lambda ids: [(i, n[i]["max"]) for i in ids]
        fill = [(o[0], n[o[0]]["max"]) for o in others]
        if policy == "focus":
            plan = full(mine) + full(vig) + full(ward) + full(favor) + [(ks, 1)] + fill
        elif policy == "balanced":
            plan = []
            for tier in range(3):
                for br in self.branches:
                    ids = self.by_branch[br]
                    if tier < len(ids):
                        plan.append((ids[tier], min(2, n[ids[tier]]["max"])))
            plan += full(vig) + full(favor) + full(ward) + [(ks, 1)]
            for br in self.branches:
                plan += full(self.by_branch[br])
        else:  # recommended
            plan = [(mine[0], 3)] + [(mine[1], n[mine[1]]["max"])] + full(favor) + [(mine[0], n[mine[0]]["max"])] + full(mine[2:]) \
                + full(vig) + [(ks, 1)] + full(ward) + fill
        return plan

    def can(self, ranks, node, level, spent):
        n = self.nodes[node]
        if ranks.get(node, 0) >= n["max"]:
            return False
        if level < self.tier_levels[n["tier"] - 1]:
            return False
        if spent < n["min_spent"]:
            return False
        for r, rk in n["req"].items():
            if ranks.get(r, 0) < rk:
                return False
        return True

    def invest(self, ranks, level, free, plan):
        done = []
        spent = sum(ranks.values())
        while free > 0:
            for node, target in plan:
                if ranks.get(node, 0) < target and self.can(ranks, node, level, spent):
                    ranks[node] = ranks.get(node, 0) + 1
                    free -= 1
                    spent += 1
                    done.append(node)
                    break
            else:
                break
        return done

    def value(self, ranks):
        return sum(r * self.w[self.nodes[i]["tier"] - 1] for i, r in ranks.items())

    def ref_value(self, cfg, level_cap, points):
        key = (level_cap, points)
        if key not in self._ref:
            ranks = {}
            self.invest(ranks, level_cap, points, self.plan("recommended", 0))
            self._ref[key] = self.value(ranks)
        return self._ref[key]


# ----------------------------------------------------------------------------------------------- 한 플레이어
class Witch:
    __slots__ = ("name", "xp", "level", "ranks", "fb", "first", "sp_bonus", "qdone", "bounties", "depth", "unlocked", "recent", "deepest_win",
                 "plan", "boss_won", "tier_seen", "last_load", "runs")

    def __init__(self, name):
        self.name = name
        self.xp = 0.0
        self.level = 1
        self.ranks = {}
        self.fb = 0
        self.first = set()
        self.sp_bonus = 0
        self.qdone = set()
        self.bounties = []
        self.depth = 1
        self.unlocked = 1
        self.recent = []
        self.deepest_win = 0
        self.plan = None
        self.boss_won = False
        self.tier_seen = set()
        self.last_load = None
        self.runs = 0


def level_of(cfg, xp):
    th = cfg["data.xp_thresholds"]
    return min(int(cfg["data.level_cap"]), bisect.bisect_right(th, xp))


def run_xp(cfg, f, win, grade):
    """G1 2.1: 봉인 진척(구역별 150/220/280을 진행에 비례) + 수호자 + 우두머리 + 완주."""
    zs, se = cfg["run.zone_start"], cfg["run.seal_end"]
    sx = cfg["data.seal_xp"]
    x = 0.0
    for z in range(3):
        a, b = zs[z], se[z]
        x += sx[z] * min(1.0, max(0.0, (f - a) / (b - a)))
    for i in (0, 1):
        if f >= cfg["run.champ_t"][i]:
            x += cfg["data.champion_xp"][i]
    if win:
        x += cfg["data.boss_xp"] + cfg["data.victory_xp"]
    x *= cfg["xp.scale"]
    if cfg["prog.grade_xp_on"]:
        x *= 1 + cfg["prog.grade_xp_bps"][grade - 1] / 10000.0
    return x


def objective_met(obj, summ, win, no_potion):
    if obj == "champion0":
        return summ["champion0"]
    if obj == "boss":
        return win
    if obj == "carrier":
        return summ["carrier"] > 0
    if obj == "rituals2":
        return summ["rituals"] >= 2
    if obj == "no_potion_win":
        return win and no_potion
    if obj == "elites6":
        return summ["elites"] >= 6
    if obj == "chests5":
        return summ["chests"] >= 5
    if obj == "shrines3":
        return summ["shrines"] >= 3
    if obj == "grade3":
        return summ["grade"] >= 3
    return False


class Player:
    def __init__(self, cfg, loot, gear, tree, ptype, plan, seed):
        self.cfg, self.loot, self.g, self.tree = cfg, loot, gear, tree
        self.t = ptype
        self.rng = random.Random(seed)
        self.plan = plan
        self.w = {n: Witch(n) for n in WITCHES}
        for i, n in enumerate(WITCHES):
            self.w[n].fb = self.rng.randrange(3)
        self.shared = cfg["gear.share"] == "shared"
        self.pools = {"all": Pool(gear)} if self.shared else {n: Pool(gear) for n in WITCHES}
        self.essence = 0
        self.shop_open = cfg["shop.open_by"] == "start"
        self.potion_bought = 0
        self.ev = {"shop_open": 0} if self.shop_open else {}
        self.sal = cfg["essence.salvage"]
        self.vref = tree.ref_value(cfg, int(cfg["data.level_cap"]), (int(cfg["data.level_cap"]) - 1) * int(cfg["data.points_per_level"]) + int(cfg["data.first_kill_points"]))
        self.income = {"salvage": 0, "grade": 0, "quest": 0}
        self.spent = {"potion": 0, "shop": 0, "gamble": 0, "forge": 0, "reroll": 0}
        self.src_items = {}
        self.fit = win_fit(cfg, ptype)
        self.thr = cfg["depth.threat"]
        self.items_total = 0
        self.secs = 0.0

    def pool(self, w):
        return self.pools["all"] if self.shared else self.pools[w]

    def mark(self, name, r):
        if name not in self.ev:
            self.ev[name] = r

    def tree_power(self, ws):
        if not self.cfg["tree.has." + ws.name] or self.vref <= 0:
            return 0.0, 0.0
        x = self.tree.value(ws.ranks) / self.vref
        return self.cfg["tree.p_full"] * x, self.cfg["tree.s_full"] * x

    def points_total(self, ws):
        cfg = self.cfg
        return (ws.level - 1) * int(cfg["data.points_per_level"]) + len(ws.first) + ws.sp_bonus

    def power_now(self, ws):
        items = self.pool(ws.name).loadout(ws.level)
        pg, sg = self.g.power(items)
        pt, st = self.tree_power(ws)
        return items, pg, pt, (1 + pg) * (1 + pt) * math.sqrt((1 + sg) * (1 + st))

    def win_prob(self, ws, M, depth):
        f = self.fit
        z = f["a"] + f["k"] * math.log(max(1e-6, M) / self.thr[depth - 1]) + self.cfg["witch.logit_offset." + ws.name]
        return min(self.cfg["win.ceil"], max(self.cfg["win.floor"], f["cap"] * sigmoid(z)))

    def add_item(self, it, ws):
        ev = self.pool(ws.name).add(it)
        if ev is not None:
            v = self.sal[QUAL[ev[3]]]
            self.income["salvage"] += v
            self.essence += v

    # ---------------------------------------------------------------------------------- 마을
    def town(self, ws, r, rec):
        cfg, rng, g = self.cfg, self.rng, self.g
        # 트리 투자
        if cfg["tree.has." + ws.name]:
            if ws.plan is None:
                ws.plan = self.tree.plan(cfg["players.%s.tree_policy" % self.t], ws.fb)
            free = self.points_total(ws) - sum(ws.ranks.values())
            done = self.tree.invest(ws.ranks, ws.level, free, ws.plan)
            if done:
                rec["invested"] = len(done)
                if self.tree.keystone() in done:
                    self.mark("keystone", r)
                for br in self.tree.branches:
                    if all(ws.ranks.get(i, 0) >= self.tree.nodes[i]["max"] for i in self.tree.by_branch[br]):
                        self.mark("branch_done", r)
        if not self.shop_open:
            return
        pool = self.pool(ws.name)
        gl = cfg["depth.zone_levels"][max(0, ws.deepest_win - 1)][2] if ws.deepest_win else cfg["depth.zone_levels"][0][2]
        reserve = cfg["spend.reserve"]
        if cfg["forge.first"]:
            self.sink_forge(ws, pool, r)
        # 회수약 상한(1회성)
        ups = cfg["shop.potion_upgrades"]
        while self.potion_bought < len(ups) and self.essence - reserve >= ups[self.potion_bought]:
            self.essence -= ups[self.potion_bought]
            self.spent["potion"] += ups[self.potion_bought]
            self.potion_bought += 1
            self.mark("potion%d" % self.potion_bought, r)
            rec["purchase"] = rec.get("purchase", 0) + 1
        # 진열
        qs = cfg["shop.quality"]
        stock = []
        for _ in range(int(cfg["shop.stock"])):
            q = bisect.bisect_right(self.loot._cum(qs), rng.random() * sum(qs))
            s = rng.randrange(7)
            price = cfg["shop.price." + QUAL[q]] * (gl / 12.0) * (cfg["shop.jewelry_mult"] if s >= 5 else 1.0)
            stock.append([s, q, gl, price])
        bought = True
        while bought:
            bought = False
            best = None
            for st in stock:
                if st[3] > self.essence - reserve:
                    continue
                it = g.make(rng, st[0], st[1], st[2])
                gain = slot_gain(g, pool, st[0], g.eff(it), st[2], ws.level)
                if gain > 0 and (best is None or gain / st[3] > best[0]):
                    best = (gain / st[3], st, it)
            if best:
                _, st, it = best
                stock.remove(st)
                self.essence -= int(round(st[3]))
                self.spent["shop"] += int(round(st[3]))
                self.add_item(it, ws)
                rec["purchase"] = rec.get("purchase", 0) + 1
                self.mark("first_buy", r)
                bought = True
        # 도박: 칸을 고른다. 기대 가치가 지금 낀 것보다 높은 칸 가운데 (몫 × 이득 / 값)이 큰 칸
        if cfg["gamble.enabled"]:
            gq = cfg["gamble.quality"]
            ev_v = sum(gq[i] * g.qv[i] for i in range(5)) / max(1e-9, sum(gq)) * g.ilf[gl]
            gp = cfg["gamble.price"]
            for _ in range(30):
                best = None
                for s, sn in enumerate(SLOTS):
                    price = int(round(gp[sn] * gl / 12.0))
                    if price > self.essence - reserve:
                        continue
                    gain = slot_gain(g, pool, s, ev_v, gl, ws.level)
                    if gain > 0 and (best is None or gain / price > best[0]):
                        best = (gain / price, s, price)
                if not best:
                    break
                _, s, price = best
                self.essence -= price
                self.spent["gamble"] += price
                q = bisect.bisect_right(self.loot._cum(gq), rng.random() * sum(gq))
                self.add_item(g.make(rng, s, q, gl), ws)
                rec["purchase"] = rec.get("purchase", 0) + 1
                self.mark("first_buy", r)
        if not cfg["forge.first"]:
            self.sink_forge(ws, pool, r)

    def sink_forge(self, ws, pool, r):
        """강화·다시 굴리기(둘 다 사용자 보류. 기본 꺼짐). 칸 가중이 큰 장비부터."""
        cfg, rng, g = self.cfg, self.rng, self.g
        reserve = cfg["spend.reserve"]
        if cfg["forge.enabled"]:
            costs, succ = cfg["forge.costs"], cfg["forge.success"]
            for it in sorted(pool.loadout(ws.level), key=lambda x: -g.w[x[1]]):
                fails = 0
                while it[5] < len(costs) and self.essence - reserve >= costs[it[5]]:
                    self.essence -= costs[it[5]]
                    self.spent["forge"] += costs[it[5]]
                    if fails >= cfg["forge.pity"] or rng.random() < succ[it[5]]:
                        it[5] += 1
                        fails = 0
                        if it[5] == len(costs):
                            self.mark("forge5", r)
                    else:
                        fails += 1
        if cfg["reroll.enabled"]:
            for it in sorted(pool.loadout(ws.level), key=lambda x: -g.w[x[1]]):
                n = 0
                while n < cfg["reroll.max"]:
                    c = cfg["reroll.cost"] * (1 + 0.5 * n)
                    if self.essence - reserve < c or it[2] >= g.qv[it[3]] * g.ilf[it[4]] * (1 + 0.6 * g.sp[it[3]]):
                        break
                    self.essence -= int(c)
                    self.spent["reroll"] += int(c)
                    it[2] = g.qv[it[3]] * g.ilf[it[4]] * (1.0 + g.sp[it[3]] * (rng.random() * 2 - 1))
                    n += 1

    # ---------------------------------------------------------------------------------- 한 판
    def run_once(self, r):
        cfg, rng, g = self.cfg, self.rng, self.g
        wname = self.plan[(r - 1) % len(self.plan)]
        ws = self.w[wname]
        ws.runs += 1
        rec = {"r": r, "witch": wname}
        # 깊이 고르기
        maxd = int(cfg["depth.max"])
        win_n = int(cfg["depth.window"])
        if ws.depth < min(maxd, ws.unlocked) and len(ws.recent) >= win_n and sum(ws.recent[-win_n:]) / win_n >= cfg["depth.up_rate"]:
            ws.depth += 1
            ws.recent = []
        elif ws.depth > 1 and len(ws.recent) >= win_n and sum(ws.recent[-win_n:]) / win_n < cfg["depth.down_rate"]:
            ws.depth -= 1
            ws.recent = []
        depth = ws.depth
        if depth >= 2:
            self.mark("depth2_in", r)
        if depth >= 3:
            self.mark("depth3_in", r)
        items, pg, pt, M = self.power_now(ws)
        prob = self.win_prob(ws, M, depth)
        win = rng.random() < prob
        if win:
            f = 1.0
        else:
            f = cfg["players.%s.defeat_f_lo" % self.t] + rng.random() * (cfg["players.%s.defeat_f_hi" % self.t] - cfg["players.%s.defeat_f_lo" % self.t])
        ws.recent.append(1 if win else 0)
        rec.update(depth=depth, win=win, f=f, M=M, pg=pg, pt=pt, pw=prob, lv0=ws.level)
        self.secs += (cfg["run.secs_win"] * f) + cfg["run.town_secs"]
        first_boss = win and not ws.boss_won
        drops, summ = run_events(cfg, self.loot, rng, self.t, wname, depth, f, win, first_boss)
        no_potion = win and rng.random() < cfg["players.%s.p_no_potion" % self.t]
        # 경험치와 첫 처치 포인트
        xp = run_xp(cfg, f, win, summ["grade"])
        pts0 = self.points_total(ws)
        used_loaded = {it[0] for it in items}
        if win:
            ws.boss_won = True
            ws.deepest_win = max(ws.deepest_win, depth)
            ws.unlocked = max(ws.unlocked, min(maxd, depth + 1))
            if depth == 1:
                ws.first.add("boss")
            if ws.unlocked >= 2:
                self.mark("depth2", r)
            if ws.unlocked >= 3:
                self.mark("depth3", r)
            self.mark("first_win", r)
            if depth >= 2:
                self.mark("depth2_clear", r)
        if summ["champion0"]:
            ws.first.add("champion:0")
        if summ["champion1"]:
            ws.first.add("champion:1")
        # 재: 단계(승리 판)
        if win:
            gi = cfg["essence.grade_per_step"] * summ["grade"]
            self.income["grade"] += gi
            self.essence += gi
        # 장비
        pool = self.pool(wname)
        for src, s, q, il in drops:
            self.src_items[src] = self.src_items.get(src, 0) + 1
            self.items_total += 1
            self.add_item(g.make(rng, s, q, il), ws)
        # 퀘스트
        qn = 0
        if cfg["quests.enabled"]:
            qn = self.quests(ws, summ, win, no_potion, xp, rec, r, depth)
            xp = rec.pop("_xp")
        # 레벨
        ws.xp += xp
        lv1 = level_of(cfg, ws.xp)
        rec["xp"] = xp
        ws.level = lv1
        rec["lv1"] = lv1
        rec["pts_gain"] = self.points_total(ws) - pts0
        for ti, tl in enumerate(self.tree.tier_levels):
            if lv1 >= tl and (wname, ti) not in ws.tier_seen:
                ws.tier_seen.add((wname, ti))
                self.mark("tier%d" % (ti + 1), r)
        for m in (6, 12, 20):
            if lv1 >= m:
                self.mark("lv%d" % m, r)
        if lv1 >= int(cfg["data.level_cap"]):
            self.mark("lv_cap", r)
        return ws, rec, summ, pool, used_loaded

    def quests(self, ws, summ, win, no_potion, xp, rec, r, depth):
        cfg, rng = self.cfg, self.rng
        done = []
        story = cfg["quests.story"]
        for q in story:
            if q["id"] in ws.qdone or (q.get("requires") and q["requires"] not in ws.qdone):
                continue
            if objective_met(q["obj"], summ, win, no_potion):
                done.append(q)
        for q in cfg["quests.side"]:
            if q["id"] not in ws.qdone and objective_met(q["obj"], summ, win, no_potion):
                done.append(q)
        gate = story[0]["id"] if story else None
        if gate is None or gate in ws.qdone:
            for q in ws.bounties:
                if objective_met(q["obj"], summ, win, no_potion):
                    done.append(q)
        zl = cfg["depth.zone_levels"][depth - 1]
        for q in done:
            rw = q["reward"]
            self.income["quest"] += rw.get("essence", 0)
            self.essence += rw.get("essence", 0)
            xp += rw.get("xp", 0)
            ws.sp_bonus += rw.get("sp", 0)
            if "item" in rw:
                s, ql = SLOT_IDX[rw["item"][0]], QUAL.index(rw["item"][1])
                self.add_item(self.g.make(rng, s, ql, min(30, zl[1] + 2)), ws)
            if rw.get("unlock") == "shop" and cfg["shop.open_by"] == "quest":
                self.shop_open = True
                self.mark("shop_open", r)
            if q["id"] not in [b["id"] for b in cfg["quests.bounty_pool"]]:
                ws.qdone.add(q["id"])
        ws.bounties = []
        if gate is None or gate in ws.qdone:
            pool = list(cfg["quests.bounty_pool"])
            offers = rng.sample(pool, min(len(pool), int(cfg["quests.bounty_offers"])))
            ws.bounties = rng.sample(offers, min(len(offers), int(cfg["quests.bounty_take"])))
        rec["quests"] = len(done)
        rec["_xp"] = xp
        if done:
            self.mark("first_quest", r)
        return len(done)


def play_player(cfg, loot, gear, tree, ptype, plan, seed, n_runs):
    P = Player(cfg, loot, gear, tree, ptype, plan, seed)
    trace = []
    for r in range(1, n_runs + 1):
        inc0 = sum(P.income.values())
        spent0 = sum(P.spent.values())
        ws, rec, summ, pool, used_ids = P.run_once(r)
        rec["income"] = sum(P.income.values()) - inc0
        P.town(ws, r, rec)
        after_items = P.pool(ws.name).loadout(ws.level)
        after = {it[0] for it in after_items}
        pg_after, _ = P.g.power(after_items)
        # 장비 교체: 다음 출발 때 새 장비가 끼워지고 장비 힘이 늘었다
        rec["gear_replaced"] = bool(after - used_ids) and pg_after > rec["pg"] + 1e-9
        if rec["gear_replaced"]:
            P.mark("first_gear", r)
        rec["spent"] = sum(P.spent.values()) - spent0
        rec["stock"] = P.essence
        rec["pg_next"] = pg_after
        rec["pt_next"], _ = P.tree_power(ws)
        rec["lvup"] = rec["lv1"] > rec["lv0"]
        rec["pts_up"] = rec["pts_gain"] > 0
        rec["quest_done"] = rec.get("quests", 0) > 0
        rec["growth"] = rec["lvup"] or rec["pts_up"] or rec["gear_replaced"] or rec["quest_done"]
        rec["growth_wide"] = rec["growth"] or rec.get("purchase", 0) > 0 or rec.get("invested", 0) > 0
        rec["secs"] = P.secs
        rec["lv_all"] = {n: P.w[n].level for n in WITCHES}
        rec["depth_all"] = {n: P.w[n].depth for n in WITCHES}
        rec["spent_by"] = dict(P.spent)
        rec["inc_by"] = dict(P.income)
        rec["pts_all"] = {n: P.points_total(P.w[n]) for n in WITCHES}
        rec["spentpts"] = {n: sum(P.w[n].ranks.values()) for n in WITCHES}
        rec["qdone_all"] = {n: len(P.w[n].qdone) for n in WITCHES}
        trace.append(rec)
    return P, trace


# ----------------------------------------------------------------------------------------------- 집계
def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def pq(xs, q):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    i = min(len(xs) - 1, max(0, int(round(q * (len(xs) - 1)))))
    return xs[i]


def longest_gap(flags):
    best = cur = 0
    for g in flags:
        if g:
            cur = 0
        else:
            cur += 1
            best = max(best, cur)
    return best


def seed_for(base, ptype, plan, i):
    return (zlib.crc32(("%s|%s|%d" % (ptype, "".join(plan), i)).encode()) ^ (base * 2654435761)) & 0x7FFFFFFF


def simulate_group(cfg, ptype, plan, n_runs, n_players, seed0, tree=None):
    loot = Loot(cfg)
    tree = tree or Tree(cfg)
    results = []
    for i in range(n_players):
        gear = Gear(cfg)
        P, tr = play_player(cfg, loot, gear, tree, ptype, plan, seed_for(seed0, ptype, plan, i), n_runs)
        results.append((P, tr))
    return results


def summarize_group(cfg, results, n_runs, plan):
    n = len(results)
    cap = int(cfg["data.level_cap"])
    S = {"players": n, "runs": n_runs, "plan": list(plan)}
    cks = [c for c in CHECKPOINTS if c <= n_runs]
    if n_runs not in cks:
        cks.append(n_runs)
    rows = {}
    for c in cks:
        def col(fn):
            return [fn(tr[c - 1]) for P, tr in results]
        lv_by_w = {w: med(col(lambda x, w=w: x["lv_all"][w])) for w in plan}
        rows[c] = {
            "lv": {w: lv_by_w[w] for w in sorted(set(plan), key=WITCHES.index)},
            "pts": {w: med(col(lambda x, w=w: x["pts_all"][w])) for w in sorted(set(plan), key=WITCHES.index)},
            "spentpts": {w: med(col(lambda x, w=w: x["spentpts"][w])) for w in sorted(set(plan), key=WITCHES.index)},
            "wins": med([sum(1 for x in tr[:c] if x["win"]) for P, tr in results]),
            "win_recent": med([sum(1 for x in tr[max(0, c - 10):c] if x["win"]) / float(len(tr[max(0, c - 10):c])) for P, tr in results]),
            "pg": med(col(lambda x: x["pg_next"])),
            "pt": med(col(lambda x: x["pt_next"])),
            "M": med(col(lambda x: x["M"])),
            "pw": med(col(lambda x: x["pw"])),
            "stock": med(col(lambda x: x["stock"])),
            "depth": med(col(lambda x: max(x["depth_all"].values()))),
            "quests": med(col(lambda x: sum(x["qdone_all"].values()))),
            "hours": med(col(lambda x: x["secs"] / 3600.0)),
        }
    S["checkpoints"] = rows
    S["checkpoint_list"] = cks
    # 눈에 보이는 성장
    for horizon in sorted({min(30, n_runs), n_runs}):
        key = "h%d" % horizon
        S[key] = {
            "growthless_share": statistics.mean([sum(1 for x in tr[:horizon] if not x["growth"]) / float(horizon) for P, tr in results]),
            "growthless_wide_share": statistics.mean([sum(1 for x in tr[:horizon] if not x["growth_wide"]) / float(horizon) for P, tr in results]),
            "longest_gap_med": med([longest_gap([x["growth"] for x in tr[:horizon]]) for P, tr in results]),
            "longest_gap_p90": pq([longest_gap([x["growth"] for x in tr[:horizon]]) for P, tr in results], 0.9),
            "longest_gap_wide_med": med([longest_gap([x["growth_wide"] for x in tr[:horizon]]) for P, tr in results]),
            "levelup_gap_med": med([longest_gap([x["lvup"] for x in tr[:horizon] if x["lv0"] < cap]) for P, tr in results]),
            "gear_replaced_share": statistics.mean([sum(1 for x in tr[:horizon] if x["gear_replaced"]) / float(horizon) for P, tr in results]),
            "income_per_run": med([sum(x["income"] for x in tr[:horizon]) / float(horizon) for P, tr in results]),
            "spent_per_run": med([sum(x["spent"] for x in tr[:horizon]) / float(horizon) for P, tr in results]),
            "stock_end": med([tr[horizon - 1]["stock"] for P, tr in results]),
            "ratio": med([(sum(x["income"] for x in tr[:horizon]) / float(sum(x["spent"] for x in tr[:horizon]))) if sum(x["spent"] for x in tr[:horizon]) > 0 else None for P, tr in results]),
            "no_sink_share": statistics.mean([1.0 if sum(x["spent"] for x in tr[:horizon]) == 0 else 0.0 for P, tr in results]),
            "unspendable_share": med([tr[horizon - 1]["stock"] / max(1.0, float(sum(x["income"] for x in tr[:horizon]))) for P, tr in results]),
        }
    # 장비 포화: 마지막 장비 힘의 95%에 처음 닿은 판
    sat = []
    for P, tr in results:
        final = tr[-1]["pg_next"]
        run = None
        for x in tr:
            if x["pg_next"] >= 0.95 * final:
                run = x["r"]
                break
        sat.append(run)
    S["gear_sat_run"] = med(sat)
    # 마지막 20% 구간에서 더 좋은 장비가 안 나오는 연속 판(최장)
    S["gear_dry_run_med"] = med([longest_gap([x["gear_replaced"] for x in tr]) for P, tr in results])
    # 이벤트
    evs = {}
    names = set()
    for P, tr in results:
        names.update(P.ev.keys())
    for nm in sorted(names):
        vals = [P.ev.get(nm) for P, tr in results]
        got = [v for v in vals if v is not None]
        evs[nm] = {"median": med(got), "reached": len(got) / float(n), "p10": pq(got, 0.1), "p90": pq(got, 0.9)}
    S["events"] = evs
    # 벽: 첫 승리, 승률 0.5가 되는 판
    S["first_win_med"] = med([P.ev.get("first_win") for P, tr in results])
    S["never_won_share"] = sum(1 for P, tr in results if "first_win" not in P.ev) / float(n)
    pw50 = []
    for P, tr in results:
        run = None
        for x in tr:
            if x["pw"] >= 0.5:
                run = x["r"]
                break
        pw50.append(run)
    S["pw50_run_med"] = med(pw50)
    S["pw50_reached"] = sum(1 for v in pw50 if v is not None) / float(n)
    # 재 지출 구성
    S["spent_by"] = {k: med([tr[-1]["spent_by"][k] for P, tr in results]) for k in results[0][1][-1]["spent_by"]}
    S["income_by"] = {k: med([tr[-1]["inc_by"][k] for P, tr in results]) for k in results[0][1][-1]["inc_by"]}
    S["items_per_run"] = med([P.items_total / float(n_runs) for P, tr in results])
    tot = {}
    for P, tr in results:
        for k, v in P.src_items.items():
            tot[k] = tot.get(k, 0) + v
    tt = float(sum(tot.values())) or 1.0
    S["item_source_share"] = {k: v / tt for k, v in sorted(tot.items())}
    S["win_rate_all"] = statistics.mean([sum(1 for x in tr if x["win"]) / float(n_runs) for P, tr in results])
    S["depth_runs_share"] = {}
    for d in (1, 2, 3):
        S["depth_runs_share"][d] = statistics.mean([sum(1 for x in tr if x["depth"] == d) / float(n_runs) for P, tr in results])
    S["hours_total"] = med([tr[-1]["secs"] / 3600.0 for P, tr in results])
    return S


JOBS = 1


def pmap(fn, tasks):
    """작업 목록을 JOBS개 프로세스로 나눠 돌린다(결정론: 작업마다 독립 시드, 순서 유지)."""
    if JOBS <= 1 or len(tasks) <= 1:
        return [fn(t) for t in tasks]
    with multiprocessing.Pool(min(JOBS, len(tasks))) as pool:
        return pool.map(fn, tasks, chunksize=1)


def _flow_task(args):
    cfg, t, plan, n_runs, n_players, seed0 = args
    res = simulate_group(cfg, t, plan, n_runs, n_players, seed0, Tree(cfg))
    return summarize_group(cfg, res, n_runs, plan)


def run_flow(cfg, types, plans, n_runs, n_players, seed0):
    keys = [(pn, t) for pn in plans for t in types]
    outs = pmap(_flow_task, [(cfg, t, plans[pn], n_runs, n_players, seed0) for pn, t in keys])
    out = {pn: {} for pn in plans}
    for (pn, t), S in zip(keys, outs):
        out[pn][t] = S
    return out


# ----------------------------------------------------------------------------------------------- 목표와 견줌
def fmt(x, nd=1):
    if x is None:
        return "-"
    if isinstance(x, float):
        return ("%." + str(nd) + "f") % x
    return str(x)


def runs_str(ev, key):
    e = ev.get(key)
    if not e:
        return "-"
    s = fmt(e["median"], 0)
    if e["reached"] < 0.995:
        s += "(%d%%)" % round(e["reached"] * 100)
    return s


def checks_for(cfg, flow, n_runs):
    """명세의 목표와 견줘 벗어난 곳. 각 줄 = (이름, 값, 목표, 판정(None=참고), 출처). 목표를 결과에 맞춰 옮기지 않는다."""
    rows = []
    h = "h30" if n_runs >= 30 else "h%d" % n_runs
    for pname, per in flow.items():
        for t, S in per.items():
            if len(set(S["plan"])) != 1:
                continue
            w = S["plan"][0]
            ev = S["events"]
            tag = "%s/%s" % (TYPE_KO[t], WITCH_KO[w])
            g = S[h]
            rows.append(("성장 없는 판 비율(첫 %s판) %s" % (h[1:], tag), g["growthless_share"], "<= 0.15", g["growthless_share"] <= 0.15, "작성자 가정(D11 D 보상 공백 취지)"))
            rows.append(("성장 없는 연속 판 최장 %s" % tag, g["longest_gap_med"], "<= 3", (g["longest_gap_med"] or 0) <= 3, "G1 10.2(레벨 정체 3판 이하)를 네 가지 성장으로 넓힘"))
            if g["ratio"] is not None:
                rows.append(("재 수입 ÷ 지출(첫 %s판) %s" % (h[1:], tag), g["ratio"], "0.8~1.5", 0.8 <= g["ratio"] <= 1.5, "작성자 가정(명세에 값 없음)"))
            else:
                rows.append(("재의 쓸 곳(첫 %s판) %s" % (h[1:], tag), "없음", "지출 > 0", False, "D6 3.1: 재는 쓸 곳이 사실상 없다(지금 데이터)"))
            if t == "skilled":
                c1 = S["checkpoints"].get(1)
                if c1:
                    rows.append(("첫 판 끝 레벨(승리 판) %s" % tag, c1["lv"][w], ">= 3", c1["lv"][w] >= 3, "G1 10.2"))
                for key, lo, hi, nm in (("lv6", 2, 4, "Lv 6 도달"), ("lv12", 7, 10, "Lv 12 도달"), ("lv20", 22, 30, "Lv 20 도달(포인트 상한)"), ("branch_done", 8, 12, "한 갈래 1~3단 완성")):
                    e = ev.get(key)
                    v = e["median"] if e else None
                    rows.append(("%s 판 수 %s" % (nm, tag), v, "%d~%d" % (lo, hi), (v is not None and lo <= v <= hi), "G1 10.2(승리만 하는 판 기준 목표를 승률 반영 모델에 건 것)"))
                e = ev.get("keystone")
                v = e["median"] if e else None
                rows.append(("키스톤을 사는 판 %s" % tag, v, "약 13(10~18)", (v is not None and 10 <= v <= 18), "D12 C4(Lv 15 = 약 13판)"))
                e = ev.get("depth2_clear")
                v = e["median"] if e else None
                rows.append(("깊이 2를 처음 이기는 판 %s" % tag, v, "<= 28", (v is not None and v <= 28), "D6 1.2(3시간·25~28판 안에 깊이 2 클리어)"))
                rows.append(("장비 힘이 포화하는 판 %s" % tag, S["gear_sat_run"], ">= 25", (S["gear_sat_run"] or 0) >= 25, "작성자 가정(D6 1.2: 25~28판에 목표 장비를 노리므로 그 전에 포화하면 안 됨)"))
            if cfg["forge.enabled"] and "forge5" in ev:
                v = ev["forge5"]["median"]
                rows.append(("강화 +5 한 점까지의 판 수 %s" % tag, v, "4~8", 4 <= v <= 8, "D12 D4.4(sim_economy로 맞추라고 한 값)  도달 %d%%" % round(ev["forge5"]["reached"] * 100)))
            if t == "poor":
                rows.append(("못함: 첫 승리 판 %s" % tag, S["first_win_med"], "참고", None, "목표 없음(D11 G1 패배 목표는 자동 조작 기준)"))
                rows.append(("못함: 승률 0.5에 닿는 판 %s" % tag, S["pw50_run_med"], "참고", None, "목표 없음. 도달 %d%%" % round(S["pw50_reached"] * 100)))
    return rows


# ----------------------------------------------------------------------------------------------- 출력
def render_flow(cfg, flow, n_runs, n_players, seed0, title=""):
    L = []
    L.append("=" * 100)
    L.append("경제·성장 흐름 — " + BANNER)
    L.append("프리셋 %s · 드랍 %s · 트리 단 %s · 장비 %s · 강화 %s · 판 %d · 플레이어 %d명/유형 · 시드 %d %s" % (
        cfg.preset, cfg["loot.mode"], cfg["tree.levels_mode"], cfg["gear.share"], "켬" if cfg["forge.enabled"] else "꺼짐(보류)", n_runs, n_players, seed0, title))
    L.append("=" * 100)
    for pname, per in flow.items():
        L.append("")
        L.append("■ %s" % pname)
        for t, S in per.items():
            plan = S["plan"]
            ws = sorted(set(plan), key=WITCHES.index)
            L.append("")
            L.append("  [%s · %s]  승률 평균 %.0f%% · 깊이별 판 비율 %s · 플레이 시간 %s시간(중앙값)" % (
                TYPE_KO[t], "·".join(WITCH_KO[w] for w in ws) + ("(번갈아)" if len(ws) > 1 else ""), S["win_rate_all"] * 100,
                " ".join("깊이%d %.0f%%" % (d, v * 100) for d, v in S["depth_runs_share"].items() if v > 0), fmt(S["hours_total"], 1)))
            hdr = "   판   " + " ".join("%7s" % ("Lv" + WITCH_KO[w]) for w in ws) + "  포인트(쓴)   승(누적) 최근10승률  장비힘  트리힘   힘M   승률p   재고  깊이 퀘스트"
            L.append(hdr)
            for c in S["checkpoint_list"]:
                r = S["checkpoints"][c]
                L.append("  %4d  %s  %s  %7s  %8s  %+6.0f%% %+6.0f%%  %5.2f  %5.0f%%  %5s   %3s  %4s" % (
                    c, " ".join("%7s" % fmt(r["lv"][w], 0) for w in ws),
                    " ".join("%2s(%2s)" % (fmt(r["pts"][w], 0), fmt(r["spentpts"][w], 0)) for w in ws)[:24].ljust(12),
                    fmt(r["wins"], 0), "%.0f%%" % (r["win_recent"] * 100), r["pg"] * 100, r["pt"] * 100, r["M"], r["pw"] * 100, fmt(r["stock"], 0), fmt(r["depth"], 0), fmt(r["quests"], 0)))
            ev = S["events"]
            L.append("   열림(몇 판 마친 뒤, 중앙값; 괄호는 도달한 비율): 트리 단2 %s · 단3 %s · 단4 %s · 키스톤 %s · 상점 %s · 첫 구매 %s · 회수약+1 %s · 깊이2 열림 %s · 입장 %s · 깊이2 클리어 %s · 깊이3 열림 %s · 첫 퀘스트 %s · 첫 승리 %s · Lv상한 %s" % (
                runs_str(ev, "tier2"), runs_str(ev, "tier3"), runs_str(ev, "tier4"), runs_str(ev, "keystone"), runs_str(ev, "shop_open"),
                runs_str(ev, "first_buy"), runs_str(ev, "potion1"), runs_str(ev, "depth2"), runs_str(ev, "depth2_in"), runs_str(ev, "depth2_clear"), runs_str(ev, "depth3"), runs_str(ev, "first_quest"), runs_str(ev, "first_win"), runs_str(ev, "lv_cap")))
            L.append("   레벨 도달 판: Lv6 %s · Lv12 %s · Lv20 %s · 한 갈래 1~3단 완성 %s" % (runs_str(ev, "lv6"), runs_str(ev, "lv12"), runs_str(ev, "lv20"), runs_str(ev, "branch_done")))
            hks = ["h30"] if n_runs <= 30 else ["h30", "h%d" % n_runs]
            for hk in hks:
                if hk not in S:
                    continue
                g = S[hk]
                L.append("   성장 없는 판 [첫 %s판] %.0f%% (재·상점 포함하면 %.0f%%) · 최장 공백 중앙값 %s판(p90 %s, 넓게 %s) · 장비 교체 판 %.0f%% · 재 수입/판 %s, 지출/판 %s, 수입÷지출 %s, 안 쓰고 남은 재 %s%%" % (
                    hk[1:], g["growthless_share"] * 100, g["growthless_wide_share"] * 100, fmt(g["longest_gap_med"], 0), fmt(g["longest_gap_p90"], 0), fmt(g["longest_gap_wide_med"], 0),
                    g["gear_replaced_share"] * 100, fmt(g["income_per_run"], 0), fmt(g["spent_per_run"], 0), fmt(g["ratio"], 2), fmt(g["unspendable_share"] * 100 if g["unspendable_share"] is not None else None, 0)))
            L.append("   장비 힘이 최종의 95%%에 닿는 판 %s · 장비 교체 없는 최장 연속 %s판 · 힘 승률 0.5 도달 %s판(%d%%) · 한 번도 못 이긴 비율 %.0f%%" % (
                fmt(S["gear_sat_run"], 0), fmt(S["gear_dry_run_med"], 0), fmt(S["pw50_run_med"], 0), round(S["pw50_reached"] * 100), S["never_won_share"] * 100))
            L.append("   재 수입 구성 %s · 지출 구성 %s · 장비 %s개/판 · 출처 %s" % (
                " ".join("%s %s" % (k, fmt(v, 0)) for k, v in S["income_by"].items()), " ".join("%s %s" % (k, fmt(v, 0)) for k, v in S["spent_by"].items() if v),
                fmt(S["items_per_run"], 1), " ".join("%s %.0f%%" % (k, v * 100) for k, v in S["item_source_share"].items())))
    return "\n".join(L)


# ----------------------------------------------------------------------------------------------- 대조
PROG_LANCE_LEVELS = [4, 5, 7, 8, 9, 10, 11, 12, 12, 13, 13, 14, 15, 15, 16, 16, 16, 17, 17, 18, 18, 18, 19, 19, 20]
LOOT_D6 = {"items": 44.0, "rare": 4.655, "jewelry": 1.446, "legendary": 0.380, "unique": 0.250, "common": 7.8, "magic": 30.8}
LOOT_TARGETS = {"rare": [3.0, 5.0], "jewelry": [0.6, 1.6], "legendary": [0.25, 0.45], "unique": [0.12, 0.28]}
P10_BUDGET = {"kits.d1_start": ([0.15, 0.30], [0.20, 0.40]), "kits.d1_end": ([0.40, 0.70], [0.40, 0.70]), "kits.d2_mid": ([0.80, 1.30], [0.60, 1.00])}


def sim_progression_levels(local):
    """_local/sim/log/prog_lance.log의 levels_by_run을 읽는다. 없으면 None."""
    p = local / "sim" / "log" / "prog_lance.log"
    if not p.exists():
        return None
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("PROGRESSION_SIM "):
            try:
                return json.loads(line[len("PROGRESSION_SIM "):])["progression"]["lance"]["levels_by_run"]
            except Exception:
                return None
    return None


def xp_all_wins(cfg, n):
    xp, out = 0.0, []
    for _ in range(n):
        xp += run_xp(cfg, 1.0, True, 1)
        out.append(level_of(cfg, xp))
    return out


def loot_expect(cfg, runs=10000, seed=4141, mode="sim_loot", witch="frost"):
    c = cfg.with_value("loot.mode", mode)
    loot = Loot(c)
    rng = random.Random(seed)
    tot = {k: 0 for k in QUAL}
    jew = 0
    items = []
    for _ in range(runs):
        out, _s = run_events(c, loot, rng, "skilled", witch, 1, 1.0, True, False)
        items.append(len(out))
        for src, s, q, il in out:
            tot[QUAL[q]] += 1
            if s >= 5:
                jew += 1
    items.sort()
    n = float(runs)
    return {"items": sum(tot.values()) / n, "rare": tot["rare"] / n, "jewelry": jew / n, "legendary": tot["legendary"] / n, "unique": tot["unique"] / n,
            "common": tot["common"] / n, "magic": tot["magic"] / n, "p10_p50_p90": [items[runs // 10], items[runs // 2], items[runs * 9 // 10]]}


def kit_values(cfg, name):
    g = Gear(cfg)
    items = []
    rng = random.Random(1)
    for s, q, il in cfg[name]:
        it = g.make(rng, SLOT_IDX[s], QUAL.index(q), il)
        it[2] = g.qv[it[3]] * g.ilf[il]
        items.append(it)
    return g.power(items)


def calibrate_text(cfg):
    L = []
    local = find_local()
    L.append("=" * 100)
    L.append("대조(맞춤과 한계) — " + BANNER)
    L.append("=" * 100)
    L.append("")
    L.append("1) 영구 경험치·레벨 — sim_progression.gd(승리만 25판, lance) 의 levels_by_run 과 대조")
    mine = xp_all_wins(cfg, 25)
    ref = sim_progression_levels(local)
    src = "_local/sim/log/prog_lance.log" if ref else "코드에 옮겨 둔 값(_local/sim/log/prog_lance.log, 2026-11-17 실행)"
    ref = ref or PROG_LANCE_LEVELS
    L.append("   기준: %s" % src)
    L.append("   실측 %s" % ref)
    L.append("   모델 %s" % mine)
    L.append("   -> %s" % ("일치(25판 모두)" if mine == ref else "불일치 %d판" % sum(1 for a, b in zip(mine, ref) if a != b)))
    L.append("   한계: 실제 코어의 경험치는 처치 수에 묶이지 않고 봉인 진척에 묶인다. 이 모델의 패배 판 경험치는 진행 f에 비례하는 근사다(대조할 패배 판 실측 없음).")
    L.append("   새로 대조하려면: python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_progression.gd -- --runs=25 --policy=lance --seed-base=1000  (이 도구는 Godot를 돌리지 않는다)")
    L.append("")
    L.append("2) 드랍 — sim_loot.gd(1만 판, 냉기, 시드 4141)와 대조. 모델은 sim_loot의 가정(일반 처치 [1245,1941,1587], 구역당 정예 2, 운반자 1)을 그대로 쓴다")
    lp = local / "sim" / "log"
    has = any("LOOT_SIM" in f.read_text(encoding="utf-8", errors="replace") for f in lp.glob("*.log")) if lp.exists() else False
    L.append("   기준: %s" % ("_local 의 LOOT_SIM 줄" if has else "대조할 실측 파일 없음(_local에 LOOT_SIM 출력이 없다) — 이 명령으로 만들 수 있다: python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000.  아래는 D6 0절에 옮겨 적힌 2026-11-17 실행값과 대조"))
    m = loot_expect(cfg, 10000, mode="sim_loot")
    L.append("   %-10s %9s %9s %8s %s" % ("지표", "D6 0절", "모델", "오차", "명세 목표"))
    for k in ("items", "common", "magic", "rare", "jewelry", "legendary", "unique"):
        e = (m[k] - LOOT_D6[k]) / LOOT_D6[k] * 100
        tg = LOOT_TARGETS.get(k)
        L.append("   %-10s %9.3f %9.3f %+7.1f%% %s" % (k, LOOT_D6[k], m[k], e, ("목표 %s %s" % (tg, "안" if tg[0] <= m[k] <= tg[1] else "밖")) if tg else ""))
    L.append("   items 분포 p10/p50/p90 모델 %s (D6: 37/44/51)" % m["p10_p50_p90"])
    L.append("   한계: 장신구는 sim_loot가 고유(냉기=목걸이)를 장신구로 센 것과 같게 센다. 접사·기본 장비의 세부는 모델에 없다(등급·칸·아이템 레벨만).")
    L.append("")
    L.append("3) 지금 데이터(now) 한 판의 재 수입 — D6 3.1: 전부 해체하면 약 150(남기는 것을 빼면 120~140)")
    now = Cfg("now")
    loot = Loot(now)
    rng = random.Random(7)
    sal = now["essence.salvage"]
    tot = 0.0
    N = 4000
    for _ in range(N):
        out, _s = run_events(now, loot, rng, "skilled", "frost", 1, 1.0, True, False)
        tot += sum(sal[QUAL[q]] for _, _, q, _ in out)
    L.append("   모델(now, 정예·운반자 없음) %.0f 재/판. sim_loot 가정(정예·운반자 포함)은 약 %.0f 재/판" % (tot / N, loot_expect_essence(cfg)))
    L.append("")
    L.append("4) D11 D2 — 보상 단계 Ⅰ, 사건에 묶인 드랍의 비율과 장비 수(목표 판당 28~34개, 사건 비율 55%% 이상)")
    sp = Cfg("spec", extra={"players.skilled.p_ritual": 0.0, "players.skilled.p_carrier": 0.0, "players.skilled.p_greed": 0.0})
    loot = Loot(sp)
    rng = random.Random(9)
    cnt, srcs = 0.0, {}
    for _ in range(4000):
        out, summ = run_events(sp, loot, rng, "skilled", "frost", 1, 1.0, True, False)
        cnt += len(out)
        for s_, _a, _b, _c in out:
            srcs[s_] = srcs.get(s_, 0) + 1
    ev = sum(v for k, v in srcs.items() if k not in ("normal", "forced"))
    L.append("   모델(spec, 단계 Ⅰ, 잘함 유형, 상자·정예·사당 모두): 장비 %.1f개/판, 사건 출처 %.0f%%, 출처 %s" % (cnt / 4000, ev / float(sum(srcs.values())) * 100, {k: round(v / 4000.0, 2) for k, v in sorted(srcs.items())}))
    L.append("   (D11 D2 표의 합 ≈ 8.7 + 4 + 4.5 + 6 + 4 + 3 = 30.2. 사람이 의식·운반자를 하면 더 늘어난다)")
    L.append("")
    L.append("4b) D6 3.3 도박이 드랍을 무의미하게 만들지 않는 상한 — R_x = (한 판의 재를 전부 도박(칸 값 30)에 썼을 때 x 등급 기대 수) ÷ (한 판 드랍의 x 등급 기대 수)")
    L.append("    재 수입은 모델의 첫 30판 평균(해체 + 보상 단계 + 퀘스트), 드랍 수는 승리 판 기준. 상한: 희귀 0.30(하한 0.10), 전설 0.30, 고유 0.15")
    gq = Cfg("spec")["gamble.quality"]
    for pn, cname in (("now(지금 데이터)", "now"), ("spec", "spec")):
        c = Cfg(cname)
        loot = Loot(c)
        for t in ("skilled", "average", "poor"):
            res = simulate_group(c, t, ["frost"], 30, 16, 11, Tree(c))
            inc = statistics.mean(sum(x["income"] for x in tr) / 30.0 for P, tr in res)
            rng = random.Random(5)
            cnt = {"rare": 0, "legendary": 0, "unique": 0}
            for _ in range(1500):
                out, _s = run_events(c, loot, rng, t, "frost", 1, 1.0, True, False)
                for src, sl, q, il in out:
                    if QUAL[q] in cnt:
                        cnt[QUAL[q]] += 1
            n_g = inc / 30.0
            r_r = n_g * gq[2] / (cnt["rare"] / 1500.0)
            r_l = n_g * 0.025 / (cnt["legendary"] / 1500.0)
            r_u = n_g * 0.005 / (cnt["unique"] / 1500.0)
            L.append("    %-14s %-6s 재 %5.0f/판 -> 도박 %4.1f회  R_희귀 %.2f %s  R_전설 %.2f %s  R_고유 %.2f %s" % (
                pn, TYPE_KO[t], inc, n_g, r_r, "(상한 안)" if r_r <= 0.30 else "(상한 초과)", r_l, "(상한 안)" if r_l <= 0.30 else "(상한 초과)", r_u, "(상한 안)" if r_u <= 0.15 else "(상한 초과)"))
    L.append("    한계: 도박 전 재를 전부 쓴다는 D6의 정의 그대로다. 모델의 실제 지출은 상점이 먼저 가져간다(상점 가격은 가정). 세트(1%)는 드랍 쪽에도 도박 쪽에도 세지 않았다(전설은 D6 G4의 2.5%).")
    L.append("")
    L.append("5) 장비 힘 식을 balance_sim의 장비 묶음(P10 예산)에 맞춤 — 고정 구성의 모델 값")
    L.append("   %-14s %10s %10s %10s %10s   %s" % ("묶음", "힘 p", "P10 힘", "버팀 s", "P10 버팀", "판정"))
    for nm, (pr, sr) in P10_BUDGET.items():
        p, s = kit_values(cfg, nm)
        ok = pr[0] <= p <= pr[1] and sr[0] <= s <= sr[1]
        L.append("   %-14s %+9.0f%% %5.0f~%3.0f%% %+9.0f%% %5.0f~%3.0f%%   %s" % (nm, p * 100, pr[0] * 100, pr[1] * 100, s * 100, sr[0] * 100, sr[1] * 100, "예산 안" if ok else "예산 밖"))
    L.append("   한계: 세 묶음의 구성(칸·등급·레벨)은 작성자가 고른 것이다. gear.p_max·gamma는 이 세 점에 맞춘 값이라 세 점 밖(예: 일반 위주 착용)의 값은 외삽이다.")
    L.append("")
    L.append("6) 승률-힘 곡선 — balance_sim --gear 표(balsim2/gear-check.txt)에 맞춘 값")
    L.append("   %-8s %6s %6s %6s %8s   표(M: 모델/표)" % ("유형", "cap", "a", "k", "RMSE"))
    for t in TYPES:
        f = win_fit(cfg, t)
        pts = " ".join("%.2f:%.0f/%.0f%%" % (m_, f["cap"] * sigmoid(f["a"] + f["k"] * math.log(m_)) * 100, w * 100) for m_, w in cfg["win.table." + t])
        L.append("   %-8s %6.2f %6.1f %6.1f %8.3f   %s" % (TYPE_KO[t], f["cap"], f["a"], f["k"], f["rmse"], pts))
    L.append("   한계: 표는 balance_sim 모델의 답이다(실측 아님). 승률이 힘에만 달린다고 가정하며 깊이는 위협 배율(depth.threat)로 힘을 나눈 것과 같게 쓴다.")
    L.append("")
    L.append("7) 대조할 실측이 없는 것")
    L.append("   · 퀘스트·상점·보상 단계·깊이 2~3: 게임에 아직 없다(명세만). 모델의 값은 전부 가정이며 calib의 source가 guess/hypo인 것이다.")
    L.append("   · 장비 교체의 체감(접사 구성, 스킬형 줄): 모델은 칸 점수 하나로 줄였다. sim_progression --carry-gear 로 실제 착용 효과를 잴 수 있다(prog_lance_gear.log가 _local/sim/log에 있다).")
    return "\n".join(L)


def loot_expect_essence(cfg):
    m = loot_expect(cfg, 3000, mode="sim_loot")
    sal = cfg["essence.salvage"]
    return sum(m[q] * sal[q] for q in QUAL if q in m)


# ----------------------------------------------------------------------------------------------- 외부 입력
def apply_from_balsim(cfg, path):
    """balance_sim.py 결과 JSON(results['정책|마녀'].win_rate, deaths[].secs)에서 기준 승률·마녀 차·죽는 시각을 가져온다."""
    d = read_json(path)
    res = d.get("results", {})
    extra = {}
    offs = {w: [] for w in WITCHES}
    for t in TYPES:
        pol = TYPE_POLICY[t]
        rates = {}
        fr = []
        for w in WITCHES:
            r = res.get("%s|%s" % (pol, w))
            if not r:
                continue
            rates[w] = min(0.99, max(0.01, r["win_rate"]))
            secs_win = max(1.0, r.get("secs_median") or 430.0)
            for x in r.get("deaths", []):
                fr.append(min(1.0, x["secs"] / max(secs_win, 400.0)))
        if rates:
            m = statistics.mean(rates.values())
            extra["players.%s.base_win" % t] = m
            for w, v in rates.items():
                offs[w].append(logit(v) - logit(m))
        if len(fr) >= 5:
            fr.sort()
            extra["players.%s.defeat_f_lo" % t] = round(fr[len(fr) // 10], 3)
            extra["players.%s.defeat_f_hi" % t] = round(fr[len(fr) * 9 // 10], 3)
    for w, v in offs.items():
        if v:
            extra["witch.logit_offset." + w] = round(statistics.mean(v), 3)
    return extra


# ----------------------------------------------------------------------------------------------- 값 바꿔 보기
HEADLINE = ["lv30", "lv100", "tier4", "keystone", "shop", "depth2", "gap30", "ratio30", "stock100", "sat", "wins100", "firstwin"]


def headline(cfg, ptype, plan, n_runs, n_players, seed0, tree):
    res = simulate_group(cfg, ptype, plan, n_runs, n_players, seed0, tree)
    S = summarize_group(cfg, res, n_runs, plan)
    w = plan[0]
    ck = S["checkpoints"]
    c30 = 30 if 30 in ck else n_runs
    h = S["h%d" % min(30, n_runs)]
    ev = S["events"]
    return {
        "lvC": ck[c30]["lv"][w], "lvN": ck[n_runs]["lv"][w], "tier4": (ev.get("tier4") or {}).get("median"), "keystone": (ev.get("keystone") or {}).get("median"),
        "shop": (ev.get("shop_open") or {}).get("median"), "depth2": (ev.get("depth2") or {}).get("median"), "gap30": h["longest_gap_med"], "growthless30": h["growthless_share"],
        "ratio30": h["ratio"], "stockN": ck[n_runs]["stock"], "sat": S["gear_sat_run"], "winsN": ck[n_runs]["wins"], "firstwin": S["first_win_med"],
        "pgN": ck[n_runs]["pg"], "pw50": S["pw50_run_med"], "never": S["never_won_share"], "depthN": ck[n_runs]["depth"],
    }


def _head_task(args):
    cfg, t, plan, n_runs, n_players, seed0 = args
    return headline(cfg, t, plan, n_runs, n_players, seed0, Tree(cfg))


def do_sweep(cfg, key, values, types, n_runs, n_players, seed0, witch):
    tasks, idx = [], []
    for vi, v in enumerate(values):
        c = cfg.with_value(key, parse_val(v) if isinstance(v, str) else v)
        for t in types:
            tasks.append((c, t, [witch], n_runs, n_players, seed0))
            idx.append((vi, t))
    outs = pmap(_head_task, tasks)
    rows = [{"value": v} for v in values]
    for (vi, t), h in zip(idx, outs):
        rows[vi][t] = h
    return rows


def render_sweep(key, rows, types, n_runs):
    L = ["", "값 바꿔 보기: %s  — %s" % (key, BANNER), "  (%d판 기준, 마녀 하나. 값 = 중앙값)" % n_runs]
    for t in types:
        L.append("  [%s]" % TYPE_KO[t])
        L.append("   %-14s %6s %6s %6s %6s %6s %7s %6s %7s %6s %6s %6s" % ("값", "Lv30*", "Lv끝", "단4", "키스톤", "상점", "깊이2", "공백", "수입/지출", "재고", "포화", "첫승"))
        for r in rows:
            h = r[t]
            L.append("   %-14s %6s %6s %6s %6s %6s %7s %6s %7s %6s %6s %6s" % (
                str(r["value"])[:14], fmt(h["lvC"], 0), fmt(h["lvN"], 0), fmt(h["tier4"], 0), fmt(h["keystone"], 0), fmt(h["shop"], 0), fmt(h["depth2"], 0),
                fmt(h["gap30"], 0), fmt(h["ratio30"], 2), fmt(h["stockN"], 0), fmt(h["sat"], 0), fmt(h["firstwin"], 0)))
    return "\n".join(L)


SENS_KEYS = [
    ("players.average.k_scale", [-0.3, 0.3], "mul", "보통 유형의 승률이 힘에 반응하는 기울기"),
    ("players.poor.k_scale", [-0.3, 0.3], "mul", "못함 유형의 기울기"),
    ("players.average.base_win", [0.10, 0.35], "abs", "보통 유형의 기준 승률(장비·트리 없음)"),
    ("players.poor.base_win", [0.005, 0.10], "abs", "못함 유형의 기준 승률"),
    ("players.skilled.base_win", [0.45, 0.9], "abs", "잘함 유형의 기준 승률"),
    ("depth.threat", [[1.0, 1.6, 2.8], [1.0, 3.0, 5.5]], "abs", "깊이 2·3의 위협 배율"),
    ("gear.p_max", [-0.3, 0.3], "mul", "장비가 주는 힘의 크기"),
    ("gear.gamma", [-0.2, 0.2], "mul", "장비 힘 곡선의 굽음"),
    ("gear.keep_per_slot", [2, 10], "abs", "칸마다 보관하는 수(교체 가능성)"),
    ("tree.p_full", [-0.4, 0.4], "mul", "트리 Lv20 힘"),
    ("tree.levels_mode", ["data", "spec"], "abs", "트리 단 레벨 1·6·12·18 대 1·5·10·15"),
    ("xp.scale", [-0.3, 0.3], "mul", "처치·봉인 경험치 배율"),
    ("essence.grade_per_step", [0, 40], "abs", "보상 단계당 재"),
    ("shop.price.rare", [-0.5, 1.0], "mul", "상점 희귀 가격"),
    ("gamble.price", [-0.5, 1.0], "gamblemul", "도박 가격"),
    ("shop.stock", [2, 8], "abs", "진열 수"),
    ("shop.quality", [[0, 0.7, 0.25, 0.04, 0.01], [0, 0.4, 0.45, 0.12, 0.03]], "abs", "진열 품질"),
    ("loot.spec.normal_drop", [15, 60], "abs", "일반 적 드랍(만분율)"),
    ("loot.spec.boss_picks", [[2, 3, 4, 5], [4, 5, 6, 8]], "abs", "우두머리 전리품 수(단계별)"),
    ("players.average.p_ritual", [0.0, 0.8], "abs", "보통 유형이 의식을 해내는 확률"),
    ("depth.up_rate", [0.4, 0.8], "abs", "깊이를 올리는 승률 문턱"),
    ("shop.open_by", ["start", "never"], "abs", "상점이 열리는 때"),
    ("gear.share", ["shared", "split"], "abs", "장비 공유"),
    ("run.secs_win", [-0.2, 0.2], "mul", "(영향 없음의 확인) 판 길이"),
]


def sens_value(cfg, key, spec, side):
    kind = spec[2]
    base = cfg[key]
    if kind == "abs":
        return spec[1][side]
    if kind == "gamblemul":
        return {k: max(1, int(round(v * (1 + spec[1][side])))) for k, v in base.items()}
    if kind == "mul":
        return base * (1 + spec[1][side]) if base is not None else None
    return base


FLOORS = {"lvN": 2.0, "tier4": 5.0, "keystone": 5.0, "depth2": 5.0, "gap30": 1.0, "ratio30": 0.3, "stockN": 50.0, "sat": 5.0, "winsN": 3.0, "firstwin": 2.0, "pgN": 0.1, "depthN": 0.5}


def metric_vector(h):
    """민감도의 지표: 낮을수록/높을수록의 방향 없이 상대 변화량의 최대를 센다."""
    keys = ["lvN", "tier4", "keystone", "depth2", "gap30", "ratio30", "stockN", "sat", "winsN", "firstwin", "pgN", "depthN"]
    return {k: h.get(k) for k in keys}


def do_sensitivity(cfg, n_runs, n_players, seed0, witch="frost"):
    types = TYPES
    tasks, idx = [], []
    for t in types:
        tasks.append((cfg, t, [witch], n_runs, n_players, seed0))
        idx.append((None, 0, t))
    specs = []
    for key, vals, kind, desc in SENS_KEYS:
        spec = (key, vals, kind, desc)
        if cfg[key] is None and kind == "mul":
            continue
        specs.append(spec)
        for side in (0, 1):
            c = cfg.with_value(key, sens_value(cfg, key, spec, side))
            for t in types:
                tasks.append((c, t, [witch], n_runs, n_players, seed0))
                idx.append((key, side, t))
    outs = pmap(_head_task, tasks)
    res = {}
    for (key, side, t), h in zip(idx, outs):
        res[(key, side, t)] = metric_vector(h)
    base = {t: res[(None, 0, t)] for t in types}
    out = []
    for key, vals, kind, desc in specs:
        eff = []
        detail = {}
        for side in (0, 1):
            for t in types:
                for m, x in res[(key, side, t)].items():
                    b = base[t][m]
                    if b is None or x is None:
                        d = 0.0 if (b is None and x is None) else 1.0
                    else:
                        d = abs(x - b) / max(abs(b), FLOORS[m])
                    d = min(d, 3.0)
                    eff.append(d)
                    detail.setdefault(m, []).append(d)
        score = statistics.mean(sorted(eff)[-10:]) if eff else 0.0
        top = sorted(detail.items(), key=lambda kv: -max(kv[1]))[:3]
        out.append({"key": key, "desc": desc, "score": score, "values": vals, "top_metrics": [k for k, _ in top]})
    out.sort(key=lambda x: -x["score"])
    return out, base


def render_sens(rows, n_runs):
    L = ["", "민감도(%d판, 서리 마녀, 세 유형 · 낮은쪽/높은쪽 값으로 바꿨을 때 지표 12개의 상대 변화량 상위 10개 평균) — %s" % (n_runs, BANNER)]
    L.append("   %-4s %-30s %7s  %-34s %s" % ("순위", "키", "영향", "값(낮은쪽, 높은쪽)", "가장 움직인 지표"))
    for i, r in enumerate(rows):
        L.append("   %-4d %-30s %7.2f  %-34s %s  — %s" % (i + 1, r["key"], r["score"], json.dumps(r["values"], ensure_ascii=False)[:34], ",".join(r["top_metrics"]), r["desc"]))
    return "\n".join(L)


def list_params(cfg):
    L = ["%-34s %-30s %-34s %s" % ("키", "값", "출처", "설명")]
    for k in sorted(cfg.meta):
        v = json.dumps(cfg.p[k], ensure_ascii=False)
        L.append("%-34s %-30s %-34s %s" % (k, v[:30], cfg.meta[k][0][:34], cfg.meta[k][1]))
    return "\n".join(L)


# ----------------------------------------------------------------------------------------------- 진입
def main(argv=None):
    ap = argparse.ArgumentParser(description="경제·성장 시뮬레이터(" + BANNER + ")")
    ap.add_argument("--preset", default="spec", help="spec(명세 첫 값, 기본) | now(지금 게임 데이터) | sim_loot(sim_loot.gd 가정, 대조용)")
    ap.add_argument("--runs", type=int, default=100)
    ap.add_argument("--players", type=int, default=60, help="유형마다 가상 플레이어 수(시드 다름)")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--types", default=",".join(TYPES))
    ap.add_argument("--witches", default="ember,frost,arc", help="마녀별 표에 낼 마녀")
    ap.add_argument("--no-rotate", action="store_true", help="세 마녀를 번갈아 키우는 표를 빼기")
    ap.add_argument("--set", action="append", default=[], help="키=값(JSON). --list-params 참고")
    ap.add_argument("--sweep", default=None, help="키=값1,값2,… (한 키를 바꿔 가며 머리 지표). 값에 쉼표가 있는 목록이면 값 사이를 ; 로: depth.threat=[1,1.6,2.8];[1,3,5]")
    ap.add_argument("--sensitivity", action="store_true")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--list-params", action="store_true")
    ap.add_argument("--from-balsim", default=None, help="balance_sim.py 결과 JSON에서 기준 승률·마녀 차·죽는 시각을 받는다")
    ap.add_argument("--jobs", type=int, default=None, help="병렬 프로세스 수(기본: 코어 수-2, 최대 8). 결과는 같다")
    ap.add_argument("--out", default=None, help="JSON 결과(_local/ 아래만)")
    a = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    if a.out:
        op = Path(a.out).resolve()
        if "_local" not in op.parts:
            raise SystemExit("--out은 _local/ 아래만 허용한다: " + a.out)
    global JOBS
    JOBS = a.jobs if a.jobs else max(1, min(8, (os.cpu_count() or 2) - 2))
    cfg = Cfg(a.preset, a.set)
    if a.from_balsim:
        extra = apply_from_balsim(cfg, a.from_balsim)
        for k, v in extra.items():
            cfg.p[k] = v
        cfg._cache = {}
        print("--from-balsim: %s 에서 %s" % (a.from_balsim, json.dumps(extra, ensure_ascii=False)))
    t0 = time.time()
    types = [t for t in a.types.split(",") if t]
    for t in types:
        if t not in TYPES:
            raise SystemExit("알 수 없는 유형: " + t)
    wl = [w for w in a.witches.split(",") if w]
    result = {"banner": BANNER, "preset": a.preset, "sets": a.set, "runs": a.runs, "players": a.players, "seed": a.seed}
    if a.list_params:
        print(list_params(cfg))
        return 0
    if a.calibrate:
        print(calibrate_text(cfg))
        return 0
    if a.sweep:
        key, vals = a.sweep.split("=", 1)
        values = [parse_val(x) for x in (vals.split(";") if ";" in vals else vals.split(","))]
        rows = do_sweep(cfg, key, values, types, a.runs, a.players, a.seed, wl[0] if wl else "frost")
        print(render_sweep(key, rows, types, a.runs))
        result["sweep"] = {"key": key, "rows": rows}
    elif a.sensitivity:
        rows, base = do_sensitivity(cfg, min(a.runs, 40), min(a.players, 30), a.seed)
        print(render_sens(rows, min(a.runs, 40)))
        result["sensitivity"] = rows
    else:
        plans = {("%s만" % WITCH_KO[w]): [w] for w in wl}
        if not a.no_rotate and len(wl) >= 3:
            plans["세 마녀 번갈아"] = list(wl)
        flow = run_flow(cfg, types, plans, a.runs, a.players, a.seed)
        txt = render_flow(cfg, flow, a.runs, a.players, a.seed)
        print(txt)
        rows = checks_for(cfg, flow, a.runs)
        print("")
        print("목표와 견줌(가설 목표. 값이 목표 밖이면 밖이라고 적는다 — 목표를 결과에 맞춰 옮기지 않는다)")
        for nm, v, tg, ok, src in rows:
            print("   %-44s %8s  목표 %-12s %s  [%s]" % (nm, fmt(v, 2), tg, "참고" if ok is None else ("통과" if ok else "벗어남"), src))
        result["flow"] = flow
        result["checks"] = [{"name": r[0], "value": r[1], "target": r[2], "pass": r[3], "source": r[4]} for r in rows]
    print("\n실행 시간 %.1f초" % (time.time() - t0))
    if a.out:
        op = Path(a.out)
        op.parent.mkdir(parents=True, exist_ok=True)
        with open(op, "w", encoding="utf-8", newline="\n") as f:
            json.dump(result, f, ensure_ascii=False, indent=1, default=lambda o: sorted(o) if isinstance(o, set) else str(o))
            f.write("\n")
        print("결과 JSON: %s" % a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
