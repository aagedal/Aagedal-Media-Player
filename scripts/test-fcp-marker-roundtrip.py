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
    def test_fresh_player_ui_export_retains_native_asset_par_failure(self):
        evidence = EVIDENCE.parent / "fcp-production-ui-anamorphic-20260919"
        result = fcp.compare(evidence / "original.fcpxml", evidence / "returned.fcpxml")
        self.assertEqual(result["status"], "differences")
        self.assertEqual({key for key, ok in result["checks"].items() if not ok},
                         {"assetPixelAspect"})
        self.assertEqual(result["original"]["raster"], [180, 240])
        self.assertEqual(result["original"]["pixelAspect"], "3/4")
        self.assertEqual(result["returned"]["assetPixelAspect"], "4/3")
        self.assertEqual(result["returned"]["durations"], ["2", "2"])
        self.assertEqual(len(result["returned"]["markers"]), 1)
        self.assertEqual(result["returned"]["markers"][0][:3], (0, 1, "QC 001"))
        self.assertTrue(result["checks"]["exactMarkerContent"])
        self.assertFalse(result["mediaIdentityVerified"])

    def test_native_event_requires_explicit_unique_browser_selection(self):
        evidence = EVIDENCE.parent / "fcp-timeline-anamorphic-20260919"
        original = EVIDENCE.parent / "fcp-oriented-anamorphic-20260919/original.fcpxml"
        returned = evidence / "returned-event.fcpxml"
        name = "rotate-90-par.mp4 vs rotate-90-par.mp4 Oriented Diagnostic"
        with self.assertRaises(ValueError):
            fcp.compare(original, returned)
        result = fcp.compare(original, returned, returned_clip_name=name)
        self.assertEqual(result["returnedClipName"], name)
        self.assertEqual({key for key, ok in result["checks"].items() if not ok},
                         {"assetPixelAspect"})
        self.assertEqual([m[0] for m in result["returned"]["markers"]], [0, 1, 47])
        for missing in ("missing", "Aagedal Geometry Timeline 117", "independent-rotate-90-par"):
            with self.subTest(name=missing), self.assertRaises(ValueError):
                fcp.compare(original, returned, returned_clip_name=missing)
        for mutation in ("duplicate", "missing-browser-markers", "changed-browser-marker"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                tree = ET.parse(returned)
                event = tree.find(".//event")
                clip = next(c for c in event.findall("asset-clip") if c.get("name") == name)
                if mutation == "duplicate":
                    event.append(ET.fromstring(ET.tostring(clip)))
                elif mutation == "missing-browser-markers":
                    for marker in clip.findall("marker"):
                        clip.remove(marker)
                else:
                    clip.find("marker").set("note", "Lost browser finding")
                path = Path(directory) / "changed.fcpxml"
                tree.write(path)
                if mutation == "changed-browser-marker":
                    changed = fcp.compare(original, path, returned_clip_name=name)
                    self.assertFalse(changed["checks"]["exactMarkerContent"])
                else:
                    with self.assertRaises(ValueError):
                        fcp.compare(original, path, returned_clip_name=name)

    def test_native_direct_import_and_review_share_asset_geometry_in_timeline(self):
        root = ET.parse(EVIDENCE.parent / "fcp-timeline-anamorphic-20260919/returned-event.fcpxml")
        resources = {r.attrib["id"]: r for r in root.findall("./resources/*")}
        sequence = root.find(".//project/sequence")
        self.assertEqual(fcp.read_format(resources, sequence.get("format")),
                         dict(raster=[1080, 1920], pixelAspect="1", frameDuration="1/24"))
        clips = sequence.findall("spine/asset-clip")
        self.assertEqual(len(clips), 4)  # Three review appends, then the direct import.
        self.assertEqual([fcp.seconds(c.get("offset")) for c in clips], [0, 2, 4, 6])
        self.assertNotEqual(clips[0].get("ref"), clips[-1].get("ref"))
        formats = [fcp.read_format(resources, resources[c.get("ref")].get("format")) for c in clips]
        self.assertTrue(all(f == formats[0] for f in formats))
        self.assertEqual(formats[0], dict(raster=[180, 240], pixelAspect="4/3", frameDuration="1/24"))
        for clip in clips:
            self.assertIsNone(clip.find("adjust-transform"))
            self.assertIsNone(clip.find("adjust-conform"))
        self.assertEqual(fcp.read_format(resources, clips[0].get("format"))["pixelAspect"], "3/4")
        self.assertEqual(fcp.read_format(resources, clips[-1].get("format"))["pixelAspect"], "4/3")

    def test_oriented_anamorphic_clip_preserves_geometry_but_asset_par_still_differs(self):
        evidence = EVIDENCE.parent / "fcp-oriented-anamorphic-20260919"
        result = fcp.compare(evidence / "original.fcpxml", evidence / "returned.fcpxml")
        self.assertEqual(result["status"], "differences")
        self.assertEqual({key for key, value in result["checks"].items() if not value},
                         {"assetPixelAspect"})
        self.assertEqual(result["returned"]["raster"], [180, 240])
        self.assertEqual(result["returned"]["pixelAspect"], "3/4")
        self.assertEqual(result["returned"]["assetPixelAspect"], "4/3")
        self.assertEqual([m[0] for m in result["returned"]["markers"]], [0, 1, 47])
        self.assertFalse(result["mediaIdentityVerified"])

    def test_native_rotated_anamorphic_asset_change_cannot_pass_as_exact(self):
        evidence = EVIDENCE.parent / "fcp-rotated-anamorphic-20260919"
        result = fcp.compare(evidence / "original.fcpxml", evidence / "returned.fcpxml")
        self.assertEqual(result["status"], "differences")
        self.assertEqual({key for key, value in result["checks"].items() if not value},
                         {"assetRaster"})
        self.assertEqual(result["original"]["assetRaster"], [240, 180])
        self.assertEqual(result["returned"]["assetRaster"], [180, 240])
        self.assertEqual(result["returned"]["raster"], [240, 180])
        self.assertEqual(result["returned"]["assetPixelAspect"], "4/3")
        self.assertEqual([m[0] for m in result["returned"]["markers"]], [0, 1, 47])
        self.assertFalse(result["mediaIdentityVerified"])

    def test_asset_format_is_compared_independently_from_clip_format(self):
        def separate_asset_format(root, attribute, value):
            resources = root.find("resources")
            fmt = ET.fromstring(ET.tostring(resources.find("format")))
            fmt.set("id", "asset-format")
            fmt.set(attribute, value)
            resources.append(fmt)
            root.find(".//asset").set("format", "asset-format")
        for attribute, value, check in [("width", "180", "assetRaster"),
                                        ("paspH", "2", "assetPixelAspect"),
                                        ("frameDuration", "1/25s", "assetFrameDuration")]:
            with self.subTest(attribute=attribute):
                result = self.changed(lambda r: separate_asset_format(r, attribute, value))
                self.assertEqual({key for key, ok in result["checks"].items() if not ok}, {check})
        # Resource IDs are local aliases, not source identity.
        self.assertEqual(self.changed(lambda r: separate_asset_format(r, "width", "160"))["status"],
                         "exact-match")
        for attribute, value in [("width", "0"), ("paspV", "0"), ("frameDuration", "0s")]:
            with self.subTest(attribute=attribute), self.assertRaises((ValueError, ZeroDivisionError)):
                self.changed(lambda r: separate_asset_format(r, attribute, value))
        for reference in ("missing", "r2"):
            with self.subTest(reference=reference), self.assertRaises((ValueError, KeyError)):
                self.changed(lambda r: r.find(".//asset").set("format", reference))

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
