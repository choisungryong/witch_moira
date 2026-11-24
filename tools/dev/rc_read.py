#!/usr/bin/env python3
"""rc_read.py - reads measure_rhythm result JSON and prints the D-run-curve (docs/specs/D-run-curve-20261124.ko.md) tables. Standard library only, no Godot.

  now    the spec's section 2 tables again from existing raw (no --rc needed): block split, grace (power) counts and gaps per block, big-fight seconds, offer sizes per level,
         and the descent gauge model ("model's answer", not the game's answer) with --cost=3000,8000,N candidates.
           python tools/dev/rc_read.py now _local/d22-r2/full_L3g.json _local/d22-r2/full_L3g_11.json --cost=3000,8000,4000 --cost=3000,8000,5000
  judge  the section-5 table RC-T1..RC-T27 from runs made with `measure_rhythm.gd ... --rc` (bare / human proxy / geared / descent now / hold), with bootstrap 10/90 % (4000 draws, seed 20261124).
           python tools/dev/rc_read.py judge --bare _local/rc-a/bare_*.json --human _local/rc-a/human_*.json --geared ... --dnow ... --dhold ... [--out _local/rc-a/judge.txt]

  bf     the boss-finale lines BF-T1..T8 of docs/specs/D-boss-finale-20261124.ko.md (runs made with the finale on and --rc: rc.fin), plus the boss-life shares per skill, per-phase work, breaks.
           python tools/dev/rc_read.py bf --bare _local/bf-b/bare_*.json --geared ... --human ... --dnow ... --hp 15000 [--out _local/bf-b/bf.txt]

Reads only. "Pass" in the judge table means the observed value meets the target as written; a line whose target lies inside the 10/90 % band is "경계". Values from a
model (descent gauge) or from a stand-in definition are marked in the line. The bot's results are a stability / balance reference, not evidence of fun (unevaluated).
"""
import argparse
import glob
import json
import math
import random
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = 20261124
DRAWS = 4000
PRIMS = ["ember", "frost", "arc"]
DESCENT_PTS = {"gi": 16, "seung1": 8, "seung2": 5, "jeon_a": 3, "boss": 2}
CHAMP_PTS = 800
BLOCKS = ["기", "승", "전", "결"]


def load_runs(paths):
    runs = []
    for pat in paths:
        for p in sorted(glob.glob(pat)) or [pat]:
            with open(p, encoding="utf-8") as f:
                runs.extend(json.load(f)["runs"])
    runs.sort(key=lambda r: (PRIMS.index(r["primary"]) if r["primary"] in PRIMS else 9, r["seed"]))
    return runs


def med(v):
    v = [x for x in v if x is not None]
    return statistics.median(v) if v else None


def pct(v, p):
    v = sorted(x for x in v if x is not None)
    if not v:
        return None
    k = (len(v) - 1) * p
    lo, hi = math.floor(k), math.ceil(k)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def fnum(x, f="%.1f"):
    return "-" if x is None else (f % x)


class Run:
    """One run of measure_rhythm: the block bounds (seconds) and the lists the tables read."""

    def __init__(self, r):
        self.r = r
        self.prim = r["primary"]
        self.seed = r["seed"]
        self.mode = r["mode"]
        self.secs = float(r["secs"])
        self.rc = r.get("rc")
        sw = r["sweep"]
        self.s = sw["s"]
        self.lives = sw["lives"]
        self.big = {b["kind"]: b for b in sw["big"]}
        self.offers_sum = r["offers"]
        beats = {b["label"]: b for b in r["beats"]}
        self.beat_from = {k: float(v["from_s"]) for k, v in beats.items()}
        if self.rc:
            ev = self.rc["ev"]
            self.ev = [(e[0] / 60.0, e[1], e[2:]) for e in ev]
            st = [t for t, k, a in self.ev if k == "beat" and a[0] == "seung1"]
            self.t_s1 = st[0] if st else None
            gates = [t for t, k, a in self.ev if k == "gate"]
            self.t_g0 = gates[0] if len(gates) > 0 else None
            self.t_g1 = gates[1] if len(gates) > 1 else None
            champ = {a[0]: t for t, k, a in self.ev if k == "champ"}
            self.t_boss = champ.get(2)
            self.champ = champ
            self.picks = [(p[0] / 60.0, p[1], p[2]) for p in self.rc["picks"]]
            self.hp_s = self.rc["hp_s"]
            self.pot_s = self.rc["pot_s"]
            self.offers = self.rc["offers"]
        else:
            self.ev = []
            self.t_s1 = self.beat_from.get("승1")
            self.t_g0 = self.beat_from.get("승2")
            self.t_g1 = self.beat_from.get("전A")
            self.t_boss = self.beat_from.get("전C")
            self.champ = {}
            for k, b in self.big.items():
                self.champ[int(k[-1]) - 1] = float(b["spawn_s"])
            self.picks = [(float(g[0]), "", "") for g in sw["graces"]]
            self.hp_s = None
            self.pot_s = None
            self.offers = []
        self.end = self.secs

    # ---- blocks (RC1): 기 [0, 승1 start) / 승 [승1 start, gate 1] / 전 (gate 1, boss appears) / 결 [boss appears, end]
    def block_of(self, t):
        if self.t_s1 is None or t < self.t_s1:
            return "기"
        if self.t_g0 is None or t <= self.t_g0 + 0.05:
            return "승"
        if self.t_boss is None or t < self.t_boss - 0.02:
            return "전"
        return "결"

    def bounds(self):
        """{block: (from, to)}; a missing end = the run ended inside the block (to = run end)."""
        pts = [("기", 0.0), ("승", self.t_s1), ("전", self.t_g0), ("결", self.t_boss)]
        out = {}
        for i, (name, a) in enumerate(pts):
            if a is None:
                continue
            b = None
            for _n, nxt in pts[i + 1:]:
                if nxt is not None:
                    b = nxt
                    break
            out[name] = (a, b if b is not None else self.end)
        return out

    def has_block(self, name):
        return name in self.bounds()

    def picks_in(self, name):
        return [p for p in self.picks if self.block_of(p[0]) == name]

    def kills_in(self, a, b):
        ks = self.s["kills"]
        return sum(v for i, v in enumerate(ks) if a <= i + 0.5 < b)

    def guardian(self, k):
        b = self.big.get("guardian%d" % k)
        return b

    def life_med(self, a, b):
        v = [l[1] for l in self.lives if a <= l[0] < b]
        return med(v)

    # ---- life / potions (need --rc)
    def hp_min(self, a, b):
        if self.hp_s is None or a is None or b is None:
            return None
        lo = max(0, math.floor(a))
        hi = min(len(self.hp_s) - 1, max(lo, math.ceil(b) - 1))
        return min(self.hp_s[lo:hi + 1]) if lo <= hi else None

    def events_in(self, kind, a, b, inclusive_end=True):
        return [(t, args) for t, k, args in self.ev if k == kind and a <= t and (t <= b if inclusive_end else t < b)]

    def potions_at(self, t):
        if self.pot_s is None or not self.pot_s:
            return None
        return self.pot_s[min(len(self.pot_s) - 1, max(0, int(t)))]

    def defeat_block(self):
        return self.block_of(self.secs) if self.mode == "defeat" else None

    def first_offer_with(self, kind):
        for o in self.offers:
            if any(c[1] == kind for c in o["cards"]):
                return o["tick"] / 60.0
        return None

    def first_pick_kind(self, kind):
        for p in self.picks:
            if p[2] == kind:
                return p[0]
        return None

    def crests(self, beat):
        return [t for t, k, a in self.ev if k == "crest" and a[0] == beat]

    def big_beats(self):
        """Stand-in for the 'big beats' of RC2 (the game has no gates yet): unlock picks, the evolve pick, the guardians' kills (gate), the boss appearance, descent_ready."""
        out = []
        for p in self.picks:
            if p[2] in ("unlock", "evolve"):
                out.append(p[0])
        out += [t for t in (self.t_g0, self.t_g1, self.t_boss) if t is not None]
        out += [t for t, k, a in self.ev if k == "dr"]
        return sorted(out)

    def descent(self):
        ready = [t for t, k, a in self.ev if k == "dr"]
        called = [t for t, k, a in self.ev if k == "dc"]
        return ready, called


# ------------------------------------------------------------------ descent gauge model (model's answer)
def beat_at(run, t):
    if run.t_boss is not None and t >= run.t_boss:
        return "boss"
    if run.t_g1 is not None and t >= run.t_g1:
        return "jeon_a"
    if run.t_g0 is not None and t >= run.t_g0:
        return "seung2"
    if run.t_s1 is not None and t >= run.t_s1:
        return "seung1"
    return "gi"


