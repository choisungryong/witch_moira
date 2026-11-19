#!/usr/bin/env python3
"""hud_layout_check.py self-check on synthetic dumps. Run: python tools/dev/test_hud_layout_check.py
Standard library only. Does not start Godot."""
import contextlib
import io
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hud_layout_check as h  # noqa: E402

FAILS = []
N = 0


def check(name, cond, detail=""):
    global N
    N += 1
    if not cond:
        FAILS.append(name)
        print("FAIL", name, detail)
    else:
        print("ok  ", name)


def row(d, name, cls="Control", x=0, y=0, w=100, h_=30, **kw):
    r = {"d": d, "class": cls, "name": name, "visible": True, "x": x, "y": y, "w": w, "h": h_, "modulate": "ffffffff", "tooltip": ""}
    r.update(kw)
    return r


def label(d, name, text, x, y, w, h_, fs=18, tw=None, th=24, lines=1, vis=None, wrap=0, ha=0, va=0, **kw):
    return row(d, name, "Label", x, y, w, h_, text=text, fs=fs, tw=tw if tw is not None else 9.0 * len(text), th=th, lines=lines,
               vis_lines=lines if vis is None else vis, wrap=wrap, ha=ha, va=va, alpha=1.0, min=[0, 0], **kw)


def dump(rows, label_="moment", meta=None, extra=True):
    if extra:
        for r in rows:
            r.setdefault("alpha", 1.0)
            r.setdefault("min", [0, 0])
    doc = {"order": [label_], "dumps": {label_: rows}}
    if meta is not None:
        doc["meta"] = meta
    return doc


def run(docs, extra_args=None, allow=None):
    """Runs the CLI on dump documents; returns (exit code, output text, json report)."""
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for i, doc in enumerate(docs):
            p = Path(tmp) / ("d%d.json" % i)
            p.write_text(json.dumps(doc), encoding="utf-8")
            paths.append(str(p))
        allow_path = Path(tmp) / "allow.json"
        allow_path.write_text(json.dumps({"allow": allow or []}), encoding="utf-8")
        out_json = Path(tmp) / "out.json"
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = h.main(paths + ["--allow", str(allow_path), "--json", str(out_json)] + (extra_args or []))
        return code, buf.getvalue(), json.loads(out_json.read_text(encoding="utf-8"))


def kinds(report):
    return sorted(v["kind"] for m in report["moments"] for v in m["violations"])


# header and a clean dump
clean = dump([row(0, "Root", w=1600, h_=900), label(1, "A", "안녕", 100, 100, 200, 30), label(1, "B", "다음", 100, 200, 200, 30)])
code, text, rep = run([clean])
check("header says zero violations is not a pass", "위반 0은 HUD 통과가 아니다. 바닥 글자(Label3D)와 셰이더로 잘리는 것은 보지 못한다." in text.splitlines()[0])
check("clean dump: exit 0, no violation", code == 0 and kinds(rep) == [], text)

# overlap: two labels whose text overlaps
d = dump([row(0, "Root", w=1600, h_=900), label(1, "A", "가나다라마바", 100, 100, 300, 30), label(1, "B", "사아자차카타", 150, 110, 300, 30)])
code, text, rep = run([d])
check("overlap of two texts is found", kinds(rep) == ["overlap"] and code == 1, text)

# overlap: parent and child are not a pair
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Btn", "Button", 100, 100, 300, 60, text="확인", fs=18, tw=40, pad=20, overrun=0, ha=1),
          label(2, "Badge", "◆ 2", 330, 110, 60, 30)])
code, text, rep = run([d])
check("a button and its own child label do not overlap", kinds(rep) == [], text)

# overlap by label box only: wide label with short text does not hit a neighbour that is outside the text
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Wide", "짧음", 100, 100, 600, 30, tw=36), label(1, "Near", "옆", 400, 100, 100, 30)])
code, text, rep = run([d])
check("short text in a wide label box does not overlap a neighbour beside the text", kinds(rep) == [], text)

