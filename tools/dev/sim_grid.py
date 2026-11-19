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
    "SY8": "A:d4+R:r4",          # N2-3 점수 8: 시너지
    "NB8": "A:d4r4",             # 점수 8 하나만 쌓기(한 주문 합 8 > 상한 6: 게임에서는 못 만듦 = 하나만에게 후한 쪽)
    "RO8": "R:d4r4",             # 점수 8 원형만(같은 사정)
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


# ----------------------------------------------------------------------------- N2: 조합 줄(안 3)의 흉내
# D16 2.3절: 줄의 곱은 빌드가 고정이라 칸에서 상수다. 그 상수를 base 피해에 미리 곱해 흉내 낸다(코어 줄 없이, 데이터 파일은 그대로).
#   울타리 차단 1점마다 자기 기본기 피해 +sb%(상한 4점), 기본기 피해 1점마다 울타리 피해 +sr%(상한 4점), 거래 기본기 넓이 1점마다 자기 기본기 피해 +sx%(상한 3점)
#   거래 기본기의 피해는 bm%로 시작(거래 감쇠), --cfg의 wh면 시험장 --basic-reach=half(기본기 넓이 축 약화)
# 한 설정(Cfg) = 값 묶음(c = 권하는 접촉 값을 얹음 / d = 데이터 파일 값 그대로) + 줄 크기 + 거래 감쇠 + 넓이.

SK = "chapter1.skill."
BORROW = {"ember": "frost", "frost": "ember", "arc": "ember"}  # sim_power.gd의 BORROW와 같다
CFGS = []   # --cfg 로 채움
SCORE = 6   # --score 로 채움


class Cfg:
    def __init__(self, val="c", sb=0, sr=0, bm=100, sx=10, wh=False, rate=False):
        self.val, self.sb, self.sr, self.bm, self.sx, self.wh, self.rate = val, sb, sr, bm, sx, wh, rate

    @staticmethod
    def parse(text):
        """'c:15/25/60' = 접촉 값, 차단->기본기 15%, 피해->울타리 25%, 거래 피해 60%. 뒤에 ':x10'(거래 줄 %), ':wh'(넓이 반)를 붙일 수 있다."""
        parts = text.split(":")
        sb, sr, bm = [int(x) for x in parts[1].split("/")]
        sx, wh, rate = 10, False, False
        for p in parts[2:]:
            if p == "wh":
                wh = True
            elif p == "rate":
                rate = True
            elif p.startswith("x"):
                sx = int(p[1:])
        return Cfg(parts[0], sb, sr, bm, sx, wh, rate)

    def zero(self):
        return Cfg(self.val, 0, 0, 100, 0, self.wh, self.rate)

    def is_zero(self):
        return self.sb == 0 and self.sr == 0 and self.bm == 100 and self.sx == 0

    def tag(self):
        if self.val == "d" and self.is_zero() and not self.wh:
            return "base"   # N1의 base 원시와 같은 칸(인수 없음)
        return "%s-s%d-%d-b%d-x%d%s%s" % (self.val, self.sb, self.sr, self.bm, self.sx, "-rt" if self.rate else "", "-wh" if self.wh else "")

    def __str__(self):
        return "%s:%d/%d/%d:x%d%s%s" % (self.val, self.sb, self.sr, self.bm, self.sx, ":rate" if self.rate else "", ":wh" if self.wh else "")


_RAW = {}


def spell_raw():
    if not _RAW:
        with open(ROOT / "chapter1/data/run_spells.json", encoding="utf-8") as fh:
            for k, s in json.load(fh)["spells"].items():
                _RAW[k] = int(s["base"]["damage_raw"])
    return _RAW


_CD = {}


