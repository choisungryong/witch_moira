#!/usr/bin/env python3
"""sim_grid.py - 시험장(chapter1/tests/sim_power.gd) 유입률 칸을 격자로 돌리고 "같은 점수 견줌" 표를 낸다.

N0(KS-3 이전 코어)와 N1(KS-3 코어를 시험장 안에서만 켬)에서 두 번 쓴 실행기와 표 만들기를 올린 것이다.
모든 수치는 자동 조작(봇)의 실측이다. 안정성·밸런스 참고 자료이며 재미는 평가하지 않는다(사람 평가가 없으면 "미평가").
데이터 파일(chapter1/data/**)은 고치지 않는다: 값은 시험장 인수(--set, --ring-*, --basic-reach, --i0)로 메모리 안에서만 바꾼다.

  python tools/dev/sim_grid.py list                                   # 실험 이름과 칸 수
  python tools/dev/sim_grid.py run  <exp> [--out DIR] [--jobs 2] [--seeds 11,12,13] [--witches frost,ember,arc] [--dry] [--force]
  python tools/dev/sim_grid.py table <exp> [--out DIR] [--witches ...]      # 원시(DIR/raw/<exp>)에서 표
  python tools/dev/sim_grid.py table-all [--out DIR]                       # 모든 실험의 표

--out 기본값은 _local/tools/sim_grid (저장소 안의 _local 아래만 허용: sim_power.gd의 --out 규칙).
동시에 띄우는 Godot는 --jobs(기본 2, 최대 4). Godot는 tools/dev/godot.py로만 부른다. 같은 이름의 원시가 있으면 건너뛴다(--force로 다시).
한 칸 = (마녀, 빌드, 태그, 마디, 조작, 시드). 조작 묶음: S = stand 4마디, S3 = stand 3마디(승 2·전 A·버티기), L = slow 3마디, P = pilot 승 2.
"""
import argparse
import concurrent.futures as cf
import glob
import json
import math
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PY = sys.executable
BEATS = ["seung1", "seung2", "jeon_a", "trial"]
BN = {"seung1": "승1", "seung2": "승2", "jeon_a": "전A", "trial": "버티기"}
WITCHES = ["frost", "ember", "arc"]
VSETS = {
    "S": ("stand", BEATS),
    "S3": ("stand", ["seung2", "jeon_a", "trial"]),
    "L": ("slow", ["seung2", "jeon_a", "trial"]),
    "P": ("pilot", ["seung2"]),
}
# 빌드 이름 -> 시험장 build 문자열. 모두 축 점수 6(= 한 주문 상한). A = 자기 기본기, R = 자기 원형, X = 빌려온 기본기.
BUILDS = {
    "noring": "A:d4",            # 기본기만(점수 4, 원형 없음) - 원형이 더하는 것의 기준
    "NB6": "A:d4r2",             # 하나만 쌓기(기본기 피해 4 + 넓이 2)
    "NB6w": "A:d3r3",            # 하나만 쌓기(넓이 쪽)
    "SY6": "A:d4+R:r2",          # 시너지: 기본기 피해 4 + 원형 차단 2
    "SY6b": "A:d3+R:r3",         # 시너지: 기본기 피해 3 + 원형 차단 3(번개는 대상 7)
    "SY6p": "A:d4+R:d2",         # 같은 점수, 원형 위력 쪽(알맞은 축인가)
    "RO6": "R:d3r3",             # 원형만 쌓기(기본기 0점)
    "RNDa": "A:d1r1+R:d1r1+X:d1r1",   # 아무거나 막 찍기 a(주문 셋에 흩음)
    "RNDb": "A:r2+R:d2+X:d1r1",       # 아무거나 막 찍기 b
    "NB7": "A:d4r2+crystal",     # 카드 수 맞춤(주문을 여는 카드도 한 장으로 센다): 하나만 쌓기 + 결정
    "RND7a": "A:d1r1+R:d1r1+X:d1",     # 카드 수 맞춤: 주문 둘을 여는 카드 2장 + 축 5점
    "RND7b": "A:d2+R:d1+X:d1r1",
    "SYE": "A:d3r2+R:r2+crystal+evo",    # 문턱 보상까지: 결정 + 진화(기본기 축 합 5, 원형 축 합 2). 7점 + 결정 + 진화 카드
    "SYEb": "A:d4r1+R:r2+crystal+evo",
    "SY0": "A:d4+R",             # 원형 0점(격자에서 --ring-* 절대값을 얹음)
    "SY0b": "A:d4",              # 노링 별칭(격자 기준)
}


def ring_id(witch):
    return "spells/chapter1.skill.%s_ring" % witch


class Job:
    def __init__(self, witch, build, tag, vset, extra=(), spec=None, seeds=None):
        self.witch, self.build, self.tag, self.vset = witch, build, tag, vset
        self.seeds = seeds  # None = 명령줄 --seeds
        self.extra = list(extra)
        self.spec = spec or BUILDS[build]

    def out(self, outdir, exp):
        return "%s/raw/%s/%s_%s_%s_%s.json" % (outdir, exp, self.witch, self.build, self.tag, self.vset)

    def command(self, outdir, exp, seeds):
        variant, beats = VSETS[self.vset]
        return [PY, "tools/dev/godot.py", "--headless", "--path", ".", "--script", "res://chapter1/tests/sim_power.gd", "--",
                "--witches=" + self.witch, "--seeds=" + (self.seeds or seeds), "--mode=inflow", "--tally", "--n0",
                "--inflow-beat=" + ",".join(beats), "--inflow-variants=" + variant, "--build=" + self.spec] + self.extra + ["--out=" + self.out(outdir, exp)]


