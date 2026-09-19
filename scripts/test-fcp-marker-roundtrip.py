#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retained native evidence and failure regressions for FCPXML comparison."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("fcp", Path(__file__).with_name("compare-fcp-marker-roundtrip.py"))
fcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fcp)
EVIDENCE = Path(__file__).resolve().parents[1] / "docs/evidence/fcp-raster-markers-23976-20260919"


class RoundTripTests(unittest.TestCase):
    def test_native_5994_drop_frame_preserves_source_start_and_all_findings(self):
        evidence = EVIDENCE.parent / "fcp-native-markers-5994-20260919"
        result = fcp.compare(evidence / "original.fcpxml", evidence / "returned.fcpxml")
        self.assertEqual(result["status"], "differences")
        self.assertEqual({key for key, value in result["checks"].items() if not value},
                         {"exactMarkerContent"})
        self.assertTrue(result["contentMatchesAfterAttributeWhitespaceNormalization"])
        self.assertFalse(result["mediaIdentityVerified"])
        returned = result["returned"]
        rate = fcp.Fraction(1001, 60000)
        self.assertEqual(fcp.Fraction(returned["frameDuration"]), rate)
        self.assertEqual(fcp.Fraction(returned["start"]) / rate, 3480)
        self.assertEqual(returned["timecodeFormat"], "DF")
        self.assertEqual([fcp.Fraction(d) / rate for d in returned["durations"]],
                         [36563, 36563])
        review = json.loads((evidence / "original-review.json").read_text())
        self.assertEqual([m[0] for m in returned["markers"]],
                         sorted({n["primaryFrame"] for n in review["notes"]}))
        self.assertEqual(len(review["notes"]), 8)
        self.assertTrue(all(m[1] == 1 for m in returned["markers"]))
        # Check against the active review as well as the export: a finding lost
        # before import must not be accepted merely because both XMLs omit it.
        for note in review["notes"]:
            marker = next(m for m in returned["markers"] if m[0] == note["primaryFrame"])
            self.assertIn(note["text"].translate(str.maketrans("\t\r\n", "   ")), marker[3])
        grouped = next(m for m in returned["markers"] if m[0] == 120)
        self.assertEqual(grouped[2], "QC 004 + QC 005 (2 findings)")

    def test_native_player_duration_fix_leaves_only_whitespace_difference(self):
        evidence = EVIDENCE.parent / "fcp-native-duration-23976-20260919"
        result = fcp.compare(evidence / "original.fcpxml", evidence / "returned.fcpxml")
        self.assertEqual({key for key, value in result["checks"].items() if not value},
                         {"exactMarkerContent"})
        self.assertTrue(result["contentMatchesAfterAttributeWhitespaceNormalization"])
        self.assertEqual(len(result["returned"]["markers"]), 7)
        self.assertEqual(fcp.Fraction(result["original"]["durations"][0]) /
                         fcp.Fraction(result["original"]["frameDuration"]), 14625)
        before = fcp.compare(evidence / "before-fix.fcpxml", evidence / "original.fcpxml")
        self.assertEqual({key for key, value in before["checks"].items() if not value}, {"durations"})

    def test_native_raster_and_findings_pass_but_exact_acceptance_does_not(self):
        result = fcp.compare(EVIDENCE / "original.fcpxml", EVIDENCE / "returned.fcpxml")
        self.assertEqual(result["status"], "differences")
        self.assertFalse(result["mediaIdentityVerified"])
        self.assertEqual({key for key, value in result["checks"].items() if not value},
                         {"durations", "exactMarkerContent"})
        self.assertTrue(result["contentMatchesAfterAttributeWhitespaceNormalization"])
        self.assertEqual(len(result["returned"]["markers"]), 7)

    def test_same_export_matches_exactly(self):
        result = fcp.compare(EVIDENCE / "original.fcpxml", EVIDENCE / "original.fcpxml")
        self.assertEqual(result["status"], "exact-match")

    def changed(self, mutate):
        with tempfile.TemporaryDirectory() as directory:
            tree = ET.parse(EVIDENCE / "original.fcpxml")
            mutate(tree.getroot())
            path = Path(directory) / "changed.fcpxml"
            tree.write(path)
            return fcp.compare(EVIDENCE / "original.fcpxml", path)

    def test_missing_extra_and_changed_markers_fail(self):
        changes = [lambda r: r.find(".//asset-clip").remove(r.find(".//marker")),
                   lambda r: r.find(".//asset-clip").append(ET.fromstring(ET.tostring(r.find(".//marker")))),
                   lambda r: r.find(".//marker").set("start", "1001/24000s"),
                   lambda r: r.find(".//marker").set("duration", "1001/12000s"),
                   lambda r: r.find(".//marker").set("value", "Changed")]
        for change in changes:
            with self.subTest(change=change):
                self.assertFalse(self.changed(change)["checks"]["markerTimingAndTitles"])

    def test_whitespace_normalization_does_not_hide_other_content_loss(self):
        result = self.changed(lambda r: r.find(".//marker").set("note", "Missing finding"))
        self.assertFalse(result["contentMatchesAfterAttributeWhitespaceNormalization"])

    def test_raster_pixel_aspect_timecode_and_duration_changes_fail(self):
        for tag, attribute, value, check in [
            ("format", "width", "1280", "raster"),
            ("format", "paspH", "2", "pixelAspect"),
            ("asset-clip", "tcFormat", "DF", "timecodeFormat"),
            ("asset-clip", "duration", "600s", "durations"),
            ("asset", "start", "1s", "assetStart"),
        ]:
            with self.subTest(attribute=attribute):
                result = self.changed(lambda r: r.find(f".//{tag}").set(attribute, value))
                self.assertFalse(result["checks"][check])

    def test_ambiguous_empty_fractional_and_invalid_inputs_rejected(self):
        changes = [lambda r: r.find("event").append(ET.fromstring(ET.tostring(r.find(".//asset-clip")))),
                   lambda r: r.find("resources").append(ET.fromstring(ET.tostring(r.find(".//format")))),
                   lambda r: r.find(".//marker").set("start", "1/24000s"),
                   lambda r: r.find(".//marker").set("duration", "0s"),
                   lambda r: r.find(".//format").set("width", "0"),
                   lambda r: r.find(".//format").set("paspV", "0"),
                   lambda r: r.find(".//asset-clip").clear()]
        for change in changes:
            with self.subTest(change=change), self.assertRaises((ValueError, KeyError, ZeroDivisionError)):
                self.changed(change)

    def test_media_verification_uses_bytes_and_requires_available_local_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            exports = []
            for index in range(2):
                media = root / f"source {index}.mov"
                media.write_bytes(b"same media")
                tree = ET.parse(EVIDENCE / "original.fcpxml")
                tree.find(".//media-rep").set("src", media.as_uri())
                path = root / f"{index}.fcpxml"
                tree.write(path)
                exports.append(path)
            self.assertTrue(fcp.compare(*exports, verify_media=True)["mediaIdentityVerified"])
            media.write_bytes(b"different media")
            result = fcp.compare(*exports, verify_media=True)
            self.assertFalse(result["checks"]["sourceMediaBytes"])
            self.assertEqual(result["status"], "differences")
            media.unlink()
            with self.assertRaises(OSError):
                fcp.compare(*exports, verify_media=True)
        with self.assertRaises(ValueError):
            fcp.media_path("https://example.com/source.mov")

    def test_rational_time_validation(self):
        for value in ("NaNs", "1/0s", "1.5s", "1", "s"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                fcp.seconds(value)


if __name__ == "__main__":
    unittest.main()