def spell_cd():
    """spell id -> (base 쿨 틱, {reach 단계: 그 단계가 덮어쓰는 쿨 틱})."""
    if not _CD:
        with open(ROOT / "chapter1/data/run_spells.json", encoding="utf-8") as fh:
            for k, s in json.load(fh)["spells"].items():
                _CD[k] = (int(s["base"]["cooldown_ticks"]), {i: int(r["cooldown_ticks"]) for i, r in enumerate(s["reach"]) if "cooldown_ticks" in r})
    return _CD


def spec_axes(spec):
    """'A:d4r2+R:r2+X:d1' -> {'A': (4, 2), 'R': (0, 2), 'X': (1, 0)}. crystal·evo 토큰은 무시."""
    out = {}
    for tok in spec.split("+"):
        tok = tok.strip()
        if tok in ("crystal", "evo", ""):
            continue
        key, _, ax = tok.partition(":")
        d = r = 0
        i = 0
        while i < len(ax):
            if ax[i] in "dr" and i + 1 < len(ax) and ax[i + 1].isdigit():
                if ax[i] == "d":
                    d = int(ax[i + 1])
                else:
                    r = int(ax[i + 1])
                i += 2
            else:
                i += 1
        out[key] = (d, r)
    return out


def contact_args(witch):
    """N1 0절이 권한 접촉 값을 시험장 인수로: 쿨 0단 0.7초(42틱) 차단 2점 이상 0.5초(30틱), 0단 피해 = 그 마디 보행자 체력, 감쇠 바닥 4000."""
    ring = SK + witch + "_ring"
    return ["--ring-dmg-x-walker=1.0", "--set=spells/%s/base/cooldown_ticks=42" % ring, "--set=spells/%s/reach/2/cooldown_ticks=30" % ring,
            "--set=spells/%s/reach/3/cooldown_ticks=30" % ring, "--set=spells/%s/base/falloff_floor_bps=4000" % ring]


def cfg_args(witch, spec, cfg):
    """빌드 문자열과 설정에서 시험장 인수를 계산한다(줄의 곱은 base 피해에 미리 곱함)."""
    ax = spec_axes(spec)
    raw = spell_raw()
    a_id, x_id = SK + witch, SK + BORROW[witch]
    out = []
    if cfg.val == "c" and "R" in ax:
        out += contact_args(witch)
    am = 1.0
    if "R" in ax:
        am += cfg.sb / 100.0 * min(ax["R"][1], 4)
    if "X" in ax:
        am += cfg.sx / 100.0 * min(ax["X"][1], 3)
    rm = 1.0 + cfg.sr / 100.0 * min(ax.get("A", (0, 0))[0], 4) if "R" in ax else 1.0
    if cfg.rate:
        # 탐침(D16 밖): 줄이 피해 대신 "쏘는 빈도"를 곱한다 = 쿨 ÷ 배율. 일반 적은 한 발에 죽어 피해 곱은 넘침이 되는지 보려는 것
        if abs(am - 1.0) > 1e-9:
            out.append("--set=spells/%s/base/cooldown_ticks=%d" % (a_id, max(12, round(spell_cd()[a_id][0] / am))))
        if "R" in ax and abs(rm - 1.0) > 1e-9:
            ring = SK + witch + "_ring"
            base_cd, reach_cd = spell_cd()[ring]
            if cfg.val == "c":
                base_cd, reach_cd = 42, {i: 30 for i in reach_cd}
            out.append("--set=spells/%s/base/cooldown_ticks=%d" % (ring, max(12, round(base_cd / rm))))
            for i, v in reach_cd.items():
                out.append("--set=spells/%s/reach/%d/cooldown_ticks=%d" % (ring, i, max(12, round(v / rm))))
    else:
        if abs(am - 1.0) > 1e-9:
            out.append("--set=spells/%s/base/damage_raw=%d" % (a_id, round(raw[a_id] * am)))
        if "R" in ax and abs(rm - 1.0) > 1e-9:
            out.append("--ring-dmg=%.4f" % rm)
    if "X" in ax and cfg.bm != 100:
        out.append("--set=spells/%s/base/damage_raw=%d" % (x_id, round(raw[x_id] * cfg.bm / 100.0)))
    if cfg.wh:
        out.append("--basic-reach=half")
    return out


