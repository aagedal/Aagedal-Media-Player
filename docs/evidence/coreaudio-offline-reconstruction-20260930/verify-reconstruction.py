#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Independently check an offline reconstructed workspace against a pinned stage."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def identity(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(block)
    return {'sha256': digest.hexdigest(), 'sizeBytes': path.stat().st_size}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('workspace', type=Path)
    parser.add_argument('--expected-publication-sha256', required=True)
    args = parser.parse_args()
    stage, workspace = args.stage.resolve(), args.workspace.resolve()
    actual_digest = identity(stage / 'publication.json')['sha256']
    if actual_digest != args.expected_publication_sha256:
        raise ValueError('stage manifest digest mismatch')
    metadata = json.loads((stage / 'publication.json').read_text())
    reconstructed = json.loads((workspace / 'reconstruction.json').read_text())
    if (reconstructed['publicationSHA256'] != actual_digest
            or reconstructed['sourceSnapshots'] != metadata['sourceSnapshots']
            or reconstructed['buildExecuted'] is not False
            or reconstructed['status'] != 'reconstructed-inputs-not-built'
            or reconstructed['reconstructionDriverSHA256'] != identity(workspace / 'reconstruction-driver.py')['sha256']):
        raise ValueError('reconstruction receipt binding mismatch')
    sources = []
    for snapshot in metadata['sourceSnapshots']:
        path = workspace / 'MPVKit'
        if snapshot['name'] != 'MPVKit-recipe':
            path = path / 'dist' / snapshot['name']
        def git(*command):
            return subprocess.check_output(['git', '-C', str(path), *command]).decode().strip()
        revision, tree, status = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}'), git('status', '--porcelain')
        if revision != snapshot['revision'] or tree != snapshot['tree'] or status:
            raise ValueError('reconstructed source Git identity/status mismatch')
        sources.append({'name': snapshot['name'], 'revision': revision, 'tree': tree, 'clean': True,
                        'shallow': git('rev-parse', '--is-shallow-repository') == 'true'})
    for entry in metadata['auxiliaryBuildInputs']:
        expected = {key: entry[key] for key in ('sha256', 'sizeBytes')}
        if identity(workspace / 'MPVKit' / entry['relativePath']) != expected:
            raise ValueError('reconstructed ZIP identity mismatch')
    if (workspace / 'build.log').exists() or (workspace / 'MPVKit/dist/release').exists():
        raise ValueError('unexpected compiled-output path in offline workspace')
    print(json.dumps({'passed': True, 'publicationSHA256': actual_digest,
                      'reconstructionSHA256': identity(workspace / 'reconstruction.json')['sha256'],
                      'driverSHA256': reconstructed['reconstructionDriverSHA256'],
                      'sourceSnapshots': sources, 'auxiliaryInputCount': len(metadata['auxiliaryBuildInputs']),
                      'buildExecuted': False, 'byteIdenticalRebuildDemonstrated': False}, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
