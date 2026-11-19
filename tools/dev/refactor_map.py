#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""참조 지도: 구조 리팩토링용 읽기 전용 정적 도구.

res:// 아래 .gd .tscn .tres .gdshader .gdshaderinc .json 의 참조 그래프를 만들어
  - 파일별 "누가 나를 참조하는가"
  - 참조 없는 파일(삭제 후보일 뿐, 단정하지 않는다)
  - 이름__층 메서드의 호출 관계
  - 버전 숫자가 이름에 든 파일
  - 정적으로 못 가른 것(불확실)
를 _local/ 아래에 JSON과 Markdown으로 쓴다. Godot를 돌리지 않고, 아무것도 고치지 않는다.

  python tools/dev/refactor_map.py [--out=_local/refactor-map/]
  python tools/dev/refactor_map.py --rename-check <옛 경로> <새 경로>
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

BLIND_SPOTS = (
    "이 지도가 보지 못하는 것: 변수·문자열 조립으로 만든 경로(\"res://\"+이름), 데이터(JSON) 안의 ID로 고르는 파일, "
    "런타임에 폴더를 훑어 찾는 파일, 문자열 이름 호출의 실제 대상 객체(이름만 대조), 에디터에서 설정한 속성, "
    "저장소 밖 도구가 여는 파일. 그래서 \"참조 없음\"은 \"죽은 코드\"가 아니라 삭제 후보일 뿐이다."
)

CODE_EXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".json"}
SKIP_EXT = {".uid", ".import"}
WEAK_BASENAME_MIN = 4
LAYER_RE = re.compile(r"^(\w+)__(\w+)$")
FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)")
VER_RE = re.compile(r"(?:^|[_\-.])(?:quality|q|ui|input|v|ver)\d+[a-z]?(?=$|[_\-.])", re.I)
DYN_CALL_RE = re.compile(r"\b(call|callv|call_deferred|has_method|Callable|connect|is_connected|Signal|call_group|set_deferred)\b")
DYN_ARG_RE = re.compile(r"\b(has_method|call_deferred|callv|call_group)\(\s*(?!&?\"§)")
PATH_REL_RE = re.compile(r"^(?:chapter1|combat)/[^\s%{}*\"']*\.[A-Za-z0-9]+$")
RES_ANY_RE = re.compile(r"res://[^\s\"'%{}]+")
STRONG_KINDS = {"preload", "load", "extends", "class_name", "ext_resource", "include", "uid",
                "path-string", "path-rel", "json-path"}


# ---------------------------------------------------------------- 파일 수집

def norm(p):
    return p.replace("\\", "/")


def find_root(start):
    d = os.path.abspath(start)
    while True:
        if os.path.exists(os.path.join(d, "project.godot")):
            return d
        up = os.path.dirname(d)
        if up == d:
            return None
        d = up


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
        return f.read()


def collect(root):
    """(files, ignored_dirs, sidecars). files: 상대 경로 집합(.uid/.import 제외)."""
    files, ignored, sidecars = set(), [], defaultdict(list)
    for dp, dns, fns in os.walk(root):
        rel_dir = norm(os.path.relpath(dp, root))
        rel_dir = "" if rel_dir == "." else rel_dir
        keep = []
        for d in sorted(dns):
            if d.startswith("."):
                continue
            if os.path.exists(os.path.join(dp, d, ".gdignore")):
                ignored.append((rel_dir + "/" + d).lstrip("/"))
                continue
            keep.append(d)
        dns[:] = keep
        for fn in sorted(fns):
            rel = (rel_dir + "/" + fn).lstrip("/")
            ext = os.path.splitext(fn)[1].lower()
            if fn == ".gdignore":
                continue
            if ext in SKIP_EXT:
                sidecars[rel[: -len(ext)]].append(rel)
                continue
            files.add(rel)
    return files, ignored, sidecars


# ---------------------------------------------------------------- GDScript 렉서

class Line:
    __slots__ = ("no", "raw", "code", "strs", "indent", "func", "defname", "in_str")

    def __init__(self, no, raw):
        self.no = no
        self.raw = raw
        self.code = ""
        self.strs = []
        self.indent = 0
        self.func = None
        self.defname = None
        self.in_str = False


def lex_gd(text):
    out, state = [], None
    for no, raw in enumerate(text.split("\n"), 1):
        raw = raw.rstrip("\r")
        L = Line(no, raw)
        L.in_str = state is not None
        ws = len(raw) - len(raw.lstrip(" \t"))
        L.indent = raw[:ws].count("\t") * 4 + raw[:ws].count(" ")
        code, i, n = [], 0, len(raw)
        while i < n:
            if state:
                j = raw.find(state, i)
                if j < 0:
                    i = n
                    break
                i = j + 3
                state = None
                continue
            c = raw[i]
            if c == "#":
                break
            if c in "\"'":
                if raw.startswith(c * 3, i):
                    j = raw.find(c * 3, i + 3)
                    code.append('""')
                    if j < 0:
                        state = c * 3
                        i = n
                        break
                    i = j + 3
                    continue
                j, buf = i + 1, []
                while j < n:
                    if raw[j] == "\\":
                        buf.append(raw[j:j + 2])
                        j += 2
                        continue
                    if raw[j] == c:
                        break
                    buf.append(raw[j])
                    j += 1
                L.strs.append("".join(buf))
                code.append('"§%d§"' % (len(L.strs) - 1))
                i = j + 1
                continue
            code.append(c)
            i += 1
        L.code = "".join(code)
        out.append(L)
    cur, cur_indent = None, -1
    for L in out:
        if L.in_str:
            L.func = cur
            continue
        s = L.code.strip()
        if not s:
            L.func = cur
            continue
        m = FUNC_RE.match(L.code)
        if m:
            cur, cur_indent = m.group(1), L.indent
            L.func, L.defname = cur, cur
            continue
        if cur is not None and L.indent <= cur_indent and s[0] not in ")]}":
            cur = None
        L.func = cur
    return out


