#!/usr/bin/env python3
"""tuning_copy.py - a copy of a data document with a few keys changed, written under _local/ (D19 V0).

The shipped chapter1/data/** is never written. The copy is what `measure_rhythm.gd --tuning=` / `--descent-doc=` read.
  python tools/dev/tuning_copy.py --out _local/d19/v0/w_d1.json --set hp_time_bps_per_s=90 --set champions.0.xp=300 --set xp_thresholds=[0,10,25]
  python tools/dev/tuning_copy.py --src chapter1/data/descent.json --out _local/x/descent.json --set cost=[3000,5000,6000]
A key path is dotted; a number in it indexes an array. The value is JSON (a bare word that is not JSON is taken as a string).
It prints the changed keys (old -> new). Nothing else is touched; key order and the rest of the document stay as they were.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _walk(doc, parts):
    cur = doc
    for p in parts[:-1]:
        cur = cur[int(p)] if isinstance(cur, list) else cur[p]
    return cur, parts[-1]


def apply_set(doc, spec):
    path, _, raw = spec.partition("=")
    if not path or not _:
        raise SystemExit("--set needs key.path=value (got %r)" % spec)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        value = raw
    parent, last = _walk(doc, path.split("."))
    key = int(last) if isinstance(parent, list) else last
    if isinstance(parent, list):
        old = parent[key]
    else:
        if key not in parent:
            raise SystemExit("no such key: %s (refusing to invent keys)" % path)
        old = parent[key]
    parent[key] = value
    return path, old, value


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default="chapter1/data/combat_tuning.json")
    ap.add_argument("--out", required=True, help="a path under _local/")
    ap.add_argument("--set", action="append", default=[], dest="sets")
    a = ap.parse_args(argv)
    out = (ROOT / a.out).resolve()
    if (ROOT / "_local").resolve() not in out.parents:
        raise SystemExit("--out must be under _local/")
    doc = json.loads((ROOT / a.src).read_text(encoding="utf-8"))
    for spec in a.sets:
        path, old, new = apply_set(doc, spec)
        print("%s: %s -> %s" % (path, json.dumps(old), json.dumps(new)))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("wrote", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
