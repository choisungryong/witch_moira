#!/usr/bin/env python3
"""gen_queue.py self test. Run: python tools/art/test_gen_queue.py
Temp folders only (a fake _local/art/drafts, a fake repo root). Codex is never called (run is only used as a dry run)."""
import json
import pathlib
import shutil
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_queue as Q  # noqa: E402

FAILS = []
N = 0


def check(name, cond, detail=""):
    global N
    N += 1
    print(("ok   " if cond else "FAIL ") + name, "" if cond else detail)
    if not cond:
        FAILS.append(name)


def mk_item(root, iid, prompt, **kw):
    f = root / "tools" / "art" / "gen_queue_prompts" / f"{iid}.prompt.txt"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(prompt, encoding="utf-8")
    return Q.new_item(iid, status="prompt_ready", prompt_file=f"tools/art/gen_queue_prompts/{iid}.prompt.txt", **kw)


def main():
    # ---- lint
    ok = "A dark iron ring with one glowing orange core. No figure."
    check("lint clean", Q.lint_prompt(ok) == [])
    check("lint private name", any("private" in p for p in Q.lint_prompt("a ring for Witch Moira")))
    check("lint other work", any("other work" in p for p in Q.lint_prompt("like Diablo icons")))
    check("lint artist", any("other work" in p for p in Q.lint_prompt("painted by Greg Rutkowski")))
    check("lint style copy", any("style-copy" in p for p in Q.lint_prompt("in the style of an old master")))
    check("lint exposure", any("exposure" in p for p in Q.lint_prompt("a naked woman")))
    check("lint exposure negated", not any("exposure" in p for p in Q.lint_prompt("no sheer cloth, no nudity, not naked")))
    check("lint minor", any("minor" in p for p in Q.lint_prompt("a young girl")))
    check("lint minor negated", not any("minor" in p for p in Q.lint_prompt("no child's object")))
    check("lint person needs adult+opaque", len(Q.lint_prompt("a woman standing", has_person=True)) == 2)
    check("lint person ok", Q.lint_prompt("an adult woman in opaque thick cloth", has_person=True) == [])
    check("lint key string", any("key" in p for p in Q.lint_prompt("sk-abcdefghijklmnopqrstuvwxyz0123")))
    check("lint e-mail", any("e-mail" in p for p in Q.lint_prompt("mail a@b.com")))

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="genq-test-"))
    try:
        root = tmp / "repo"
        art = root / "chapter1" / "art"
        art.mkdir(parents=True)
        (art / "asset_slots.json").write_text(json.dumps({"slots": {
            "icon.x.a": {"planned": True, "file": "", "source": "spec A", "contract": {"size": [128, 128]}},
            "icon.x.b": {"planned": True, "file": "", "source": "spec B"},
            "icon.x.done": {"file": "x.png", "source": "done"}}}), encoding="utf-8")
        (art / "ASSET-LEDGER.json").write_text(json.dumps({"assets": [
            {"path": "ui/old.png", "status": "임시 그림"}, {"path": "ui/fine.png", "status": "등록됨"}]}, ensure_ascii=False), encoding="utf-8")
        (root / "docs").mkdir()
        (root / "docs" / "spec.md").write_text("intro\nneeds: new-frame | 카드 틀 | 512x512 | 투명 | 2 | 1\n```\nneeds: in-fence | no | x\n```\n- needs: second | 용도\n", encoding="utf-8")
        data = {"schema": 1, "items": [Q.new_item("have-b", slot="icon.x.b")]}
        found = Q.scan_candidates(data, root)
        ids = sorted(i["id"] for i in found)
        check("scan slots/ledger/docs", ids == ["new-frame", "replace-ui-old-png", "second", "slot-icon-x-a"], str(ids))
        nf = next(i for i in found if i["id"] == "new-frame")
        check("scan needs fields", (nf["count"], nf["priority"], nf["background"], nf["target"]) == (2, 1, "magenta", "512x512"))
        check("scan slot size", next(i for i in found if i["id"] == "slot-icon-x-a")["target"] == "128x128")
        data["items"] += found
        check("scan is idempotent", Q.scan_candidates(data, root) == [])

        # ---- selection
        a = mk_item(root, "a", ok, priority=2)
        b = mk_item(root, "b", ok, priority=1)
        c = mk_item(root, "c", ok, priority=0, route="paid-api", est_cost_usd=0.1)
        d = mk_item(root, "d", ok, priority=0, needs_user="choose")
        e = mk_item(root, "e", ok, priority=0, depends_on=["a"])
        f_ = mk_item(root, "f", "like Diablo", priority=0)
        g = mk_item(root, "g", ok, priority=0, refs=["no/such/ref.png"])
        h = Q.new_item("h", priority=0)
        h["status"] = "prompt_ready"
        q = {"schema": 1, "items": [a, b, c, d, e, f_, g, h]}
        got = [i["id"] for i in Q.pick_next(q, root, 0)]
        check("next order by priority, others excluded", got == ["b", "a"], str(got))
        check("next --only bypasses needs_user", [i["id"] for i in Q.pick_next(q, root, 0, ["d"])] == ["d"])
        why = Q.problems(f_, q, root)
        check("lint failure explains itself", any("lint" in w for w in why))
        check("missing reference explained", any("reference missing" in w for w in Q.problems(g, q, root)))
        check("paid route is never eligible", any("approval" in w for w in Q.problems(c, q, root, explicit=True)))
        a["status"] = "generated"
        check("depends_on satisfied by generated", Q.problems(e, q, root) == [])
        a["status"] = "prompt_ready"

        text = Q.compose(a, root)
        check("compose has preamble/bg/guard", "built-in image generation" in text and "#FF00FF" in text and "No text" in text and "1024x1024" in text)
        a2 = dict(a, refs=["x.png"], ref_role="same")
        check("compose same-character reference", "THIS SAME character" in Q.compose(a2, root))
        order = Q.work_order([b, a], tmp / "queue", root)
        check("work order lists prompt and save place", "## 1. b" in order and "## 2. a" in order and "queue/b/b-a1.png" in order.replace("\\", "/"))

        rep = Q.status_report(q, root)
        check("status counts", rep["total"] == 8 and rep["by_status"]["prompt_ready"] == 8)
        check("status approval/waiting/blocked", [x["id"] for x in rep["approval_needed"]] == ["c"] and "d" in rep["waiting_for_person"] and "f" in rep["blocked"])
        json.dumps(rep)

        # ---- file round trip, transitions, record
        qf = tmp / "queue.json"
        Q.save_queue(qf, q)
        check("save/load round trip", Q.load_queue(qf)["items"][0]["id"] == "a" and b"\r\n" not in qf.read_bytes())
        check("set ok", Q.main(["set", "a", "dropped", "--queue-file", str(qf), "--root", str(root), "--drafts", str(tmp / "_local/art/drafts")]) == 0 if (tmp / "_local/art/drafts").mkdir(parents=True) is None else False)
        check("set stored", Q.find(Q.load_queue(qf), "a")["status"] == "dropped")
        try:
            Q.main(["set", "b", "adopted", "--queue-file", str(qf), "--root", str(root), "--drafts", str(tmp / "_local/art/drafts")])
            check("adopt only from review_pending", False)
        except SystemExit:
            check("adopt only from review_pending", True)

        drafts = tmp / "_local" / "art" / "drafts"
        (drafts / "index.json").write_text("[]", encoding="utf-8")
        from PIL import Image, ImageDraw
        png = tmp / "fake.png"
        im = Image.new("RGB", (256, 256), (255, 0, 255))
        ImageDraw.Draw(im).ellipse((60, 60, 196, 196), fill=(200, 120, 40))
        im.save(png)
        chk = Q.autocheck(png)
        check("autocheck facts", chk["size"] == [256, 256] and chk["has_alpha_channel"] is False and chk["magenta_share"] > 0.4)
        rc = Q.main(["record", "b", "--file", str(png), "--bundle", "t", "--queue-file", str(qf), "--root", str(root), "--drafts", str(drafts)])
        itb = Q.find(Q.load_queue(qf), "b")
        check("record: status, result, provenance", rc == 0 and itb["status"] == "review_pending" and len(itb["results"]) == 1 and itb["provenance"]["ledger_status"] == "시안")
        check("record: result under queue folder", (tmp / "_local/art/queue/b/b-a1.png").is_file())
        idx = json.loads((drafts / "index.json").read_text(encoding="utf-8"))
        check("record: gallery bundle", any(e.get("group") == "대기열 · t" for e in idx) and len(idx) >= 2, str(len(idx)))
        rc = Q.main(["set", "b", "adopted", "--queue-file", str(qf), "--root", str(root), "--drafts", str(drafts)])
        check("adopt from review_pending", rc == 0 and Q.find(Q.load_queue(qf), "b")["status"] == "adopted")

        # dry run builds the config and never calls Codex
        rc = Q.main(["run", "--only", "b", "--queue-file", str(qf), "--root", str(root), "--drafts", str(drafts)])
        check("run without --execute is a dry run", rc == 0)
        rc = Q.main(["run", "--n", "1", "--execute", "--queue-file", str(qf), "--root", str(root), "--drafts", str(drafts)])
        check("run --execute without --yes stops", rc in (0, 3))
        # prune
        Q.main(["set", "a", "dropped", "--queue-file", str(qf), "--root", str(root), "--drafts", str(drafts)])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- the real queue file
    q = Q.load_queue(Q.QUEUE_FILE)
    ids = [i["id"] for i in q["items"]]
    check("real queue: ids unique", len(ids) == len(set(ids)))
    check("real queue: statuses valid", all(i["status"] in Q.STATUSES for i in q["items"]))
    bad = [i["id"] for i in q["items"] if i["status"] != "candidate" and not Q.read_prompt(i)]
    check("real queue: every started item has its prompt file", not bad, str(bad))
    dirty = {i["id"]: Q.lint_prompt(Q.compose(i), i.get("has_person", False)) for i in q["items"] if Q.read_prompt(i)}
    dirty = {k: v for k, v in dirty.items() if v}
    check("real queue: every prompt lints clean", not dirty, str(dirty))
    check("real queue: only the free route is ready", all(i["route"] == Q.FREE for i in q["items"] if i["status"] == "prompt_ready"))
    print(f"{N} checks, {len(FAILS)} failed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
