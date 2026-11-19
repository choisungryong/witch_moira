#!/usr/bin/env python3
"""에셋 자리표(chapter1/art/asset_slots.json)와 소리 표(chapter1/data/audio_map.json)가 가리키는 파일을 읽는 공용 모듈.

표준 라이브러리만. 파일을 쓰거나 코드를 실행하지 않는다. 자리표의 꼴은 docs/specs/T7-asset-swap-structure-20261120.ko.md 3.3 절이다.
도구 여럿(check_build.py, refactor_map.py, manager/catalog.py, asset_intake.py, asset_ledger.py)이 같은 읽기를 쓰도록 한 곳에 둔다.
이 모듈이 아는 것은 표에 적힌 글자뿐이다. 그 파일이 게임에서 실제로 로드되는지는 말하지 않는다.

경로 규칙: 자리표의 file/meta/extra_files 는 chapter1/art 기준 상대 경로이고, res:// 로 시작하면 그대로(저장소 루트 기준) 쓴다.
이 모듈이 돌려주는 경로는 모두 저장소 루트 기준 슬래시 경로다(예: chapter1/art/actors/hero.png).
"""
import json
from pathlib import Path

SLOTS_REL = "chapter1/art/asset_slots.json"
AUDIO_MAP_REL = "chapter1/data/audio_map.json"
ART_REL = "chapter1/art"
FILE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".glb", ".gltf", ".ttf", ".otf", ".wav", ".ogg", ".mp3", ".json", ".tres", ".tscn"}
AUDIO_EXT = {".wav", ".ogg", ".mp3"}
INHERIT_KEYS = ("kind", "file", "meta", "fallback", "extra_files", "contract")


