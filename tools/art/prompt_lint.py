"""Check attempt prompts against the direction sheet (지시서) and the wording rules. Read-only.

  python tools/art/prompt_lint.py CONFIG.json [--dir DIR] [--only name ...]
      for every item of a gen.py config: rebuild the expected prompt from the sheet and compare with the attempt's
      prompt file (default <drafts>/<folder>/<name>.prompt.txt). Result per item:
        identical | identical + corrections appended (the appended text is marked, not counted as a mismatch)
        | DIFFERS (missing / extra paragraphs are listed)
  python tools/art/prompt_lint.py --scan DIR
      no sheet needed: banned words, key-like strings, and whether a corrections block is present, for every *.prompt.txt

Banned words come from docs/story/wording-rules.json ("banned"). If that file does not exist the check is skipped and the
report says so. Exit code 1 when anything differs or any banned word / key-like string is found.
"""
import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen  # noqa: E402

RULES_REL = pathlib.Path("docs") / "story" / "wording-rules.json"


def load_banned():
    """(words, note). Accepts list[str], list[dict with word/term/text], or dict {word: ...}."""
    for base in (gen.ROOT, *gen.ROOT.parents):
        p = base / RULES_REL
        if p.is_file():
            try:
                data = json.loads(p.read_text(encoding="utf-8-sig"))
            except ValueError as e:
                return [], f"banned-word check SKIPPED: {p} is not valid JSON ({e})"
            raw = data.get("banned") if isinstance(data, dict) else None
            if raw is None:
                return [], f"banned-word check SKIPPED: {p} has no 'banned' key"
            if isinstance(raw, dict):
                raw = list(raw)
            words = []
            for w in raw:
                if isinstance(w, dict):
                    w = w.get("word") or w.get("term") or w.get("text")
                if isinstance(w, str) and w:
                    words.append(w)
            return words, f"banned words from {p} ({len(words)})"
    return [], f"banned-word check SKIPPED: {RULES_REL.as_posix()} does not exist yet"


def text_hits(text, words):
    hits = [w for w in words if w.lower() in text.lower()]
    if gen.SECRET.search(text):
        hits.append("<key-like string>")
    return hits


def paragraphs(t):
    return [p.strip() for p in t.strip().split("\n\n") if p.strip()]


def split_corr(t):
    if gen.LABEL in t:
        i = t.index(gen.LABEL)
        return t[:i], t[i + len(gen.LABEL):].strip()
    return t, None


def classify(expected, actual):
    """-> (status, details). The corrections block (revise.py label) is split off both sides and reported separately."""
    ebase, ecorr = split_corr(expected)
    base, corr = split_corr(actual)
    n = len(corr) if corr else 0
    if base.strip() == ebase.strip():
        if corr is None and ecorr is None:
            return "identical", {"corrections_chars": 0}
        if corr == ecorr:
            return "identical", {"corrections_chars": n}
        if ecorr is None:
            return "identical + corrections appended", {"corrections_chars": n}
        return "DIFFERS", {"missing": [f"corrections text: {ecorr[:90]}"], "extra": [f"corrections text: {(corr or '')[:90]}"], "corrections_chars": n}
    e, a = paragraphs(ebase), paragraphs(base)
    return "DIFFERS", {"missing": [p[:100] for p in e if p not in a], "extra": [p[:100] for p in a if p not in e],
                       "corrections_chars": n}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("config", nargs="?")
    ap.add_argument("--dir", help="folder holding the prompt files (default <drafts>/<folder>)")
    ap.add_argument("--scan")
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--drafts")
    a = ap.parse_args(argv)
    words, note = load_banned()
    print(note)
    bad = 0
    if a.scan:
        for p in sorted(pathlib.Path(a.scan).rglob("*.prompt.txt")):
            t = p.read_text(encoding="utf-8", errors="replace")
            h = text_hits(t, words)
            bad += bool(h)
            print(f"{p.name}: {'HITS ' + str(h) if h else 'clean'}{'  (has corrections block)' if gen.LABEL in t else ''}")
        return 1 if bad else 0
    if not a.config:
        ap.error("config or --scan required")
    drafts = gen.find_drafts(a.drafts)
    cfg = gen.load_config(a.config)
    b = gen.Builder(cfg, drafts)
    n = {"identical": 0, "identical + corrections appended": 0, "DIFFERS": 0, "no-file": 0}
    for it in cfg["items"]:
        if a.only and it["name"] not in a.only:
            continue
        folder = it.get("folder", cfg["folder"])
        f = (pathlib.Path(a.dir) if a.dir else drafts / folder) / f"{it['name']}.prompt.txt"
        expected, _ = b.build(it)
        if not f.exists():
            n["no-file"] += 1
            print(f"{it['name']}: no prompt file ({f})")
            continue
        actual = f.read_text(encoding="utf-8")
        status, d = classify(expected, actual)
        n[status] += 1
        hits = text_hits(actual, words)
        bad += status == "DIFFERS" or bool(hits)
        line = f"{it['name']}: {status}"
        if d["corrections_chars"]:
            line += f" [corrections {d['corrections_chars']} chars, marked]"
        if hits:
            line += f"  BANNED/KEY HITS {hits}"
        print(line)
        for k in ("missing", "extra"):
            for p in d.get(k, []):
                print(f"    {k}: {p!r}")
    print("summary:", json.dumps(n, ensure_ascii=False))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