# ----------------------------------------------------------------------------- 실험(작업 목록)

def exp_base(witches):
    """N1-1·5의 바탕: 같은 점수 빌드 9종 x (stand 4마디 + slow 3마디 + pilot 승 2), 데이터 파일 값 그대로."""
    names = ["noring", "NB6", "NB6w", "SY6", "SY6b", "SY6p", "RO6", "RNDa", "RNDb"]
    # RNDb는 냉기에서만(시간: 스스로 정한 것)
    return [Job(w, n, "base", v) for w in witches for n in names if n != "RNDb" or w == "frost" for v in ("S", "L", "P")]


def ring_knobs(cd, dx, floor, witch, freeze=None, stagger=None, stun=None, radius=2.4):
    a = ["--ring-cd=%.3f" % cd, "--ring-cd-all", "--ring-dmg-x-walker=%s" % dx, "--set=%s/base/falloff_floor_bps=%d" % (ring_id(witch), floor)]
    if radius is not None:
        a.append("--ring-radius=%s" % radius)
    if freeze is not None:
        a.append("--set=%s/base/freeze_ticks=%d" % (ring_id(witch), freeze))
    if stagger is not None:
        a.append("--set=%s/base/stagger_ticks=%d" % (ring_id(witch), stagger))
    if stun is not None:
        a.append("--set=%s/base/stun_ticks=%d" % (ring_id(witch), stun))
    return a


def grid_tag(cd, dx, floor, extra=""):
    return "c%.2f_x%s_f%d%s" % (cd, dx, floor, extra)


def exp_grid(witches):
    """N1-1·2·3: 원형 피해(보행자 체력 배수) x 감쇠 바닥 x 쿨. 원형 0점(SY0) 위에 값을 직접 얹고 stand 3마디."""
    jobs = []
    for w in witches:
        # 냉기는 전부(27칸), 화염·번개는 모서리만(8칸): 시간 때문에 스스로 정한 것
        full = w == "frost"
        for cd in ((0.5, 0.7, 0.9) if full else (0.5, 0.9)):
            for dx in ((0.5, 0.75, 1.0) if full else (0.5, 1.0)):
                for fl in ((10000, 7000, 4000) if full else (10000, 4000)):
                    jobs.append(Job(w, "SY0", grid_tag(cd, dx, fl), "S3", ring_knobs(cd, dx, fl, w)))
    return jobs


def exp_gridl(witches):
    """격자에서 고른 칸에 slow(받은 피해)와 pilot(열린 처리량)을 더한다. 어느 칸인지는 GRIDL_PICK."""
    jobs = []
    for w in witches:
        for cd, dx, fl in GRIDL_PICK:
            for v in ("L", "P"):
                jobs.append(Job(w, "SY0", grid_tag(cd, dx, fl), v, ring_knobs(cd, dx, fl, w)))
    return jobs


GRIDL_PICK = [(0.5, 0.5, 10000), (0.5, 1.0, 4000), (0.7, 0.75, 7000), (0.7, 1.0, 7000), (0.9, 1.0, 4000)]


def exp_hold(witches):
    """구조 쪽 대안: 원형은 약하게 치고 오래 묶고(빙결·흔들림·경련 틱을 늘림) 기본기가 마무리한다."""
    jobs = []
    for w in witches:
        for dx in (0.25, 0.4):
            for ctl in (80, 150, 240):
                kw = {"frost": dict(freeze=ctl), "ember": dict(stagger=min(ctl, 180)), "arc": dict(stun=min(ctl, 120))}[w]
                tag = "hold_x%s_t%d" % (dx, kw[list(kw)[0]])
                for cd in (0.5, 0.7):
                    jobs.append(Job(w, "SY0", tag + "_c%.1f" % cd, "S3", ring_knobs(cd, dx, 10000, w, **kw)))
    return jobs


def exp_i0(witches):
    """N1-2: I0 끔(prefer_kinds 비움)과 켬(base 칸)의 비. stand 3마디 + slow 3마디."""
    names = ["noring", "SY6", "RO6"]
    return [Job(w, n, "i0off", v, ["--i0=off"]) for w in witches for n in names for v in ("S3", "L")]


I0_GRID = [(100, 900), (0, 900), (200, 1300), (0, 1300)]  # (prefer_when_clear_cm, prefer_kind_cm); 쓰는 값은 200, 900


def exp_i0d(witches):
    """N1-2 힘 쪽: I0의 조건 거리를 바꿔 본다(가까이 붙은 적이 없다고 치는 거리 prefer_when_clear_cm, 원거리를 찾는 거리 prefer_kind_cm). 0이면 가까이 적이 있어도 늘 원거리 먼저."""
    jobs = []
    for w in witches:
        for clear, kind in I0_GRID:
            extra = ["--set=spells/chapter1.skill.%s/prefer_when_clear_cm=%d" % (w, clear), "--set=spells/chapter1.skill.%s/prefer_kind_cm=%d" % (w, kind)]
            for n in ("SY6", "RO6"):
                jobs.append(Job(w, n, "i0c%dk%d" % (clear, kind), "S3", extra))
            jobs.append(Job(w, "SY6", "i0c%dk%d" % (clear, kind), "L", extra))
    return jobs


