#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unsafe release ZIP and false immutable/universal candidate regressions."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('clean_candidate', Path(__file__).with_name('build-mpv-coreaudio-clean-candidate.py'))
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CleanCandidateTests(unittest.TestCase):
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
            receipt = {'candidateMPVKitRevision': 'recipe', 'sourceInputs': {}, 'prebuiltAuxiliaryInputs': []}
            with patch.object(candidate, 'git', side_effect=['recipe', '']), patch.object(candidate, 'capture', return_value='arm64'):
                with self.assertRaisesRegex(ValueError, 'actual framework architecture mismatch'):
                    candidate.verify_build(root, receipt)

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


if __name__ == '__main__':
    unittest.main()