def cfg_job(witch, name, spec, cfg, vset):
    return Job(witch, name, cfg.tag(), vset, cfg_args(witch, spec, cfg), spec=spec)


def gen_samples(score, n=20, seed=2020):
    """무작위 표본(D16 3.2): 점수 score를 주문 셋(A·R·X)의 축 여섯(피해·넓이)에 흩음. 축 상한 4, 한 주문 합 6, 셋 다 1점 이상. 가능한 배치 전부에서 시드로 균등하게 n개."""
    import itertools
    import random
    vecs = []
    for v in itertools.product(range(5), repeat=6):
        if sum(v) != score or any(v[i] + v[i + 1] > 6 or v[i] + v[i + 1] == 0 for i in (0, 2, 4)):
            continue
        vecs.append(v)
    picks = random.Random(seed + score).sample(vecs, n)
    out = []
    for i, v in enumerate(picks, 1):
        toks = []
        for key, (d, r) in zip("ARX", ((v[0], v[1]), (v[2], v[3]), (v[4], v[5]))):
            toks.append("%s:%s%s" % (key, "d%d" % d if d else "", "r%d" % r if r else ""))
        out.append(("R%dx%02d" % (score, i), "+".join(toks)))
    return out, len(vecs)


def exp_lines(witches):
    """N2-1: 안 3(조합 줄) 흉내 + 거래 감쇠. 설정(--cfg)마다 SY6·SY6b·SY6p·RO6·RNDa·RNDb. 줄 끔 기준(--cfg c:0/0/100:x0)도 같은 실험."""
    jobs = []
    for cfg in (CFGS or [Cfg("c", 15, 25, 60)]):
        for w in witches:
            plan = [("SY6", ("S3", "L", "P")), ("RO6", ("S3", "P")), ("SY6p", ("S3",)), ("SY6b", ("S3", "P")), ("RNDa", ("S3", "L", "P")), ("RNDb", ("S3", "L", "P"))]
            if cfg.is_zero():
                plan = [("SY6", ("S3", "L", "P")), ("RO6", ("S3", "P")), ("RNDa", ("S3", "L", "P")), ("RNDb", ("S3", "L", "P"))]
            for name, vs in plan:
                for v in vs:
                    jobs.append(cfg_job(w, name, BUILDS[name], cfg, v))
            if cfg.wh:  # 넓이를 반으로 한 기준의 NB는 slow 칸이 N1에 없다
                for n in ("NB6", "NB6w"):
                    jobs.append(Job(w, n, "whalf", "L", ["--basic-reach=half"]))
    return jobs


def exp_scan(witches):
    """N2-1 훑기: 줄 크기를 여러 개 빠르게 보려고 SY6·RO6·RNDa·RNDb만 stand 3마디 + pilot 승2(slow·SY6p·SY6b 없음). 설정(--cfg)마다."""
    return [cfg_job(w, n, BUILDS[n], cfg, v) for cfg in (CFGS or [Cfg("c", 15, 25, 60)]) for w in witches for n in ("SY6", "RNDa", "RNDb", "RO6") for v in ("S3", "P")]


def exp_scanr(witches):
    """N2 거래 감쇠 훑기: RNDa·RNDb만 새로 돈다(stand 3마디 + pilot 승2). SY6·RO6는 거래가 없어 감쇠와 무관하므로 같은 줄 크기의 다른 감쇠 칸 원시를 복사해 쓴다(copy_sibling_raw)."""
    return [cfg_job(w, n, BUILDS[n], cfg, v) for cfg in (CFGS or [Cfg("c", 15, 25, 10)]) for w in witches for n in ("RNDa", "RNDb") for v in ("S3", "P")]