ILK_RINGS = [(0.5, 0.5, 10000), (0.5, 0.75, 4000)]
ILK_VALUES = [(6000, 4000), (12000, 4000), (18000, 4000), (12000, 10000), (18000, 10000)]  # (I1 vs_cc 빙결 bps, I2 터뜨림 bonus bps). 쓰는 값은 6000, 4000


def exp_ilk(witches):
    """구조 쪽 대안 2: 맞물림 값(I1 제어된 적에게 +%, I2 터뜨림 +%)을 키워 기본기가 마무리하는 몫을 늘린다. 냉기만(빙결 키: vs_cc/frozen, detonates/chill/bonus_bps)."""
    jobs = []
    for w in witches:
        if w != "frost":
            continue
        for cd, dx, fl in ILK_RINGS:
            for vs, det in ILK_VALUES:
                if (vs, det) == (6000, 4000):
                    continue  # 격자 칸과 같다
                extra = ring_knobs(cd, dx, fl, w) + ["--set=spells/chapter1.skill.frost/vs_cc/frozen=%d" % vs, "--set=%s/detonates/chill/bonus_bps=%d" % (ring_id(w), det)]
                jobs.append(Job(w, "SY0", grid_tag(cd, dx, fl, "_v%d_d%d" % (vs, det)), "S3", extra))
    return jobs


def exp_bud(witches):
    """구조 쪽 대안 3: 원형이 한 번에 치는 수(예산)를 줄인다. 둘레 전체를 쓸어 버리면 한 번에 많이 죽여 기본기 몫이 없다. 쿨 0.5초, 바닥 7000."""
    jobs = []
    for w in witches:
        for dx in (0.5, 0.75):
            for b in (3, 5, 7):
                jobs.append(Job(w, "SY0", grid_tag(0.5, dx, 7000, "_b%d" % b), "S3", ring_knobs(0.5, dx, 7000, w) + ["--ring-budget=%d" % b]))
    return jobs


SLOWX_SEEDS = "14,15,16,17,18,19"


def exp_slowx(witches):
    """slow 30초 받은 피해는 시드 흩어짐이 커서 시드를 더한다(14~19, base 칸과 같은 태그라서 table base가 9시드로 합친다). 냉기만(시간)."""
    return [Job(w, n, "base", "L", seeds=SLOWX_SEEDS) for w in witches if w == "frost" for n in ("noring", "NB6", "NB6w", "SY6", "SY6p", "RO6", "RNDa")]


def exp_width(witches):
    """N1-4: 기본기 넓이 축을 낮춘 두 값(half = 한 단계를 반으로, none = 넓이 점이 아무것도 안 올림)에서 순위."""
    # 넓이 점이 없는 빌드(noring, SY6, SY6b, SY6p, RO6)는 이 인수에 영향이 없어 base 칸을 그대로 쓴다.
    return [Job(w, n, "w" + mode, v, ["--basic-reach=" + mode]) for w in witches for mode in ("half", "none") for n in WIDTH_BUILDS for v in ("S3", "P")]


WIDTH_BUILDS = ["NB6", "NB6w", "RNDa"]
WIDTH_FREE = ("noring", "SY6", "SY6b", "SY6p", "RO6")  # 넓이 점이 없다 = 넓이 인수에 불변


def exp_mix(witches):
    """N1-5: 원거리 많음(50:45:5)과 원거리 0에서 원형만 ÷ 시너지. stand 3마디 + slow 3마디."""
    jobs = []
    for w in witches:
        for n in ("noring", "SY6", "RO6"):
            jobs.append(Job(w, n, "mix50-45-5", "S3", ["--inflow-mix=50:45:5"]))
            jobs.append(Job(w, n, "mix50-45-5", "L", ["--inflow-mix=50:45:5"]))
            if w == "frost":  # 원거리 0은 냉기만(스스로 정한 것: 시간)
                jobs.append(Job(w, n, "mix-ranged", "S3", ["--inflow-mix=-ranged"]))
    return jobs


def exp_cards7(witches):
    """카드 수를 맞춘 견줌: 주문을 여는 카드도 한 장으로 센다. SY6·RO6는 원형을 여는 카드 1장 + 축 6점 = 7장, NB는 결정을 더해 7장, 아무거나는 주문 둘을 여는 2장 + 축 5점 = 7장."""
    return [Job(w, n, "cards7", v) for w in witches if w == "frost" for n in ("NB7", "RND7a", "RND7b") for v in ("S3", "L", "P")]  # 냉기만(시간)


def exp_evo(witches):
    """문턱 보상(결정 + 진화)을 더한 시너지 빌드. 같은 점수가 아니다(점수 7 + 카드 둘 더). 아무거나가 시너지를 이기는 것이 문턱 보상이 빠져서인지 본다. 냉기만."""
    return [Job(w, n, "evo", v) for w in witches if w == "frost" for n in ("SYE", "SYEb") for v in ("S3", "L", "P")]


def exp_cut(witches):
    """N1-3: 원거리·돌격을 하나씩 뺀 섞임에서 기본기만 대 시너지(stand 3마디). 남는 위협이 무엇인지 가른다."""
    return [Job(w, n, "mix" + m, "S3", ["--inflow-mix=" + m]) for w in witches for n in ("noring", "SY6") for m in ("-charger", "-both")]


