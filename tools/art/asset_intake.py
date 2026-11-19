#!/usr/bin/env python3
"""외부 에셋 가져오기 검수기(표준 라이브러리만, Python 3.10).

GLB 머리와 JSON 조각만 읽는다. 스크립트를 실행하거나 파일을 고치지 않는다.
(--init-attribution만 새 ATTRIBUTION.ko.md를 만든다. 이미 있으면 덮어쓰지 않는다.)

  python tools/art/asset_intake.py FILE.glb [--profile enemy] [--budget tools/art/asset_budget.json] [--json]
  python tools/art/asset_intake.py --scan chapter1/art [--json] [--strict]
  python tools/art/asset_intake.py --check-attribution DIR
  python tools/art/asset_intake.py --init-attribution DIR
  python tools/art/asset_intake.py NEW.glb --slot actor.walker.model [--slots chapter1/art/asset_slots.json]
  python tools/art/asset_intake.py --slot 'actor.walker.*' --dir chapter1/art/actors/walker_b/   # 묶음: 자리마다 폴더 안의 같은 이름 파일
  python tools/art/asset_intake.py --slot actor.walker.model                                      # 파일 없이: 지금 자리의 파일이 계약을 채우는가

라이선스를 판단하지 않는다. 기록에 적힌 글자가 있는지, 가리키는 파일이 있는지만 본다.
--slot 대조는 자리표(asset_slots.json)의 계약 칸을 새 파일과 한 줄씩 견준다(계약 / 새 파일 / 판정). 코드가 읽는 값(배율·자세 숫자)과
Godot 임포트 뒤의 이름은 이 도구가 보지 못한다(최종 판정은 chapter1/tests/test_asset_slots.gd).
종료 코드: 0 정상, 1 --strict에서 오류·예산 초과·계약 차이, 2 읽기 실패.
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slot_paths  # noqa: E402

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
    nodes = doc.get("nodes", [])
    joint_names = sorted({nodes[j].get("name", "") for sk in skins for j in sk.get("joints", []) if 0 <= j < len(nodes)} - {""})

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
            "joint_names": joint_names,
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


# ---------------------------------------------------------------- 자리표 계약 대조 (T7-2, 명세 3.6의 1단계)

OK, BAD, NOTE, NA = "일치", "차이", "주의", "확인 못 함"
IMAGE_TEXTURE_KINDS = {"texture", "sprite_sheet", "atlas", "nine_slice", "prop_atlas"}


def _row(item, contract, actual, verdict, note=""):
    return {"item": item, "contract": contract, "actual": actual, "verdict": verdict, "note": note}


def _compact(v) -> str:
    return json.dumps(v, ensure_ascii=False, separators=(",", ":")) if not isinstance(v, str) else v


def png_facts(path: Path) -> dict:
    """PNG 머리(IHDR)와 tRNS 조각만 읽는다. 알파 = 색 형식 4·6 또는 tRNS 조각."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise GlbError("PNG 머리가 아니다")
    w, h = struct.unpack(">II", data[16:24])
    color = data[25]
    alpha = color in (4, 6)
    pos = 8
    while pos + 8 <= len(data) and not alpha:
        n, t = struct.unpack(">I4s", data[pos:pos + 8])
        if t == b"tRNS":
            alpha = True
        if t in (b"IDAT", b"IEND"):
            break
        pos += 12 + n
    return {"size": (w, h), "alpha": alpha}


