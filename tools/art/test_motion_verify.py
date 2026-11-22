#!/usr/bin/env python3
"""motion_verify.py 의 비교 규칙 시험. 가짜 측정 출력만 쓴다(godot 을 부르지 않는다)."""
import json, sys, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import motion_verify as mv  # noqa: E402
import motion_math as mm  # noqa: E402

G_RUN, G_WALK, S = 7.2215, 2.2125, 1.32


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

    def test_without_screen_value_uses_calc(self):
        stride = mm.stride_for(5.8, 0.96667, 1.3)
        r = mv.compare(fake(1.3, 2.0), 5.8, 0.96667, stride, G_WALK, S, None)
        self.assertAlmostEqual(r["slip_calc"], 2.0, delta=0.05)
        self.assertTrue(r["slip_ok"])

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
            ok.write_text(json.dumps(fake(0.6061, 0.4)))
            self.assertEqual(mv.main(["--current", "--no-run", str(ok), "--screen-slip", "0.38"]), 0)
            bad = Path(d) / "bad.json"
            bad.write_text(json.dumps({"error": "x"}))
            self.assertEqual(mv.main(["--current", "--no-run", str(bad)]), 2)


if __name__ == "__main__":
    unittest.main()