EXPERIMENTS = {"base": exp_base, "grid": exp_grid, "gridl": exp_gridl, "hold": exp_hold, "i0": exp_i0, "width": exp_width, "mix": exp_mix, "cut": exp_cut, "cards7": exp_cards7, "i0d": exp_i0d, "ilk": exp_ilk, "evo": exp_evo, "bud": exp_bud, "slowx": exp_slowx}


def jobs_of(exp, witches):
    return EXPERIMENTS[exp](witches)


def run_jobs(jobs, exp, outdir, seeds, nproc, dry=False, force=False):
    def one(job):
        out = job.out(outdir, exp)
        if (ROOT / out).is_file() and not force:
            return out, 0, "skip (exists)"
        cmd = job.command(outdir, exp, seeds)
        if dry:
            return out, 0, " ".join(cmd)
        (ROOT / out).parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
        lines = [ln for ln in r.stdout.splitlines() if "RESULT" in ln]
        return out, r.returncode, (lines[-1][-120:] if lines else (r.stdout + r.stderr)[-300:])
    with cf.ThreadPoolExecutor(nproc) as pool:
        for res in pool.map(one, jobs):
            print(res, flush=True)


# ----------------------------------------------------------------------------- 표(집계)

def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def spread(xs):
    """시드 흩어짐 = 절반 범위 / 평균(0.3 = +-30% 선)."""
    m = mean(xs)
    return (max(xs) - min(xs)) / (2 * abs(m)) if len(xs) > 1 and m else 0.0


def ratio(a, b):
    return a / b if b and b == b and a == a else float("nan")


class Store:
    """(witch, build, tag, beat, variant) -> 칸(시드마다 하나) 목록."""

    def __init__(self):
        self.g = defaultdict(list)

    def load(self, outdir, exp):
        root = Path(outdir) if os.path.isabs(outdir) else ROOT / outdir
        for p in sorted(glob.glob(str(root / "raw" / exp / "*.json"))):
            base = os.path.basename(p)[:-5]
            witch, rest = base.split("_", 1)
            build, rest = rest.split("_", 1)
            tag = rest.rsplit("_", 1)[0]
            with open(p, encoding="utf-8") as fh:
                cells = json.load(fh)["cells"]
            for c in cells:
                self.g[(witch, build, tag, c["beat"], c["variant"])].append(c)

    def vals(self, key, f):
        out = []
        for c in self.g.get(key, []):
            v = f(c) if callable(f) else c.get(f)
            if v is not None:
                out.append(float(v))
        return out

    def m(self, key, f):
        return mean(self.vals(key, f))

    def unstable(self, key, f, limit=0.30, floor=3.0):
        xs = self.vals(key, f)
        return len(xs) > 1 and abs(mean(xs)) > floor and spread(xs) > limit


def contact_hits(c):
    s = c.get("src_hits", {})
    return float(s.get("walker", 0) + s.get("charger", 0))


def ranged_hits(c):
    return float(c.get("src_hits", {}).get("ranged", 0))


def i1_chance(c):
    return 100.0 * c.get("ward", {}).get("vs_cc_hits", 0) / max(1, c.get("basic_hits", 0))


METRICS = [  # 이름, 키 또는 함수, 폭, 소수 자리
    ("cont%", "contact_share_pct", 6, 1), ("cHit", contact_hits, 5, 0), ("rHit", ranged_hits, 5, 0), ("tk30%", "taken_30s_pct", 7, 0), ("P", "power_hp_s", 6, 1),
    ("kill/s", "kill_per_s", 6, 2), ("al/cap", lambda c: c["alive_mean"] / max(1, c["alive_cap"]), 6, 2), ("ring%", "ring_kill_share_pct", 5, 0),
    ("R<6m", "ranged_in_6m", 5, 1), ("aliveR", "alive_ranged", 6, 1), ("I1%", i1_chance, 5, 0), ("i1x%", "i1_extra_share_pct", 5, 1), ("i2x%", "i2_extra_share_pct", 5, 1),
    ("dead", "dead_np_s", 5, 1),
    ("rKill", lambda c: c.get("ranged_kills_basic", 0) + c.get("ranged_kills_ring", 0) + c.get("ranged_kills_other", 0), 5, 0), ("i0c", lambda c: c.get("ward", {}).get("i0_casts", 0), 4, 0),
    ("wHP", lambda c: c.get("src_dmg_hp", {}).get("walker", 0), 5, 0), ("rHP", lambda c: c.get("src_dmg_hp", {}).get("ranged", 0), 5, 0), ("cHP", lambda c: c.get("src_dmg_hp", {}).get("charger", 0), 5, 0)]


def metric_table(store, title, rows, beats, variant):
    """rows = [(표시 이름, witch, build, tag)]. 마디마다 한 블록. * = 3시드 흩어짐 > 30%."""
    out = ["== " + title + " (variant=%s, 시드 평균; * = 시드 흩어짐 >30%%)" % variant]
    for beat in beats:
        out.append("-- %s" % BN[beat])
        out.append("%-24s | %s" % ("cell", " ".join("%*s" % (w, n) for n, f, w, d in METRICS)))
        for label, witch, build, tag in rows:
            key = (witch, build, tag, beat, variant)
            if key not in store.g:
                continue
            cells = []
            for n, f, w, d in METRICS:
                xs = store.vals(key, f)
                x = mean(xs)
                star = "*" if len(xs) > 1 and spread(xs) > 0.30 and abs(x) > 3 else " "
                cells.append(("%*.*f" % (w, d, x) if x == x else "%*s" % (w, "-")) + star)
            out.append("%-24s | %s" % (label, " ".join(cells)))
    return out


