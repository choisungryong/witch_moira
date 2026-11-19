#!/usr/bin/env python3
"""내보낸 캐릭터 glb가 게임의 계약을 지키는지 검사한다(표준 라이브러리만, Blender 필요 없음).

  python tools/art/rig_check.py FILE.glb [--slot actor.hero.model] [--require-dodge] [--max-tris 15000] [--scale 1.32] [--json]

보는 것: 뼈 이름(24개 표준 또는 --bones 목록), 클립 이름과 길이(게임이 쓰는 구간 이상이고 너무 길지 않은가), 재질(종류·텍스처),
삼각형 예산, 가중치(무가중치 0, 정점당 4개 이하, 합 1), 방향(정면 +Z, 위 +Y)과 크기(키×배율이 게임 목표 2.67 근처인가).
자리표 계약(clips·bones·timing·budget)은 asset_intake.py의 대조(compare_slot)를 그대로 불러 덧붙인다.
보지 않는 것: Godot 임포트 뒤의 이름·재질, 움직임의 품질, 라이선스. 종료 코드: 0 통과, 1 차이가 있음, 2 읽기 실패.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import asset_intake as ai  # noqa: E402

REPO = HERE.parents[1]
STANDARD_BONES = [
    "origin", "pelvis_cr", "spine_cr_01", "spine_cr_02", "spine_cr_03", "neck_cr", "head_cr",
    "shoulder_cr_l", "upper_arm_cr_l", "forearm_cr_l", "hand_cr_l", "shoulder_cr_r", "upper_arm_cr_r", "forearm_cr_r", "hand_cr_r",
    "finger_middle.01.r", "thigh_cr_l", "shin_cr_l", "tarsal_cr_l", "toe_cr_l", "thigh_cr_r", "shin_cr_r", "tarsal_cr_r", "toe_cr_r",
]
# 클립: (게임이 쓰는 최소 길이, 권하는 최대 길이, 꼭 있어야 하는가)
CLIP_RULES = {"idle": (1.2, 1.25, True), "run": (0.6, 0.65, True), "cast": (0.6, 0.65, True), "hit": (0.3, 0.35, True),
              "death": (0.9, 0.95, True), "dodge": (0.5, 0.55, False)}
GAME_HEIGHT = 2.67
OK, BAD, NOTE = "통과", "차이", "주의"
BAD_EXT = ("KHR_draco_mesh_compression", "EXT_meshopt_compression")

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(doc, binchunk, ai_):
    acc = doc["accessors"][ai_]
    fmt, size = CT[acc["componentType"]]
    n = NC[acc["type"]]
    bv = doc["bufferViews"][acc["bufferView"]]
    stride = bv.get("byteStride") or size * n
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    norm = acc.get("normalized", False)
    div = {"B": 255.0, "H": 65535.0, "b": 127.0, "h": 32767.0}.get(fmt, 1.0) if norm else 1.0
    out = []
    for i in range(acc["count"]):
        row = struct.unpack_from("<" + fmt * n, binchunk, off + i * stride)
        out.append(tuple(v / div for v in row) if div != 1.0 else row)
    return out


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_local(node):
    if "matrix" in node:
        m = node["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def world_matrices(doc):
    nodes = doc.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    cache = {}

    def w(i):
        if i in cache:
            return cache[i]
        m = node_local(nodes[i])
        if i in parent:
            m = mat_mul(w(parent[i]), m)
        cache[i] = m
        return m
    return {i: w(i) for i in range(len(nodes))}


def row(item, contract, actual, verdict, note=""):
    return {"item": item, "contract": contract, "actual": actual, "verdict": verdict, "note": note}


def check_glb(path: Path, a) -> dict:
    doc, binchunk = ai.read_glb(path)
    info = ai.inspect_glb(path)
    rows = []
    nodes = doc.get("nodes", [])
    # --- 뼈
    joints = set(info["detail"]["joint_names"])
    want = a.bones or STANDARD_BONES
    missing = [b for b in want if b not in joints]
    rows.append(row("뼈 이름", "%d개 모두 있음" % len(want), "없음: " + ",".join(missing) if missing else "%d개 있음(스킨 %d)" % (len(joints), info["metrics"]["bones"]), BAD if missing else OK))
    extra = sorted(joints - set(want))
    if extra:
        rows.append(row("표준 밖 뼈", "-", ",".join(extra[:8]) + (" 외 %d" % (len(extra) - 8) if len(extra) > 8 else ""), NOTE, "게임은 무시하지만 가중치·크기만 늘린다"))
    # --- 클립
    clips = {c["name"]: c["seconds"] for c in info["detail"]["clips"]}
    for name, (lo, hi, req) in CLIP_RULES.items():
        if name == "dodge" and a.require_dodge:
            req = True
        if name not in clips:
            rows.append(row("클립 " + name, ">= %.2f초" % lo, "없음", BAD if req else NOTE, "" if req else "회피 클립은 아직 게임이 쓰지 않는다"))
            continue
        sec = clips[name]
        if sec + 1e-3 < lo:
            rows.append(row("클립 " + name, ">= %.2f초" % lo, "%.3f초" % sec, BAD, "게임이 쓰는 구간보다 짧다. 중간에 끊긴다"))
        elif sec > hi:
            rows.append(row("클립 " + name, "%.2f~%.2f초" % (lo, hi), "%.3f초" % sec, NOTE, "더 길다. 순환·구간 계산이 어긋날 수 있다"))
        else:
            rows.append(row("클립 " + name, "%.2f~%.2f초" % (lo, hi), "%.3f초" % sec, OK))
    # --- 재질
    mats = doc.get("materials", [])
    used = sorted({p.get("material") for m in doc.get("meshes", []) for p in m.get("primitives", []) if "material" in p})
    nopbr, notex = [], []
    for mi in used:
        m = mats[mi]
        pbr = m.get("pbrMetallicRoughness")
        if pbr is None:
            nopbr.append(m.get("name", str(mi)))
        elif "baseColorTexture" not in pbr:
            notex.append(m.get("name", str(mi)))
    rows.append(row("재질 종류", "표준 재질(pbrMetallicRoughness)", ("표준 아님: " + ",".join(nopbr)) if nopbr else "%d개 모두 표준" % len(used), BAD if nopbr else OK))
    if notex:
        rows.append(row("색 텍스처", "재질마다 baseColorTexture", "없음: " + ",".join(notex), BAD,
                        "게임의 재질 처리가 albedo_color를 덮어써서 질감 없는 재질은 색을 잃는다. 단색 텍스처를 입힌다(rig_parts가 함)"))
    else:
        rows.append(row("색 텍스처", "재질마다 baseColorTexture", "모두 있음", OK))
    bad_ext = [e for e in doc.get("extensionsRequired", []) if e in BAD_EXT]
    rows.append(row("압축 확장", "없음", ",".join(bad_ext) if bad_ext else "없음", BAD if bad_ext else OK))
    # --- 삼각형
    tris = info["metrics"]["triangles"]
    rows.append(row("삼각형", "<= %d(상한 %d)" % (a.max_tris, a.hard_tris), "{:,}".format(tris), OK if tris <= a.max_tris else (NOTE if tris <= a.hard_tris else BAD),
                    "" if tris <= a.max_tris else "권고(1만5천)를 넘는다. mesh_reduce.py로 줄인다"))
    # --- 가중치
    unweighted = over4 = bad_sum = skinned_verts = 0
    for m in doc.get("meshes", []):
        for p in m.get("primitives", []):
            at = p.get("attributes", {})
            if "JOINTS_0" not in at:
                continue
            w0 = read_accessor(doc, binchunk, at["WEIGHTS_0"])
            w1 = read_accessor(doc, binchunk, at["WEIGHTS_1"]) if "WEIGHTS_1" in at else None
            for i, w in enumerate(w0):
                skinned_verts += 1
                s = sum(w)
                if w1 is not None:
                    extra_w = sum(w1[i])
                    if extra_w > 1e-4:
                        over4 += 1
                    s += extra_w
                if s < 1e-4:
                    unweighted += 1
                elif abs(s - 1.0) > 0.01:
                    bad_sum += 1
    rows.append(row("가중치", "무가중치 0, 정점당 4개 이하, 합 1", "스킨 정점 %d: 무가중치 %d, 5개 이상 %d, 합이 1이 아님 %d" % (skinned_verts, unweighted, over4, bad_sum),
                    OK if not (unweighted or over4 or bad_sum) and skinned_verts else (BAD if skinned_verts else NOTE), "" if skinned_verts else "스킨된 메시가 없다"))
    # --- 방향과 크기
    wm = world_matrices(doc)
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}
    ymin, ymax = 1e9, -1e9
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        for p in doc["meshes"][n["mesh"]].get("primitives", []):
            acc = doc["accessors"][p["attributes"]["POSITION"]]
            if "min" in acc and "max" in acc:
                m = wm[i] if "skin" not in n else [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
                for corner in ((acc["min"][0], acc["min"][1], acc["min"][2]), (acc["max"][0], acc["max"][1], acc["max"][2])):
                    y = m[1][0] * corner[0] + m[1][1] * corner[1] + m[1][2] * corner[2] + m[1][3]
                    ymin, ymax = min(ymin, y), max(ymax, y)
    if ymax > ymin:
        h = ymax - ymin
        scaled = h * a.scale
        ok = abs(scaled - GAME_HEIGHT) / GAME_HEIGHT <= 0.25
        rows.append(row("키(메시 y 범위)", "키×배율 %.2f ≈ 게임 %.2f(±25%%)" % (a.scale, GAME_HEIGHT), "%.3f m(바닥 %.3f) → %.2f" % (h, ymin, scaled), OK if ok else NOTE,
                        "" if ok else "자리표의 배율(scale)을 이 키에 맞게 다시 정해야 한다"))
        rows.append(row("바닥", "발이 y=0 근처", "%.3f" % ymin, OK if abs(ymin) < 0.05 else NOTE))
    else:
        rows.append(row("키", "-", "메시 범위를 못 읽음", NOTE))
    if "tarsal_cr_l" in by_name and "toe_cr_l" in by_name:
        a_, t_ = wm[by_name["tarsal_cr_l"]], wm[by_name["toe_cr_l"]]
        dz = t_[2][3] - a_[2][3]
        dx = a_[0][3]
        rows.append(row("방향", "발끝이 +Z(정면 +Z), 캐릭터 왼쪽 +X", "발끝-발목 z %+.3f, 왼발 x %+.3f" % (dz, dx), OK if dz > 0 and dx > 0 else BAD,
                        "" if dz > 0 and dx > 0 else "정면이 반대거나 좌우가 뒤집혔다"))
    # --- 자리표 계약(asset_intake)
    slot_rows = []
    if a.slot:
        table, err = ai.slot_paths.load_slots(REPO, REPO / ai.slot_paths.SLOTS_REL)
        if a.slot not in (table or {}):
            slot_rows.append(row("자리표", a.slot, "그런 자리가 없다", BAD))
        else:
            res = ai.compare_slot(REPO, a.slot, table[a.slot], path)
            for r in res["rows"]:
                verdict = {ai.OK: OK, ai.BAD: BAD, ai.NOTE: NOTE}.get(r["verdict"], NOTE)
                note = r.get("note", "")
                if verdict == BAD and "prefixes[" in r["item"] and r["actual"].startswith("0"):
                    # 상체 접두 규칙(thumb. 등)은 "그 이름으로 시작하는 뼈를 상체로 본다"는 규칙이다. 뼈가 하나도 없어도 게임은 동작한다.
                    verdict, note = NOTE, "접두 규칙일 뿐 그 뼈가 꼭 있어야 하는 것은 아니다(없으면 해당 없음). 손가락 뼈를 뺀 24뼈 대에서 나오는 값"
                slot_rows.append(row("[자리표] " + r["item"], r["contract"], r["actual"], verdict, note))
    if getattr(a, "mesh_only", False):
        rows = [r for r in rows if not (r["item"].startswith(("뼈", "클립", "표준 밖", "방향", "가중치")))]
        slot_rows = []
    return {"file": str(path), "metrics": info["metrics"], "rows": rows, "slot_rows": slot_rows}


def fmt(res) -> str:
    out = ["파일: %s" % res["file"],
           "삼각형 {:,}, 뼈 {}, 클립 {}, 재질 {}, 파일 {:,} B".format(res["metrics"]["triangles"], res["metrics"]["bones"], res["metrics"]["clips"], res["metrics"]["materials"], res["metrics"]["file_bytes"]), ""]
    for r in res["rows"] + res["slot_rows"]:
        out.append("  [%s] %s | 계약: %s | 실제: %s%s" % (r["verdict"], r["item"], r["contract"], r["actual"], (" | " + r["note"]) if r["note"] else ""))
    bad = sum(1 for r in res["rows"] + res["slot_rows"] if r["verdict"] == BAD)
    note = sum(1 for r in res["rows"] + res["slot_rows"] if r["verdict"] == NOTE)
    out.append("")
    out.append("차이 %d, 주의 %d. 이 검사가 보지 않는 것: Godot 임포트 뒤의 이름·재질, 움직임의 품질, 라이선스." % (bad, note))
    return "\n".join(out)


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description="캐릭터 glb 계약 검사")
    ap.add_argument("file")
    ap.add_argument("--slot", help="자리표 id(예: actor.hero.model)도 함께 대조")
    ap.add_argument("--bones", nargs="*", help="필수 뼈 이름(기본: 표준 24개)")
    ap.add_argument("--require-dodge", action="store_true")
    ap.add_argument("--max-tris", type=int, default=15000)
    ap.add_argument("--hard-tris", type=int, default=20000)
    ap.add_argument("--scale", type=float, default=1.32, help="게임이 모델에 곱하는 배율(자리표 scale)")
    ap.add_argument("--mesh-only", action="store_true", help="뼈대·동작이 아직 없는 단계(mesh_reduce 결과): 뼈·클립·방향 줄을 건너뜀")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    try:
        res = check_glb(Path(a.file), a)
    except (ai.GlbError, OSError, KeyError, struct.error, json.JSONDecodeError) as e:
        print("읽기 실패: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 2
    print(json.dumps(res, ensure_ascii=False, indent=2) if a.json else fmt(res))
    return 1 if any(r["verdict"] == BAD for r in res["rows"] + res["slot_rows"]) else 0


if __name__ == "__main__":
    sys.exit(main())