def copy_sibling_raw(outdir, witches):
    """scanr용: --cfg마다 SY6·RO6의 같은 줄 크기·다른 감쇠 원시를 새 태그 이름으로 복사한다(같은 인수 = 같은 결과). 복사한 수를 돌려준다."""
    import shutil
    n = 0
    for cfg in CFGS:
        for w in witches:
            for b in ("SY6", "RO6"):
                for v in ("S3", "P"):
                    if b == "RO6" and v == "L":
                        continue
                    dst = ROOT / outdir / "raw" / "scanr" / ("%s_%s_%s_%s.json" % (w, b, cfg.tag(), v))
                    if dst.is_file():
                        continue
                    pat = "%s_%s_%s-s%d-%d-b*-x%d%s%s_%s.json" % (w, b, cfg.val, cfg.sb, cfg.sr, cfg.sx, "-rt" if cfg.rate else "", "-wh" if cfg.wh else "", v)
                    hits = sorted(glob.glob(str(ROOT / outdir / "raw" / "*" / pat)))
                    if hits:
                        dst.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(hits[0], dst)
                        n += 1
    return n


def hold1_args(witch):
    """D16 2.1절 안 1 흉내: 울타리는 사실상 못 죽이고(피해 = 보행자 체력의 5%) 오래 묶고(150틱), 기본기는 제어된 적에게 3배(vs_cc 20000). 쿨·바닥은 접촉 값."""
    ring = SK + witch + "_ring"
    a = [x for x in contact_args(witch) if not x.startswith("--ring-dmg-x-walker")] + ["--ring-dmg-x-walker=0.05"]
    key = {"frost": "freeze_ticks=150", "ember": "stagger_ticks=150", "arc": "stun_ticks=120"}[witch]
    a.append("--set=spells/%s/base/%s" % (ring, key))
    for sp in ("frost", "ember", "arc"):
        for st in ("frozen", "stunned", "staggered"):
            a.append("--set=spells/%s%s/vs_cc/%s=20000" % (SK, sp, st))
    return a


def exp_hold1(witches):
    """N2-6: 안 1(울타리는 죽이지 않고 묶음, 기본기가 마무리) 흉내. SY6·RO6·RNDa·RNDb(거래 감쇠 없음)를 stand 3마디 + pilot 승2 + slow 3마디로. 태그 c-a1."""
    return [Job(w, n, "c-a1", v, hold1_args(w), spec=BUILDS[n]) for w in witches for n in ("SY6", "RO6", "RNDa", "RNDb") for v in ("S3", "P", "L")]


def exp_rnd20(witches):
    """N2-2/3: 무작위 표본 20(--score 6|8, 시드 고정)을 설정(--cfg)마다 stand 3마디 + pilot 승2로(시간: slow는 뺌, L-10은 손으로 고른 둘로만)."""
    samples, _ = gen_samples(SCORE)
    vsets = ("S3",) if SCORE == 12 else ("S3", "P")   # 점수 12(N2-9)는 stand만
    return [cfg_job(w, n, s, cfg, v) for cfg in (CFGS or [Cfg("c", 15, 25, 60)]) for w in witches for n, s in samples for v in vsets]


def exp_pts8(witches):
    """N2-3: 점수 8의 SY8(A:d4+R:r4)·NB8(A:d4r4, 한 주문 합 8 > 상한 6이라 게임에서는 못 만드는 하나만 쌓기 = 하나만에게 후한 쪽)·RO8(R:d4r4, 같은 사정)."""
    jobs = []
    for cfg in (CFGS or [Cfg("c", 15, 25, 60)]):
        for w in witches:
            for n, vs in (("SY8", ("S3", "L", "P")), ("RO8", ("S3", "P")), ("NB8", ("S3", "L", "P"))):
                if n == "NB8":   # NB는 줄·접촉 값과 무관: 넓이 설정만 다르다
                    jobs.append(Job(w, n, "whalf" if cfg.wh else "base", vs[0], ["--basic-reach=half"] if cfg.wh else [], spec=BUILDS[n]))
                    for v in vs[1:]:
                        jobs.append(Job(w, n, "whalf" if cfg.wh else "base", v, ["--basic-reach=half"] if cfg.wh else [], spec=BUILDS[n]))
                else:
                    for v in vs:
                        jobs.append(cfg_job(w, n, BUILDS[n], cfg, v))
    return jobs


