#!/usr/bin/env python3
"""motion_verify.py 의 비교 규칙 시험. 가짜 측정 출력과 고정 몸 보고서(fixtures/)만 쓴다(godot 을 부르지 않고, git 밖 파일도 읽지 않는다)."""
import json, sys, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import motion_verify as mv  # noqa: E402
import motion_math as mm  # noqa: E402

G_RUN, G_WALK, S = 7.2215, 2.2125, 1.32
FIXTURE = HERE / "fixtures" / "motion_pack_report.json"   # tracked; the hero body report is outside git


def fake(rate, slip, speed=5.8, samples=200):
    return {"avg_speed_mps": speed, "rate_measured": rate, "slip_rms_mps": slip, "slip_rms_horiz_mps": slip + 0.1,
            "stance_samples": samples, "windows_used": 8, "windows_total": 13, "display": "headless"}


class CompareRules(unittest.TestCase):
    def test_current_contract_same(self):
        r = mv.compare(fake(0.607, 0.42), 5.8, 0.5333333, 5.104, G_RUN, S, 0.38)
        self.assertTrue(r["same"])
        self.assertAlmostEqual(r["rate_game"], 0.606, delta=0.001)

    def test_rate_off_by_three_percent_fails(self):
        r = mv.compare(fake(0.606 * 1.03, 0.4), 5.8, 0.5333333, 5.104, G_RUN, S, 0.38)
        self.assertFalse(r["rate_ok"])
        self.assertFalse(r["same"])

    def test_rate_inside_two_percent_passes(self):
        r = mv.compare(fake(0.606 * 1.015, 0.4), 5.8, 0.5333333, 5.104, G_RUN, S, 0.38)
        self.assertTrue(r["rate_ok"])

    def test_slip_difference_against_screen(self):
        r = mv.compare(fake(1.3, 1.85), 5.8, 0.96667, mm.stride_for(5.8, 0.96667, 1.3), G_WALK, S, 1.95)
        self.assertTrue(r["slip_ok"])
        r = mv.compare(fake(1.3, 1.70), 5.8, 0.96667, mm.stride_for(5.8, 0.96667, 1.3), G_WALK, S, 1.95)
        self.assertFalse(r["slip_ok"])

    def test_without_screen_value_is_not_judged(self):
        stride = mm.stride_for(5.8, 0.96667, 1.3)
        r = mv.compare(fake(1.3, 2.0), 5.8, 0.96667, stride, G_WALK, S, None)
        self.assertIsNone(r["slip_ok"])
        self.assertFalse(r["slip_judged"])
        self.assertEqual(r["exit"], 3)
        self.assertAlmostEqual(r["slip_calc"], 2.0, delta=0.05)   # only printed as a reference

    def test_rate_off_beats_missing_screen(self):
        r = mv.compare(fake(0.606 * 1.05, 0.4), 5.8, 0.5333333, 5.104, G_RUN, S, None)
        self.assertEqual(r["exit"], 1)

    def test_slip_tolerance_edges(self):
        args = (5.8, 0.5333333, 5.104, G_RUN, S)
        self.assertEqual(mv.compare(fake(0.6061, 0.38 + 0.14), *args, 0.38)["exit"], 0)
        self.assertEqual(mv.compare(fake(0.6061, 0.38 - 0.14), *args, 0.38)["exit"], 0)
        self.assertEqual(mv.compare(fake(0.6061, 0.38 + 0.16), *args, 0.38)["exit"], 1)
        self.assertEqual(mv.compare(fake(0.6061, 0.38 - 0.16), *args, 0.38)["exit"], 1)

    def test_floor_above_calc_is_fine_when_screen_agrees(self):
        # running shape from B1-b: calc 0.023, in-game 0.42, screen 0.38 -> judged against the screen only
        r = mv.compare(fake(0.6061, 0.42), 5.8, 0.5333333, 5.104, G_RUN, S, 0.38)
        self.assertGreater(r["slip_calc"] + 0.4, 0.4)
        self.assertEqual(r["exit"], 0)

    def test_no_stored_screen_table(self):
        self.assertFalse(hasattr(mv, "SCREEN_REPORTED"))

    def test_probe_line_parser_and_usable(self):
        text = "noise\nHERO_MOTION_PROBE " + json.dumps(fake(0.6, 0.4)) + "\nHUD_DUMP_RESULT {}"
        self.assertTrue(mv.usable(mv.parse_probe_line(text)))
        self.assertIsNone(mv.parse_probe_line("nothing"))
        self.assertFalse(mv.usable({"error": "bad_drive"}))
        self.assertFalse(mv.usable({"rate_measured": None, "slip_rms_mps": None}))

    def test_probe_args_stay_isolated(self):
        args = mv.build_probe_args({"clip": "walk", "run_time_scale": 0.96667, "stride_world_m": 4.313}, 840, "t", False)
        self.assertIn("--chapter1-profile-off", args)
        self.assertIn("--stop-tick=840", args)
        self.assertTrue(any(a.startswith("--pose-override=") for a in args))
        self.assertTrue(any("tools" in a and a.endswith("godot.py") for a in args))

    def test_no_run_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            ok = Path(d) / "ok.json"
            # --current reads the run contract now in asset_slots.json: the fake game-side rate follows it
            pose = json.loads(mv.SLOTS.read_text(encoding="utf-8"))["slots"]["actor.hero.frost.model"]["contract"]["pose"]
            cur_rate = mm.rate_from_contract(5.8, float(pose["run_time_scale"]), float(pose["stride_world_m"]))
            ok.write_text(json.dumps(fake(cur_rate, 0.4)))
            base = ["--current", "--no-run", str(ok), "--report", str(FIXTURE)]
            self.assertEqual(mv.main(base + ["--screen-slip", "0.38"]), 0)
            self.assertEqual(mv.main(base + ["--screen-slip", "0.20"]), 1)
            self.assertEqual(mv.main(base), 3)
            bad = Path(d) / "bad.json"
            bad.write_text(json.dumps({"error": "x"}))
            self.assertEqual(mv.main(["--current", "--no-run", str(bad), "--report", str(FIXTURE)]), 2)

    def test_report_argument_is_read(self):
        with tempfile.TemporaryDirectory() as d:
            ok = Path(d) / "ok.json"
            ok.write_text(json.dumps(fake(1.3, 1.94)))
            self.assertEqual(mv.main(["--clip", "walk", "--rate", "1.3", "--no-run", str(ok), "--report", str(FIXTURE), "--screen-slip", "1.95"]), 0)
            self.assertEqual(mv.main(["--clip", "walk", "--rate", "1.3", "--no-run", str(ok), "--report", str(FIXTURE)]), 3)
            missing = Path(d) / "nope.json"
            self.assertEqual(mv.main(["--clip", "walk", "--rate", "1.3", "--no-run", str(ok), "--report", str(missing)]), 2)
            self.assertEqual(mv.clip_numbers("walk", FIXTURE), (0.96667, 2.2125))

if __name__ == "__main__":
    unittest.main()