def best_nb(store, witch, tag, beat, variant, f, lower):
    """하나만 쌓기(NB6·NB6w) 가운데 그 지표에서 NB에 가장 유리한 쪽(스스로 정한 규칙: 판정에 가장 엄한 쪽)."""
    cand = []
    for n in ("NB6", "NB6w"):
        key = (witch, n, tag, beat, variant)
        if key in store.g:
            cand.append((store.m(key, f), n, store.unstable(key, f)))
    cand = [c for c in cand if c[0] == c[0]]
    if not cand:
        return float("nan"), None, False
    return (min if lower else max)(cand, key=lambda c: c[0])


LINES = [  # 이름, 조작, 마디, 지표, 낮을수록 좋음, 통과 조건, 통과선 글
    ("접촉 시간 몫 SY/NB최선", "stand", BEATS, "contact_share_pct", True, lambda r: r <= 0.5, "<=0.5"),
    ("접촉 맞은 횟수 SY/NB최선", "stand", BEATS, contact_hits, True, lambda r: r <= 0.3, "<=0.3"),
    ("slow 30초 받은 피해 SY/NB최선", "slow", ["seung2", "jeon_a", "trial"], "taken_30s_pct", True, lambda r: r <= 0.6, "<=0.6"),
    ("열린 처리량 P_open SY/NB최선", "pilot", ["seung2"], "power_hp_s", False, lambda r: r >= 0.7, ">=0.7"),
    ("밀착 처리량 P_close SY/NB최선", "stand", BEATS, "power_hp_s", False, lambda r: r >= 1.6, ">=1.6(목표 1.6~2.0)"),
]


def pass_lines(store, witch, syn="SY6", tag="base"):
    out = ["%-34s %-18s | %s" % ("줄(%s, %s)" % (witch, syn), "통과선", "  ".join("%-9s" % BN[b] for b in BEATS))]
    for name, var, beats, f, lower, ok, line in LINES:
        cells = []
        for b in BEATS:
            if b not in beats:
                cells.append("%-9s" % "n/a")
                continue
            s = store.m((witch, syn, tag, b, var), f)
            nb, who, nbun = best_nb(store, witch, tag, b, var, f, lower)
            r = ratio(s, nb)
            un = store.unstable((witch, syn, tag, b, var), f) or nbun
            cells.append("%-9s" % ((("%.2f" % r) + ("*" if un else "") + ("o" if r == r and ok(r) else "x")) if r == r else "-"))
        out.append("%-34s %-18s | %s" % (name, line, "  ".join(cells)))
    for name, var, beats, f, lower, ok, line in (("원형 처치 몫 % (<=60)", "stand", BEATS, "ring_kill_share_pct", True, lambda r: r <= 60, ""),
                                                ("I1 맞은 비율 %", "stand", BEATS, i1_chance, False, lambda r: True, "기록"),
                                                ("I1+I2 추가 피해 몫 %", "stand", BEATS, lambda c: c.get("i1_extra_share_pct", 0) + c.get("i2_extra_share_pct", 0), False, lambda r: True, "기록(20~40)"),
                                                ("6m 안 원거리 수", "stand", BEATS, "ranged_in_6m", True, lambda r: True, "기록")):
        cells = []
        for b in BEATS:
            x = store.m((witch, syn, tag, b, var), f)
            un = store.unstable((witch, syn, tag, b, var), f)
            cells.append("%-9s" % (("%.1f" % x) + ("*" if un else "") if x == x else "-"))
        out.append("%-34s %-18s | %s" % (name, line, "  ".join(cells)))
    out.append("(o 통과 / x 미달 / * 시드 흩어짐 >30%이라 판정에 쓰지 않음. NB최선 = NB6·NB6w 가운데 그 줄에서 NB에 유리한 쪽)")
    return out


def versus(store, witch, tag="base"):
    """같은 점수 빌드끼리 한눈에: 마디마다 SY6를 나머지로 나눈 값(접촉·받은 피해·처리량)."""
    out = ["== %s SY6 / 상대 (stand 접촉·stand P_close·slow 받은 피해·pilot P_open). 접촉·받은 피해는 낮을수록, P는 높을수록 SY6가 낫다" % witch]
    others = ["NB6", "NB6w", "RO6", "SY6p", "RNDa", "RNDb", "noring"]
    out.append("%-7s | %s" % ("상대", " | ".join("%-27s" % BN[b] for b in BEATS)))
    for o in others:
        cells = []
        for b in BEATS:
            parts = []
            for var, f in (("stand", "contact_share_pct"), ("stand", "power_hp_s"), ("slow", "taken_30s_pct"), ("pilot", "power_hp_s")):
                parts.append("%5.2f" % ratio(store.m((witch, "SY6", tag, b, var), f), store.m((witch, o, tag, b, var), f)) if (witch, o, tag, b, var) in store.g else "    -")
            cells.append("%-27s" % " ".join(parts))
        out.append("%-7s | %s" % (o, " | ".join(cells)))
    out.append("(각 칸 = 접촉 / P_close / 받은 피해(slow) / P_open(pilot, 승2만))")
    return out


