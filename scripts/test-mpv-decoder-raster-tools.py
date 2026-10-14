#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise framework link preservation and extraction boundaries."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).with_name('prepare-mpv-decoder-raster-app-candidate.py'))
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class FrameworkExtractionTests(unittest.TestCase):
    def archive(self, root, link=None, entry='Libmpv.framework/Libmpv'):
        archive = root / 'framework.zip'
        with zipfile.ZipFile(archive, 'w') as file:
            file.writestr('Libmpv.framework/Versions/A/Libmpv', b'native binary')
            if link is not None:
                info = zipfile.ZipInfo(entry)
                info.create_system = 3
                info.external_attr = 0o120755 << 16
                file.writestr(info, link)
            else:
                file.writestr(entry, b'native binary')
        return archive

    @unittest.skipUnless(Path('/usr/bin/ditto').exists(), 'macOS framework extraction required')
    def test_preserves_framework_link_to_contained_binary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = self.archive(root, 'Versions/A/Libmpv')
            candidate.unpack_framework(archive, root / 'expanded')
            binary = root / 'expanded/Libmpv.framework/Libmpv'
            self.assertTrue(binary.is_symlink())
            self.assertEqual(binary.read_bytes(), b'native binary')

    def test_rejects_escaping_links_before_any_extraction(self):
        for link in ('/tmp/outside', '../../outside', 'Versions/../../outside', 'Versions\\outside'):
            with self.subTest(link=link), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = self.archive(root, link)
                with self.assertRaisesRegex(ValueError, 'unsafe framework archive link'):
                    candidate.unpack_framework(archive, root / 'expanded')
                self.assertFalse((root / 'expanded').exists())

    def test_rejects_escaping_archive_members_before_any_extraction(self):
        for entry in ('/tmp/outside', '../../outside', 'Libmpv.framework/../../outside', 'Libmpv.framework\\outside'):
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = self.archive(root, entry=entry)
                with self.assertRaisesRegex(ValueError, 'unsafe framework archive path'):
                    candidate.unpack_framework(archive, root / 'expanded')
                self.assertFalse((root / 'expanded').exists())


if __name__ == '__main__':
    unittest.main()
