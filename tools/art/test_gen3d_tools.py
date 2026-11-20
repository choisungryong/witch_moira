#!/usr/bin/env python3
"""gen3d 도구의 Blender 없이 도는 부분 검사: python tools/art/test_gen3d_tools.py"""
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen3d_prepare as gp  # noqa: E402
import gen3d_video as gv  # noqa: E402


class T(unittest.TestCase):
    def test_fill_band_replaces_line(self):
        px = np.zeros((32, 32, 4), np.float32)
        px[..., :3] = 0.5
        px[16, :, :3] = 1.0          # 한 줄짜리 이음선
        cov = np.ones((32, 32), bool)
        band = np.zeros((32, 32), bool)
        band[15:18] = True
        gp.fill_band(px, band, cov, band)
        self.assertTrue(np.allclose(px[16, :, :3], 0.5, atol=1e-3))

    def test_natural_sort(self):
        names = ["m_t10.png", "m_t2.png", "m_t1.png"]
        self.assertEqual(sorted(names, key=gv.natural), ["m_t1.png", "m_t2.png", "m_t10.png"])

    def test_region_arg_files_exist(self):
        base = Path(__file__).resolve().parent / "rig_configs"
        for n in ("joints_frost_hy31.json", "mocap_clips_gen3d.json"):
            self.assertTrue((base / n).is_file(), n)


if __name__ == "__main__":
    unittest.main()