def gauge_model(run, costs):
    """Per-second kills -> points by the beat (descent.json kill_by_beat; a guardian kill = 800 instead of its kill point). 'now' policy: used at the moment it is ready, the gauge
    restarts from 0 the next second (the rest of that second is dropped). Not counted: sweep bonus, control hits, strong-enemy damage points, the pause during the sweep.
    Returns (ready times, gauge fraction toward the next cost when the boss appears)."""
    ks = run.s["kills"]
    gd = {}
    for k in (1, 2):
        b = run.guardian(k)
        if b and b["death_s"] >= 0:
            gd[int(b["death_s"])] = gd.get(int(b["death_s"]), 0) + 1
    gauge = 0.0
    k = 0
    ready = []
    frac_boss = None
    for i, n in enumerate(ks):
        t = i + 0.5
        if run.t_boss is not None and frac_boss is None and i + 1 > run.t_boss:
            frac_boss = gauge / costs[min(k, len(costs) - 1)] if k < len(costs) else None
        pts_k = DESCENT_PTS[beat_at(run, t)]
        pts = n * pts_k
        if i in gd:
            pts += gd[i] * (CHAMP_PTS - pts_k)
        if k >= len(costs):
            continue
        if gauge + pts >= costs[k] and pts > 0:
            ready.append(i + (costs[k] - gauge) / pts)
            gauge = 0.0
            k += 1
            continue
        gauge += pts
    if frac_boss is None and run.t_boss is not None and k < len(costs):
        frac_boss = gauge / costs[k]
    return ready, frac_boss


# ------------------------------------------------------------------ now
def cmd_now(args):
    runs = [Run(r) for r in load_runs(args.files)]
    out = []
    P = out.append
    P("RC-A 1: 이미 있는 원시 %d판에서 명세 2절을 다시 셈함 (Godot 없음). 파일: %s" % (len(runs), ", ".join(args.files)))
    P("토막은 RC1의 네 사건: 기 [0, 승1 시작) / 승 [승1 시작, 관문 1] / 전 (관문 1, 우두머리 등장) / 결 [등장, 끝]. 옛 원시는 마디 시작을 0.1초로만 안다.")
    P("")
    P("[A] 토막 가르기 (초)")
    P("%-6s %4s %6s | %6s %6s %6s %6s | %5s %5s %5s %5s" % ("계열", "시드", "판길이", "승1시작", "관문1", "관문2", "우두머리", "기", "승", "전", "결"))
    dur = {b: [] for b in BLOCKS}
    marks = {"s1": [], "g0": [], "g1": [], "boss": [], "secs": []}
    for r in runs:
        b = r.bounds()
        d = {n: (b[n][1] - b[n][0]) if n in b else None for n in BLOCKS}
        for n in BLOCKS:
            if d[n] is not None:
                dur[n].append(d[n])
        for key, val in (("s1", r.t_s1), ("g0", r.t_g0), ("g1", r.t_g1), ("boss", r.t_boss), ("secs", r.secs)):
            if val is not None:
                marks[key].append(val)
        P("%-6s %4d %6.1f | %6s %6s %6s %6s | %5s %5s %5s %5s" % (r.prim, r.seed, r.secs, fnum(r.t_s1), fnum(r.t_g0), fnum(r.t_g1), fnum(r.t_boss),
                                                                 fnum(d["기"]), fnum(d["승"]), fnum(d["전"]), fnum(d["결"])))

    def rng(v, f="%.1f"):
        return "-" if not v else (f + " (" + f + "~" + f + ")") % (statistics.median(v), min(v), max(v))
    P("가운데(최소~최대): 승1 시작 %s | 관문1 %s | 관문2 %s | 우두머리 %s | 판 %s" % (rng(marks["s1"]), rng(marks["g0"]), rng(marks["g1"]), rng(marks["boss"]), rng(marks["secs"])))
    P("토막 길이: 기 %s | 승 %s | 전 %s | 결 %s" % tuple(rng(dur[n]) for n in BLOCKS))
    P("")
    P("[B] 토막별 권능(은총) 수와 간격 (판마다 센 값의 가운데(최소~최대))")
    cnt = {b: [] for b in BLOCKS}
    gap_med = {b: [] for b in BLOCKS}
    gap_max = {b: [] for b in BLOCKS}
    first = []
    byname = {}
    for r in runs:
        for b in BLOCKS:
            ps = [p[0] for p in r.picks_in(b)]
            cnt[b].append(len(ps))
        if r.picks:
            first.append(r.picks[0][0])
        allp = [p[0] for p in r.picks]
        for i in range(1, len(allp)):
            blk = r.block_of(allp[i])
            gap_max[blk].append(allp[i] - allp[i - 1])
        for g in r.r["sweep"]["graces"]:
            byname[g[1]] = byname.get(g[1], 0) + 1
    for b in BLOCKS:
        P("  %s: 권능 수 %s | 그 토막 안에서 끝나는 간격(앞 권능이 앞 토막이어도 포함) 가운데 %s 최대 %s" % (b, rng(cnt[b], "%.0f"), fnum(med(gap_max[b])), fnum(max(gap_max[b]) if gap_max[b] else None)))
    P("  첫 권능 시각 %s | 판 전체 권능 수 %s" % (rng(first), rng([len(r.picks) for r in runs], "%.0f")))
    P("  (참고) 코어 마디 이름으로 센 권능 합: %s (판 %d개)" % (dict(sorted(byname.items())), len(runs)))
    P("  (참고) 관문 둘 안의 권능은 승(관문 1 쌍)과 전(관문 2 쌍)에 센다. 명세 2.1은 마디 이름으로 센 값(승1~관문1 5 / 승2~관문2 5)이다.")
    P("")
    P("[C] 큰 적 싸움 초(등장 → 처치, 다가가는 시간 포함) 계열별 가운데(최소~최대)")
    for kind in ("guardian1", "guardian2", "guardian3"):
        cells = []
        for pr in PRIMS:
            v = [float(r.big[kind]["lived_s"]) for r in runs if r.prim == pr and kind in r.big and r.big[kind]["death_s"] >= 0]
            cells.append("%s %s (n=%d)" % (pr, rng(v), len(v)))
        P("  %s: %s" % ({"guardian1": "수호자 1", "guardian2": "수호자 2", "guardian3": "우두머리"}[kind], " | ".join(cells)))
    P("")
    P("[D] 카드 패의 크기 [레벨별 카드 수의 가운데(최소~최대)]")
    bylevel = {}
    for r in runs:
        for lv, n, k in r.offers_sum:
            bylevel.setdefault(lv, []).append(n)
    P("  " + " | ".join("L%d %s" % (lv, rng(v, "%.0f")) for lv, v in sorted(bylevel.items())))
    P("")
    P("[E] 필살기 게이지 셈 [모델의 답: 처치 수 × 마디 점수 + 수호자 800. 쓸기 덤·제어·강한 적 피해 점수·쓰는 동안의 정지는 뺌. 정책 now = 준비되면 바로 씀]")
    costs_list = [[3000, 8000, 10000]] + [[int(x) for x in c.split(",")] for c in (args.cost or [])]
    for costs in costs_list:
        rows = []
        for r in runs:
            ready, frac = gauge_model(r, costs)
            rows.append((r, ready, frac))
        n3 = sum(1 for _r, rd, _f in rows if len(rd) >= 3)
        c1 = [rd[0] for _r, rd, _f in rows if len(rd) > 0]
        c2 = [rd[1] for _r, rd, _f in rows if len(rd) > 1]
        c3 = [rd[2] for _r, rd, _f in rows if len(rd) > 2]
        rel3 = [rd[2] - r.t_boss for r, rd, _f in rows if len(rd) > 2 and r.t_boss is not None]
        fr = [f for _r, _rd, f in rows if f is not None]
        early = sum(1 for r, rd, _f in rows if rd and r.t_s1 is not None and rd[0] < r.t_s1)
        late = sum(1 for r, rd, _f in rows if rd and r.champ.get(0) is not None and rd[0] > r.champ[0])
        second_ok = sum(1 for r, rd, _f in rows if len(rd) > 1 and r.t_g0 is not None and r.t_boss is not None and r.t_g0 < rd[1] < r.t_boss)
        P("  cost=%s : 첫째가 승 시작 앞인 판 %d, 수호자 1 등장 뒤인 판 %d, 둘째가 전 토막 안인 판 %d (모델의 답)" % (costs, early, late, second_ok))
        P("  cost=%s : 판 %d | 3번 찬 판 %d | 첫째 %s | 둘째 %s | 셋째 %s | 셋째 − 우두머리 등장(음수 = 앞) %s | 등장 때 다음 충전의 몫 %s" % (
            costs, len(rows), n3, rng(c1), rng(c2), rng(c3), rng(rel3), ("%.0f%% (%.0f~%.0f%%)" % (statistics.median(fr) * 100, min(fr) * 100, max(fr) * 100)) if fr else "-"))
    print_out(out, args.out)


# ------------------------------------------------------------------ judge
class Clause:
    def __init__(self, label, sets, per_run, agg, meets, fmt, target, reading="", ref=False, unmeasured=False):
        self.label, self.sets, self.per_run, self.agg, self.meets, self.fmt, self.target, self.reading, self.ref = label, sets, per_run, agg, meets, fmt, target, reading, ref
        self.unmeasured = unmeasured  # a reference-only clause that stands for a target the tool cannot measure: the line is marked "(일부)"


