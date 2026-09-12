#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression checks for complete metadata candidate source provenance."""

import argparse
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))
import metadata_candidate
from metadata_candidate import PINNED_REVISION, validate_candidate_provenance


BASELINE_ARCHIVE = "a" * 64
CANDIDATE_ARCHIVE = "b" * 64
PATCH = "c" * 64
CANDIDATE = "d" * 40


def provenance(mode="exactCheckout"):
    exact = mode == "exactCheckout"
    return {
        "schemaVersion": 1,
        "mode": mode,
        "baselineRevision": PINNED_REVISION,
        "baselineCheckout": "/baseline",
        "baselineArchiveSHA256": BASELINE_ARCHIVE,
        "candidateExpectedRevision": CANDIDATE if exact else PINNED_REVISION,
        "candidateResolvedRevision": CANDIDATE if exact else PINNED_REVISION,
        "candidateCheckout": "/candidate" if exact else "/baseline",
        "candidateArchiveSHA256": CANDIDATE_ARCHIVE if exact else BASELINE_ARCHIVE,
        "patchSHA256": None if exact else PATCH,
    }


class CandidateProvenanceTests(unittest.TestCase):
    def test_accepts_complete_exact_checkout_and_patch_modes(self):
        for mode in ("exactCheckout", "recordedPatch"):
            with self.subTest(mode=mode):
                self.assertEqual(validate_candidate_provenance(provenance(mode))["mode"], mode)

    def test_rejects_missing_and_extra_fields(self):
        for mutation in (lambda value: value.pop("candidateExpectedRevision"),
                         lambda value: value.update(unreviewed=True)):
            value = provenance()
            mutation(value)
            with self.assertRaises(ValueError):
                validate_candidate_provenance(value)

    def test_rejects_expected_resolved_mismatch(self):
        value = provenance()
        value["candidateResolvedRevision"] = "e" * 40
        with self.assertRaises(ValueError):
            validate_candidate_provenance(value)

    def test_rejects_abbreviated_or_malformed_hashes(self):
        for key, bad in (("candidateExpectedRevision", "d" * 12),
                         ("candidateArchiveSHA256", "not-a-digest"),
                         ("patchSHA256", "C" * 64)):
            value = provenance("recordedPatch" if key == "patchSHA256" else "exactCheckout")
            value[key] = bad
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_candidate_provenance(value)

    def test_rejects_patch_claim_for_exact_checkout(self):
        value = provenance()
        value["patchSHA256"] = PATCH
        with self.assertRaises(ValueError):
            validate_candidate_provenance(value)

    def test_rejects_missing_patch_identity_or_different_patch_source(self):
        for key, replacement in (("patchSHA256", None), ("candidateCheckout", "/candidate"),
                                 ("candidateArchiveSHA256", CANDIDATE_ARCHIVE)):
            value = provenance("recordedPatch")
            value[key] = replacement
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_candidate_provenance(value)

    def test_rejects_relative_checkout_paths(self):
        for key in ("baselineCheckout", "candidateCheckout"):
            value = provenance()
            value[key] = "relative"
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_candidate_provenance(value)

    def test_requires_candidate_checkout_and_expected_sha_together(self):
        parser = argparse.ArgumentParser()
        with tempfile.TemporaryDirectory() as temporary, \
                mock.patch.object(metadata_candidate, "_clean_revision"):
            baseline = Path(temporary)
            for checkout, sha in ((baseline, CANDIDATE), (None, CANDIDATE)):
                args = argparse.Namespace(candidate_checkout=checkout, expected_candidate_sha=sha)
                if checkout is baseline:
                    args.expected_candidate_sha = None
                with self.subTest(checkout=checkout), self.assertRaises(SystemExit):
                    metadata_candidate.resolve_candidate(args, parser, baseline, baseline / "patch")

    def test_rejects_abbreviated_expected_sha_before_candidate_use(self):
        parser = argparse.ArgumentParser()
        with tempfile.TemporaryDirectory() as temporary, \
                mock.patch.object(metadata_candidate, "_clean_revision"):
            baseline = Path(temporary)
            candidate = baseline / "candidate"
            candidate.mkdir()
            args = argparse.Namespace(candidate_checkout=candidate, expected_candidate_sha=CANDIDATE[:12])
            with self.assertRaises(SystemExit):
                metadata_candidate.resolve_candidate(args, parser, baseline, baseline / "patch")

    def test_rejects_candidate_whose_head_does_not_match_expected_sha(self):
        parser = argparse.ArgumentParser()
        with tempfile.TemporaryDirectory() as temporary:
            baseline = Path(temporary)
            candidate = baseline / "candidate"
            candidate.mkdir()
            args = argparse.Namespace(candidate_checkout=candidate, expected_candidate_sha=CANDIDATE)
            def inspect(_checkout, _expected, active_parser, label):
                if label == "candidate":
                    active_parser.error("candidate mismatch")
                return PINNED_REVISION
            with mock.patch.object(metadata_candidate, "_clean_revision", side_effect=inspect), \
                    self.assertRaises(SystemExit):
                metadata_candidate.resolve_candidate(args, parser, baseline, baseline / "patch")


if __name__ == "__main__":
    unittest.main()
