#!/usr/bin/env python3
"""출처 원장 도구: chapter1/art/ASSET-LEDGER.json 을 만들고 점검한다.

표준 라이브러리만(Python 3.10). 외부 호출·생성·그림 수정을 하지 않는다. 읽기와 원장 쓰기만 한다.

  python tools/art/asset_ledger.py check            # 구멍 목록. 오류가 있으면 종료 코드 1
  python tools/art/asset_ledger.py check --strict   # 구멍(미확인·배포 불가)도 종료 코드 2
                                                    # (자리표 대조의 경고와 "자리 없음" 목록은 종료 코드에 영향이 없다)
  python tools/art/asset_ledger.py add PATH --source-type ai_generated --origin ... --license ... \
        --model ... --prompt-file P.txt --date 2026-11-19 --postprocess ...
  python tools/art/asset_ledger.py migrate          # quality03 옛 기록 + 폴더별 ATTRIBUTION 에서 원장을 만든다

약속
- 값을 모르면 "미확인" 으로 시작하는 글로 적는다(지어내지 않는다). check 가 목록에 올린다.
- 필수 칸이 비어 있으면(칸이 없거나 빈 글) 오류다. "미확인" 은 오류가 아니라 구멍이다.
- 배포 가능 여부는 원장에 적지 않고 check 가 계산한다. 출처·라이선스·날짜·후처리(생성물은 모델·프롬프트·약관 확인)가
  다 있고, 사람이 release_cleared 를 true 로 표시한 것만 "배포 가능"이다.
- 원장 경로는 chapter1/art 기준 상대 경로(슬래시)다.
"""
import argparse
import datetime
import fnmatch
import hashlib
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slot_paths  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
ASSET_EXT = {
    ".png": "image", ".jpg": "image", ".jpeg": "image", ".svg": "image", ".webp": "image",
    ".glb": "model", ".gltf": "model",
    ".ttf": "font", ".otf": "font",
    ".wav": "audio", ".ogg": "audio", ".mp3": "audio",
}
UNKNOWN = "미확인"
SOURCE_TYPES = ("ai_generated", "project_original", "third_party", "third_party_derived", "derived")
REQUIRED = ("path", "sha256", "size", "kind", "source_type", "origin", "license", "date", "postprocess")
REQUIRED_AI = ("model", "prompt")
LEDGER_NAME = "ASSET-LEDGER.json"


# ---------------------------------------------------------------- 공통

def art_dir(root):
    return Path(root) / "chapter1" / "art"


