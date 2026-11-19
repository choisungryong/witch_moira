"""HUD layout check: reads Control dumps and lists layout violations.

    python tools/dev/hud_layout_check.py <dump.json> [<dump.json> ...] [--allow tools/dev/hud_layout_allow.json]
        [--only <label glob>] [--combat <label regex>] [--min-font-720 11.2] [--json <out.json>] [--strict]

Input: the JSON of hud_dump.gd (--dump=<file> with --dump-extra) or of scene_shot.gd (always with the extra fields).
A dump written without --dump-extra still gets overlap and screen-edge checks on whole rectangles; text, font, clip and
alpha checks are skipped (and said so).

Checks (kind names are what the allow list matches):
  overlap        two visible content controls that are not parent and child overlap by 2 px or more in both directions.
                 Content = text, button, texture, range, line edit. A label counts by its text, not by its whole box.
                 Windows laid over other windows (a branch that covers 30% of the screen or more) are layers, not overlaps.
  offscreen      a visible control is cut by the screen edge (after its own clipping ancestors).
  center         a content control inside the middle 60% x 60% of the screen. Only for combat moments (meta.combat,
                 or a label that matches --combat). A scene dump is never a combat moment.
  text_overflow  a label or button whose text does not fit its own box: lines cut, text taller or wider than the box,
                 or a control smaller than its minimum size. Text cut with an ellipsis on purpose is "text_trimmed"
                 (reported, not counted unless --strict).
  clipped        a button cut by a clipping ancestor (a scroll list's edge, a window that cuts its content). Information,
                 not counted unless --strict: scrolling lists always show a cut item, but a cut main button is worth a look.
  font_small     text whose size at 720p (code size x 720/canvas height) is under --min-font-720 (default 11.2,
                 the 720p floor of docs/specs/A4: code 14).

Exit code: 0 no violation, 1 violations, 2 bad arguments or input.
"""
import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

HEADER = "위반 0은 HUD 통과가 아니다. 바닥 글자(Label3D)와 셰이더로 잘리는 것은 보지 못한다."
EXTRA_NOTE = ("또 보지 못하는 것: 컨트롤이 _draw로 직접 그리는 글·그림(스킬 트리, 아이콘, 구슬), 가려진 뒤쪽 화면, "
              "색 대비, 글자 모양. 그림은 사람이 본다.")
TEXT_CLASSES = {"Label", "RichTextLabel", "LineEdit"}
BUTTON_CLASSES = {"Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton", "LinkButton", "ColorPickerButton"}
PICTURE_CLASSES = {"TextureRect", "ProgressBar", "TextureProgressBar", "TextureButton", "HSlider", "VSlider", "ScrollBar", "HScrollBar", "VScrollBar"}
DEFAULT_COMBAT = r"^(playing|upgrade-prompt|discovery|flow-playing|profile-rejected-nosave-playing|end-playing)"
INFO_KINDS = ("text_trimmed", "clipped")
LAYER_AREA = 0.30
EPS = 0.5


def alpha_of(row):
    if "alpha" in row:
        return float(row["alpha"])
    mod = str(row.get("modulate", "ffffffff"))
    return int(mod[6:8], 16) / 255.0 if len(mod) >= 8 else 1.0


def inter(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    return (x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0))


def clean_name(row):
    """Godot names unnamed nodes @Class@123: the number changes every run, so the path uses <Class> instead."""
    m = re.fullmatch(r"@([A-Za-z0-9]+)@\d+", str(row["name"]))
    return "<%s>" % m.group(1) if m else str(row["name"])