def table_base(store, witches):
    out = []
    for w in witches:
        out += ["", "######## %s" % w, ""]
        for syn in ("SY6", "SY6b"):
            out += pass_lines(store, w, syn) + [""]
        out += versus(store, w) + [""]
        rows = [(n, w, n, "base") for n in ("noring", "NB6", "NB6w", "SY6", "SY6b", "SY6p", "RO6", "RNDa", "RNDb")]
        for var, beats in (("stand", BEATS), ("slow", ["seung2", "jeon_a", "trial"]), ("pilot", ["seung2"])):
            out += metric_table(store, "%s 같은 점수 빌드" % w, rows, beats, var) + [""]
    return out


def table_generic(store, witches, tags, builds, title, variants=(("stand", BEATS),)):
    out = []
    for w in witches:
        rows = [("%s %s" % (b, t), w, b, t) for t in tags for b in builds]
        for var, beats in variants:
            out += metric_table(store, "%s [%s]" % (title, w), rows, beats, var) + [""]
    return out


def grid_summary(store, witches, tags_picker):
    """격자: 칸마다 접촉(SY/NB최선)·원형 처치 몫·I1 맞은 비율·추가 피해 몫·P_close. 승2·전A·버티기 한 줄에 모아 본다."""
    out = []
    for w in witches:
        tags = sorted({k[2] for k in store.g if k[0] == w and k[1] == "SY0" and tags_picker(k[2])})
        if not tags:
            continue
        out.append("== %s 격자: stand, SY0(원형 0점 + 절대값) / NB최선(base). 칸 = 접촉비 | 원형처치%% | I1%% | 추가피해%%(I1+I2) | P_close비 (승2 / 전A / 버티기). 접촉비 <=0.5 이고 원형처치 <=60 이면 'OK'" % w)
        out.append("%-26s | %s" % ("tag(쿨,피해x보행자체력,바닥)", " | ".join("%-38s" % BN[b] for b in ("seung2", "jeon_a", "trial"))))
        for t in tags:
            cells, ok_all = [], True
            for b in ("seung2", "jeon_a", "trial"):
                key = (w, "SY0", t, b, "stand")
                if key not in store.g:
                    cells.append("%-38s" % "-")
                    continue
                nbc, _, _ = best_nb(store, w, "base", b, "stand", "contact_share_pct", True)
                nbp, _, _ = best_nb(store, w, "base", b, "stand", "power_hp_s", False)
                rc = ratio(store.m(key, "contact_share_pct"), nbc)
                rk = store.m(key, "ring_kill_share_pct")
                ok = rc <= 0.5 and rk <= 60
                ok_all &= ok
                st = "*" if store.unstable(key, "contact_share_pct") else " "
                cells.append("%-38s" % ("%.2f%s %3.0f %3.0f %4.1f %.2f%s" % (rc, st, rk, store.m(key, i1_chance), store.m(key, lambda c: c.get("i1_extra_share_pct", 0) + c.get("i2_extra_share_pct", 0)), ratio(store.m(key, "power_hp_s"), nbp), " OK" if ok else "")))
            out.append("%-26s | %s%s" % (t, " | ".join(cells), "   <- 세 마디 모두 OK" if ok_all else ""))
        out.append("")
    return out


