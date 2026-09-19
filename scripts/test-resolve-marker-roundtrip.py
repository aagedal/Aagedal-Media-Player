#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regressions for retained editor loss and strict round-trip evidence."""
from fractions import Fraction
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("validator", Path(__file__).with_name("validate-resolve-marker-roundtrip.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
RATE = Fraction(30000, 1001)
EVIDENCE = Path(__file__).resolve().parents[1] / "docs/evidence/resolve-markers-20260915"


def edl(start="00:00:58;00", end="00:00:58;01", note="Unicode æøå 日本語", duration=1):
    return (f"TITLE: Test\nFCM: DROP FRAME\n001 001 V C {start} {end} {start} {end}\n"
            f" |C:ResolveColorBlue |M:{note} |D:{duration}\n")


class RoundTripTests(unittest.TestCase):
    def test_retained_editor_loss_is_failure(self):
        report = validator.compare((EVIDENCE / "source-a_vs_source-b_review.edl").read_text(),
                                   (EVIDENCE / "resolve-roundtrip.edl").read_text(), RATE)
        self.assertEqual(report["status"], "failed")
        self.assertEqual((report["expectedCount"], report["actualCount"]), (8, 13))
        self.assertEqual([entry["frame"] for entry in report["missing"]], [1740, 1741, 1800])
        self.assertEqual(len(report["unexpected"]), 8)

    def test_colon_drop_frame_and_one_frame_event_span_preserve_range(self):
        source = edl("00:00:59;29", "00:01:00;04", duration=3)
        returned = edl("00:00:59:29", "00:01:00:02", duration=3)
        self.assertEqual(validator.compare(source, returned, RATE)["status"], "passed")

    def test_fractional_drop_frame_boundaries(self):
        for rate, last, first, frame in [
            (RATE, "00:00:59;29", "00:01:00;02", 1800),
            (RATE, "00:09:59;29", "00:10:00;00", 17982),
            (Fraction(60000, 1001), "00:00:59;59", "00:01:00;04", 3600),
            (Fraction(60000, 1001), "00:09:59;59", "00:10:00;00", 35964),
        ]:
            self.assertEqual(validator.frame_number(last, rate, True), frame - 1)
            self.assertEqual(validator.frame_number(first, rate, True), frame)
        self.assertEqual(validator.frame_number("00:01:00:00", Fraction(24000, 1001), False), 1440)

    def test_moved_frame_duration_text_and_color_fail(self):
        source = edl()
        for changed in [edl("00:00:58;01", "00:00:58;02"), edl(duration=2),
                        edl(note="Unicode lost"), source.replace("ColorBlue", "ColorRed")]:
            self.assertEqual(validator.compare(source, changed, RATE)["status"], "failed")

    def test_duplicate_multiplicity_is_preserved(self):
        source = edl()
        duplicate = source + "\n".join(source.splitlines()[2:])
        self.assertEqual(validator.compare(duplicate, source, RATE)["status"], "failed")
        self.assertEqual(validator.compare(source, duplicate, RATE)["status"], "failed")
        self.assertEqual(validator.compare(duplicate, duplicate, RATE)["status"], "passed")

    def test_invalid_or_unaccounted_lines_fail_closed(self):
        source = edl()
        for changed in ["", source.replace("FCM: DROP FRAME", ""),
                        source + "unparsed marker", source.replace("|D:1", "|D:0"),
                        source.replace("00:00:58;00", "00:01:00;00"),
                        source.replace("00:00:58;00", "00:00:58;30"),
                        source.replace("00:00:58;00", "24:00:58;00"),
                        source.replace("FCM: DROP FRAME", "FCM: NON-DROP FRAME"),
                        "\n".join(source.splitlines()[:-1])]:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                validator.parse_edl(changed, RATE)
        with self.assertRaises(ValueError):
            validator.parse_edl(source, Fraction(24))


if __name__ == "__main__":
    unittest.main()
