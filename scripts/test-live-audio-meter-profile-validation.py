#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import copy
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "validator", Path(__file__).with_name("validate-live-audio-meter-profile.py")
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
input_spec = importlib.util.spec_from_file_location(
    "inputs", Path(__file__).with_name("live-audio-meter-profile-inputs.py")
)
inputs = importlib.util.module_from_spec(input_spec)
input_spec.loader.exec_module(inputs)


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.input = Path(self.temporary.name) / "representative.mxf"
        self.input.write_bytes(b"representative production media fixture identity")
        self.digest = hashlib.sha256(self.input.read_bytes()).hexdigest()

    def tearDown(self):
        self.temporary.cleanup()

    def manifest(self):
        return [{"path": str(self.input), "sha256": self.digest,
                 "audioStreamOrderIndex": 0, "audioTrackSelectionExplicit": False}]

    def record(self):
        return {
            "schemaVersion": 2,
            "inputIndex": 0,
            "file": "representative.mxf",
            "inputSHA256": self.digest,
            "durationSeconds": 60,
            "codec": "pcm_s24le",
            "declaredChannelLayout": "stereo",
            "channels": 2,
            "sampleRate": 48_000,
            "metadataStreamIndex": 3,
            "audioStreamOrderIndex": 0,
            "requestedAudioStreamOrderIndex": 0,
            "audioTrackSelectionExplicit": False,
            "availableAudioTrackCount": 2,
            "audioTrackLabel": "First stereo track",
            "backend": "mpv",
            "observation": {
                "audioStreamOrderIndex": 0,
                "metadataStreamIndex": 3,
                "startSourceFrame": 0,
                "endSourceFrame": 240_000,
                "publishedSnapshotCount": 30,
                "observationSeconds": 5,
                "wallSeconds": 5.02,
                "firstSnapshotLatencySeconds": 0.08,
                "maximumSnapshotIntervalSeconds": 0.12,
                "maximumAbsoluteClockDriftSeconds": 0.02,
                "clockDriftSampleCount": 12,
                "maximumDecodedAheadSeconds": 0.249,
                "initialAppResidentBytes": 100,
                "peakAppResidentBytes": 200,
                "peakChildResidentBytes": 50,
                "monitorRoutingInvariant": True,
                "cancellationObserved": True,
                "cancellationLatencySeconds": 0.03,
                "childResidentBytesAfterCancellation": 0,
            },
            "eof": {
                "audioStreamOrderIndex": 0,
                "metadataStreamIndex": 3,
                "observed": True,
                "finalSnapshot": True,
                "startSourceFrame": 2_640_000,
                "endSourceFrame": 2_880_000,
                "publishedSnapshotCount": 20,
                "wallSeconds": 5.1,
                "decoderVersion": "ffmpeg version 9.0.1",
                "timestampSource": "ffmpeg-framecrc-v1",
                "timestampTimeBase": "1/48000",
                "timestampFrameCount": 240_000,
                "syntheticInitialSilenceFrameCount": 1_024,
                "dynamicRangeCompressionDisabled": True,
                "codecNormalizationDisabled": True,
                "maximumAbsoluteClockDriftSeconds": 0.02,
                "clockDriftSampleCount": 10,
                "maximumDecodedAheadSeconds": 0.25,
                "peakAppResidentBytes": 210,
                "peakChildResidentBytes": 55,
            },
        }

    def test_accepts_complete_record(self):
        self.assertEqual(validator.validate([self.record()], self.manifest())[0]["backend"], "mpv")

    def test_accepts_deliberate_different_tracks_in_same_file(self):
        manifest = inputs.capture([str(self.input), "--audio-stream-order", "1", str(self.input)])
        first = self.record()
        second = copy.deepcopy(first)
        second.update({"inputIndex": 1, "audioStreamOrderIndex": 1,
                       "requestedAudioStreamOrderIndex": 1,
                       "audioTrackSelectionExplicit": True, "metadataStreamIndex": 4})
        for section in ("observation", "eof"):
            second[section].update({"audioStreamOrderIndex": 1, "metadataStreamIndex": 4})
        self.assertEqual(len(validator.validate([second, first], manifest)), 2)

    def test_rejects_requested_track_mismatch_and_retargeted_segments(self):
        for section, key, value in [
            (None, "requestedAudioStreamOrderIndex", 1),
            (None, "audioStreamOrderIndex", 1),
            (None, "audioTrackSelectionExplicit", True),
            (None, "availableAudioTrackCount", 0),
            (None, "audioTrackLabel", ""),
            (None, "audioTrackSelectionExplicit", 0),
            (None, "requestedAudioStreamOrderIndex", False),
            (None, "inputIndex", False),
            (None, "schemaVersion", 2.0),
            ("observation", "audioStreamOrderIndex", 1),
            ("eof", "audioStreamOrderIndex", 1),
            ("eof", "metadataStreamIndex", 4),
        ]:
            row = self.record()
            (row if section is None else row[section])[key] = value
            with self.subTest(section=section, key=key), self.assertRaises(ValueError):
                validator.validate([row], self.manifest())

    def test_rejects_non_default_track_without_explicit_request(self):
        manifest = self.manifest()
        manifest[0]["audioStreamOrderIndex"] = 1
        row = self.record()
        row.update({"requestedAudioStreamOrderIndex": 1, "audioStreamOrderIndex": 1})
        with self.assertRaisesRegex(ValueError, "requires deliberate selection"):
            validator.validate([row], manifest)

    def test_rejects_duplicate_file_and_track_request_with_distinct_record_indexes(self):
        second = self.record()
        second["inputIndex"] = 1
        with self.assertRaisesRegex(ValueError, "duplicate profile file/audio-stream"):
            validator.validate([self.record(), second], self.manifest() * 2)

    def test_input_selector_applies_only_to_next_file(self):
        manifest = inputs.capture(["--audio-stream-order", "1", str(self.input), str(self.input)])
        self.assertEqual([row["audioStreamOrderIndex"] for row in manifest], [1, 0])
        self.assertEqual([row["audioTrackSelectionExplicit"] for row in manifest], [True, False])
        self.assertEqual(manifest[0]["sha256"], self.digest)

    def test_input_capture_rejects_malformed_selectors_duplicates_and_missing_files(self):
        for arguments in [
            [], ["--audio-stream-order"], ["--audio-stream-order", "1"],
            ["--audio-stream-order", "-1", str(self.input)],
            ["--audio-stream-order", "1.0", str(self.input)],
            [str(self.input), "--audio-stream-order", "0", str(self.input)],
            [str(self.input.parent / "missing.mov")],
        ]:
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                inputs.capture(arguments)

    def test_rejects_missing_duplicate_and_wrong_input_identity(self):
        with self.assertRaises(ValueError):
            validator.validate([], self.manifest())
        with self.assertRaises(ValueError):
            validator.validate([self.record(), self.record()], self.manifest() * 2)
        row = self.record()
        row["inputSHA256"] = "b" * 64
        with self.assertRaises(ValueError):
            validator.validate([row], self.manifest())

    def test_rejects_input_changed_after_manifest_capture(self):
        row = self.record()
        self.input.write_bytes(b"replacement bytes")
        with self.assertRaisesRegex(ValueError, "changed after manifest capture"):
            validator.validate([row], self.manifest())

    def test_rejects_malformed_source_metadata(self):
        for key, value in [
            ("durationSeconds", 19), ("codec", ""), ("channels", 9), ("sampleRate", 88_200),
            ("backend", "unknown"), ("metadataStreamIndex", False),
        ]:
            row = self.record()
            row[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validator.validate([row], self.manifest())

    def test_rejects_incomplete_or_unbounded_observation(self):
        for key, value in [
            ("publishedSnapshotCount", 1), ("maximumDecodedAheadSeconds", 0.251),
            ("peakChildResidentBytes", 0), ("monitorRoutingInvariant", False),
            ("cancellationObserved", False), ("cancellationLatencySeconds", 5.1),
            ("childResidentBytesAfterCancellation", 1),
        ]:
            row = self.record()
            row["observation"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], self.manifest())

    def test_rejects_incomplete_or_inconsistent_eof_provenance(self):
        for key, value in [
            ("observed", False), ("finalSnapshot", False),
            ("timestampSource", "estimated"), ("timestampFrameCount", 1),
            ("syntheticInitialSilenceFrameCount", 240_001),
            ("dynamicRangeCompressionDisabled", False),
            ("codecNormalizationDisabled", False), ("peakChildResidentBytes", 0),
        ]:
            row = self.record()
            row["eof"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], self.manifest())

    def test_eof_time_base_must_match_each_supported_selected_rate(self):
        for rate in (44_100, 48_000, 96_000):
            row = self.record()
            row["sampleRate"] = rate
            row["observation"]["endSourceFrame"] = 5 * rate
            row["eof"]["timestampTimeBase"] = f"1/{rate}"
            with self.subTest(rate=rate):
                validator.validate([row], self.manifest())
                for invalid in ("1/1", "1/48001", "0/48000", "estimated", None):
                    row["eof"]["timestampTimeBase"] = invalid
                    with self.subTest(time_base=invalid), self.assertRaisesRegex(ValueError, "time base"):
                        validator.validate([row], self.manifest())

    def test_rejects_snapshot_timings_outside_observed_wall_interval(self):
        for changes in (
            {"firstSnapshotLatencySeconds": 5.03},
            {"maximumSnapshotIntervalSeconds": 5.03},
            {"firstSnapshotLatencySeconds": 4, "maximumSnapshotIntervalSeconds": 2},
            {"maximumSnapshotIntervalSeconds": 0},
        ):
            row = self.record()
            row["observation"].update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validator.validate([row], self.manifest())

    def test_observation_duration_matches_supported_runner_range(self):
        row = self.record()
        row["observation"].update({"observationSeconds": 30, "wallSeconds": 30.1})
        validator.validate([row], self.manifest())
        row["observation"].update({"observationSeconds": 31, "wallSeconds": 31.1})
        with self.assertRaisesRegex(ValueError, "observation duration"):
            validator.validate([row], self.manifest())

    def test_rejects_non_finite_numbers(self):
        for section, key in [
            ("observation", "firstSnapshotLatencySeconds"),
            ("observation", "maximumAbsoluteClockDriftSeconds"),
            ("eof", "wallSeconds"),
        ]:
            row = copy.deepcopy(self.record())
            row[section][key] = float("nan")
            with self.subTest(section=section, key=key), self.assertRaises(ValueError):
                validator.validate([row], self.manifest())


if __name__ == "__main__":
    unittest.main()