def exp_cards7l(witches):
    """N2-4: 카드 수 같게(주문을 여는 카드도 한 장으로 셈). RND7a·RND7b를 설정마다. SY6·RO6(원형 열기 1 + 6점 = 7장)는 lines 실험, NB7은 N1 cards7 원시를 쓴다."""
    return [cfg_job(w, n, BUILDS[n], cfg, v) for cfg in (CFGS or [Cfg("c", 15, 25, 60)]) for w in witches for n in ("RND7a", "RND7b") for v in ("S3", "L", "P")]


EXPERIMENTS = {"base": exp_base, "grid": exp_grid, "gridl": exp_gridl, "hold": exp_hold, "i0": exp_i0, "width": exp_width, "mix": exp_mix, "cut": exp_cut, "cards7": exp_cards7, "i0d": exp_i0d, "ilk": exp_ilk, "evo": exp_evo, "bud": exp_bud, "slowx": exp_slowx,
               "lines": exp_lines, "scan": exp_scan, "scanr": exp_scanr, "hold1": exp_hold1, "rnd20": exp_rnd20, "pts8": exp_pts8, "cards7l": exp_cards7l}


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


N2_EXPS = ["lines", "scan", "scanr", "hold1", "rnd20", "pts8", "cards7l"]


def table_exp(store, exp, witches):
    if exp in N2_EXPS:
        return table_lines(store, witches)
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


# ----------------------------------------------------------------------------- N2 판정: D16 3.3절 통과선 L-1~L-14
# 모든 칸은 봇 실측의 시드 평균. 같은 줄의 비 = (시너지 칸 평균) / (상대 칸 평균). * = 시드 흩어짐 >30%(판정 불가). o 통과 / x 미달 / . 판정 줄 아님(참고).

KINDS = {  # 점수 묶음 -> (시너지, 하나만 목록, 원형만, 무작위 목록(손으로 고른 것))
    6: ("SY6", ["NB6", "NB6w"], "RO6", ["RNDa", "RNDb"]),
    7: ("SY6", ["NB7"], "RO6", ["RND7a", "RND7b"]),   # 카드 7장: NB7은 N1 cards7 원시(태그 cards7), SY6·RO6는 원형 열기 1 + 6점
    8: ("SY8", ["NB8"], "RO8", []),
    12: ("SY6", ["NB6", "NB6w"], "RO6", []),   # N2-9 기연의 크기 대리: 시너지는 +0점(6점), 무작위 표본은 +6점(12점)
}
SAMPLES = {6: "R6x", 8: "R8x", 12: "R12x"}
B3 = ["seung2", "jeon_a", "trial"]


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    i = q * (len(xs) - 1)
    lo = int(math.floor(i))
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


def pick_tag(store, w, build, tags, beat, var):
    for t in tags:
        if (w, build, t, beat, var) in store.g:
            return t
    return tags[0]


def nb_cell(store, w, names, nbtags, beat, var, f, lower):
    cand = []
    for n in names:
        for t in nbtags:
            k = (w, n, t, beat, var)
            if k in store.g:
                cand.append((store.m(k, f), store.unstable(k, f)))
                break
    cand = [c for c in cand if c[0] == c[0]]
    if not cand:
        return float("nan"), False
    return (min if lower else max)(cand, key=lambda c: c[0])


def rnd_cells(store, w, rnd, tag, beat, var, f):
    """무작위 목록(이름, 태그)의 칸 평균들."""
    xs = []
    for n in rnd:
        k = (w, n, tag, beat, var)
        if k in store.g:
            x = store.m(k, f)
            if x == x:
                xs.append(x)
    return xs