def boot(vals, agg, rng_):
    n = len(vals)
    out = []
    for _ in range(DRAWS):
        out.append(agg([vals[rng_.randrange(n)] for _ in range(n)]))
    return out


def run_clause(cl, sets):
    """-> list of (group, n, value text, q10 text, q90 text, verdict) over the groups of the set(s)."""
    res = []
    rng_ = random.Random(SEED)
    for pr in PRIMS:
        vals = []
        for sname in cl.sets:
            vals += [cl.per_run(r) for r in sets.get(sname, []) if r.prim == pr]
        if not vals:
            res.append((pr, 0, "-", "-", "-", "재지 않음"))
            continue
        stat = cl.agg(vals)
        b = boot(vals, cl.agg, rng_)
        q10 = quant(b, 0.10)
        q90 = quant(b, 0.90)
        ok, lo, hi = safe(cl.meets, stat), safe(cl.meets, q10), safe(cl.meets, q90)
        verdict = "통과" if (ok and lo and hi) else ("못 미침" if not (ok or lo or hi) else "경계")
        raw = [v for v in vals if isinstance(v, (int, float)) and not isinstance(v, bool)]
        extra = ""
        if raw and not isinstance(stat, float) and not set(raw) <= {0, 1}:
            extra = " [값 가운데 %.2f (%.2f~%.2f), %d/%d판에 값]" % (statistics.median(raw), min(raw), max(raw), len(raw), len(vals))
        nn = "/%d" % len(vals)
        res.append((pr, len(vals), cl.fmt(stat).replace("/n", nn) + extra, cl.fmt(q10).replace("/n", nn), cl.fmt(q90).replace("/n", nn), verdict))
    return res


def safe(fn, x):
    try:
        return bool(fn(x))
    except TypeError:
        return False


def quant(boots, p):
    """10/90 % of bootstrap statistics that may be numbers or tuples (tuples: element-wise)."""
    boots = [b for b in boots if b is not None]
    if not boots:
        return None
    if isinstance(boots[0], tuple):
        return tuple(pct([b[i] for b in boots], p) for i in range(len(boots[0])))
    return pct(boots, p)


def cnt_in(vals, lo, hi):
    return sum(1 for v in vals if v is not None and lo <= v <= hi)


def mk_count(pred_label, pred):
    return lambda vals: sum(1 for v in vals if v is not None and pred(v))


def all_runs(sets, names):
    out = []
    for n in names:
        out += sets.get(n, [])
    return out


def crisis_of(o):
    if o["hp_bps"] < 3500:
        return "생존"
    if o["champ_alive"]:
        return "큰 적"
    if o["cap"] > 0 and o["alive"] >= 0.6 * o["cap"] or (0 <= o["crest_age"] <= 900):
        return "무리"
    return None


_GROWTH = None


def growth_ranks():
    global _GROWTH
    if _GROWTH is None:
        with open(ROOT / "chapter1/data/growth_quality37.json", encoding="utf-8") as f:
            _GROWTH = {s["id"]: s["ranks"] for s in json.load(f)["skills"]}
    return _GROWTH


def card_tags(cid, kind):
    """D-run-curve 4.4 when the data has no `answers` key: unlock/passive(crystal) = crowd, evolve = crowd + big, rank by what the next rank adds."""
    if kind in ("unlock", "passive"):
        return {"무리"}
    if kind == "evolve":
        return {"무리", "큰 적"}
    if kind == "rank":
        m = re.match(r"rank:(.+):(\d+)$", cid)
        if m and m.group(1) in growth_ranks():
            rk = growth_ranks()[m.group(1)]
            n = int(m.group(2))
            if 2 <= n <= len(rk):
                a, b = rk[n - 2], rk[n - 1]
                tags = set()
                if any(b.get(k, 0) > a.get(k, 0) for k in ("projectiles", "hit_budget", "radius_cm", "chain_targets")):
                    tags.add("무리")
                if b.get("damage_raw", 0) >= a.get("damage_raw", 1) * 1.25 or b.get("cooldown_ticks", 0) < a.get("cooldown_ticks", 0):
                    tags.add("큰 적")
                return tags
    return set()


def floor_would_replace(o):
    """(applicable, would_replace). The 4.3 rule 1-2 as written, with the offer state the tool recorded; protected card and candidate stock are not known here, so a
    replacement needs >= 2 cards in the offer (a single card is the protected one). Upper bound of what the floor would do."""
    crisis = crisis_of(o)
    if crisis is None or len(o["cards"]) < 2:
        return (0, 0)
    order = {"생존": ["생존", "큰 적", "무리"], "큰 적": ["큰 적", "무리"], "무리": ["무리"]}[crisis]
    tagset = [card_tags(c[0], c[1]) for c in o["cards"]]
    for want in order:
        if any(want in t for t in tagset):
            return (1, 0)
        # the first tag in the order that has no answer in the pack: the pack lacks the answer to the crisis; the rule asks for the crisis tag only
        break
    return (1, 1)


