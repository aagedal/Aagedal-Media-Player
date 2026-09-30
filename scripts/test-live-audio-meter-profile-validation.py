#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


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
settings_spec = importlib.util.spec_from_file_location(
    "settings", Path(__file__).with_name("live-audio-meter-profile-settings.py")
)
settings = importlib.util.module_from_spec(settings_spec)
settings_spec.loader.exec_module(settings)


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

    def test_native_output_gate_rejects_failed_driver_despite_passing_meter_record(self):
        rows = validator.validate([self.record()], self.manifest())
        for failure in (
            "[ao/coreaudio] error: unable to set the input channel layout on the audio unit (-50)",
            "[ao/avfoundation] fatal: unable to create player",
            "[ao] error: Failed to initialize audio driver 'coreaudio'",
            "[cplayer] error: Audio output initialization failed.",
            "[AudioConverter] channel mapping input channel '6619138' for output channel '0' is out of range [-1..'2')",
        ):
            # A later fallback driver, successful video clock, and meter row
            # cannot turn a failed native output initialization into acceptance.
            log = validator.NATIVE_LOGGING_MARKER + "\n" + failure + "\nAO: [avfoundation] 48000Hz stereo\n"
            with self.subTest(failure=failure), self.assertRaisesRegex(ValueError, "native audio output reported"):
                validator.validate_native_output_log(log, rows)

    def test_native_output_gate_requires_release_logging_and_accepts_non_output_warnings(self):
        rows = [self.record()]
        with self.assertRaisesRegex(ValueError, "logging was not enabled"):
            validator.validate_native_output_log("", rows)
        validator.validate_native_output_log(validator.NATIVE_LOGGING_MARKER + "\n"
            "[ao/coreaudio] warn: sample rate differs\n[vd] error: decoder fallback\n", rows)
        rows[0]["backend"] = "avFoundation"
        validator.validate_native_output_log("", rows)

    def test_native_output_gate_rejects_retained_false_passing_coreaudio_baseline(self):
        retained = Path(__file__).resolve().parents[1] / "docs/evidence/live-meter-native-output-20260930/safe-baseline/profile.log"
        # These schema-2 source-meter runs historically passed despite this AO
        # failure. Add the new logging receipt to exercise the failure itself.
        with self.assertRaisesRegex(ValueError, "native audio output reported"):
            validator.validate_native_output_log(
                validator.NATIVE_LOGGING_MARKER + "\n" + retained.read_text(), [self.record()])

    def test_rejected_native_output_removes_previous_passing_summary(self):
        root = Path(self.temporary.name) / "profile"
        (root / "attachments").mkdir(parents=True)
        (root / "inputs.json").write_text(json.dumps(self.manifest()))
        (root / "attachments/record.txt").write_text(
            "LIVE_AUDIO_METER_PROFILE " + json.dumps(self.record()) + "\n")
        (root / "profile.log").write_text(validator.NATIVE_LOGGING_MARKER + "\n")
        with patch.object(validator.sys, "argv", ["validator", str(root)]), patch("builtins.print"):
            validator.main()
            self.assertTrue((root / "summary.json").is_file())
            (root / "profile.log").write_text(validator.NATIVE_LOGGING_MARKER + "\n"
                "[ao/coreaudio] error: unable to set the input channel layout on the audio unit (-50)\n")
            with self.assertRaisesRegex(ValueError, "native audio output reported"):
                validator.main()
            self.assertFalse((root / "summary.json").exists())

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
        for duration in (5, 30, 1_800):
            row = self.record()
            row["durationSeconds"] = duration + 20
            row["observation"].update({"observationSeconds": duration, "wallSeconds": duration + 0.1,
                                       "endSourceFrame": duration * row["sampleRate"]})
            with self.subTest(duration=duration):
                validator.validate([row], self.manifest())
        row["observation"].update({"observationSeconds": 1_801, "wallSeconds": 1_801.1})
        with self.assertRaisesRegex(ValueError, "observation duration"):
            validator.validate([row], self.manifest())

    def test_long_observation_requires_source_progress_and_transport_headroom(self):
        row = self.record()
        row["durationSeconds"] = 1_820
        row["observation"].update({"observationSeconds": 1_800, "wallSeconds": 1_800.1})
        with self.assertRaisesRegex(ValueError, "enough paced source frames"):
            validator.validate([row], self.manifest())
        row["observation"]["endSourceFrame"] = 1_800 * row["sampleRate"]
        row["durationSeconds"] = 1_809
        with self.assertRaisesRegex(ValueError, "transport-check headroom"):
            validator.validate([row], self.manifest())

    def test_runner_deadline_scales_for_soak_and_each_input(self):
        self.assertEqual(settings.execution_time_allowance("5", 1), 305)
        self.assertEqual(settings.execution_time_allowance("5.5", 2), 491)
        self.assertEqual(settings.execution_time_allowance("1800", 2), 4_080)
        for value in ("bad", "nan", "inf", "4.99", "1800.01"):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "PROFILE_SECONDS"):
                settings.execution_time_allowance(value, 1)

    def test_runner_rejects_invalid_duration_before_build_or_artifact_creation(self):
        script = Path(__file__).with_name("profile-live-audio-meter.sh").resolve()
        for value in ("nan", "1800.01"):
            artifact = Path(self.temporary.name) / f"invalid-duration-{value}"
            environment = dict(os.environ, LIVE_AUDIO_METER_PROFILE_SECONDS=value)
            result = subprocess.run(["/bin/zsh", str(script), str(artifact), str(self.input)],
                                    env=environment, capture_output=True, text=True, timeout=10)
            with self.subTest(value=value):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("LIVE_AUDIO_METER_PROFILE_SECONDS", result.stderr)
                self.assertNotIn("Building production", result.stderr)
                self.assertFalse(artifact.exists())

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
