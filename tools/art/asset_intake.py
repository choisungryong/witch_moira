#!/usr/bin/env python3
"""외부 에셋 가져오기 검수기(표준 라이브러리만, Python 3.10).

GLB 머리와 JSON 조각만 읽는다. 스크립트를 실행하거나 파일을 고치지 않는다.
(--init-attribution만 새 ATTRIBUTION.ko.md를 만든다. 이미 있으면 덮어쓰지 않는다.)

  python tools/art/asset_intake.py FILE.glb [--profile enemy] [--budget tools/art/asset_budget.json] [--json]
  python tools/art/asset_intake.py --scan chapter1/art [--json] [--strict]
  python tools/art/asset_intake.py --check-attribution DIR
  python tools/art/asset_intake.py --init-attribution DIR

라이선스를 판단하지 않는다. 기록에 적힌 글자가 있는지, 가리키는 파일이 있는지만 본다.
종료 코드: 0 정상, 1 --strict에서 오류 또는 예산 초과, 2 읽기 실패.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUDGET = Path(__file__).resolve().with_name("asset_budget.json")
METRIC_LABEL = {
    "triangles": "삼각형",
    "vertices": "정점",
    "materials": "재질 수",
    "bones": "뼈 수(스킨 최대)",
    "texture_max_px": "텍스처 최대 한 변(px)",
    "texture_pixels_total": "텍스처 픽셀 합",
    "file_bytes": "파일 크기(바이트)",
    "clips": "클립 수",
}

# ---------------------------------------------------------------- GLB 읽기


class GlbError(Exception):
    pass


def read_glb(path: Path) -> tuple[dict, bytes]:
    """GLB 컨테이너에서 JSON과 BIN 조각을 읽는다. 그 밖의 것은 건드리지 않는다."""
    data = path.read_bytes()
    if len(data) < 20:
        raise GlbError("파일이 너무 짧다")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise GlbError("glTF 머리가 아니다")
    if version != 2:
        raise GlbError(f"glTF 버전 {version}은 읽지 않는다")
    if length > len(data):
        raise GlbError("머리의 길이가 실제 크기보다 크다(잘린 파일)")
    pos = 12
    doc = None
    binchunk = b""
    while pos + 8 <= min(length, len(data)):
        clen, ctype = struct.unpack_from("<II", data, pos)
        body = data[pos + 8: pos + 8 + clen]
        if len(body) < clen:
            raise GlbError("조각이 잘렸다")
        if ctype == 0x4E4F534A and doc is None:
            doc = json.loads(body.decode("utf-8"))
        elif ctype == 0x004E4942 and not binchunk:
            binchunk = body
        pos += 8 + ((clen + 3) // 4) * 4
    if doc is None:
        raise GlbError("JSON 조각이 없다")
    return doc, binchunk


def _image_size(blob: bytes) -> tuple[int, int] | None:
    if blob[:8] == b"\x89PNG\r\n\x1a\n" and len(blob) >= 24:
        w, h = struct.unpack(">II", blob[16:24])
        return w, h
    if blob[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(blob):
            if blob[i] != 0xFF:
                i += 1
                continue
            marker = blob[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                i += 2
                continue
            seglen = struct.unpack(">H", blob[i + 2: i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", blob[i + 5: i + 9])
                return w, h
            i += 2 + seglen
    return None


def _view_bytes(doc: dict, binchunk: bytes, index: int) -> bytes:
    bv = doc["bufferViews"][index]
    off = bv.get("byteOffset", 0)
    return binchunk[off: off + bv["byteLength"]]


def _accessor_time_max(doc: dict, binchunk: bytes, acc_index: int) -> float | None:
    acc = doc["accessors"][acc_index]
    if acc.get("max"):
        return float(acc["max"][0])
    if acc.get("componentType") != 5126 or acc.get("type") != "SCALAR" or "bufferView" not in acc or not binchunk:
        return None
    bv = doc["bufferViews"][acc["bufferView"]]
    stride = bv.get("byteStride") or 4
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    best = None
    for i in range(acc["count"]):
        o = base + i * stride
        if o + 4 > len(binchunk):
            return None
        v = struct.unpack_from("<f", binchunk, o)[0]
        best = v if best is None or v > best else best
    return best


def inspect_glb(path: Path) -> dict:
    doc, binchunk = read_glb(path)
    accessors = doc.get("accessors", [])
    meshes = doc.get("meshes", [])

    tris = 0
    verts = 0
    surfaces = 0
    non_tri = 0
    used_materials: set[int] = set()
    no_material_prims = 0
    mesh_stats = []
    for mi, mesh in enumerate(meshes):
        mt = mv = 0
        for prim in mesh.get("primitives", []):
            surfaces += 1
            attrs = prim.get("attributes", {})
            pos = attrs.get("POSITION")
            vcount = accessors[pos]["count"] if pos is not None else 0
            n = accessors[prim["indices"]]["count"] if "indices" in prim else vcount
            mode = prim.get("mode", 4)
            if mode == 4:
                t = n // 3
            elif mode in (5, 6):
                t = max(n - 2, 0)
            else:
                t = 0
                non_tri += 1
            mt += t
            mv += vcount
            if "material" in prim:
                used_materials.add(prim["material"])
            else:
                no_material_prims += 1
        tris += mt
        verts += mv
        mesh_stats.append({"name": mesh.get("name", f"mesh{mi}"), "primitives": len(mesh.get("primitives", [])),
                           "triangles": mt, "vertices": mv})

    # 장면에서 메시가 몇 번 쓰이는지(인스턴스). 삼각형 합은 메시 하나씩 센 값이다.
    mesh_nodes = sum(1 for n in doc.get("nodes", []) if "mesh" in n)

    skins = doc.get("skins", [])
    skin_joints = [len(s.get("joints", [])) for s in skins]

    textures = []
    for ii, img in enumerate(doc.get("images", [])):
        info = {"index": ii, "name": img.get("name", ""), "mime": img.get("mimeType", ""), "storage": "", "width": None,
                "height": None, "bytes": None}
        if "bufferView" in img and binchunk:
            blob = _view_bytes(doc, binchunk, img["bufferView"])
            info["storage"] = "내장"
            info["bytes"] = len(blob)
            size = _image_size(blob)
            if size:
                info["width"], info["height"] = size
        elif "uri" in img:
            uri = img["uri"]
            if uri.startswith("data:"):
                info["storage"] = "data URI"
            else:
                info["storage"] = "외부 파일 " + uri
                ext = (path.parent / uri)
                if ext.is_file():
                    info["bytes"] = ext.stat().st_size
                    with ext.open("rb") as fh:
                        size = _image_size(fh.read(65536))
                    if size:
                        info["width"], info["height"] = size
        textures.append(info)

    clips = []
    for ai, anim in enumerate(doc.get("animations", [])):
        dur = 0.0
        for samp in anim.get("samplers", []):
            m = _accessor_time_max(doc, binchunk, samp["input"])
            if m is not None and m > dur:
                dur = m
        clips.append({"name": anim.get("name", f"anim{ai}"), "seconds": round(dur, 4),
                      "channels": len(anim.get("channels", []))})

    ext_used = list(doc.get("extensionsUsed", []))
    ext_req = list(doc.get("extensionsRequired", []))
    ext_uris = [b["uri"] for b in doc.get("buffers", []) if "uri" in b and not b["uri"].startswith("data:")]
    asset = doc.get("asset", {})

    px_total = sum((t["width"] or 0) * (t["height"] or 0) for t in textures)
    px_max = max([max(t["width"] or 0, t["height"] or 0) for t in textures], default=0)

    return {
        "file": str(path),
        "metrics": {
            "triangles": tris,
            "vertices": verts,
            "materials": len(used_materials),
            "bones": max(skin_joints, default=0),
            "texture_max_px": px_max,
            "texture_pixels_total": px_total,
            "file_bytes": path.stat().st_size,
            "clips": len(clips),
        },
        "detail": {
            "surfaces": surfaces,
            "materials_declared": len(doc.get("materials", [])),
            "primitives_without_material": no_material_prims,
            "non_triangle_primitives": non_tri,
            "mesh_nodes": mesh_nodes,
            "meshes": mesh_stats,
            "skins": len(skins),
            "skin_joints": skin_joints,
            "textures": textures,
            "clips": clips,
            "generator": asset.get("generator", ""),
            "extensions_used": ext_used,
            "extensions_required": ext_req,
            "external_buffers": ext_uris,
            "scripts": "GLB에는 실행 코드가 없다. 읽기만 했다",
        },
    }


# ---------------------------------------------------------------- 예산 대조


def load_budget(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def judge(metrics: dict, budget: dict, profile: str) -> list[dict]:
    prof = budget["profiles"].get(profile)
    if prof is None:
        raise KeyError(f"예산표에 프로필 '{profile}'이 없다(있는 것: {', '.join(budget['profiles'])})")
    rows = []
    for key, value in metrics.items():
        entry = prof["metrics"].get(key, {"limit": None, "reference": None, "basis": [], "note": "예산표에 항목 없음"})
        limit, ref = entry.get("limit"), entry.get("reference")
        if limit is None:
            status = "기준 없음"
        else:
            status = "통과" if value <= limit else "초과"
        rows.append({"metric": key, "label": METRIC_LABEL.get(key, key), "value": value, "limit": limit,
                     "reference": ref, "ratio_to_reference": (round(value / ref, 3) if ref else None),
                     "status": status, "basis": entry.get("basis", []), "note": entry.get("note", "")})
    return rows


# ---------------------------------------------------------------- ATTRIBUTION 검사

URL_RE = re.compile(r"https?://[^\s)>\]\"']+")
LICENSE_RE = re.compile(r"CC0|CC[ -]?BY(?:[ -]?SA)?[ -]?\d(?:\.\d)?|OGA-BY|OFL|SIL Open Font|Apache|\bMIT\b|Public Domain",
                        re.I)
AUTHOR_RE = re.compile(r"저작자|원작자|작가|원작\s*[:：,]|원 ?모델\s*[:：,]|Author|제작자|CC0\s+\S+|CC[ -]?BY[^,\n]*[,:]\s*\S+", re.I)
DATE_RE = re.compile(r"\d{4}[-./]\d{1,2}[-./]\d{1,2}|받은 날짜|내려받은 날")
ABS_RE = re.compile(r"(?<![A-Za-z])[A-Za-z]:[/\\][A-Za-z0-9_./\\\-]+")
REL_RE = re.compile(r"(?:\.\./|\./)[\w./\-]+")
FILE_RE = re.compile(r"(?<![\w/.\-{},_])([\w\-]+(?:\.[\w\-]+)*\.(?:json|md|blend|glb|png|zip|fbx))\b")
LOCAL_RE = re.compile(r"_local/[A-Za-z0-9_./\-]*")

TEMPLATE = """# {title}