def expand(L, s):
    """코드 조각의 "§n§" 자리표를 원래 문자열로."""
    return re.sub(r'"§(\d+)§"', lambda m: '"' + L.strs[int(m.group(1))] + '"', s)


# ---------------------------------------------------------------- 그래프

class Graph:
    def __init__(self, root):
        self.root = root
        self.files, self.ignored, self.sidecars = collect(root)
        self.by_base = defaultdict(list)
        for f in self.files:
            self.by_base[os.path.basename(f)].append(f)
        self.uid = {}
        self.edges = {}          # (src,dst,kind) -> dict
        self.dangling = []
        self.uncertain = []
        self.prefixes = []       # (src, line, dir_prefix)
        self.roots = defaultdict(list)
        self.class_names = {}
        self.extends = {}
        self.gd = {}             # path -> [Line]
        self.string_mentions = defaultdict(list)   # 이름 -> [(file,line,dyn)]
        self.layer_methods = {}
        self.func_defs = defaultdict(set)
        self._build_uid()
        self._scan()
        self._roots()
        self._class_refs()
        self._layers()

    # -- 유틸
    def in_ignored(self, rel):
        return any(rel == d or rel.startswith(d + "/") for d in self.ignored)

    def _build_uid(self):
        rx = re.compile(r'uid="(uid://[^"]+)"')
        for f in self.files:
            ext = os.path.splitext(f)[1].lower()
            sc = self.sidecars.get(f, [])
            for s in sc:
                try:
                    t = read_text(os.path.join(self.root, s))
                except OSError:
                    continue
                m = rx.search(t) if s.endswith(".import") else re.search(r"uid://\S+", t)
                if m:
                    self.uid[m.group(1) if s.endswith(".import") else m.group(0)] = f
            if ext in (".tscn", ".tres"):
                head = read_text(os.path.join(self.root, f)).split("\n", 1)[0]
                m = rx.search(head)
                if m:
                    self.uid[m.group(1)] = f

    def resolve(self, lit, src, kind):
        """리터럴을 상대 경로로. 못 찾으면 None."""
        if lit.startswith("uid://"):
            return self.uid.get(lit)
        if lit.startswith("res://"):
            p = norm(os.path.normpath(lit[6:]))
        elif kind == "include":
            p = norm(os.path.normpath(os.path.join(os.path.dirname(src), lit)))
        else:
            p = norm(os.path.normpath(lit))
        return p if p in self.files else None

    def add_edge(self, src, lit, kind, line, weak=False, alias=None, alias_uses=None):
        dst = self.resolve(lit, src, kind)
        if dst is None:
            plausible = (lit.startswith("res://") or lit.startswith("uid://") or kind == "include")
            tail = lit.rstrip("/")
            if (plausible and not lit.endswith("/") and not re.search(r"[%{}*]|\.\./", lit)
                    and re.search(r"\.\w{1,12}$", tail)
                    and not self.in_ignored(norm(os.path.normpath(lit[6:])) if lit.startswith("res://") else "")):
                self.dangling.append({"from": src, "line": line, "kind": kind, "literal": lit})
            return
        if dst == src:
            return
        k = (src, dst, kind)
        e = self.edges.get(k)
        if e is None:
            e = {"from": src, "to": dst, "kind": kind, "weak": weak, "lines": [], "literal": lit}
            self.edges[k] = e
        if line not in e["lines"]:
            e["lines"].append(line)
        if alias:
            e["alias"], e["alias_uses"] = alias, alias_uses

    def uncertain_add(self, src, line, kind, text):
        self.uncertain.append({"file": src, "line": line, "kind": kind, "text": text.strip()[:160]})

    # -- 스캔
    def _scan(self):
        for f in sorted(self.files):
            ext = os.path.splitext(f)[1].lower()
            if ext not in CODE_EXT:
                continue
            text = read_text(os.path.join(self.root, f))
            if ext == ".gd":
                self._scan_gd(f, text)
            elif ext in (".tscn", ".tres"):
                self._scan_tscn(f, text)
            elif ext in (".gdshader", ".gdshaderinc"):
                self._scan_shader(f, text)
            elif ext == ".json":
                self._scan_json(f, text)

    def _scan_json(self, f, text):
        for i, line in enumerate(text.split("\n"), 1):
            for m in re.finditer(r'"(res://[^"\s]+|(?:chapter1|combat)/[^"\s]+)"', line):
                lit = m.group(1)
                if lit.endswith("/"):
                    continue
                if re.search(r"\.\w+$", lit):
                    self.add_edge(f, lit, "json-path", i)

    def _scan_shader(self, f, text):
        for i, line in enumerate(text.split("\n"), 1):
            s = re.split(r"(?<!:)//", line, maxsplit=1)[0]
            m = re.match(r'\s*#include\s+"([^"]+)"', s)
            if m:
                self.add_edge(f, m.group(1), "include", i)
            for m in RES_ANY_RE.finditer(s):
                self.add_edge(f, m.group(0), "path-string", i)

    def _scan_tscn(self, f, text):
        for i, line in enumerate(text.split("\n"), 1):
            if line.startswith("[ext_resource"):
                pm = re.search(r'path="([^"]+)"', line)
                um = re.search(r'uid="(uid://[^"]+)"', line)
                if pm:
                    self.add_edge(f, pm.group(1), "ext_resource", i)
                elif um:
                    self.add_edge(f, um.group(1), "uid", i)
                continue
            m = re.match(r'\[connection signal="\w+" from="[^"]*" to="[^"]*" method="(\w+)"', line)
            if m:
                self.string_mentions[m.group(1)].append((f, i, True))
                continue
            for m in RES_ANY_RE.finditer(line):
                self.add_edge(f, m.group(0), "path-string", i)

    def _scan_gd(self, f, text):
        lines = lex_gd(text)
        self.gd[f] = lines
        # 별칭 사용 횟수를 위한 식별자 집합
        for L in lines:
            if L.defname:
                self.func_defs[f].add(L.defname)
            if L.in_str and not L.code.strip():
                continue
            m = re.match(r"\s*class_name\s+(\w+)", L.code)
            if m:
                self.class_names[m.group(1)] = f
            m = re.match(r"\s*extends\s+(.+?)\s*$", L.code)
            if m and f not in self.extends:
                arg = m.group(1)
                sm = re.fullmatch(r'"§(\d+)§"', arg)
                if sm:
                    lit = L.strs[int(sm.group(1))]
                    self.extends[f] = lit
                    self.add_edge(f, lit, "extends", L.no)
                else:
                    self.extends[f] = arg.split(".")[0].strip(":")
            # 문자열 이름(층 메서드 이름 대조용)
            dyn = bool(DYN_CALL_RE.search(L.code))
            for s in L.strs:
                if s and len(s) < 80 and re.fullmatch(r"[A-Za-z_]\w*", s):
                    self.string_mentions[s].append((f, L.no, dyn))
                if re.fullmatch(r"[A-Za-z_]\w*__", s):
                    self.uncertain_add(f, L.no, "층 메서드 이름 조립 의심", expand(L, L.code))
            if DYN_ARG_RE.search(L.code):
                self.uncertain_add(f, L.no, "동적 메서드 이름 호출", expand(L, L.code))
            if re.search(r"\bCallable\(\s*[\w.]+\s*,\s*(?!&?\"§)", L.code):
                self.uncertain_add(f, L.no, "동적 메서드 이름 호출", expand(L, L.code))
            if re.search(r"DirAccess\.(open|get_files_at|get_directories_at)\(|list_dir_begin", L.code):
                self.uncertain_add(f, L.no, "폴더 훑기(DirAccess)", expand(L, L.code))
                for s in L.strs:
                    pre = self._dir_prefix(s)
                    if pre:
                        self.prefixes.append((f, L.no, pre))
            # 로드 대상이 리터럴이 아닌 load()
            if re.search(r"(?<![\w.])load\(\s*(?!\"§)|ResourceLoader\.load\(\s*(?!\"§)", L.code):
                self.uncertain_add(f, L.no, "load(변수)", expand(L, L.code))
            # 별칭 상수
            alias = None
            am = re.match(r"\s*(?:const|var)\s+(\w+)\s*(?::[^=]*)?:?=\s*(?:pre)?load\(\s*\"§(\d+)§\"", L.code)
            if am:
                alias = am.group(1)
            # 문자열 순회(extends 줄은 위에서 이미 처리)
            for m in ([] if re.match(r"\s*extends\s", L.code) else re.finditer(r'"§(\d+)§"', L.code)):
                s = L.strs[int(m.group(1))]
                before, after = L.code[:m.start()], L.code[m.end():]
                ctx_pre = re.search(r"(\w+)\(\s*$", before)
                fn = ctx_pre.group(1) if ctx_pre else ""
                concat = bool(re.match(r"\s*[+%]", after)) or bool(re.search(r"[+%]\s*$", before))
                tmpl = bool(re.search(r"%[sdif]|\{\w*\}", s))
                if s.startswith("res://") or s.startswith("uid://"):
                    if concat or tmpl or s.endswith("/") or s in ("res://", "uid://"):
                        self.uncertain_add(f, L.no, "동적 경로 조립", expand(L, L.code))
                        pre = self._dir_prefix(s)
                        if pre:
                            self.prefixes.append((f, L.no, pre))
                        continue
                    if re.fullmatch(r"(?:res|uid)://\S+", s):
                        if fn == "preload":
                            kind = "preload"
                        elif fn == "load" or fn.endswith("load"):
                            kind = "load"
                        else:
                            kind = "path-string"
                        self.add_edge(f, s, kind, L.no,
                                      alias=alias if kind in ("preload", "load") else None,
                                      alias_uses=self._alias_uses(lines, alias, L.no) if alias else None)
                    else:
                        for mm in RES_ANY_RE.finditer(s):
                            self.add_edge(f, mm.group(0), "path-string", L.no, weak=True)
                elif s.startswith(("chapter1/", "combat/")):
                    if concat or tmpl or s.endswith("/"):
                        self.uncertain_add(f, L.no, "동적 경로 조립", expand(L, L.code))
                        pre = self._dir_prefix(s)
                        if pre:
                            self.prefixes.append((f, L.no, pre))
                    elif PATH_REL_RE.match(s):
                        self.add_edge(f, s, "path-rel", L.no)
                else:
                    self._weak_basename(f, L.no, s)

    def _dir_prefix(self, s):
        p = s[6:] if s.startswith("res://") else s
        p = re.split(r"[%{]", p)[0]
        if "/" not in p:
            return None
        p = p[: p.rfind("/") + 1]
        return p if p.strip("/") else None

    def _alias_uses(self, lines, alias, defline):
        rx = re.compile(r"\b%s\b" % re.escape(alias))
        return sum(len(rx.findall(L.code)) for L in lines if L.no != defline and not L.in_str)

    def _weak_basename(self, f, line, s):
        if not s or " " in s or len(s) > 120:
            return
        base = s.rsplit("/", 1)[-1]
        if len(base) < WEAK_BASENAME_MIN or "." not in base:
            return
        if base not in self.by_base:
            return
        if "/" in s and not any(t.endswith(s.lstrip("/")) for t in self.by_base[base]):
            return
        for t in self.by_base[base]:
            if t != f:
                k = (f, t, "basename")
                e = self.edges.setdefault(k, {"from": f, "to": t, "kind": "basename", "weak": True,
                                              "lines": [], "literal": s})
                if line not in e["lines"]:
                    e["lines"].append(line)
                if len(self.by_base[base]) > 1:
                    e["ambiguous"] = True

    # -- 뿌리
    def _roots(self):
        pg = os.path.join(self.root, "project.godot")
        if os.path.exists(pg):
            text = read_text(pg)
            section = ""
            for line in text.split("\n"):
                line = line.rstrip("\r")
                m = re.match(r"\[(\w+)\]", line)
                if m:
                    section = m.group(1)
                    continue
                for r in RES_ANY_RE.finditer(line):
                    p = r.group(0)[6:].lstrip("*")
                    why = "project.godot"
                    if line.startswith("run/main_scene"):
                        why = "project.godot 주 장면"
                    elif section == "autoload":
                        why = "project.godot 자동 로드"
                    self._root_add(p, why)
        ex = os.path.join(self.root, "export_presets.cfg")
        if os.path.exists(ex):
            for r in RES_ANY_RE.finditer(read_text(ex)):
                self._root_add(r.group(0)[6:], "export_presets.cfg")
        for f in sorted(self.files):
            if f.startswith("chapter1/tests/"):
                self.roots[f].append("tests/ 폴더")
        tdir = os.path.join(self.root, "tools")
        for dp, dns, fns in os.walk(tdir):
            dns[:] = sorted(d for d in dns if not d.startswith("."))
            for fn in sorted(fns):
                if not fn.endswith(".py"):
                    continue
                rel = norm(os.path.relpath(os.path.join(dp, fn), self.root))
                text = read_text(os.path.join(dp, fn))
                for m in re.finditer(r"res://([\w./\-]+\.\w+)|((?:chapter1|combat)/[\w./\-]+\.\w+)", text):
                    self._root_add(m.group(1) or m.group(2), "tools: " + rel)

    def _root_add(self, p, why):
        p = norm(os.path.normpath(p))
        if p in self.files and why not in self.roots[p]:
            self.roots[p].append(why)

    def _class_refs(self):
        for name, owner in self.class_names.items():
            rx = re.compile(r"\b%s\b" % re.escape(name))
            for f, lines in self.gd.items():
                if f == owner:
                    continue
                hit = [L.no for L in lines if not L.in_str and rx.search(L.code)
                       and not re.match(r"\s*class_name\s", L.code)]
                if hit:
                    k = (f, owner, "class_name")
                    self.edges[k] = {"from": f, "to": owner, "kind": "class_name", "weak": False,
                                     "lines": hit[:20], "literal": name}
        for f, ex in self.extends.items():
            if ex in self.class_names and self.class_names[ex] != f:
                k = (f, self.class_names[ex], "extends")
                self.edges.setdefault(k, {"from": f, "to": self.class_names[ex], "kind": "extends",
                                          "weak": False, "lines": [1], "literal": ex})

    # -- 층 메서드
    def _layers(self):
        defs = {}
        for f, lines in self.gd.items():
            for L in lines:
                if L.defname:
                    m = LAYER_RE.match(L.defname)
                    if m:
                        defs[(f, L.defname)] = {"file": f, "name": L.defname, "base": m.group(1),
                                                "suffix": m.group(2), "line": L.no, "sites": [], "ambiguous": False}
        names = defaultdict(list)
        for (f, n) in defs:
            names[n].append(f)
        for f, lines in self.gd.items():
            for L in lines:
                if L.in_str or not L.code.strip():
                    continue
                for m in re.finditer(r"[A-Za-z_]\w*", L.code):
                    n = m.group(0)
                    if n not in names:
                        continue
                    if L.defname == n and re.match(r"\s*(?:static\s+)?func\s+" + re.escape(n) + r"\b", L.code):
                        continue
                    before = L.code[:m.start()].rstrip()
                    attr = before.endswith(".") and not re.search(r"\b(self|super)\.$", before)
                    after = L.code[m.end():].lstrip()
                    kind = "call" if after.startswith("(") else "ref"
                    if not attr and (f, n) in defs:
                        targets, amb = [(f, n)], False
                    else:
                        targets = [(g, n) for g in names[n]]
                        amb = len(targets) > 1 or attr
                    for t in targets:
                        defs[t]["sites"].append({"file": f, "line": L.no, "func": L.func, "kind": kind,
                                                 "ambiguous": amb})
        # 도달 가능성(비층 함수·최상위 코드에서 시작)
        alive = set()
        edges = defaultdict(set)
        for key, d in defs.items():
            for s in d["sites"]:
                caller = (s["file"], s["func"])
                if s["func"] is not None and caller in defs:
                    edges[caller].add(key)
                else:
                    alive.add(key)
            if self.string_mentions.get(d["name"]):
                alive.add(key)
        stack = list(alive)
        while stack:
            k = stack.pop()
            for t in edges.get(k, ()):
                if t not in alive:
                    alive.add(t)
                    stack.append(t)
        for key, d in defs.items():
            n = len(d["sites"])
            d["category"] = "none" if n == 0 else ("single" if n == 1 else "multi")
            d["string_mentions"] = [{"file": a, "line": b, "dyn_call_line": c}
                                    for a, b, c in self.string_mentions.get(d["name"], [])]
            d["reachable"] = key in alive
            d["fold_candidate"] = d["category"] == "single" and not d["string_mentions"]
            c = d["sites"][0] if n == 1 else None
            d["single_caller_is_layer_same_base"] = bool(
                c and c["func"] and LAYER_RE.match(c["func"]) and
                LAYER_RE.match(c["func"]).group(1) == d["base"] and c["file"] == d["file"])
        self.layer_methods = defs

    # -- 질의
    def incoming(self):
        inc = defaultdict(list)
        for e in self.edges.values():
            inc[e["to"]].append(e)
        return inc