def sha256_of(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def png_size(p):
    try:
        with open(p, "rb") as f:
            head = f.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
            return struct.unpack(">II", head[16:24])
    except OSError:
        pass
    return None


def is_unknown(v):
    return isinstance(v, str) and v.strip().startswith(UNKNOWN)


def is_empty(v):
    return v is None or (isinstance(v, str) and not v.strip())


def load_ledger(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def list_asset_files(root):
    base = art_dir(root)
    out = []
    for p in sorted(base.rglob("*")):
        if p.is_file() and p.suffix.lower() in ASSET_EXT:
            out.append(p.relative_to(base).as_posix())
    return out


def ignored_files(root):
    """원장 대상이 아닌 파일(문서·메타데이터·스크립트·가져오기 파일)의 확장자별 개수."""
    base = art_dir(root)
    cnt = {}
    for p in base.rglob("*"):
        if p.is_file() and p.suffix.lower() not in ASSET_EXT:
            cnt[p.suffix.lower() or "(없음)"] = cnt.get(p.suffix.lower() or "(없음)", 0) + 1
    return cnt


def file_facts(root, rel):
    p = art_dir(root) / rel
    facts = {"sha256": sha256_of(p), "size": p.stat().st_size,
             "kind": ASSET_EXT.get(p.suffix.lower(), "other")}
    wh = png_size(p) if p.suffix.lower() == ".png" else None
    if wh:
        facts["width"], facts["height"] = wh
    return facts


def record_ref(root, rel):
    p = art_dir(root) / rel
    return {"path": rel, "sha256": sha256_of(p)} if p.is_file() else {"path": rel, "sha256": UNKNOWN + ": 파일 없음"}


# ---------------------------------------------------------------- 배포 판정

def provenance_blockers(e):
    """출처 기록이 모자란 이유 목록(없으면 기록은 갖춰진 것)."""
    why = []
    for k in ("source_type", "origin", "license", "date", "postprocess"):
        if is_unknown(e.get(k)):
            why.append("%s 미확인" % k)
    if e.get("source_type") == "ai_generated":
        for k in REQUIRED_AI:
            if is_unknown(e.get(k)):
                why.append("%s 미확인" % k)
        if e.get("terms_checked") is not True:
            why.append("생성 도구 이용 약관 확인 안 됨(terms_checked)")
    if str(e.get("status", "")).startswith("rejected"):
        why.append("채택하지 않은 시도작(status=%s)" % e.get("status"))
    return why


def release_blockers(e):
    why = provenance_blockers(e)
    if e.get("release_cleared") is not True:
        why.append("배포 확인 표시(release_cleared) 없음")
    return why


# ---------------------------------------------------------------- check

def slot_report(root, ledger_paths):
    """자리표·소리 표와 원장의 대조(T7-2). 경고와 목록만 만든다(오류가 아니다: 출처 구멍은 지금 개발을 막지 않는다).
    ledger_paths: 원장 항목의 path(chapter1/art 기준) 모음. 자리표가 없으면 {"present": False}."""
    table, err = slot_paths.load_slots(root)
    audio = slot_paths.audio_map_refs(root)
    if not table and not audio:
        return {"present": False, "error": err}
    prefix = slot_paths.ART_REL + "/"
    base = art_dir(root)
    used, warnings = set(), []
    pairs = [("자리표 %s (%s)" % (sid, role), p, role) for sid, role, p in slot_paths.slot_refs(root)]
    pairs += [("소리 표 %s" % cue, p, "file") for cue, p in audio]
    for who, p, role in pairs:
        ext = Path(p).suffix.lower()
        if not p.startswith(prefix):
            if role in ("file", "extra", "fallback") and ext in ASSET_EXT:
                warnings.append("%s: chapter1/art 밖의 파일이라 원장이 덮지 않는다: %s" % (who, p))
            continue
        rel = p[len(prefix):]
        used.add(rel)
        if role == "meta" or ext not in ASSET_EXT:
            continue
        if not (base / rel).is_file():
            warnings.append("%s: 가리키는 파일이 없다: %s" % (who, rel))
        elif rel not in ledger_paths:
            warnings.append("%s: 원장에 없는 파일이다: %s" % (who, rel))
    no_slot = sorted(x for x in ledger_paths if x not in used)
    return {"present": True, "slots": len(table), "planned": sum(1 for s in table.values() if not s.get("file")),
            "audio_refs": len(audio), "warnings": warnings, "no_slot": no_slot, "error": err}


def run_check(root, ledger_path):
    errors, holes, notbl = [], [], []
    if not Path(ledger_path).is_file():
        return {"errors": ["원장이 없다: %s" % ledger_path], "holes": [], "release": [], "counts": {}}
    led = load_ledger(ledger_path)
    entries = led.get("assets", [])
    base = art_dir(root)
    seen = {}
    for i, e in enumerate(entries):
        pth = e.get("path")
        if is_empty(pth):
            errors.append("항목 %d: path 가 비었다" % i)
            continue
        if pth in seen:
            errors.append("%s: 원장에 두 번 있다" % pth)
        seen[pth] = e
        for k in REQUIRED:
            if is_empty(e.get(k)):
                errors.append("%s: 필수 칸 '%s' 이(가) 비었다" % (pth, k))
        if e.get("source_type") and e["source_type"] not in SOURCE_TYPES:
            errors.append("%s: source_type '%s' 은(는) 허용 값이 아니다 %s" % (pth, e["source_type"], SOURCE_TYPES))
        if e.get("source_type") == "ai_generated":
            for k in REQUIRED_AI:
                if is_empty(e.get(k)):
                    errors.append("%s: 생성물인데 '%s' 칸이 비었다" % (pth, k))
        f = base / pth
        if not f.is_file():
            errors.append("%s: 원장에는 있는데 파일이 없다" % pth)
        else:
            h = sha256_of(f)
            if e.get("sha256") and h != e["sha256"]:
                errors.append("%s: 해시가 다르다(원장 %s..., 실제 %s...)" % (pth, str(e["sha256"])[:12], h[:12]))
            if e.get("size") is not None and f.stat().st_size != e["size"]:
                errors.append("%s: 크기가 다르다(원장 %s, 실제 %d)" % (pth, e["size"], f.stat().st_size))
        for r in e.get("record_files", []):
            if not (base / r["path"]).is_file():
                errors.append("%s: 가리키는 기록 파일이 없다 %s" % (pth, r["path"]))
    for rel in list_asset_files(root):
        if rel not in seen:
            errors.append("%s: 파일이 있는데 원장에 없다" % rel)
    for pth, e in seen.items():
        unk = [k for k, v in e.items() if is_unknown(v) and k in
               ("source_type", "origin", "license", "date", "postprocess", "model", "prompt", "creator")]
        if unk:
            holes.append((pth, unk))
        pb = release_blockers(e)
        if pb:
            notbl.append((pth, pb))
    counts = {"entries": len(entries),
              "with_unknown": len(holes),
              "provenance_complete": sum(1 for e in entries if not provenance_blockers(e)),
              "release_ready": sum(1 for e in entries if not release_blockers(e)),
              "ignored_by_ext": ignored_files(root)}
    return {"errors": errors, "holes": holes, "release": notbl, "counts": counts, "slots": slot_report(root, set(seen))}


def _group(pairs, per_file):
    if per_file:
        return [(k, [p]) for p, k in pairs]
    g = {}
    for p, k in pairs:
        g.setdefault(k, []).append(p)
    return list(g.items())


def _fold(paths):
    """같은 폴더의 파일을 폴더/{a,b,c} 꼴로 접는다."""
    d = {}
    for p in paths:
        head, _, tail = p.rpartition("/")
        d.setdefault(head, []).append(tail)
    out = []
    for head, tails in d.items():
        pre = head + "/" if head else ""
        out.append(pre + (tails[0] if len(tails) == 1 else "{" + ",".join(tails) + "}"))
    return " ".join(out)


def cmd_check(a):
    res = run_check(a.root, a.ledger)
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print("== 오류(원장이 틀렸거나 어긋남): %d" % len(res["errors"]))
        for m in res["errors"]:
            print("  ERR", m)
        print("== 구멍: '미확인' 칸이 있는 항목 %d" % len(res["holes"]))
        for key, paths in _group([(p, ", ".join(u)) for p, u in res["holes"]], a.per_file):
            print("  HOLE [%d] %s :: %s" % (len(paths), key, _fold(paths)))
        print("== 배포 불가로 봐야 하는 항목 %d (출처 기록 부족 + 사람 확인 전 포함)" % len(res["release"]))
        for key, paths in _group([(p, "; ".join(w)) for p, w in res["release"]], a.per_file):
            print("  NO   [%d] %s :: %s" % (len(paths), key, _fold(paths)))
        sl = res.get("slots") or {"present": False}
        if not sl["present"]:
            print("== 자리표 대조: 자리표 없음(chapter1/art/asset_slots.json%s)" % (" 읽기 실패: " + sl["error"] if sl.get("error") else ""))
        else:
            print("== 자리표 대조: 자리 %d(파일 아직 없는 계획 자리 %d), 소리 표가 가리키는 파일 %d" % (sl["slots"], sl["planned"], sl["audio_refs"]))
            print("== 자리표·소리 표 경고(원장에 없거나 파일이 없음, 종료 코드에 영향 없음): %d" % len(sl["warnings"]))
            for m in sl["warnings"]:
                print("  WARN", m)
            print("== 자리 없음(원장에는 있는데 어느 자리·소리 표에도 없는 파일, 안 쓰임 후보일 뿐 단정하지 않음): %d" % len(sl["no_slot"]))
            if sl["no_slot"]:
                print("  SLOTLESS", _fold(sl["no_slot"]))
        c = res["counts"]
        if c:
            print("== 요약: 항목 %d, 출처 기록 갖춤 %d, 배포 가능 %d, 미확인 있음 %d" % (
                c["entries"], c["provenance_complete"], c["release_ready"], c["with_unknown"]))
            print("   원장 대상 아닌 파일(확장자별): %s" % c["ignored_by_ext"])
        print("   이 점검이 보지 않는 것: 파일 내용의 품질·저작권 실제 여부·약관 문구. 기록의 유무와 해시만 본다.")
    if res["errors"]:
        return 1
    if a.strict and (res["holes"] or res["release"]):
        return 2
    return 0


# ---------------------------------------------------------------- add

def cmd_add(a):
    base = art_dir(a.root)
    p = Path(a.path)
    if not p.is_absolute():
        p = (Path.cwd() / p)
    try:
        rel = p.resolve().relative_to(base.resolve()).as_posix()
    except ValueError:
        print("chapter1/art/ 안의 파일만 올린다: %s" % p)
        return 1
    if not p.is_file():
        print("파일이 없다: %s" % p)
        return 1
    if p.suffix.lower() not in ASSET_EXT:
        print("원장 대상 확장자가 아니다: %s" % p.suffix)
        return 1
    if a.source_type not in SOURCE_TYPES:
        print("--source-type 은 %s 중 하나" % (SOURCE_TYPES,))
        return 1
    prompt = a.prompt
    if a.prompt_file:
        prompt = Path(a.prompt_file).read_text(encoding="utf-8")
    ledger_path = Path(a.ledger)
    led = load_ledger(ledger_path) if ledger_path.is_file() else new_ledger(a.date)
    e = {"path": rel}
    e.update(file_facts(a.root, rel))
    miss = []

    def val(name, v):
        if is_empty(v):
            miss.append(name)
            return UNKNOWN + ": 입력 없음"
        return v
    e["source_type"] = a.source_type
    e["origin"] = val("origin", a.origin)
    e["license"] = val("license", a.license)
    if a.source_type == "ai_generated":
        e["model"] = val("model", a.model)
        e["prompt"] = val("prompt", prompt)
        e["terms_checked"] = bool(a.terms_checked)
    elif a.model:
        e["model"] = a.model
    if a.creator:
        e["creator"] = a.creator
    e["date"] = a.date or datetime.date.today().isoformat()
    e["postprocess"] = val("postprocess", a.postprocess)
    e["record_files"] = [record_ref(a.root, r) for r in (a.record_file or [])]
    e["release_cleared"] = False
    e["status"] = a.status or "등록됨"
    if a.notes:
        e["notes"] = a.notes
    entries = led.setdefault("assets", [])
    idx = next((i for i, x in enumerate(entries) if x.get("path") == rel), None)
    if idx is not None and not a.replace:
        print("이미 있는 항목이다(바꾸려면 --replace): %s" % rel)
        return 1
    if idx is not None:
        entries[idx] = e
    else:
        entries.append(e)
        entries.sort(key=lambda x: x["path"])
    write_json(ledger_path, led)
    print("등록: %s sha256=%s... %d바이트" % (rel, e["sha256"][:12], e["size"]))
    if miss:
        print("  '미확인' 으로 적은 칸: %s (check 가 구멍으로 올린다)" % ", ".join(miss))
    return 0


# ---------------------------------------------------------------- migrate

def new_ledger(date=None):
    return {
        "schema": 1,
        "scope": "chapter1/art/ 아래 모든 에셋 파일(%s). 문서·메타데이터 JSON·스크립트·.import 는 대상이 아니다." % ", ".join(sorted(ASSET_EXT)),
        "created": date or datetime.date.today().isoformat(),
        "conventions": [
            "경로는 chapter1/art 기준 상대 경로.",
            "값을 모르면 '미확인' 으로 시작하는 글로 적는다. 지어내지 않는다.",
            "배포 가능 여부는 원장에 적지 않고 `python tools/art/asset_ledger.py check` 가 계산한다. release_cleared 는 사람이 확인한 뒤에만 true 로 바꾼다.",
            "생성물(ai_generated)은 모델·프롬프트·약관 확인(terms_checked)이 있어야 출처 기록이 갖춰진 것으로 본다.",
        ],
        "records": [],
        "assets": [],
    }


def norm_path(s):
    """사용자 홈 경로를 치환한다(계정 식별 정보를 원장에 옮기지 않는다)."""
    if not isinstance(s, str):
        return s
    for pre in ("C:\\Users\\twins", "C:/Users/twins"):
        s = s.replace(pre, "%USERPROFILE%")
    return s


def norm_deep(x):
    if isinstance(x, str):
        return norm_path(x)
    if isinstance(x, list):
        return [norm_deep(i) for i in x]
    if isinstance(x, dict):
        return {k: norm_deep(v) for k, v in x.items()}
    return x


def _read(root, rel):
    p = art_dir(root) / rel
    if not p.is_file():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


Q3 = "quality03/"
Q3_AI_MODEL = "built-in image_gen.imagegen (모델 이름·버전 기록 없음, 원장 v04 의 generation_mode 표기)"
Q3_ASSETS_NOTE = "날짜는 quality03/README.ko.md 표제(2026-10-31)."

AI_UNKNOWN = {
    "source_type": "ai_generated",
    "model": UNKNOWN + ": 생성 도구 이름·버전 기록 없음",
    "prompt": UNKNOWN + ": 프롬프트 기록 없음",
    "terms_checked": False,
}

# 폴더별 규칙(처음 맞는 것). quality03 PNG 는 옛 원장에서 따로 채운다. 값은 각 폴더의 ATTRIBUTION·README 에서 옮긴 것만 쓴다.
SEED_RULES = [
    ("fonts/NotoSerifKR-VF.ttf", dict(
        source_type="third_party", creator="Google Fonts 프로젝트의 Noto Serif KR 저작자들",
        origin="google/fonts 저장소 ofl/notoserifkr (https://github.com/google/fonts/tree/main/ofl/notoserifkr), 판 2.003. 원래 이름 NotoSerifKR[wght].ttf",
        license="SIL Open Font License 1.1 (원문 fonts/NotoSerifKR-OFL.txt)", date="2026-11-18",
        postprocess="없음(파일 내용 그대로, 이름만 NotoSerifKR-VF.ttf 로 바꿈)",
        obligations="OFL 원문을 배포 폴더·크레딧에 포함(T4 고지 항목)",
        records=["fonts/ATTRIBUTION.ko.md", "fonts/NotoSerifKR-OFL.txt"])),
    ("fonts/PretendardVariable.ttf", dict(
        source_type="third_party", creator="Pretendard 저작자(orioncactus)",
        origin="orioncactus/pretendard (https://github.com/orioncactus/pretendard) v1.3.9",
        license="SIL Open Font License 1.1 (원문 fonts/Pretendard-LICENSE.txt), 예약 글꼴 이름 Pretendard", date="2026-11-18",
        postprocess="없음(파일 내용 그대로)",
        obligations="OFL 원문을 배포 폴더·크레딧에 포함(T4 고지 항목). 부분 집합 등 수정판을 만들면 이름을 바꿔야 한다",
        records=["fonts/ATTRIBUTION.ko.md", "fonts/Pretendard-LICENSE.txt"])),
    ("chained_warden/v01/*", dict(
        source_type="third_party_derived", creator="Mophs",
        origin="OpenGameArt 'Chained Demon' https://opengameart.org/content/chained-demon (원본·파생 source 는 저장소 밖 C:/Project/game-research/art-sources/oga-chained-demon-20261101-01/)",
        license="CC BY 3.0 (제공된 대안 중 선택) https://creativecommons.org/licenses/by/3.0/",
        date=UNKNOWN + ": 취득일 기록 없음(보존 폴더 이름에 20261101)",
        postprocess="구형 재질의 PBR 변환/packed diffuse, smooth shading, 정점 가중치 4개 보정, 새 RootMotion, 자체 FK 8클립, 미터 변환, 피부/가면/사슬 재질 분리(원본 diffuse 픽셀 유지)",
        obligations="CC BY 3.0 저작자 표시(원작자·출처·라이선스·변경 사실)를 게임 크레딧에 넣어야 한다",
        records=["chained_warden/v01/ATTRIBUTION.ko.md"],
        notes="원본·파생 source 가 저장소 밖에 있어 이 저장소만으로는 원본 대조 불가(도구 검토 G2 와 같은 종류).")),
    ("rigged_mage/v01/*", dict(
        source_type="third_party_derived", creator="thecubber (원 리그 크레딧 Julius)",
        origin="OpenGameArt 'Rigged textured mage' https://opengameart.org/content/rigged-textured-mage",
        license="CC BY-SA 3.0 https://creativecommons.org/licenses/by-sa/3.0/ (파생물도 같은 CC BY-SA 3.0)",
        date=UNKNOWN + ": 취득일 기록 없음(변경일 2026-11-17)",
        postprocess="구형 재질 변환, 자체 IK 보행/대기/시전/피격/사망 베이크, 무가중치 정점 보정, 미터 변환. 2026-11-17 색·노멀 텍스처에서 망토 등판 문양을 지움(Pillow, numpy, scipy)",
        obligations="CC BY-SA 3.0 저작자 표시와 동일 조건 변경 허락(파생물 공개 조건). 배포 전 검토 필요",
        records=["rigged_mage/v01/ATTRIBUTION.ko.md"])),
    ("skeleton_outlaw/v02/*", dict(
        source_type="third_party_derived", creator="KevDev",
        origin=UNKNOWN + ": ATTRIBUTION 은 ../v01/ATTRIBUTION.ko.md 와 SOURCE.json 을 가리키나 둘 다 저장소에 없다",
        license="CC0 (ATTRIBUTION 서술; 근거가 되는 v01 기록은 저장소에 없다)",
        date=UNKNOWN + ": 기록 없음",
        postprocess="8mesh/6skin 을 같은 bind 공간으로 변환해 1mesh/2surface/1skin 으로 병합, 재질 정리(원본 삼각형·UV·스킨 가중치·9클립·텍스처 유지)",
        records=["skeleton_outlaw/v02/ATTRIBUTION.ko.md"],
        notes="원본 기록(v01, SOURCE.json)이 저장소에 없어 CC0 근거를 확인할 수 없다.")),
    ("characters/*_v02.png", dict(
        AI_UNKNOWN, creator="사용자(이미지 생성 도구로 직접 생성해 제공)",
        origin="사용자가 이미지 생성 도구로 직접 만들어 제공한 원화, 2026-11-16. 프롬프트 바탕 plans/director-redesign-20261114/ART-PROMPTS-v2.ko.md(옛 저장소 문서)",
        prompt=UNKNOWN + ": 생성 뒤 대화로 고쳐 최종 문장이 기록되지 않았다(ATTRIBUTION 서술)",
        license=UNKNOWN + ": 사용자 제공 생성물, 생성 도구 이용 약관 확인 전(ATTRIBUTION: 배포 전 약관·수위 기준 확인)",
        date="2026-11-16", postprocess="없음(배경 제거·크기 조정 안 함)",
        records=["characters/ATTRIBUTION.ko.md"],
        notes="ATTRIBUTION 이 말하는 v01 파일(ember_witch/, frost_witch/ 등)은 이 폴더에 없다. v02 는 1024x1536 PNG, 배경 포함.")),
    ("portraits/frost/layers/*", dict(
        source_type="derived", creator="프로젝트(Python PIL, numpy 로 원화를 부위별로 나눔)",
        origin="원화 chapter1/art/characters/frost_witch_v02.png 에서 파생. 2026-11-17 제작, 2026-11-18 저장소로 복사",
        license=UNKNOWN + ": 원화와 같은 권리를 따른다고 보나 원화의 생성 도구 약관 확인 전",
        date="2026-11-17",
        postprocess="부위별 다각형·밝기 경계로 분할, 가려진 곳은 거울 반사와 번짐으로 채움, 속성 효과 지움",
        records=["portraits/ATTRIBUTION.ko.md", "portraits/frost/layers_source.json"])),
    ("portraits/ember/layers/*", dict(
        source_type="derived", creator="프로젝트(Python PIL, numpy, scipy)",
        origin="자세 시안 _local/art/drafts/ember_witch_pose/p2-r1.png(저장소 밖, 시안의 생성 도구·프롬프트 미확인)에서 파생",
        license=UNKNOWN + ": 시안의 생성 출처·약관 미확인",
        date="2026-11-17",
        postprocess="손으로 잡은 다각형을 윤곽 밝기에 맞춰 분할, 가려진 곳은 거울 반사와 번짐으로 채움, 불꽃 띠·불똥 지움",
        records=["portraits/ATTRIBUTION.ko.md", "portraits/ember/layers_source.json"])),
    ("portraits/storm/layers/*", dict(
        source_type="derived", creator="프로젝트(Python PIL, numpy, scipy)",
        origin="자세 시안 _local/art/drafts/storm_witch_pose/p3-r1.png(저장소 밖, 시안의 생성 도구·프롬프트 미확인)에서 파생",
        license=UNKNOWN + ": 시안의 생성 출처·약관 미확인",
        date="2026-11-17",
        postprocess="분할 후 두 손 사이 번개를 몸통·팔·배경에서 지우고 채움(배경 보정 fix_bg.py 는 저장소 밖)",
        records=["portraits/ATTRIBUTION.ko.md", "portraits/storm/layers_source.json"])),
    ("portraits/*/*_eyes_*.png", dict(
        AI_UNKNOWN, creator="프로젝트(Codex CLI 그림 생성의 국소 편집)",
        origin="원화의 눈 자리만 Codex CLI 로 다시 그려 원화 좌표에 맞춰 잘라 냄. 작업 폴더 _local/art/drafts/*_witch_blink/(저장소 밖)",
        prompt=UNKNOWN + ": 프롬프트 기록 없음(작업 폴더는 저장소 밖)",
        model=UNKNOWN + ": Codex CLI 로 기록됨, 모델 이름·버전 기록 없음",
        license=UNKNOWN + ": 원화와 같은 권리를 따른다고 보나 약관 확인 전",
        date="2026-11-17", postprocess="원화 좌표에 맞춰 잘라 냄",
        records=["portraits/ATTRIBUTION.ko.md"])),
    ("equipment_icons35/*", dict(
        source_type="project_original", creator="프로젝트",
        origin="프로젝트 자체 SVG 벡터 드로잉. 외부 그림·글꼴·필터·원격 리소스 없음(ATTRIBUTION 서술)",
        license="프로젝트 자체 제작(제3자 요소 없음, ATTRIBUTION 서술)",
        date=UNKNOWN + ": 제작일 기록 없음", postprocess="없음(벡터 직접 작성, tools/art/make_equipment_icons.py 가 만든 것으로 보이나 기록에는 없음)",
        records=["equipment_icons35/ATTRIBUTION.ko.md"],
        notes="제품34 런타임 미연결로 기록돼 있다.")),
    ("ui/kit/hud_atlas.png", dict(
        AI_UNKNOWN, creator="프로젝트(Codex 생성 시안을 잘라 보정)",
        origin="Codex 생성 시안(2026-11-17) kit_c rim60 의 조각 36개를 build_kit.py 로 한 장에 모음",
        prompt=UNKNOWN + ": 프롬프트 파일이 _local/art/drafts/ui_kit_v2/kit_c/ 에 있다고 기록돼 있으나 저장소에 없다",
        model=UNKNOWN + ": Codex 로 기록됨, 모델 이름·버전 기록 없음",
        license=UNKNOWN + ": 생성 도구 약관 확인 전", date="2026-11-17",
        postprocess="시안 그림에서 조각을 잘라 마젠타 바탕을 떼고 보정(ui/kit/build_kit.py)",
        records=["ui/kit/ATTRIBUTION.ko.md", "ui/kit/build_kit.py"])),
    ("ui/kit/*", dict(
        AI_UNKNOWN, creator="프로젝트(Codex 생성 1차 키트 + 코드)",
        origin="Codex 생성(1차 키트) + 코드, 2026-11-17. 전투 HUD 밖 화면용",
        prompt=UNKNOWN + ": 프롬프트 기록 없음",
        model=UNKNOWN + ": Codex 로 기록됨, 모델 이름·버전 기록 없음",
        license=UNKNOWN + ": 생성 도구 약관 확인 전", date="2026-11-17",
        postprocess="코드 가공(내용은 기록에 없음, build_kit.py 참조)",
        records=["ui/kit/ATTRIBUTION.ko.md"])),
    ("actors/*", dict(
        AI_UNKNOWN, creator=UNKNOWN + ": 기록 없음",
        origin="README 는 '독립 생성한 2.5D PNG 스프라이트' 라고만 적는다. README 가 가리키던 출처·프롬프트·원본 경로 기록(옛 저장소 plans/chapter1-c2-20261031-01/)은 이 저장소에 없다",
        prompt=UNKNOWN + ": 기록 없음",
        license=UNKNOWN + ": README 는 CC0·제3자 라이선스 모델로 표기하지 않는다고만 적는다",
        date=UNKNOWN + ": 생성일 기록 없음(README 표제 2026-10-31)",
        postprocess=UNKNOWN + ": README 는 분석 스크립트로 픽셀을 고치지 않았다고 서술하나 근거 기록 없음",
        records=["README.ko.md"])),
]


def match_rule(rel):
    for pat, rule in SEED_RULES:
        if fnmatch.fnmatch(rel, pat):
            return rule
    return None


def build_entry_from_rule(root, rel, rule):
    rule = dict(rule)
    recs = rule.pop("records", [])
    e = {"path": rel}
    e.update(file_facts(root, rel))
    keys = ("source_type", "creator", "origin", "license", "date", "postprocess", "model", "prompt",
            "terms_checked", "obligations")
    for k in keys:
        if k in rule:
            e[k] = rule[k]
    e["record_files"] = [record_ref(root, r) for r in recs]
    e["release_cleared"] = False
    e["status"] = rule.get("status", "기록 이관(원장 migrate)")
    if "notes" in rule:
        e["notes"] = rule["notes"]
    return e


def migrate_quality03_images(root, led, used_records):
    """quality03 PNG: v04(최신)를 기준으로, v01·v03·GENERATED-*·검사 파일을 합쳐 한 항목으로."""
    v04 = _read(root, Q3 + "ASSET-LEDGER-v04.json")
    v03 = _read(root, Q3 + "ASSET-LEDGER-v03.json")
    v01 = _read(root, Q3 + "ASSET-LEDGER-v01.json")
    gens = {}
    for g in ("GENERATED-HERO.json", "GENERATED-SOIL.json", "GENERATED-FOLIAGE-RUN.json", "GENERATION-PROMPTS.json"):
        d = _read(root, Q3 + g)
        if d is None:
            continue
        used_records.add(Q3 + g)
        if "prompt" in d:  # GENERATED-HERO / SOIL: 평평한 꼴
            gens.setdefault(d["target"], []).append((Q3 + g, d))
        else:
            for _, v in d.items():
                if isinstance(v, dict) and "target" in v:
                    gens.setdefault(v["target"], []).append((Q3 + g, v))
    inspections = {
        "cloister_props_v01.png": "PROP-INSPECTION.json",
        "hero_cast_v01.png": "HERO-CAST-INSPECTION.json",
        "cloister_foliage_v01.png": "FOLIAGE-INSPECTION.json",
    }
    companions = {
        "cloister_props_v01.png": ["cloister_props_v01.json"],
        "hero_cast_v01.png": ["hero_cast_v01.json"],
        "cloister_foliage_v01.png": ["cloister_foliage_v01.json"],
    }
    earlier = {}
    for name, d in (("ASSET-LEDGER-v01.json", v01), ("ASSET-LEDGER-v03.json", v03)):
        if d:
            for a in d.get("assets", []):
                earlier.setdefault(a["path"], []).append((name, a))
    out = []
    if not v04:
        return out
    for group, status_default in (("accepted_for_runtime_trial", None), ("rejected_attempts", "rejected")):
        for a in v04.get(group, []):
            rel = Q3 + a["path"]
            if not (art_dir(root) / rel).is_file():
                out.append(("missing", rel))
                continue
            e = {"path": rel}
            e.update(file_facts(root, rel))
            e["source_type"] = "ai_generated"
            e["creator"] = "프로젝트(Codex 내장 이미지 생성)"
            e["origin"] = "생성 원본 %s (quality03 원장 v04). 이 경로는 저장소 밖이며 홈 경로는 %%USERPROFILE%% 로 치환" % norm_path(a.get("original", UNKNOWN))
            e["original_sha256"] = a.get("original_sha256")
            e["model"] = Q3_AI_MODEL
            e["generation_mode"] = a.get("generation_mode")
            e["prompt"] = norm_path(a.get("prompt") or UNKNOWN + ": v04 에 프롬프트 없음")
            e["reference_inputs"] = norm_deep(a.get("reference_inputs", []))
            e["terms_checked"] = False
            e["license"] = a.get("rights", UNKNOWN)
            e["date"] = "2026-10-31"
            e["postprocess"] = ("없음: 생성 원본 PNG 를 그대로 복사(원본 sha256 일치 %s)" % ("확인됨" if a.get("sha256") == a.get("original_sha256") else UNKNOWN))
            e["status"] = a.get("status") or (("rejected_motion_coherence" if group == "rejected_attempts" else "채택(런타임 시험용)"))
            if a.get("reason"):
                e["reject_reason"] = a["reason"]
            notes = [Q3_ASSETS_NOTE, "최종 품질 승인 아님(v04 status). 모델 이름·버전은 기록에 없다."]
            if a.get("sha256") != e["sha256"]:
                notes.append("주의: v04 의 sha256(%s...)과 현재 파일이 다르다." % str(a.get("sha256"))[:12])
            e["notes"] = " ".join(notes)
            e["width_height_in_v04"] = [a.get("width"), a.get("height"), a.get("mode")]
            recs = ["quality03/ASSET-LEDGER-v04.json"]
            used_records.add("quality03/ASSET-LEDGER-v04.json")
            for nm, old in earlier.get(a["path"], []):
                used_records.add(Q3 + nm)
            for c in companions.get(a["path"], []):
                recs.append(Q3 + c)
            e["earlier_records"] = [
                {"record": Q3 + nm, "sha256_then": old.get("sha256"),
                 "same_hash_as_now": old.get("sha256") == e["sha256"],
                 "same_prompt_as_v04": old.get("prompt") == a.get("prompt")}
                for nm, old in earlier.get(a["path"], [])]
            variants = []
            for gname, g in gens.get(a["path"], []):
                if g.get("prompt") != a.get("prompt"):
                    variants.append({"record": gname, "prompt": norm_path(g.get("prompt")),
                                     "original": norm_path(g.get("original"))})
                recs.append(gname)
            if variants:
                e["prompt_other_records"] = variants  # v04 와 다른 문장이 다른 기록에 있으면 잃지 않도록 보존
            if a["path"] in inspections:
                ins = _read(root, Q3 + inspections[a["path"]])
                if ins is not None:
                    e["inspection"] = {"record": Q3 + inspections[a["path"]], "data": ins}
                    used_records.add(Q3 + inspections[a["path"]])
            e["record_files"] = []
            for r in dict.fromkeys(recs):
                e["record_files"].append(record_ref(root, r))
            e["release_cleared"] = False
            if v04.get("limitations"):
                e["limitations_from_v04"] = v04["limitations"]
            out.append(("ok", e))
    return out


def audio_entries(root, rels):
    al = _read(root, "quality03_audio/AUDIO-LEDGER.json")
    out = []
    products = {p["file"]: p for p in (al or {}).get("products", [])}
    for rel in rels:
        name = rel.split("/", 1)[1]
        e = {"path": rel}
        e.update(file_facts(root, rel))
        if name in products:
            p = products[name]
            e.update(
                source_type="third_party_derived", creator=al.get("creator", UNKNOWN),
                origin="Kenney 에셋 가공(소스 페이지: %s). 층별 소스·가중은 quality03_audio/AUDIO-LEDGER.json products[%s].layers" % (", ".join(al.get("pages", [])), name),
                license="%s (원문 quality03_audio/LICENSE-Kenney-*.txt)" % al.get("license", UNKNOWN),
                date=UNKNOWN + ": 가공일 기록 없음",
                postprocess=al.get("method", UNKNOWN),
                record_files=[record_ref(root, "quality03_audio/AUDIO-LEDGER.json")],
                release_cleared=False, status="기록 이관(원장 migrate)")
            if p.get("sha256") != e["sha256"]:
                e["notes"] = "주의: AUDIO-LEDGER 의 sha256 과 현재 파일이 다르다."
            if name == "ambience.wav":
                e["notes"] = (e.get("notes", "") + " AUDIO-LEDGER 서술: 설계한 드론 후보이며 현장 녹음이 아니다.").strip()
        elif name in ("jewel_0.wav", "legend_0.wav"):
            e.update(
                source_type="project_original", creator="프로젝트(tools/dev/make_drop_sounds.py)",
                origin="외부 소스 없이 tools/dev/make_drop_sounds.py 가 사인파 배음으로 합성(quality03_audio/SYNTHESIZED.ko.md)",
                license="프로젝트 자체 합성(제3자 요소 없음, SYNTHESIZED.ko.md 서술)",
                date=UNKNOWN + ": 합성일 기록 없음", postprocess="없음(스크립트 출력)",
                record_files=[record_ref(root, "quality03_audio/SYNTHESIZED.ko.md")],
                release_cleared=False, status="기록 이관(원장 migrate)",
                notes="AUDIO-LEDGER.json 에는 없다(도구 검토 G3). 소리 원장 정리는 sound-designer 몫.")
        else:
            e.update(source_type=UNKNOWN + ": 기록 없음", origin=UNKNOWN + ": 어느 기록에도 없다",
                     license=UNKNOWN, date=UNKNOWN, postprocess=UNKNOWN, record_files=[],
                     release_cleared=False, status="기록 없음")
        out.append(e)
    return out


def cmd_migrate(a):
    ledger_path = Path(a.ledger)
    if ledger_path.is_file() and not a.force:
        print("원장이 이미 있다. 덮어쓰려면 --force (손으로 고친 내용이 사라진다): %s" % ledger_path)
        return 1
    led = new_ledger(a.date)
    used = set()
    assets = {}
    q = migrate_quality03_images(a.root, led, used)
    for kind, e in q:
        if kind == "ok":
            assets[e["path"]] = e
    files = list_asset_files(a.root)
    audio_rels = [r for r in files if r.startswith("quality03_audio/") and ASSET_EXT[Path(r).suffix.lower()] == "audio"]
    for e in audio_entries(a.root, audio_rels):
        assets[e["path"]] = e
    for rel in files:
        if rel in assets:
            continue
        rule = match_rule(rel)
        if rule is None:
            e = {"path": rel}
            e.update(file_facts(a.root, rel))
            e.update(source_type=UNKNOWN + ": 어떤 기록에도 없다", origin=UNKNOWN, license=UNKNOWN, date=UNKNOWN,
                     postprocess=UNKNOWN, record_files=[], release_cleared=False, status="기록 없음")
            assets[rel] = e
        else:
            assets[rel] = build_entry_from_rule(a.root, rel, rule)
    led["assets"] = [assets[k] for k in sorted(assets)]
    # 보존한 옛 기록 파일(지우지 않는다). 해시로 원본 그대로임을 고정한다.
    rec_files = sorted(p.relative_to(art_dir(a.root)).as_posix() for p in (art_dir(a.root) / "quality03").glob("*.json")
                       if p.name.startswith(("ASSET-LEDGER-v", "GENERATED-", "GENERATION-", "ART-METADATA", "HERO-CAST", "PROP-", "FOLIAGE-")))
    led["records"] = [dict(record_ref(a.root, r), role=_role(r)) for r in rec_files]
    write_json(ledger_path, led)
    print("합침: 항목 %d, 보존한 옛 기록 %d -> %s" % (len(led["assets"]), len(led["records"]), ledger_path))
    return 0


def _role(rel):
    n = rel.split("/")[-1]
    if n.startswith("ASSET-LEDGER-v"):
        return "옛 원장(%s). 지우지 않고 보존. 최신은 v04" % n
    if n.startswith("GENERAT"):
        return "생성 프롬프트·원본 경로 기록. 원장 항목의 prompt 와 대조해 다른 문장은 prompt_other_records 에 보존"
    if n.endswith("INSPECTION.json"):
        return "알파·연결 요소 검사 결과. 해당 항목의 inspection 에 복사"
    if n.startswith("ART-METADATA"):
        return "메타데이터 스크립트 첫 실행 실패(exit1)와 복구 기록. 게임 결함 아님"
    return "옛 기록"


# ---------------------------------------------------------------- main

def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(ROOT), help="저장소 루트(기본: 이 파일 기준)")
    ap.add_argument("--ledger", default=None, help="원장 경로(기본: <root>/chapter1/art/ASSET-LEDGER.json)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--strict", action="store_true")
    c.add_argument("--json", action="store_true")
    c.add_argument("--per-file", action="store_true", help="같은 사유를 묶지 않고 파일마다")
    ad = sub.add_parser("add")
    ad.add_argument("path")
    ad.add_argument("--source-type", required=True)
    ad.add_argument("--origin")
    ad.add_argument("--license")
    ad.add_argument("--model")
    ad.add_argument("--prompt")
    ad.add_argument("--prompt-file")
    ad.add_argument("--creator")
    ad.add_argument("--date")
    ad.add_argument("--postprocess")
    ad.add_argument("--record-file", action="append", help="chapter1/art 기준 상대 경로, 여러 번 가능")
    ad.add_argument("--terms-checked", action="store_true")
    ad.add_argument("--status")
    ad.add_argument("--notes")
    ad.add_argument("--replace", action="store_true")
    m = sub.add_parser("migrate")
    m.add_argument("--force", action="store_true")
    m.add_argument("--date", help="created 칸에 적을 날짜(기본 오늘)")
    a = ap.parse_args(argv)
    if a.ledger is None:
        a.ledger = str(art_dir(a.root) / LEDGER_NAME)
    if a.cmd == "migrate":
        return cmd_migrate(a)
    if a.cmd == "add":
        return cmd_add(a)
    return cmd_check(a)


if __name__ == "__main__":
    sys.exit(main())
