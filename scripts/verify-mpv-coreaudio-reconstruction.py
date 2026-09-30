#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Audit an offline reconstructed CoreAudio workspace against a pinned stage.

This reads retained inputs only. It never invokes a dependency build, downloads
assets, relocates the recipe, or changes the app's shipping dependency pin.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tarfile

spec = importlib.util.spec_from_file_location(
    'publication', Path(__file__).with_name('prepare-mpv-coreaudio-publication.py'))
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


def verify_payload_inventory(stage, workspace, metadata):
    """Require precisely the retained inputs, including ignored build files.

    Git status is insufficient: ignored headers, Swift sources and prior build
    output can affect compilation without changing any committed source byte.
    Only each restored repository's own Git metadata directory is excluded.
    """
    cache_names = {'clang-cache', 'swift-cache', 'temporary'}
    expected_workspace = cache_names | {'MPVKit', 'reconstruction-driver.py', 'reconstruction.json'}
    if {path.name for path in workspace.iterdir()} != expected_workspace:
        raise ValueError('reconstructed payload inventory mismatch: workspace entries')
    for name in expected_workspace:
        path = workspace / name
        if path.is_symlink():
            raise ValueError('reconstructed payload inventory mismatch: workspace symlink ' + name)
        if name in cache_names:
            if not path.is_dir() or any(path.iterdir()):
                raise ValueError('reconstructed payload inventory mismatch: nonempty or missing cache ' + name)
        elif name != 'MPVKit' and not stat.S_ISREG(path.lstat().st_mode):
            raise ValueError('reconstructed payload inventory mismatch: nonregular workspace file ' + name)
    checkout = workspace / 'MPVKit'
    expected_files, expected_directories, git_directories = set(), {Path('.')}, set()

    def include(path, is_directory=False):
        (expected_directories if is_directory else expected_files).add(path)
        expected_directories.update(path.parents)

    for snapshot in metadata['sourceSnapshots']:
        root = Path('.') if snapshot['name'] == 'MPVKit-recipe' else Path('dist') / snapshot['name']
        include(root, is_directory=True)
        git_directories.add(root / '.git')
        with tarfile.open(stage / snapshot['archivePath'], 'r:gz') as archive:
            for member in archive:
                if not (member.isfile() or member.isdir()):
                    raise ValueError('unsupported reconstruction source archive entry')
                include(root / member.name, is_directory=member.isdir())
    for entry in metadata['auxiliaryBuildInputs']:
        include(Path(entry['relativePath']))

    if checkout.is_symlink() or not checkout.is_dir():
        raise ValueError('reconstructed payload inventory mismatch: MPVKit directory')
    actual_files, actual_directories, actual_git = set(), {Path('.')}, set()
    def walk_error(error):
        raise error
    for root, directories, files in os.walk(checkout, topdown=True, followlinks=False, onerror=walk_error):
        for name in directories[:]:
            path = Path(root) / name
            relative = path.relative_to(checkout)
            if path.is_symlink():
                raise ValueError('reconstructed payload inventory mismatch: symlink ' + str(relative))
            if relative in git_directories:
                actual_git.add(relative)
                directories.remove(name)
            else:
                actual_directories.add(relative)
        for name in files:
            path = Path(root) / name
            relative = path.relative_to(checkout)
            if not stat.S_ISREG(path.lstat().st_mode):
                raise ValueError('reconstructed payload inventory mismatch: nonregular file ' + str(relative))
            actual_files.add(relative)
    if (actual_files != expected_files or actual_directories != expected_directories
            or actual_git != git_directories):
        extras = sorted(str(path) for path in (actual_files - expected_files) | (actual_directories - expected_directories))
        missing = sorted(str(path) for path in (expected_files - actual_files) | (expected_directories - actual_directories) | (git_directories - actual_git))
        raise ValueError('reconstructed payload inventory mismatch: extra=' + repr(extras) + ', missing=' + repr(missing))
    return len(actual_files)


