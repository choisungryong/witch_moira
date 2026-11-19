"""Picture queue: find the pictures the game will need, keep them as a list, and keep Codex making them ahead of time.

  python tools/art/gen_queue.py scan [--write]            # collect candidates (planned slots, ledger "임시/교체 예정", docs `needs:` lines)
  python tools/art/gen_queue.py status [--json [FILE]]    # one table: counts per state, blocked, waiting for a person, approval needed
  python tools/art/gen_queue.py lint [ID ...]             # prompt checks (banned words, private names, other works, adults only, exposure)
  python tools/art/gen_queue.py next --n 5 [--only ID ...] # prints the WORK ORDER for the next K items (free Codex path only)
  python tools/art/gen_queue.py run --n 5 [--only ID ...] [--execute --yes]   # dry run by default; with both flags calls Codex CLI, one at a time
  python tools/art/gen_queue.py record ID ... [--bundle NAME] [--file PATH]   # take results in, review sheet + gallery bundle "대기열 · NAME"
  python tools/art/gen_queue.py set ID STATUS [--note TEXT]                  # candidate|prompt_ready|generated|review_pending|adopted|dropped
  python tools/art/gen_queue.py prune [--yes]                                # delete dropped attempts' pictures and work folders (prompts stay)

The queue is tools/art/gen_queue.json; prompts are tools/art/gen_queue_prompts/<id>.prompt.txt (the item's own paragraph only;
`next`/`run` put the standard preamble, the background sentence and the common guard around it). Results live in
<_local>/art/queue/<id>/ and never in chapter1/art/ (adoption is a decision of the director and the user).

Free path only: an item whose route is not "codex-free" (paid API, Sunra) is shown as "approval needed" with its estimated cost
and is never executed here. Codex is called through gen.py (same command line, one attempt at a time, outside-change check).
Marker for documents: a line `needs: <id> | <use> | <size> | <background magenta|black|opaque> | <count> | <priority 1-5>` (outside code
fences) is picked up by `scan` as a candidate. Nothing is written to the repository except the queue file and prompt files.
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen  # noqa: E402
import prompt_lint  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
QUEUE_FILE = ROOT / "tools" / "art" / "gen_queue.json"
PROMPT_DIR = ROOT / "tools" / "art" / "gen_queue_prompts"
STATUSES = ["candidate", "prompt_ready", "generated", "review_pending", "adopted", "dropped"]
STATUS_KO = {"candidate": "후보", "prompt_ready": "프롬프트 준비", "generated": "생성됨", "review_pending": "검수 대기",
             "adopted": "채택", "dropped": "버림"}
FREE = "codex-free"
MAX_ATTEMPTS = 3
RESULT_NAME = "result.png"

BACKGROUNDS = {
    "magenta": "Background: one perfectly flat, solid magenta #FF00FF filling every pixel that is not the subject (no gradient, no vignette, "
               "no cast shadow or glow on the background, no magenta or pink inside the subject) so the background can be keyed out later.",
    "black": "Background: pure flat black #000000 everywhere outside the light itself; the picture is made only of light and will be "
             "composited with additive blending, so nothing dark may carry detail.",
    "opaque": "Full-bleed picture, no transparency and no frame around it.",
}
GUARD = ("No text, no letters, no numbers, no logo, no watermark, no signature. No modern objects. Nobody is recognisable as a real person "
         "and nothing copies another game, film or artist.")
PREAMBLE = ("Use your built-in image generation tool to create exactly one image and save it in the current directory as {out}. {refs}"
            "Do not write any code. Create no file other than {out}. Do not read, modify or delete any other file in this directory or "
            "elsewhere. When done, reply with the saved file name, its pixel size and whether it has an alpha channel.")

# ---------------------------------------------------------------- lint
PRIVATE = ["witch-moira", "witch moira", "moira", "twins", "choi sung", "ashen cloister", "잿빛 회랑", "d2r-combat", "c:\\", "/users/"]
OTHER_WORKS = ["diablo", "path of exile", "sacrata", "hades", "vampire survivors", "elden ring", "dark souls", "bloodborne", "berserk",
               "castlevania", "zelda", "pokemon", "magic the gathering", "hearthstone", "slay the spire", "isaac", "blizzard", "nintendo",
               "disney", "ghibli", "marvel", "genshin", "final fantasy", "warcraft", "street fighter", "game of thrones", "tolkien",
               "hollow knight", "dead cells", "darkest dungeon", "last epoch", "grim dawn", "torchlight", "디아블로", "사크라타", "하데스",
               "패스 오브 엑자일", "greg rutkowski", "frazetta", "beksinski", "giger", "amano", "miura", "artgerm", "mucha", "moebius",
               "wlop", "stalenhag", "mullins", "ruan jia", "sargent", "artstation"]
STYLE_COPY = [r"in the style of", r"inspired by", r"style of", r"reminiscent of", r"fan ?art", r"\bparody\b", r"lookalike", r"look-alike"]
LOOSE = [r"celebrit", r"actress", r"real person", r"likeness of", r"photo of a", r"supermodel"]
EXPOSURE = [r"\bnude\b", r"\bnaked\b", r"topless", r"nipple", r"areola", r"genital", r"underboob", r"sideboob", r"lingerie", r"bikini",
            r"thong", r"see-through", r"\bsheer\b", r"bare breast", r"cleavage", r"fetish", r"bdsm", r"erotic", r"sexual"]
MINOR = [r"\bchild", r"\bkid\b", r"\bgirl\b", r"\bboy\b", r"teen", r"schoolgirl", r"loli", r"\bminor\b", r"\bbaby\b", r"\btoddler"]
NEGATION = re.compile(r"(?:\bno\b|\bnobody\b|\bnot\b|\bnever\b|\bwithout\b|\bavoid|\bdo not\b|\bdon't\b|\bnothing\b|\bnone\b)[^.\n]{0,70}$", re.I)


def _hits(text, patterns, negation_excuses):
    out = []
    for pat in patterns:
        for m in re.finditer(pat, text, re.I):
            before = text[max(0, m.start() - 90):m.start()]
            if negation_excuses and NEGATION.search(before):
                continue
            out.append(m.group(0))
    return out


def lint_prompt(text, has_person=False):
    """-> list of problems (strings). Empty = clean."""
    probs = []
    low = text.lower()
    words, _ = prompt_lint.load_banned()
    for w in prompt_lint.text_hits(text, words):
        probs.append(f"banned word / key-like string: {w}")
    for w in PRIVATE:
        if w in low:
            probs.append(f"private or project name: {w}")
    if re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", text):
        probs.append("e-mail address")
    for w in OTHER_WORKS:
        if re.search(r"(?<![a-z])" + re.escape(w) + r"(?![a-z])", low):
            probs.append(f"other work / artist name: {w}")
    for h in _hits(text, STYLE_COPY, False):
        probs.append(f"style-copy phrase: {h}")
    for h in _hits(text, LOOSE, True):
        probs.append(f"real-person phrase: {h}")
    for h in _hits(text, EXPOSURE, True):
        probs.append(f"exposure word without a negation: {h}")
    for h in _hits(text, MINOR, True):
        probs.append(f"minor-reading word without a negation: {h}")
    if has_person:
        if "adult" not in low:
            probs.append("person item without the word 'adult'")
        if "opaque" not in low:
            probs.append("person item without 'opaque' (clothing over chest and hips must be stated opaque)")
    return probs


# ---------------------------------------------------------------- file helpers
def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def load_queue(path):
    path = pathlib.Path(path)
    if not path.exists():
        return {"schema": 1, "updated": now(), "items": []}
    return json.loads(path.read_text(encoding="utf-8"))


def save_queue(path, data):
    path = pathlib.Path(path)
    data["updated"] = now()
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def find(data, iid):
    for it in data["items"]:
        if it["id"] == iid:
            return it
    raise SystemExit(f"unknown id: {iid}")


def new_item(iid, **kw):
    it = {"id": iid, "title": kw.pop("title", iid), "use": "", "source": "", "canvas": "1024x1024", "target": "", "background": "magenta",
          "count": 1, "priority": 3, "status": "candidate", "route": FREE, "est_cost_usd": None, "prompt_file": "", "refs": [],
          "kind": "icon", "has_person": False, "ref_role": "style", "slot": "", "needs_user": "", "depends_on": [], "blocked": "", "notes": "",
          "attempts": 0, "results": [], "last_error": "", "history": [{"at": now(), "status": "candidate"}]}
    it.update(kw)
    return it


def set_status(it, status, note=""):
    if status not in STATUSES:
        raise SystemExit(f"status must be one of {STATUSES}")
    it["status"] = status
    it["history"].append({"at": now(), "status": status, **({"note": note} if note else {})})


def resolve_ref(r, root):
    """absolute | repo-relative | relative to a _local/art/drafts folder (the root or an ancestor, for worktrees) -> Path or None."""
    r = pathlib.Path(r)
    if r.is_absolute():
        return r if r.exists() else None
    root = pathlib.Path(root)
    for base in (root, *[b / "_local" / "art" / "drafts" for b in (root, *root.parents)]):
        if (base / r).exists():
            return base / r
    return None


def prompt_path(it, root=ROOT):
    return (pathlib.Path(root) / it["prompt_file"]) if it.get("prompt_file") else None


def read_prompt(it, root=ROOT):
    p = prompt_path(it, root)
    return p.read_text(encoding="utf-8").strip() if p and p.is_file() else ""


def compose(it, root=ROOT, ref_names=None):
    """The full text sent to Codex."""
    refs = ""
    if it.get("refs"):
        names = "; ".join(f"({i + 1}) {n}" for i, n in enumerate(ref_names or [pathlib.Path(r).name for r in it["refs"]]))
        if it.get("ref_role") == "same":
            refs = (f"The attached image(s), in this order: {names}. Reference (1) is the previous version of THIS SAME character: keep her face, hair, horns, crown, "
                    "colours and painting style; change only what the description below says. ")
        else:
            refs = (f"The attached image(s) are references for painting style and shape language only, in this order: {names}. "
                    "Do not copy any character, face or object from them. ")
    w, h = (it["canvas"].split("x") + ["", ""])[:2]
    parts = [PREAMBLE.format(out=RESULT_NAME, refs=refs), f"Canvas: {w}x{h} pixels.", read_prompt(it, root),
             BACKGROUNDS.get(it["background"], it["background"]), GUARD]
    return "\n\n".join(p for p in parts if p) + "\n"


def autocheck(path):
    """Mechanical facts about a result (size, alpha, corner colour, magenta share). Not a verdict."""
    from PIL import Image
    import numpy as np
    im = Image.open(path)
    rgba = im.convert("RGBA")
    a = np.asarray(rgba, dtype=np.int32)
    rgb = a[..., :3]
    mag = ((rgb[..., 0] > 200) & (rgb[..., 2] > 200) & (rgb[..., 1] < 70)).mean()
    corners = [tuple(int(x) for x in rgb[y, x]) for y, x in ((0, 0), (0, -1), (-1, 0), (-1, -1))]
    return {"size": list(im.size), "mode": im.mode, "has_alpha_channel": "A" in im.mode,
            "magenta_share": round(float(mag), 3), "corner_rgb": corners, "dark_share": round(float((rgb.max(axis=2) < 40).mean()), 3),
            "stddev": round(float(rgb.std()), 1)}


# ---------------------------------------------------------------- scan
NEEDS_RE = re.compile(r"^\s*(?:[-*>]\s*)*(?:<!--\s*)?needs:\s*(.+?)(?:\s*-->)?\s*$")
LEDGER_RE = re.compile(r"임시|교체\s*예정|교체\s*필요|placeholder|temporary", re.I)


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def scan_candidates(data, root):
    root = pathlib.Path(root)
    have_ids = {i["id"] for i in data["items"]}
    have_slots = {i["slot"] for i in data["items"] if i.get("slot")}
    out = []
    slots_file = root / "chapter1" / "art" / "asset_slots.json"
    if slots_file.is_file():
        for sid, s in json.loads(slots_file.read_text(encoding="utf-8"))["slots"].items():
            if s.get("planned") and not s.get("file") and sid not in have_slots:
                size = (s.get("contract") or {}).get("size")
                out.append(new_item("slot-" + slug(sid), title=sid, use=f"자리 {sid} (파일 없음, 임시 문양)", source=f"asset_slots.json planned: {s.get('source', '')[:90]}",
                                    slot=sid, canvas="1024x1024", target=("x".join(map(str, size)) if size else "")))
    led = root / "chapter1" / "art" / "ASSET-LEDGER.json"
    if led.is_file():
        for a in json.loads(led.read_text(encoding="utf-8")).get("assets", []):
            txt = " ".join(str(a.get(k, "")) for k in ("status", "notes", "origin", "postprocess"))
            m = LEDGER_RE.search(txt)
            iid = "replace-" + slug(a["path"])
            if m and iid not in have_ids:
                out.append(new_item(iid, title=a["path"], use=f"원장에 '{m.group(0)}'로 적힌 파일의 교체", source=f"ASSET-LEDGER.json {a['path']}"))
    docs = root / "docs"
    for md in sorted(docs.rglob("*.md")) if docs.is_dir() else []:
        fenced = False
        for n, line in enumerate(md.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            m = None if fenced else NEEDS_RE.match(line)
            if not m:
                continue
            f = [x.strip() for x in m.group(1).split("|")]
            f += [""] * (6 - len(f))
            iid = slug(f[0]) or "doc-" + md.stem
            if iid in have_ids or any(o["id"] == iid for o in out):
                continue
            bg = {"투명": "magenta", "magenta": "magenta", "black": "black", "검정": "black", "opaque": "opaque", "불투명": "opaque"}.get(f[3], "magenta")
            out.append(new_item(iid, title=f[0], use=f[1], source=f"{md.relative_to(root).as_posix()}:{n} needs:", target=f[2], background=bg,
                                count=int(f[4]) if f[4].isdigit() else 1, priority=int(f[5]) if f[5].isdigit() else 3))
    return out


# ---------------------------------------------------------------- selection
def problems(it, data, root, explicit=False):
    """Why an item cannot be handed out now (empty list = eligible)."""
    why = []
    if it["route"] != FREE:
        why.append(f"route {it['route']}: approval needed")
    if it["status"] != "prompt_ready":
        why.append(f"status {it['status']}")
    if it.get("needs_user") and not explicit:      # naming the id on the command line is the person's go-ahead
        why.append("waits for a person: " + it["needs_user"])
    if it.get("blocked"):
        why.append("blocked: " + it["blocked"])
    for d in it.get("depends_on", []):
        dep = next((x for x in data["items"] if x["id"] == d), None)
        if not dep or dep["status"] not in ("generated", "review_pending", "adopted"):
            why.append(f"depends on {d}")
    p = prompt_path(it, root)
    if not p or not p.is_file():
        why.append("no prompt file")
    else:
        lp = lint_prompt(compose(it, root), it.get("has_person", False))
        why += ["lint: " + x for x in lp]
    for r in it.get("refs", []):
        if not resolve_ref(r, root):
            why.append(f"reference missing: {r}")
    if it["attempts"] >= MAX_ATTEMPTS:
        why.append(f"{it['attempts']} attempts already (max {MAX_ATTEMPTS}; use set to reset)")
    return why


def pick_next(data, root, n, only=None):
    order = {it["id"]: i for i, it in enumerate(data["items"])}
    pool = [it for it in data["items"] if (not only or it["id"] in only)]
    ok = [it for it in pool if not problems(it, data, root, explicit=bool(only))]
    ok.sort(key=lambda it: (it["priority"], order[it["id"]]))
    return ok[:n] if n else ok


def work_order(items, qroot, root):
    L = ["WORK ORDER (Codex, image generation) -- one picture per item, one at a time.",
         "Rules: AGENTS.md role 'image generation'. Save only the image, named as given, in the folder given. No code. No other files.",
         "Free path only (Codex CLI, ChatGPT login). No API, no Sunra, no downloads. Adults only. Exposure no higher than the approved art.", ""]
    for i, it in enumerate(items, 1):
        out = pathlib.Path(qroot) / it["id"]
        L += [f"## {i}. {it['id']}  -  {it['title']}  (priority {it['priority']}, attempt {it['attempts'] + 1}/{MAX_ATTEMPTS})",
              f"use      : {it['use']}", f"from     : {it['source']}",
              f"canvas   : {it['canvas']}   final target: {it['target'] or '-'}   background: {it['background']}   count wanted: {it['count']}",
              f"refs     : {', '.join(it['refs']) or '-'}", f"save to  : {out.as_posix()}/{it['id']}-a{it['attempts'] + 1}.png (file the tool names; Codex itself saves {RESULT_NAME} in its work folder)",
              "review   : opens and reads at 128/64/40 px (icons) or at thumbnail size (frames), background really flat (no gradient / magenta inside), "
              "no text or letters, one saturated colour on a dark neutral, no banned element, adults only.",
              "prompt   :", ""]
        L += ["    " + ln for ln in compose(it, root).splitlines()] + [""]
    L.append("Run: python tools/art/gen_queue.py run --only " + " ".join(i["id"] for i in items) + " --execute --yes")
    return "\n".join(L)


# ---------------------------------------------------------------- run / record
class Lock:
    def __init__(self, path):
        self.path = pathlib.Path(path)

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.path.exists() and time.time() - self.path.stat().st_mtime < 3 * 3600:
            raise SystemExit(f"another gen_queue run holds {self.path} (remove it if that run is gone)")
        self.path.write_text(str(os.getpid()), encoding="utf-8")
        return self

    def __exit__(self, *a):
        self.path.unlink(missing_ok=True)


LIMIT_RE = re.compile(r"usage limit|rate limit|quota|too many requests|429|try again (?:later|in)|limit reached", re.I)


def run_one(it, qroot, drafts, root, execute):
    """One attempt through gen.py. Returns (png path or None, note)."""
    name = f"{it['id']}-a{it['attempts'] + 1}"
    out = pathlib.Path(qroot) / it["id"]
    cfg = {"batch": f"queue-{name}", "folder": it["id"], "group": "대기열", "output_name": RESULT_NAME, "model": gen.DEFAULT_MODEL, "id_prefix": "queue-",
           "refs": [str(resolve_ref(r, root)) for r in it.get("refs", [])],
           "note": f"대기열 {it['id']}: {it['use']}"[:200],
           "items": [{"name": name, "title": it["title"],
                      "template": [{"text": compose(it, root, [pathlib.Path(r).name for r in it.get("refs", [])]).rstrip()}]}]}
    cfg_path = out / f"{name}.gen.json"
    out.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
    argv = [str(cfg_path), "--drafts", str(qroot)] + (["--execute", "--yes"] if execute else [])
    gen.main(argv)
    png = out / f"{name}.png"
    log = out / f"{name}.run.log"
    note = ""
    if execute and not png.exists() and log.exists():
        tail = log.read_text(encoding="utf-8", errors="replace")[-3000:]
        if LIMIT_RE.search(tail):
            note = "LIMIT"
    return (png if png.exists() else None), note


def cleanup_work(out, name):
    shutil.rmtree(out / "work" / name, ignore_errors=True)
    w = out / "work"
    if w.is_dir() and not any(w.iterdir()):
        w.rmdir()


def collect_results(it, qroot, add_file=None):
    """Attach new <id>-aN.png files (or an external file) to the item. Returns the new paths."""
    out = pathlib.Path(qroot) / it["id"]
    if add_file:
        n = max([int(m.group(1)) for r in it["results"] for m in [re.search(r"-a(\d+)\.png$", r)] if m] + [it["attempts"]]) + 1
        out.mkdir(parents=True, exist_ok=True)
        dst = out / f"{it['id']}-a{n}.png"
        shutil.copy2(add_file, dst)
        it["attempts"] = max(it["attempts"], n)
    new = []
    for p in sorted(out.glob(f"{it['id']}-a*.png")):
        if str(p) not in it["results"]:
            it["results"].append(str(p))
            new.append(p)
            m = re.search(r"-a(\d+)\.png$", p.name)
            it["attempts"] = max(it["attempts"], int(m.group(1)))
    return new


def provenance(it, png, prompt_text):
    import hashlib
    return {"file": str(png), "sha256": hashlib.sha256(pathlib.Path(png).read_bytes()).hexdigest(), "tool": "Codex CLI (built-in image generation, ChatGPT login)",
            "model": gen.DEFAULT_MODEL, "date": datetime.date.today().isoformat(), "prompt_file": it["prompt_file"],
            "prompt_sha256": gen.sha(prompt_text), "postprocess": "none yet (original, background not removed)", "ledger_status": "시안",
            "license_note": "terms not checked; not marked deployable (release_cleared stays false)"}


def make_review(items, drafts, bundle, qroot):
    """Review sheets (icon kind and image kind separately) + gallery bundle. Returns text lines."""
    import review_sheet
    import gallery
    lines = []
    lroot = gen.local_root(drafts)
    group = f"대기열 · {bundle}"
    dest = pathlib.Path(drafts) / "queue" / bundle
    dest.mkdir(parents=True, exist_ok=True)
    from PIL import Image
    for kind in ("icon", "image"):
        rows = [{"id": it["id"], "file": it["results"][-1]} for it in items if it["results"] and (it["kind"] == "icon") == (kind == "icon")]
        if not rows:
            continue
        rows_file = pathlib.Path(qroot) / f"_rows-{bundle}-{kind}.json"
        rows_file.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8", newline="\n")
        name = f"queue-{bundle}-{kind}"
        review_sheet.main(["--list", str(rows_file), "--name", name, "--kind", kind, "--drafts", str(drafts)])
        rows_file.unlink()
        sheet = lroot / "art" / "review" / f"{name}.jpg"
        shutil.copy2(sheet, dest / f"sheet-{kind}.jpg")
        gen.write_json_atomic(dest / f"sheet-{kind}.json", {"id": f"queue-{bundle}-sheet-{kind}", "character": "queue", "group": group, "title": f"검수 시트 ({kind})",
                                                           "file": f"queue/{bundle}/sheet-{kind}.jpg", "tool": "Codex CLI + Python", "model": gen.DEFAULT_MODEL,
                                                           "created": now(), "status": "검토 대기", "note": "원본·가공·작은 크기·실루엣 (review_sheet.py)"})
        lines.append(f"sheet: {sheet}")
    for it in items:
        if not it["results"]:
            continue
        src = pathlib.Path(it["results"][-1])
        im = Image.open(src).convert("RGB")
        im.thumbnail((1024, 1024))
        jpg = dest / (src.stem + ".jpg")
        im.save(jpg, quality=88)
        ptxt = f"{it['id']}.prompt.txt"
        (dest / ptxt).write_text(compose(it), encoding="utf-8", newline="\n")
        gen.write_json_atomic(dest / (src.stem + ".json"), {"id": f"queue-{src.stem}", "character": "queue", "group": group, "title": f"{it['id']} · {it['title']}"[:80],
                                                            "file": f"queue/{bundle}/{jpg.name}", "prompt_file": f"queue/{bundle}/{ptxt}", "tool": "Codex CLI",
                                                            "model": gen.DEFAULT_MODEL, "created": now(), "status": "검토 대기",
                                                            "note": f"대기열 시안. 원본 {src.name} ({it['canvas']}) 는 _local/art/queue/{it['id']}/ 에 있음"})
    rc = gallery.main(["add", "--folder", f"queue/{bundle}", "--drafts", str(drafts), "--write"])
    lines.append(f"gallery bundle '{group}': gallery.py add exit {rc}")
    return lines


# ---------------------------------------------------------------- status
def status_report(data, root):
    by = {s: [] for s in STATUSES}
    for it in data["items"]:
        by[it["status"]].append(it["id"])
    approval = [{"id": i["id"], "route": i["route"], "est_cost_usd": i["est_cost_usd"]} for i in data["items"] if i["route"] != FREE and i["status"] not in ("adopted", "dropped")]
    waiting_person = [i["id"] for i in data["items"] if i["status"] == "review_pending" or (i.get("needs_user") and i["status"] not in ("adopted", "dropped"))]
    no_prompt = [i["id"] for i in data["items"] if i["status"] == "candidate" and not i.get("prompt_file")]
    blocked = {}
    for i in data["items"]:
        if i["status"] in ("adopted", "dropped"):
            continue
        if i.get("blocked") or i.get("needs_user"):
            blocked[i["id"]] = i.get("blocked") or "waits: " + i["needs_user"]
        elif i["status"] == "prompt_ready":
            w = [x for x in problems(i, data, root) if x.startswith(("lint", "reference", "depends", "no prompt"))]
            if w:
                blocked[i["id"]] = "; ".join(w)
    ready = [i["id"] for i in pick_next(data, root, 0)]
    return {"updated": data.get("updated"), "total": len(data["items"]), "by_status": {s: len(v) for s, v in by.items()},
            "ids_by_status": by, "ready_for_codex": ready, "approval_needed": approval,
            "estimated_cost_known_usd": round(sum(a["est_cost_usd"] or 0 for a in approval), 3),
            "waiting_for_person": waiting_person, "candidates_without_prompt": no_prompt, "blocked": blocked}


def status_table(rep, data):
    L = [f"queue: {rep['total']} items (updated {rep['updated']})", "", "status            count", "----------------  -----"]
    for s in STATUSES:
        L.append(f"{s:<16}  {rep['by_status'][s]:>5}   {STATUS_KO[s]}")
    L += ["", f"ready for Codex now ({len(rep['ready_for_codex'])}): " + ", ".join(rep["ready_for_codex"][:14]) + (" ..." if len(rep["ready_for_codex"]) > 14 else ""),
          f"candidates without prompt ({len(rep['candidates_without_prompt'])}): " + ", ".join(rep["candidates_without_prompt"][:10]) + (" ..." if len(rep["candidates_without_prompt"]) > 10 else ""),
          f"waiting for a person ({len(rep['waiting_for_person'])}): " + ", ".join(rep["waiting_for_person"][:14]),
          f"approval needed ({len(rep['approval_needed'])}): " + "; ".join(f"{a['id']} [{a['route']}] ~${a['est_cost_usd']}" for a in rep["approval_needed"]),
          f"blocked ({len(rep['blocked'])}):"]
    L += [f"   {k}: {v}" for k, v in rep["blocked"].items()]
    return "\n".join(L)


# ---------------------------------------------------------------- main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["scan", "status", "lint", "next", "run", "record", "set", "prune"])
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--queue-file", default=str(QUEUE_FILE))
    ap.add_argument("--root", default=str(ROOT), help="repository root (planned slots, ledger, docs, prompts)")
    ap.add_argument("--drafts")
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--json", nargs="?", const="-")
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--bundle")
    ap.add_argument("--file")
    ap.add_argument("--note", default="")
    ap.add_argument("--no-gallery", action="store_true")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    root = pathlib.Path(a.root)
    data = load_queue(a.queue_file)
    only = a.only or a.ids

    if a.cmd == "scan":
        found = scan_candidates(data, root)
        for it in found:
            print(f"  + {it['id']}  [{it['source']}]  {it['use']}")
        print(f"{len(found)} new candidates ({len(data['items'])} in the queue)")
        if a.write and found:
            data["items"] += found
            save_queue(a.queue_file, data)
            print("wrote", a.queue_file)
        elif found:
            print("preview only (use --write)")
        return 0

    if a.cmd == "status":
        rep = status_report(data, root)
        if a.json:
            text = json.dumps(rep, ensure_ascii=False, indent=1)
            if a.json == "-":
                print(text)
            else:
                pathlib.Path(a.json).parent.mkdir(parents=True, exist_ok=True)
                pathlib.Path(a.json).write_text(text + "\n", encoding="utf-8", newline="\n")
                print("wrote", a.json)
        else:
            print(status_table(rep, data))
        return 0

    if a.cmd == "lint":
        bad = 0
        for it in data["items"]:
            if only and it["id"] not in only:
                continue
            if not read_prompt(it, root):
                continue
            pr = lint_prompt(compose(it, root), it.get("has_person", False))
            bad += bool(pr)
            print(f"{it['id']}: " + ("clean" if not pr else "; ".join(pr)))
        return 1 if bad else 0

    drafts = gen.find_drafts(a.drafts)
    qroot = gen.local_root(drafts) / "art" / "queue"

    if a.cmd == "next":
        items = pick_next(data, root, a.n, only or None)
        if not items:
            print("nothing eligible (see: status)")
            return 0
        text = work_order(items, qroot, root)
        if a.out:
            gen.write_text(a.out, text)
            print("wrote", a.out)
        else:
            print(text)
        return 0

    if a.cmd == "run":
        items = pick_next(data, root, a.n, only or None)
        for iid in only:
            if iid not in [i["id"] for i in items]:
                it = find(data, iid)
                print(f"skip {iid}: " + "; ".join(problems(it, data, root, explicit=True)))
        if not items:
            print("nothing eligible")
            return 0
        if a.execute and not a.yes:
            print(f"{len(items)} attempts would call Codex CLI (free, one at a time): " + ", ".join(i["id"] for i in items) + "\nNothing was run. Add --yes.")
            return 3
        qroot.mkdir(parents=True, exist_ok=True)
        with Lock(qroot / ".run.lock"):
            for it in items:
                png, note = run_one(it, qroot, drafts, root, a.execute)
                if not a.execute:
                    continue
                it["attempts"] += 1
                name = f"{it['id']}-a{it['attempts']}"
                if png:
                    it["results"].append(str(png))
                    it["last_error"] = ""
                    it["checks"] = autocheck(png)
                    it["provenance"] = provenance(it, png, compose(it, root))
                    set_status(it, "generated", name)
                    cleanup_work(png.parent, name)
                else:
                    it["last_error"] = "no image" + (" (limit hit)" if note == "LIMIT" else "")
                    it["history"].append({"at": now(), "status": it["status"], "note": f"{name}: {it['last_error']}"})
                save_queue(a.queue_file, data)
                if note == "LIMIT":
                    print("usage limit detected; stopping the batch. Resume later with the same command.")
                    break
        print("queue saved" if a.execute else "dry run only: nothing was generated")
        return 0

    if a.cmd == "record":
        if not a.ids:
            ap.error("record needs ids")
        items = [find(data, i) for i in a.ids]
        for it in items:
            new = collect_results(it, qroot, a.file if len(items) == 1 else None)
            for p in new:
                it["checks"] = autocheck(p)
                it["provenance"] = provenance(it, p, compose(it, root))
            if it["results"] and it["status"] in ("candidate", "prompt_ready"):
                set_status(it, "generated", "record")
            print(f"{it['id']}: {len(new)} new, {len(it['results'])} results, attempts {it['attempts']}")
        have = [i for i in items if i["results"]]
        bundle = a.bundle or "묶음-" + datetime.date.today().strftime("%Y%m%d")
        if have and not a.no_gallery:
            for line in make_review(have, drafts, bundle, qroot):
                print(line)
            for it in have:
                if it["status"] == "generated":
                    set_status(it, "review_pending", f"sheet+gallery {bundle}")
        save_queue(a.queue_file, data)
        return 0

    if a.cmd == "set":
        if len(a.ids) != 2:
            ap.error("set needs: ID STATUS")
        it = find(data, a.ids[0])
        if a.ids[1] == "adopted" and it["status"] != "review_pending":
            raise SystemExit("adopt only from review_pending (the director and the user decide)")
        set_status(it, a.ids[1], a.note)
        if a.ids[1] == "prompt_ready":
            it["attempts"] = 0 if a.note.startswith("reset") else it["attempts"]
        save_queue(a.queue_file, data)
        print(f"{it['id']} -> {it['status']}")
        if it["status"] == "adopted" and it["results"]:
            print("ledger step (director/asset-producer, after the file is placed under chapter1/art and the license is checked):\n"
                  f"  python tools/art/asset_ledger.py add <path under chapter1/art> --source-type ai_generated --origin 'Codex CLI queue item {it['id']}' "
                  f"--license <checked terms> --model {gen.DEFAULT_MODEL} --prompt-file {it['prompt_file']} --postprocess <what was done>")
        return 0

    if a.cmd == "prune":
        freed = 0
        for it in data["items"]:
            if it["status"] != "dropped":
                continue
            out = qroot / it["id"]
            for p in list(out.glob("*.png")) + list(out.glob("*.last.txt")) + list(out.glob("*.run.log")):
                freed += p.stat().st_size
                print(("delete " if a.yes else "would delete ") + str(p))
                if a.yes:
                    p.unlink()
            if a.yes:
                shutil.rmtree(out / "work", ignore_errors=True)
                it["results"] = []
        if a.yes:
            save_queue(a.queue_file, data)
        print(f"{freed / 1e6:.1f} MB " + ("freed" if a.yes else "reclaimable (use --yes)"))
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
