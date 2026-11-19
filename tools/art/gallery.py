"""Draft gallery index tool (replaces organize.py / register_*.py / reg_*.py / setpick*.py). Works on
<drafts>/index.json, the file tools/manager/drafts.py reads (read-only there), and <drafts>/selection.json (the manager's marks).

  python tools/art/gallery.py lint  [--check-manager] [--json OUT]       # read-only
  python tools/art/gallery.py add   --folder DIR | --meta FILE... [--write]   # preview unless --write
  python tools/art/gallery.py add   --sheet REL.jpg --id ID --title T --group G [--character C] [--prompt-file REL.txt] [--note N] [--write]
  python tools/art/gallery.py pick  ID... --mark candidate|final|archive|clear [--write]

add --sheet: registers a review sheet (a picture made by review_sheet.py --out <drafts>/<folder>/sheet-x.jpg) as one entry.
add: entries are built from each attempt's meta JSON (the <name>.json gen.py/the old batch scripts write). Duplicate ids and
     entries whose image or prompt file is missing are skipped and listed. With --write the old index.json is copied to
     index.json.bak-<time> first and the new one is written atomically (UTF-8, LF, indent 1, like the existing file).
pick: records a mark in selection.json in the format drafts.py uses ({revision, records:{id:{mark,updated}}}); the id must be
      in the index. Without --write it only prints what would change.
All writes stay under the drafts folder, which must live inside a _local/ folder.
"""
import argparse
import datetime
import importlib.util
import json
import os
import pathlib
import shutil
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen  # noqa: E402  (ROOT, find_drafts, assert_local, write_json_atomic)

IMAGE_TYPES = {".png", ".jpg", ".jpeg", ".webp"}      # same set as drafts.py IMAGE_TYPES
MARKS = {"candidate", "final", "archive"}
META_FIELDS = ("id", "character", "group", "title", "file", "prompt_file", "tool", "model", "created", "status", "note")


def safe_join(base, rel, suffixes):
    """Mirror of drafts.safe_join, but says why it failed: (path, None) or (None, reason)."""
    if not isinstance(rel, str) or not rel or "\\" in rel or ":" in rel or "\x00" in rel or rel.startswith("/"):
        return None, "unsafe or empty path"
    if any(x in ("", ".", "..") for x in rel.split("/")):
        return None, "unsafe path part"
    try:
        p = (base.resolve() / rel).resolve()
    except OSError:
        return None, "unresolvable path"
    if not p.is_relative_to(base.resolve()):
        return None, "escapes the drafts folder"
    if p.suffix.lower() not in suffixes:
        return None, f"suffix {p.suffix!r} not allowed"
    if not p.is_file():
        return None, "file missing"
    return p, None


def read_index(drafts):
    path = drafts / "index.json"
    if not path.is_file():
        return None, "index.json does not exist"
    try:
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as e:
        return None, f"index.json unreadable: {e}"
    if not isinstance(raw, list):
        return None, "index.json is not a list"
    return raw, None