# alignment right: the same wide label right-aligned does overlap
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Wide", "짧음", 100, 100, 600, 30, tw=36, ha=2), label(1, "Near", "옆", 660, 100, 100, 30)])
code, text, rep = run([d])
check("right-aligned text overlaps a neighbour at the right end", kinds(rep) == ["overlap"], text)

# layered windows are not overlaps
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Menu", w=1000, h_=700, x=300, y=100), label(2, "Title", "제목", 400, 200, 300, 40),
          row(1, "Dialog", w=1600, h_=900), label(2, "Q", "질문입니다", 450, 210, 300, 40)])
code, text, rep = run([d])
check("a big window laid over another is a layer, not an overlap", kinds(rep) == [], text)

# invisible, transparent, clipped
d = dump([row(0, "Root", w=1600, h_=900), label(1, "A", "가나다라마바", 100, 100, 300, 30), label(1, "B", "사아자차카타", 150, 110, 300, 30, visible=False)])
d["dumps"]["moment"][2]["visible"] = False
check("an invisible control is ignored", run([d])[0] == 0)
d = dump([row(0, "Root", w=1600, h_=900), label(1, "A", "가나다라마바", 100, 100, 300, 30), label(1, "B", "사아자차카타", 150, 110, 300, 30)])
d["dumps"]["moment"][2]["alpha"] = 0.0
check("a fully faded control is ignored", run([d])[0] == 0)
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Scroll", "ScrollContainer", 0, 0, 400, 100),
          label(2, "Inner", "스크롤 안쪽", 10, 300, 300, 30, clip=[0, 0, 400, 100]), label(1, "Outside", "밖의 글", 10, 300, 300, 30)])
check("a control clipped away by a scroll container does not overlap", run([d])[0] == 0)

# offscreen
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Off", "넘침", 1550, 100, 200, 30)])
code, text, rep = run([d])
check("a control cut by the right edge is found", "offscreen" in kinds(rep) and code == 1, text)
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Off", "넘침", 1500, 100, 200, 30, clip=[0, 0, 1600, 100])])
d["dumps"]["moment"][1]["clip"] = [1500, 100, 100, 30]
check("clipping ancestors count: nothing cut when the clip is inside the screen", "offscreen" not in kinds(run([d])[2]))

# center: combat label or meta only
mid = [row(0, "Root", w=1600, h_=900), label(1, "Toast", "가운데 글", 700, 400, 200, 30)]
code, text, rep = run([dump([dict(r) for r in mid], label_="playing-120")])
check("combat label: content in the middle 60% is found", kinds(rep) == ["center"], text)
check("a menu label is not a combat moment", run([dump([dict(r) for r in mid], label_="menu")])[0] == 0)
check("meta combat=false wins over a combat-looking label", run([dump([dict(r) for r in mid], label_="playing-1", meta={"combat": False, "canvas": [1600, 900]})])[0] == 0)
check("meta combat=true makes any label a combat moment", run([dump([dict(r) for r in mid], label_="x", meta={"combat": True, "canvas": [1600, 900]})])[0] == 1)
edge = [row(0, "Root", w=1600, h_=900), label(1, "Top", "위쪽", 700, 40, 200, 30)]
check("content outside the middle 60% is fine in combat", run([dump(edge, label_="playing-1")])[0] == 0)

