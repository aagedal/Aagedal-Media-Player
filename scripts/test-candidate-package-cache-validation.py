#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


script = Path(__file__).with_name("validate-candidate-package-cache.py")
spec = importlib.util.spec_from_file_location("candidate_package_cache", script)
assert spec and spec.loader
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class CandidatePackageCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / "cache"
        self.checkout = self.cache / "checkouts" / "ExamplePackage"
        self.checkout.mkdir(parents=True)
        subprocess.run(["git", "init", "-q", str(self.checkout)], check=True)
        for key, value in (("user.name", "Cache Test"), ("user.email", "cache@example.invalid")):
            subprocess.run(["git", "-C", str(self.checkout), "config", key, value], check=True)
        (self.checkout / "Package.swift").write_text("// pinned\n")
        subprocess.run(["git", "-C", str(self.checkout), "add", "Package.swift"], check=True)
        subprocess.run(["git", "-C", str(self.checkout), "commit", "-qm", "pin"], check=True)
        self.revision = subprocess.check_output(
            ["git", "-C", str(self.checkout), "rev-parse", "HEAD"], text=True,
        ).strip()
        self.resolved = self.root / "Package.resolved"
        self.write_resolved(self.revision)

    def write_resolved(self, revision):
        self.resolved.write_text(json.dumps({"pins": [{
            "location": "https://example.invalid/ExamplePackage",
            "state": {"revision": revision},
        }]}))

    def test_accepts_clean_exact_checkout(self):
        self.assertEqual(
            validator.validate(self.resolved, self.cache),
            [("ExamplePackage", self.revision)],
        )

    def test_rejects_dirty_checkout(self):
        (self.checkout / "Package.swift").write_text("// changed\n")
        with self.assertRaisesRegex(ValueError, "local changes"):
            validator.validate(self.resolved, self.cache)

    def test_rejects_wrong_revision(self):
        self.write_resolved("0" * 40)
        with self.assertRaisesRegex(ValueError, "expected"):
            validator.validate(self.resolved, self.cache)

    def test_rejects_missing_checkout(self):
        self.write_resolved(self.revision)
        self.resolved.write_text(json.dumps({"pins": [{
            "location": "https://example.invalid/MissingPackage",
            "state": {"revision": self.revision},
        }]}))
        with self.assertRaises(FileNotFoundError):
            validator.validate(self.resolved, self.cache)


if __name__ == "__main__":
    unittest.main()
