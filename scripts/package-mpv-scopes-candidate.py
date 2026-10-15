#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Package an arm64 scope delta and pin its bytes in a new descriptor."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import tarfile
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('restore',root/'scripts/restore-mpv-decoder-raster-candidate.py')
    restore = importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('candidate',type=Path);p.add_argument('archive',type=Path);p.add_argument('descriptor',type=Path)
    p.add_argument('--validation-directory',type=Path)
    a = p.parse_args()
    if a.archive.exists() or a.descriptor.exists():raise ValueError('archive and descriptor must be new')
    candidate = a.candidate.resolve()
    receipt = json.loads((candidate/'receipt.json').read_text())
    if receipt['architectures'] != ['arm64'] or restore.sha(candidate/'objects/libmpv.a') != receipt['archiveSHA256']:
        raise ValueError('candidate archive does not match receipt')
    for name, sha in receipt['providerInputs'].items():
        if restore.sha(candidate/'source/player'/name) != sha:raise ValueError('candidate source changed')
    with tempfile.TemporaryDirectory() as tmp:
        payload = Path(tmp)
        shutil.copyfile(candidate/'objects/libmpv.a',payload/'libmpv.a')
        shutil.copyfile(candidate/'receipt.json',payload/'build-receipt.json')
        shutil.copyfile(candidate/'source.patch',payload/'source.patch')
        with tarfile.open(payload/'mpv-scopes-source.tar.gz','w:gz') as tar:
            tar.add(candidate/'source',arcname='mpv-scopes')
        clients = payload/'clients'
        clients.mkdir()
        for name in ('scope-native','scope-gpu','scope-native-link.json','scope-gpu-link.json'):
            if (candidate/name).is_file():shutil.copy2(candidate/name,clients/name)
        if a.validation_directory:
            shutil.copytree(a.validation_directory,payload/'validation')
        metadata = {'schemaVersion':1,'architectures':['arm64'],
            'baselineInventorySHA256':json.loads((root/'docs/mpv-decoder-raster-handoff.json').read_text())['inventorySHA256'],
            'files':restore.inventory(payload)}
        (payload/'bundle.json').write_text(json.dumps(metadata,indent=2)+'\n')
        a.archive.parent.mkdir(parents=True,exist_ok=True)
        with tarfile.open(a.archive,'w:gz') as tar:
            for file in sorted(payload.iterdir()):tar.add(file,arcname=file.name)
        descriptor = {'schemaVersion':1,'architectures':['arm64'],'filename':a.archive.name,
            'sha256':restore.sha(a.archive),'sizeBytes':a.archive.stat().st_size,
            'inventorySHA256':restore.sha(payload/'bundle.json'),
            'baselineDescriptor':'mpv-decoder-raster-handoff.json',
            'scope':'Local development delta; shipping package pins remain unchanged.'}
        a.descriptor.write_text(json.dumps(descriptor,indent=2)+'\n')
    print(a.archive)


if __name__=='__main__':main()