class Moment:
    def __init__(self, label, rows, meta, canvas):
        self.label, self.rows, self.meta, self.canvas = label, rows, meta, canvas
        self.extra = any("min" in r for r in rows)
        self.parent = []
        stack = []
        for i, r in enumerate(rows):
            while stack and rows[stack[-1]]["d"] >= r["d"]:
                stack.pop()
            self.parent.append(stack[-1] if stack else -1)
            stack.append(i)
        self.chain = []
        for i in range(len(rows)):
            c, p = [], i
            while p >= 0:
                c.append(p)
                p = self.parent[p]
            self.chain.append(c[::-1])
        self.path = []
        for i, r in enumerate(rows):
            names = [clean_name(rows[k]) for k in self.chain[i]]
            self.path.append("/".join(names))

    def clip(self, i):
        r = self.rows[i]
        box = (r["x"], r["y"], r["w"], r["h"])
        if "clip" in r:
            box = inter(box, tuple(r["clip"]))
        return box

    def shown(self, i):
        r = self.rows[i]
        if not r["visible"] or r["w"] < EPS or r["h"] < EPS or alpha_of(r) <= 0.05:
            return False
        # a control hidden through a faded ancestor is covered by "alpha" in extra dumps; without it, check the chain
        if not self.extra:
            return all(alpha_of(self.rows[k]) > 0.05 for k in self.chain[i])
        return True

    def is_content(self, i):
        r = self.rows[i]
        cls = r["class"]
        if cls in TEXT_CLASSES or cls in BUTTON_CLASSES:
            return bool(str(r.get("text", "")).strip()) or cls in BUTTON_CLASSES
        return cls in PICTURE_CLASSES

    def box(self, i):
        """The area the control really paints: a label's text box, else its whole rectangle, then clipped."""
        r = self.rows[i]
        x, y, w, h = r["x"], r["y"], r["w"], r["h"]
        if r["class"] == "Label" and "tw" in r and str(r.get("text", "")).strip():
            tw = min(float(r["tw"]), w) if int(r.get("wrap", 0)) == 0 else min(float(r["tw"]), w)
            th = min(float(r["th"]), h) if float(r["th"]) > 0 else h
            ha, va = int(r.get("ha", 0)), int(r.get("va", 0))
            bx = x if ha in (0, 3) else (x + (w - tw) / 2 if ha == 1 else x + w - tw)
            by = y if va in (0, 3) else (y + (h - th) / 2 if va == 1 else y + h - th)
            x, y, w, h = bx, by, tw, th
        box = (x, y, w, h)
        if "clip" in r:
            box = inter(box, tuple(r["clip"]))
        return box

    def layered(self, i, j):
        """True when i and j sit in different top-level branches and the later one is a big window laid over the other."""
        ci, cj = self.chain[i], self.chain[j]
        k = 0
        while k < min(len(ci), len(cj)) and ci[k] == cj[k]:
            k += 1
        if k >= len(ci) or k >= len(cj):
            return True  # ancestor relation
        later = max(ci[k], cj[k])
        r = self.rows[later]
        return r["w"] * r["h"] >= LAYER_AREA * self.canvas[0] * self.canvas[1]

    def describe(self, i):
        r = self.rows[i]
        text = str(r.get("text", "")).replace("\n", " / ")
        if len(text) > 28:
            text = text[:27] + "…"
        tail = ' "%s"' % text if text else ""
        return "%s [%s%s] %dx%d at (%d,%d)" % (self.path[i], r["class"], tail, round(r["w"]), round(r["h"]), round(r["x"]), round(r["y"]))


