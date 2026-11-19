#!/usr/bin/env python3
"""결정 번호 장부: docs/ 전체에서 결정 번호(N숫자, U숫자)를 모아 겹친 번호와 다음 빈 번호를 낸다.

찾는 것
  정의 행   표의 첫 칸이 번호만인 행: `| N39 | 제목 | ... |`, `| **N59** (2판) | ... |`, `| N41·N42 | ... |`
  참조 행   첫 칸에 번호와 다른 글이 붙은 행(`| N5 균열 속 눈뜸 | ... |`): 다른 결정을 가리키는 표라서 번호만 세고 제목 비교에는 쓰지 않는다
  표지      `[잠정 · N7]`, `[미정 · N9 · U12와 묶임]` 같은 대괄호 안의 번호. 그 결정에 기대는 대목의 표시라서 제목 비교에는 쓰지 않는다
상태(확정·잠정)는 읽지 않고 추측하지도 않는다.

겹침의 판정(추정이다): 같은 번호의 정의 행들 제목이 한글 두 글자 조각을 거의 나누지 않으면 서로 다른 항목으로 본다.
같은 결정을 다른 문서가 다르게 풀어 쓴 것(제목이 달라도 조각이 겹침)은 겹침으로 세지 않는다. 사람이 마지막으로 확인한다.
번호 체계: 기본 범위(결정 번호를 쓰는 문서)는 docs/story/*.md, docs/reviews/DECISIONS-PENDING-*.md, docs/reviews/STORY-REVIEW-*.md.
그 밖의 문서(spec·검토서 등)는 문서 안에서만 쓰는 번호(N1, N2 …)일 수 있어 겹침은 알려 주되 종료 코드에는 넣지 않는다.
`--all-scope`로 모든 문서를 한 체계로 본다.

  python tools/dev/decision_ledger.py                      # 표로 출력. 범위 안에 겹침이 있으면 종료 1
  python tools/dev/decision_ledger.py --json --out=_local/decisions/ledger.json
"""
import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SCOPE = ["docs/story/*.md", "docs/reviews/DECISIONS-PENDING-*.md", "docs/reviews/STORY-REVIEW-*.md"]
NUM = r"[NU]\d+"
CELL1 = re.compile(rf"^\**\s*({NUM}(?:\s*[·,~]\s*{NUM})*)\s*\**\s*(?:\([^)]*\))?\s*\**\s*$")
CELL1_LOOSE = re.compile(rf"^\**\s*({NUM})(?![0-9])")
MARKER = re.compile(r"\[([^\]\n]*·[^\]\n]*)\]")
TOKEN = re.compile(rf"(?<![A-Za-z0-9])({NUM})(?![0-9])")
PROSE = TOKEN


def clean(s: str) -> str:
    s = re.sub(r"[*`]", "", s)
    return re.sub(r"\s+", " ", s).strip()


def bigrams(s: str) -> set:
    out = set()
    for run in re.findall(r"[가-힣]+", s):
        out |= {run[i:i + 2] for i in range(len(run) - 1)}
    return out


def similar(a: str, b: str, threshold: float = 0.12) -> bool:
    x, y = bigrams(a), bigrams(b)
    if not x or not y:
        return a == b
    return len(x & y) / min(len(x), len(y)) >= threshold


def scan_text(rel: str, text: str) -> list:
    """한 문서의 번호 나옴 목록. kind: row(정의 행) / ref(참조 행) / marker(표지)."""
    occ = []
    for n, line in enumerate(text.splitlines(), 1):
        st = line.strip()
        if st.startswith("|"):
            cells = [c.strip() for c in st.strip("|").split("|")]
            if not cells:
                continue
            m = CELL1.match(cells[0])
            if m:
                title = clean(cells[1]) if len(cells) > 1 else ""
                for num in TOKEN.findall(m.group(1)):
                    occ.append({"num": num, "kind": "row", "file": rel, "line": n, "title": title})
                continue
            m = CELL1_LOOSE.match(cells[0])
            if m:
                title = clean(" ".join(cells[:2]))
                occ.append({"num": m.group(1), "kind": "ref", "file": rel, "line": n, "title": title})
                continue
        for mk in MARKER.finditer(line):
            for num in TOKEN.findall(mk.group(1)):
                occ.append({"num": num, "kind": "marker", "file": rel, "line": n, "title": ""})
    return occ


def prose_numbers(text: str) -> set:
    return set(PROSE.findall(text))


def in_scope(rel: str, scope: list) -> bool:
    return any(fnmatch.fnmatch(rel, g) for g in scope)


