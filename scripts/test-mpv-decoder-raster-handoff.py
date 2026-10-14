#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check pinned restoration, extraction boundaries and fresh project isolation."""
import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('handoff', Path(__file__).with_name('restore-mpv-decoder-raster-candidate.py'))
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


class HandoffTests(unittest.TestCase):
    def make_bundle(self, root, unsafe=None, corrupt=False):
        source = root / 'source'
        source.mkdir()
        (source / 'MPVKit').mkdir()
        (source / 'MPVKit/binary').write_bytes(b'validated arm64 binary')
        (source / 'MPVKit/current').symlink_to('binary')
        metadata = {'architectures': ['arm64'], 'files': handoff.inventory(source)}
        (source / 'bundle.json').write_text(json.dumps(metadata))
        if corrupt:
            (source / 'MPVKit/binary').write_bytes(b'changed binary')
        archive = root / 'bundle.tar.gz'
        with tarfile.open(archive, 'w:gz') as file:
            file.add(source, arcname='.')
            if unsafe:
                member = tarfile.TarInfo('MPVKit/unsafe')
                member.type = tarfile.SYMTYPE
                member.linkname = unsafe
                file.addfile(member)
        return archive, {'sizeBytes': archive.stat().st_size, 'sha256': handoff.sha(archive)}

    def test_restores_at_new_path_without_original_build_and_preserves_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, identity = self.make_bundle(root)
            handoff.restore(archive, root / 'different-location', identity)
            binary = root / 'different-location/MPVKit/current'
            self.assertTrue(binary.is_symlink())
            self.assertEqual(binary.read_bytes(), b'validated arm64 binary')

    def test_rejects_wrong_archive_identity_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, identity = self.make_bundle(root)
            with self.assertRaisesRegex(ValueError, 'repository-pinned'):
                handoff.restore(archive, root / 'output', {**identity, 'sha256': 'wrong'})
            self.assertFalse((root / 'output').exists())

    def test_rejects_escaping_links_before_creating_output(self):
        for target in ('/tmp/outside', '../../outside', 'dir\\outside'):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive, identity = self.make_bundle(root, unsafe=target)
                with self.assertRaisesRegex(ValueError, 'unsafe bundle symlink'):
                    handoff.restore(archive, root / 'output', identity)
                self.assertFalse((root / 'output').exists())

    def test_changed_payload_fails_inventory_and_cleans_partial_restore(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, identity = self.make_bundle(root, corrupt=True)
            with self.assertRaisesRegex(ValueError, 'inventory'):
                handoff.restore(archive, root / 'output', identity)
            self.assertFalse((root / 'output').exists())

    def test_existing_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, identity = self.make_bundle(root)
            output = root / 'output'
            output.mkdir()
            (output / 'work').write_text('keep')
            with self.assertRaisesRegex(ValueError, 'must be new'):
                handoff.restore(archive, output, identity)
            self.assertEqual((output / 'work').read_text(), 'keep')

    def test_prepared_app_keeps_source_pins_and_only_prunes_local_dependency(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, package = root / 'repository', root / 'package'
            package.mkdir()
            (package / 'Package.swift').write_text('// local candidate')
            for name in ('Aagedal Media Player', 'Aagedal Media Player Tests'):
                (repo / name).mkdir(parents=True)
            project = repo / 'Aagedal Media Player.xcodeproj'
            project.mkdir()
            (project / 'project.pbxproj').write_text('isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/aagedal/MPVKit"; requirement = { revision = fixed; };')
            resolved = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            resolved.parent.mkdir(parents=True)
            pins = {'version': 3, 'pins': [{'identity': 'mpvkit'}, {'identity': 'sparkle'}]}
            resolved.write_text(json.dumps(pins))
            handoff.prepare_app(repo, package, root / 'app')
            self.assertEqual(json.loads(resolved.read_text()), pins)
            copied = root / 'app' / resolved.relative_to(repo)
            self.assertEqual(json.loads(copied.read_text())['pins'], [{'identity': 'sparkle'}])
            self.assertIn('XCLocalSwiftPackageReference', (root / 'app' / (project / 'project.pbxproj').relative_to(repo)).read_text())


if __name__ == '__main__':
    unittest.main()
