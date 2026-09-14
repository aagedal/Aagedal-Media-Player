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


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.input = Path(self.temporary.name) / "representative.mxf"
        self.input.write_bytes(b"representative production media fixture identity")
        self.digest = hashlib.sha256(self.input.read_bytes()).hexdigest()

    def tearDown(self):
        self.temporary.cleanup()

    def manifest(self):
        return [{"path": str(self.input), "sha256": self.digest}]

    def record(self):
        return {
            "schemaVersion": 1,
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
            "backend": "mpv",
            "observation": {
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
