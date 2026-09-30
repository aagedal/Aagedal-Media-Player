#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression checks for reusable retained-source/input reconstruction audits."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load('audit', 'verify-mpv-coreaudio-reconstruction.py')
fixtures = load('fixtures', 'test-mpv-coreaudio-publication.py')


class ReconstructionAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        # Match the CLI's canonical paths, including macOS /var -> /private/var.
        self.root = Path(self.temporary.name).resolve()
        self.stage, self.workspace = self.root / 'stage', self.root / 'workspace'
        self.stage.mkdir()
        self.environment = {key: value for key, value in audit.os.environ.items() if not key.startswith('GIT_')}
        self.environment.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=audit.os.devnull, GIT_ATTR_NOSYSTEM='1')
        self.metadata = fixtures.PublicationTests().fixture(self.stage)
        self.digest = audit.publication.sha(self.stage / 'publication.json')
        audit.publication.reconstruct(self.stage, self.workspace, self.digest)

    def verify(self):
        return audit.verify(self.stage, self.workspace, self.digest)

    def git(self, directory, *command, **kwargs):
        return subprocess.check_output(['git', '-C', str(directory), *command], env=self.environment, **kwargs)

    def test_exact_restoration_passes_without_running_build(self):
        result = self.verify()
        self.assertTrue(result['passed'])
        self.assertEqual(result['auxiliaryInputCount'], 20)
        self.assertEqual(result['sourceFileCount'], 7)
        self.assertEqual(len(result['sourceSnapshots']), 3)
        self.assertTrue(all(entry['shallow'] for entry in result['sourceSnapshots']))
        self.assertFalse((self.workspace / 'MPVKit/dist/release').exists())
        self.assertFalse(result['byteIdenticalRebuildDemonstrated'])

    def test_source_edits_hidden_from_git_status_still_fail(self):
        directory = self.workspace / 'MPVKit/dist/libmpv-v0.41.0'
        self.git(directory, 'update-index', '--assume-unchanged', 'source.txt')
        (directory / 'source.txt').write_bytes(b'edited')
        self.assertEqual(self.git(directory, 'status', '--porcelain'), b'')
        with self.assertRaisesRegex(ValueError, 'working-file identity mismatch'):
            self.verify()

    def test_executable_mode_is_checked_even_if_git_ignores_filemode(self):
        directory = self.workspace / 'MPVKit/dist/FFmpeg-n8.1.2'
        self.git(directory, 'config', 'core.filemode', 'false')
        (directory / 'source.txt').chmod(0o755)
        self.assertEqual(self.git(directory, 'status', '--porcelain'), b'')
        with self.assertRaisesRegex(ValueError, 'working-file identity mismatch'):
            self.verify()

    def test_modified_cached_input_is_rejected(self):
        (self.workspace / 'MPVKit' / self.metadata['auxiliaryBuildInputs'][0]['relativePath']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'auxiliary input identity mismatch'):
            self.verify()

    def test_replaced_commit_with_same_source_tree_is_rejected(self):
        snapshot = self.metadata['sourceSnapshots'][1]
        directory = self.workspace / 'MPVKit/dist/libmpv-v0.41.0'
        original = (self.stage / snapshot['commitPath']).read_bytes()
        revision = self.git(directory, 'hash-object', '-w', '-t', 'commit', '--stdin',
                            input=original + b'changed commit message\n').decode().strip()
        self.git(directory, 'update-ref', 'HEAD', revision)
        with self.assertRaisesRegex(ValueError, 'Git identity mismatch'):
            self.verify()

    def test_receipt_cannot_claim_compilation_or_changed_environment(self):
        path = self.workspace / 'reconstruction.json'
        original = json.loads(path.read_text())
        for mutation in ('built', 'environment', 'inputs', 'driver', 'command', 'working-directory', 'cache'):
            with self.subTest(mutation=mutation):
                receipt = json.loads(json.dumps(original))
                if mutation == 'built':
                    receipt['buildExecuted'] = True
                elif mutation == 'environment':
                    receipt['environmentDeclaration']['byteIdenticalRebuildDemonstrated'] = True
                elif mutation == 'inputs':
                    receipt['auxiliaryBuildInputs'][0]['sha256'] = '0' * 64
                elif mutation == 'driver':
                    receipt['reconstructionDriverSHA256'] = '0' * 64
                elif mutation == 'command':
                    receipt['candidateBuildCommand'][0] = 'unrelated-command'
                elif mutation == 'working-directory':
                    receipt['buildWorkingDirectory'] = '/unrelated-workspace'
                else:
                    receipt['isolatedEnvironmentPaths']['TMPDIR'] = '/unrelated-cache'
                path.write_text(json.dumps(receipt))
                with self.assertRaisesRegex(ValueError, 'receipt binding mismatch'):
                    self.verify()

    def test_digest_and_stage_payload_are_both_checked(self):
        with self.assertRaisesRegex(ValueError, 'externally retained'):
            audit.verify(self.stage, self.workspace, 'invalid')
        with self.assertRaisesRegex(ValueError, 'externally retained SHA-256'):
            audit.verify(self.stage, self.workspace, '0' * 64)
        (self.stage / self.metadata['binaryTargets'][0]['assetPath']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'publication payload identity mismatch'):
            self.verify()

    def test_inherited_git_directory_does_not_redirect_audit(self):
        with patch.dict(audit.os.environ, {'GIT_DIR': str(self.root / 'unrelated-git')}):
            self.assertTrue(self.verify()['passed'])

    def test_symlink_in_place_of_identical_source_file_is_rejected(self):
        path = self.workspace / 'MPVKit/LICENSE'
        other = self.root / 'same-content'
        other.write_bytes(path.read_bytes())
        path.unlink()
        path.symlink_to(other)
        with self.assertRaisesRegex(ValueError, 'working-file identity mismatch'):
            self.verify()

    def test_command_line_reports_success_and_wrong_digest_failure(self):
        command = [sys.executable, str(Path(audit.__file__)), str(self.stage), str(self.workspace),
                   '--expected-publication-sha256', self.digest]
        result = subprocess.run(command, capture_output=True, text=True, env=self.environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['passed'])
        command[-1] = '0' * 64
        result = subprocess.run(command, capture_output=True, text=True, env=self.environment)
        self.assertEqual(result.returncode, 1)
        self.assertIn('externally retained SHA-256', result.stderr)


if __name__ == '__main__':
    unittest.main()
