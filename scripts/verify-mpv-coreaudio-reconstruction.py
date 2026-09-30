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
import subprocess
import sys
import tarfile

spec = importlib.util.spec_from_file_location(
    'publication', Path(__file__).with_name('prepare-mpv-coreaudio-publication.py'))
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


def verify(stage, workspace, expected_publication_sha256):
    if not re.fullmatch(r'[a-f0-9]{64}', expected_publication_sha256):
        raise ValueError('expected publication SHA-256 must be an externally retained lowercase digest')
    if publication.sha(stage / 'publication.json') != expected_publication_sha256:
        raise ValueError('publication does not match externally retained SHA-256')
    # Verifying the stage is necessary: the manifest alone does not verify the
    # immutable receipt, source archive/commit objects or declared origins.
    publication.verify(stage)
    metadata = json.loads((stage / 'publication.json').read_text())
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
