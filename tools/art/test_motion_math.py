#!/usr/bin/env python3
"""motion_math.py 와 motion_apply.py 시험. 자리표 사본은 임시 폴더에만 쓴다(본 자리표는 읽기만)."""
import difflib, json, shutil, sys, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import motion_math as mm  # noqa: E402
import motion_apply as ma  # noqa: E402

SLOTS = ma.SLOTS
G_RUN, G_WALK, SCALE = 7.25, 2.2125, 1.32
SLOT = "actor.hero.frost.model"


class MathCases(unittest.TestCase):
    def test_current_contract_rate(self):
        self.assertAlmostEqual(mm.rate_from_contract(5.8, 0.5333333, 5.104), 0.606, delta=0.001)

    def test_walk_stride(self):
        self.assertAlmostEqual(mm.stride_for(5.8, 0.96667, 1.3), 4.313, delta=0.002)
        self.assertAlmostEqual(mm.stride_for(5.8, 0.96667, 1.99), 2.82, delta=0.01)

    def test_no_slip_rate(self):
        self.assertAlmostEqual(mm.rate_no_slip(5.8, G_WALK, SCALE), 1.99, delta=0.01)
        self.assertAlmostEqual(mm.rate_no_slip(5.8, G_RUN, SCALE), 0.606, delta=0.001)

    def test_slip_table(self):
        self.assertAlmostEqual(mm.slip(5.8, 0.606, G_RUN, SCALE), 0.0, delta=0.02)
        s = mm.slip(5.8, 1.3, G_WALK, SCALE)
        self.assertAlmostEqual(s, 2.0, delta=0.05)
        self.assertAlmostEqual(mm.slip_ratio(5.8, 1.3, G_WALK, SCALE), 0.35, delta=0.01)
        self.assertAlmostEqual(mm.slip(3.8, 1.3, G_WALK, SCALE), 0.0, delta=0.02)
        self.assertAlmostEqual(mm.speed_no_slip(1.5, G_WALK, SCALE), 4.38, delta=0.01)

    def test_roundtrip(self):
        for v, length_s, r in [(5.8, 0.5, 0.7), (3.0, 1.2, 2.2)]:
            self.assertAlmostEqual(mm.rate_from_contract(v, length_s, mm.stride_for(v, length_s, r)), r, places=9)

    def test_rejects_bad_input(self):
        for f in (lambda: mm.rate_from_contract(1, 1, 0), lambda: mm.stride_for(1, 1, 0), lambda: mm.rate_no_slip(1, 0, 1)):
            with self.assertRaises(ValueError):
                f()

    def test_selfcheck_cases_are_consistent(self):
        for c in mm.selfcheck_cases():
            self.assertAlmostEqual(c["rate_from_stride"], c["r"], places=9)


def make_pick(tmp, **over):
    values = {"line": "frost", "slot": SLOT, "clip": "walk", "clip_source": "body", "rate": 1.3, "speed_seen": 5.8, "speed_game": 5.8,
              "L": 0.96667, "stride_world_m": 4.313}
    values.update(over)
    rec = {"screen": "character", "subject": "frost/locomotion", "verdict": "pick", "note": "test", "values": values,
           "proposals": [], "by": "user", "created": "2026-11-22 00:00:00", "status": "open", "closed_ref": ""}
    p = Path(tmp) / "picks.json"
    p.write_text(json.dumps({"revision": 1, "records": {"pk-test": rec}}), encoding="utf-8")
    return p