def build_clauses():
    C = []

    def add(rc_id, block, metric, target, clauses):
        C.append((rc_id, block, metric, target, clauses))

    inr = lambda lo, hi: (lambda x: x is not None and lo <= x <= hi)
    ge = lambda t: (lambda x: x is not None and x >= t)
    le = lambda t: (lambda x: x is not None and x <= t)
    f1 = lambda x: "-" if x is None else "%.1f" % x
    f2 = lambda x: "-" if x is None else "%.2f" % x
    f0 = lambda x: "-" if x is None else "%.0f" % x

    def cnt_of(pred):
        return lambda vals: sum(1 for v in vals if v is not None and pred(v))

    # T1
    add("RC-T1", "기", "첫 고비(기 마디 안 첫 wave_crest) 시각", "판 95~115초, 14/20 이상으로 읽음", [
        Clause("자동", ["bare"], lambda r: next(iter(r.crests("gi")), None), cnt_of(inr(95, 115)), ge(14), lambda x: "%s/n" % f0(x), "")])
    # T2
    add("RC-T2", "기", "S1(열림 카드가 패에 든 첫 권능) 시각", "100~125초 14/20 이상으로 읽음 (고비 뒤 25초 안은 고비가 없어 셀 수 없음)", [
        Clause("자동(패에 든)", ["bare"], lambda r: r.first_offer_with("unlock"), cnt_of(inr(100, 125)), ge(14), lambda x: "%s/n" % f0(x), "")])
    # T3
    add("RC-T3", "기", "기 토막 사망", "자동 0/60, 사람 대리 ≤ 1/60", [
        Clause("자동", ["bare"], lambda r: 1 if r.defeat_block() == "기" else 0, lambda v: sum(v), lambda x: x == 0, lambda x: "%s판" % f0(x), ""),
        Clause("사람 대리", ["human"], lambda r: 1 if r.defeat_block() == "기" else 0, lambda v: sum(v), lambda x: x <= 1, lambda x: "%s판" % f0(x), "")])
    # T4
    s1_hp = lambda r: (r.hp_min(r.first_offer_with("unlock") - 20, r.first_offer_with("unlock")) if r.first_offer_with("unlock") is not None else None)
    add("RC-T4", "기", "S1 직전 20초 최저 생명", "자동 0.55~0.85 (14/20), 사람 대리 0.40~0.75 (S1 = 열림 카드가 패에 든 권능)", [
        Clause("자동", ["bare"], s1_hp, cnt_of(inr(0.55, 0.85)), ge(14), lambda x: "%s/n" % f0(x), ""),
        Clause("사람 대리", ["human"], s1_hp, cnt_of(inr(0.40, 0.75)), ge(14), lambda x: "%s/n" % f0(x), "사람 대리 14/20은 자동 줄을 따라 읽음")])
    # T5
    def t5(r):
        if r.t_s1 is None:
            return None
        used = len(r.events_in("pu", 0, r.t_s1, False))
        return (used, r.potions_at(r.t_s1 - 1))
    add("RC-T5", "기", "기 토막 물약 사용 / 끝 보유", "사람 대리에서 1개 이상 쓴 판 ≥ 8/20, 끝 보유 가운데 1~2", [
        Clause("사람 대리", ["human"], t5, lambda v: (sum(1 for x in v if x and x[0] >= 1), med([x[1] for x in v if x])), lambda t: t[0] is not None and t[0] >= 8 and t[1] is not None and 1 <= t[1] <= 2,
               lambda t: "쓴 판 %s / 끝 보유 가운데 %s" % (f0(t[0]), f1(t[1])), "")])
    # T6
    def t6(r):
        c = r.crests("seung1")
        return (r.champ[0] - c[0]) if c and 0 in r.champ else None
    def t6b(r):
        c = [t for t in r.crests("seung1") if 0 in r.champ and t < r.champ[0]]
        return (r.champ[0] - c[-1]) if c and 0 in r.champ else None
    add("RC-T6", "승", "큰 머리(승1 첫 머리) → 수호자 1 등장 간격", "10~35초 (가운데)", [
        Clause("자동(승1의 첫 wave_crest = 마디 시작과 같은 틱)", ["bare"], t6, med, inr(10, 35), f1, "표의 글자대로 첫 머리"),
        Clause("자동(수호자 1 직전 마지막 머리 = 명세 2.1이 가리킨 승1 시작+40초 머리)", ["bare"], t6b, med, inr(10, 35), f1, "참고: 명세 손셈이 가정한 머리", ref=True)])
    # T7
    def t7(r):
        b = r.guardian(1)
        return r.hp_min(b["death_s"] - 20, b["death_s"]) if b and b["death_s"] >= 0 else None
    add("RC-T7", "승", "수호자 1 처치 직전 20초 최저 생명", "자동 0.35~0.70 (14/20), 사람 대리 0.25~0.60", [
        Clause("자동", ["bare"], t7, cnt_of(inr(0.35, 0.70)), ge(14), lambda x: "%s/n" % f0(x), ""),
        Clause("사람 대리", ["human"], t7, cnt_of(inr(0.25, 0.60)), ge(14), lambda x: "%s/n" % f0(x), "")])
    # T8
    def t8(r):
        if r.t_s1 is None or r.t_g0 is None:
            return 0
        return 1 if r.events_in("drop", r.t_s1, r.t_g0 + 0.05) and any(a[0] == "rare" for t, a in r.events_in("drop", r.t_s1, r.t_g0 + 0.05)) else 0
    add("RC-T8", "승", "희귀 장비가 승 토막 안에", "20/20 (계열마다)", [
        Clause("자동", ["bare"], t8, lambda v: (sum(v), len(v)), lambda t: t[0] == t[1], lambda t: "%s/%s" % (f0(t[0]), f0(t[1])), "품질 rare 이상이 아니라 'rare' 하나만 셈(unique·legendary 등 더 높은 품질은 따로 셈하지 않음)")])
    # T9
    def t9(r):
        return r.potions_at(r.t_g0) if r.t_g0 is not None else None
    add("RC-T9", "승", "관문 1 뒤 물약 보유", "가운데 2~4", [
        Clause("자동", ["bare"], t9, med, inr(2, 4), f1, ""),
        Clause("사람 대리", ["human"], t9, med, inr(2, 4), f1, "")])
    # T10-T12 (cross-primary ratio is added by the caller)
    big_sec = lambda k: (lambda r: float(r.big["guardian%d" % k]["lived_s"]) if ("guardian%d" % k) in r.big and r.big["guardian%d" % k]["death_s"] >= 0 else None)
    add("RC-T10", "승", "수호자 1 싸움(초)", "맨몸 10~18 / 장비 갖춤 7~12 / 계열 가운데의 최대÷최소 ≤ 1.4", [
        Clause("맨몸", ["bare"], big_sec(1), med, inr(10, 18), f1, ""),
        Clause("장비 갖춤", ["geared"], big_sec(1), med, inr(7, 12), f1, "")])
    add("RC-T11", "전", "수호자 2 싸움(초)", "맨몸 8~14 / 장비 갖춤 5~9", [
        Clause("맨몸", ["bare"], big_sec(2), med, inr(8, 14), f1, ""),
        Clause("장비 갖춤", ["geared"], big_sec(2), med, inr(5, 9), f1, "")])
    add("RC-T12", "결", "우두머리 싸움(초)", "맨몸 50~80 / 장비 갖춤 35~60 / 장비÷맨몸 ≥ 0.60 / 계열 최대÷최소 ≤ 1.3", [
        Clause("맨몸", ["bare"], big_sec(3), med, inr(50, 80), f1, ""),
        Clause("장비 갖춤", ["geared"], big_sec(3), med, inr(35, 60), f1, "")])
    # T13
    def t13(r):
        return r.hp_min(r.t_boss, r.end) if r.t_boss is not None else None
    add("RC-T13", "결", "우두머리 싸움 중 최저 생명", "자동 ≤ 0.45인 판 ≥ 10/20, 사람 대리 ≤ 0.30인 판 ≥ 10/20", [
        Clause("자동", ["bare"], t13, cnt_of(lambda x: x <= 0.45), ge(10), lambda x: "%s/n" % f0(x), ""),
        Clause("사람 대리", ["human"], t13, cnt_of(lambda x: x <= 0.30), ge(10), lambda x: "%s/n" % f0(x), "")])
    # T14
    def t14(r):
        return 1 if r.t_boss is not None and r.events_in("pu", r.t_boss, r.end) else 0
    add("RC-T14", "결", "우두머리 싸움 중 물약 1개 이상", "자동 ≥ 12/20", [
        Clause("자동", ["bare"], t14, lambda v: sum(v), ge(12), lambda x: "%s/n" % f0(x), "우두머리가 없으면(그 전에 짐) 0으로 셈")])
    # T15
    def t15(r):
        return (1, 1 if r.defeat_block() == "결" else 0) if r.mode == "defeat" else (0, 0)
    t15agg = lambda v: (sum(x[0] for x in v), sum(x[1] for x in v))
    add("RC-T15", "판", "패배", "자동 ≤ 2/20, 사람 대리 ≤ 5/20, 진 판의 70% 이상이 결에서", [
        Clause("자동", ["bare"], t15, t15agg, lambda t: t[0] <= 2 and (t[0] == 0 or t[1] / t[0] >= 0.7), lambda t: "진 %s판(결 %s)" % (f0(t[0]), f0(t[1])), ""),
        Clause("사람 대리", ["human"], t15, t15agg, lambda t: t[0] <= 5 and (t[0] == 0 or t[1] / t[0] >= 0.7), lambda t: "진 %s판(결 %s)" % (f0(t[0]), f0(t[1])), "")])
    # T16
    add("RC-T16", "전", "전 토막 권능 수", "6~7 (가운데)", [
        Clause("자동", ["bare"], lambda r: len(r.picks_in("전")) if r.t_boss is not None else None, med, inr(6, 7), f1, "관문 2의 쌍은 전, 관문 1의 쌍은 승으로 셈")])
    # T17
    def t17(r):
        pk = [p[0] for p in r.picks]
        gaps = [pk[i] - pk[i - 1] for i in range(1, len(pk)) if r.block_of(pk[i]) in ("전",) or (r.t_boss is not None and abs(pk[i] - r.t_boss) < 0.02 and i > 0)]
        return gaps if r.t_boss is not None else None
    def t17agg(v):
        gaps = [g for x in v if x for g in x]
        return (med(gaps), max(gaps) if gaps else None)
    add("RC-T17", "전", "전 토막 권능 간격", "가운데 12~22초, 최대 ≤ 30초", [
        Clause("자동", ["bare"], t17, t17agg, lambda t: t[0] is not None and 12 <= t[0] <= 22 and t[1] <= 30, lambda t: "가운데 %s / 최대 %s" % (f1(t[0]), f1(t[1])), "간격 = 전 토막 안(우두머리 등장 권능 포함)에서 끝나는 권능 사이. 판 모두의 최대")])
    # T18
    def t18(r):
        b = r.bounds()
        if "승" not in b or "전" not in b:
            return None
        ks = (r.kills_in(*b["승"]) / max(1e-9, b["승"][1] - b["승"][0]), r.kills_in(*b["전"]) / max(1e-9, b["전"][1] - b["전"][0]))
        ls, lj = r.life_med(*b["승"]), r.life_med(*b["전"])
        return (ks[1] / ks[0] if ks[0] > 0 else None, lj / ls if ls and lj else None)
    add("RC-T18", "전", "처치 속도의 오름", "전÷승 분당 처치 ≥ 1.5, 보통 적 수명 가운데 전 ≤ 승 × 0.75 (판마다 비의 가운데)", [
        Clause("자동", ["bare"], t18, lambda v: (med([x[0] for x in v if x]), med([x[1] for x in v if x])), lambda t: t[0] is not None and t[0] >= 1.5 and t[1] is not None and t[1] <= 0.75,
               lambda t: "처치비 %s / 수명비 %s" % (f2(t[0]), f2(t[1])), "수명 = 그 토막 안에서 태어나 죽은 보통 적, 살아남은 적은 뺌")])
    # T19
    def t19(r):
        return r.hp_min(r.t_g0, r.t_boss) if r.t_g0 is not None and r.t_boss is not None else None
    add("RC-T19", "전", "전 토막 최저 생명", "자동 ≥ 0.45 (14/20)", [
        Clause("자동", ["bare"], t19, cnt_of(lambda x: x >= 0.45), ge(14), lambda x: "%s/n" % f0(x), "")])
    # T20
    def t20(r):
        ev = r.first_pick_kind("evolve")
        c = r.crests("seung2")
        floor = None
        if c:
            nxt = [p[0] for p in r.picks if p[0] > c[0]]
            floor = nxt[0] if nxt else None
        return (ev, floor)
    def t20agg(v):
        evs = [x[0] for x in v if x[0] is not None]
        ok = sum(1 for x in v if x[0] is not None and x[1] is not None and x[0] <= x[1] + 1e-9)
        return (ok, len(v), (pct(evs, 0.9) - pct(evs, 0.1)) if len(evs) >= 2 else None)
    add("RC-T20", "전", "S3 진화 시각", "20/20이 승2 첫 머리 뒤 첫 권능 이전에 진화, 진화 시각 p10~p90 폭 ≥ 40초", [
        Clause("자동", ["bare"], t20, t20agg, lambda t: t[0] == t[1] and t[2] is not None and t[2] >= 40, lambda t: "%s/%s, 폭 %s초" % (f0(t[0]), f0(t[1]), f1(t[2])), "진화 시각 = 진화 카드를 고른 시각")])
    # T21
    def t21(r):
        small = [o for o in r.offers_sum if o[0] >= 15 and o[1] < 3]
        last = r.offers_sum[-1][1] if r.offers_sum else 0
        return (len(small), last)
    add("RC-T21", "전·결", "레벨 15 뒤 패의 카드 수", "모든 패 3장 이상 (마지막 큰 선택은 4)", [
        Clause("자동", ["bare"], t21, lambda v: (sum(1 for x in v if x[0] > 0), sum(1 for x in v if x[1] < 3)), lambda t: t[0] == 0 and t[1] == 0, lambda t: "3장 미만 패가 있는 판 %s / 마지막 선택 3장 미만 %s" % (f0(t[0]), f0(t[1])), "마지막 선택 4장은 데이터에 final_offer 키가 없어 3장 이상으로만 셈")])
    # T22
    def t22(r):
        bb = r.big_beats()
        return max((bb[i] - bb[i - 1] for i in range(1, len(bb))), default=None)
    add("RC-T22", "판", "큰 박자 사이 간격", "최대 ≤ 70초", [
        Clause("자동(대리 정의)", ["bare"], t22, lambda v: max([x for x in v if x is not None], default=None), le(70), f1, "큰 박자 = 열림·진화 선택, 수호자 처치(관문), 우두머리 등장, 필살기 준비. 지금 게임엔 큰 박자 표시가 없어 대리 정의")])
    # T23
    def t23(r):
        bb = r.big_beats()
        al = [(a / b if b else 0) for a, b in zip(r.s["alive"], r.s["an"])]
        dm = r.s["dmg"]
        hit = tot = 0
        for T in bb:
            lo = max(0, int(T - 60))
            hi = min(len(al), int(T) + 1)
            if hi - lo < 5:
                continue
            ia = max(range(lo, hi), key=lambda i: al[i])
            id_ = max(range(lo, min(hi, len(dm))), key=lambda i: dm[i]) if lo < len(dm) else ia
            tot += 1
            if (T - (ia + 0.5)) <= 25 or (T - (id_ + 0.5)) <= 25:
                hit += 1
        return (hit, tot)
    add("RC-T23", "판", "꼭대기 → 보상", "큰 박자 가운데 직전 25초 안에 그 앞 60초의 가장 큰 살아 있는 적 수 또는 가장 큰 받은 피해가 있었던 몫 ≥ 70%", [
        Clause("자동(대리 정의)", ["bare"], t23, lambda v: (sum(x[0] for x in v), sum(x[1] for x in v)), lambda t: t[1] > 0 and t[0] / t[1] >= 0.70, lambda t: "%s/%s (%.0f%%)" % (f0(t[0]), f0(t[1]), 100.0 * t[0] / max(1, t[1])), "큰 박자는 T22와 같은 대리 정의, 앞 60초의 꼭대기 = 초 단위 평균 살아 있는 적 수 또는 받은 피해의 최댓값 초")])
    # T24 / T25
    def t24(r):
        _ready, called = r.descent()
        return len(called)
    frac = lambda t: "%s/%s" % (f0(t[0]), f0(t[1]))
    fracagg = lambda v: (sum(v), len(v))
    ge70 = lambda t: t[1] > 0 and t[0] / t[1] >= 0.70
    add("RC-T24", "판", "필살기 횟수", "now에서 3번 ≥ 14/20, hold에서 2번 ≥ 14/20 (실제 코어의 켠 판, 모델 아님). 판 수가 계열마다 10이라 14/20을 70%로 읽음", [
        Clause("now 3번", ["dnow"], lambda r: 1 if t24(r) == 3 else 0, fracagg, ge70, frac, ""),
        Clause("hold 2번(참고)", ["dhold"], lambda r: 1 if t24(r) == 2 else 0, fracagg, ge70, frac,
               "도구의 hold 정책 = 첫째 준비부터 우두머리까지 아낌(판당 1번). 명세가 말한 'hold'(둘째만 아낌)가 아니라 이 값은 목표의 판정이 아니다 -> 줄의 판정에서 뺌, 재지 않음", ref=True, unmeasured=True)])
    def t25(r):
        ready, _c = r.descent()
        ok1 = len(ready) > 0 and r.t_s1 is not None and r.champ.get(0) is not None and r.t_s1 <= ready[0] <= r.champ[0]
        ok2 = len(ready) > 1 and r.t_g0 is not None and r.t_boss is not None and r.t_g0 < ready[1] < r.t_boss
        ok3 = len(ready) > 2 and r.t_boss is not None and r.t_boss - 40 <= ready[2] <= r.t_boss - 10
        return (1 if ok1 else 0, 1 if ok2 else 0, 1 if ok3 else 0)
    add("RC-T25", "판", "필살기 준비 시각", "첫째 승 토막 안(수호자 1 등장 전), 둘째 전 토막 안, 셋째 우두머리 등장 10~40초 앞 (now). 셋 모두 맞는 판 ≥ 14/20으로 읽음", [
        Clause("now", ["dnow"], t25, lambda v: (sum(x[0] for x in v), sum(x[1] for x in v), sum(x[2] for x in v), sum(1 for x in v if all(x)), len(v)),
               lambda t: t[4] > 0 and t[3] / t[4] >= 0.70, lambda t: "첫째 %s / 둘째 %s / 셋째 %s / 셋 모두 %s (판 %s)" % (f0(t[0]), f0(t[1]), f0(t[2]), f0(t[3]), f0(t[4])), "판 수가 계열마다 10이라 14/20을 70%로 읽음")])
    # T26
    def t26(r):
        a = w = 0
        for o in r.offers:
            ap, wr = floor_would_replace(o)
            a += 1
            w += wr
        return (w, a)
    add("RC-T26", "판", "카드 바닥이 바꿨을 패의 몫", "10~35%", [
        Clause("자동(도구 안 셈, 모델의 답)", ["bare"], t26, lambda v: (sum(x[0] for x in v), sum(x[1] for x in v)), lambda t: t[1] > 0 and 0.10 <= t[0] / t[1] <= 0.35,
               lambda t: "%s/%s (%.0f%%)" % (f0(t[0]), f0(t[1]), 100.0 * t[0] / max(1, t[1])), "4.3 규칙 1·2를 패 상태(살아 있는 적, 파도 나이, 수호자, 생명)로 셈. 보호 카드·후보 재고를 몰라 카드가 2장 이상인 패만 셈. 위 한계로 실제 바닥의 몫이 아니다")])
    # T27
    add("RC-T27", "판", "전투 길이", "400~470초 (가운데)", [
        Clause("자동", ["bare"], lambda r: r.secs, med, inr(400, 470), f1, "")])
    return C