def table_exp(store, exp, witches):
    if exp == "base":
        return table_base(store, witches)
    if exp == "grid":
        return grid_summary(store, witches, lambda t: t.startswith("c"))
    if exp == "gridl":
        out = []
        for w in witches:
            rows = [("SY0 " + grid_tag(*r), w, "SY0", grid_tag(*r)) for r in GRIDL_PICK] + [(n + " 기본", w, n, "base") for n in ("noring", "NB6", "NB6w", "SY6", "SY6p", "RO6", "RNDa")]
            out += metric_table(store, "격자 선택 칸 slow [%s]" % w, rows, ["seung2", "jeon_a", "trial"], "slow") + [""]
            out += metric_table(store, "격자 선택 칸 pilot [%s]" % w, rows, ["seung2"], "pilot") + [""]
        return out
    if exp == "hold":
        return grid_summary(store, witches, lambda t: t.startswith("hold"))
    if exp == "i0":
        out = []
        for w in witches:
            rows = [("%s I0 %s" % (b, lab), w, b, tag) for b in ("noring", "SY6", "RO6") for lab, tag in (("켬", "base"), ("끔", "i0off"))]
            for var, beats in (("stand", ["seung2", "jeon_a", "trial"]), ("slow", ["seung2", "jeon_a", "trial"])):
                out += metric_table(store, "N1-2 I0 켬/끔 [%s]" % w, rows, beats, var) + [""]
            out += i0_ratio(store, w)
        return out
    if exp == "width":
        out = []
        for w in witches:
            for mode in ("base", "whalf", "wnone"):
                rows = [(b, w, b, "base" if b in WIDTH_FREE else mode) for b in ("noring", "NB6", "NB6w", "SY6", "SY6b", "RNDa", "RO6")]
                for var, beats in (("stand", BEATS[1:]), ("pilot", ["seung2"])):
                    out += metric_table(store, "N1-4 넓이 축 %s [%s]" % (mode, w), rows, beats, var) + [""]
            out += width_rank(store, w)
        return out
    if exp == "evo":
        out = []
        for w in witches:
            rows = [("SYE A:d3r2+R:r2+결정+진화", w, "SYE", "evo"), ("SYEb A:d4r1+R:r2+결정+진화", w, "SYEb", "evo"), ("SY6", w, "SY6", "base"), ("NB7 A:d4r2+결정", w, "NB7", "cards7"), ("NB6w", w, "NB6w", "base"),
                    ("RO6", w, "RO6", "base"), ("RNDa", w, "RNDa", "base"), ("RND7a", w, "RND7a", "cards7")]
            for var, beats in (("stand", BEATS[1:]), ("slow", BEATS[1:]), ("pilot", ["seung2"])):
                out += metric_table(store, "문턱 보상 [%s]" % w, rows, beats, var) + [""]
        return out
    if exp == "cards7":
        out = []
        for w in witches:
            rows = [("NB7(A:d4r2+결정)", w, "NB7", "cards7"), ("SY6(원형 열기 1+6점)", w, "SY6", "base"), ("RO6(원형 열기 1+6점)", w, "RO6", "base"),
                    ("RND7a(둘 열기 2+5점)", w, "RND7a", "cards7"), ("RND7b(둘 열기 2+5점)", w, "RND7b", "cards7")]
            for var, beats in (("stand", BEATS[1:]), ("slow", BEATS[1:]), ("pilot", ["seung2"])):
                out += metric_table(store, "카드 7장 맞춤 [%s]" % w, rows, beats, var) + [""]
        return out
    if exp == "bud":
        return grid_summary(store, witches, lambda t: "_b" in t)
    if exp == "ilk":
        return grid_summary(store, witches, lambda t: "_v" in t or t in {grid_tag(*r) for r in ILK_RINGS})
    if exp == "i0d":
        out = []
        for w in witches:
            rows = [("%s I0 clear%d kind%d" % (b, c, k), w, b, "i0c%dk%d" % (c, k)) for b in ("SY6", "RO6") for c, k in I0_GRID] + [("%s I0 기본(200/900)" % b, w, b, "base") for b in ("SY6", "RO6")]
            rows.sort(key=lambda r: r[0])
            out += metric_table(store, "N1-2 I0 조건 거리 [%s]" % w, rows, BEATS[1:], "stand") + [""]
            rows = [("SY6 I0 clear%d kind%d" % (c, k), w, "SY6", "i0c%dk%d" % (c, k)) for c, k in I0_GRID] + [("SY6 I0 기본(200/900)", w, "SY6", "base")]
            out += metric_table(store, "N1-2 I0 조건 거리 [%s]" % w, rows, BEATS[1:], "slow") + [""]
        return out
    if exp == "cut":
        out = []
        for w in witches:
            rows = [("%s %s" % (b, lab), w, b, tag) for lab, tag in (("기본섞임", "base"), ("-원거리", "mix-ranged"), ("-돌격", "mix-charger"), ("-둘 다", "mix-both")) for b in ("noring", "SY6")]
            out += metric_table(store, "N1-3 위협을 하나씩 뺌 [%s]" % w, rows, ["seung2", "jeon_a", "trial"], "stand") + [""]
            out.append("== %s SY6 / noring 30초 받은 피해 비(stand). 통과선 <=0.5는 '그 위협을 뺐을 때 원형이 받는 피해를 줄이는가'" % w)
            for lab, tag in (("기본섞임", "base"), ("-원거리", "mix-ranged"), ("-돌격", "mix-charger"), ("-둘 다", "mix-both")):
                cells = []
                for b in ("seung2", "jeon_a", "trial"):
                    s, n = (w, "SY6", tag, b, "stand"), (w, "noring", tag, b, "stand")
                    un = "*" if store.unstable(s, "taken_30s_pct") or store.unstable(n, "taken_30s_pct") else " "
                    cells.append("%s %.2f%s (%.0f/%.0f)" % (BN[b], ratio(store.m(s, "taken_30s_pct"), store.m(n, "taken_30s_pct")), un, store.m(s, "taken_30s_pct"), store.m(n, "taken_30s_pct")))
                out.append("%-8s | %s" % (lab, " | ".join(cells)))
            out.append("")
        return out
    if exp == "mix":
        out = []
        for w in witches:
            rows = [("%s %s" % (b, lab), w, b, tag) for b in ("noring", "SY6", "RO6") for lab, tag in (("기본섞임", "base"), ("50:45:5", "mix50-45-5"), ("원거리0", "mix-ranged"))]
            out += metric_table(store, "N1-5 원거리 많음 [%s]" % w, rows, BEATS[1:], "stand") + [""]
            out += metric_table(store, "N1-5 원거리 많음 [%s]" % w, rows, ["seung2", "jeon_a", "trial"], "slow") + [""]
            out += mix_ratio(store, w)
        return out
    return []


def i0_ratio(store, w):
    out = ["== %s N1-2: I0 켬 / I0 끔 비(<=0.5가 통과선: 6m 안 원거리 수, 살아 있는 원거리 수). 받은 피해·원거리 맞은 횟수 비도 함께" % w]
    out.append("%-8s %-6s | %s" % ("build", "move", " | ".join("%-40s" % BN[b] for b in ("seung2", "jeon_a", "trial"))))
    for b in ("noring", "SY6", "RO6"):
        for var in ("stand", "slow"):
            cells = []
            for beat in ("seung2", "jeon_a", "trial"):
                on, off = (w, b, "base", beat, var), (w, b, "i0off", beat, var)
                un = "*" if store.unstable(on, "ranged_in_6m") or store.unstable(off, "ranged_in_6m") else " "
                cells.append("R6m %.2f%s aliveR %.2f tk30 %.2f rHit %.2f" % (ratio(store.m(on, "ranged_in_6m"), store.m(off, "ranged_in_6m")), un, ratio(store.m(on, "alive_ranged"), store.m(off, "alive_ranged")),
                                                                              ratio(store.m(on, "taken_30s_pct"), store.m(off, "taken_30s_pct")), ratio(store.m(on, ranged_hits), store.m(off, ranged_hits))))
            out.append("%-8s %-6s | %s" % (b, var, " | ".join("%-40s" % c for c in cells)))
    return out