# ---------------------------------------------------------------- 보고서

def build_report(g):
    inc = g.incoming()
    out_edges = defaultdict(list)
    for e in g.edges.values():
        out_edges[e["from"]].append(e)
    # 뿌리에서 도달
    seen = set(g.roots)
    stack = list(seen)
    while stack:
        n = stack.pop()
        for e in out_edges.get(n, ()):
            if e["to"] not in seen:
                seen.add(e["to"])
                stack.append(e["to"])
    prefixes = sorted({p for _, _, p in g.prefixes})

    def under_prefix(f):
        return [p for p in prefixes if f.startswith(p)]

    files = {}
    unref, unref_assets, unreachable, tests_only, weak_only = [], [], [], [], []
    for f in sorted(g.files):
        ext = os.path.splitext(f)[1].lower()
        is_code = ext in CODE_EXT
        refs = sorted(inc.get(f, []), key=lambda e: (e["from"], e["kind"]))
        files[f] = {
            "kind": "code" if is_code else "asset",
            "root_reasons": g.roots.get(f, []),
            "extends": g.extends.get(f),
            "referrers": [{"from": e["from"], "kind": e["kind"], "weak": e["weak"], "lines": e["lines"][:6],
                           **({"alias": e["alias"], "alias_uses": e["alias_uses"]} if "alias" in e else {}),
                           **({"ambiguous": True} if e.get("ambiguous") else {})} for e in refs],
            "referrer_count": len({e["from"] for e in refs}),
        }
        if f in g.roots:
            continue
        mp = under_prefix(f)
        if not refs:
            rec = {"file": f, "maybe_dynamic_prefix": mp}
            (unref if is_code else unref_assets).append(rec)
        else:
            if f not in seen and is_code:
                unreachable.append({"file": f, "referrers": sorted({e["from"] for e in refs}),
                                    "maybe_dynamic_prefix": mp})
            srcs = {e["from"] for e in refs}
            if all(s.startswith("chapter1/tests/") for s in srcs) and not f.startswith("chapter1/tests/"):
                tests_only.append({"file": f, "referrers": sorted(srcs)})
            if all(e["weak"] for e in refs):
                weak_only.append({"file": f, "referrers": sorted(srcs)})
    version = []
    for f in sorted(g.files):
        parts = f.split("/")
        hit = []
        for i, p in enumerate(parts):
            stem = p if i < len(parts) - 1 else os.path.splitext(p)[0]
            if VER_RE.search(stem):
                hit.append(stem)
        if hit:
            version.append({"file": f, "tokens": hit, "kind": files[f]["kind"],
                            "referrer_count": files[f]["referrer_count"],
                            "referrers": sorted({r["from"] for r in files[f]["referrers"]})[:6]})
    layers = sorted(g.layer_methods.values(), key=lambda d: (d["file"], d["line"]))
    chains = defaultdict(list)
    for d in layers:
        chains[(d["file"], d["base"])].append(d["name"])
    lc = {"none": 0, "single": 0, "multi": 0}
    for d in layers:
        lc[d["category"]] += 1
    summary = {
        "layer_methods": len(layers),
        "layer_files": len({d["file"] for d in layers}),
        "layer_chains": len(chains),
        "layer_single_caller": lc["single"],
        "layer_single_caller_fold_candidates": sum(1 for d in layers if d["fold_candidate"]),
        "layer_single_caller_super_chain": sum(1 for d in layers if d["single_caller_is_layer_same_base"]),
        "layer_multi_caller": lc["multi"],
        "layer_no_static_caller": lc["none"],
        "layer_with_string_mention": sum(1 for d in layers if d["string_mentions"]),
        "layer_unreachable": sum(1 for d in layers if not d["reachable"]),
        "unreferenced_code_files": len(unref),
        "unreachable_from_roots_code_files": len(unreachable),
        "only_tests_reference": len(tests_only),
        "weak_only_reference": len(weak_only),
        "unreferenced_assets": len(unref_assets),
        "version_named_files": len(version),
        "version_named_code_files": sum(1 for v in version if v["kind"] == "code"),
        "uncertain": len(g.uncertain),
        "dangling_references": len(g.dangling),
        "files_scanned": len(g.files),
        "code_files_scanned": sum(1 for v in files.values() if v["kind"] == "code"),
        "edges": len(g.edges),
    }
    summary_line = ("요약: 남은 층 메서드 %d개(%d파일, 사슬 %d), 참조 없는 코드 파일 %d개(자산 %d개), 뿌리에서 도달 못 하는 코드 파일 %d개, "
                    "버전 숫자 이름 %d개, 불확실 %d건" % (
                        summary["layer_methods"], summary["layer_files"], summary["layer_chains"],
                        summary["unreferenced_code_files"], summary["unreferenced_assets"],
                        summary["unreachable_from_roots_code_files"],
                        summary["version_named_files"], summary["uncertain"]))
    return {
        "blind_spots": BLIND_SPOTS,
        "summary_line": summary_line,
        "summary": summary,
        "roots": {k: v for k, v in sorted(g.roots.items())},
        "ignored_dirs": sorted(g.ignored),
        "files": files,
        "unreferenced": unref,
        "unreferenced_assets": unref_assets,
        "unreachable_from_roots": unreachable,
        "only_tests_reference": tests_only,
        "weak_only_reference": weak_only,
        "version_named": version,
        "layer_methods": [{k: v for k, v in d.items()} for d in layers],
        "layer_chains": [{"file": f, "base": b, "layers": ns} for (f, b), ns in sorted(chains.items())],
        "uncertain": g.uncertain,
        "dynamic_prefixes": [{"file": a, "line": b, "prefix": c} for a, b, c in sorted(set(g.prefixes))],
        "dangling_references": g.dangling,
    }


