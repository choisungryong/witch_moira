#!/usr/bin/env python3
"""sim_economy.py 자체 검사(모델의 불변식과 대조). 실행: python tools/dev/test_sim_economy.py
표준 라이브러리만. 게임 코어(Godot)를 돌리지 않는다. 모델의 답이며 게임의 답이 아니다."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sim_economy as e  # noqa: E402

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


def group(cfg, t="average", plan=("frost",), runs=30, players=12, seed=11):
    return e.simulate_group(cfg, t, list(plan), runs, players, seed)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:  # noqa: BLE001
        pass
    e.JOBS = 1
    spec = e.Cfg("spec")

    # 1 결정론: 같은 인수 같은 결과, 병렬이어도 같다
    a = e.run_flow(spec, ["average"], {"x": ["frost"]}, 20, 8, 11)
    b = e.run_flow(spec, ["average"], {"x": ["frost"]}, 20, 8, 11)
    check("결정론: 같은 인수 같은 결과", json.dumps(a, sort_keys=True, default=str) == json.dumps(b, sort_keys=True, default=str))
    c = e.run_flow(spec, ["average"], {"x": ["frost"]}, 20, 8, 12)
    check("시드가 다르면 결과가 다르다", json.dumps(a, sort_keys=True, default=str) != json.dumps(c, sort_keys=True, default=str))
    e.JOBS = 2
    p = e.run_flow(spec, ["average", "poor"], {"x": ["frost"]}, 20, 8, 11)
    e.JOBS = 1
    s = e.run_flow(spec, ["average", "poor"], {"x": ["frost"]}, 20, 8, 11)
    check("병렬(2)과 직렬의 결과가 같다", json.dumps(p, sort_keys=True, default=str) == json.dumps(s, sort_keys=True, default=str))

    # 2 영구 경험치: sim_progression.gd의 승리 25판(lance)과 같은 레벨 열
    check("경험치 곡선: 승리 25판의 레벨 열이 sim_progression 실측과 같다", e.xp_all_wins(spec, 25) == e.PROG_LANCE_LEVELS, e.xp_all_wins(spec, 25))
    check("승리 한 판의 경험치 합 1000(G1 2.1)", abs(e.run_xp(Cfg_no_bonus(), 1.0, True, 1) - 1000) < 1e-6)
    check("패배 판의 경험치는 승리보다 적다", e.run_xp(Cfg_no_bonus(), 0.5, False, 1) < 1000)

    # 3 드랍: sim_loot 가정 그대로일 때 D6 0절의 값과 8% 안
    m = e.loot_expect(spec, 6000, mode="sim_loot")
    for k in ("items", "rare", "legendary"):
        check("드랍 대조 %s ±8%%" % k, abs(m[k] - e.LOOT_D6[k]) / e.LOOT_D6[k] < 0.08, (m[k], e.LOOT_D6[k]))
    sp = e.Cfg("spec", extra={"players.skilled.p_ritual": 0.0, "players.skilled.p_carrier": 0.0, "players.skilled.p_greed": 0.0})
    loot = e.Loot(sp)
    import random
    rng = random.Random(3)
    n = 0
    for _ in range(1500):
        out, _s = e.run_events(sp, loot, rng, "skilled", "frost", 1, 1.0, True, False)
        n += len(out)
    check("spec 단계 Ⅰ 한 판의 장비 수가 D11 D2의 28~34 안", 28 <= n / 1500.0 <= 34, n / 1500.0)

    # 4 장비 묶음이 P10 예산 안
    for nm, (pr, sr) in e.P10_BUDGET.items():
        pp, ss = e.kit_values(spec, nm)
        check("장비 묶음 %s 힘·버팀이 P10 예산 안" % nm, pr[0] <= pp <= pr[1] and sr[0] <= ss <= sr[1], (pp, ss))

    # 5 승률 곡선: 힘이 늘면 오르고 깊이가 깊으면 내린다
    P = e.Player(spec, e.Loot(spec), e.Gear(spec), e.Tree(spec), "average", ["frost"], 1)
    ws = P.w["frost"]
    check("힘이 늘면 승률이 오른다", P.win_prob(ws, 2.0, 1) > P.win_prob(ws, 1.0, 1))
    check("깊이가 깊으면 같은 힘에서 승률이 내린다", P.win_prob(ws, 2.0, 2) < P.win_prob(ws, 2.0, 1))
    for t in e.TYPES:
        f = e.win_fit(spec, t)
        check("승률 곡선 맞춤 오차 %s < 0.05" % t, f["rmse"] < 0.05, f["rmse"])

    # 6 한 판 시뮬레이션의 불변식
    ok_lv = ok_pts = ok_ledger = ok_rank = True
    for t in e.TYPES:
        for P, tr in group(spec, t, ("ember", "frost", "arc"), 40, 6):
            prev = {w: 1 for w in e.WITCHES}
            for x in tr:
                for w in e.WITCHES:
                    if x["lv_all"][w] < prev[w]:
                        ok_lv = False
                    prev[w] = x["lv_all"][w]
                    if x["spentpts"][w] > x["pts_all"][w]:
                        ok_pts = False
            if P.essence != sum(P.income.values()) - sum(P.spent.values()):
                ok_ledger = False
            for w in e.WITCHES:
                for node, rk in P.w[w].ranks.items():
                    if rk > P.tree.nodes[node]["max"]:
                        ok_rank = False
    check("레벨은 내려가지 않는다", ok_lv)
    check("쓴 포인트가 번 포인트를 넘지 않는다", ok_pts)
    check("재 장부: 재고 = 수입 - 지출", ok_ledger)
    check("트리 랭크가 최대 랭크를 넘지 않는다", ok_rank)

    # 7 트리 투자는 데이터의 규칙(요구 노드, 단 레벨, 최소 투자)을 지킨다
    tree = e.Tree(spec)
    ranks = {}
    tree.invest(ranks, 1, 20, tree.plan("focus", 0))
    check("Lv 1에서는 1단만 산다", all(tree.nodes[i]["tier"] == 1 for i in ranks), ranks)
    ranks = {}
    tree.invest(ranks, 20, 22, tree.plan("recommended", 0))
    check("Lv 20 포인트 22면 키스톤(최소 투자 15)을 살 수 있다", ranks.get(tree.keystone(), 0) == 1, ranks)
    check("포인트 22로는 트리 전부(42랭크)를 못 채운다 — 선택에 포기가 있다", sum(ranks.values()) == 22 and tree.total_ranks > 22, tree.total_ranks)

    # 8 프리셋: now에는 트리가 없는 마녀가 있고 퀘스트·상점이 없다
    now = e.Cfg("now")
    ems = [P for P, tr in group(now, "skilled", ("ember",), 20, 6)]
    check("now: 화염은 포인트를 쓰지 못한다(트리 없음)", all(sum(P.w["ember"].ranks.values()) == 0 for P in ems))
    check("now: 상점·퀘스트가 없어 재 지출 0", all(sum(P.spent.values()) == 0 for P in ems))
    check("now: 서리는 투자한다", any(sum(P.w["frost"].ranks.values()) > 0 for P, tr in group(now, "skilled", ("frost",), 20, 6)))

    # 9 강화는 기본 꺼짐(보류), 켜면 재를 쓴다
    off = group(spec, "skilled", ("frost",), 40, 10)
    check("강화 기본 꺼짐: 강화 지출 0", all(P.spent["forge"] == 0 for P, tr in off))
    on = group(e.Cfg("spec", ["forge.enabled=true"]), "skilled", ("frost",), 40, 10)
    check("강화 켬: 재를 쓴다", sum(P.spent["forge"] for P, tr in on) > 0)

    # 10 유형 서열: 잘함 >= 보통 >= 못함 (승 수)
    wins = {}
    for t in e.TYPES:
        wins[t] = sum(sum(1 for x in tr if x["win"]) for P, tr in group(spec, t, ("frost",), 30, 20))
    check("승리 수 서열 잘함 > 보통 > 못함", wins["skilled"] > wins["average"] > wins["poor"], wins)

    # 11 장비가 되먹임된다: 장비를 막으면(칸당 0점) 힘이 오르지 않는다
    zero = e.Cfg("spec", ["gear.p_max=0", "tree.p_full=0", "tree.s_full=0"])
    gr = group(zero, "average", ("frost",), 30, 10)
    check("장비·트리 힘 0이면 힘 M은 1", all(abs(x["M"] - 1.0) < 1e-9 for P, tr in gr for x in tr))

    # 12 장비 공유와 분리는 세 마녀를 번갈아 키울 때 다르다
    sh = group(spec, "average", ("ember", "frost", "arc"), 30, 12)
    sp_ = group(e.Cfg("spec", ["gear.share=split"]), "average", ("ember", "frost", "arc"), 30, 12)
    a1 = e.med([tr[-1]["pg_next"] for P, tr in sh])
    b1 = e.med([tr[-1]["pg_next"] for P, tr in sp_])
    check("장비 공유가 분리보다 장비 힘이 높다(번갈아 키울 때)", a1 > b1, (a1, b1))

    # 13 값 바꾸기: 알 수 없는 키는 거부, --out은 _local 밖이면 거부
    try:
        e.Cfg("spec", ["no.such.key=1"])
        check("알 수 없는 --set 키 거부", False)
    except SystemExit:
        check("알 수 없는 --set 키 거부", True)
    try:
        e.main(["--out", str(Path(e.ROOT) / "tools" / "x.json"), "--list-params"])
        check("--out이 _local 밖이면 거부", False)
    except SystemExit:
        check("--out이 _local 밖이면 거부", True)

    # 14 calib 파일: 모든 값에 출처와 설명이 있다, 알려진 출처 표지만
    doc = json.load(open(e.CALIB_PATH, encoding="utf-8"))
    tags = ("data", "spec", "balance_sim", "fit", "hypo", "guess", "preset", "table", "user", "sensitivity", "balsim")
    bad = [k for k, v in doc["params"].items() if not v.get("source") or not any(v["source"].startswith(t) for t in tags)]
    check("calib: 모든 값에 알려진 출처 표지가 있다", not bad, bad[:5])
    check("calib: 프리셋 키가 모두 실제 값이다", all(k in doc["params"] for pr in doc["presets"].values() for k in pr))
    n_guess = sum(1 for v in doc["params"].values() if v["source"].startswith("guess"))
    check("calib: 가정한 값(guess)이 목록으로 셀 수 있다", n_guess > 0, n_guess)

    # 15 balance_sim의 장비 묶음과 같은 값인지(불러올 수 있을 때만)
    try:
        import balance_sim as bs
        same = all(abs(bs.GEAR_KITS[k][0] - spec["kit." + k.split(".")[1]][0]) < 1e-9 for k in ("kit.d1_start", "kit.d1_end", "kit.d2_mid"))
        check("balance_sim GEAR_KITS와 calib의 장비 묶음이 같다", same)
    except Exception as ex:  # noqa: BLE001
        print("skip balance_sim 대조:", ex)

    print("\n%d개 검사, 실패 %d" % (N_CHECK, len(FAILS)))
    for f in FAILS:
        print(" -", f)
    return 1 if FAILS else 0


def Cfg_no_bonus():
    return e.Cfg("now")


if __name__ == "__main__":
    sys.exit(main())
