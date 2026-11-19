#!/usr/bin/env python3
"""낱말 검사기: 플레이어에게 보이는 글에서 금지·제한 낱말, 이름 꼴, 이름 글자 수, 영어 용어집을 찾는다.

규칙은 docs/story/wording-rules.json(세계관·스토리 책임자가 관리)에서 읽는다. 이 파일은 규칙을 갖지 않는다.
검사 대상: chapter1/i18n/ko.po·en.po, chapter1/data/*.json 의 한글 글(이름·설명·lore 등), chapter1/**/*.gd 의 한글 리터럴(tests 제외).
docs/ 는 검사하지 않는다. 글 모으는 방식은 tools/dev/check_glyphs.py 와 같다(그 파일의 정규식·풀이 함수를 불러 쓰고,
fontTools 가 없어 불러오지 못하면 같은 정의를 쓴다).

  python tools/dev/wording_lint.py                         # 검사. fail 이 있으면 종료 1, 규칙 파일이 없으면 2
  python tools/dev/wording_lint.py --json --out=_local/wording/lint.json
  python tools/dev/wording_lint.py --rules=tools/dev/test_data/wording-rules.test.json

규칙 꼴(모르는 키는 무시):
  banned / restricted : [{word, stems[], grade: fail|warn, rule, exceptions[], note}]   글에 word 나 stems 가 들어 있으면 걸린다.
                        exceptions 는 동음어 보호: 예외 문구 안에 겹친 걸림은 버린다. grade 가 없으면 banned 는 fail, restricted 는 warn.
  name_shape          : [{id, desc, pattern(정규식), grade, applies_to[]}]  이름에 pattern 이 맞으면 걸린다(나쁜 꼴을 적는다).
                        applies_to 가 비면 이름에만. 항목은 문맥 이름(name, description, lore, text) 또는 키·파일 글롭.
  name_max_chars      : {default, by_key_pattern{글롭: 수}, grade}  이름 글자 수 상한(grade 가 없으면 fail).
  en_glossary         : {must[{ko, en}], banned_en[]}  en.po 의 금지 영어 낱말, 한국어 용어가 든 키의 영어에 en 이 있는지.
  allow_pending       : [{file, key_or_text, decision, why}]  결정 대기. 세어서 따로 보여 주고 fail 로 치지 않는다.
"""
import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RULES = ROOT / "docs" / "story" / "wording-rules.json"

try:  # check_glyphs 는 fontTools 가 있어야 불러진다. 없으면 같은 정의를 쓴다.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from check_glyphs import STR_RE, unescape  # type: ignore
except Exception:  # noqa: BLE001
    STR_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

    def unescape(s: str) -> str:
        return s.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\")

HANGUL = re.compile(r"[가-힣]")
NAME_KEY_PO = re.compile(r"\.name$")  # .title 은 창·알림 제목이라 이름이 아니다
NAME_JSON_KEYS = {"name"}
SKIP_JSON_KEYS = {"note", "notes", "comment", "comments", "source", "why"}
CONTEXT_JSON = {"description": "description", "desc": "description", "lore": "lore", "flavor": "lore", "text": "text"}


# ---------------------------------------------------------------- 글 모으기
def _t(file, line, key, text, lang, ctx):
    return {"file": file, "line": line, "key": key, "text": text, "lang": lang, "ctx": ctx}


def parse_po(path: Path, rel: str, lang: str) -> list:
    """msgid(키) → msgstr 글. 줄 번호는 msgstr 가 시작한 줄. 복수형 칸은 줄바꿈으로 이어 붙인다."""
    out = []
    key = None
    segs: list = []
    state = None
    str_line = 0

    def flush():
        if key and segs and "".join(segs).strip():
            ctx = "name" if NAME_KEY_PO.search(key) else ("lore" if ".lore" in key else "text")
            out.append(_t(rel, str_line, key, "\n".join(segs), lang, ctx))

    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if line.startswith("#") or not line:
            continue
        m = re.match(r'^(msgid_plural|msgid|msgstr(?:\[\d+\])?)\s*"(.*)"$', line)
        if m:
            kind, val = m.group(1), unescape(m.group(2))
            if kind == "msgid":
                flush()
                key, segs, state = val, [], "id"
            elif kind == "msgid_plural":
                state = "plural"
            else:
                if not segs:
                    str_line = n
                segs.append(val)
                state = "str"
            continue
        m = re.match(r'^"(.*)"$', line)
        if m:
            val = unescape(m.group(1))
            if state == "id" and key is not None:
                key += val
            elif state == "str" and segs:
                segs[-1] += val
    flush()
    return out