def cmd_judge(args):
    sets = {}
    for name in ("bare", "human", "geared", "dnow", "dhold"):
        paths = getattr(args, name)
        sets[name] = [Run(r) for r in load_runs(paths)] if paths else []
        if sets[name] and name != "dhold" and not any(r.rc for r in sets[name]):
            print("warning: %s has no rc block" % name, file=sys.stderr)
    out = []
    P = out.append
    P("RC-T 표 판정. 자동 조작(chapter_pilot), 리듬·도입부 켬, 버티기 끔(--rhythm-on --no-trial-arena), 영구 트리 없음. 재표집 %d회, 씨앗 %d, 계열마다 값 옆에 10/90%%." % (DRAWS, SEED))
    P("판 수: " + ", ".join("%s %d" % (k, len(v)) for k, v in sets.items()))
    P("판정: 통과 = 관측값과 10/90% 값 모두 목표 안 / 못 미침 = 셋 모두 목표 밖 / 경계 = 판정선이 10~90% 폭 안 / 재지 않음 = 그 입력이 없음. 줄의 판정 = 잰 칸 가운데 하나라도 못 미침이면 못 미침, 아니면 경계가 있으면 경계, 아니면 통과(일부 칸이 재지 않음이면 '(일부)').")
    P("")
    summary = {}
    compact = []
    for rc_id, block, metric, target, clauses in build_clauses():
        cparts = []
        P("%s [%s] %s" % (rc_id, block, metric))
        P("   목표: %s" % target)
        verdicts = []
        unmeasured = 0
        for cl in clauses:
            if not any(sets.get(s) for s in cl.sets):
                P("   - %s: 재지 않음 (입력 없음)" % cl.label)
                cparts.append("%s: 재지 않음(입력 없음)" % cl.label)
                unmeasured += 1
                continue
            segs = []
            for pr, n, val, q10, q90, vd in run_clause(cl, sets):
                P("   - %s %-5s n=%-2d 값 %s | 10%% %s | 90%% %s | %s" % (cl.label, pr, n, val, q10, q90, vd))
                short = val.split(" [")[0]
                segs.append("%s %s (10%% %s / 90%% %s, n=%d) %s" % (pr, short, q10.split(" [")[0], q90.split(" [")[0], n, vd))
                if vd != "재지 않음" and not cl.ref:
                    verdicts.append(vd)
            cparts.append("%s: %s" % (cl.label, " ; ".join(segs)) + ("(참고 칸)" if cl.ref else ""))
            if cl.reading:
                P("       읽기: %s" % cl.reading)
            if cl.ref:
                P("       (참고 칸: 줄의 판정에 넣지 않음)")
                if cl.unmeasured:
                    unmeasured += 1
        if rc_id == "RC-T10" and sets["bare"]:
            P("   - 맨몸 계열 가운데의 최대÷최소 (재표집 포함)  %s" % ratio_across(sets["bare"], big_med(1), 1.4))
        if rc_id == "RC-T12":
            if sets["bare"]:
                P("   - 맨몸 계열 가운데의 최대÷최소 %s (목표 ≤ 1.3)" % ratio_across(sets["bare"], big_med(3), 1.3))
            if sets["geared"] and sets["bare"]:
                P("   - 장비÷맨몸 (같은 계열·시드 쌍의 가운데) %s (목표 ≥ 0.60)" % paired_ratio(sets))
        if rc_id == "RC-T10" and sets["geared"]:
            P("   - 장비 갖춤 계열 가운데의 최대÷최소 %s (참고)" % ratio_across(sets["geared"], big_med(1), 99))
        if not verdicts:
            final = "재지 않음"
        elif "못 미침" in verdicts:
            final = "못 미침"
        elif "경계" in verdicts:
            final = "경계"
        else:
            final = "통과"
        if verdicts and unmeasured and final in ("통과", "경계"):
            final += "(일부)"
        P("   => %s 판정: %s" % (rc_id, final))
        P("")
        summary[rc_id] = final
        compact.append("%s [%s] %s | 목표 %s\n    %s\n    => %s" % (rc_id, block, metric, target, "\n    ".join(cparts), final))
    appendix(sets, P)
    P("표 (27줄, 칸마다 계열별 값 (10%/90% 재표집) 판정)")
    for c in compact:
        P(c)
    P("")
    P("한 줄 요약 (27줄)")
    cnt = {"통과": 0, "못 미침": 0, "경계": 0, "재지 않음": 0}
    for k, v in summary.items():
        key = v if v in cnt else ("재지 않음" if v.endswith("(일부)") else v)
        cnt[key] = cnt.get(key, 0) + 1
    P("  통과 %d / 못 미침 %d / 경계 %d / 재지 않음 %d (일부 칸만 잰 줄의 '(일부)'는 재지 않음으로 셈)" % (cnt["통과"], cnt["못 미침"], cnt["경계"], cnt["재지 않음"]))
    P("  " + ", ".join("%s %s" % (k, v) for k, v in summary.items()))
    print_out(out, args.out)


