#!/usr/bin/env python3
"""Descent screen rectangle versus the camera (TECH-REVIEW-20261123 B3).

chapter1/data/descent.json "area" is the 16:9 ground rectangle the camera shows, written down by hand: the core never reads a camera or a
resolution (so a run is the same at any window size). When the camera size or angle is changed (OPEN-WORK 9: 19.5 vs 14, CAMERA_OFFSET) this
test fails until the data is changed on purpose. It reads the numbers out of the source text, no Godot needed:
  CAMERA_OFFSET   chapter1/view/world/chapter_world.gd   the camera sits at this offset from the hero and looks at it
  camera.size     chapter1/view/fx/combat_juice.gd       orthographic size (the vertical extent in metres) set by apply_look
Model (same as docs/specs/D24 12.1): half_w = size * 16/9 / 2; half_h on the ground = (size / 2) / sin(elevation); elevation = atan(y / hypot(x, z));
right_deg = atan2(z, x) of the camera's right axis on the ground, which for a camera at (x, y, z) looking at the origin is (-z', x') of the view direction
(-x, -z): right = (z, -x) normalised, angle = atan2(-x, z).
    python tools/dev/test_descent_area.py        exit 0 = the data matches the camera
"""
import json, math, re, sys, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESCENT = ROOT / 'chapter1' / 'data' / 'descent.json'
WORLD = ROOT / 'chapter1' / 'view' / 'world' / 'chapter_world.gd'
JUICE = ROOT / 'chapter1' / 'view' / 'fx' / 'combat_juice.gd'
ASPECT = 16 / 9
TOL_M = 0.1      # the data is written to 0.1 m
TOL_DEG = 0.1


def camera_offset(text):
    m = re.search(r'const\s+CAMERA_OFFSET\s*:=\s*Vector3\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)', text)
    if not m:
        raise ValueError('CAMERA_OFFSET not found in chapter_world.gd')
    return tuple(float(g) for g in m.groups())


def camera_size(text):
    """The size apply_look() sets on the orthographic camera."""
    m = re.search(r'func apply_look\(.*?\n(?=func |\Z)', text, re.S)
    body = m.group(0) if m else ''
    s = re.search(r'camera\.size\s*=\s*([-\d.]+)', body)
    if not s:
        raise ValueError('camera.size not found in combat_juice.gd apply_look')
    return float(s.group(1))


def expected_area(offset, size):
    x, y, z = offset
    elevation = math.atan2(y, math.hypot(x, z))
    return {'right_deg': math.degrees(math.atan2(-x, z)), 'half_w_m': size * ASPECT / 2, 'half_h_m': size / 2 / math.sin(elevation), 'elevation_deg': math.degrees(elevation)}


def mismatches(area, offset, size):
    want = expected_area(offset, size)
    out = []
    if abs(float(area['half_w_m']) - want['half_w_m']) > TOL_M:
        out.append('half_w_m %.2f in descent.json, camera gives %.2f' % (float(area['half_w_m']), want['half_w_m']))
    if abs(float(area['half_h_m']) - want['half_h_m']) > TOL_M:
        out.append('half_h_m %.2f in descent.json, camera gives %.2f' % (float(area['half_h_m']), want['half_h_m']))
    if abs(float(area['right_deg']) - want['right_deg']) > TOL_DEG:
        out.append('right_deg %.1f in descent.json, camera gives %.1f' % (float(area['right_deg']), want['right_deg']))
    return out


class DescentAreaMatchesCamera(unittest.TestCase):
    def test_shipped_data_matches_the_camera(self):
        area = json.loads(DESCENT.read_text(encoding='utf-8'))['area']
        offset = camera_offset(WORLD.read_text(encoding='utf-8'))
        size = camera_size(JUICE.read_text(encoding='utf-8'))
        problems = mismatches(area, offset, size)
        self.assertEqual(problems, [], 'descent.json area no longer matches the camera (offset %s, size %s): %s' % (offset, size, '; '.join(problems)))

    def test_detects_a_camera_change(self):
        area = json.loads(DESCENT.read_text(encoding='utf-8'))['area']
        offset = camera_offset(WORLD.read_text(encoding='utf-8'))
        self.assertNotEqual(mismatches(area, offset, 14.0), [])                 # camera size 14 (the open decision)
        self.assertNotEqual(mismatches(area, (11.0, 19.0, 16.0), camera_size(JUICE.read_text(encoding='utf-8'))), [])   # a changed offset
        self.assertNotEqual(mismatches(area, (11.0, 25.0, 14.0), 19.5), [])     # a changed elevation

    def test_parsers_read_the_source(self):
        self.assertEqual(camera_offset('const CAMERA_OFFSET := Vector3(11,19,14)'), (11.0, 19.0, 14.0))
        self.assertEqual(camera_size('func apply_look(world: RefCounted) -> void:\n\tcamera.size = 19.5\n\nfunc other():\n\tcamera.size = 3'), 19.5)
        self.assertRaises(ValueError, camera_size, 'func x():\n\tpass')


if __name__ == '__main__':
    unittest.main()