def collect_json(path: Path, rel: str) -> list:
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines()
    out = []

    def line_of(s: str) -> int:
        needle = json.dumps(s, ensure_ascii=False)
        for i, ln in enumerate(lines, 1):
            if needle in ln:
                return i
        return 0

    def walk(v, keypath, last):
        if isinstance(v, str):
            if HANGUL.search(v) and last not in SKIP_JSON_KEYS and not last.startswith("_"):
                ctx = "name" if last in NAME_JSON_KEYS else CONTEXT_JSON.get(last, "text")
                out.append(_t(rel, line_of(v), keypath, v, "ko", ctx))
        elif isinstance(v, list):
            for i, x in enumerate(v):
                walk(x, f"{keypath}[{i}]", last)
        elif isinstance(v, dict):
            for k, x in v.items():
                walk(x, f"{keypath}.{k}" if keypath else str(k), str(k))

    walk(json.loads(raw), "", "")
    return out


def collect_gd(path: Path, rel: str) -> list:
    out = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        for m in STR_RE.finditer(line):
            s = unescape(m.group(1))
            if HANGUL.search(s):
                out.append(_t(rel, n, "", s, "ko", "text"))
    return out


def collect_texts(root: Path = ROOT) -> list:
    out = []
    i18n = root / "chapter1" / "i18n"
    for po, lang in (("ko.po", "ko"), ("en.po", "en")):
        if (i18n / po).is_file():
            out += parse_po(i18n / po, f"chapter1/i18n/{po}", lang)
    for js in sorted((root / "chapter1" / "data").glob("*.json")):
        try:
            out += collect_json(js, f"chapter1/data/{js.name}")
        except (ValueError, OSError):
            pass
    for gd in sorted((root / "chapter1").rglob("*.gd")):
        rel = gd.relative_to(root)
        if "tests" in rel.parts:
            continue
        out += collect_gd(gd, rel.as_posix())
    return out


# ---------------------------------------------------------------- 검사
def _spans(text: str, needles: list) -> list:
    spans = []
    for nd in needles:
        if nd:
            spans += [(m.start(), m.end()) for m in re.finditer(re.escape(nd), text)]
    return spans


def _covered(span, protected) -> bool:
    return any(a <= span[0] and span[1] <= b for a, b in protected)


def _grade(g, default="warn") -> str:
    return g if g in ("fail", "warn") else default


def _f(t, rule, grade, matched, note):
    return {"file": t["file"], "line": t["line"], "key": t["key"], "rule": rule, "grade": grade,
            "matched": matched, "text": t["text"], "note": note, "pending": None}


def check_words(t: dict, rules: dict, findings: list):
    if t["lang"] != "ko":
        return
    for section, default in (("banned", "fail"), ("restricted", "warn")):
        for r in rules.get(section) or []:
            if not isinstance(r, dict) or not r.get("word"):
                continue
            needles = [r["word"]] + [s for s in (r.get("stems") or []) if s]
            protected = _spans(t["text"], r.get("exceptions") or [])
            hit = None
            for nd in needles:
                for m in re.finditer(re.escape(nd), t["text"]):
                    if not _covered((m.start(), m.end()), protected):
                        hit = m.group(0)
                        break
                if hit:
                    break
            if hit:
                findings.append(_f(t, f"{section}:{r['word']}", _grade(r.get("grade"), default), hit,
                                   " ".join(x for x in (r.get("rule", ""), r.get("note", "")) if x)))


def _applies(applies: list, t: dict) -> bool:
    if not applies:
        return t["ctx"] == "name"
    return any(a == t["ctx"] or fnmatch.fnmatch(t["key"] or "", a) or fnmatch.fnmatch(t["file"], a) for a in applies)


def check_names(t: dict, rules: dict, findings: list):
    if t["lang"] != "ko":
        return
    for r in rules.get("name_shape") or []:
        if not isinstance(r, dict) or not r.get("pattern") or not _applies(r.get("applies_to") or [], t):
            continue
        try:
            m = re.search(r["pattern"], t["text"])
        except re.error:
            continue
        if m:
            findings.append(_f(t, f"name_shape:{r.get('id', '?')}", _grade(r.get("grade"), "warn"), m.group(0), r.get("desc", "")))
    mc = rules.get("name_max_chars")
    if isinstance(mc, dict) and t["ctx"] == "name":
        limit = mc.get("default")
        for pat, n in (mc.get("by_key_pattern") or {}).items():
            if fnmatch.fnmatch(t["key"] or "", pat):
                limit = n
                break
        if isinstance(limit, int) and len(t["text"]) > limit:
            findings.append(_f(t, "name_max_chars", _grade(mc.get("grade"), "fail"), t["text"], f"{len(t['text'])}자 > 상한 {limit}자"))


