#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Restore the validated arm64 MPVKit package and optionally prepare a fresh app copy.

No MPVKit rebuild, original package cache, Metal compiler, or /private/tmp build
workspace is required. The repository handoff descriptor pins the release asset.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        name = str(path.relative_to(root))
        if name == 'bundle.json':
            continue
        if path.is_symlink():
            result[name] = {'link': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': sha(path), 'sizeBytes': path.stat().st_size}
        elif not path.is_dir():
            raise ValueError('unsupported bundle entry: ' + name)
    return result


def restore(archive, output, expected):
    if output.exists():
        raise ValueError('restore output must be new')
    if archive.stat().st_size != expected['sizeBytes'] or sha(archive) != expected['sha256']:
        raise ValueError('bundle does not match repository-pinned size/SHA256')
    with tarfile.open(archive, 'r:gz') as file:
        names = set()
        for member in file.getmembers():
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or '\\' in member.name or member.name in names:
                raise ValueError('unsafe or duplicate bundle path')
            names.add(member.name)
            if member.issym():
                link = Path(member.linkname)
                if link.is_absolute() or '..' in link.parts or '\\' in member.linkname:
                    raise ValueError('unsafe bundle symlink')
            elif not (member.isfile() or member.isdir()):
                raise ValueError('unsupported bundle member')
        output.mkdir(parents=True)
        try:
            file.extractall(output, filter='data')
            metadata = verify_restored(output, expected)
        except Exception:
            shutil.rmtree(output)
            raise
    return metadata


def verify_restored(root, expected):
    manifest = root / 'bundle.json'
    if expected.get('inventorySHA256') and sha(manifest) != expected['inventorySHA256']:
        raise ValueError('restored inventory differs from repository-pinned manifest')
    metadata = json.loads(manifest.read_text())
    if metadata['architectures'] != ['arm64'] or inventory(root) != metadata['files']:
        raise ValueError('restored bundle inventory/architecture mismatch')
    return metadata


def prepare_app(repository, package, output):
    repository, package, output = (path.resolve() for path in (repository, package, output))
    if output.exists() or output == repository or repository in output.parents:
        raise ValueError('app output must be new and outside the source repository')
    if not (package / 'Package.swift').is_file():
        raise ValueError('restored MPVKit package missing')
    output.mkdir(parents=True)
    for name in ('Aagedal Media Player', 'Aagedal Media Player Tests', 'Aagedal Media Player.xcodeproj'):
        shutil.copytree(repository / name, output / name, ignore=shutil.ignore_patterns('xcuserdata', '.DS_Store'))
    project = output / 'Aagedal Media Player.xcodeproj/project.pbxproj'
    text, count = re.subn(r'isa = XCRemoteSwiftPackageReference;\s*repositoryURL = "https://github.com/aagedal/MPVKit";\s*requirement = \{[^}]+\};',
                         'isa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ' + json.dumps(str(package)) + ';', project.read_text())
    if count != 1:
        raise ValueError('expected exactly one MPVKit project reference')
    project.write_text(text)
    # A fresh cache has no remote MPVKit checkout: retain only remote packages
    # still referenced by this isolated project. Shipping pins stay untouched.
    resolved = output / 'Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    data = json.loads(resolved.read_text())
    data['pins'] = [pin for pin in data['pins'] if pin['identity'].lower() != 'mpvkit']
    resolved.write_text(json.dumps(data, indent=2) + '\n')
    fixtures = package.parent / 'fixtures/fixtures.json'
    if fixtures.is_file():
        data = json.loads(fixtures.read_text())
        for case in data['cases']:
            case['input'] = str(fixtures.parent / Path(case['input']).name)
            if case.get('references'):
                case['references'] = [str(fixtures.parent / Path(path).name) for path in case['references']]
        (output / 'native-fixtures.json').write_text(json.dumps(data, indent=2) + '\n')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='new persistent directory for the restored package')
    parser.add_argument('--reuse', action='store_true', help='verify an existing restoration and prepare a new app copy without downloading again')
    parser.add_argument('--bundle', type=Path, help='already downloaded bundle; otherwise download the pinned release asset')
    parser.add_argument('--descriptor', type=Path, default=Path(__file__).resolve().parents[1] / 'docs/mpv-decoder-raster-handoff.json')
    parser.add_argument('--prepare-app', type=Path, metavar='REPOSITORY')
    parser.add_argument('--app-output', type=Path)
    args = parser.parse_args()
    if bool(args.prepare_app) != bool(args.app_output):
        parser.error('--prepare-app and --app-output must be supplied together')
    descriptor = json.loads(args.descriptor.read_text())
    if args.reuse:
        if args.bundle:
            parser.error('--reuse and --bundle cannot be combined')
        verify_restored(args.output.resolve(), descriptor)
    else:
        with tempfile.TemporaryDirectory() as temporary:
            archive = args.bundle or Path(temporary) / 'candidate.tar.gz'
            if not args.bundle:
                subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--output', str(archive), descriptor['url']], check=True)
            restore(archive, args.output.resolve(), descriptor)
    print('Restored verified arm64 MPVKit:', args.output.resolve() / 'MPVKit')
    if args.prepare_app:
        app = prepare_app(args.prepare_app, args.output / 'MPVKit', args.app_output)
        print('Prepared app project:', app / 'Aagedal Media Player.xcodeproj')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