def check(m, args):
    out = []
    rows, (cw, ch) = m.rows, m.canvas
    shown = [i for i in range(len(rows)) if m.shown(i)]
    shown_set = set(shown)
    content = [i for i in shown if m.is_content(i)]
    combat = bool(m.meta.get("combat")) or (m.meta.get("combat") is None and re.search(args.combat, m.label) is not None)

    # overlap
    for a_pos, i in enumerate(content):
        bi = m.box(i)
        if bi[2] < EPS or bi[3] < EPS:
            continue
        anc_i = set(m.chain[i])
        for j in content[a_pos + 1:]:
            if j in anc_i or i in m.chain[j]:
                continue
            bj = m.box(j)
            ov = inter(bi, bj)
            if ov[2] < args.overlap_min or ov[3] < args.overlap_min:
                continue
            if m.layered(i, j):
                continue
            out.append({"kind": "overlap", "a": i, "b": j, "detail": "%s  <>  %s  overlap %dx%d" % (m.describe(i), m.describe(j), round(ov[2]), round(ov[3]))})

    # offscreen
    for i in shown:
        r = rows[i]
        if r["class"] in ("ScrollContainer",):
            continue
        b = m.clip(i)
        if b[2] < EPS or b[3] < EPS:
            continue
        over = (max(0.0, -b[0]), max(0.0, -b[1]), max(0.0, b[0] + b[2] - cw), max(0.0, b[1] + b[3] - ch))
        if max(over) > EPS:
            out.append({"kind": "offscreen", "a": i, "detail": "%s  cut by the screen edge (left %d top %d right %d bottom %d)" % ((m.describe(i),) + tuple(round(v) for v in over))})

    # center (combat moments only)
    if combat:
        cx0, cy0, cx1, cy1 = cw * 0.2, ch * 0.2, cw * 0.8, ch * 0.8
        for i in content:
            b = m.box(i)
            ov = inter(b, (cx0, cy0, cx1 - cx0, cy1 - cy0))
            if ov[2] < 2 or ov[3] < 2:
                continue
            if b[2] * b[3] >= 0.6 * cw * ch:
                continue
            out.append({"kind": "center", "a": i, "detail": "%s  inside the middle 60%% (%dx%d of it)" % (m.describe(i), round(ov[2]), round(ov[3]))})

    if not m.extra:
        return out

    # buttons cut by a clipping ancestor
    for i in shown:
        r = rows[i]
        if r["class"] in BUTTON_CLASSES and "clip" in r:
            full = r["w"] * r["h"]
            seen = m.clip(i)
            vis = seen[2] * seen[3]
            if full > 0 and 0.0 < vis < 0.98 * full:
                out.append({"kind": "clipped", "a": i, "detail": "%s  %d%% of the button is visible" % (m.describe(i), round(100 * vis / full))})

    # text overflow, font floor
    scale720 = 720.0 / ch
    for i in shown:
        r = rows[i]
        text = str(r.get("text", ""))
        has_text = bool(text.strip())
        found = None
        if r["class"] == "Label" and has_text and "tw" in r:
            w, h = r["w"], r["h"]
            if int(r.get("vis_lines", 0)) < int(r.get("lines", 0)):
                found = ("text_overflow", "%d of %d lines are cut (box %dx%d)" % (int(r["lines"]) - int(r["vis_lines"]), int(r["lines"]), round(w), round(h)))
            elif float(r["th"]) > h + 1.5:
                found = ("text_overflow", "text %d px tall in a %d px box" % (round(float(r["th"])), round(h)))
            elif int(r.get("wrap", 0)) == 0 and float(r["tw"]) > w + 1.0:
                found = ("text_overflow", "text %d px wide in a %d px box (no wrapping)" % (round(float(r["tw"])), round(w)))
        elif r["class"] in BUTTON_CLASSES and has_text and "tw" in r:
            need = float(r["tw"]) + float(r.get("pad", 0))
            if need > r["w"] + 1.0:
                kind = "text_trimmed" if int(r.get("overrun", 0)) != 0 else "text_overflow"
                found = (kind, "button text needs %d px, button is %d px wide" % (round(need), round(r["w"])))
        elif r["class"] == "RichTextLabel" and has_text and "th" in r and float(r["th"]) > r["h"] + 1.5:
            found = ("text_overflow", "rich text %d px tall in a %d px box" % (round(float(r["th"])), round(r["h"])))
        if found is None and r["class"] not in ("ScrollContainer", "Control") and "min" in r:
            mw, mh = r["min"]
            if mw > r["w"] + 1.5 or mh > r["h"] + 1.5:
                found = ("text_overflow", "smaller than its own minimum size (%dx%d < %dx%d)" % (round(r["w"]), round(r["h"]), round(mw), round(mh)))
        if found:
            out.append({"kind": found[0], "a": i, "detail": "%s  %s" % (m.describe(i), found[1])})
        if has_text and "fs" in r and int(r["fs"]) * scale720 < args.min_font_720 - 0.01:
            out.append({"kind": "font_small", "a": i, "detail": "%s  size %d = %.1f px at 720p (floor %.1f)" % (m.describe(i), int(r["fs"]), int(r["fs"]) * scale720, args.min_font_720)})
    return out


def load_allow(path):
    if not path or not Path(path).is_file():
        return []
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    return doc.get("allow", [])