def short_site(s):
    return "%s:%d(%s)" % (s["file"].split("/")[-1], s["line"], s["func"] or "최상위")


def render_md(rep):
    L = []
    a = L.append
    a(rep["blind_spots"])
    a("")
    a("# 참조 지도")
    a("")
    a(rep["summary_line"])
    a("")
    a("읽기 전용 정적 지도다. 삭제·이름 바꾸기·접기는 하지 않았고, 아래 후보는 근거 목록일 뿐이다.")
    a("")
    S = rep["summary"]
    a("## 수치")
    a("")
    for k, v in S.items():
        a("- %s: %s" % (k, v))
    a("")
    a("## 뿌리(진입점)")
    a("")
    for f, why in rep["roots"].items():
        if f.startswith("chapter1/tests/"):
            continue
        a("- `%s` — %s" % (f, ", ".join(why)))
    nt = sum(1 for f in rep["roots"] if f.startswith("chapter1/tests/"))
    a("- chapter1/tests/ 아래 %d개 파일(모두 뿌리)" % nt)
    a("")
    a("## 참조 없는 코드 파일(삭제 후보, 단정 아님)")
    a("")
    for r in rep["unreferenced"]:
        extra = ("  [동적 접두 아래: %s]" % ", ".join(r["maybe_dynamic_prefix"])) if r["maybe_dynamic_prefix"] else ""
        a("- `%s`%s" % (r["file"], extra))
    if not rep["unreferenced"]:
        a("- (없음)")
    a("")
    a("## 뿌리에서 도달 못 하는 코드 파일(참조자가 있어도 모두 도달 불가한 쪽)")
    a("")
    for r in rep["unreachable_from_roots"]:
        a("- `%s` ← %s" % (r["file"], ", ".join("`%s`" % x for x in r["referrers"])))
    if not rep["unreachable_from_roots"]:
        a("- (없음)")
    a("")
    a("## 참조자가 tests/ 뿐인 파일")
    a("")
    for r in rep["only_tests_reference"]:
        a("- `%s` ← %s" % (r["file"], ", ".join("`%s`" % x for x in r["referrers"])))
    if not rep["only_tests_reference"]:
        a("- (없음)")
    a("")
    a("## 약한 참조(이름 일치 등)만 있는 파일")
    a("")
    for r in rep["weak_only_reference"]:
        a("- `%s` ← %s" % (r["file"], ", ".join("`%s`" % x for x in r["referrers"])))
    if not rep["weak_only_reference"]:
        a("- (없음)")
    a("")
    a("## 참조 없는 자산(%d개, 전체는 JSON)" % len(rep["unreferenced_assets"]))
    a("")
    by = defaultdict(int)
    for r in rep["unreferenced_assets"]:
        d = "/".join(r["file"].split("/")[:3])
        by[d] += 1
    for d, n in sorted(by.items(), key=lambda x: -x[1])[:25]:
        a("- %s: %d" % (d, n))
    a("")
    a("## 이름에 버전 숫자가 든 파일·폴더")
    a("")
    a("| 파일 | 참조자 수 | 참조자(최대 6) |")
    a("|---|---|---|")
    for v in rep["version_named"]:
        if v["kind"] != "code":
            continue
        a("| `%s` | %d | %s |" % (v["file"], v["referrer_count"], ", ".join(x.split("/")[-1] for x in v["referrers"])))
    na = sum(1 for v in rep["version_named"] if v["kind"] != "code")
    a("")
    a("(자산 %d개는 JSON의 version_named에)" % na)
    a("")
    a("## 이름__층 메서드")
    a("")
    cats = {"single": "호출 한 곳", "none": "정적 호출 없음", "multi": "여러 곳"}
    by_file = defaultdict(list)
    for d in rep["layer_methods"]:
        by_file[d["file"]].append(d)
    for f, ds in by_file.items():
        a("### `%s` (%d개)" % (f, len(ds)))
        a("")
        for d in ds:
            sites = ", ".join(short_site(s) for s in d["sites"][:4]) + (" 외" if len(d["sites"]) > 4 else "")
            flags = []
            if d["fold_candidate"]:
                flags.append("접어 넣기 후보")
            if d["string_mentions"]:
                flags.append("문자열 이름 언급 %d건%s" % (len(d["string_mentions"]),
                             "(동적 호출 줄 있음)" if any(m["dyn_call_line"] for m in d["string_mentions"]) else ""))
            if not d["reachable"]:
                flags.append("비층 함수에서 도달 불가")
            if d["single_caller_is_layer_same_base"]:
                flags.append("super 사슬")
            a("- L%d `%s` — %s%s%s" % (d["line"], d["name"], cats[d["category"]],
                                      (" ← " + sites) if sites else "",
                                      ("  [" + ", ".join(flags) + "]") if flags else ""))
        a("")
    a("## 불확실(정적으로 못 가른 것) %d건" % len(rep["uncertain"]))
    a("")
    kinds = defaultdict(list)
    for u in rep["uncertain"]:
        kinds[u["kind"]].append(u)
    for k, us in sorted(kinds.items()):
        a("### %s (%d건)" % (k, len(us)))
        a("")
        for u in us[:60]:
            a("- `%s:%d` `%s`" % (u["file"], u["line"], u["text"].replace("`", "'")))
        if len(us) > 60:
            a("- … %d건 더(JSON)" % (len(us) - 60))
        a("")
    a("## 깨진 참조(대상 파일이 없는 경로 리터럴) %d건" % len(rep["dangling_references"]))
    a("")
    for d in rep["dangling_references"][:80]:
        a("- `%s:%d` %s `%s`" % (d["from"], d["line"], d["kind"], d["literal"]))
    a("")
    a("## 파일별 참조자(코드 파일)")
    a("")
    for f, v in rep["files"].items():
        if v["kind"] != "code":
            continue
        rs = v["referrers"]
        head = "- `%s` — %d" % (f, v["referrer_count"])
        if v["root_reasons"]:
            head += " [뿌리: %s]" % ", ".join(v["root_reasons"][:2])
        if rs:
            head += ": " + ", ".join("%s(%s%s)" % (r["from"].split("/")[-1], r["kind"],
                                                    ",별칭미사용" if r.get("alias_uses") == 0 else "")
                                     for r in rs[:8]) + (" …" if len(rs) > 8 else "")
        a(head)
    a("")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- 이름 바꾸기 점검

