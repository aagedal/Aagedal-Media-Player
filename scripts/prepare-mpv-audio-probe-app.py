#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare a NEW arm64 audio-probe app without recompiling MPVKit.

Verify the repository-pinned raster bundle, scope delta and audio release;
overlay seven ABI-matched FFmpeg n8.1.2 archives while retaining native scopes.
Inputs are read-only. Shipping package pins and provider gates stay unchanged.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('restore', root / 'scripts/restore-mpv-decoder-raster-candidate.py')
    restore = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restore)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('scope_delta', type=Path, help='Restored pinned delta directory, with bundle.json')
    parser.add_argument('audio_release', type=Path, help='Retained audio.1 archives and release.json')
    parser.add_argument('output', type=Path)
    parser.add_argument('--repository', type=Path, default=root)
    args = parser.parse_args()
    descriptor = json.loads((root / 'docs/mpv-audio-probe-handoff.json').read_text())
    restore.verify_restored(args.baseline, json.loads((root / 'docs/mpv-decoder-raster-handoff.json').read_text()))
    delta = restore.verify_restored(args.scope_delta, json.loads((root / 'docs/mpv-scopes-handoff.json').read_text()))
    if delta['baselineInventorySHA256'] != restore.sha(args.baseline / 'bundle.json'):
        raise ValueError('scope delta baseline mismatch')
    if restore.sha(args.audio_release / 'release.json') != descriptor['releaseDescriptorSHA256']:
        raise ValueError('audio release descriptor checksum mismatch')
    release = json.loads((args.audio_release / 'release.json').read_text())
    if release['tag'] != descriptor['audioRelease']:
        raise ValueError('audio release identity mismatch')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    package = output / 'MPVKit'
    shutil.copytree(args.baseline / 'MPVKit', package, symlinks=True)
    mpv = package / 'Candidate/Libmpv-GPL/Libmpv.xcframework/macos-arm64/Libmpv.framework/Versions/A/Libmpv'
    shutil.copyfile(args.scope_delta / 'libmpv.a', mpv)
    overlays = []
    for artifact in release['artifacts']:
        if artifact['asset'].startswith('Libmpv-'):
            continue
        archive = args.audio_release / artifact['asset']
        if archive.stat().st_size != artifact['bytes'] or restore.sha(archive) != artifact['sha256']:
            raise ValueError('audio archive checksum mismatch: ' + archive.name)
        name = artifact['asset'].split('-GPL.')[0]
        with tempfile.TemporaryDirectory(prefix='aagedal-audio-overlay-') as temp:
            extracted = Path(temp)
            with zipfile.ZipFile(archive) as file:
                for entry in file.infolist():
                    path = Path(entry.filename)
                    if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
                        raise ValueError('unsafe audio archive path')
            subprocess.run(['ditto', '-x', '-k', str(archive.resolve()), str(extracted)], check=True)
            frameworks = list(extracted.rglob(name + '.framework'))
            if len(frameworks) != 1:
                raise ValueError('expected one macOS framework')
            framework = frameworks[0]
            binary = framework / 'Versions/A' / name
            if restore.sha(binary) != artifact['binary_sha256']:
                raise ValueError('audio binary checksum mismatch: ' + name)
            thin = extracted / 'arm64.a'
            subprocess.run(['lipo', str(binary), '-thin', 'arm64', '-output', str(thin)], check=True)
            shutil.copyfile(thin, binary)
            target = package / 'Candidate' / (name + '-GPL') / (name + '.xcframework/macos-arm64') / framework.name
            shutil.rmtree(target)
            shutil.copytree(framework, target, symlinks=True)
            if subprocess.check_output(['lipo', '-archs', str(target / 'Versions/A' / name)], text=True).strip() != 'arm64':
                raise ValueError('unexpected output architecture')
            overlays.append({'target': name, 'archiveSHA256': artifact['sha256'], 'arm64SHA256': restore.sha(binary)})
    if len(overlays) != 7:
        raise ValueError('expected seven FFmpeg targets')
    receipt = {'architectures': ['arm64'], 'audioRelease': release['tag'], 'overlays': overlays,
               'libmpvSHA256': restore.sha(mpv), 'scopeDeltaInventorySHA256': restore.sha(args.scope_delta / 'bundle.json')}
    restore.prepare_app(args.repository, package, output / 'app')
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(output / 'app')


if __name__ == '__main__':
    main()
