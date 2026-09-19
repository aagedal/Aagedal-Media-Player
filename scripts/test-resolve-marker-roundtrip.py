#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regressions for retained editor loss and strict round-trip evidence."""
from fractions import Fraction
import importlib.util
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("validator", Path(__file__).with_name("validate-resolve-marker-roundtrip.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
generator_spec = importlib.util.spec_from_file_location("generator", Path(__file__).with_name("generate-review-interchange-fixtures.py"))
generator = importlib.util.module_from_spec(generator_spec)
generator_spec.loader.exec_module(generator)
RATE = Fraction(30000, 1001)
EVIDENCE = Path(__file__).resolve().parents[1] / "docs/evidence/resolve-markers-20260915"


def edl(start="00:00:58;00", end="00:00:58;01", note="Unicode æøå 日本語", duration=1):
    return (f"TITLE: Test\nFCM: DROP FRAME\n001 001 V C {start} {end} {start} {end}\n"
            f" |C:ResolveColorBlue |M:{note} |D:{duration}\n")


class RoundTripTests(unittest.TestCase):
    def native_fixture(self, root, rate="59.94"):
        suffix = {"59.94": "5994", "23.976": "23976"}[rate]
        evidence = EVIDENCE.with_name(f"resolve-markers-{suffix}-20260919")
        manifest = self.make_fixture(root, rate)
        snapshot = json.loads((evidence / "native-snapshot.json").read_text())
        old_root = str(Path(snapshot["clips"][0]["path"]).parent)
        # Adapt captured records only in the temporary test; retained evidence is immutable.
        snapshot = json.loads(json.dumps(snapshot).replace(old_root, str(root.resolve())))
        original = (evidence / "source-a_vs_source-b_review.edl").read_text().replace(old_root, str(root.resolve()))
        return manifest, snapshot, original

    def test_native_snapshot_matches_actual_retained_records(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest, snapshot, original = self.native_fixture(root)
            path = root / "snapshot.json"
            path.write_text(json.dumps(snapshot))
            result = validator.verify_native_snapshot(path, manifest, original, Fraction(60000, 1001), "21.1.0.14")
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["markerCount"], 7)
            self.assertEqual(result["snapshotSHA256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_native_relative_time_snapshot_requires_zero_start_and_exact_rate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest, snapshot, original = self.native_fixture(root, "23.976")
            self.assertIsNone(json.loads(manifest.read_text())["sourceStartTimecode"])
            path = root / "snapshot.json"
            path.write_text(json.dumps(snapshot))
            result = validator.verify_native_snapshot(path, manifest, original, Fraction(24000, 1001), "21.1.0.14")
            self.assertEqual((result["status"], result["markerCount"], result["startTimecode"]),
                             ("passed", 7, "00:00:00:00"))
            for key, value in [("startTimecode", "01:00:00:00"), ("rate", "24"),
                               ("dropFrame", "1"), ("startFrame", "1")]:
                changed = copy.deepcopy(snapshot)
                changed["metadata"][key] = value
                path.write_text(json.dumps(changed))
                with self.subTest(key=key), self.assertRaises(ValueError):
                    validator.verify_native_snapshot(path, manifest, original, Fraction(24000, 1001), "21.1.0.14")

    def test_native_wrong_media_and_timeline_configuration_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest, snapshot, original = self.native_fixture(root)
            mutations = [("metadata", key, value) for key, value in {
                "schemaVersion": "2", "editorVersion": "old", "rate": "29.97", "dropFrame": "0",
                "startTimecode": "01:00:00;00", "startFrame": "3481", "endFrame": "40042",
                "videoTracks": "2", "project": "", "timeline": ""}.items()]
            mutations.append(("metadata", "rate", None))
            mutations += [("clip", key, value) for key, value in {
                "path": str(root / "source-b.mov"), "fps": "60", "sourceStart": "00:00:00:00",
                "sourceFrames": "36562", "startFrame": "3481", "endFrame": "40042",
                "leftOffset": "0.5"}.items()]
            for section, key, value in mutations:
                changed = copy.deepcopy(snapshot)
                target = changed["metadata"] if section == "metadata" else changed["clips"][0]
                target[key] = value
                path = root / "snapshot.json"
                path.write_text(json.dumps(changed))
                with self.subTest(section=section, key=key), self.assertRaises(ValueError):
                    validator.verify_native_snapshot(path, manifest, original, Fraction(60000, 1001), "21.1.0.14")

    def test_native_marker_loss_extras_and_content_changes_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest, snapshot, original = self.native_fixture(root)
            variants = []
            for key, value in [("frame", "-1"), ("frame", "0.5"), ("duration", "2"),
                               ("color", "Red"), ("name", "lost Unicode"), ("note", "extra note")]:
                changed = copy.deepcopy(snapshot)
                changed["markers"][0][key] = value
                variants.append(changed)
            for key in ("markers", "clips"):
                for replacement in ([], None, snapshot[key] + [snapshot[key][0]]):
                    changed = copy.deepcopy(snapshot)
                    changed[key] = replacement
                    variants.append(changed)
            variants.extend([{}, {"metadata": []}])
            for changed in variants:
                path = root / "snapshot.json"
                path.write_text(json.dumps(changed))
                with self.subTest(changed=changed), self.assertRaises(ValueError):
                    validator.verify_native_snapshot(path, manifest, original, Fraction(60000, 1001), "21.1.0.14")

    def test_native_cli_requires_fixture_and_retains_both_evidence_types(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest, snapshot, original = self.native_fixture(root)
            path = root / "snapshot.json"
            path.write_text(json.dumps(snapshot))
            source = root / "original.edl"
            source.write_text(original)
            output = root / "result.json"
            args = ["validator", str(source), str(source), "--rate", "60000/1001", "--editor-version",
                    "21.1.0.14", "--native-snapshot", str(path), "--output", str(output)]
            with patch("sys.argv", args), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(validator.main(), 1)
            self.assertFalse(output.exists())
            args.extend(["--fixture-manifest", str(manifest)])
            with patch("sys.argv", args), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(validator.main(), 0)
            result = json.loads(output.read_text())
            self.assertEqual(result["nativeTimeline"]["status"], "passed")
            self.assertEqual(result["fixtureProvenance"]["status"], "passed")

    def make_fixture(self, root, rate="29.97", resolve_copy=True):
        def fake_encode(command, **kwargs):
            Path(command[-1]).write_bytes(b"stand-in for generated media")

        def canonical_paths(command, **kwargs):
            return json.dumps([str(Path(path).resolve()) for path in command[-2:]])

        args = ["generator", str(root), "--rate", rate]
        if resolve_copy:
            args.append("--resolve-copy")
        with patch("sys.argv", args), patch.object(generator.subprocess, "run", fake_encode), \
                patch.object(generator.subprocess, "check_output", canonical_paths), contextlib.redirect_stdout(io.StringIO()):
            generator.main()
        return root / "fixture-manifest.json"

    def fixture_edl(self, root):
        note = (f"Finding / Source A URL: {(root / 'source-a.mov').as_uri()}"
                f" / Source B URL: {(root / 'source-b.mov').as_uri()}")
        source = edl(note=note)
        return source + ("\n".join(source.splitlines()[2:]) + "\n") * 6

    def test_resolve_copy_preserves_full_review_at_all_fixture_rates(self):
        for rate in ("29.97", "59.94", "23.976"):
            with self.subTest(rate=rate), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "fixture"
                manifest = json.loads(self.make_fixture(root, rate).read_text())
                copy = json.loads((root / manifest["reviewFile"]).read_text())
                original_name = next(name for name in manifest["sha256"] if " vs " in name)
                original = json.loads((root / original_name).read_text())
                self.assertEqual(len(original["notes"]), 8)
                self.assertEqual(len(copy["notes"]), 7)
                self.assertEqual(len({note["primaryFrame"] for note in copy["notes"]}), 7)
                self.assertEqual(copy["notes"], [note for note in original["notes"]
                                               if note["id"] not in manifest["omittedFindingIDs"]])
                omitted = [note for note in original["notes"] if note["id"] in manifest["omittedFindingIDs"]]
                self.assertEqual(len(omitted), 1)
                self.assertTrue(omitted[0]["text"].startswith("Fixture 5:"))
                for name, digest in manifest["sha256"].items():
                    self.assertEqual(hashlib.sha256((root / name).read_bytes()).hexdigest(), digest)
                with self.assertRaises(FileExistsError):
                    self.make_fixture(root, rate)

    def test_default_fixture_still_has_all_findings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest = json.loads(self.make_fixture(root, resolve_copy=False).read_text())
            self.assertEqual(manifest["reviewMarkerCount"], 8)
            self.assertEqual(manifest["omittedFindingIDs"], [])
            self.assertFalse((root / "resolve-unique.aagedal-compare.json").exists())

    def test_current_fixture_provenance_and_stale_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture with spaces"
            manifest = self.make_fixture(root)
            source = self.fixture_edl(root)
            result = validator.verify_fixture(manifest, source, source, RATE)
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["markerCount"], 7)
            for changed in (source.replace("source-a.mov", "old-source-a.mov"),
                            source.replace("source-b.mov", "old-source-b.mov"),
                            source.replace("file:", "https:"),
                            source.replace(" / Source A URL: ", " / missing: "), edl()):
                with self.subTest(changed=changed), self.assertRaises(ValueError):
                    validator.verify_fixture(manifest, source, changed, RATE)
            with self.assertRaises(ValueError):
                validator.verify_fixture(manifest, source, source, Fraction(60000, 1001))

    def test_changed_media_or_review_fails_provenance(self):
        for filename in ("source-a.mov", "source-b.mov", "resolve-unique.aagedal-compare.json"):
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "fixture"
                manifest = self.make_fixture(root)
                source = self.fixture_edl(root)
                with (root / filename).open("ab") as output:
                    output.write(b"changed")
                with self.assertRaisesRegex(ValueError, "Fixture input changed"):
                    validator.verify_fixture(manifest, source, source, RATE)

    def test_moved_fixture_and_unsafe_manifest_fail_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest = self.make_fixture(root)
            moved = root.with_name("moved")
            root.rename(moved)
            source = self.fixture_edl(moved)
            manifest = moved / manifest.name
            with self.assertRaisesRegex(ValueError, "Review source identity"):
                validator.verify_fixture(manifest, source, source, RATE)
            data = json.loads(manifest.read_text())
            data["sha256"] = {"../outside": "0" * 64}
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "directly beside"):
                validator.verify_fixture(manifest, source, source, RATE)

    def test_cli_retains_provenance_and_never_overwrites_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            manifest = self.make_fixture(root)
            source = root / "original.edl"
            returned = root / "returned.edl"
            source.write_text(self.fixture_edl(root))
            returned.write_bytes(source.read_bytes())
            output = root / "result.json"
            args = ["validator", str(source), str(returned), "--rate", "30000/1001",
                    "--editor-version", "test-only", "--fixture-manifest", str(manifest),
                    "--output", str(output)]
            with patch("sys.argv", args), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(validator.main(), 0)
            saved = output.read_bytes()
            report = json.loads(saved)
            self.assertEqual(report["fixtureProvenance"]["manifestSHA256"],
                             hashlib.sha256(manifest.read_bytes()).hexdigest())
            with patch("sys.argv", args), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(validator.main(), 1)
            self.assertEqual(output.read_bytes(), saved)
            returned.write_text(returned.read_text().replace("source-a.mov", "stale.mov"))
            args[-1] = str(root / "invalid-result.json")
            with patch("sys.argv", args), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(validator.main(), 1)
            self.assertFalse((root / "invalid-result.json").exists())

    def test_retained_clean_native_roundtrip_passes(self):
        for directory, original, rate in [
            ("resolve-markers-20260919", "unique-markers.edl", RATE),
            ("resolve-markers-5994-20260919", "source-a_vs_source-b_review.edl", Fraction(60000, 1001)),
            ("resolve-markers-23976-20260919", "source-a_vs_source-b_review.edl", Fraction(24000, 1001)),
        ]:
            with self.subTest(rate=rate):
                evidence = EVIDENCE.with_name(directory)
                report = validator.compare((evidence / original).read_text(),
                                           (evidence / "resolve-roundtrip.edl").read_text(), rate)
                self.assertEqual(report["status"], "passed")
                self.assertEqual((report["expectedCount"], report["actualCount"]), (7, 7))
                self.assertEqual(report["missing"], [])
                self.assertEqual(report["unexpected"], [])

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
