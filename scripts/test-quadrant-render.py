#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Geometry evidence must distinguish correct aspect from correct Fit placement."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("geometry", Path(__file__).with_name("measure-quadrant-render.py"))
geometry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geometry)
COLORS = ["green", "yellow", "red", "blue"]


def frame(width=90, height=160, bounds=None):
    left, top, right, bottom = bounds or (0, 0, width, height)
    data = bytearray(width * height * 3)
    palette = [(0, 255, 0), (255, 255, 0), (255, 0, 0), (0, 0, 255)]
    for y in range(top, bottom):
        for x in range(left, right):
            quadrant = 2 * (y >= (top + bottom) / 2) + (x >= (left + right) / 2)
            offset = (y * width + x) * 3
            data[offset:offset + 3] = bytes(palette[quadrant])
    return data


class GeometryTests(unittest.TestCase):
    def test_correct_full_frame(self):
        self.assertTrue(all(geometry.measure(frame(), 90, 160, 9/16, COLORS)["checks"].values()))

    def test_matching_aspect_with_four_margins_fails_fit(self):
        result = geometry.measure(frame(bounds=(9, 16, 81, 144)), 90, 160, 9/16, COLORS)
        self.assertTrue(result["checks"]["displayAspect"])
        self.assertFalse(result["checks"]["fitBounds"])
        self.assertEqual(result["margins"], [9, 16, 9, 16])

    def test_legitimate_letterbox_passes(self):
        result = geometry.measure(frame(bounds=(0, 35, 90, 125)), 90, 160, 1, COLORS)
        self.assertTrue(all(result["checks"].values()))

    def test_wrong_aspect_fails(self):
        self.assertFalse(geometry.measure(frame(), 90, 160, 1, COLORS)["checks"]["displayAspect"])

    def test_wrong_rotation_fails(self):
        self.assertFalse(geometry.measure(frame(), 90, 160, 9/16, COLORS[::-1])["checks"]["orientation"])

    def test_blank_truncated_and_invalid_aspect_fail(self):
        for data, aspect in ((bytes(90*160*3), 1), (b"", 1), (frame(), 0), (frame(), float("nan"))):
            with self.subTest(aspect=aspect), self.assertRaises(ValueError):
                geometry.measure(data, 90, 160, aspect, COLORS)

    def test_sparse_edges_cannot_fake_solid_content(self):
        data = frame()
        for y in range(70, 90):
            data[y*90*3:(y+1)*90*3] = bytes(90*3)
        result = geometry.measure(data, 90, 160, 9/16, COLORS)
        self.assertTrue(result["checks"]["fitBounds"])
        self.assertFalse(result["checks"]["solidQuadrants"])


if __name__ == "__main__":
    unittest.main()