def mix_ratio(store, w):
    out = ["== %s N1-5: 원형만(RO6) ÷ 시너지(SY6). 원거리 많음 stand 받은 피해(30초)·slow 받은 피해·6m 안 원거리·살아 있는 원거리·P. 목표: 받은 피해 비 >=1.5(원거리 많음 stand)" % w]
    out.append("%-14s %-6s | %s" % ("mix", "move", " | ".join("%-44s" % BN[b] for b in BEATS[1:])))
    for lab, tag in (("기본섞임", "base"), ("50:45:5", "mix50-45-5"), ("원거리0", "mix-ranged")):
        for var in ("stand", "slow"):
            cells = []
            for beat in BEATS[1:]:
                a, s = (w, "RO6", tag, beat, var), (w, "SY6", tag, beat, var)
                if a not in store.g or s not in store.g:
                    cells.append("-")
                    continue
                un = "*" if store.unstable(a, "taken_30s_pct") or store.unstable(s, "taken_30s_pct") else " "
                cells.append("tk30 %.2f%s R6m %.2f aliveR %.2f P %.2f" % (ratio(store.m(a, "taken_30s_pct"), store.m(s, "taken_30s_pct")), un, ratio(store.m(a, "ranged_in_6m"), store.m(s, "ranged_in_6m")),
                                                                         ratio(store.m(a, "alive_ranged"), store.m(s, "alive_ranged")), ratio(store.m(a, "power_hp_s"), store.m(s, "power_hp_s"))))
            out.append("%-14s %-6s | %s" % (lab, var, " | ".join("%-44s" % c for c in cells)))
    return out


def width_rank(store, w):
    out = ["== %s N1-4 넓이 축 낮춤: NB 최선 대비 SY6의 P(stand 4마디, pilot 승2)와 접촉" % w]
    out.append("%-8s | %s" % ("넓이", " | ".join("%-34s" % BN[b] for b in BEATS)))
    for mode in ("base", "whalf", "wnone"):
        cells = []
        for b in BEATS:
            def nbp(var, f, lower):
                xs = []
                for n in ("NB6", "NB6w"):
                    k = (w, n, mode, b, var)
                    if k in store.g:
                        xs.append(store.m(k, f))
                xs = [x for x in xs if x == x]
                return (min if lower else max)(xs) if xs else float("nan")
            sy = (w, "SY6", "base", b, "stand")  # SY6는 넓이 점이 없어 인수에 불변
            cells.append("Pc %.2f cont %.2f Po %s" % (ratio(store.m(sy, "power_hp_s"), nbp("stand", "power_hp_s", False)), ratio(store.m(sy, "contact_share_pct"), nbp("stand", "contact_share_pct", True)),
                                                      ("%.2f" % ratio(store.m((w, "SY6", "base", b, "pilot"), "power_hp_s"), nbp("pilot", "power_hp_s", False))) if b == "seung2" else "-"))
        out.append("%-8s | %s" % (mode, " | ".join("%-34s" % c for c in cells)))
    out.append("(Pc = stand P_close SY6/NB최선, cont = stand 접촉 몫 SY6/NB최선, Po = pilot P_open SY6/NB최선)")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["list", "run", "table", "table-all"])
    ap.add_argument("exp", nargs="?")
    ap.add_argument("--out", default="_local/tools/sim_grid")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--seeds", default="11,12,13")
    ap.add_argument("--witches", default=",".join(WITCHES))
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args(argv)
    witches = a.witches.split(",")
    if not a.out.startswith("_local/") or ".." in a.out:
        ap.error("--out must be a relative path under _local/")
    if a.cmd == "list":
        for name in EXPERIMENTS:
            jobs = jobs_of(name, witches)
            cells = sum(len(VSETS[j.vset][1]) * len(a.seeds.split(",")) for j in jobs)
            print("%-6s jobs=%-4d cells=%-5d %s" % (name, len(jobs), cells, (EXPERIMENTS[name].__doc__ or "").strip().splitlines()[0]))
        return 0
    if a.cmd == "run":
        if a.exp not in EXPERIMENTS:
            ap.error("unknown experiment (see list)")
        if not 1 <= a.jobs <= 4:
            ap.error("--jobs must be 1..4")
        run_jobs(jobs_of(a.exp, witches), a.exp, a.out, a.seeds, a.jobs, a.dry, a.force)
        return 0
    exps = list(EXPERIMENTS) if a.cmd == "table-all" else [a.exp]
    for exp in exps:
        store = Store()
        store.load(a.out, exp)
        # 기준(NB 최선)은 base의 원시에서, slow 시드 보강(slowx)은 base와 같은 칸에 합쳐서 가져온다
        extra = {"cut": ["mix"], "ilk": ["grid"], "gridl": ["grid"], "evo": ["cards7"], "bud": ["grid"]}.get(exp, [])
        for dep in ["base", "slowx"] + extra:
            if dep != exp:
                store.load(a.out, dep)
        print("\n" + "=" * 100 + "\n" + exp + "\n" + "=" * 100)
        print("\n".join(table_exp(store, exp, witches)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