# text overflow
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Cut", "한 줄 두 줄 세 줄", 100, 100, 200, 48, th=72, lines=3, vis=2, wrap=2)])
code, text, rep = run([d])
check("label with cut lines is found", kinds(rep) == ["text_overflow"] and "1 of 3 lines" in text, text)
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Wide", "아주 아주 긴 글", 100, 100, 100, 30, tw=240)])
code, text, rep = run([d])
check("unwrapped label wider than its box is found", kinds(rep) == ["text_overflow"], text)
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Btn", "Button", 100, 100, 150, 40, text="아주 긴 단추 글", fs=18, tw=200, pad=24, overrun=0)])
code, text, rep = run([d])
check("button text that does not fit is found", kinds(rep) == ["text_overflow"], text)
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Btn", "Button", 100, 100, 150, 40, text="아주 긴 단추 글", fs=18, tw=200, pad=24, overrun=3)])
code, text, rep = run([d])
check("ellipsis trimming is reported but not counted", kinds(rep) == ["text_trimmed"] and code == 0, text)
check("--strict counts trimmed text", run([d], ["--strict"])[0] == 1)
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Box", "PanelContainer", 100, 100, 100, 40, min=[100, 90])])
d["dumps"]["moment"][1]["min"] = [100, 90]
code, text, rep = run([d])
check("a control smaller than its minimum size is found", kinds(rep) == ["text_overflow"], text)

# a button cut by its scroll container is information only
d = dump([row(0, "Root", w=1600, h_=900), row(1, "Btn", "Button", 100, 100, 200, 40, text="장착", fs=18, tw=30, pad=20, overrun=0, clip=[0, 0, 400, 120])])
code, text, rep = run([d])
check("a half-cut button is listed as clipped, not counted", kinds(rep) == ["clipped"] and code == 0, text)
check("--strict counts clipped", run([d], ["--strict"])[0] == 1)

# font floor
d = dump([row(0, "Root", w=1600, h_=900), label(1, "Small", "작은 글", 100, 100, 200, 30, fs=13), label(1, "Ok", "충분한 글", 100, 200, 200, 30, fs=14)])
code, text, rep = run([d])
check("size 13 is under the 720p floor, 14 is not", kinds(rep) == ["font_small"] and "Small" in text and "Ok" not in text.split("[font_small]")[1], text)
check("floor can be changed", run([d], ["--min-font-720", "10"])[0] == 0)

# allow list
d = dump([row(0, "Root", w=1600, h_=900), label(1, "A", "가나다라마바", 100, 100, 300, 30), label(1, "B", "사아자차카타", 150, 110, 300, 30)])
code, text, rep = run([d], allow=[{"kind": "overlap", "a": "*/A", "b": "*/B", "why": "test"}])
check("allow list mutes an overlap pair (either order)", code == 0 and rep["moments"][0]["allowed"] == 1, text)
code, text, rep = run([d], allow=[{"kind": "offscreen", "path": "*", "why": "other kind"}])
check("allow list of another kind mutes nothing", code == 1)
code, text, rep = run([d], allow=[{"kind": "*", "label": "other*", "a": "*", "b": "*"}])
check("allow list entry for another moment label mutes nothing", code == 1)

# dump without extra fields still gets the whole-rectangle checks and says so
d = dump([row(0, "Root", w=1600, h_=900), row(1, "A", "Label", 100, 100, 300, 30, text="가나다"), row(1, "B", "Label", 150, 110, 300, 30, text="사아자")], extra=False)
code, text, rep = run([d])
check("a plain dump gets overlap checks and the notice", kinds(rep) == ["overlap"] and "no --dump-extra" in text, text)

# unnamed nodes get a stable path
d = dump([row(0, "@Control@19309", w=1600, h_=900), label(1, "@Label@19312", "가나다라마바", 100, 100, 300, 30), label(1, "@Label@19313", "사아자차카타", 150, 110, 300, 30)])
code, text, rep = run([d], allow=[{"kind": "overlap", "a": "<Control>/<Label>", "b": "<Control>/<Label>", "why": "test"}])
check("@Class@123 names become <Class> in paths (allow list stays valid between runs)", code == 0 and "@Label@" not in text, text)

# bad input
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "x.json"
    p.write_text("{}", encoding="utf-8")
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            h.main([str(p)])
        check("a file that is not a dump is refused", False)
    except SystemExit as err:
        check("a file that is not a dump is refused", "not a hud_dump" in str(err))

print("\n%d checks, %d failed" % (N, len(FAILS)))
sys.exit(1 if FAILS else 0)