class Apply(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="motion-apply-")
        # 몸 옆 pack-report 를 읽도록 같은 상대 위치에 사본을 둔다(없으면 클립 확인만 생략됨)
        self.slots = Path(self.tmp) / "asset_slots.json"
        shutil.copyfile(SLOTS, self.slots)
        self.orig = SLOTS.read_bytes()
        self.picks = make_pick(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cli(self, *args):
        import contextlib, io
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return ma.main(["--pick", "pk-test", "--slots", str(self.slots), "--picks", str(self.picks), *args])

    def test_default_does_not_write(self):
        self.assertEqual(self.run_cli(), 0)
        self.assertEqual(self.slots.read_bytes(), self.orig)

    def test_write_changes_only_the_slot_lines(self):
        self.assertEqual(self.run_cli("--write"), 0)
        new = self.slots.read_bytes()
        self.assertNotEqual(new, self.orig)
        a, b = self.orig.decode("utf-8").splitlines(keepends=True), new.decode("utf-8").splitlines(keepends=True)
        self.assertEqual(len(a), len(b))
        diff_lines = [i for i, (x, y) in enumerate(zip(a, b)) if x != y]
        self.assertEqual(len(diff_lines), 4)  # clips.run, run_time_scale, stride_world_m, source
        changed_text = [b[i] for i in diff_lines]
        self.assertTrue(any('"run": "walk"' in t for t in changed_text))
        self.assertTrue(any('"run_time_scale": 0.96667' in t for t in changed_text))
        self.assertTrue(any('"stride_world_m": 4.313' in t for t in changed_text))
        self.assertTrue(any('"source"' in t and "clip 'walk'" in t for t in changed_text))
        # difflib 으로도 확인: 바뀐 줄은 모두 그 칸 안
        sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
        ops = [op for op in sm.get_opcodes() if op[0] != "equal"]
        self.assertTrue(all(op[0] == "replace" and op[2] - op[1] == op[4] - op[3] for op in ops))
        self.assertEqual(sum(op[2] - op[1] for op in ops), 4)
        start = next(i for i, l in enumerate(a) if '"%s"' % SLOT in l)
        end = next(i for i, l in enumerate(a) if '"actor.hero.ember.model"' in l)
        self.assertTrue(all(start <= i < end for i in diff_lines))
        # 파싱해 다른 칸이 그대로인지
        d0, d1 = json.loads(self.orig), json.loads(new)
        d0["slots"][SLOT]["contract"]["clips"]["run"] = d1["slots"][SLOT]["contract"]["clips"]["run"]
        d0["slots"][SLOT]["contract"]["pose"]["run_time_scale"] = d1["slots"][SLOT]["contract"]["pose"]["run_time_scale"]
        d0["slots"][SLOT]["contract"]["pose"]["stride_world_m"] = d1["slots"][SLOT]["contract"]["pose"]["stride_world_m"]
        d0["slots"][SLOT]["source"] = d1["slots"][SLOT]["source"]
        self.assertEqual(d0, d1)

    def test_line_endings_preserved(self):
        crlf = self.orig.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        self.slots.write_bytes(crlf)
        self.assertEqual(self.run_cli("--write"), 0)
        new = self.slots.read_bytes()
        self.assertEqual(new.count(b"\r\n"), crlf.count(b"\r\n"))
        self.assertEqual(new.count(b"\n"), new.count(b"\r\n"))

    def test_check(self):
        self.assertEqual(self.run_cli("--check"), 1)  # 아직 적용 전
        self.assertEqual(self.run_cli("--write"), 0)
        self.assertEqual(self.run_cli("--check"), 0)

    def test_current_contract_checks_clean(self):
        p = make_pick(self.tmp, clip="run", rate=0.606, L=0.5333333, stride_world_m=5.104)
        self.picks = p
        self.assertEqual(self.run_cli("--check"), 0)
        self.assertEqual(self.run_cli("--write"), 0)
        self.assertEqual(self.slots.read_bytes().count(b"\n"), self.orig.count(b"\n"))

    def test_unknown_clip_refused(self):
        self.picks = make_pick(self.tmp, clip="walk_a", clip_source="motions")
        # 사본 폴더에는 몸 pack-report 가 없어 확인을 건너뛰므로, 자리표 안의 file 상대 위치에 보고서를 둔다
        rel = json.loads(self.orig)["slots"][SLOT]["file"]
        rep = (Path(self.tmp) / rel).with_suffix(".pack-report.json")
        rep.parent.mkdir(parents=True, exist_ok=True)
        rep.write_text(json.dumps({"clips": {"run": {}, "walk": {}}}), encoding="utf-8")
        self.assertEqual(self.run_cli("--write"), 2)
        self.assertEqual(self.slots.read_bytes(), self.orig)

    def test_rejects_non_pick_and_missing_values(self):
        doc = json.loads(self.picks.read_text(encoding="utf-8"))
        doc["records"]["pk-test"]["verdict"] = "hold"
        self.picks.write_text(json.dumps(doc), encoding="utf-8")
        self.assertEqual(self.run_cli("--write"), 2)
        self.picks = make_pick(self.tmp, L=None)
        self.assertEqual(self.run_cli("--write"), 2)
        self.assertEqual(self.slots.read_bytes(), self.orig)

    def test_missing_slot(self):
        self.picks = make_pick(self.tmp, slot="actor.hero.nobody.model")
        self.assertEqual(self.run_cli("--write"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