def allowed(entry, rule):
    """rule: {kind, label?, path?|a?+b?, why}. Globs use fnmatch on the control path (names joined by '/') and the moment label."""
    v, m = entry
    if rule.get("kind", "*") not in ("*", v["kind"]):
        return False
    if not fnmatch.fnmatch(m.label, rule.get("label", "*")):
        return False
    if v["kind"] == "overlap":
        pa, pb = m.path[v["a"]], m.path[v["b"]]
        ga, gb = rule.get("a", rule.get("path", "*")), rule.get("b", "*")
        return (fnmatch.fnmatch(pa, ga) and fnmatch.fnmatch(pb, gb)) or (fnmatch.fnmatch(pb, ga) and fnmatch.fnmatch(pa, gb))
    return fnmatch.fnmatch(m.path[v["a"]], rule.get("path", rule.get("a", "*")))


def moments_of(path, args):
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        raise SystemExit("hud_layout_check: cannot read %s: %s" % (path, err))
    if not isinstance(doc, dict) or "dumps" not in doc:
        raise SystemExit("hud_layout_check: %s is not a hud_dump/scene_shot dump (no \"dumps\")" % path)
    meta = doc.get("meta", {})
    canvas = tuple(meta.get("canvas", args.canvas))
    for label in doc.get("order", list(doc["dumps"])):
        if args.only and not fnmatch.fnmatch(label, args.only):
            continue
        yield Moment(label, doc["dumps"][label], meta, canvas)


def parse_size(text):
    m = re.fullmatch(r"(\d+)x(\d+)", text)
    if not m:
        raise argparse.ArgumentTypeError("expected WxH, got " + text)
    return (int(m.group(1)), int(m.group(2)))


def main(argv=None):
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description="HUD layout check on Control dumps")
    ap.add_argument("dumps", nargs="+")
    ap.add_argument("--allow", default=str(here / "hud_layout_allow.json"))
    ap.add_argument("--only", default="")
    ap.add_argument("--combat", default=DEFAULT_COMBAT)
    ap.add_argument("--canvas", type=parse_size, default=(1600, 900))
    ap.add_argument("--min-font-720", type=float, default=11.2)
    ap.add_argument("--overlap-min", type=float, default=2.0)
    ap.add_argument("--info-limit", type=int, default=3, help="how many uncounted (information) lines to print per kind")
    ap.add_argument("--json", default="")
    ap.add_argument("--strict", action="store_true", help="count text_trimmed (ellipsis on purpose) as violations")
    ap.add_argument("--quiet", action="store_true", help="counts only")
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    print(HEADER)
    print(EXTRA_NOTE)
    rules = load_allow(args.allow)
    total, report = 0, []
    noted_scene = False
    for path in args.dumps:
        for m in moments_of(path, args):
            if m.meta.get("note") and not noted_scene:
                print("(%s)" % m.meta["note"])
                noted_scene = True
            found = check(m, args)
            kept, muted = [], 0
            for v in found:
                if any(allowed((v, m), rule) for rule in rules):
                    muted += 1
                else:
                    kept.append(v)
            counted = [v for v in kept if v["kind"] not in INFO_KINDS or args.strict]
            total += len(counted)
            window = m.meta.get("window")
            print("== %s  (%s, canvas %dx%d%s, %d controls, %d shown)  violations %d, information %d, allowed %d%s" % (
                m.label, Path(path).name, m.canvas[0], m.canvas[1], ", window %dx%d" % tuple(window) if window else "",
                len(m.rows), sum(1 for i in range(len(m.rows)) if m.shown(i)), len(counted), len(kept) - len(counted), muted,
                "" if m.extra else "  [no --dump-extra: text/font/clip checks skipped]"))
            if not args.quiet:
                per_kind = {}
                for v in sorted(kept, key=lambda v: (v["kind"], v["a"])):
                    n = per_kind.get(v["kind"], 0)
                    per_kind[v["kind"]] = n + 1
                    if v not in counted and n >= args.info_limit:
                        continue
                    print("  [%s]%s %s" % (v["kind"], "" if v in counted else " (not counted)", v["detail"]))
                for kind, n in per_kind.items():
                    if kind in INFO_KINDS and n > args.info_limit and not args.strict:
                        print("  [%s] ... and %d more (--info-limit)" % (kind, n - args.info_limit))
            report.append({"label": m.label, "file": str(path), "violations": [{"kind": v["kind"], "detail": v["detail"], "counted": v in counted} for v in kept], "allowed": muted})
    print("TOTAL %d violation(s)" % total)
    if args.json:
        Path(args.json).write_text(json.dumps({"header": HEADER, "total": total, "moments": report}, ensure_ascii=False, indent=1), encoding="utf-8")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
