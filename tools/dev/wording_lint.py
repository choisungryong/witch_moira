#!/usr/bin/env python3
"""낱말 검사기: 플레이어에게 보이는 글에서 금지·제한 낱말, 이름 꼴, 이름 글자 수, 영어 용어집을 찾는다.

규칙은 docs/story/wording-rules.json(세계관·스토리 책임자가 관리)에서 읽는다. 이 파일은 규칙을 갖지 않는다.
규칙 파일의 `conventions` 절이 해석의 기준이다(이 파일은 그것을 그대로 따른다).

  python tools/dev/wording_lint.py                         # 검사. 결정 대기가 아닌 fail 이 있으면 종료 1, 규칙 파일이 없거나 못 읽으면 2
  python tools/dev/wording_lint.py --summary               # 마지막 줄에 영문·숫자 요약 한 줄
  python tools/dev/wording_lint.py --json                  # 표준 출력을 JSON 으로
  python tools/dev/wording_lint.py --out=_local/wording/lint.json   # 확장자가 .json 이면 JSON, 아니면 글
  python tools/dev/wording_lint.py --docs                  # scope.docs(문서, 등급 warn)도 본다(기본은 게임 글만)
  python tools/dev/wording_lint.py --rules=tools/dev/test_data/wording-rules.test.json --root=시험용_루트

검사 대상(scope.game_text): chapter1/i18n/ko.po·en.po, chapter1/data/*.json 의 json_fields, chapter1/**/*.gd 의 한글 리터럴, project.godot.
exclude 는 규칙 파일의 것을 따른다(tests/, chapter_items.gd, combat_run.gd 등). 글 모으는 방식은 tools/dev/check_glyphs.py 와 같다
(그 파일의 정규식·풀이 함수를 불러 쓰고, fontTools 가 없어 못 불러오면 같은 정의를 쓴다).
키: ko.po·en.po 는 msgid, 데이터 JSON 은 key_map 으로 만든 키(없으면 data:<파일>:<경로>), .gd 는 code:<경로>.
키가 data:·code: 인 글에는 applies_to 가 없는 banned·restricted 규칙만 건다.
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
DEFAULT_JSON_FIELDS = ["name", "evolved_name", "title", "description", "lore", "slot_names"]


# ---------------------------------------------------------------- 글 맞추기 도우미
def glob_match(rel: str, pat: str) -> bool:
    """경로 글롭. ** 는 폴더를 넘고 * 는 한 폴더 안."""
    out, i = "", 0
    while i < len(pat):
        if pat.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pat.startswith("**", i):
            out += ".*"
            i += 2
        elif pat[i] == "*":
            out += "[^/]*"
            i += 1
        elif pat[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pat[i])
            i += 1
    return re.fullmatch(out, rel) is not None


def key_match(key: str, pats: list) -> bool:
    return any(fnmatch.fnmatchcase(key or "", p) for p in pats)


def expand(applies, groups: dict) -> list:
    out = []
    for a in applies or []:
        out += groups.get(a, []) if a.startswith("@") else [a]
    return out


def is_unkeyed(t: dict) -> bool:
    return t["key"].startswith("data:") or t["key"].startswith("code:")


# ---------------------------------------------------------------- 글 모으기
def _t(file, line, key, text, lang, kind, slot=None):
    return {"file": file, "line": line, "key": key, "text": text, "lang": lang, "kind": kind, "slot": slot}


def parse_po(path: Path, rel: str, lang: str) -> list:
    """msgid(키) → msgstr 글. 줄 번호는 msgstr 가 시작한 줄. 복수형 칸은 줄바꿈으로 이어 붙인다."""
    out, key, segs, state, str_line = [], None, [], None, 0

    def flush():
        if key and segs and "".join(segs).strip():
            out.append(_t(rel, str_line, key, "\n".join(segs), lang, "po"))

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


class KeyMapper:
    """conventions.key_map: 'bases[].name' → 'item.base.<id>.name' 같은 표로 데이터 글의 키를 만든다."""

    def __init__(self, key_map: dict):
        self.key_map = key_map or {}

    def entries(self, rel: str) -> list:
        out = []
        for fpat, table in self.key_map.items():
            if glob_match(rel, fpat):
                out += list(table.items())
        return out

    @staticmethod
    def _match(pat: str, segs: list):
        """pat 과 경로 조각(('k', 이름) 또는 ('i', 번호))이 맞으면 <slot> 값을 돌려준다(없으면 빈 문자열). 안 맞으면 None."""
        parts = []
        for tok in pat.split("."):
            m = re.fullmatch(r"([^\[\]]+)((?:\[\])*)", tok)
            if not m:
                return None
            parts.append(("k", m.group(1)))
            parts += [("i", None)] * (len(m.group(2)) // 2)
        if len(parts) != len(segs):
            return None
        slot = ""
        for (pk, pv), (sk, sv) in zip(parts, segs):
            if pk != sk:
                return None
            if pk == "k":
                if re.fullmatch(r"<\w+>", pv):
                    slot = sv
                elif pv != sv:
                    return None
        return slot

    def key_for(self, rel: str, segs: list, elems: list):
        """segs: [('k',이름)|('i',번호)...], elems: 배열 요소 [(배열 이름, 요소 dict)...]."""
        for pat, tmpl in self.entries(rel):
            slot = self._match(pat, segs)
            if slot is None:
                continue
            vars_ = {"slot": slot}
            if elems:
                last = elems[-1][1]
                vars_["id"] = str(last.get("id", ""))
                vars_["level"] = str(last.get("level", ""))
            for name, el in elems:
                if name == "trees":
                    vars_["tree_id"] = str(el.get("tree_id", el.get("id", "")))
            return re.sub(r"<(\w+)>", lambda m: vars_.get(m.group(1), m.group(0)), tmpl)
        return None


def collect_json(path: Path, rel: str, mapper: KeyMapper, fields: list) -> list:
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines()
    out = []

    def line_of(s: str) -> int:
        needle = json.dumps(s, ensure_ascii=False)
        for i, ln in enumerate(lines, 1):
            if needle in ln:
                return i
        return 0

    def dotted(segs):
        s = ""
        for k, v in segs:
            s += f"[{v}]" if k == "i" else (("." if s else "") + v)
        return s

    def walk2(v, segs, elems):
        """slot_names 의 자식 문자열도 글로 본다."""
        if isinstance(v, dict):
            in_slot = bool(segs) and segs[-1] == ("k", "slot_names")
            for k, x in v.items():
                if in_slot and isinstance(x, str):
                    generic = [("k", s) if t == "k" else ("i", None) for t, s in segs] + [("k", str(k))]
                    key = mapper.key_for(rel, generic, elems)
                    out.append(_t(rel, line_of(x), key or f"data:{Path(rel).name}:{dotted(segs)}.{k}", x, "ko", "json"))
                else:
                    walk2(x, segs + [("k", str(k))], elems)
        elif isinstance(v, list):
            name = segs[-1][1] if segs and segs[-1][0] == "k" else ""
            for i, x in enumerate(v):
                walk2(x, segs + [("i", i)], elems + ([(name, x)] if isinstance(x, dict) else []))
        elif isinstance(v, str):
            leaf = segs[-1][1] if segs and segs[-1][0] == "k" else ""
            if leaf in fields and leaf != "slot_names" and v.strip():
                generic = [("k", s) if t == "k" else ("i", None) for t, s in segs]
                key = mapper.key_for(rel, generic, elems)
                slot = elems[-1][1].get("slot") if elems else None
                out.append(_t(rel, line_of(v), key or f"data:{Path(rel).name}:{dotted(segs)}", v, "ko", "json", slot))

    walk2(json.loads(raw), [], [])
    return out


def collect_code(path: Path, rel: str) -> list:
    out = []
    is_godot = path.suffix == ".godot"
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        st = line.lstrip()
        if st.startswith(";" if is_godot else "#"):
            continue
        for m in STR_RE.finditer(line):
            s = unescape(m.group(1))
            if HANGUL.search(s):
                out.append(_t(rel, n, f"code:{rel}", s, "ko", "code"))
    return out


def collect_texts(root: Path, rules: dict) -> list:
    scope = (rules.get("scope") or {}).get("game_text") or {}
    excl = scope.get("exclude") or []
    fields = scope.get("json_fields") or DEFAULT_JSON_FIELDS
    mapper = KeyMapper((rules.get("conventions") or {}).get("key_map"))

    def skipped(rel):
        return any(glob_match(rel, e) for e in excl)

    out = []
    i18n = root / "chapter1" / "i18n"
    for po, lang in (("ko.po", "ko"), ("en.po", "en")):
        rel = f"chapter1/i18n/{po}"
        if (i18n / po).is_file() and not skipped(rel):
            out += parse_po(i18n / po, rel, lang)
    for js in sorted((root / "chapter1" / "data").glob("*.json")):
        rel = f"chapter1/data/{js.name}"
        if skipped(rel):
            continue
        try:
            out += collect_json(js, rel, mapper, fields)
        except (ValueError, OSError):
            pass
    for gd in sorted((root / "chapter1").rglob("*.gd")):
        rel = gd.relative_to(root).as_posix()
        if not skipped(rel):
            out += collect_code(gd, rel)
    pg = root / "project.godot"
    if pg.is_file() and not skipped("project.godot"):
        out += collect_code(pg, "project.godot")
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


def find_hit(rule: dict, text: str):
    """pattern(정규식)이 있으면 그것으로, 없으면 stems(없으면 word)의 부분 문자열로 찾는다. exceptions 가 덮는 자리는 버린다."""
    protected = _spans(text, rule.get("exceptions") or [])
    if rule.get("pattern"):
        try:
            it = re.finditer(rule["pattern"], text)
        except re.error:
            return None
        for m in it:
            if not _covered((m.start(), m.end()), protected) and m.group(0):
                return m.group(0)
        return None
    for nd in rule.get("stems") or ([rule["word"]] if rule.get("word") else []):
        for m in re.finditer(re.escape(nd), text):
            if not _covered((m.start(), m.end()), protected):
                return m.group(0)
    return None


def _g(rule, default="warn", status=None):
    g = rule.get("grade")
    return g if g in ("fail", "warn") else default


class Linter:
    def __init__(self, rules: dict):
        self.rules = rules
        self.groups = rules.get("groups") or {}
        self.head_status = rules.get("status", "")
        self.findings = []

    def add(self, t, rule_label, word, grade, matched, rule, text_note=""):
        self.findings.append({
            "file": t["file"], "line": t["line"], "key": t["key"], "rule": rule_label, "word": word, "grade": grade,
            "matched": matched, "text": t["text"], "note": rule.get("note", "") if isinstance(rule, dict) else text_note,
            "rule_ref": rule.get("rule", "") if isinstance(rule, dict) else "",
            "status": (rule.get("status") if isinstance(rule, dict) else None) or self.head_status, "pending": None})

    def applies(self, rule: dict, t: dict) -> bool:
        if rule.get("lang", "ko") != t["lang"]:
            return False
        ap = rule.get("applies_to")
        if ap:
            if is_unkeyed(t) or not key_match(t["key"], expand(ap, self.groups)):
                return False
        if rule.get("only_slots") and t.get("slot") not in rule["only_slots"]:
            return False
        if t["key"] in (rule.get("exception_keys") or []):
            return False
        return True

    def words(self, t):
        for section, default in (("banned", "fail"), ("restricted", "warn")):
            for r in self.rules.get(section) or []:
                if not isinstance(r, dict) or not (r.get("word") or r.get("pattern")) or not self.applies(r, t):
                    continue
                hit = find_hit(r, t["text"])
                if hit:
                    self.add(t, f"{section}:{r.get('word', '')}", r.get("word", ""), _g(r, default), hit, r)

    def shapes(self, t):
        if is_unkeyed(t):
            return
        for r in self.rules.get("name_shape") or []:
            if not isinstance(r, dict) or not r.get("pattern") or not self.applies(r, t):
                continue
            hit = find_hit(r, t["text"])
            if hit:
                self.add(t, f"name_shape:{r.get('id', '?')}", r.get("id", ""), _g(r), hit, r)

    def max_chars(self, t):
        mc = self.rules.get("name_max_chars")
        if not isinstance(mc, dict) or is_unkeyed(t) or mc.get("lang", "ko") != t["lang"]:
            return
        limit = None
        for pat, n in (mc.get("by_key_pattern") or {}).items():
            if fnmatch.fnmatchcase(t["key"], pat):
                limit = n
                break
        if limit is None and key_match(t["key"], expand(mc.get("default_applies_to"), self.groups)):
            limit = mc.get("default")
        if not isinstance(limit, int):
            return
        txt = re.sub(r"\s", "", t["text"]) if key_match(t["key"], mc.get("spaces_not_counted") or []) else t["text"]
        if len(txt) > limit:
            grade = "warn" if key_match(t["key"], mc.get("warn_only") or []) else _g(mc, "fail")
            self.add(t, "name_max_chars", "name_max_chars", grade, t["text"], mc,
                     f"{len(txt)}자 > 상한 {limit}자")
            self.findings[-1]["note"] = f"{len(txt)}자 > 상한 {limit}자. " + (mc.get("rule") or "")

    def english(self, texts: list):
        g = self.rules.get("en_glossary")
        if not isinstance(g, dict):
            return
        ko = {t["key"]: t for t in texts if t["lang"] == "ko" and t["kind"] == "po"}
        for t in (x for x in texts if x["lang"] == "en"):
            for w in g.get("banned_en") or []:
                if re.search(r"(?<![A-Za-z])" + re.escape(w) + r"(?![A-Za-z])", t["text"], re.I):
                    self.add(t, f"en_banned:{w}", w, "fail", w, {"rule": g.get("rule", ""), "status": g.get("status", "")}, g.get("note", ""))
            for r in g.get("restricted_en") or []:
                w = r.get("word", "")
                if w and re.search(r"(?<![A-Za-z])" + re.escape(w) + r"(?![A-Za-z])", t["text"], re.I):
                    self.add(t, f"en_restricted:{w}", w, "warn", w, r)
            k = ko.get(t["key"])
            for p in (g.get("must") or []) if k else []:
                if not (isinstance(p, dict) and p.get("ko") and p.get("en")):
                    continue
                if p.get("applies_to") and not key_match(t["key"], expand(p["applies_to"], self.groups)):
                    continue
                if p["ko"] in k["text"] and not re.search(re.escape(p["en"]), t["text"], re.I):
                    self.add(t, f"en_must:{p['ko']}={p['en']}", f"{p['ko']}={p['en']}", "warn", t["text"], p,
                             "한국어에 용어가 있는데 영어에 짝이 없음")

    def structure(self, root: Path):
        for s in self.rules.get("structure") or []:
            f, chk = s.get("file", ""), s.get("check", "")
            try:
                data = json.loads((root / f).read_text(encoding="utf-8"))
                ok = True
                for m in re.finditer(r"len\(([\w.]+)\)\s*==\s*(\d+)", chk):
                    cur = data
                    for part in m.group(1).split("."):
                        cur = cur[part]
                    ok = ok and len(cur) == int(m.group(2))
                if not re.search(r"len\(", chk):
                    continue  # 해석할 수 없는 검사 식은 건너뛴다(보고서에 따로 적는다)
            except (OSError, ValueError, KeyError, TypeError):
                continue
            if not ok:
                self.findings.append({"file": f, "line": 0, "key": "", "rule": f"structure:{s.get('id', '?')}", "word": s.get("id", ""),
                                      "grade": _g(s), "matched": chk, "text": s.get("desc", ""), "note": s.get("note", ""),
                                      "rule_ref": s.get("rule", ""), "status": s.get("status") or self.head_status, "pending": None})

    def run(self, texts: list, root: Path) -> list:
        for t in texts:
            self.words(t)
            self.shapes(t)
            self.max_chars(t)
        self.english(texts)
        self.structure(root)
        return self.findings


def apply_pending(findings: list, rules: dict) -> set:
    """결정 대기에 든 걸림에 표시한다. 쓰인 allow_pending 항목의 번호 집합을 돌려준다(안 쓰인 항목 = 글이 이미 바뀌었거나 규칙이 안 걸림)."""
    used = set()
    for f in findings:
        for idx, p in enumerate(rules.get("allow_pending") or []):
            if not isinstance(p, dict):
                continue
            if not glob_match(f["file"], str(p.get("file", ""))):
                continue
            kt = p.get("key_or_text")
            if kt is not None:
                if f.get("doc"):
                    if kt not in f["text"]:
                        continue
                elif kt != f["key"] and kt != f["text"]:
                    continue
            if p.get("word") and p["word"] != f["word"]:
                continue
            if p.get("text") is not None and p["text"] != f["text"]:
                continue
            f["pending"] = {"decision": p.get("decision", ""), "why": p.get("why", "")}
            used.add(idx)
            break
    return used


def scan_docs(root: Path, rules: dict, linter: "Linter") -> list:
    """scope.docs: 문서 줄을 banned·restricted(applies_to 없음, skip_docs 아님)로만 본다. 등급은 항상 warn."""
    sd = (rules.get("scope") or {}).get("docs") or {}
    inc, exc = sd.get("include") or [], sd.get("exclude") or []
    use = [r for sec in ("banned", "restricted") for r in rules.get(sec) or []
           if isinstance(r, dict) and (r.get("word") or r.get("pattern")) and not r.get("applies_to") and not r.get("skip_docs") and r.get("lang", "ko") == "ko"]
    out = []
    files = {p for pat in inc for p in root.glob(pat)} if inc else set()
    for p in sorted(files):
        rel = p.relative_to(root).as_posix()
        if not p.is_file() or any(glob_match(rel, e) for e in exc):
            continue
        try:
            lines = p.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for n, line in enumerate(lines, 1):
            for r in use:
                hit = find_hit(r, line)
                if hit:
                    linter.add(_t(rel, n, "", line.strip(), "ko", "doc"), f"doc:{r.get('word', '')}", r.get("word", ""), "warn", hit, r)
                    linter.findings[-1]["doc"] = True
                    out.append(linter.findings[-1])
    return out


LAST: dict = {}


def lint(texts: list, rules: dict, root: Path = ROOT, docs: bool = False) -> list:
    lt = Linter(rules)
    lt.run(texts, root)
    if docs:
        scan_docs(root, rules, lt)
    lt.used_pending = apply_pending(lt.findings, rules)
    LAST["used_pending"] = lt.used_pending
    return lt.findings


def summarize(findings: list) -> dict:
    live = [f for f in findings if not f["pending"]]
    return {"fail": sum(f["grade"] == "fail" for f in live), "warn": sum(f["grade"] == "warn" for f in live),
            "pending": sum(1 for f in findings if f["pending"])}


def format_lines(findings: list) -> list:
    out = []
    order = sorted(findings, key=lambda x: (bool(x["pending"]), x["grade"] != "fail", x["file"], x["line"], x["rule"]))
    for f in order:
        tag = "PENDING" if f["pending"] else f["grade"].upper()
        out.append(f"{f['file']}:{f['line']}  [{tag}]  {f['rule']}  key={f['key'] or '-'}  {f['text'][:80]!r}")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="플레이어에게 보이는 글의 낱말 검사")
    ap.add_argument("--rules", default=str(DEFAULT_RULES))
    ap.add_argument("--root", default=str(ROOT), help="검사할 저장소 루트(시험용)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--summary", action="store_true", help="마지막에 영문·숫자 요약 줄을 찍는다")
    ap.add_argument("--docs", action="store_true", help="scope.docs(문서, 등급 warn)도 본다")
    ap.add_argument("--out", help="결과를 파일로도 저장(_local/ 아래 권장). .json 이면 JSON, 아니면 글")
    a = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    rp = Path(a.rules)
    if not rp.is_file():
        print(f"WORDING no rules file: {rp}")
        return 2
    try:
        rules = json.loads(rp.read_text(encoding="utf-8"))
        if not isinstance(rules, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError) as e:
        print(f"WORDING cannot read rules file: {e}")
        return 2
    root = Path(a.root)
    texts = collect_texts(root, rules)
    findings = lint(texts, rules, root, a.docs)
    s = summarize(findings)
    unused = [p for i, p in enumerate(rules.get("allow_pending") or [])
              if i not in LAST.get("used_pending", set()) and (a.docs or not str(p.get("file", "")).startswith(("docs/", ".claude/")))]
    result = {"rules_file": str(rp), "texts": len(texts), **s, "unused_allow_pending": unused, "findings": findings,
              "not_checked": (rules.get("conventions") or {}).get("not_machine_checked", []) + ["비유인지 아닌지의 판정(낱말만 찾음)"]}
    lines = format_lines(findings)
    summary = f"SUMMARY fail={s['fail']} warn={s['warn']} pending={s['pending']} texts={len(texts)} docs={'on' if a.docs else 'off'} exit={1 if s['fail'] else 0}"
    if a.out:
        op = Path(a.out)
        op.parent.mkdir(parents=True, exist_ok=True)
        body = json.dumps(result, ensure_ascii=False, indent=1) if op.suffix == ".json" else "\n".join(lines + [summary])
        op.write_text(body + "\n", encoding="utf-8", newline="\n")
    if a.json:
        print(json.dumps(result, ensure_ascii=False, indent=1))
    else:
        print("\n".join(lines))
        for p in unused:
            print(f"UNUSED allow_pending: {p.get('file')} {p.get('key_or_text')!r} word={p.get('word')}")
        print(f"WORDING {'FAIL' if s['fail'] else 'PASS'} texts={len(texts)} fail={s['fail']} warn={s['warn']} pending={s['pending']}")
    if a.summary:
        print(summary)
    return 1 if s["fail"] else 0


if __name__ == "__main__":
    sys.exit(main())