def rng_txt(v, f="%.2f"):
    v = [x for x in v if x is not None]
    return "-" if not v else (f + " (" + f + "~" + f + ", n=%d)") % (statistics.median(v), min(v), max(v), len(v))


def appendix(sets, P):
    """RC-A 2 items that are not one RC-T line each: per block lowest life, potions, powers; S1/S2/S3 times; first rare; the 20 s before each big beat."""
    for name, label in (("bare", "맨몸"), ("human", "사람 대리"), ("geared", "장비 갖춤"), ("dnow", "필살기 now"), ("dhold", "필살기 hold")):
        runs = sets.get(name) or []
        if not runs or not runs[0].rc:
            continue
        P("[부록] %s %d판 — 토막별 값 (계열 합쳐 가운데(최소~최대, n))" % (label, len(runs)))
        for b in BLOCKS:
            hp, used, held, npk, lifes, dur = [], [], [], [], [], []
            for r in runs:
                bd = r.bounds()
                if b not in bd:
                    continue
                a, e = bd[b]
                dur.append(e - a)
                hp.append(r.hp_min(a, e))
                used.append(len(r.events_in("pu", a, e, False)))
                held.append(r.potions_at(max(a, e - 1.0)))
                npk.append(len(r.picks_in(b)))
                lifes.append(r.life_med(a, e))
            P("  %s: 길이 %s | 최저 생명 %s | 물약 사용 %s | 끝 보유 %s | 권능 %s | 보통 적 수명 가운데 %s" % (b, rng_txt(dur, "%.1f"), rng_txt(hp), rng_txt(used, "%.0f"), rng_txt(held, "%.0f"), rng_txt(npk, "%.0f"), rng_txt(lifes, "%.1f")))
        s1o = [r.first_offer_with("unlock") for r in runs]
        unl = [[p[0] for p in r.picks if p[2] == "unlock"] for r in runs]
        s1 = [u[0] if len(u) > 0 else None for u in unl]
        s2 = [u[1] if len(u) > 1 else None for u in unl]
        s3 = [r.first_pick_kind("evolve") for r in runs]
        rare = []
        rare_blk = {}
        for r in runs:
            d = [t for t, a in r.events_in("drop", 0, r.end) if a[0] in ("rare", "unique", "legendary", "set")]
            d1 = [t for t, a in r.events_in("drop", 0, r.end) if a[0] == "rare"]
            rare.append(d1[0] if d1 else None)
            if d1:
                rare_blk[r.block_of(d1[0])] = rare_blk.get(r.block_of(d1[0]), 0) + 1
        P("  S1(열림 카드가 패에 든 첫 시각) %s | 첫 열림 선택 %s | 둘째 열림 선택(S2) %s | 진화 선택(S3) %s" % (rng_txt(s1o, "%.1f"), rng_txt(s1, "%.1f"), rng_txt(s2, "%.1f"), rng_txt(s3, "%.1f")))
        P("  열림을 고른 수: 가운데 %s | 첫 희귀(rare) 시각 %s, 토막 %s" % (rng_txt([len(u) for u in unl], "%.0f"), rng_txt(rare, "%.1f"), rare_blk))
        pre = []
        gaps = []
        for r in runs:
            for T in r.big_beats():
                pre.append(r.hp_min(max(0, T - 20), T))
            bb = r.big_beats()
            gaps += [bb[i] - bb[i - 1] for i in range(1, len(bb))]
        P("  큰 박자(대리 정의) 직전 20초 최저 생명 %s | 큰 박자 사이 간격 %s" % (rng_txt(pre), rng_txt(gaps, "%.1f")))
        P("")


def big_med(k):
    return lambda r: float(r.big["guardian%d" % k]["lived_s"]) if ("guardian%d" % k) in r.big and r.big["guardian%d" % k]["death_s"] >= 0 else None


def ratio_across(runs, fn, limit):
    rng_ = random.Random(SEED)
    groups = {pr: [fn(r) for r in runs if r.prim == pr] for pr in PRIMS}
    groups = {k: v for k, v in groups.items() if v}
    if len(groups) < 2:
        return "-"

    def stat(g):
        m = [med(v) for v in g.values()]
        return max(m) / min(m) if m and min(m) else None
    obs = stat(groups)
    bs = []
    for _ in range(DRAWS):
        bs.append(stat({k: [v[rng_.randrange(len(v))] for _ in v] for k, v in groups.items()}))
    q10, q90 = pct(bs, 0.1), pct(bs, 0.9)
    ok = obs is not None and obs <= limit
    if limit < 90:
        verdict = "통과" if (obs <= limit and q90 <= limit) else ("못 미침" if q10 > limit else "경계")
    else:
        verdict = "참고"
    return "%s (10%% %s / 90%% %s) n=%d %s" % (fnum(obs, "%.2f"), fnum(q10, "%.2f"), fnum(q90, "%.2f"), sum(len(v) for v in groups.values()), verdict)


def paired_ratio(sets):
    bare = {(r.prim, r.seed): r for r in sets["bare"]}
    vals = []
    for r in sets["geared"]:
        b = bare.get((r.prim, r.seed))
        if b and "guardian3" in r.big and "guardian3" in b.big and r.big["guardian3"]["death_s"] >= 0 and b.big["guardian3"]["death_s"] >= 0:
            vals.append((r.prim, float(r.big["guardian3"]["lived_s"]) / float(b.big["guardian3"]["lived_s"])))
    if not vals:
        return "-"
    parts = []
    rng_ = random.Random(SEED)
    for pr in PRIMS:
        v = [x for p, x in vals if p == pr]
        if not v:
            continue
        bs = [med([v[rng_.randrange(len(v))] for _ in v]) for _ in range(DRAWS)]
        o = med(v)
        q10, q90 = pct(bs, 0.1), pct(bs, 0.9)
        vd = "통과" if q10 >= 0.60 else ("못 미침" if q90 < 0.60 else "경계")
        parts.append("%s %.2f (10%% %.2f / 90%% %.2f, n=%d) %s" % (pr, o, q10, q90, len(v), vd))
    return " | ".join(parts)


def print_out(lines, out):
    text = "\n".join(lines) + "\n"
    sys.stdout.buffer.write(text.encode("utf-8"))
    if out:
        p = Path(out)
        if not str(p).replace("\\", "/").startswith("_local/"):
            print("--out must be under _local/", file=sys.stderr)
            sys.exit(2)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")