def fmt(r, un, ok, judged):
    if r != r:
        return "%-9s" % "-"
    return "%-9s" % (("%.2f" % r) + ("*" if un else "") + (("o" if ok(r) else "x") if judged and not un else ""))


def lines_block(store, w, tag, kind, rnd_names, rnd_label, zero_tag):
    sy, nbs, ro, _ = KINDS[kind]
    nbtags = ["whalf"] if tag.endswith("-wh") else ["base"]
    if kind == 7:
        nbtags = ["cards7"]
    P, CH, TK = "power_hp_s", contact_hits, "taken_30s_pct"
    rows = []

    def key(b, var, beat, t=None):
        return (w, b, t or tag, beat, var)

    def r_nb(f, var, beat, lower):
        s = store.m(key(sy, var, beat), f)
        nbv, nun = nb_cell(store, w, nbs, nbtags, beat, var, f, lower)
        return ratio(s, nbv), store.unstable(key(sy, var, beat), f) or nun

    def r_ro(f, var, beat):
        k2 = key(ro, var, beat)
        return ratio(store.m(key(sy, var, beat), f), store.m(k2, f)), store.unstable(key(sy, var, beat), f) or store.unstable(k2, f)

    def r_rnd(f, var, beat, q=0.5, inv=False):
        xs = rnd_cells(store, w, rnd_names, tag, beat, var, f)
        if not xs:
            return float("nan"), False
        m = pct(xs, q)
        s = store.m(key(sy, var, beat), f)
        return (ratio(m, s) if inv else ratio(s, m)), store.unstable(key(sy, var, beat), f)

    def r_off(b, beat):
        t0 = pick_tag(store, w, b, [zero_tag, "base"], beat, "stand")
        k0 = (w, b, t0, beat, "stand")
        return ratio(store.m(key(b, "stand", beat), P), store.m(k0, P)), store.unstable(key(b, "stand", beat), P) or store.unstable(k0, P)

    def r_p6(f, var, beat):
        k2 = key("SY6p", var, beat)
        return ratio(store.m(key(sy, var, beat), f), store.m(k2, f)), store.unstable(key(sy, var, beat), f) or store.unstable(k2, f)

    J = lambda *bs: set(bs)
    spec = [  # id, 설명, 계산, 판정 마디, 조건, 통과선 글
        ("L-1", "SY/NB 밀착P(stand)", lambda b: r_nb(P, "stand", b, False), J("jeon_a", "trial"), lambda r: r >= 1.6, ">=1.6(1.6~2.0)"),
        ("L-2", "SY/NB 열린P(pilot)", lambda b: r_nb(P, "pilot", b, False), J("seung2"), lambda r: r >= 0.7, ">=0.7"),
        ("L-3", "SY/NB 접촉 맞은횟수", lambda b: r_nb(CH, "stand", b, True), J(*B3), lambda r: r <= 0.3, "<=0.3"),
        ("L-4", "SY/NB slow 받은피해", lambda b: r_nb(TK, "slow", b, True), J(*B3), lambda r: r <= 0.6, "<=0.6"),
        ("L-5", "SY/RO 밀착P(stand)", lambda b: r_ro(P, "stand", b), J("jeon_a", "trial"), lambda r: r >= 1.3, ">=1.3"),
        ("L-6", "SY/RO 열린P(pilot)", lambda b: r_ro(P, "pilot", b), J("seung2"), lambda r: r >= 1.5, ">=1.5"),
        ("L-8", "SY/무작위중앙 밀착P", lambda b: r_rnd(P, "stand", b), J("jeon_a", "trial"), (lambda r, _b=[0]: True), ">=1.6(전A)/1.5(버티기)"),
        ("L-9", "SY/무작위중앙 열린P", lambda b: r_rnd(P, "pilot", b), J("seung2"), lambda r: r >= 1.5, ">=1.5"),
        ("L-10", "SY/무작위중앙 slow 받은피해", lambda b: r_rnd(TK, "slow", b), J("jeon_a", "trial"), lambda r: r <= 0.8, "<=0.8"),
        ("L-11", "무작위p90/SY 밀착P", lambda b: r_rnd(P, "stand", b, 0.9, True), J("jeon_a"), lambda r: r <= 0.85, "<=0.85"),
        ("L-12", "SY 줄켬/줄끔 밀착P", lambda b: r_off(sy, b), J("jeon_a", "trial"), lambda r: 1.25 <= r <= 1.67, "1.25~1.67"),
        ("L-13", "RO 줄켬/줄끔 밀착P", lambda b: r_off(ro, b), J("jeon_a", "trial"), lambda r: r <= 1.10, "<=1.10"),
        ("L-14a", "SY/SY6p 밀착P", lambda b: r_p6(P, "stand", b), J("jeon_a", "trial"), lambda r: r > 1.0, ">1"),
        ("L-14b", "SY/SY6p 접촉 맞은횟수", lambda b: r_p6(CH, "stand", b), J("jeon_a", "trial"), lambda r: r < 1.0, "<1"),
    ]
    out = ["-- %s %s (태그 %s; 무작위 = %s %d개) | %s" % (w, "점수" + str(kind), tag, rnd_label, len(rnd_names), "  ".join("%-9s" % BN[b] for b in B3))]
    verdict = {}
    for lid, label, fn, judged, ok, line in spec:
        if kind == 8 and lid in ("L-14a", "L-14b"):
            continue
        cells = []
        for b in B3:
            if lid in ("L-2", "L-6", "L-9") and b != "seung2":
                cells.append("%-9s" % "n/a")
                continue
            if lid == "L-11" and b == "seung2":
                pass
            try:
                r, un = fn(b)
            except KeyError:
                r, un = float("nan"), False
            if lid == "L-8":
                okf = (lambda r, bb=b: r >= (1.6 if bb == "jeon_a" else 1.5))
            else:
                okf = ok
            cells.append(fmt(r, un, okf, b in judged))
            if b in judged and r == r and not un:
                verdict.setdefault(lid, []).append(okf(r))
            elif b in judged:
                verdict.setdefault(lid, []).append(None)
        out.append("%-7s %-30s %-24s | %s" % (lid, label, line, "  ".join(cells)))
    ps = [lid for lid, v in verdict.items() if v and all(x is True for x in v)]
    fl = [lid for lid, v in verdict.items() if any(x is False for x in v)]
    un = [lid for lid, v in verdict.items() if any(x is None for x in v) and not any(x is False for x in v)]
    out.append("   통과: %s | 미달: %s | 판정 못 함(*·칸 없음): %s" % (" ".join(ps) or "-", " ".join(fl) or "-", " ".join(un) or "-"))
    # 기록줄: 울타리 처치 몫 R-2, 원거리 처치 중 기본기 몫 R-1
    rec = []
    for b in B3:
        k = key(sy, "stand", b)
        rk = store.m(k, lambda c: c.get("ranged_kills_basic", 0) / max(1, c.get("ranged_kills_basic", 0) + c.get("ranged_kills_ring", 0) + c.get("ranged_kills_other", 0)) * 100.0)
        rec.append("%s: 울타리 처치 %.0f%% / 원거리 처치 중 기본기 %.0f%%" % (BN[b], store.m(k, "ring_kill_share_pct"), rk))
    out.append("   기록(R-1·R-2, 판정 아님): " + " | ".join(rec))
    # 가장 센 무작위 표본(표본일 때)
    if rnd_label == "표본" and rnd_names:
        top = []
        for n in rnd_names:
            xs = [store.m(key(n, "stand", b), P) for b in ("jeon_a", "trial")]
            sy_x = [store.m(key(sy, "stand", b), P) for b in ("jeon_a", "trial")]
            if all(x == x for x in xs + sy_x):
                top.append((sum(x / s for x, s in zip(xs, sy_x)) / 2, n))
        top.sort(reverse=True)
        specs = {}
        for n in rnd_names:
            for c in store.g.get(key(n, "stand", "jeon_a"), [])[:1]:
                specs[n] = c.get("spec", "?")
        out.append("   무작위 표본 위 3(전A·버티기 P/SY 평균): " + ", ".join("%s %s %.2f" % (n, specs.get(n, "?"), x) for x, n in top[:3]))
        out.append("   표본 중 SY를 넘은 수(전A/버티기): %s" % " / ".join("%d" % sum(1 for n in rnd_names if store.m(key(n, "stand", b), P) > store.m(key(sy, "stand", b), P)) for b in ("jeon_a", "trial")))
    return out