def lint(drafts, check_manager=False, json_out=None):
    raw, err = read_index(drafts)
    if err:
        print("ERROR:", err)
        return 2
    problems, infos, seen, valid = [], [], set(), 0
    kinds = {"no_id": 0, "duplicate_id": 0, "not_object": 0, "bad_file": 0, "prompt_file_missing": 0, "prompt_file_not_txt": 0, "prompt_file_empty": 0}
    for i, e in enumerate(raw):
        tag = f"#{i + 1}"
        if not isinstance(e, dict):
            kinds["not_object"] += 1
            problems.append((tag, "entry is not an object"))
            continue
        iid = e.get("id")
        if not isinstance(iid, str) or not iid:
            kinds["no_id"] += 1
            problems.append((tag, "no id"))
            continue
        if iid in seen:
            kinds["duplicate_id"] += 1
            problems.append((iid, "duplicate id (the manager skips the later one)"))
            continue
        seen.add(iid)
        _, why = safe_join(drafts, e.get("file"), IMAGE_TYPES)
        if why:
            kinds["bad_file"] += 1
            problems.append((iid, f"file {e.get('file')!r}: {why} (the manager skips this entry)"))
            continue
        valid += 1
        pf = e.get("prompt_file")
        if not pf:
            kinds["prompt_file_empty"] += 1
            infos.append((iid, "no prompt_file set"))
        else:
            _, why = safe_join(drafts, pf, {".txt"})
            if why and why.startswith("suffix"):
                kinds["prompt_file_not_txt"] += 1
                problems.append((iid, f"prompt_file {pf!r}: not a .txt (the manager shows 'no prompt' for it)"))
            elif why:
                kinds["prompt_file_missing"] += 1
                problems.append((iid, f"prompt_file {pf!r}: {why}"))
    ids = seen
    sel = drafts / "selection.json"
    orphan_marks = []
    if sel.is_file():
        try:
            recs = json.loads(sel.read_text(encoding="utf-8")).get("records", {})
            orphan_marks = [k for k in recs if k not in ids]
        except (OSError, ValueError, AttributeError):
            problems.append(("selection.json", "unreadable"))
    for k in orphan_marks:
        problems.append((k, "selection.json mark for an id that is not in the index"))
    indexed_files = {e.get("file") for e in raw if isinstance(e, dict)}
    unindexed = []
    for m in sorted(drafts.glob("*/*.json")):
        try:
            d = json.loads(m.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(d, dict) and isinstance(d.get("id"), str) and isinstance(d.get("file"), str) and d["id"] not in ids \
                and d["file"] not in indexed_files and (drafts / d["file"]).is_file():
            unindexed.append(d["id"])
    for t, w in problems:
        print(f"  PROBLEM {t}: {w}")
    summary = {"entries": len(raw), "valid_for_manager": valid, "broken": len(raw) - valid, **kinds,
               "selection_orphans": len(orphan_marks), "attempt_metas_not_in_index": len(unindexed)}
    print("summary:", json.dumps(summary, ensure_ascii=False))
    if check_manager:
        mgr = gen.ROOT / "tools" / "manager"
        sys.path.insert(0, str(mgr))
        spec = importlib.util.spec_from_file_location("manager_drafts", mgr / "drafts.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        entries, _, warns = mod.read_index(drafts, gen.ROOT / "chapter1" / "art" / "characters")
        skipped = [w for w in warns if "건너뜁" in w]
        same = len(entries) == valid
        print(f"manager drafts.py read_index: {len(entries)} entries shown, {len(skipped)} skipped warnings -> "
              f"{'AGREES with lint' if same else 'DISAGREES with lint (' + str(valid) + ')'}")
        summary["manager_entries"] = len(entries)
        summary["manager_agrees"] = same
    if json_out:
        gen.write_json_atomic(json_out, {"summary": summary, "problems": problems, "info": infos, "unindexed": unindexed})
    return 1 if (summary["broken"] or kinds["prompt_file_missing"] or kinds["prompt_file_not_txt"] or orphan_marks) else 0


def entry_from_meta(drafts, meta):
    """-> (entry, None) or (None, reason)."""
    if not isinstance(meta, dict) or not isinstance(meta.get("id"), str) or not meta["id"] or not isinstance(meta.get("file"), str):
        return None, "not an attempt meta (needs id and file)"
    _, why = safe_join(drafts, meta["file"], IMAGE_TYPES)
    if why:
        return None, f"file {meta['file']!r}: {why}"
    if meta.get("prompt_file"):
        _, why = safe_join(drafts, meta["prompt_file"], {".txt"})
        if why:
            return None, f"prompt_file {meta['prompt_file']!r}: {why}"
    e = {k: meta[k] for k in META_FIELDS if k in meta and isinstance(meta[k], str)}
    e.setdefault("character", pathlib.PurePosixPath(meta["file"]).parts[0])
    e.setdefault("status", "검토 대기")
    e.setdefault("created", datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    return e, None


def add(drafts, metas, write):
    raw, err = read_index(drafts)
    if err:
        print("ERROR:", err)
        return 2
    have = {e.get("id") for e in raw if isinstance(e, dict)}
    new, skipped = [], []
    for mp in metas:
        try:
            meta = json.loads(pathlib.Path(mp).read_text(encoding="utf-8"))
        except (OSError, ValueError) as ex:
            skipped.append((str(mp), f"unreadable: {ex}"))
            continue
        e, why = entry_from_meta(drafts, meta)
        if why:
            skipped.append((str(mp), why))
        elif e["id"] in have:
            skipped.append((e["id"], "already in the index"))
        else:
            have.add(e["id"])
            new.append(e)
    for e in new:
        print(f"  ADD {e['id']}  ({e['file']})")
    for t, why in skipped:
        print(f"  skip {t}: {why}")
    print(f"{len(new)} to add, {len(skipped)} skipped, index has {len(raw)} entries")
    if not write or not new:
        print("preview only (use --write)" if new else "nothing to write")
        return 0
    path = drafts / "index.json"
    gen.assert_local(path)
    bak = drafts / f"index.json.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, bak)
    gen.write_json_atomic(path, raw + new)
    chk = json.loads(path.read_text(encoding="utf-8"))
    print(f"wrote {path} ({len(chk)} entries); backup {bak.name}")
    return 0 if len(chk) == len(raw) + len(new) else 2


def pick(drafts, ids, mark, write):
    raw, err = read_index(drafts)
    if err:
        print("ERROR:", err)
        return 2
    have = {e.get("id") for e in raw if isinstance(e, dict)}
    unknown = [i for i in ids if i not in have]
    if unknown:
        print("unknown ids (not in index):", unknown)
        return 1
    path = drafts / "selection.json"
    cur = {"revision": 0, "records": {}}
    if path.is_file():
        cur = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(cur, dict) or not isinstance(cur.get("revision"), int) or not isinstance(cur.get("records"), dict):
            print("selection.json has an unexpected shape; not touching it")
            return 2
    for i in ids:
        if mark == "clear":
            cur["records"].pop(i, None)
        else:
            cur["records"][i] = {"mark": mark, "updated": time.strftime("%Y-%m-%d %H:%M:%S")}
        print(f"  {i}: {mark}")
    cur["revision"] += 1
    if not write:
        print(f"preview only (use --write); revision would become {cur['revision']}")
        return 0
    if path.is_file():
        shutil.copy2(path, drafts / f"selection.json.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    gen.write_json_atomic(path, cur)
    print("wrote", path, "revision", cur["revision"])
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["lint", "add", "pick"])
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--drafts")
    ap.add_argument("--meta", nargs="*", default=[])
    ap.add_argument("--folder", help="drafts-relative folder; every <name>.json meta in it is considered")
    ap.add_argument("--mark", choices=sorted(MARKS | {"clear"}))
    ap.add_argument("--sheet")
    ap.add_argument("--id")
    ap.add_argument("--title")
    ap.add_argument("--group")
    ap.add_argument("--character")
    ap.add_argument("--prompt-file")
    ap.add_argument("--note", default="")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check-manager", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args(argv)
    drafts = gen.find_drafts(a.drafts)
    if a.cmd == "lint":
        return lint(drafts, a.check_manager, a.json)
    if a.cmd == "add":
        metas = list(a.meta)
        if a.folder:
            metas += sorted(p for p in (drafts / a.folder).glob("*.json"))
        if a.sheet:
            if not (a.id and a.title and a.group):
                ap.error("--sheet needs --id --title --group")
            tmp = gen.local_root(drafts) / "art" / "ledgers" / "_sheet_meta.tmp.json"
            meta = {"id": a.id, "character": a.character or pathlib.PurePosixPath(a.sheet).parts[0], "group": a.group, "title": a.title,
                    "file": a.sheet, "tool": "Codex CLI + Python", "model": gen.DEFAULT_MODEL, "status": "검토 대기", "note": a.note}
            if a.prompt_file:
                meta["prompt_file"] = a.prompt_file
            gen.write_json_atomic(tmp, meta)
            metas.append(tmp)
        if not metas:
            ap.error("--meta, --folder or --sheet required")
        return add(drafts, metas, a.write)
    if not a.ids or not a.mark:
        ap.error("pick needs ids and --mark")
    return pick(drafts, a.ids, a.mark, a.write)


if __name__ == "__main__":
    sys.exit(main())
