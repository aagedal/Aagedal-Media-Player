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
        result.update(fixtureSHA256="original", codestreamSHA256=diagnostic.PINNED_CODESTREAM_SHA256,
                      codestreamBytes=diagnostic.PINNED_CODESTREAM_BYTES)
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

    def test_codestream_identity_and_size_are_required_even_when_variants_match(self):
        for key, bad_values in {
            "codestreamSHA256": (None, "different", "0" * 64),
            "codestreamBytes": (None, 1, True, "584049", 584049.0),
        }.items():
            for bad in bad_values:
                result = self.evidence()
                for variant in result.values():
                    if bad is None:
                        del variant[key]
                    else:
                        variant[key] = bad
                with self.subTest(field=key, value=bad):
                    self.assertFalse(diagnostic.validate_results(result, "original", True))

    def test_source_provenance_is_required_when_supplied(self):
        value = {
            "schemaVersion": 1, "mode": "exactCheckout", "baselineRevision": diagnostic.REVISION,
            "baselineCheckout": "/baseline", "baselineArchiveSHA256": "a" * 64,
            "candidateExpectedRevision": "b" * 40, "candidateResolvedRevision": "b" * 40,
            "candidateCheckout": "/candidate", "candidateArchiveSHA256": "c" * 64,
            "patchSHA256": None,
        }
        self.assertTrue(diagnostic.validate_results(self.evidence(), "original", True, value))
        for mutation in (lambda v: v.clear(), lambda v: v.update(candidateResolvedRevision="d" * 40),
                         lambda v: v.update(patchSHA256="e" * 64)):
            bad = copy.deepcopy(value)
            mutation(bad)
            self.assertFalse(diagnostic.validate_results(self.evidence(), "original", True, bad))

    def test_fixture_signature_distinguishes_container_and_bare_codestream(self):
        self.assertEqual(diagnostic.fixture_kind(diagnostic.CONTAINER_SIGNATURE + b"ftyp"), "container")
        self.assertEqual(diagnostic.fixture_kind(bytes.fromhex("ff0a") + b"stream"), "bareCodestream")
        self.assertEqual(diagnostic.fixture_kind(b"not a JPEG XL file"), "unknown")
        diagnostic.validate_fixture_hash(diagnostic.PINNED_FIXTURE_SHA256)
        with self.assertRaisesRegex(ValueError, "JXL fixture SHA-256 mismatch"):
            diagnostic.validate_fixture_hash("0" * 64)

    def test_contract_reports_both_disagreements(self):
        source = '''func testReadJXLBareCodestream() throws {
            XCTAssertThrowsError(try metadata.writeToData()) { error in
                guard case .writeNotSupported = metaError else { return }
            }
        }
        func testReadJXLContainer() throws {}'''
        expectation = diagnostic.upstream_write_expectation(source)
        self.assertEqual(expectation, "writeNotSupported")
        report = diagnostic.contract_report("container", expectation, self.evidence())
        self.assertTrue(report["fixtureNameDisagreesWithBytes"])
        self.assertTrue(report["assertionDisagreesWithObservedWrites"])
        self.assertTrue(report["requiresUpstreamReview"])

        reconciled = diagnostic.contract_report("bareCodestream", "writeSucceeds", self.evidence())
        self.assertFalse(reconciled["requiresUpstreamReview"])

    def test_write_expectation_is_scoped_to_named_upstream_case(self):
        source = '''func testReadJXLBareCodestream() throws {
            let written = try metadata.writeToData()
        }
        func testReadJXLContainer() throws {
            XCTAssertThrowsError(try metadata.writeToData())
        }'''
        self.assertEqual(diagnostic.upstream_write_expectation(source), "writeSucceeds")
        self.assertEqual(diagnostic.upstream_write_expectation("func other() {}"), "unrecognized")


if __name__ == "__main__":
    unittest.main()