def verify(stage, workspace, expected_publication_sha256):
    if not re.fullmatch(r'[a-f0-9]{64}', expected_publication_sha256):
        raise ValueError('expected publication SHA-256 must be an externally retained lowercase digest')
    if publication.sha(stage / 'publication.json') != expected_publication_sha256:
        raise ValueError('publication does not match externally retained SHA-256')
    # Verifying the stage is necessary: the manifest alone does not verify the
    # immutable receipt, source archive/commit objects or declared origins.
    publication.verify(stage)
    metadata = json.loads((stage / 'publication.json').read_text())
    payload_file_count = verify_payload_inventory(stage, workspace, metadata)
    retained = json.loads((stage / 'provenance/build-receipt.json').read_text())
    reconstructed = json.loads((workspace / 'reconstruction.json').read_text())
    driver_sha = publication.sha(workspace / 'reconstruction-driver.py')
    expected_inputs = [{key: entry[key] for key in ('relativePath', 'sha256', 'sizeBytes')}
                       for entry in metadata['auxiliaryBuildInputs']]
    if (reconstructed.get('schemaVersion') != 1
            or reconstructed.get('publicationSHA256') != expected_publication_sha256
            or reconstructed.get('sourceSnapshots') != metadata['sourceSnapshots']
            or reconstructed.get('auxiliaryBuildInputs') != expected_inputs
            or reconstructed.get('buildExecuted') is not False
            or reconstructed.get('status') != 'reconstructed-inputs-not-built'
            or reconstructed.get('recipePathRelocations') != []
            or reconstructed.get('blockers') != metadata['blockers']
            or reconstructed.get('environmentDeclaration') != publication.reconstruction_environment(retained)
            or any(reconstructed.get(key) != value for key, value in publication.reconstruction_build_plan(workspace).items())
            or reconstructed.get('reconstructionDriverSHA256') != driver_sha):
        raise ValueError('reconstruction receipt binding mismatch')
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    environment.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_ATTR_NOSYSTEM='1')
    sources = []
    source_file_count = 0
    for snapshot in metadata['sourceSnapshots']:
        directory = workspace / 'MPVKit'
        if snapshot['name'] != 'MPVKit-recipe':
            directory /= 'dist/' + snapshot['name']
        def git(*command):
            return subprocess.check_output(['git', '-C', str(directory), *command], env=environment).decode().strip()
        revision, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
        if revision != snapshot['revision'] or tree != snapshot['tree']:
            raise ValueError('reconstructed source Git identity mismatch')
        # Read actual working files, rather than trusting Git status/index flags
        # such as assume-unchanged or feature-dependent filemode handling.
        with tarfile.open(stage / snapshot['archivePath'], 'r:gz') as archive:
            for member in archive:
                if not member.isfile():
                    if not member.isdir():
                        raise ValueError('unsupported reconstruction source archive entry')
                    continue
                path = directory / member.name
                if (path.is_symlink() or directory.resolve() not in path.resolve().parents
                        or not path.is_file() or path.stat().st_size != member.size
                        or bool(path.stat().st_mode & 0o111) != bool(member.mode & 0o111)
                        or publication.sha(path) != hashlib.sha256(archive.extractfile(member).read()).hexdigest()):
                    raise ValueError('reconstructed source working-file identity mismatch: ' + snapshot['name'] + '/' + member.name)
                source_file_count += 1
        sources.append({'name': snapshot['name'], 'revision': revision, 'tree': tree,
                        'shallow': git('rev-parse', '--is-shallow-repository') == 'true'})
    for entry in metadata['auxiliaryBuildInputs']:
        path = workspace / 'MPVKit' / entry['relativePath']
        if (path.is_symlink() or (workspace / 'MPVKit').resolve() not in path.resolve().parents
                or publication.identity(path) != {key: entry[key] for key in ('sha256', 'sizeBytes')}):
            raise ValueError('reconstructed auxiliary input identity mismatch')
    return {'passed': True, 'scope': 'Retained source/input identity audit; dependency compilation is not verified.',
            'publicationSHA256': expected_publication_sha256,
            'reconstructionSHA256': publication.sha(workspace / 'reconstruction.json'),
            'driverSHA256': driver_sha, 'sourceSnapshots': sources,
            'sourceFileCount': source_file_count, 'auxiliaryInputCount': len(expected_inputs),
            'payloadFileCount': payload_file_count,
            'byteIdenticalRebuildDemonstrated': False, 'blockers': metadata['blockers']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('workspace', type=Path)
    parser.add_argument('--expected-publication-sha256', required=True)
    args = parser.parse_args()
    try:
        result = verify(args.stage.resolve(), args.workspace.resolve(), args.expected_publication_sha256)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f'Reconstruction verification failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