# ------------------------------------------------------------------ bf: the boss finale lines (D-boss-finale 6절 BF-T1..T8 + the boss-life shares of 7절 (a)(b))
def bf_of(r, hp):
    """One run's finale numbers from rc.ev (be / bp / bs / bx / bc / bo / pu rows) and rc.fin; None when the run had no finale."""
    if not r.rc or "fin" not in r.rc:
        return None
    fin = r.rc["fin"]
    ev = r.rc["ev"]
    first = lambda tag: next((e for e in ev if e[1] == tag), None)
    be = first("be")
    if be is None:
        return None
    g3 = r.big.get("guardian3")
    end = round(float(g3["death_s"]) * 60) if g3 and g3["death_s"] >= 0 else round(r.secs * 60)
    bp = {e[2]: e[0] for e in ev if e[1] == "bp"}
    bs = {e[2]: e[0] for e in ev if e[1] == "bs"}
    bx = {e[2]: e[0] for e in ev if e[1] == "bx"}
    o = {"fight": (end - be[0]) / 60.0, "entrance": ((bp[1] - be[0]) / 60.0) if 1 in bp else None}
    ph_end = {1: bs.get(0), 2: bs.get(1), 3: end}
    o["work"] = [((ph_end[k] - bp[k]) / 60.0) if (k in bp and ph_end[k] is not None) else None for k in (1, 2, 3)]
    o["brk"] = [((bx[i] - bs[i]) / 60.0) if (i in bs and i in bx) else None for i in (0, 1)]
    o["brk_ticks"] = [(bx[i] - bs[i]) if (i in bs and i in bx) else None for i in (0, 1)]
    got = o["entrance"] or 0.0
    got += sum(b for b in o["brk"] if b is not None)
    o["brk_share"] = got / o["fight"] if o["fight"] > 0 else None
    kb, hb, hb_hits = fin.get("kills_break", {}), fin.get("hurt_break", {}), fin.get("hits_break", {})
    o["kills_brk"] = [int(kb.get(str(i), 0)) if i in bs else None for i in (0, 1)]
    o["hurt_brk"] = [int(hb.get(str(i), 0)) / 256.0 if i in bs else None for i in (0, 1)]
    o["hits_brk"] = [int(hb_hits.get(str(i), 0)) if i in bs else None for i in (0, 1)]
    hp_ph = fin.get("hurt_phase", {})
    o["hurt_phase"] = [int(hp_ph.get(str(k), 0)) / 256.0 for k in (1, 2, 3)]
    pu = [e[0] for e in ev if e[1] == "pu" and e[0] >= be[0]]
    o["pot_fight"] = len(pu)
    o["pot_brk1"] = sum(1 for t in pu if 1 in bs and 1 in bx and bs[1] <= t <= bx[1])
    o["pot_brk0"] = sum(1 for t in pu if 0 in bs and 0 in bx and bs[0] <= t <= bx[0])
    o["chip_bps"] = max([e[3] for e in ev if e[1] == "bc"], default=0)
    o["potion_drop"] = any(e[1] == "bo" for e in ev)
    dealt = fin.get("boss_dealt", {})
    full = float(hp) * 256.0
    prim = "chapter1.skill." + r.prim
    o["share_prim"] = float(dealt.get(prim, 0)) / full
    o["share_aux"] = sum(float(v) for k, v in dealt.items() if k != prim) / full
    o["share_by"] = {k: float(v) / full for k, v in dealt.items()}
    o["other_dealt"] = float(fin.get("other_dealt", 0)) / 256.0
    lh = fin.get("last_hit", {})
    o["defeat"] = r.mode == "defeat"
    if o["defeat"]:
        sec = int(r.secs)
        lo = max(0, sec - 3)
        low = min(r.hp_s[lo:sec + 1]) if r.hp_s else None
        o["death"] = {"attack_id": lh.get("attack_id", ""), "source_kind": lh.get("source_kind", ""), "hp_3s": low}
    o["hp_min"] = r.hp_min(be[0] / 60.0, end / 60.0)
    o["hit_by"] = fin.get("hit_by")  # None for a run made before measure_rhythm wrote it
    return o