(이 틀의 빈 칸은 사람이 채운다. 모르는 칸은 지우지 말고 '미확인'이라고 적는다.)

- 원 모델/작품명: 미확인
- 저작자: 미확인
- 출처 주소: 미확인
- 라이선스: 미확인(선택한 라이선스와 원문 주소를 함께 적는다)
- 받은 날짜: 미확인(YYYY-MM-DD)
- 받은 파일과 해시: 미확인(파일 이름, 바이트, SHA-256)
- 원본 보관 위치: 미확인(저장소 안이면 상대 경로, 밖이면 절대 경로와 해시)
- 변경 내용: 없음 / 미확인(변경했다면 무엇을 어떻게 바꿨는지)
- 변경 표시·동일조건 공유 등 라이선스가 요구하는 의무: 미확인
- 게임에서 쓰는 곳: 미확인
"""


def _strip_code(text: str) -> str:
    return text


def find_attribution(start: Path, stop: Path) -> Path | None:
    cur = start if start.is_dir() else start.parent
    stop = stop.resolve()
    cur = cur.resolve()
    while True:
        cand = cur / "ATTRIBUTION.ko.md"
        if cand.is_file():
            return cand
        if cur == stop or cur.parent == cur:
            return None
        cur = cur.parent


def check_attribution(att: Path, external: bool = True) -> list[dict]:
    """기록 한 장의 구멍. severity: 오류 / 경고."""
    raw = att.read_text(encoding="utf-8", errors="replace")
    # '항목: 미확인' 줄은 빈 칸이다. 칸 이름만 있는 줄이 통과로 세어지지 않게 뺀다.
    text = "\n".join(l for l in raw.splitlines() if not re.search(r"[:：]\s*미확인", l))
    d = att.parent
    out: list[dict] = []

    def add(sev: str, code: str, msg: str):
        out.append({"severity": sev, "code": code, "message": msg})

    unfilled = len(re.findall(r"[:：]\s*미확인", raw))
    if "(이 틀의 빈 칸은 사람이 채운다" in raw or unfilled >= 3:
        add("경고", "TEMPLATE_UNFILLED", f"'미확인'이 {unfilled}곳. 틀 그대로이거나 채우지 못한 칸이 많다")
    has_url = bool(URL_RE.search(text))
    abs_paths = list(dict.fromkeys(m.rstrip(".") for m in ABS_RE.findall(text) if not m.startswith("http")))
    sev_ext = "오류" if external else "경고"
    note = "" if external else "(외부 에셋이 아니면 해당 없음)"
    if not has_url:
        add(sev_ext, "NO_SOURCE_URL", "출처 주소(URL)가 없다" + note)
    if not LICENSE_RE.search(text):
        add(sev_ext, "NO_LICENSE", "라이선스 표기가 없다" + note)
    if not AUTHOR_RE.search(text):
        add("경고", "NO_AUTHOR", "저작자를 찾을 수 없다")
    if not DATE_RE.search(text):
        add("경고", "NO_DATE", "받은 날짜가 없다(변경 날짜만 있을 수 있다)")

    # 가리키는 파일이 저장소에 있는가
    refs: list[str] = []
    for m in REL_RE.findall(text):
        refs.append(m.rstrip(".,"))
    for m in FILE_RE.findall(text):
        refs.append(m)
    seen = set()
    for r in refs:
        if r in seen or r.startswith("_"):
            continue
        seen.add(r)
        if (d / r).exists():
            continue
        # 기록이 저장소 밖 폴더를 가리키면 그 폴더 안의 이름도 인정한다(재귀 탐색은 파일 이름만 본다)
        if not r.startswith(".") and any(Path(a).is_dir() and next(Path(a).rglob(r), None) for a in abs_paths):
            continue
        sev_ref = "오류" if external else "경고"
        hint = "" if external else "(원래 파일명이나 줄임 표기일 수 있다)"
        if r.startswith("../") or r.startswith("./"):
            add(sev_ref, "REF_MISSING", f"가리키는 파일이 없다: {r}{hint}")
        else:
            add(sev_ref, "REF_MISSING", f"같은 폴더에 있어야 하는 파일이 없다: {r}{hint}")
    for a in abs_paths:
        p = Path(a)
        if p.exists():
            add("경고", "OUTSIDE_REPO", f"원본이 저장소 밖에 있다(지금은 있음, 다른 PC·저장소만으로는 재현 불가): {a}")
        else:
            add("오류", "OUTSIDE_REPO_MISSING", f"저장소 밖 경로가 실제로 없다: {a}")
    for l in set(LOCAL_RE.findall(text)):
        add("경고", "LOCAL_TEMP", f"git에 올라가지 않는 임시 폴더를 가리킨다: {l.rstrip('.')}")
    if re.search(r"보존|보관", text) and not abs_paths and not REL_RE.search(text):
        add("경고", "PRESERVE_NO_PATH", "원본을 '보존했다'고 하나 위치가 경로로 적혀 있지 않다")
    if re.search(r"SHA|sha256|해시", text, re.I) is None and (abs_paths or "SOURCE.json" in text):
        add("경고", "NO_HASH", "받은 원본의 해시가 기록에 없다")
    return out


def scan(root: Path) -> dict:
    root = root.resolve()
    glbs = sorted(p for p in root.rglob("*.glb") if ".godot" not in p.parts)
    atts = sorted(root.rglob("ATTRIBUTION.ko.md"))
    models = []
    covered: set[Path] = set()
    for g in glbs:
        entry = {"glb": _rel(g), "attribution": None, "stats": None, "error": None, "holes": []}
        try:
            entry["stats"] = inspect_glb(g)["metrics"]
        except (GlbError, json.JSONDecodeError, KeyError, struct.error) as e:
            entry["error"] = f"{type(e).__name__}: {e}"
        att = find_attribution(g.parent, root)
        if att is None:
            entry["holes"].append({"severity": "오류", "code": "NO_ATTRIBUTION", "message": "이 모델을 덮는 ATTRIBUTION.ko.md가 없다"})
        else:
            entry["attribution"] = _rel(att)
            covered.add(att)
            entry["holes"] = check_attribution(att)
        models.append(entry)
    other = []
    for a in atts:
        if a in covered:
            continue
        other.append({"attribution": _rel(a), "holes": check_attribution(a, external=False)})
    no_record = []
    for child in sorted(p for p in root.iterdir() if p.is_dir()):
        if not any(child.rglob("ATTRIBUTION.ko.md")):
            files = [f for f in child.rglob("*") if f.is_file() and f.suffix.lower() not in (".import", ".uid")]
            if files:
                no_record.append({"dir": _rel(child), "files": len(files)})
    return {"root": _rel(root), "models": models, "other_records": other, "dirs_without_record": no_record}


def _rel(p: Path) -> str:
    try:
        return p.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return p.as_posix()


# ---------------------------------------------------------------- 출력


def fmt_inspect(res: dict, rows: list[dict] | None, profile: str | None) -> str:
    m, d = res["metrics"], res["detail"]
    L = [f"파일: {_rel(Path(res['file']))}"]
    L.append(f"삼각형 {m['triangles']:,}, 정점 {m['vertices']:,}, 표면(프리미티브) {d['surfaces']}, 재질 {m['materials']}"
             f"(선언 {d['materials_declared']}), 메시 노드 {d['mesh_nodes']}")
    L.append(f"스킨 {d['skins']}개, 뼈 {d['skin_joints']}, 클립 {m['clips']}, 파일 {m['file_bytes']:,}바이트")
    if d["primitives_without_material"]:
        L.append(f"주의: 재질 없는 프리미티브 {d['primitives_without_material']}개(엔진 기본 재질)")
    if d["non_triangle_primitives"]:
        L.append(f"주의: 삼각형이 아닌 프리미티브 {d['non_triangle_primitives']}개(삼각형 수에 안 센다)")
    for t in d["textures"]:
        size = f"{t['width']}x{t['height']}" if t["width"] else "크기 미상"
        L.append(f"  텍스처 {t['index']}: {size}, {t['mime'] or '형식 미상'}, {t['storage']}, {t['bytes'] if t['bytes'] is not None else '?'}바이트")
    for c in d["clips"]:
        L.append(f"  클립 {c['name']}: {c['seconds']}초, 채널 {c['channels']}")
    if d["external_buffers"]:
        L.append(f"경고: 외부 버퍼 참조 {d['external_buffers']}")
    if d["extensions_required"]:
        L.append(f"필수 확장: {d['extensions_required']}")
    L.append(f"생성 도구: {d['generator'] or '미상'}; {d['scripts']}")
    if rows is not None:
        L.append(f"예산 대조(프로필 {profile}):")
        for r in rows:
            lim = "기준 없음" if r["limit"] is None else f"상한 {r['limit']:,}"
            ref = "" if r["reference"] is None else f", 참고 {r['reference']:,}(x{r['ratio_to_reference']})"
            L.append(f"  {r['label']}: {r['value']:,}  [{r['status']}] {lim}{ref}")
        over = sum(1 for r in rows if r["status"] == "초과")
        none = sum(1 for r in rows if r["status"] == "기준 없음")
        L.append(f"  요약: 초과 {over}, 통과 {sum(1 for r in rows if r['status'] == '통과')}, 기준 없음 {none}")
    return "\n".join(L)


def fmt_holes(holes: list[dict], indent: str = "  ") -> list[str]:
    return [f"{indent}[{h['severity']}] {h['code']}: {h['message']}" for h in holes] or [f"{indent}구멍 없음"]


def fmt_scan(res: dict) -> str:
    L = [f"스캔: {res['root']}"]
    L.append("== 모델(GLB)")
    for m in res["models"]:
        s = m["stats"]
        head = f"- {m['glb']}"
        if s:
            head += (f": 삼각형 {s['triangles']:,}, 정점 {s['vertices']:,}, 재질 {s['materials']}, 뼈 {s['bones']}, "
                     f"클립 {s['clips']}, 텍스처 최대 {s['texture_max_px']}px, {s['file_bytes']:,}B")
        else:
            head += f": 읽기 실패 {m['error']}"
        L.append(head)
        L.append(f"  기록: {m['attribution'] or '없음'}")
        L.extend(fmt_holes(m["holes"]))
    L.append("== 모델과 짝이 아닌 기록 파일")
    for o in res["other_records"]:
        L.append(f"- {o['attribution']}")
        L.extend(fmt_holes(o["holes"]))
    L.append("== ATTRIBUTION이 하나도 없는 최상위 폴더(파일이 있는 것만; 기록이 필요한지는 사람이 판단)")
    for n in res["dirs_without_record"]:
        L.append(f"- {n['dir']} ({n['files']}개 파일)")
    errs = sum(1 for m in res["models"] for h in m["holes"] if h["severity"] == "오류")
    errs += sum(1 for o in res["other_records"] for h in o["holes"] if h["severity"] == "오류")
    warns = sum(1 for m in res["models"] for h in m["holes"] if h["severity"] == "경고")
    warns += sum(1 for o in res["other_records"] for h in o["holes"] if h["severity"] == "경고")
    L.append(f"요약: 오류 {errs}, 경고 {warns}")
    return "\n".join(L)


def count_errors(res: dict) -> int:
    return (sum(1 for m in res["models"] for h in m["holes"] if h["severity"] == "오류")
            + sum(1 for o in res["other_records"] for h in o["holes"] if h["severity"] == "오류"))


# ---------------------------------------------------------------- 진입


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description="외부 에셋 가져오기 검수기")
    ap.add_argument("files", nargs="*", help="검사할 .glb")
    ap.add_argument("--scan", metavar="DIR", help="폴더 아래 모든 GLB와 ATTRIBUTION의 구멍 목록")
    ap.add_argument("--check-attribution", metavar="DIR", help="폴더의 ATTRIBUTION.ko.md 검사")
    ap.add_argument("--init-attribution", metavar="DIR", help="빈 ATTRIBUTION.ko.md 틀을 만든다(있으면 만들지 않는다)")
    ap.add_argument("--budget", default=str(DEFAULT_BUDGET))
    ap.add_argument("--profile", default="enemy")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true", help="오류나 예산 초과가 있으면 종료 코드 1")
    a = ap.parse_args(argv)

    if not (a.files or a.scan or a.check_attribution or a.init_attribution):
        ap.print_help()
        return 2
    code = 0

    if a.init_attribution:
        d = Path(a.init_attribution)
        if not d.is_dir():
            print(f"폴더가 없다: {d}", file=sys.stderr)
            return 2
        target = d / "ATTRIBUTION.ko.md"
        if target.exists():
            print(f"이미 있다. 덮어쓰지 않는다: {target}")
        else:
            target.write_text(TEMPLATE.format(title=d.name), encoding="utf-8", newline="\n")
            print(f"틀을 만들었다: {target}")
        holes = check_attribution(target)
        print("\n".join(fmt_holes(holes)))
        return 0

    if a.check_attribution:
        att = Path(a.check_attribution) / "ATTRIBUTION.ko.md"
        if not att.is_file():
            print(f"기록이 없다: {att}")
            return 1 if a.strict else 0
        holes = check_attribution(att)
        if a.json:
            print(json.dumps(holes, ensure_ascii=False, indent=2))
        else:
            print(att)
            print("\n".join(fmt_holes(holes)))
        if a.strict and any(h["severity"] == "오류" for h in holes):
            code = 1

    if a.scan:
        res = scan(Path(a.scan))
        print(json.dumps(res, ensure_ascii=False, indent=2) if a.json else fmt_scan(res))
        if a.strict and count_errors(res):
            code = 1

    if a.files:
        budget = load_budget(Path(a.budget))
        for f in a.files:
            try:
                res = inspect_glb(Path(f))
            except (GlbError, json.JSONDecodeError, KeyError, struct.error, OSError) as e:
                print(f"읽기 실패 {f}: {type(e).__name__}: {e}", file=sys.stderr)
                return 2
            rows = judge(res["metrics"], budget, a.profile)
            att = find_attribution(Path(f).parent, REPO_ROOT)
            holes = check_attribution(att) if att else [{"severity": "오류", "code": "NO_ATTRIBUTION",
                                                          "message": "이 모델을 덮는 ATTRIBUTION.ko.md가 없다"}]
            if a.json:
                print(json.dumps({**res, "budget": rows, "attribution": _rel(att) if att else None, "holes": holes},
                                 ensure_ascii=False, indent=2))
            else:
                print(fmt_inspect(res, rows, a.profile))
                print(f"기록: {_rel(att) if att else '없음'}")
                print("\n".join(fmt_holes(holes)))
            if a.strict and (any(r["status"] == "초과" for r in rows) or any(h["severity"] == "오류" for h in holes)):
                code = 1
    return code


if __name__ == "__main__":
    sys.exit(main())
