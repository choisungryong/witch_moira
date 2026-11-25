#!/usr/bin/env python3
"""kit_batch.py - runs a batch of element-kit measure_rhythm runs (one Godot process per seed) and runs them again with other values.

It replaces the one-off runners of the element-tree trials (_local/et-b/one.sh, set.sh, chain*.sh; D-element-trees 16.7, ET-D). Standard library only.

  run    python tools/dev/kit_batch.py run --dir _local/et-d --tuning _local/et-b/on.json --seeds 11-30 --preset kit140 [--par 6] [--limit-min 40] [--kit-doc _local/et-d/doc.json]
         --preset kit140 = link / link_rank / main (tree all) + rnd1..rnd3 (tree all, random policy, --kit-seed 1..3) + newl (tree none, link policy), the 140-run table of 16.7.
         --preset bare = the old-growth runs of BF-B (no kit; ember, frost and arc in one file, the tool's "fire" and "arcold" sets) for seeds that BF-B did not run.
         --set NAME:policy=link,tree=all[,kit_seed=N][,kit=off][,primaries=ember;frost;arc][,extra=--flag;--flag2]  (repeatable, in place of / besides a preset)
         Writes <dir>/<name>_s<seed>.json and _stdout.txt, skips a run whose JSON is already complete (re-running a half-done batch picks up where it stopped), retries a run
         that Godot could not start (script load failure under load) up to 5 times, and records what it did in <dir>/batch.json and <dir>/done.log.
         --limit-min: a set that has been running longer than this many minutes is cut: its queued seeds are not started and are listed as "cut" in batch.json.
  again  python tools/dev/kit_batch.py again --dir _local/et-d --to _local/et-d/r2 [--kit-doc ...] [--seeds 11-20] [--only link,newl] [--tuning ...]
         reads <dir>/batch.json and runs the same sets again into --to with the given overrides (the second try with changed values).
  status python tools/dev/kit_batch.py status --dir _local/et-d
  read   python tools/dev/kit_batch.py read --dir _local/et-d --fire "_local/bf-b/bare_s*.json" --arcold "_local/bf-b/bare_s*.json" [--s1 30] [--out _local/et-d/kit.txt]
         calls `rc_read.py kit` with every set found in <dir> (link, link_rank, main, rnd1..3, newl) and the given old-growth files.

Every Godot call goes through tools/dev/godot.py (isolated APPDATA). No more than --par (default 4, at most 6) processes at once. The bot's results are a stability / balance
reference, not evidence of fun (unevaluated).
"""
import argparse
import json
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRESETS = {
    "kit140": {
        "link": {"policy": "link", "tree": "all"},
        "link_rank": {"policy": "link_rank", "tree": "all"},
        "main": {"policy": "main", "tree": "all"},
        "rnd1": {"policy": "random", "tree": "all", "kit_seed": 1},
        "rnd2": {"policy": "random", "tree": "all", "kit_seed": 2},
        "rnd3": {"policy": "random", "tree": "all", "kit_seed": 3},
        "newl": {"policy": "link", "tree": "none"},
    },
    "bare": {"bare": {"kit": "off", "primaries": "ember;frost;arc"}},
    "link2": {"link": {"policy": "link", "tree": "all"}, "newl": {"policy": "link", "tree": "none"}},
}
FAIL_MARKS = ("Compilation failed", "Can't open file", "Failed to load script")


def parse_seeds(s):
    out = []
    for part in str(s).split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def parse_set(spec):
    name, _, rest = spec.partition(":")
    d = {}
    for kv in rest.split(","):
        k, _, v = kv.partition("=")
        if k:
            d[k] = int(v) if k == "kit_seed" else v
    return name, d


def rel(p):
    p = Path(p)
    return str(p.relative_to(ROOT)).replace("\\", "/") if p.is_absolute() and ROOT in p.parents else str(p).replace("\\", "/")


def complete(path):
    try:
        t = Path(path).read_text(encoding="utf-8")
    except OSError:
        return False
    return '"mode"' in t


def cmd_for(name, s, seed, args, out):
    c = [sys.executable, "tools/dev/godot.py", "--headless", "--path", ".", "--script", "res://chapter1/tests/measure_rhythm.gd", "--",
         "--seeds=%d" % seed, "--primaries=%s" % str(s.get("primaries", args["primary"])).replace(";", ","), "--rhythm-on", "--no-trial-arena", "--thirds", "--rc", "--tuning=%s" % args["tuning"]]
    if s.get("kit") != "off":
        c += ["--element-kit", "--kit-tree=%s" % s.get("tree", "all"), "--kit-policy=%s" % s.get("policy", "link")]
    if "kit_seed" in s:
        c.append("--kit-seed=%d" % s["kit_seed"])
    if args.get("kit_doc"):
        c.append("--kit-doc=%s" % args["kit_doc"])
    for x in str(s.get("extra", "")).split(";"):
        if x:
            c.append(x)
    c.append("--out=%s" % out)
    return c