def check_english(texts: list, rules: dict, findings: list):
    g = rules.get("en_glossary")
    if not isinstance(g, dict):
        return
    en = [t for t in texts if t["lang"] == "en"]
    ko = {t["key"]: t for t in texts if t["lang"] == "ko" and t["file"].endswith(".po")}
    for t in en:
        for w in g.get("banned_en") or []:
            m = re.search(r"\b" + re.escape(w) + r"\b", t["text"], re.I)
            if m:
                findings.append(_f(t, f"en_banned:{w}", "fail", m.group(0), ""))
        k = ko.get(t["key"])
        for p in (g.get("must") or []) if k else []:
            if isinstance(p, dict) and p.get("ko") and p.get("en") and p["ko"] in k["text"] \
                    and not re.search(re.escape(p["en"]), t["text"], re.I):
                findings.append(_f(t, f"en_must:{p['ko']}->{p['en']}", _grade(p.get("grade"), "warn"), t["text"],
                                   "한국어에 용어가 있는데 영어에 짝이 없음"))


def apply_pending(findings: list, rules: dict):
    for f in findings:
        for p in rules.get("allow_pending") or []:
            if not isinstance(p, dict):
                continue
            fl, kt = str(p.get("file", "")), str(p.get("key_or_text", ""))
            if fl and not (f["file"] == fl or f["file"].endswith(fl)):
                continue
            if kt and kt != f["key"] and kt not in f["text"]:
                continue
            f["pending"] = {"decision": p.get("decision", ""), "why": p.get("why", "")}
            break


def lint(texts: list, rules: dict) -> list:
    findings: list = []
    for t in texts:
        check_words(t, rules, findings)
        check_names(t, rules, findings)
    check_english(texts, rules, findings)
    apply_pending(findings, rules)
    return findings


def summarize(findings: list) -> dict:
    live = [f for f in findings if not f["pending"]]
    return {"fail": sum(f["grade"] == "fail" for f in live), "warn": sum(f["grade"] == "warn" for f in live),
            "pending": sum(1 for f in findings if f["pending"])}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="플레이어에게 보이는 글의 낱말 검사")
    ap.add_argument("--rules", default=str(DEFAULT_RULES))
    ap.add_argument("--root", default=str(ROOT), help="검사할 저장소 루트(시험용)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--out", help="결과를 파일로도 저장(_local/ 아래 권장)")
    a = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    rp = Path(a.rules)
    if not rp.is_file():
        print(f"WORDING 규칙 파일 없음: {rp}")
        return 2
    try:
        rules = json.loads(rp.read_text(encoding="utf-8"))
        if not isinstance(rules, dict):
            raise ValueError("최상위가 객체가 아님")
    except (ValueError, OSError) as e:
        print(f"WORDING 규칙 파일을 읽지 못함: {e}")
        return 2
    texts = collect_texts(Path(a.root))
    findings = lint(texts, rules)
    s = summarize(findings)
    result = {"rules_file": str(rp), "texts": len(texts), **s, "findings": findings,
              "not_checked": ["docs/ 의 문서", "비유인지 아닌지의 판정(낱말만 찾음)", "영어 외 언어"]}
    if a.out:
        op = Path(a.out)
        op.parent.mkdir(parents=True, exist_ok=True)
        op.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    if a.json:
        print(json.dumps(result, ensure_ascii=False, indent=1))
    else:
        for f in sorted(findings, key=lambda x: (bool(x["pending"]), x["grade"] != "fail", x["file"], x["line"])):
            tag = "결정대기" if f["pending"] else f["grade"]
            print(f"{f['file']}:{f['line']}  {f['rule']}  {tag}  {f['text'][:80]!r}")
        print(f"WORDING {'FAIL' if s['fail'] else 'PASS'} texts={len(texts)} fail={s['fail']} warn={s['warn']} 결정대기={s['pending']}")
    return 1 if s["fail"] else 0


if __name__ == "__main__":
    sys.exit(main())
