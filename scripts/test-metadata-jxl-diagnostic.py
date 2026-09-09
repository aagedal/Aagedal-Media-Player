#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Require complete, matching JXL diagnostic evidence from the intended fixture."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("diagnostic", Path(__file__).with_name("diagnose-metadata-jxl-fixture.py"))
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class DiagnosticTests(unittest.TestCase):
    def evidence(self):
        result = {name: True for name in diagnostic.CHECKS}
        result.update(fixtureSHA256="original", codestreamSHA256="stream")
        return {name: copy.deepcopy(result) for name in ("baseline", "candidate")}

    def test_complete_matching_evidence(self):
        self.assertTrue(diagnostic.validate_results(self.evidence(), "original", True))

    def test_missing_or_inconsistent_variant_rejected(self):
        for name in ("baseline", "candidate"):
            result = self.evidence()
            del result[name]
            self.assertFalse(diagnostic.validate_results(result, "original", True))
        result = self.evidence()
        result["candidate"]["codestreamSHA256"] = "different"
        self.assertFalse(diagnostic.validate_results(result, "original", True))

    def test_missing_false_or_non_boolean_checks_rejected(self):
        for check in diagnostic.CHECKS:
            for value in (None, False, 1, "true"):
                result = self.evidence()
                for variant in result.values():
                    if value is None:
                        del variant[check]
                    else:
                        variant[check] = value
                self.assertFalse(diagnostic.validate_results(result, "original", True))

    def test_wrong_fixture_or_changed_inputs_rejected(self):
        self.assertFalse(diagnostic.validate_results(self.evidence(), "other", True))
        self.assertFalse(diagnostic.validate_results(self.evidence(), "original", False))


if __name__ == "__main__":
    unittest.main()