def build(root: Path, scope: list, all_scope: bool = False) -> dict:
    occ, prose = [], {}
    for p in sorted((root / "docs").rglob("*.md")):
        rel = p.relative_to(root).as_posix()
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        found = scan_text(rel, text)
        occ += found
        prose[rel] = prose_numbers(text)
    nums: dict = {}
    for o in occ:
        o["scope"] = all_scope or in_scope(o["file"], scope)
        nums.setdefault(o["num"], []).append(o)

    entries, overlaps_scope, overlaps_other = [], [], []
    for num in sorted(nums, key=lambda s: (s[0], int(s[1:]))):
        items = nums[num]
        rows = [o for o in items if o["kind"] == "row"]
        sc_rows = [o for o in rows if o["scope"]]
        first = (sc_rows or rows or items)[0]
        files = sorted({o["file"] for o in items})
        e = {"num": num, "title": first["title"] or "(정의 행 없음: 표지·참조로만 나옴)", "first": f"{first['file']}:{first['line']}",
             "files": files, "rows": [{"at": f"{o['file']}:{o['line']}", "title": o["title"], "scope": o["scope"]} for o in rows],
             "overlap": False}
        for label, flag in (("scope", True), ("other", False)):
            part = [o for o in rows if o["scope"] == flag]
            if len(part) < 2:
                continue
            clusters: list = []
            for o in part:
                for c in clusters:
                    if any(similar(o["title"], q["title"]) for q in c):
                        c.append(o)
                        break
                else:
                    clusters.append([o])
            # 군집끼리 서로 닮은 것이 있으면 합친다(순서에 따른 갈림 방지)
            merged = True
            while merged and len(clusters) > 1:
                merged = False
                for i in range(len(clusters)):
                    for j in range(i + 1, len(clusters)):
                        if any(similar(a["title"], b["title"]) for a in clusters[i] for b in clusters[j]):
                            clusters[i] += clusters.pop(j)
                            merged = True
                            break
                    if merged:
                        break
            if len(clusters) > 1:
                entry = {"num": num, "scope": label, "groups": [[{"at": f"{o['file']}:{o['line']}", "title": o["title"]} for o in c] for c in clusters]}
                (overlaps_scope if flag else overlaps_other).append(entry)
                if flag:
                    e["overlap"] = True
        entries.append(e)

    def next_free(prefix: str) -> dict:
        in_s = [int(o["num"][1:]) for o in occ if o["num"][0] == prefix and o["scope"]]
        pr = [int(x[1:]) for rel, s in prose.items() if (all_scope or in_scope(rel, scope)) for x in s if x[0] == prefix]
        top_tables = max(in_s, default=0)
        top_prose = max(pr, default=0)
        return {"highest_in_tables": top_tables, "highest_incl_prose": max(top_tables, top_prose), "next": max(top_tables, top_prose) + 1}

    return {"scope": "모든 문서" if all_scope else scope, "entries": entries, "overlaps": overlaps_scope,
            "overlaps_other_systems": overlaps_other, "next_free": {"N": next_free("N"), "U": next_free("U")},
            "note": "겹침은 제목의 한글 조각이 닮았는지로 한 추정이다. 상태(확정·잠정)는 읽지 않았다."}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="결정 번호 장부")
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--scope", action="append", help="결정 번호를 쓰는 문서의 글롭(여러 번 줄 수 있음)")
    ap.add_argument("--all-scope", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    ledger = build(Path(a.root), a.scope or DEFAULT_SCOPE, a.all_scope)
    if a.out:
        op = Path(a.out)
        op.parent.mkdir(parents=True, exist_ok=True)
        op.write_text(json.dumps(ledger, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    if a.json:
        print(json.dumps(ledger, ensure_ascii=False, indent=1))
    else:
        print("번호 | 제목 첫 줄 | 처음 나온 곳 | 나온 문서 수 | 겹침")
        for e in ledger["entries"]:
            print(f"{e['num']} | {e['title'][:50]} | {e['first']} | {len(e['files'])} | {'겹침' if e['overlap'] else ''}")
        for title, key in (("겹친 번호(결정 번호 문서)", "overlaps"), ("겹친 번호(다른 번호 체계로 보이는 문서, 종료 코드에 넣지 않음)", "overlaps_other_systems")):
            print(f"\n{title}: {len(ledger[key])}개")
            for o in ledger[key]:
                print(f"  {o['num']}")
                for g in o["groups"]:
                    for r in g:
                        print(f"    {r['at']}  {r['title'][:60]}")
                    print("    --")
        nf = ledger["next_free"]
        print(f"\n다음 빈 번호: N{nf['N']['next']}(표의 가장 큰 번호 N{nf['N']['highest_in_tables']}, 본문 언급까지 N{nf['N']['highest_incl_prose']}), "
              f"U{nf['U']['next']}(표 U{nf['U']['highest_in_tables']}, 본문까지 U{nf['U']['highest_incl_prose']})")
        print(f"LEDGER {'FAIL' if ledger['overlaps'] else 'PASS'} numbers={len(ledger['entries'])} overlaps={len(ledger['overlaps'])}")
    return 1 if ledger["overlaps"] else 0


if __name__ == "__main__":
    sys.exit(main())