def svg_facts(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    root = re.search(r"<svg\b[^>]*>", text, re.S)
    head = root.group(0) if root else ""
    box = re.search(r'viewBox\s*=\s*"([^"]+)"', head)
    if box:
        nums = [float(x) for x in re.split(r"[\s,]+", box.group(1).strip()) if x]
        if len(nums) == 4:
            return {"size": (nums[2], nums[3]), "alpha": None}
    wh = [re.search(r'\b%s\s*=\s*"([\d.]+)(?:px)?"' % k, head) for k in ("width", "height")]
    if all(wh):
        return {"size": (float(wh[0].group(1)), float(wh[1].group(1))), "alpha": None}
    return {"size": None, "alpha": None}


def image_facts(path: Path) -> dict:
    ext = path.suffix.lower()
    if ext == ".png":
        return png_facts(path)
    if ext == ".svg":
        return svg_facts(path)
    with path.open("rb") as fh:
        size = _image_size(fh.read(65536))
    return {"size": size, "alpha": False if ext in (".jpg", ".jpeg") else None}


def read_import_params(path: Path) -> dict | None:
    """파일 옆 .import 의 [params] 값(글자). 없으면 None."""
    imp = path.with_name(path.name + ".import")
    if not imp.is_file():
        return None
    out, inside = {}, False
    for line in imp.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("["):
            inside = line == "[params]"
        elif inside and "=" in line:
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip().strip('"').lower()
    return out


def _near(name: str, pool, n: int = 3) -> list[str]:
    return difflib.get_close_matches(name, sorted(pool), n=n, cutoff=0.55)


def _rows_import(contract: dict, path: Path, rows: list) -> None:
    want = contract.get("import")
    if not isinstance(want, dict) or not want:
        return
    have = read_import_params(path)
    if have is None:
        rows.append(_row("import", _compact(want), "(.import 없음)", NA, "임포트 뒤 확인"))
        return
    for k, v in want.items():
        got = have.get(k)
        same = got is not None and got == str(v).lower()
        rows.append(_row("import." + k, _compact(v), got if got is not None else "(칸 없음)", OK if same else BAD))


def _rows_model(slot: dict, path: Path, budget_path: Path, rows: list) -> None:
    info = inspect_glb(path)
    joints = set(info["detail"]["joint_names"])
    clips = {c["name"]: c["seconds"] for c in info["detail"]["clips"]}
    c = slot.get("contract") or {}
    bones = c.get("bones") or {}
    for logical, real in bones.items():
        if real in joints:
            rows.append(_row("bones." + logical, real, "있음", OK))
            continue
        alt = real.replace(".", "_").replace(":", "_")
        if alt in joints:
            rows.append(_row("bones." + logical, real, alt, NOTE, "Godot 임포트가 이름을 바꾼 꼴과 같다 [추정]. 최종 판정은 test_asset_slots.gd"))
            continue
        near = _near(real, joints)
        rows.append(_row("bones." + logical, real, "없음", BAD, "비슷한 이름: " + (", ".join(near) if near else "없음")))
    groups = c.get("bone_groups") or {}
    for gname, members in groups.items():
        if not isinstance(members, list):
            continue
        if gname.endswith("prefixes") or gname.endswith("contains"):
            for m in members:
                n = sum(1 for j in joints if (j.startswith(m) if gname.endswith("prefixes") else m in j))
                rows.append(_row("bone_groups.%s[%s]" % (gname, m), "관절 1개 이상", "%d개" % n, OK if n else BAD))
        else:
            unknown = [m for m in members if m not in bones]
            if unknown:
                rows.append(_row("bone_groups." + gname, _compact(members), "bones에 없는 이름 " + ",".join(unknown), BAD, "계약 칸 안의 불일치(파일 문제가 아니다)"))
    clip_map = c.get("clips") or {}
    for logical, real in clip_map.items():
        if real in clips:
            rows.append(_row("clips." + logical, real, "%.4g초" % clips[real], OK))
        else:
            near = _near(real, clips)
            rows.append(_row("clips." + logical, real, "없음", BAD, "비슷한 이름: " + (", ".join(near) if near else "없음") + " / 파일의 클립: " + (", ".join(sorted(clips)) or "없음")))
    timing = {}
    hz = c.get("tick_hz")
    for k, v in (c.get("timing_ticks") or {}).items():
        if hz:
            timing[k] = v / hz
    timing.update({k: v for k, v in (c.get("timing_s") or {}).items()})
    unmapped = []
    for k, secs in timing.items():
        base = k[:-6] if k.endswith("_cycle") else k
        real = clip_map.get(base)
        if real is None:
            unmapped.append(k)
        elif real in clips:
            rows.append(_row("timing." + k, "클립 %s ≥ %.4g초" % (real, secs), "%.4g초" % clips[real], OK if clips[real] + 1e-3 >= secs else BAD))
    if unmapped:
        rows.append(_row("timing(어느 클립인지 계약에 없음)", ", ".join(unmapped), "대조하지 않음", NA))
    profile = c.get("budget_profile")
    if profile and budget_path.is_file():
        try:
            judged = judge(info["metrics"], load_budget(budget_path), profile)
            over = [r for r in judged if r["status"] == "초과"]
            for r in over:
                rows.append(_row("budget." + r["metric"], "상한 %s" % r["limit"], str(r["value"]), BAD, "프로필 " + profile))
            rows.append(_row("budget(%s)" % profile, "초과 0", "초과 %d" % len(over), OK if not over else BAD))
        except KeyError as e:
            rows.append(_row("budget", profile, str(e), NA))


def _regions(node):
    """곁 JSON 안의 (조각 4칸 [x,y,w,h], 그 조각이 가리키는 texture 글자 또는 None)."""
    if isinstance(node, dict):
        reg = node.get("region")
        if isinstance(reg, list) and len(reg) == 4 and all(isinstance(x, (int, float)) for x in reg):
            yield reg, node.get("texture")
        for v in node.values():
            yield from _regions(v)
    elif isinstance(node, list):
        for v in node:
            yield from _regions(v)


def _meta_names(doc) -> set[str]:
    names = set()

    def go(n):
        if isinstance(n, dict):
            for k, v in n.items():
                names.add(str(k))
                if k in ("id", "name", "state", "direction") and isinstance(v, str):
                    names.add(v)
                go(v)
        elif isinstance(n, list):
            for v in n:
                if isinstance(v, str):
                    names.add(v)
                go(v)
    go(doc)
    return names


def _rows_meta(root: Path, slot: dict, meta: Path | None, size, rows: list) -> None:
    own = slot_paths.repo_path(slot.get("file"))  # 이 자리의 파일을 가리키는 조각은 새 파일의 크기로 잰다
    c = slot.get("contract") or {}
    need_meta = any(k in c for k in ("states", "directions", "pieces_required", "ids_required", "group"))
    if meta is None:
        if slot.get("meta") or need_meta:
            rows.append(_row("meta", slot.get("meta") or "(곁 JSON)", "(곁 JSON 없음)", BAD if need_meta else NA))
        return
    doc, err = slot_paths.read_json(meta)
    if doc is None:
        rows.append(_row("meta", slot.get("meta") or "", err or "읽지 못함", BAD))
        return
    names = _meta_names(doc)
    for key in ("states", "directions", "pieces_required", "ids_required"):
        want = c.get(key)
        if isinstance(want, list):
            miss = [x for x in want if x not in names]
            rows.append(_row("meta." + key, _compact(want), "빠진 것 " + ",".join(miss) if miss else "다 있음", BAD if miss else OK,
                             ("비슷한 이름: " + ", ".join(sorted({n for m in miss for n in _near(m, names, 2)}))) if miss else ""))
    if "group" in c:
        got = doc.get("group") if isinstance(doc, dict) else None
        rows.append(_row("meta.group", c["group"], got if got is not None else "(칸 없음)", OK if got == c["group"] else BAD))
    bad, example, total = 0, "", 0
    for reg, tex in _regions(doc):
        total += 1
        w, h = size if size else (None, None)
        if tex:
            tp = slot_paths.repo_path(tex)
            if tp and tp != own and (root / tp).is_file():
                try:
                    w, h = image_facts(root / tp)["size"] or (None, None)
                except (GlbError, OSError, struct.error):
                    w = h = None
        if w is None:
            continue
        x, y, rw, rh = reg
        if x < 0 or y < 0 or rw < 0 or rh < 0 or x + rw > w or y + rh > h:
            bad += 1
            example = example or "%s 가 %sx%s 밖" % (reg, w, h)
    if total:
        rows.append(_row("meta.region(조각이 그림 안에 드나)", "조각 %d개" % total, "밖으로 나간 것 %d" % bad, BAD if bad else OK, example))


def _rows_font(slot: dict, path: Path, rows: list) -> None:
    c = slot.get("contract") or {}
    if not (c.get("axes") or c.get("features") or c.get("chars")):
        return
    try:
        sys.path.insert(0, str(REPO_ROOT / "tools" / "dev"))
        import check_glyphs  # noqa: E402  (cmap 읽기를 복사하지 않고 불러 쓴다)
        font = check_glyphs.TTFont(str(path), lazy=True)
    except Exception as e:  # fontTools 없음, 글꼴 읽기 실패
        rows.append(_row("font", "axes/features/chars", "읽지 못함: %s" % type(e).__name__, NA))
        return
    if c.get("axes"):
        have = {a.axisTag for a in font["fvar"].axes} if "fvar" in font else set()
        miss = [a for a in c["axes"] if a not in have]
        rows.append(_row("font.axes", _compact(c["axes"]), ",".join(sorted(have)) or "(가변 축 없음)", BAD if miss else OK))
    if c.get("features"):
        tags = set()
        for table in ("GSUB", "GPOS"):
            if table in font and font[table].table.FeatureList:
                tags |= {fr.FeatureTag for fr in font[table].table.FeatureList.FeatureRecord}
        miss = [f for f in c["features"] if f not in tags]
        rows.append(_row("font.features", _compact(c["features"]), "빠진 것 " + ",".join(miss) if miss else "다 있음", BAD if miss else OK))
    if c.get("chars"):
        cmap = font.getBestCmap()
        miss = [ch for ch in c["chars"] if ord(ch) not in cmap]
        rows.append(_row("font.chars", "%d자" % len(c["chars"]), "없는 글자 %d" % len(miss), BAD if miss else OK, "".join(miss[:20])))


def _rows_image(root: Path, slot: dict, path: Path, meta: Path | None, current: Path | None, rows: list) -> None:
    kind = slot.get("kind")
    c = slot.get("contract") or {}
    facts = image_facts(path)
    size = facts["size"]
    if current and current.is_file() and current.suffix.lower() != path.suffix.lower():
        rows.append(_row("형식", current.suffix.lower(), path.suffix.lower(), NOTE, "다른 형식이면 호출부가 확장자를 가정하는지 확인"))
    want = c.get("size")
    if isinstance(want, list) and len(want) == 2:
        rows.append(_row("size", "%sx%s" % tuple(want), "%sx%s" % size if size else "읽지 못함",
                         OK if size and [size[0], size[1]] == [float(want[0]), float(want[1])] else BAD if size else NA))
    elif size and current and current.is_file() and current != path:
        try:
            cur = image_facts(current)["size"]
        except (GlbError, OSError, struct.error):
            cur = None
        if cur and cur != size:
            rows.append(_row("size(계약에 칸 없음, 지금 자리 파일과 비교)", "%sx%s" % cur, "%sx%s" % size, NOTE, "계약에 size를 적으면 판정으로 바뀐다"))
    if c.get("square") is True:
        rows.append(_row("square", "정사각", "%sx%s" % size if size else "읽지 못함", OK if size and size[0] == size[1] else BAD if size else NA))
    if "alpha" in c:
        a = facts["alpha"]
        rows.append(_row("alpha", str(c["alpha"]).lower(), "확인 못 함(형식에 알파 정보 없음)" if a is None else str(a).lower(),
                         NA if a is None else OK if a == bool(c["alpha"]) else BAD))
    crops = c.get("crops")
    if isinstance(crops, dict) and size:
        for name, r in crops.items():
            ok = isinstance(r, list) and len(r) == 4 and r[0] >= 0 and r[1] >= 0 and r[0] + r[2] <= size[0] and r[1] + r[3] <= size[1]
            rows.append(_row("crops." + name, _compact(r), "그림 %sx%s" % size, OK if ok else BAD))
    if kind == "nine_slice" and size:
        m = c.get("margin")
        if isinstance(m, (int, float)):
            rows.append(_row("margin", str(m), "한 변 %s" % min(size), OK if m * 2 <= min(size) else BAD, "여백 두 배가 그림보다 크면 가운데가 없다"))
    _rows_meta(root, slot, meta, size, rows)
    _rows_import(c, path, rows)


def compare_slot(root, slot_id: str, slot: dict, new_file: Path | None = None, meta_file: Path | None = None,
                 budget_path: Path = DEFAULT_BUDGET) -> dict:
    """한 자리의 계약과 새 파일(없으면 지금 자리의 파일)을 견준 표. {"slot","kind","file","rows","skipped"}"""
    root = Path(root)
    kind = slot.get("kind", "?")
    cur_rel = slot_paths.repo_path(slot.get("file"))
    current = (root / cur_rel) if cur_rel else None
    target = Path(new_file) if new_file else current
    out = {"slot": slot_id, "kind": kind, "file": _rel(target) if target else "", "rows": [], "skipped": ""}
    rows = out["rows"]
    if target is None:
        out["skipped"] = "계획 중인 자리(file 칸이 비었다). 대조할 파일이 없다"
        return out
    if not target.is_file():
        rows.append(_row("file", cur_rel or "", "파일 없음", BAD))
        return out
    meta = meta_file
    if meta is None and slot.get("meta"):
        mp = slot_paths.repo_path(slot["meta"])
        meta = (root / mp) if mp else None
        meta = meta if meta and meta.is_file() else None
    try:
        if kind == "model":
            _rows_model(slot, target, budget_path, rows)
        elif kind in IMAGE_TEXTURE_KINDS:
            _rows_image(root, slot, target, meta, current, rows)
        elif kind == "font":
            _rows_font(slot, target, rows)
            _rows_import(slot.get("contract") or {}, target, rows)
        else:
            rows.append(_row("kind", kind, "이 종류는 파일 존재만 본다", NA))
    except (GlbError, json.JSONDecodeError, KeyError, struct.error, OSError, IndexError) as e:
        rows.append(_row("읽기", target.name, "%s: %s" % (type(e).__name__, e), BAD))
    skipped = [k for k in ("scale", "pose") if k in (slot.get("contract") or {})]
    if skipped:
        out["skipped"] = "코드가 읽는 값이라 파일로 대조하지 않은 칸: " + ", ".join(skipped)
    return out


def match_slots(table: dict, pattern: str) -> list[str]:
    if pattern.endswith("*"):
        return sorted(s for s in table if s.startswith(pattern[:-1]))
    return [pattern] if pattern in table else []


def pick_in_dir(slot: dict, folder: Path) -> tuple[Path | None, str]:
    """새 폴더 안에서 이 자리의 파일: 같은 파일 이름 -> 같은 확장자 파일이 하나뿐일 때."""
    rel = slot_paths.repo_path(slot.get("file"))
    if not rel:
        return None, "계획 중인 자리"
    same = folder / Path(rel).name
    if same.is_file():
        return same, ""
    ext = Path(rel).suffix.lower()
    cands = [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ext] if folder.is_dir() else []
    if len(cands) == 1:
        return cands[0], "이름이 달라 확장자로 골랐다"
    return None, ("%s 에 %s 파일이 없다" % (folder, Path(rel).name)) if not cands else "%s 파일이 여럿이라 고를 수 없다: %s" % (ext, ", ".join(p.name for p in cands[:5]))


def count_verdicts(res: dict) -> dict:
    return {v: sum(1 for r in res["rows"] if r["verdict"] == v) for v in (BAD, NOTE, OK, NA)}


def fmt_compare(res: dict) -> str:
    L = ["== 자리 %s (%s) — %s" % (res["slot"], res["kind"], res["file"] or "대조할 파일 없음")]
    if res["skipped"]:
        L.append("  (" + res["skipped"] + ")")
    for r in res["rows"]:
        L.append("  [%s] %s | 계약: %s | 새 파일: %s%s" % (r["verdict"], r["item"], r["contract"], r["actual"], (" | " + r["note"]) if r["note"] else ""))
    n = count_verdicts(res)
    if not res["rows"]:
        return "\n".join(L)
    L.append("  요약:차이 %d, 주의 %d, 일치 %d, 확인 못 함 %d" % (n[BAD], n[NOTE], n[OK], n[NA]))
    return "\n".join(L)


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


def run_slot_mode(a) -> int:
    root = Path(a.root)
    slots_path = Path(a.slots) if a.slots else root / slot_paths.SLOTS_REL
    table, err = slot_paths.load_slots(root, slots_path)
    if not table:
        print("자리표를 읽지 못했다: %s%s" % (slots_path, (" (" + err + ")") if err else " (파일이 없다)"), file=sys.stderr)
        return 2
    ids = match_slots(table, a.slot)
    if not ids:
        print("맞는 자리가 없다: %s (예: %s)" % (a.slot, ", ".join(list(table)[:4])), file=sys.stderr)
        return 2
    if a.files and (len(ids) != 1 or a.dir):
        print("파일을 직접 주려면 --slot 이 자리 하나를 가리켜야 하고 --dir 과 함께 쓸 수 없다", file=sys.stderr)
        return 2
    if len(a.files) > 1:
        print("--slot 은 파일 하나만 받는다", file=sys.stderr)
        return 2
    results = []
    for sid in ids:
        slot = table[sid]
        if a.files:
            new = Path(a.files[0])
            note = ""
        elif a.dir:
            new, note = pick_in_dir(slot, Path(a.dir))
        else:
            new, note = None, ""
        if a.dir and new is None:
            res = {"slot": sid, "kind": slot.get("kind", "?"), "file": "", "rows": [], "skipped": note}
            if note != "계획 중인 자리":
                res["rows"].append(_row("file", slot.get("file") or "", note, BAD))
        else:
            res = compare_slot(root, sid, slot, new, budget_path=Path(a.budget))
            if note:
                res["skipped"] = (res["skipped"] + "; " if res["skipped"] else "") + note
        results.append(res)
    if a.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        for res in results:
            print(fmt_compare(res))
        total = {v: sum(count_verdicts(r)[v] for r in results) for v in (BAD, NOTE, OK, NA)}
        print("전체: 자리 %d개, 차이 %d, 주의 %d, 일치 %d, 확인 못 함 %d" % (len(results), total[BAD], total[NOTE], total[OK], total[NA]))
        print("이 대조가 보지 않는 것: 코드가 읽는 숫자(배율·자세), Godot 임포트 뒤의 이름, 그림의 품질, 라이선스.")
    bad = sum(count_verdicts(r)[BAD] for r in results)
    return 1 if (a.strict and bad) else 0


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
    ap.add_argument("--strict", action="store_true", help="오류나 예산 초과나 계약 차이가 있으면 종료 코드 1")
    ap.add_argument("--slot", metavar="ID", help="자리 id 또는 접두*(예: 'actor.walker.*'). 새 파일(없으면 지금 자리의 파일)을 계약과 대조")
    ap.add_argument("--slots", metavar="PATH", default=None, help="자리표 경로(기본 <root>/chapter1/art/asset_slots.json)")
    ap.add_argument("--root", metavar="DIR", default=str(REPO_ROOT), help="저장소 루트(자체 검사용. 기본은 이 저장소)")
    ap.add_argument("--dir", metavar="DIR", help="--slot 과 함께: 자리마다 이 폴더 안의 같은 이름 파일을 대조(묶음 교체)")
    a = ap.parse_args(argv)

    if not (a.files or a.scan or a.check_attribution or a.init_attribution or a.slot):
        ap.print_help()
        return 2
    code = 0

    if a.slot:
        return run_slot_mode(a)

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
