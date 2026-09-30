#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Publication identity, target completeness and immutable staging regressions."""
import importlib.util
import json
import io
from pathlib import Path
import tempfile
import subprocess
from unittest.mock import patch
import tarfile
import unittest

spec = importlib.util.spec_from_file_location('publication', Path(__file__).with_name('prepare-mpv-coreaudio-publication.py'))
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)
BASE = 'https://github.com/aagedal/MPVKit/releases/download/test-immutable-tag'


class PublicationTests(unittest.TestCase):
    def fixture(self, root):
        receipt = {'buildSucceeded': True, 'shippingProduct': 'MPVKit-GPL', 'builderSHA256': '',
                   'candidateMPVKitRevision': 'recipe', 'artifacts': {}, 'prebuiltAuxiliaryInputs': [],
                   'verification': {'shippingFeatureParity': {'passed': True}},
                   'sourceInputs': {name: {'candidateRevision': name, 'candidateTree': name + '-tree'}
                                    for name in ('libmpv-v0.41.0', 'FFmpeg-n8.1.2')}}
        def write(name, content):
            file = root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(content)
            return file
        receipt['builderSHA256'] = publication.sha(write('provenance/builder.py', b'builder'))
        receipt['patchSHA256'] = publication.sha(write('provenance/iina-18384-audio-channel.patch', b'patch'))
        preparer = write('provenance/preparer.py', b'preparer')
        targets = []
        for name in publication.LIBRARIES:
            path = 'assets/' + name + '-GPL.xcframework.zip'
            original = 'dist/release/' + name + '.xcframework.zip'
            entry = publication.identity(write(path, name.encode()))
            receipt['artifacts'][original] = entry
            targets.append({'name': name + '-GPL', 'url': BASE + '/' + Path(path).name,
                            'checksum': entry['sha256'], 'assetPath': path, 'originalBuildPath': original,
                            'remoteAuthenticated': False})
        targets.extend({'name': name, 'url': 'https://github.com/upstream/repo/releases/download/1/' + name + '.zip',
                        'checksum': 'a' * 64, 'remoteAuthenticated': False} for name in publication.AUXILIARIES)
        write('provenance/retained-package.swift', publication.package_manifest(targets).encode())
        write('package/Package.swift', publication.package_manifest(targets).encode())
        inputs = []
        recipe_names = ['example' + str(index) for index in range(19)] + ['libluajit']
        for index in range(20):
            name = recipe_names[index]
            path = f'inputs/{name}-1/{name}.zip'
            entry = {'relativePath': 'dist/' + path.removeprefix('inputs/'), 'publicationPath': path,
                     'recipeURL': f'https://github.com/upstream/repo/releases/download/1/{name}-all.zip',
                     'remoteAuthenticated': False, 'buildOnly': name == 'libluajit',
                     **publication.identity(write(path, b'input'))}
            inputs.append(entry)
            receipt['prebuiltAuxiliaryInputs'].append(entry)
        recipe = 'var version: String {\n' + '\n'.join('case .' + name + ':\n return "1"' for name in recipe_names)
        recipe += '\n}\nvar url: String {\n' + '\n'.join('case .' + name + ':\n return "https://github.com/upstream/repo/releases/download/\\(self.version)/' + name + '-all.zip"' for name in recipe_names) + '\n}\nvar next: String'
        snapshots = []
        for name in ['MPVKit-recipe', 'libmpv-v0.41.0', 'FFmpeg-n8.1.2']:
            path = 'sources/' + name + '.tar.gz'
            content = {'source.txt': b'source'}
            if name == 'MPVKit-recipe':
                content = {'Package.swift': publication.package_manifest(targets).encode(),
                           'Sources/BuildScripts/XCFrameworkBuild/main.swift': recipe.encode()}
                for filename in ('Sources/_MPVKit-GPL/dummy.c', 'Sources/_FFmpeg-GPL/dummy.c', 'LICENSE'):
                    content[filename] = b'package source'
                    write('package/' + filename, content[filename])
            archive_path = root / path
            archive_path.parent.mkdir(parents=True, exist_ok=True)
            with tarfile.open(archive_path, 'w:gz') as archive:
                for filename, data in content.items():
                    member = tarfile.TarInfo(filename)
                    member.size, member.mode = len(data), 0o644
                    archive.addfile(member, io.BytesIO(data))
            tree = publication.archive_tree(archive_path)
            commit = ('tree ' + tree + '\nparent ' + 'a' * 40 + '\n'
                      'author Test <test@example.invalid> 1 +0000\n'
                      'committer Test <test@example.invalid> 1 +0000\n\ntest snapshot\n').encode()
            commit_path = 'sources/' + name + '.commit'
            write(commit_path, commit)
            revision = publication.git_object('commit', commit).hex()
            if name == 'MPVKit-recipe':
                receipt['candidateMPVKitRevision'] = revision
            else:
                receipt['sourceInputs'][name] = {'candidateRevision': revision, 'candidateTree': tree}
            snapshots.append({'name': name, 'revision': revision, 'tree': tree,
                              'archivePath': path, 'commitPath': commit_path})
        receipt_path = write('provenance/build-receipt.json', json.dumps(receipt).encode())
        metadata = {'schemaVersion': 1, 'status': 'prepared-local-unpublished', 'shippingProduct': 'MPVKit-GPL',
                    'platforms': ['macos'], 'minimumMacOS': '12.0', 'architectures': ['arm64', 'x86_64'],
                    'releaseBaseURL': BASE, 'luaEnabled': False, 'blockers': publication.BLOCKERS,
                    'binaryTargets': targets, 'auxiliaryBuildInputs': inputs, 'sourceSnapshots': snapshots,
                    'verification': receipt['verification'],
                    'buildReceiptSHA256': publication.sha(receipt_path), 'preparerSHA256': publication.sha(preparer),
                    'files': {str(file.relative_to(root)): publication.identity(file) for file in root.rglob('*') if file.is_file()}}
        self.save(root, metadata)
        return metadata

    def save(self, root, metadata):
        (root / 'publication.json').write_text(json.dumps(metadata))

    def test_valid_complete_package_verifies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            result = publication.verify(root)
            self.assertTrue(result['passed'])
            self.assertEqual(result['auxiliaryTargetCount'], 21)
            self.assertEqual(result['gplArtifactCount'], 8)

    def test_mutated_asset_and_neighbor_metadata_cannot_replace_build_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            metadata = self.fixture(root)
            target = metadata['binaryTargets'][0]
            path = root / target['assetPath']
            path.write_bytes(b'replacement')
            metadata['files'][target['assetPath']] = publication.identity(path)
            target['checksum'] = publication.sha(path)
            self.save(root, metadata)
            with self.assertRaisesRegex(ValueError, 'immutable build receipt'):
                publication.verify(root)

    def test_auxiliary_target_replacement_rejected_even_with_regenerated_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            metadata = self.fixture(root)
            metadata['binaryTargets'][8]['checksum'] = 'b' * 64
            path = root / 'package/Package.swift'
            path.write_text(publication.package_manifest(metadata['binaryTargets']))
            metadata['files']['package/Package.swift'] = publication.identity(path)
            self.save(root, metadata)
            with self.assertRaisesRegex(ValueError, 'retained recipe declarations'):
                publication.verify(root)

    def test_missing_target_input_source_and_broadened_platform_rejected(self):
        for field in ('binaryTargets', 'auxiliaryBuildInputs', 'sourceSnapshots', 'platforms'):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                metadata = self.fixture(root)
                metadata[field].pop()
                self.save(root, metadata)
                with self.assertRaises(ValueError):
                    publication.verify(root)

    def test_recipe_url_authentication_and_blocker_claim_mutations_rejected(self):
        for mutation in ('url', 'authenticated', 'blockers', 'source-tree'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                metadata = self.fixture(root)
                if mutation == 'url':
                    metadata['auxiliaryBuildInputs'][0]['recipeURL'] = 'https://example.com/replaced.zip'
                elif mutation == 'authenticated':
                    metadata['binaryTargets'][0]['remoteAuthenticated'] = True
                elif mutation == 'blockers':
                    metadata['blockers'] = []
                else:
                    metadata['sourceSnapshots'][1]['tree'] = '0' * 40
                self.save(root, metadata)
                with self.assertRaises(ValueError):
                    publication.verify(root)

    def test_source_archive_replacement_cannot_replace_committed_tree(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            metadata = self.fixture(root)
            path = metadata['sourceSnapshots'][1]['archivePath']
            with tarfile.open(root / path, 'w:gz') as archive:
                member = tarfile.TarInfo('source.txt')
                member.size = 7
                archive.addfile(member, io.BytesIO(b'changed'))
            metadata['files'][path] = publication.identity(root / path)
            self.save(root, metadata)
            with self.assertRaisesRegex(ValueError, 'Git identity mismatch'):
                publication.verify(root)

    def test_untracked_file_and_missing_file_rejected(self):
        for mutation in ('extra', 'nested-publication', 'missing'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root)
                if mutation == 'extra':
                    (root / 'extra').write_text('unexpected')
                elif mutation == 'nested-publication':
                    (root / 'sources/publication.json').write_text('unexpected')
                else:
                    (root / 'provenance/builder.py').unlink()
                with self.assertRaisesRegex(ValueError, 'inventory mismatch'):
                    publication.verify(root)

    def test_symlink_payload_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            metadata = self.fixture(root)
            target = root / 'provenance/preparer.py'
            target.unlink()
            target.symlink_to(root / 'provenance/builder.py')
            metadata['files']['provenance/preparer.py'] = publication.identity(target)
            self.save(root, metadata)
            with self.assertRaisesRegex(ValueError, 'payload identity mismatch'):
                publication.verify(root)

    def test_existing_output_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, 'never overwritten'):
                publication.prepare(Path('/missing-build'), Path(temporary), BASE)

    def test_release_url_requires_explicit_safe_tag(self):
        self.assertEqual(publication.release_base(BASE), BASE)
        for value in ('http://github.com/a/b/releases/download/v1', BASE + '?token=secret',
                      BASE + '#fragment', BASE.replace('test-immutable-tag', 'latest'),
                      BASE.replace('test-immutable-tag', 'main'), BASE.replace('github.com', 'example.com'),
                      BASE + '/extra', BASE + '"'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                publication.release_base(value)

    def test_offline_reconstruction_restores_exact_commits_trees_and_zip_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stage, workspace = root / 'stage', root / 'workspace'
            stage.mkdir()
            metadata = self.fixture(stage)
            with patch.dict(publication.os.environ, {'GIT_DIR': str(root / 'wrong-git-directory')}):
                result = publication.reconstruct(stage, workspace, publication.sha(stage / 'publication.json'))
            self.assertFalse(result['buildExecuted'])
            self.assertEqual(result['status'], 'reconstructed-inputs-not-built')
            self.assertFalse(result['environmentDeclaration']['byteIdenticalRebuildDemonstrated'])
            self.assertIsNone(result['environmentDeclaration']['recordedBuild']['xcodeVersion'])
            for snapshot in metadata['sourceSnapshots']:
                path = workspace / 'MPVKit'
                if snapshot['name'] != 'MPVKit-recipe':
                    path = path / 'dist' / snapshot['name']
                for expression, expected in [('HEAD', snapshot['revision']), ('HEAD^{tree}', snapshot['tree'])]:
                    actual = subprocess.check_output(['git', '-C', str(path), 'rev-parse', expression]).decode().strip()
                    self.assertEqual(actual, expected)
                self.assertEqual((path / '.git/shallow').read_text(), snapshot['revision'] + '\n')
            for entry in metadata['auxiliaryBuildInputs']:
                self.assertEqual(publication.identity(workspace / 'MPVKit' / entry['relativePath']),
                                 {key: entry[key] for key in ('sha256', 'sizeBytes')})
            self.assertEqual(json.loads((workspace / 'reconstruction.json').read_text()), result)
            self.assertIn(str(workspace / 'MPVKit/Sources/BuildScripts'), result['candidateBuildCommand'])
            self.assertFalse((workspace / 'build.log').exists())
            self.assertEqual(result['reconstructionDriverSHA256'], publication.sha(workspace / 'reconstruction-driver.py'))
            self.assertTrue((workspace / 'temporary').is_dir())

    def test_reconstruction_requires_external_digest_and_verified_stage_before_creating_output(self):
        for mutation in ('digest', 'asset', 'invalid-digest'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                stage, workspace = root / 'stage', root / 'workspace'
                stage.mkdir()
                metadata = self.fixture(stage)
                digest = publication.sha(stage / 'publication.json')
                if mutation == 'digest':
                    digest = '0' * 64
                elif mutation == 'invalid-digest':
                    digest = 'invalid'
                else:
                    (stage / metadata['binaryTargets'][0]['assetPath']).write_bytes(b'mutated')
                with self.assertRaises(ValueError):
                    publication.reconstruct(stage, workspace, digest)
                self.assertFalse(workspace.exists())

    def test_reconstruction_cannot_overwrite_workspace_or_write_inside_stage(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary)
            self.fixture(stage)
            digest = publication.sha(stage / 'publication.json')
            with self.assertRaisesRegex(ValueError, 'never overwritten'):
                publication.reconstruct(stage, stage, digest)
            with self.assertRaisesRegex(ValueError, 'separate from publication'):
                publication.reconstruct(stage, stage / 'new-output', digest)
            self.assertFalse((stage / 'new-output').exists())

    def test_reconstruction_rejects_archive_symlinks_before_extraction(self):
        for name, link in [('link', '../outside'), ('link', '/tmp/outside')]:
            with self.subTest(link=link), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive_path = root / 'archive.tar.gz'
                with tarfile.open(archive_path, 'w:gz') as archive:
                    good = tarfile.TarInfo('source.txt')
                    good.size = 4
                    archive.addfile(good, io.BytesIO(b'good'))
                    bad = tarfile.TarInfo(name)
                    bad.type, bad.linkname = tarfile.SYMTYPE, link
                    archive.addfile(bad)
                with self.assertRaisesRegex(ValueError, 'unsafe reconstruction source'):
                    publication.restore_source(archive_path, root / 'missing.commit', root / 'output', {})
                self.assertFalse((root / 'output').exists())

    def test_manifest_has_only_gpl_product_and_macos_and_no_lua(self):
        text = publication.package_manifest([])
        self.assertIn('platforms: [.macOS(.v12)]', text)
        self.assertNotIn('Libluajit', text)
        self.assertNotIn('iOS(', text)
        self.assertEqual(text.count('.library('), 1)


if __name__ == '__main__':
    unittest.main()
