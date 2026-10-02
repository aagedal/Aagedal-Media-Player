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

spec = importlib.util.spec_from_file_location('portable', Path(__file__).with_name('build-mpv-coreaudio-from-stage.py'))
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)


class PortableBuildTests(unittest.TestCase):
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

    @unittest.skipUnless(Path('/usr/bin/sandbox-exec').exists(), 'macOS sandbox-exec required')
    def test_offline_policy_denies_socket_creation(self):
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)',
                                 sys.executable, '-c', 'import socket; socket.socket().connect(("127.0.0.1", 9))'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Operation not permitted', result.stderr)


if __name__ == '__main__':
    unittest.main()
