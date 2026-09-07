#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression checks for incomplete or misleading metadata profile artifacts."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

validator_path = Path(__file__).with_name("validate-metadata-memory-profile.py")
validate = runpy.run_path(str(validator_path))["validate"]


def fixture():
    snapshot = dict(format="mp4", duration=3600, fileSize=1000, bitRate=None,
                    title=None, comment=None, videoStreamCount=0, subtitleStreamCount=0,
                    chapterCount=0, hasRTMD=False, audioStreams=[dict(codec="alac", sampleRate=48000,
                    channels=6, bitDepth=16, duration=3600, bitRate=None, channelLayout="5.1")])
    records = []
    for variant in ("baseline", "fixed"):
        for mode in ("read", "rtmd", "skip-mdat"):
            names = ["initial", "retained", "released"] if mode == "read" else ["initial", "mapped", "probed", "released"]
            phases = [dict(phase=name, residentBytes=100, lifetimePeakResidentBytes=200) for name in names]
            phases[-1]["wallSeconds"] = 0.01
            if mode == "read":
                phases[1]["metadata"] = copy.deepcopy(snapshot)
            elif mode == "rtmd":
                phases[2]["hasRTMD"] = False
            else:
                phases[2].update(boxTypes=["ftyp", "mdat", "moov"], payloadBytes=100)
            records.append(dict(variant=variant, input="/fixture.m4a", mode=mode, phases=phases))
    return records


class MetadataMemoryValidationTests(unittest.TestCase):
    def test_complete_matrix(self):
        validate(fixture(), ["/fixture.m4a"])

    def test_missing_duplicate_and_unknown_workloads(self):
        rows = fixture()
        for bad in (rows[:-1], rows + [rows[0]], rows[1:] + [dict(rows[0], mode="unknown")]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                validate(bad, ["/fixture.m4a"])
        for inputs in ([], ["/fixture.m4a"] * 2, ["/other.m4a"]):
            with self.subTest(inputs=inputs), self.assertRaises(ValueError):
                validate(rows, inputs)

    def test_bad_phase_sequence(self):
        rows = fixture()
        rows[0]["phases"].reverse()
        with self.assertRaises(ValueError):
            validate(rows, ["/fixture.m4a"])

    def test_invalid_memory_and_time(self):
        for field, values in (("residentBytes", [0, -1, True, 1.5, float("nan"), 201]),
                              ("lifetimePeakResidentBytes", [0, -1, True, float("inf"), 99, 199]),
                              ("wallSeconds", [0, -1, True, float("nan"), float("inf")])):
            for value in values:
                rows = fixture()
                rows[0]["phases"][-1][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    validate(rows, ["/fixture.m4a"])

    def test_equal_but_incomplete_or_nonfinite_snapshots(self):
        for snapshot in ({}, dict(fixture()[0]["phases"][1]["metadata"], duration=float("nan")),
                         dict(fixture()[0]["phases"][1]["metadata"], audioStreams=[{}])):
            rows = fixture()
            for index in (0, 3):
                rows[index]["phases"][1]["metadata"] = snapshot
            with self.subTest(snapshot=snapshot), self.assertRaises(ValueError):
                validate(rows, ["/fixture.m4a"])

    def test_each_parity_result_is_checked(self):
        for index, field, value in ((3, "metadata", dict(fixture()[0]["phases"][1]["metadata"], duration=2)),
                                    (4, "hasRTMD", True), (5, "payloadBytes", 101), (5, "boxTypes", ["moov"])):
            rows = fixture()
            rows[index]["phases"][1 if index == 3 else 2][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(rows, ["/fixture.m4a"])

    def test_malformed_snapshot_scalar_types(self):
        for field, values in (("duration", ["broken", True, -1]), ("fileSize", [False, 1.5]),
                              ("title", [5]), ("comment", [[]]), ("bitRate", ["unknown"])):
            for value in values:
                rows = fixture()
                for index in (0, 3):
                    rows[index]["phases"][1]["metadata"][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    validate(rows, ["/fixture.m4a"])
        for field, value in (("channels", True), ("bitDepth", 1.5), ("sampleRate", "48000"),
                             ("duration", -1), ("bitRate", False), ("codec", 123), ("channelLayout", [])):
            rows = fixture()
            rows[0]["phases"][1]["metadata"]["audioStreams"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(rows, ["/fixture.m4a"])

    def test_cli_reconciles_raw_artifacts_with_summary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            rows = fixture()
            (root / "environment.json").write_text(json.dumps({"inputs": [{"path": "/fixture.m4a"}]}))
            for row in rows:
                directory = root / row["variant"]
                directory.mkdir(exist_ok=True)
                (directory / f'input-0-{row["mode"]}.jsonl').write_text("\n".join(json.dumps(p) for p in row["phases"]))
            summary = root / "summary.json"
            summary.write_text(json.dumps({"snapshotParity": True, "records": rows}))
            command = [sys.executable, str(validator_path), str(root)]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            rows[0]["phases"][1]["metadata"]["hasRTMD"] = 0
            summary.write_text(json.dumps({"snapshotParity": True, "records": rows}))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            rows[0]["phases"][1]["metadata"]["hasRTMD"] = False
            rows[0]["phases"][0]["residentBytes"] = 101
            summary.write_text(json.dumps({"snapshotParity": True, "records": rows}))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            (root / "fixed/input-0-rtmd.jsonl").unlink()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
