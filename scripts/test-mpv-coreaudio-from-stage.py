#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check input closure and offline feature gates for the portable builder."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('portable', Path(__file__).with_name('build-mpv-coreaudio-from-stage.py'))
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)


class PortableBuildTests(unittest.TestCase):
    def test_decoder_provider_retains_patch_and_source_and_rejects_dirty_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'MPVKit/dist/libmpv-v0.41.0'
            source.mkdir(parents=True)
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            (source / 'provider.c').write_text('before\n')
            portable.builder.commit(source, 'Fixture baseline')
            baseline = portable.builder.git(source, 'rev-parse', 'HEAD')
            expected = {'revision': baseline, 'tree': portable.builder.git(source, 'rev-parse', 'HEAD^{tree}')}
            (source / 'provider.c').write_text('after\n')
            patch = root / 'docs/dependency-patches/mpv-0.41.0-decoder-raster-candidate.patch'
            patch.parent.mkdir(parents=True)
            patch.write_text(subprocess.check_output(['git', '-C', str(source), 'diff'], text=True))
            subprocess.run(['git', '-C', str(source), 'checkout', '--', 'provider.c'], check=True)
            output = root / 'evidence'
            output.mkdir()
            with mock.patch.object(portable, '__file__', str(root / 'scripts/driver.py')):
                with self.assertRaisesRegex(ValueError, 'verified source snapshot'):
                    portable.apply_decoder_raster_candidate(root / 'MPVKit', output, {**expected, 'tree': 'wrong'})
                receipt = portable.apply_decoder_raster_candidate(root / 'MPVKit', output, expected)
                self.assertEqual(receipt['retainedRevision'], baseline)
                self.assertNotEqual(receipt['candidateRevision'], baseline)
                self.assertEqual((source / 'provider.c').read_text(), 'after\n')
                self.assertEqual(receipt['patch'], portable.publication.identity(output / 'decoder-raster-source' / patch.name))
                self.assertEqual(receipt['sourceArchive'], portable.publication.identity(output / 'decoder-raster-source/libmpv-decoder-raster.tar.gz'))
                expected = {'revision': receipt['candidateRevision'], 'tree': receipt['candidateTree']}
                (source / 'provider.c').write_text('dirty\n')
                with self.assertRaisesRegex(ValueError, 'must be clean'):
                    portable.apply_decoder_raster_candidate(root / 'MPVKit', output, expected)

    def test_scope_provider_retains_sources_and_rejects_reapplication(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = root / 'MPVKit'
            source = checkout / 'dist/libmpv-v0.41.0'
            (source / 'player').mkdir(parents=True)
            (source / 'player/command.c').write_text('    { "aagedal-decoder-raster", cmd_aagedal_decoder_raster },\n')
            (source / 'player/screenshot.c').write_text('/* baseline */\n')
            (source / 'player/screenshot.h').write_text('/* baseline */\n')
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            portable.builder.commit(source, 'Scope fixture baseline')
            output = root / 'evidence'
            output.mkdir()
            receipt = portable.apply_scopes_candidate(checkout, output)
            self.assertTrue((output / 'scopes-source/libmpv-scopes.tar.gz').is_file())
            self.assertIn('scope_math.h', receipt['providerInputs'])
            self.assertIn('.spawn_thread = true', (source / 'player/command.c').read_text())
            before = (source / 'player/screenshot.c').read_bytes()
            with self.assertRaisesRegex(ValueError, 'already patched'):
                portable.apply_scopes_candidate(checkout, output)
            self.assertEqual(before, (source / 'player/screenshot.c').read_bytes())

    def test_header_symlink_binds_external_content_and_detects_same_size_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            headers = root / 'headers'
            headers.mkdir()
            external = root / 'cellar'
            external.mkdir()
            header = external / 'test.h'
            header.write_text('before')
            (headers / 'test').symlink_to(external, target_is_directory=True)
            before = portable.tree_identity(headers)
            header.write_text('after!')
            self.assertNotEqual(before['manifestSHA256'], portable.tree_identity(headers)['manifestSHA256'])

    def test_header_directory_cycles_are_finite_and_repeatable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'test.h').write_text('test')
            (root / 'loop').symlink_to(root, target_is_directory=True)
            before = portable.tree_identity(root)
            self.assertEqual(before, portable.tree_identity(root))
            self.assertLess(before['entryCount'], 10)

    def test_missing_and_dangling_declared_inputs_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(ValueError):
                portable.tree_identity(root / 'missing')
            (root / 'dangling').symlink_to(root / 'missing')
            with self.assertRaises(ValueError):
                portable.tree_identity(root)

    def test_optional_feature_changes_fail_even_when_shipping_flags_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'provenance').mkdir()
            identity = {'architectures': {'arm64': {'libmpv/config.h': {'booleanConfigurationSHA256': 'original'}}}}
            (root / 'provenance/build-receipt.json').write_text(json.dumps({'verification': {'shippingFeatureParity': identity}}))
            verification = {'shippingFeatureParity': identity}
            self.assertEqual(portable.configuration_differences(root, verification), [])
            changed = {'shippingFeatureParity': {'architectures': {'arm64': {'libmpv/config.h': {'booleanConfigurationSHA256': 'changed'}}}}}
            self.assertEqual(portable.configuration_differences(root, changed), ['arm64/libmpv/config.h'])

    def test_arm64_configuration_ignores_unbuilt_intel_slice(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'provenance').mkdir()
            arm = {'libmpv/config.h': {'booleanConfigurationSHA256': 'same'}}
            baseline = {'architectures': {'arm64': arm, 'x86_64': arm}}
            (root / 'provenance/build-receipt.json').write_text(json.dumps({'verification': {'shippingFeatureParity': baseline}}))
            actual = {'shippingFeatureParity': {'architectures': {'arm64': arm}}}
            self.assertEqual(portable.configuration_differences(root, actual), [])

    def test_verifier_rejects_unknown_or_empty_architecture_declaration(self):
        for architectures in ([], ['x86_64'], ['arm64', 'arm64'], ['arm64', 'unknown']):
            with self.subTest(architectures=architectures):
                with self.assertRaisesRegex(ValueError, 'architecture declaration'):
                    portable.builder.verify_build(Path('/unused'), {'architectures': architectures})

    @unittest.skipUnless(Path('/usr/bin/sandbox-exec').exists(), 'macOS sandbox-exec required')
    def test_offline_policy_denies_socket_creation(self):
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)',
                                 sys.executable, '-c', 'import socket; socket.socket().connect(("127.0.0.1", 9))'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Operation not permitted', result.stderr)


if __name__ == '__main__':
    unittest.main()