def rename_check(g, old, new):
    old, new = norm(old), norm(new)
    for pre in ("res://",):
        if old.startswith(pre):
            old = old[len(pre):]
        if new.startswith(pre):
            new = new[len(pre):]
    old, new = old.strip("/"), new.strip("/")
    is_dir = old not in g.files and any(f.startswith(old + "/") for f in g.files)
    targets = [old] if old in g.files else sorted(f for f in g.files if f.startswith(old + "/"))
    res = {"old": old, "new": new, "is_dir": is_dir, "targets": targets, "edits": [], "notes": [], "warnings": [],
           "sidecars": [], "text_mentions": [], "dynamic_prefix": []}
    if not targets:
        res["warnings"].append("옛 경로가 지도의 파일 집합에 없다(오타이거나 .gdignore 폴더 안)")
        return res

    def newpath(t):
        return new if not is_dir else new + t[len(old):]

    for t in targets:
        n = newpath(t)
        if n in g.files:
            res["warnings"].append("새 경로가 이미 있다: " + n)
        if g.in_ignored(n):
            res["warnings"].append(".gdignore 폴더 안으로 옮기는 것: " + n)
        if os.path.splitext(n)[1].lower() != os.path.splitext(t)[1].lower():
            res["warnings"].append("확장자가 바뀐다: %s -> %s" % (t, n))
        res["sidecars"] += [{"move": s, "to": newpath(t) + s[len(t):]} for s in g.sidecars.get(t, [])]
    tset = set(targets)
    for e in sorted(g.edges.values(), key=lambda e: (e["from"], e["lines"][0])):
        if e["to"] not in tset or e["from"] in tset and is_dir and False:
            continue
        t = e["to"]
        n = newpath(t)
        lit = e["literal"]
        kind = e["kind"]
        rec = {"in": e["from"], "lines": e["lines"], "kind": kind, "weak": e["weak"], "literal": lit}
        if kind in ("preload", "load", "ext_resource", "path-string", "extends", "json-path", "path-rel", "include"):
            if lit.startswith("uid://"):
                rec["edit"] = "고칠 필요 없음(uid 참조, .uid 사이드카를 같이 옮길 때)"
            elif lit.startswith("res://"):
                rec["edit"] = "%s -> res://%s" % (lit, n)
            elif kind == "include":
                rec["edit"] = "%s -> %s" % (lit, norm(os.path.relpath(n, os.path.dirname(e["from"]))))
            else:
                rec["edit"] = "%s -> %s" % (lit, n)
            if e["from"] in tset:
                rec["note"] = "참조하는 파일도 같이 옮겨진다(상대 경로 리터럴이면 다시 확인)"
        elif kind == "basename":
            changed = os.path.basename(t) != os.path.basename(n)
            rec["edit"] = ("이름이 바뀌므로 문자열 \"%s\" 수정 필요" % lit) if changed or "/" in lit else "기본 이름이 같아 대개 고칠 필요 없음(확인)"
            if e.get("ambiguous"):
                rec["note"] = "같은 기본 이름의 파일이 여럿이라 어느 것을 가리키는지 불분명"
        elif kind == "class_name":
            rec["edit"] = "고칠 필요 없음(class_name은 그대로)"
        res["edits"].append(rec)
    for pre in sorted({p for _, _, p in g.prefixes}):
        for t in targets:
            if t.startswith(pre) or newpath(t).startswith(pre):
                if os.path.dirname(newpath(t)) != os.path.dirname(t) or True:
                    res["dynamic_prefix"].append({"prefix": pre, "file": t,
                        "note": "동적 경로 접두 아래라 코드가 이름 조립으로 찾을 수 있다. 옮긴 뒤 이 접두 밖으로 나가면 못 찾는다"
                                if not newpath(t).startswith(pre) else "새 경로도 같은 접두 아래"})
    for r in g.roots:
        if r in tset:
            res["notes"].append("뿌리 참조: %s — %s" % (r, ", ".join(g.roots[r])))
    pg = ("project.godot", "export_presets.cfg")
    # 글 언급(그래프 밖): 문서와 도구
    pats = []
    for t in targets:
        pats += [t, "res://" + t]
    scan_dirs = ["docs", "tools", ".claude"]
    cand = [p for p in pg + ("CLAUDE.md", "AGENTS.md") if os.path.exists(os.path.join(g.root, p))]
    for sd in scan_dirs:
        for dp, dns, fns in os.walk(os.path.join(g.root, sd)):
            dns[:] = sorted(d for d in dns if not d.startswith(".") or sd == ".claude" and d == "agents")
            for fn in sorted(fns):
                if fn.endswith((".md", ".py", ".txt", ".cfg", ".json", ".toml")):
                    cand.append(norm(os.path.relpath(os.path.join(dp, fn), g.root)))
    for p in cand:
        try:
            text = read_text(os.path.join(g.root, p))
        except OSError:
            continue
        for i, line in enumerate(text.split("\n"), 1):
            if any(x in line for x in pats):
                res["text_mentions"].append({"file": p, "line": i, "text": line.strip()[:140]})
    # 셰이더 상대 include 경고
    for t in targets:
        if t.endswith((".gdshader", ".gdshaderinc")) and os.path.dirname(newpath(t)) != os.path.dirname(t):
            res["warnings"].append("셰이더 파일의 폴더가 바뀐다: 안의 상대 #include가 깨질 수 있다 — " + t)
    return res


