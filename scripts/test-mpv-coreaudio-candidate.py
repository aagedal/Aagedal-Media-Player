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
        }, source, Path('/isolated/source'), Path('/isolated/object.o'), Path('/current-sdk'), 'arm64')
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
                }, Path('/cache'), Path('/isolated/source'), Path('/isolated/object.o'), Path('/current-sdk'), 'arm64')

    def test_architecture_flags_must_agree_on_requested_slice(self):
        for flags in ('-arch x86_64', '-target x86_64-apple-macos12.0', '',
                      '-arch arm64 -arch arm64', '-arch arm64 -target x86_64-apple-macos12.0', '-arch'):
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                candidate.compile_command({
                    'directory': '/cache', 'file': 'audio/out/ao_coreaudio.c',
                    'command': '/usr/bin/clang -c audio/out/ao_coreaudio.c -o original.o ' + flags,
                }, Path('/cache'), Path('/isolated/source'), Path('/isolated/object.o'), Path('/current-sdk'), 'arm64')
        for arch in candidate.ARCHES:
            for flag in (f'-arch {arch}', f'-target {arch}-apple-macos12.0',
                         f'-arch {arch} -target {arch}-apple-macos12.0'):
                command = candidate.compile_command({
                    'directory': '/cache', 'file': 'audio/out/ao_coreaudio.c',
                    'command': '/usr/bin/clang ' + flag + ' -c audio/out/ao_coreaudio.c -o original.o',
                }, Path('/cache'), Path('/isolated/source'), Path('/isolated/object.o'), Path('/current-sdk'), arch)
                self.assertIn(arch if '-arch' in command else arch + '-apple-macos12.0', command)

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

    def test_member_paths_rejected_before_archive_extraction(self):
        for name in ('../outside.o', '/tmp/outside.o', 'objects/a.o', '..', '.',
                     'a\\outside.o', '__.SYMDEF/../../outside.o', 'control\tname.o'):
            with self.subTest(name=name), patch.object(candidate, 'capture', return_value=(name + '\n').encode()):
                with self.assertRaisesRegex(ValueError, 'unsafe archive member'):
                    candidate.archive_members(Path('input.a'))
        with patch.object(candidate, 'capture', return_value=b'__.SYMDEF_64 SORTED\n__.SYMDEF_extra.o\n'):
            self.assertEqual(candidate.archive_members(Path('input.a')), ['__.SYMDEF_extra.o'])

    def test_all_framework_links_must_stay_inside_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            framework = root / 'Libmpv.framework'
            (framework / 'Versions/A/Headers').mkdir(parents=True)
            (framework / 'Versions/Current').symlink_to('A')
            (framework / 'Headers').symlink_to('Versions/Current/Headers')
            candidate.validate_framework_links(framework)
            (framework / 'Headers').unlink()
            (framework / 'Headers').symlink_to(root / 'original-headers')
            with self.assertRaisesRegex(ValueError, 'symlink escapes isolated candidate'):
                candidate.validate_framework_links(framework)

    def test_source_links_cannot_copy_unfingerprinted_external_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            (root / 'external').mkdir()
            (source / 'includes').symlink_to(root / 'external')
            with self.assertRaisesRegex(ValueError, 'cached source symlink escapes'):
                candidate.validate_tree_links(source, 'cached source')

    def test_input_snapshot_checks_database_headers_objects_and_symlink_identity(self):
        import json
        with tempfile.TemporaryDirectory() as directory, patch.object(candidate, 'capture', return_value=b'revision\n'):
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            (source / 'source.c').write_text('source')
            framework = root / 'framework'
            (framework / 'Versions/A').mkdir(parents=True)
            (framework / 'Versions/A/Libmpv').write_bytes(b'archive')
            (framework / 'Libmpv').symlink_to('Versions/A/Libmpv')
            for arch in candidate.ARCHES:
                scratch = root / 'dist/libmpv/macos/scratch' / arch
                scratch.mkdir(parents=True)
                entries = []
                for name in candidate.FILES:
                    (scratch / (name + '.o')).write_bytes(b'object')
                    entries.append({'file': name, 'output': name + '.o'})
                (scratch / 'compile_commands.json').write_text(json.dumps(entries))
                (scratch / 'config.h').write_text('config')
            baseline = candidate.snapshot_inputs(root, source, framework)
            candidate.verify_inputs_unchanged(baseline, candidate.snapshot_inputs(root, source, framework))
            paths = [source / 'source.c', framework / 'Versions/A/Libmpv',
                     root / 'dist/libmpv/macos/scratch/arm64/config.h',
                     root / 'dist/libmpv/macos/scratch/arm64/ao_coreaudio.c.o']
            for path in paths:
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'inputs changed during rebuild'):
                    candidate.verify_inputs_unchanged(baseline, candidate.snapshot_inputs(root, source, framework))
                path.write_bytes(original)
            database = root / 'dist/libmpv/macos/scratch/arm64/compile_commands.json'
            original = database.read_text()
            database.write_text(original + '\n')
            with self.assertRaisesRegex(ValueError, 'architectures'):
                candidate.verify_inputs_unchanged(baseline, candidate.snapshot_inputs(root, source, framework))
            database.write_text(original)
            link = framework / 'Libmpv'
            link.unlink()
            link.symlink_to('./Versions/A/Libmpv')
            with self.assertRaisesRegex(ValueError, 'frameworkTreeSHA256'):
                candidate.verify_inputs_unchanged(baseline, candidate.snapshot_inputs(root, source, framework))

    def test_input_snapshot_rejects_added_removed_or_changed_categories(self):
        for before, after in (({'source': 'a'}, {'source': 'b'}),
                              ({'source': 'a'}, {'source': 'a', 'patch': 'b'}),
                              ({'source': 'a', 'patch': 'b'}, {'source': 'a'})):
            with self.subTest(before=before, after=after), self.assertRaisesRegex(ValueError, 'inputs changed'):
                candidate.verify_inputs_unchanged(before, after)


if __name__ == '__main__':
    unittest.main()
