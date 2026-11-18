#!/usr/bin/env python3
"""L3-c: every character the game can print must exist in the bundled font chain.

Sources: chapter1/i18n/*.po (msgid and msgstr), string literals in chapter1/**/*.gd (tests excluded),
string values in chapter1/data/*.json. Fonts: chapter1/art/fonts/*.ttf (chain = union of their cmaps,
because system fallback is off). Prints missing characters with the first places they appear.
Exit 0 when nothing is missing, 1 otherwise. Needs fonttools.

  python tools/dev/check_glyphs.py            # check
  python tools/dev/check_glyphs.py --verbose  # also list the source counts
"""
import json
import re
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
FONT_DIR = ROOT / "chapter1" / "art" / "fonts"
STR_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# Characters that are never drawn: control characters and joiners.
IGNORED = {"\n", "\r", "\t", "​", "‍", "️"}


def font_chain() -> dict:
    chain = {}
    for ttf in sorted(FONT_DIR.glob("*.ttf")):
        chain[ttf.name] = set(TTFont(str(ttf), lazy=True).getBestCmap().keys())
    return chain


def unescape(s: str) -> str:
    return (s.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\"))


def collect() -> dict:
    """char -> list of 'file:line' where it was first seen (max 3)."""
    seen: dict = {}
    counts = {"po": 0, "gd": 0, "json": 0}

    def add(text: str, where: str, kind: str):
        counts[kind] += 1
        for ch in text:
            if ch in IGNORED:
                continue
            places = seen.setdefault(ch, [])
            if len(places) < 3 and where not in places:
                places.append(where)

    for po in sorted((ROOT / "chapter1" / "i18n").glob("*.po")):
        for n, line in enumerate(po.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            m = re.match(r'^(?:msgid|msgstr|msgid_plural|msgstr\[\d+\])?\s*"(.*)"$', line)
            if m and not line.startswith("#"):
                add(unescape(m.group(1)), f"{po.name}:{n}", "po")
    for gd in sorted((ROOT / "chapter1").rglob("*.gd")):
        if "tests" in gd.relative_to(ROOT).parts:
            continue
        for n, line in enumerate(gd.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for m in STR_RE.finditer(line):
                add(unescape(m.group(1)), f"{gd.relative_to(ROOT).as_posix()}:{n}", "gd")
    for js in sorted((ROOT / "chapter1" / "data").glob("*.json")):
        def walk(v):
            if isinstance(v, str):
                add(v, js.name, "json")
            elif isinstance(v, list):
                for x in v:
                    walk(x)
            elif isinstance(v, dict):
                for x in v.values():
                    walk(x)
        walk(json.loads(js.read_text(encoding="utf-8")))
    seen["__counts__"] = counts  # type: ignore[assignment]
    return seen


def main() -> int:
    chain = font_chain()
    if not chain:
        print("GLYPHS FAIL no .ttf in", FONT_DIR)
        return 1
    seen = collect()
    counts = seen.pop("__counts__")
    covered = set().union(*chain.values())
    missing = {ch: where for ch, where in seen.items() if ord(ch) not in covered}
    if "--verbose" in sys.argv:
        print("fonts:", {k: len(v) for k, v in chain.items()}, "sources:", counts, "distinct chars:", len(seen))
    for ch in sorted(missing):
        print(f"MISSING U+{ord(ch):04X} {ch!r} {', '.join(missing[ch])}")
    print(f"GLYPHS {'PASS' if not missing else 'FAIL'} distinct={len(seen)} missing={len(missing)} fonts={len(chain)}")
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