def render_rename(res):
    L = []
    a = L.append
    a(BLIND_SPOTS)
    a("")
    a("# 이름 바꾸기 점검: %s -> %s" % (res["old"], res["new"]))
    a("")
    a("대상 파일 %d개%s. 아래는 고칠 곳의 목록이며 이 도구는 아무것도 고치지 않았다." % (
        len(res["targets"]), "(폴더)" if res["is_dir"] else ""))
    a("")
    if res["warnings"]:
        a("## 경고")
        a("")
        for w in res["warnings"]:
            a("- " + w)
        a("")
    a("## 코드·장면·셰이더·데이터에서 고칠 곳 %d건" % len(res["edits"]))
    a("")
    for e in res["edits"]:
        a("- `%s` L%s [%s%s] %s%s" % (e["in"], ",".join(map(str, e["lines"][:4])), e["kind"],
                                    ",약함" if e["weak"] else "", e.get("edit", ""),
                                    (" — " + e["note"]) if e.get("note") else ""))
    a("")
    a("## 같이 옮길 사이드카(.uid/.import) %d개" % len(res["sidecars"]))
    a("")
    for s in res["sidecars"]:
        a("- %s -> %s" % (s["move"], s["to"]))
    a("")
    a("## 동적 경로 접두와 겹침 %d건" % len(res["dynamic_prefix"]))
    a("")
    for d in res["dynamic_prefix"]:
        a("- `%s` 접두 `%s`: %s" % (d["file"], d["prefix"], d["note"]))
    a("")
    a("## 뿌리 참조")
    a("")
    for n in res["notes"]:
        a("- " + n)
    a("")
    a("## 문서·도구의 글 언급 %d건(동작에는 영향 없음, 읽는 사람이 고침)" % len(res["text_mentions"]))
    a("")
    for m in res["text_mentions"][:60]:
        a("- `%s:%d` %s" % (m["file"], m["line"], m["text"].replace("`", "'")))
    if len(res["text_mentions"]) > 60:
        a("- … %d건 더" % (len(res["text_mentions"]) - 60))
    a("")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- 진입점

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def resolve_out(root, out):
    p = os.path.abspath(out if os.path.isabs(out) else os.path.join(root, out))
    base = os.path.abspath(os.path.join(root, "_local"))
    if not (p == base or p.startswith(base + os.sep)):
        return None
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description="참조 지도(읽기 전용)")
    ap.add_argument("--root", default=None, help="Godot 프로젝트 루트(기본: 이 스크립트에서 위로 찾음)")
    ap.add_argument("--out", default="_local/refactor-map/", help="출력 폴더(_local/ 아래만 허용)")
    ap.add_argument("--rename-check", nargs=2, metavar=("OLD", "NEW"))
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass
    root = args.root or find_root(os.path.dirname(os.path.abspath(__file__)))
    if not root or not os.path.exists(os.path.join(root, "project.godot")):
        print("project.godot를 찾지 못했다", file=sys.stderr)
        return 2
    root = os.path.abspath(root)
    out = resolve_out(root, args.out)
    if out is None:
        print("--out은 <루트>/_local/ 아래여야 한다", file=sys.stderr)
        return 2
    g = Graph(root)
    if args.rename_check:
        res = rename_check(g, *args.rename_check)
        md = render_rename(res)
        write(os.path.join(out, "rename-check.md"), md)
        write(os.path.join(out, "rename-check.json"), json.dumps(res, ensure_ascii=False, indent=1) + "\n")
        sys.stdout.write(md)
        return 0
    rep = build_report(g)
    write(os.path.join(out, "refmap.json"), json.dumps(rep, ensure_ascii=False, indent=1) + "\n")
    write(os.path.join(out, "refmap.md"), render_md(rep))
    print(BLIND_SPOTS)
    print(rep["summary_line"])
    if not args.quiet:
        print("출력: " + norm(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