def repo_path(raw, art_rel=ART_REL):
    """표에 적힌 글자 -> 저장소 루트 기준 경로. 빈 글자는 None."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    s = raw.strip().replace("\\", "/")
    if s.startswith("res://"):
        return s[len("res://"):].lstrip("/")
    return (art_rel.rstrip("/") + "/" + s.lstrip("/")) if art_rel else s


def read_json(path):
    """(내용, 오류 글). 파일이 없으면 (None, None)."""
    p = Path(path)
    if not p.is_file():
        return None, None
    try:
        return json.loads(p.read_text(encoding="utf-8")), None
    except (OSError, ValueError) as e:
        return None, "%s: %s" % (type(e).__name__, e)


def load_slots(root, slots_path=None):
    """(자리 표 dict, 오류 글). 표가 없으면 ({}, None). inherit 를 풀어 slot['resolved'] 에 합친 값을 둔다."""
    path = Path(slots_path) if slots_path else Path(root) / SLOTS_REL
    doc, err = read_json(path)
    if doc is None:
        return {}, err
    slots = doc.get("slots") if isinstance(doc, dict) else None
    if not isinstance(slots, dict):
        return {}, "slots 칸이 없다"
    out = {}
    for sid in slots:
        out[sid] = resolve_slot(slots, sid)
    return out, None


def resolve_slot(slots, sid, _seen=None):
    """inherit 를 따라 합친 자리. 자기 칸이 이긴다(contract 는 최상위 칸 단위로 덮는다). 순환은 끊는다."""
    seen = set(_seen or ())
    raw = slots.get(sid)
    if not isinstance(raw, dict) or sid in seen:
        return {}
    seen.add(sid)
    base = {}
    parent = raw.get("inherit")
    if isinstance(parent, str) and parent in slots:
        base = resolve_slot(slots, parent, seen)
    merged = {k: base[k] for k in INHERIT_KEYS if k in base}
    for k, v in raw.items():
        if k == "contract" and isinstance(v, dict) and isinstance(merged.get("contract"), dict):
            merged["contract"] = {**merged["contract"], **v}
        elif k != "inherit":
            merged[k] = v
    merged["inherit"] = raw.get("inherit")
    return merged


def slot_refs(root, slots_path=None):
    """자리표가 가리키는 파일: [(자리 id, 'file'|'meta'|'extra'|'fallback', 저장소 기준 경로)]. 빈 file(계획 중)은 뺀다.
    inherit 로 물려받은 파일도 그 자리의 것으로 센다(같은 파일을 여러 자리가 가리키면 자리마다 한 줄)."""
    slots, _ = load_slots(root, slots_path)
    out = []
    for sid, s in slots.items():
        own = (s.get("file"), "file"), (s.get("meta"), "meta"), (s.get("fallback"), "fallback")
        for raw, role in own:
            p = repo_path(raw)
            if p:
                out.append((sid, role, p))
        for raw in s.get("extra_files") or []:
            p = repo_path(raw)
            if p:
                out.append((sid, "extra", p))
    return out


def meta_files(root, slots_path=None):
    """자리표가 meta 로 가리키는 곁 JSON(저장소 기준 경로 집합). 원장·기록 JSON 같은 다른 JSON 은 포함하지 않는다."""
    return {p for _, role, p in slot_refs(root, slots_path) if role == "meta"}


def walk_strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from walk_strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk_strings(v)


def looks_like_file(s):
    if not isinstance(s, str) or not s or len(s) > 260 or "\n" in s or " " in s.strip():
        return False
    return Path(s.split("?")[0]).suffix.lower() in FILE_EXT


def sidecar_refs(root, meta_rel):
    """곁 JSON(저장소 기준 경로)에 적힌 파일 경로 문자열 중 실제로 있는 파일. res:// 는 그대로, 그 밖은 art 기준 -> 곁 JSON 폴더 기준 순."""
    root = Path(root)
    doc, _ = read_json(root / meta_rel)
    if doc is None:
        return []
    out = []
    folder = meta_rel.rsplit("/", 1)[0] if "/" in meta_rel else ""
    for s in dict.fromkeys(walk_strings(doc)):
        if not looks_like_file(s):
            continue
        cands = [repo_path(s)]
        if not s.startswith("res://"):
            cands.append((folder + "/" + s.lstrip("/")) if folder else s)
        for c in cands:
            if c and c != meta_rel and (root / c).is_file():
                out.append(c)
                break
    return out


def audio_map_refs(root, audio_map_path=None):
    """소리 표에서 소리 파일 확장자로 끝나는 글자: [(큐 위치, 저장소 기준 경로)]. 표 꼴을 몰라도 읽도록 모든 글자를 훑는다(없으면 [])."""
    path = Path(audio_map_path) if audio_map_path else Path(root) / AUDIO_MAP_REL
    doc, _ = read_json(path)
    out = []

    def go(node, where):
        if isinstance(node, str):
            if Path(node).suffix.lower() in AUDIO_EXT:
                out.append((where or "(root)", repo_path(node)))
        elif isinstance(node, dict):
            for k, v in node.items():
                go(v, (where + "." if where else "") + str(k))
        elif isinstance(node, list):
            for i, v in enumerate(node):
                go(v, "%s[%d]" % (where, i))
    if doc is not None:
        go(doc, "")
    return out


def all_refs(root, slots_path=None, audio_map_path=None):
    """{저장소 기준 경로: [이유 글]}: 자리표(file·meta·extra·fallback), 곁 JSON 안의 경로, 소리 표."""
    refs = {}

    def add(path, why):
        refs.setdefault(path, [])
        if why not in refs[path]:
            refs[path].append(why)
    for sid, role, p in slot_refs(root, slots_path):
        add(p, "자리표 %s (%s)" % (sid, role))
        if role == "meta" and p.endswith(".json"):
            for q in sidecar_refs(root, p):
                add(q, "곁 JSON %s 안의 경로" % p)
    for cue, p in audio_map_refs(root, audio_map_path):
        add(p, "소리 표 %s" % cue)
    return refs
