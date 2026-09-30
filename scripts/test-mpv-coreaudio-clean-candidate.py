#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unsafe release ZIP and false immutable/universal candidate regressions."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import subprocess
import unittest
from unittest.mock import patch
import sys
import zipfile

spec = importlib.util.spec_from_file_location('clean_candidate', Path(__file__).with_name('build-mpv-coreaudio-clean-candidate.py'))
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CleanCandidateTests(unittest.TestCase):
    def write_shipping_headers(self, root):
        for arch in ('arm64', 'x86_64'):
            for identity, expected in candidate.SHIPPING_FLAGS.items():
                library, filename = identity.split('/')
                path = root / 'MPVKit/dist' / library / 'macos/scratch' / arch / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(''.join(f'#define {feature} {value}\n' for feature, value in expected.items()))

    def test_zip_paths_are_checked_before_any_file_is_extracted(self):
        for name in ('../outside', '/tmp/outside', 'a/../../outside', 'a\\outside'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / 'input.zip'
                with zipfile.ZipFile(archive, 'w') as file:
                    file.writestr('valid.h', 'valid first entry')
                    file.writestr(name, 'must never escape')
                output = root / 'output'
                output.mkdir()
                with self.assertRaisesRegex(ValueError, 'unsafe cached ZIP path'):
                    candidate.unpack_zip(archive, output)
                self.assertEqual(list(output.iterdir()), [])

    def test_zip_symlink_is_rejected_before_it_can_redirect_later_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'input.zip'
            with zipfile.ZipFile(archive, 'w') as file:
                entry = zipfile.ZipInfo('includes')
                entry.create_system = 3
                entry.external_attr = 0o120777 << 16
                file.writestr(entry, '../outside')
                file.writestr('includes/header.h', 'payload')
            with self.assertRaisesRegex(ValueError, 'ZIP symlink'):
                candidate.unpack_zip(archive, root / 'output')
            self.assertFalse((root / 'outside').exists())

    def test_valid_release_zip_payload_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'input.zip'
            with zipfile.ZipFile(archive, 'w') as file:
                file.writestr('include/header.h', b'header')
                file.writestr('lib/macos/thin/arm64/lib/libexample.a', b'archive')
            candidate.unpack_zip(archive, root / 'output')
            self.assertEqual((root / 'output/include/header.h').read_bytes(), b'header')
            self.assertEqual((root / 'output/lib/macos/thin/arm64/lib/libexample.a').read_bytes(), b'archive')

    def test_universal_plist_does_not_waive_missing_actual_binary_slice(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            release = root / 'MPVKit/dist/release'
            release.mkdir(parents=True)
            info = {'AvailableLibraries': [{'LibraryIdentifier': 'macos-arm64_x86_64',
                    'LibraryPath': 'Libmpv.framework', 'SupportedPlatform': 'macos',
                    'SupportedArchitectures': ['arm64', 'x86_64']}]}
            with zipfile.ZipFile(release / 'Libmpv.xcframework.zip', 'w') as file:
                file.writestr('Libmpv.xcframework/Info.plist', plistlib.dumps(info))
                file.writestr('Libmpv.xcframework/macos-arm64_x86_64/Libmpv.framework/Versions/A/Libmpv', b'single-slice')
            archive = release / 'Libmpv.xcframework.zip'
            receipt = {'candidateMPVKitRevision': 'recipe', 'sourceInputs': {}, 'prebuiltAuxiliaryInputs': [],
                       'artifacts': {'dist/release/Libmpv.xcframework.zip': {'sha256': candidate.sha(archive), 'sizeBytes': archive.stat().st_size}}}
            with patch.object(candidate, 'git', side_effect=['recipe', '']), patch.object(candidate, 'capture', return_value='arm64'):
                with self.assertRaisesRegex(ValueError, 'actual framework architecture mismatch'):
                    candidate.verify_build(root, receipt)

    def test_replaced_zip_and_matching_neighbor_checksum_cannot_replace_receipt_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'MPVKit/dist/release/Libmpv.xcframework.zip'
            archive.parent.mkdir(parents=True)
            archive.write_bytes(b'original archive')
            receipt = {'candidateMPVKitRevision': 'recipe', 'sourceInputs': {}, 'prebuiltAuxiliaryInputs': [],
                       'artifacts': {'dist/release/Libmpv.xcframework.zip': {'sha256': candidate.sha(archive), 'sizeBytes': archive.stat().st_size}}}
            archive.write_bytes(b'replaced archive')
            archive.with_name('Libmpv.xcframework.checksum.txt').write_text(candidate.sha(archive))
            with patch.object(candidate, 'git', side_effect=['recipe', '']), patch.object(candidate, 'capture') as inspect_binary:
                with self.assertRaisesRegex(ValueError, 'artifact differs from immutable build receipt'):
                    candidate.verify_build(root, receipt)
                inspect_binary.assert_not_called()

    def test_source_revision_tree_or_dirty_status_invalidates_candidate(self):
        receipt = {'candidateMPVKitRevision': 'recipe', 'sourceInputs': {
                    'libmpv-v0.41.0': {'candidateRevision': 'mpv', 'candidateTree': 'tree'}}}
        for revision, tree, status in [('different', 'tree', ''), ('mpv', 'different', ''), ('mpv', 'tree', ' M audio/out/ao_coreaudio.c')]:
            with self.subTest(revision=revision, tree=tree, status=status), patch.object(candidate, 'git', side_effect=['recipe', '', revision, tree, status]):
                with self.assertRaisesRegex(ValueError, 'candidate source changed during build'):
                    candidate.verify_build(Path('/isolated'), receipt)

    def test_copied_zip_must_match_recorded_original_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = root / 'original.zip'
            original.write_bytes(b'original')
            copied = root / 'MPVKit/dist/libexample-1.0/libexample.zip'
            copied.parent.mkdir(parents=True)
            copied.write_bytes(b'different')
            receipt = {'candidateMPVKitRevision': 'recipe', 'sourceInputs': {}, 'prebuiltAuxiliaryInputs': [
                        {'path': str(original), 'relativePath': 'dist/libexample-1.0/libexample.zip', 'sha256': candidate.sha(original)}]}
            with patch.object(candidate, 'git', side_effect=['recipe', '']):
                with self.assertRaisesRegex(ValueError, 'copied/original auxiliary ZIP mismatch'):
                    candidate.verify_build(root, receipt)

    def test_wrong_cached_git_revision_cannot_be_cloned(self):
        with patch.object(candidate, 'git', return_value='different'), patch.object(candidate, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'cached source revision mismatch'):
                candidate.clone_clean(Path('/source'), Path('/output'), 'expected')
            run.assert_not_called()

    def test_shipping_configuration_rejects_license_backend_and_decoder_loss_on_either_architecture(self):
        regressions = [('libmpv/config.h', 'HAVE_GPL'), ('libmpv/config.h', 'HAVE_COREAUDIO'),
                       ('FFmpeg/config.h', 'CONFIG_METAL'), ('FFmpeg/config.h', 'CONFIG_LIBSMBCLIENT'),
                       ('FFmpeg/config_components.h', 'CONFIG_ADPCM_N64_DECODER')]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write_shipping_headers(root)
            self.assertTrue(candidate.shipping_configuration(root, True)['passed'])
            for arch in ('arm64', 'x86_64'):
                for identity, feature in regressions:
                    library, filename = identity.split('/')
                    path = root / 'MPVKit/dist' / library / 'macos/scratch' / arch / filename
                    before = path.read_text()
                    path.write_text(before.replace(f'#define {feature} 1', f'#define {feature} 0'))
                    with self.subTest(arch=arch, feature=feature), self.assertRaisesRegex(ValueError, f'{arch}/{feature}'):
                        candidate.shipping_configuration(root, True)
                    path.write_text(before)

    def test_historical_identity_verification_exposes_non_equivalent_features(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write_shipping_headers(root)
            header = root / 'MPVKit/dist/FFmpeg/macos/scratch/x86_64/config.h'
            header.write_text(header.read_text().replace('#define CONFIG_GPL 1', '#define CONFIG_GPL 0'))
            result = candidate.shipping_configuration(root, False)
            self.assertFalse(result['passed'])
            self.assertEqual(result['mismatches'], [{'architecture': 'x86_64', 'header': 'FFmpeg/config.h',
                              'feature': 'CONFIG_GPL', 'expected': 1, 'actual': 0}])

    def test_missing_configuration_feature_fails_instead_of_becoming_zero_or_unavailable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write_shipping_headers(root)
            header = root / 'MPVKit/dist/libmpv/macos/scratch/arm64/config.h'
            header.write_text(header.read_text().replace('#define HAVE_GPL 1\n', ''))
            with self.assertRaisesRegex(ValueError, 'HAVE_GPL=None'):
                candidate.shipping_configuration(root, True)

    def test_missing_metal_compiler_stops_before_output_or_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / candidate.SMB_ZIP
            archive.parent.mkdir(parents=True)
            with zipfile.ZipFile(archive, 'w') as file:
                for arch in ('arm64', 'x86_64'):
                    file.writestr(f'lib/macos/thin/{arch}/lib/libsmbclient.a', 'archive')
            failure = subprocess.CompletedProcess([], 1, 'missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain')
            with patch.object(candidate.subprocess, 'run', return_value=failure), patch.object(candidate, 'clone_clean') as clone:
                with self.assertRaisesRegex(ValueError, 'requires a working Metal compiler.*CONFIG_METAL=1'):
                    candidate.build(root, root.parent / (root.name + '-output'))
                clone.assert_not_called()
                self.assertFalse((root.parent / (root.name + '-output')).exists())

    def test_verify_exit_status_rejects_legacy_receipt_without_shipping_product(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write_shipping_headers(root)
            header = root / 'MPVKit/dist/FFmpeg/macos/scratch/arm64/config.h'
            header.write_text(header.read_text().replace('#define CONFIG_GPL 1', '#define CONFIG_GPL 0'))
            (root / 'builder.py').write_text('historical builder')
            (root / 'receipt.json').write_text(json.dumps({'buildSucceeded': True, 'builderSHA256': candidate.sha(root / 'builder.py')}))
            def feature_gate(output, receipt, require_shipping=True):
                return {'shippingFeatureParity': candidate.shipping_configuration(output, require_shipping)}
            with patch.object(sys, 'argv', ['builder', '--verify', str(root)]), patch.object(candidate, 'verify_build', side_effect=feature_gate):
                self.assertEqual(candidate.main(), 1)
            self.assertFalse((root / 'shipping-verification.json').exists())
            with patch.object(sys, 'argv', ['builder', '--diagnose-historical', str(root)]), patch.object(candidate, 'verify_build', side_effect=feature_gate):
                self.assertEqual(candidate.main(), 0)
            self.assertFalse(json.loads((root / 'historical-parity-diagnostic.json').read_text())['shippingFeatureParity']['passed'])


if __name__ == '__main__':
    unittest.main()
