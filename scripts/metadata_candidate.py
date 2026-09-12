#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Shared, fail-closed source selection for metadata candidate harnesses."""

import hashlib
from pathlib import Path
import re
import subprocess


PINNED_REVISION = "c2d77c2dcefcb997623e52beca57bc61ce302cb9"
_SHA1 = re.compile(r"^[0-9a-f]{40}$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def git(checkout, *arguments):
    return subprocess.check_output(["git", "-C", str(checkout), *arguments])


def archive(checkout):
    return git(checkout, "archive", "HEAD")


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def add_candidate_arguments(parser):
    parser.add_argument(
        "--candidate-checkout",
        type=Path,
        help="clean candidate checkout to test instead of applying the recorded patch",
    )
    parser.add_argument(
        "--expected-candidate-sha",
        help="full 40-character commit SHA required with --candidate-checkout",
    )


def _clean_revision(checkout, expected, parser, label):
    try:
        resolved = git(checkout, "rev-parse", "HEAD").decode().strip()
        dirty = git(checkout, "status", "--porcelain").strip()
    except (OSError, subprocess.CalledProcessError) as error:
        parser.error(f"Could not inspect {label} checkout: {error}")
    if resolved != expected or dirty:
        parser.error(f"Expected clean {label} checkout at {expected}: {checkout}")
    return resolved


class CandidateSource:
    """Pinned baseline plus either the recorded patch or an exact candidate commit."""

    def __init__(self, baseline, candidate, expected, patch):
        self.baseline = baseline
        self.candidate = candidate
        self.expected = expected
        self.patch = patch
        self.mode = "exactCheckout" if candidate != baseline else "recordedPatch"
        self._baseline_archive = archive(baseline)
        self._candidate_archive = archive(candidate)
        self._provenance = {
            "schemaVersion": 1,
            "mode": self.mode,
            "baselineRevision": PINNED_REVISION,
            "baselineCheckout": str(baseline),
            "baselineArchiveSHA256": sha256_bytes(self._baseline_archive),
            "candidateExpectedRevision": expected,
            "candidateResolvedRevision": git(candidate, "rev-parse", "HEAD").decode().strip(),
            "candidateCheckout": str(candidate),
            "candidateArchiveSHA256": sha256_bytes(self._candidate_archive),
            "patchSHA256": digest(patch) if self.mode == "recordedPatch" else None,
        }
        validate_candidate_provenance(self._provenance)

    @property
    def provenance(self):
        return dict(self._provenance)

    def checkout_for(self, variant):
        return self.baseline if variant == "baseline" else self.candidate

    def archive_for(self, variant):
        return self._baseline_archive if variant == "baseline" else self._candidate_archive

    def apply_patch(self, package, log):
        if self.mode != "recordedPatch":
            return
        with Path(log).open("w") as output:
            subprocess.run(
                ["patch", "-p1", "-i", str(self.patch)], cwd=package,
                stdout=output, stderr=subprocess.STDOUT, check=True, timeout=60,
            )

    def verify_unchanged(self):
        for checkout, expected, expected_archive in (
            (self.baseline, PINNED_REVISION, self._baseline_archive),
            (self.candidate, self.expected, self._candidate_archive),
        ):
            if (git(checkout, "rev-parse", "HEAD").decode().strip() != expected
                    or git(checkout, "status", "--porcelain").strip()
                    or archive(checkout) != expected_archive):
                return False
        return True


def resolve_candidate(args, parser, baseline, patch):
    """Validate command arguments and return a source selection."""
    baseline = Path(baseline).resolve(strict=True)
    _clean_revision(baseline, PINNED_REVISION, parser, "pinned baseline")
    supplied_checkout = args.candidate_checkout is not None
    supplied_sha = args.expected_candidate_sha is not None
    if supplied_checkout != supplied_sha:
        parser.error("--candidate-checkout and --expected-candidate-sha must be supplied together")
    if not supplied_checkout:
        return CandidateSource(baseline, baseline, PINNED_REVISION, Path(patch))
    expected = args.expected_candidate_sha
    if not isinstance(expected, str) or not _SHA1.fullmatch(expected):
        parser.error("--expected-candidate-sha must be a full lowercase 40-character commit SHA")
    candidate = args.candidate_checkout.resolve(strict=True)
    if candidate == baseline:
        parser.error("Exact candidate checkout must be separate from the pinned baseline checkout")
    _clean_revision(candidate, expected, parser, "candidate")
    return CandidateSource(baseline, candidate, expected, Path(patch))


def validate_candidate_provenance(value):
    """Reject incomplete, ambiguous, or internally inconsistent source evidence."""
    required = {
        "schemaVersion", "mode", "baselineRevision", "baselineCheckout",
        "baselineArchiveSHA256", "candidateExpectedRevision",
        "candidateResolvedRevision", "candidateCheckout",
        "candidateArchiveSHA256", "patchSHA256",
    }
    if not isinstance(value, dict) or set(value) != required:
        raise ValueError("Incomplete candidate provenance")
    if type(value["schemaVersion"]) is not int or value["schemaVersion"] != 1 \
            or value["mode"] not in {"recordedPatch", "exactCheckout"}:
        raise ValueError("Invalid candidate provenance mode or version")
    if value["baselineRevision"] != PINNED_REVISION:
        raise ValueError("Unexpected baseline revision provenance")
    for key in ("baselineRevision", "candidateExpectedRevision", "candidateResolvedRevision"):
        if not isinstance(value[key], str) or not _SHA1.fullmatch(value[key]):
            raise ValueError(f"Invalid candidate provenance SHA: {key}")
    for key in ("baselineArchiveSHA256", "candidateArchiveSHA256"):
        if not isinstance(value[key], str) or not _SHA256.fullmatch(value[key]):
            raise ValueError(f"Invalid candidate provenance digest: {key}")
    for key in ("baselineCheckout", "candidateCheckout"):
        if not isinstance(value[key], str) or not Path(value[key]).is_absolute():
            raise ValueError(f"Invalid candidate provenance path: {key}")
    if value["candidateExpectedRevision"] != value["candidateResolvedRevision"]:
        raise ValueError("Candidate expected and resolved revisions differ")
    if value["mode"] == "recordedPatch":
        if (value["candidateExpectedRevision"] != PINNED_REVISION
                or value["candidateCheckout"] != value["baselineCheckout"]
                or value["candidateArchiveSHA256"] != value["baselineArchiveSHA256"]
                or not isinstance(value["patchSHA256"], str)
                or not _SHA256.fullmatch(value["patchSHA256"])):
            raise ValueError("Inconsistent recorded-patch provenance")
    elif (value["candidateCheckout"] == value["baselineCheckout"]
          or value["patchSHA256"] is not None):
        raise ValueError("Inconsistent exact-checkout provenance")
    return value
