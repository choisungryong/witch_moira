"""Codex image-generation batch runner (replaces the per-batch batch_*.py / run_*.py / revise.py copies).

  python tools/art/gen.py CONFIG.json                      # dry run (default): build prompts, compare, write nothing under drafts/
  python tools/art/gen.py CONFIG.json --only a-1 a-2       # only these attempts
  python tools/art/gen.py CONFIG.json --execute            # prints "N attempts with model M" and STOPS (exit 3)
  python tools/art/gen.py CONFIG.json --execute --yes      # really calls Codex CLI, one attempt at a time
  python tools/art/gen.py CONFIG.json verify               # re-extract spec sentences and compare with the recorded hashes
  python tools/art/gen.py snapshot                         # print the git status snapshot used for the outside-change check

Config (JSON). Strings are literal text; "@name" refers to a named part; vars are written {key} and replaced literally.
  batch, folder (under drafts/), group, output_name (file Codex must save, e.g. icon.png), model, refs (default reference
  images), specs {key: file relative to repo root}, parts {name: segment}, template [segment, ...] (joined with a blank line),
  correction_label, expect_pattern, items [...].
Segment: "literal" | "@part" | {"text"} | {"file"} | {"spec": key, "after": marker, "fence": true}  (first ``` block after marker)
         | {"spec": key, "after": marker, "regex": "...", "group": 1, "flags": "s"}   optional "replace": {old: new}
Item: name (file stem), folder (overrides config.folder), title, refs, vars, parts (item-scoped override of named parts), template, expect (drafts-relative
      prompt file to compare), base_prompt_file + replace [[old,new]] + correction (revise.py style: base prompt + label + text),
      note, id.
The Codex call is copied from the past batch scripts (batch_equipment_icon.py, batch_round3.py, run_prompt.py):
  codex exec -m MODEL [-i REF]... -C WORKDIR --skip-git-repo-check -s workspace-write --color never -o LAST -   (prompt on stdin)
No keys or .env are read; Codex gets the environment of the calling process. Output goes only under a _local/ folder.
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_MODEL = "gpt-5.6-sol"          # the model every past batch script passes with -m
LABEL = "CORRECTIONS FOR THIS VERSION (these override anything above): "   # revise.py / batch_equipment_icon_r2.py
SECRET = re.compile(r"sk-[A-Za-z0-9_-]{16,}|API[_-]?KEY\s*[=:]\s*\S+|Bearer\s+[A-Za-z0-9._-]{20,}", re.I)


# ---------------------------------------------------------------- paths
def find_drafts(explicit=None):
    """drafts folder: --drafts, env ART_DRAFTS, ROOT/_local/art/drafts, or the same under an ancestor (git worktrees)."""
    cands = [explicit, os.environ.get("ART_DRAFTS")]
    cands += [p / "_local" / "art" / "drafts" for p in [ROOT, *ROOT.parents]]
    for c in cands:
        if c and pathlib.Path(c).is_dir():
            return pathlib.Path(c).resolve()
    raise SystemExit("drafts folder not found (use --drafts or ART_DRAFTS)")


def local_root(path):
    """The '_local' ancestor of path (or None)."""
    p = pathlib.Path(path).resolve()
    for q in [p, *p.parents]:
        if q.name == "_local":
            return q
    return None


def assert_local(path):
    if local_root(path) is None:
        raise SystemExit(f"refusing to write outside a _local/ folder: {path}")
    return pathlib.Path(path)


def write_text(path, text):
    assert_local(path)
    pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(path).write_text(text, encoding="utf-8", newline="\n")


def write_json_atomic(path, data):
    assert_local(path)
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def sha(x):
    return hashlib.sha256(x.encode("utf-8") if isinstance(x, str) else x).hexdigest()


def resolve_file(rel, drafts):
    """absolute, drafts-relative or repo-relative path -> existing Path or None."""
    p = pathlib.Path(rel)
    if p.is_absolute():
        return p if p.exists() else None
    for base in (drafts, ROOT, *ROOT.parents):
        if (base / p).exists():
            return base / p
    return None


# ---------------------------------------------------------------- prompt assembly
class Builder:
    def __init__(self, cfg, drafts):
        self.cfg, self.drafts = cfg, drafts
        self._spec = {}

    def spec(self, key):
        if key not in self._spec:
            rel = self.cfg.get("specs", {}).get(key)
            if not rel:
                raise SystemExit(f"spec key '{key}' not in config.specs")
            p = ROOT / rel
            if not p.exists():
                p = resolve_file(rel, self.drafts)
            if not p:
                raise SystemExit(f"spec file not found: {rel}")
            self._spec[key] = (rel, p.read_text(encoding="utf-8"), sha(p.read_bytes()))
        return self._spec[key]

    @staticmethod
    def subst(s, vars_):
        for k, v in vars_.items():
            s = s.replace("{" + k + "}", str(v))
        return s

    def extract(self, seg, vars_):
        rel, text, fsha = self.spec(seg["spec"])
        after = self.subst(seg.get("after", ""), vars_)
        i = text.index(after) if after else 0          # ValueError when the marker vanished = spec changed
        rest = text[i:]
        if seg.get("fence"):
            m = re.search(r"```\n(.*?)\n```", rest, re.S)
        else:
            flags = sum(getattr(re, f.upper()) for f in seg.get("flags", ""))
            m = re.search(self.subst(seg["regex"], vars_), rest, flags)
        if not m:
            raise ValueError(f"no match after marker {after!r}")
        out = m.group(seg.get("group", 1) if not seg.get("fence") else 1).strip()
        info = {"kind": "spec", "spec": rel, "spec_sha256": fsha, "marker": after, "extracted_sha256": sha(out)}
        for old, new in seg.get("replace", {}).items():
            if old not in out:
                raise ValueError(f"replace target {old!r} not in extracted text")
            out = out.replace(old, new)
            info["replaced"] = True
        return out, info

    def resolve(self, seg, vars_, parts, segs):
        if isinstance(seg, list):
            return "\n\n".join(self.resolve(s, vars_, parts, segs) for s in seg)
        if isinstance(seg, str):
            if seg.startswith("@"):
                name = seg[1:]
                if name not in parts:
                    raise SystemExit(f"unknown part {seg}")
                return self.resolve(parts[name], vars_, parts, segs)
            t = self.subst(seg, vars_)
            segs.append({"kind": "literal", "sha256": sha(t)})
            return t
        if "text" in seg:
            t = self.subst(seg["text"], vars_)
            segs.append({"kind": "literal", "sha256": sha(t)})
            return t
        if "file" in seg:
            p = resolve_file(self.subst(seg["file"], vars_), self.drafts)
            if not p:
                raise SystemExit(f"segment file not found: {seg['file']}")
            t = p.read_text(encoding="utf-8").strip()
            segs.append({"kind": "file", "file": seg["file"], "sha256": sha(t)})
            return t
        if "spec" in seg:
            t, info = self.extract(seg, vars_)
            segs.append(info | {"text": t})
            return t
        raise SystemExit(f"bad segment: {seg!r}")

    def build(self, item):
        cfg = self.cfg
        vars_ = {"id": item["name"], "name": item["name"], "out": cfg.get("output_name", "icon.png"),
                 "folder": cfg.get("folder", "")}
        vars_.update(cfg.get("vars", {}))
        vars_.update(item.get("vars", {}))
        parts = dict(cfg.get("parts", {}))
        parts.update(item.get("parts", {}))
        segs = []
        if item.get("base_prompt_file"):
            p = resolve_file(self.subst(item["base_prompt_file"], vars_), self.drafts)
            if not p:
                raise SystemExit(f"base_prompt_file not found: {item['base_prompt_file']}")
            text = p.read_text(encoding="utf-8")
            segs.append({"kind": "base_prompt", "file": item["base_prompt_file"], "sha256": sha(text)})
            for old, new in item.get("replace", []):
                if old not in text:
                    raise SystemExit(f"{item['name']}: replace target not in base prompt: {old[:50]!r}")
                text = text.replace(old, new)
            prompt = text.rstrip() + "\n"
        else:
            tpl = item.get("template", cfg.get("template"))
            if not tpl:
                raise SystemExit("no template")
            prompt = "\n\n".join(self.resolve(s, vars_, parts, segs) for s in tpl) + "\n"
        corr = item.get("correction")
        if corr:
            prompt = prompt.rstrip() + "\n\n" + cfg.get("correction_label", LABEL) + self.subst(corr, vars_) + "\n"
            segs.append({"kind": "correction", "sha256": sha(corr)})
        for s in segs:                                   # an extracted spec sentence must appear verbatim
            if s["kind"] == "spec" and not s.get("replaced") and s["text"] not in prompt:
                raise SystemExit(f"{item['name']}: spec sentence not verbatim in prompt")
        return prompt, segs


def load_config(path):
    raw = pathlib.Path(path).read_text(encoding="utf-8")
    if SECRET.search(raw):
        raise SystemExit("config looks like it contains a key or token; refusing (keys come from the environment)")
    cfg = json.loads(raw)
    for k in ("batch", "folder", "items"):
        if k not in cfg:
            raise SystemExit(f"config missing '{k}'")
    cfg["_sha256"] = sha(raw)
    return cfg


def compare_expected(prompt, drafts, rel):
    p = resolve_file(rel, drafts) if rel else None
    if not p:
        return {"expect": rel, "result": "no-file"}
    old = p.read_text(encoding="utf-8")
    if old == prompt:
        return {"expect": rel, "result": "match", "sha256": sha(prompt)}
    n = next((i for i, (a, b) in enumerate(zip(old, prompt)) if a != b), min(len(old), len(prompt)))
    return {"expect": rel, "result": "differs", "first_diff_char": n, "existing_sha256": sha(old), "built_sha256": sha(prompt),
            "existing_len": len(old), "built_len": len(prompt)}


# ---------------------------------------------------------------- git outside-change check
def git_snapshot():
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "status", "--short"], capture_output=True, text=True, encoding="utf-8").stdout
    except OSError:
        out = ""
    agents = ROOT / "AGENTS.md"
    return {"status": sorted(l for l in out.splitlines() if l.strip()),
            "agents_sha256": sha(agents.read_bytes()) if agents.exists() else None,
            "codex_dirs": sorted(str(p.relative_to(ROOT)) for p in ROOT.glob(".codex*"))}


def snapshot_diff(before, after):
    return {"new_status_lines": [l for l in after["status"] if l not in before["status"]],
            "agents_md_changed": before["agents_sha256"] != after["agents_sha256"],
            "new_codex_dirs": [d for d in after["codex_dirs"] if d not in before["codex_dirs"]]}


# ---------------------------------------------------------------- run
def codex_cmd(model, refs, wd, last):
    cmd = ["codex", "exec", "-m", model]
    for r in refs:
        cmd += ["-i", str(r)]
    return cmd + ["-C", str(wd), "--skip-git-repo-check", "-s", "workspace-write", "--color", "never", "-o", str(last), "-"]


def load_ledger(path, cfg):
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"batch": cfg["batch"], "config_sha256": cfg["_sha256"], "attempts": []}


def meta_for(cfg, item, rel_png, rel_prompt, status, note, model):
    folder = item.get("folder", cfg["folder"])
    return {"id": item.get("id") or f"{cfg.get('id_prefix', folder + '-')}{item['name']}", "character": folder,
            "group": cfg.get("group", cfg["batch"]), "title": item.get("title", item["name"]), "file": rel_png,
            "prompt_file": rel_prompt, "tool": "Codex CLI", "model": model,
            "created": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "status": status, "note": note}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("config", help="config JSON, or the word 'snapshot'")
    ap.add_argument("action", nargs="?", default="run", choices=["run", "verify"])
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--drafts")
    ap.add_argument("--ledger-dir")
    ap.add_argument("--dry-run", action="store_true", help="default; build and compare only")
    ap.add_argument("--execute", action="store_true", help="call Codex (needs --yes after the count is printed)")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--retry-failed", action="store_true")
    a = ap.parse_args(argv)
    if a.config == "snapshot":
        print(json.dumps(git_snapshot(), ensure_ascii=False, indent=1))
        return 0
    if a.execute and a.dry_run:
        raise SystemExit("--dry-run and --execute are exclusive")
    drafts = find_drafts(a.drafts)
    cfg = load_config(a.config)
    model = cfg.get("model", DEFAULT_MODEL)
    items = [i for i in cfg["items"] if not a.only or i["name"] in a.only]
    if not items:
        raise SystemExit("no matching items")
    lroot = local_root(drafts)
    ledger_dir = pathlib.Path(a.ledger_dir) if a.ledger_dir else lroot / "art" / "ledgers"
    execute = a.execute
    dry_dir = lroot / "art" / "gen-dryrun" / cfg["batch"]
    ledger_path = ledger_dir / f"{cfg['batch']}{'' if execute else '.dryrun'}.ledger.json"
    b = Builder(cfg, drafts)
    built = []
    for it in items:
        prompt, segs = b.build(it)
        built.append((it, prompt, segs))
    if a.action == "verify":
        ledger = load_ledger(ledger_path if execute else ledger_dir / f"{cfg['batch']}.ledger.json", cfg)
        rec = {x["name"]: x for x in ledger["attempts"]}
        bad = 0
        for it, prompt, segs in built:
            r = rec.get(it["name"])
            if not r:
                print(f"{it['name']}: not in ledger")
                continue
            same = r.get("prompt_sha256") == sha(prompt)
            bad += not same
            print(f"{it['name']}: {'spec/prompt unchanged' if same else 'CHANGED since recorded (spec or config edited)'}")
        return 1 if bad else 0
    print(f"batch {cfg['batch']}: {len(built)} attempts, model {model}, folder {cfg['folder']}, mode {'EXECUTE' if execute else 'dry-run'}")
    if execute and not a.yes:
        print(f"-> {len(built)} attempts would be run with Codex CLI model {model}, one at a time (~1-3 min each).")
        print("   Nothing was run. Re-run with --execute --yes to proceed.")
        return 3
    ledger = load_ledger(ledger_path, cfg)
    ledger.update(config_path=str(pathlib.Path(a.config).resolve()), config_sha256=cfg["_sha256"], model=model,
                  mode="execute" if execute else "dry-run", updated=datetime.datetime.now().isoformat(timespec="seconds"))
    rec = {x["name"]: x for x in ledger["attempts"]}
    before = git_snapshot()
    total_t0 = time.time()
    for it, prompt, segs in built:
        name = it["name"]
        prev = rec.get(name)
        if execute and prev and (prev["status"] == "ok" or (prev["status"] in ("no-image", "error") and not a.retry_failed)):
            print(f"{name}: skip (ledger says {prev['status']})")
            continue
        folder = it.get("folder", cfg["folder"])
        outdir = drafts / folder if execute else dry_dir
        rel_prompt = f"{folder}/{name}.prompt.txt"
        rel_png = f"{folder}/{name}.png"
        exp = compare_expected(prompt, drafts, it.get("expect") or (cfg["expect_pattern"].format(folder=folder, name=name) if cfg.get("expect_pattern") else None))
        ref_paths = [(r, resolve_file(r, drafts)) for r in it.get("refs", cfg.get("refs", []))]
        missing = [r for r, p in ref_paths if p is None]
        entry = {"name": name, "id": meta_for(cfg, it, rel_png, rel_prompt, "", "", model)["id"], "status": "dry-run" if not execute else "running",
                 "prompt_file": rel_prompt, "prompt_sha256": sha(prompt), "segments": [{k: v for k, v in s.items() if k != "text"} for s in segs],
                 "refs": [r for r, _ in ref_paths], "missing_refs": missing, "compare": exp,
                 "started": datetime.datetime.now().isoformat(timespec="seconds")}
        write_text(outdir / f"{name}.prompt.txt", prompt)
        if not execute:
            write_json_atomic(outdir / f"{name}.json", meta_for(cfg, it, rel_png, rel_prompt, "dry-run", "dry-run, Codex not called", model))
            print(f"{name}: prompt {len(prompt)} chars sha {sha(prompt)[:12]}  compare={exp['result']}"
                  + (f" (first diff at char {exp['first_diff_char']})" if exp["result"] == "differs" else "") + (f"  MISSING REFS {missing}" if missing else ""))
        else:
            if missing:
                raise SystemExit(f"{name}: reference images missing: {missing}")
            clash = [x for x in (".png", ".json") if (outdir / f"{name}{x}").exists()]
            if clash and not (prev and prev["status"] == "running"):
                entry["status"] = "blocked-exists"
                print(f"{name}: BLOCKED, {clash} already exist (new attempts need a new name; nothing is overwritten)")
                rec[name] = entry
                ledger["attempts"] = list(rec.values())
                write_json_atomic(ledger_path, ledger)
                continue
            wd = outdir / "work" / name
            wd.mkdir(parents=True, exist_ok=True)
            copies = []
            for r, p in ref_paths:
                dst = wd / p.name
                shutil.copy2(p, dst)
                copies.append(dst)
            last = outdir / f"{name}.last.txt"
            if last.exists():
                last.unlink()
            rec[name] = entry
            ledger["attempts"] = list(rec.values())
            write_json_atomic(ledger_path, ledger)           # status 'running' is on disk before the call (resume point)
            snap0 = git_snapshot()
            t0 = time.time()
            with open(outdir / f"{name}.prompt.txt", "rb") as fin, open(outdir / f"{name}.run.log", "wb") as log:
                r = subprocess.run(codex_cmd(model, copies, wd, last), stdin=fin, stdout=log, stderr=subprocess.STDOUT, shell=(sys.platform == "win32"))
            secs = round(time.time() - t0)
            made = wd / cfg.get("output_name", "icon.png")
            ok = made.exists() and not any(made.read_bytes() == p.read_bytes() for p in copies)   # a copy of a reference is not a result
            if ok:
                shutil.copy2(made, outdir / f"{name}.png")
            entry.update(status="ok" if ok else "no-image", seconds=secs, exit_code=r.returncode, outside=snapshot_diff(snap0, git_snapshot()),
                         meta_file=f"{folder}/{name}.json", last_message=f"{folder}/{name}.last.txt")
            note = (it.get("note", cfg.get("note", "")) + f" 걸린 시간 {secs}초, 종료코드 {r.returncode}").strip()
            write_json_atomic(outdir / f"{name}.json", meta_for(cfg, it, rel_png, rel_prompt, "검토 대기" if ok else "거부·실패", note, model))
            print(name, "ok" if ok else "NO IMAGE", secs, "s exit", r.returncode, flush=True)
        rec[name] = entry
        ledger["attempts"] = list(rec.values())
        write_json_atomic(ledger_path, ledger)
    diff = snapshot_diff(before, git_snapshot())
    ledger["outside_check"] = {"checked": execute, **diff, "elapsed_seconds": round(time.time() - total_t0)}
    ledger["updated"] = datetime.datetime.now().isoformat(timespec="seconds")
    write_json_atomic(ledger_path, ledger)
    print("ledger:", ledger_path)
    if execute:
        print("outside check:", json.dumps(diff, ensure_ascii=False))
    else:
        print("outside check: not applicable (nothing was executed); prompts/meta in", dry_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
