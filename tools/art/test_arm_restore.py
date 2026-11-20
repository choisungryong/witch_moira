"""arm_restore.py 검사(numpy만). python -m pytest tools/art/test_arm_restore.py 또는 python tools/art/test_arm_restore.py"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arm_restore as ar  # noqa: E402


def tube(rx, ry, n=24, rings=10, length=1.0):
    pts = []
    for r in range(rings):
        x = length * r / (rings - 1)
        for k in range(n):
            a = 2 * np.pi * k / n
            pts.append((x, ry * np.sin(a), rx * np.cos(a)))
    return np.array(pts)


def test_restore_inflates_flat_arm():
    orig = tube(0.04, 0.04)
    fit = tube(0.04, 0.02)          # y(앞뒤)가 절반으로 눌림
    head, tail = np.array([0.0, 0, 0]), np.array([1.0, 0, 0])
    w = {"upper": np.ones(len(orig))}
    new, rep = ar.restore(orig, fit, w, {"upper": (head, tail)}, {"upper": (head, tail)}, ["upper"], cap=3.0)
    assert abs(rep["upper"]["k"] - 2.0) < 0.05
    mf = ar.mid_section(new, head, tail)
    assert abs(mf[1] - 0.08) < 0.005   # 짧은 폭이 원본(0.08)으로


def test_elbow_blend_is_smooth():
    n = 100
    pos = np.zeros((n, 3))
    pos[:, 0] = np.linspace(-0.2, 0.2, n)
    W = {"up": np.where(pos[:, 0] < 0, 1.0, 0.0), "fo": np.where(pos[:, 0] < 0, 0.0, 1.0)}
    ar.elbow_blend(pos, W, "up", "fo", np.zeros(3), np.array([1.0, 0, 0]), 0.1)
    assert np.allclose(W["up"] + W["fo"], 1.0)
    mid = np.argmin(np.abs(pos[:, 0]))
    assert 0.4 < W["fo"][mid] < 0.6
    assert np.all(np.diff(W["fo"]) >= -1e-9)


if __name__ == "__main__":
    test_restore_inflates_flat_arm()
    test_elbow_blend_is_smooth()
    print("OK")
