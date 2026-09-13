#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("validate-github-release-asset.py")
SPEC = importlib.util.spec_from_file_location("release_asset_validator", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GitHubReleaseAssetValidationTests(unittest.TestCase):
    name = "Aagedal_Media_Player_2-0-0.zip"
    digest = "a" * 64

    def asset(self, **changes: object) -> dict[str, object]:
        value: dict[str, object] = {
            "name": self.name,
            "state": "uploaded",
            "size": 1234,
            "digest": f"sha256:{self.digest}",
        }
        value.update(changes)
        return value

    def validate(self, payload: object) -> None:
        MODULE.validate_asset(
            payload,
            expected_name=self.name,
            expected_size=1234,
            expected_sha256=self.digest,
        )

    def test_accepts_one_uploaded_asset_with_matching_size_and_digest(self) -> None:
        self.validate({"assets": [self.asset(), self.asset(name="source.zip")]})

    def test_rejects_missing_or_duplicate_named_asset(self) -> None:
        for assets in ([], [self.asset(), self.asset()]):
            with self.subTest(count=len(assets)), self.assertRaises(ValueError):
                self.validate({"assets": assets})

    def test_rejects_nonuploaded_wrong_size_or_boolean_size(self) -> None:
        for changes in ({"state": "new"}, {"size": 1235}, {"size": True}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.validate({"assets": [self.asset(**changes)]})

    def test_rejects_missing_malformed_or_mismatched_digest(self) -> None:
        for digest in (None, "", "sha256:not-hex", f"sha256:{'b' * 64}"):
            with self.subTest(digest=digest), self.assertRaises(ValueError):
                self.validate({"assets": [self.asset(digest=digest)]})

    def test_rejects_malformed_release_payload(self) -> None:
        for payload in (None, [], {}, {"assets": None}, {"assets": ["asset"]}):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                self.validate(payload)


if __name__ == "__main__":
    unittest.main()