def cmd_bf(args):
    sets = {}
    for name in ("bare", "human", "geared", "dnow"):
        paths = getattr(args, name)
        sets[name] = [Run(r) for r in load_runs(paths)] if paths else []
    BF = {name: {id(r): bf_of(r, args.hp) for r in rs} for name, rs in sets.items()}
    for name, rs in sets.items():
        for r in rs:
            r.bf = BF[name][id(r)]
    inr = lambda lo, hi: (lambda x: x is not None and lo <= x <= hi)
    f1 = lambda x: "-" if x is None else "%.1f" % x
    f2 = lambda x: "-" if x is None else "%.2f" % x
    f0 = lambda x: "-" if x is None else "%.0f" % x
    medl = lambda v, k: med([x[k] for x in v if x and x[k] is not None])
    out = []
    P = out.append
    P("BF-T 판정(D-boss-finale 6절). 재표집 %d회, 씨앗 %d, 10/90%% 폭 안에 줄이 있으면 경계. 우두머리 체력 %d(우두머리 몫 = 입힌 피해 ÷ 체력×256). 사람 재미는 미평가." % (DRAWS, SEED, args.hp))
    P("판 수: " + ", ".join("%s %d (우두머리 싸움이 있었던 판 %d)" % (k, len(v), sum(1 for r in v if r.bf)) for k, v in sets.items()))
    P("")

    def clause_run(label, cl):
        P("   - %s" % label)
        for pr, n, val, q10, q90, vd in run_clause(cl, sets):
            P("       %-5s n=%-2d 값 %s | 10%% %s | 90%% %s | %s" % (pr, n, val, q10, q90, vd))
        return [vd for *_x, vd in run_clause(cl, sets)]

    def per(fn):
        return lambda r: fn(r.bf) if r.bf else None

    verdicts = {}

    def finish(rc_id, vds):
        vds = [v for v in vds if v != "재지 않음"]
        v = "재지 않음" if not vds else ("못 미침" if "못 미침" in vds else ("경계" if "경계" in vds else "통과"))
        verdicts[rc_id] = v
        P("   => %s 판정: %s" % (rc_id, v))
        P("")

    # T1
    P("BF-T1 국면마다의 일(초, 계열 가운데) | 맨몸 1국면 7~20, 2국면 7~20, 3국면 6~17 / 장비 갖춤 각 2.5 이상")
    w = lambda r: r.bf["work"] if r.bf and None not in r.bf["work"] else None
    aggw = lambda v: tuple(med([x[i] for x in v if x]) for i in range(3))
    fw = lambda t: "%s / %s / %s" % tuple(f1(x) for x in t)
    vds = []
    vds += clause_run("맨몸 (1/2/3국면)", Clause("맨몸", ["bare"], w, aggw, lambda t: inr(7, 20)(t[0]) and inr(7, 20)(t[1]) and inr(6, 17)(t[2]), fw, ""))
    vds += clause_run("장비 갖춤 (각 2.5 이상)", Clause("장비", ["geared"], w, aggw, lambda t: all(x is not None and x >= 2.5 for x in t), fw, ""))
    finish("BF-T1", vds)
    # T2
    P("BF-T2 쉼의 실제 길이 | 데이터 값(600, 540틱) ± 6틱, 20/20 (장비·강림 켬 열 포함)")
    # a run that was lost inside a break has no end to measure: not counted (None), a finished break must be on the data value
    def brk(r):
        b = r.bf
        if not b:
            return None
        if b["defeat"] and None in b["brk_ticks"]:
            return None
        t0, t1 = b["brk_ticks"]
        return 1 if (t0 is not None and t1 is not None and abs(t0 - 600) <= 6 and abs(t1 - 540) <= 6) else 0
    vds = []
    for nm, lab in (("bare", "맨몸"), ("geared", "장비 갖춤"), ("human", "사람 대리"), ("dnow", "강림 now")):
        if sets[nm]:
            vds += clause_run(lab, Clause(lab, [nm], brk, lambda v: (sum(x for x in v if x is not None), len([x for x in v if x is not None])), lambda t: t[0] == t[1], lambda t: "%s/%s" % (f0(t[0]), f0(t[1])), ""))
    finish("BF-T2", vds)
    # T3
    P("BF-T3 쉼(표적 빠짐: 등장 + 쉼 둘)의 몫 | 맨몸 ≤ 45%, 장비 갖춤 ≤ 60%")
    vds = []
    vds += clause_run("맨몸", Clause("맨몸", ["bare"], per(lambda b: b["brk_share"]), med, lambda x: x is not None and x <= 0.45, f2, ""))
    vds += clause_run("장비 갖춤", Clause("장비", ["geared"], per(lambda b: b["brk_share"]), med, lambda x: x is not None and x <= 0.60, f2, ""))
    finish("BF-T3", vds)
    # T4
    P("BF-T4 쉼 동안의 일 | 쉼 하나마다 맨몸 자동 처치 가운데 ≥ 10, 처치도 받은 피해도 없는 쉼 ≤ 10%")
    k4 = lambda r: (r.bf["kills_brk"], r.bf["hurt_brk"]) if r.bf else None

    def k4agg(v):
        v = [x for x in v if x]
        kk = [med([x[0][i] for x in v if x[0][i] is not None]) for i in (0, 1)]
        empty = sum(1 for x in v for i in (0, 1) if x[0][i] is not None and x[0][i] == 0 and (x[1][i] or 0) == 0)
        tot = sum(1 for x in v for i in (0, 1) if x[0][i] is not None)
        return (kk[0], kk[1], empty, tot)
    vds = clause_run("맨몸", Clause("맨몸", ["bare"], k4, k4agg, lambda t: t[0] is not None and t[1] is not None and t[0] >= 10 and t[1] >= 10 and t[3] > 0 and t[2] / t[3] <= 0.10,
                                  lambda t: "쉼1 처치 가운데 %s / 쉼2 %s / 빈 쉼 %s/%s" % (f1(t[0]), f1(t[1]), f0(t[2]), f0(t[3])), ""))
    finish("BF-T4", vds)
    # T5
    P("BF-T5 큰 공격의 전조 | 데이터 검사(측정 아님): 코어가 켠 판에서 읽는 값 — 몸 85/54틱, 바닥 65/72, 내리찍기 70/72, 착지 55/72, 폭풍 40/60 (주인공 기본 120의 20% = 24 이상은 모두 54틱 이상) -> 통과(손으로 읽음, 도구가 다시 읽지 않음)")
    verdicts["BF-T5"] = "통과(데이터 읽기)"
    P("")
    # T6
    P("BF-T6 죽음이 읽히는가 | 진 판의 80% 이상에서 마지막 타격이 전조가 있던 공격(attack_id 있음)이거나 죽기 전 3초 동안 생명이 30% 아래")
    vds = []
    for nm, lab in (("bare", "맨몸"), ("human", "사람 대리"), ("geared", "장비 갖춤"), ("dnow", "강림 now")):
        d = [(r.prim, r.seed, r.bf["death"]) for r in sets[nm] if r.bf and r.bf["defeat"]]
        if sets[nm]:
            P("   - %s: 우두머리에서 진 판 %d / %d" % (lab, len(d), len(sets[nm])))
            for pr, sd, dd in d:
                P("       %s seed %d: 마지막 타격 attack_id=%r source=%s, 죽기 3초 최저 생명 %s" % (pr, sd, dd["attack_id"], dd["source_kind"], f2(dd["hp_3s"])))
            if d:
                ok = sum(1 for _p, _s, dd in d if dd["attack_id"] != "" or (dd["hp_3s"] is not None and dd["hp_3s"] < 0.30))
                P("       읽히는 죽음 %d/%d (%.0f%%) -> %s" % (ok, len(d), 100.0 * ok / len(d), "통과" if ok / len(d) >= 0.8 else "못 미침"))
                vds.append("통과" if ok / len(d) >= 0.8 else "못 미침")
    finish("BF-T6", vds)
    if not vds:
        verdicts["BF-T6"] = "재지 못함(진 판 없음)"
    # T7
    P("BF-T7 쉼 2의 물약 | 자동(맨몸), 쉼 2 안에서 물약을 쓴 판 ≥ 8/20")
    vds = clause_run("맨몸", Clause("맨몸", ["bare"], per(lambda b: 1 if b["pot_brk1"] >= 1 else 0), lambda v: sum(x for x in v if x is not None), lambda x: x >= 8, lambda x: "%s/n" % f0(x), ""))
    finish("BF-T7", vds)
    # T8
    P("BF-T8 강림 켬(now) 참고 | 맨몸 싸움 ≥ 45초 (판정에 넣지 않음)")
    if sets["dnow"]:
        for pr, n, val, q10, q90, vd in run_clause(Clause("강림 now", ["dnow"], per(lambda b: b["fight"]), med, lambda x: x is not None and x >= 45, f1, ""), sets):
            P("   - %-5s n=%-2d 값 %s | 10%% %s | 90%% %s | (참고) %s" % (pr, n, val, q10, q90, vd))
    P("")
    # records
    P("[기록, 판정에 쓰지 않음] 계열별 가운데(최소~최대, n)")
    for nm, lab in (("bare", "맨몸"), ("geared", "장비 갖춤"), ("human", "사람 대리"), ("dnow", "강림 now")):
        if not sets[nm]:
            continue
        P("  %s" % lab)
        for pr in PRIMS:
            rs = [r.bf for r in sets[nm] if r.prim == pr and r.bf]
            if not rs:
                continue
            g = lambda k, f="%.1f": rng_txt([x[k] for x in rs if x[k] is not None], f)
            P("    %-5s 싸움 %s초 | 등장 %s | 1국면 일 %s | 쉼1 %s | 2국면 일 %s | 쉼2 %s | 3국면 일 %s" % (pr, g("fight"), rng_txt([x["entrance"] for x in rs], "%.1f"), rng_txt([x["work"][0] for x in rs if x["work"][0] is not None], "%.1f"),
                                                                                         rng_txt([x["brk"][0] for x in rs if x["brk"][0] is not None], "%.2f"), rng_txt([x["work"][1] for x in rs if x["work"][1] is not None], "%.1f"),
                                                                                         rng_txt([x["brk"][1] for x in rs if x["brk"][1] is not None], "%.2f"), rng_txt([x["work"][2] for x in rs if x["work"][2] is not None], "%.1f")))
            P("          우두머리 몫 주력 %s / 보조 %s / 사슬 깎기 %.0f bps | 쉼 처치 %s / %s | 쉼 받은 피해(생명 단위) %s / %s | 국면 받은 피해 %s / %s / %s" % (
                rng_txt([x["share_prim"] for x in rs], "%.2f"), rng_txt([x["share_aux"] for x in rs], "%.2f"), med([x["chip_bps"] for x in rs]),
                rng_txt([x["kills_brk"][0] for x in rs if x["kills_brk"][0] is not None], "%.0f"), rng_txt([x["kills_brk"][1] for x in rs if x["kills_brk"][1] is not None], "%.0f"),
                rng_txt([x["hurt_brk"][0] for x in rs if x["hurt_brk"][0] is not None], "%.0f"), rng_txt([x["hurt_brk"][1] for x in rs if x["hurt_brk"][1] is not None], "%.0f"),
                rng_txt([x["hurt_phase"][0] for x in rs], "%.0f"), rng_txt([x["hurt_phase"][1] for x in rs], "%.0f"), rng_txt([x["hurt_phase"][2] for x in rs], "%.0f")))
            hb = {}
            for x in rs:
                for k, v in (x.get("hit_by") or {}).items():
                    hb.setdefault(k, []).append(v)
            if hb:
                P("          맞은 공격(판당 맞은 수 평균 / 한 번이라도 맞은 판 / 스친 수 합 / 받은 피해 합의 판당 평균, 생명 단위): " + " | ".join("%s %.2f / %d판 / %d / %.1f" % (k, sum(v[0] for v in vs) / len(rs), len(vs), sum(v[2] for v in vs), sum(v[1] for v in vs) / 256.0 / len(rs)) for k, vs in sorted(hb.items())))
            sk = {}
            for x in rs:
                for k, v in x["share_by"].items():
                    sk.setdefault(k.replace("chapter1.skill.", ""), []).append(v)
            P("          기술별 우두머리 몫(가운데) %s | 싸움 중 최저 생명 %s | 물약 싸움 %s (쉼1 %s / 쉼2 %s), 쉼2 물약 쓴 판 %d/%d | 진 판 %d" % (
                ", ".join("%s %.3f" % (k, med(v)) for k, v in sorted(sk.items())), rng_txt([x["hp_min"] for x in rs if x["hp_min"] is not None]),
                rng_txt([x["pot_fight"] for x in rs], "%.0f"), rng_txt([x["pot_brk0"] for x in rs], "%.0f"), rng_txt([x["pot_brk1"] for x in rs], "%.0f"),
                sum(1 for x in rs if x["pot_brk1"] >= 1), len(rs), sum(1 for x in rs if x["defeat"])))
    P("")
    P("한 줄 요약: " + ", ".join("%s %s" % (k, v) for k, v in verdicts.items()))
    print_out(out, args.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("bf")
    for k in ("bare", "human", "geared", "dnow"):
        b.add_argument("--" + k, nargs="*")
    b.add_argument("--hp", type=int, default=15000, help="the boss's health in the tuning (boss_finale.hp)")
    b.add_argument("--out")
    n = sub.add_parser("now")
    n.add_argument("files", nargs="+")
    n.add_argument("--cost", action="append", help="3000,8000,N (repeatable): the descent costs to try beside the shipped 3000,8000,10000")
    n.add_argument("--out")
    j = sub.add_parser("judge")
    for k in ("bare", "human", "geared", "dnow", "dhold"):
        j.add_argument("--" + k, nargs="*")
    j.add_argument("--out")
    args = ap.parse_args()
    {"now": cmd_now, "judge": cmd_judge, "bf": cmd_bf}[args.cmd](args)


if __name__ == "__main__":
    main()