def table_lines(store, witches):
    out = []
    for w in witches:
        tags = sorted({k[2] for k in store.g if k[0] == w and k[1] in ("SY6", "SY8", "RND7a") and k[2] not in ("base", "whalf", "wnone", "cards7", "evo", "i0off") and k[2][:2] in ("c-", "d-")})
        for tag in tags:
            val = tag[0]
            zero_tag = "%s-s0-0-b100-x0%s" % (val, "-wh" if tag.endswith("-wh") else "")
            out.append("")
            out.append("######## %s  %s" % (w, tag))
            for kind in (6, 7, 8, 12):
                sy = KINDS[kind][0]
                if (w, sy, tag, "jeon_a", "stand") not in store.g:
                    continue
                hand = KINDS[kind][3]
                if hand and any((w, n, tag, "jeon_a", "stand") in store.g for n in hand):
                    out += lines_block(store, w, tag, kind, hand, "손으로 고른", zero_tag)
                if kind in SAMPLES:
                    names = sorted({k[1] for k in store.g if k[0] == w and k[2] == tag and k[1].startswith(SAMPLES[kind])})
                    if names:
                        out += lines_block(store, w, tag, kind, names, "표본", zero_tag)
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
    ap.add_argument("--cfg", default="", help="N2 설정(쉼표로 여러 개): 값묶음:차단->기본기%%/피해->울타리%%/거래피해%%[:x거래줄%%][:wh]. 예 c:15/25/60 (c=접촉 값, d=데이터 값). lines·rnd20·pts8·cards7l 실험에 쓴다")
    ap.add_argument("--score", type=int, default=6, help="rnd20의 표본 점수(6 또는 8)")
    a = ap.parse_args(argv)
    global SCORE
    SCORE = a.score
    CFGS[:] = [Cfg.parse(t) for t in a.cfg.split(",") if t.strip()]
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
        if a.exp == "scanr" and not a.dry:
            print("copied sibling raw:", copy_sibling_raw(a.out, witches))
        run_jobs(jobs_of(a.exp, witches), a.exp, a.out, a.seeds, a.jobs, a.dry, a.force)
        return 0
    exps = list(EXPERIMENTS) if a.cmd == "table-all" else [a.exp]
    for exp in exps:
        store = Store()
        store.load(a.out, exp)
        # 기준(NB 최선)은 base의 원시에서, slow 시드 보강(slowx)은 base와 같은 칸에 합쳐서 가져온다
        extra = {"cut": ["mix"], "ilk": ["grid"], "gridl": ["grid"], "evo": ["cards7"], "bud": ["grid"]}.get(exp, [])
        if exp in N2_EXPS:   # N2 판정은 N2 실험 원시 전부 + N1의 base·width·cards7(하나만 쌓기 기준)을 함께 읽는다
            extra = [e for e in N2_EXPS + ["width", "cards7"]]
        for dep in ["base", "slowx"] + extra:
            if dep != exp:
                store.load(a.out, dep)
        print("\n" + "=" * 100 + "\n" + exp + "\n" + "=" * 100)
        print("\n".join(table_exp(store, exp, witches)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