def run_batch(args):
    d = ROOT / args["dir"]
    d.mkdir(parents=True, exist_ok=True)
    sets, seeds = args["sets"], args["seeds"]
    par = max(1, min(6, int(args.get("par", 4))))
    lock = threading.Lock()
    started = {}
    cut = {k: [] for k in sets}
    failed = []
    log = open(d / "done.log", "a", encoding="utf-8")
    limit = float(args.get("limit_min", 40)) * 60

    def one(name, seed):
        out = "%s/%s_s%d.json" % (args["dir"], name, seed)
        if complete(ROOT / out):
            return
        with lock:
            t0 = started.setdefault(name, time.time())
            if time.time() - t0 > limit:
                cut[name].append(seed)
                return
        for attempt in range(1, 6):
            with open(ROOT / (out[:-5] + "_stdout.txt"), "w", encoding="utf-8") as so:
                subprocess.run(cmd_for(name, sets[name], seed, args, out), cwd=ROOT, stdout=so, stderr=subprocess.STDOUT)
            txt = (ROOT / (out[:-5] + "_stdout.txt")).read_text(encoding="utf-8", errors="replace")
            if complete(ROOT / out) and not any(m in txt for m in FAIL_MARKS):
                with lock:
                    log.write("%s %d ok try %d %s\n" % (name, seed, attempt, time.strftime("%H:%M:%S")))
                    log.flush()
                return
            time.sleep(5)
        with lock:
            failed.append("%s_s%d" % (name, seed))

    jobs = [(n, s) for n in sets for s in seeds]
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=par) as ex:
        list(ex.map(lambda j: one(*j), jobs))
    rec = dict(args)
    rec["cut"] = {k: v for k, v in cut.items() if v}
    rec["failed"] = failed
    rec["wall_min"] = round((time.time() - t0) / 60, 1)
    (d / "batch.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1), encoding="utf-8")
    print("kit_batch: %d runs asked, wall %.1f min, cut %s, failed %s" % (len(jobs), rec["wall_min"], rec["cut"] or "none", failed or "none"))
    return 0 if not failed else 1


def cmd_run(a):
    sets = {}
    if a.preset:
        sets.update(PRESETS[a.preset])
    for spec in a.set or []:
        n, d = parse_set(spec)
        sets[n] = d
    if not sets:
        sys.exit("kit_batch: no sets (--preset or --set)")
    args = {"dir": rel(a.dir), "tuning": rel(a.tuning), "seeds": parse_seeds(a.seeds), "sets": sets, "par": a.par, "limit_min": a.limit_min, "primary": a.primary, "kit_doc": rel(a.kit_doc) if a.kit_doc else ""}
    sys.exit(run_batch(args))


def cmd_again(a):
    src = json.loads((ROOT / rel(a.dir) / "batch.json").read_text(encoding="utf-8"))
    args = {k: src[k] for k in ("tuning", "seeds", "sets", "par", "limit_min", "primary", "kit_doc")}
    args["dir"] = rel(a.to)
    if a.tuning:
        args["tuning"] = rel(a.tuning)
    if a.kit_doc:
        args["kit_doc"] = rel(a.kit_doc)
    if a.seeds:
        args["seeds"] = parse_seeds(a.seeds)
    if a.par:
        args["par"] = a.par
    if a.only:
        keep = a.only.split(",")
        args["sets"] = {k: v for k, v in args["sets"].items() if k in keep}
    sys.exit(run_batch(args))


def cmd_status(a):
    d = ROOT / rel(a.dir)
    names = {}
    for p in sorted(d.glob("*_s*.json")):
        n, _, s = p.stem.rpartition("_s")
        if s.isdigit() and n:
            names.setdefault(n, []).append((int(s), complete(p)))
    for n, v in names.items():
        print("%-10s done %d / files %d" % (n, sum(1 for _, ok in v if ok), len(v)))
    b = d / "batch.json"
    if b.exists():
        r = json.loads(b.read_text(encoding="utf-8"))
        print("batch.json: wall %s min, cut %s, failed %s" % (r.get("wall_min"), r.get("cut") or "none", r.get("failed") or "none"))


def cmd_read(a):
    c = [sys.executable, "tools/dev/rc_read.py", "kit"]
    for d in [rel(x) for x in a.dir.split(",")]:  # --dir _local/et-d,_local/et-d/ext reads both (seeds 11~30 and 31~50) as one set per name
        if list((ROOT / d).glob("bare_s*.json")) and not (a.fire or a.arcold):
            c += ["--set", "fire=%s/bare_s*.json" % d, "--set", "arcold=%s/bare_s*.json" % d]
        for n in ("link", "link_rank", "main", "rnd1", "rnd2", "rnd3", "newl"):
            if list((ROOT / d).glob(n + "_s*.json")):
                c += ["--set", "%s=%s/%s_s*.json" % (n, d, n)]
    if a.fire:
        c += ["--set", "fire=" + a.fire]
    if a.arcold:
        c += ["--set", "arcold=" + a.arcold]
    c += ["--s0", str(a.s0), "--s1", str(a.s1)]
    if a.out:
        c += ["--out", a.out]
    sys.exit(subprocess.run(c, cwd=ROOT).returncode)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--dir", required=True)
    r.add_argument("--tuning", required=True)
    r.add_argument("--seeds", default="11-30")
    r.add_argument("--preset", choices=sorted(PRESETS))
    r.add_argument("--set", action="append")
    r.add_argument("--par", type=int, default=4)
    r.add_argument("--limit-min", type=float, default=40)
    r.add_argument("--primary", default="arc")
    r.add_argument("--kit-doc")
    g = sub.add_parser("again")
    g.add_argument("--dir", required=True)
    g.add_argument("--to", required=True)
    g.add_argument("--tuning")
    g.add_argument("--kit-doc")
    g.add_argument("--seeds")
    g.add_argument("--only")
    g.add_argument("--par", type=int)
    s = sub.add_parser("status")
    s.add_argument("--dir", required=True)
    e = sub.add_parser("read")
    e.add_argument("--dir", required=True)
    e.add_argument("--fire")
    e.add_argument("--arcold")
    e.add_argument("--s0", type=int, default=11)
    e.add_argument("--s1", type=int, default=30)
    e.add_argument("--out")
    a = ap.parse_args()
    {"run": cmd_run, "again": cmd_again, "status": cmd_status, "read": cmd_read}[a.cmd](a)


if __name__ == "__main__":
    main()
