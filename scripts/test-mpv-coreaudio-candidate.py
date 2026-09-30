#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Safety checks for the opt-in incremental dependency candidate builder."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).with_name('rebuild-mpv-coreaudio-candidate.py'))
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CandidateRebuildTests(unittest.TestCase):
    def test_compilation_cannot_write_cached_objects_or_dependency_files(self):
        source = Path('/cache/dist/libmpv-v0.41.0')
        command = candidate.compile_command({
            'directory': '/cache/dist/libmpv/macos/scratch/arm64',
            'file': '../../../../libmpv-v0.41.0/audio/out/ao_coreaudio.c',
            'command': '/usr/bin/clang -I. -I../../../../libmpv-v0.41.0 -I../../../../libmpv-v0.41.0/include -arch arm64 -MD -MQ libmpv.a.p/audio_out_ao_coreaudio.c.o -MF libmpv.a.p/audio_out_ao_coreaudio.c.o.d -o libmpv.a.p/audio_out_ao_coreaudio.c.o -isysroot /old-sdk -c ../../../../libmpv-v0.41.0/audio/out/ao_coreaudio.c',
        }, source, Path('/isolated/source'), Path('/isolated/object.o'), Path('/current-sdk'))
        self.assertEqual(command[command.index('-o') + 1], '/isolated/object.o')
        self.assertEqual(command[command.index('-c') + 1], '/isolated/source/audio/out/ao_coreaudio.c')
        self.assertIn('-I/isolated/source', command)
        self.assertIn('-I/isolated/source/include', command)
        self.assertIn('-I/cache/dist/libmpv/macos/scratch/arm64', command)
        self.assertEqual(command[command.index('-isysroot') + 1], '/current-sdk')
        for flag in ('-MD', '-MMD', '-MQ', '-MF', '-MT'):
            self.assertNotIn(flag, command)
        self.assertEqual(command.count('-o'), 1)

    def test_unrecognized_write_flags_and_response_files_are_rejected(self):
        for flags in ['-MJ /cache/compile.json', '-serialize-diagnostics /cache/compile.dia',
                      '-save-temps', '-ftime-trace', '@/cache/args.rsp']:
            with self.subTest(flags=flags), self.assertRaisesRegex(ValueError, 'unsupported cached compile argument'):
                candidate.compile_command({
                    'directory': '/cache', 'file': 'audio/out/ao_coreaudio.c',
                    'command': '/usr/bin/clang ' + flags + ' -c audio/out/ao_coreaudio.c -o original.o',
                }, Path('/cache'), Path('/isolated/source'), Path('/isolated/object.o'), Path('/current-sdk'))

    def test_existing_output_rejected_before_running_external_tools(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(candidate, 'capture') as capture:
            with self.assertRaisesRegex(ValueError, 'output already exists'):
                candidate.validate_inputs(Path('/cache'), Path('/framework'), Path(directory))
            capture.assert_not_called()

    def test_output_inside_cache_rejected_before_running_external_tools(self):
        with patch.object(candidate, 'capture') as capture:
            with self.assertRaisesRegex(ValueError, 'outside both input directories'):
                candidate.validate_inputs(Path('/cache'), Path('/framework'), Path('/cache/new-candidate'))
            capture.assert_not_called()

    def test_versioned_framework_preserves_relative_binary_link_and_rejects_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            framework = root / 'Libmpv.framework'
            binary = framework / 'Versions/A/Libmpv'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'original')
            (framework / 'Libmpv').symlink_to('Versions/A/Libmpv')
            self.assertEqual(candidate.framework_binary_destination(framework), binary.resolve())
            self.assertTrue((framework / 'Libmpv').is_symlink())
            (framework / 'Libmpv').unlink()
            (framework / 'Libmpv').symlink_to(root / 'outside')
            with self.assertRaisesRegex(ValueError, 'escapes isolated candidate'):
                candidate.framework_binary_destination(framework)

    def test_duplicate_members_rejected_but_symbol_index_is_not_object(self):
        with patch.object(candidate, 'capture', return_value=b'__.SYMDEF SORTED\na.o\nb.o\n'):
            self.assertEqual(candidate.archive_members(Path('input.a')), ['a.o', 'b.o'])
        with patch.object(candidate, 'capture', return_value=b'a.o\na.o\n'):
            with self.assertRaisesRegex(ValueError, 'duplicate archive members'):
                candidate.archive_members(Path('input.a'))


if __name__ == '__main__':
    unittest.main()
