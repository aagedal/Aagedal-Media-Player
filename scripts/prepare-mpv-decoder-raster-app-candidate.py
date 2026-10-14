#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Copy the app into an isolated workspace with local candidate binary targets.

The source project, shipping pins, and original package cache are read-only.
This is a development integration workspace, not a publishable dependency.
"""
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

spec = importlib.util.spec_from_file_location('builder', Path(__file__).with_name('build-mpv-coreaudio-clean-candidate.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def unpack_framework(archive, destination):
    # Framework links (Versions/Current, top-level binary/resources) are needed
    # by Xcode. Accept contained relative links, never arbitrary ZIP links.
    with zipfile.ZipFile(archive) as file:
        for entry in file.infolist():
            path = Path(entry.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
                raise ValueError('unsafe framework archive path')
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                target = Path(file.read(entry).decode('utf-8'))
                if target.is_absolute() or '..' in target.parts or '\\' in str(target):
                    raise ValueError('unsafe framework archive link')
    destination.mkdir(parents=True)
    subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), str(destination)], check=True)


def prepare(repository, cache, build, output):
    repository, cache, build, output = (p.resolve() for p in (repository, cache, build, output))
    if output.exists():
        raise ValueError('candidate output must be new')
    if output == repository or repository in output.parents:
        raise ValueError('candidate workspace must be outside the source repository')
    receipt = json.loads((build / 'portable-build.json').read_text())
    if not receipt.get('buildSucceeded') or not receipt.get('decoderRasterCandidate'):
        raise ValueError('requires a successful decoder-raster candidate rebuild')
    builder.verify_build(build, receipt)
    resolved = repository / 'Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    subprocess.run(['python3', str(Path(__file__).with_name('validate-candidate-package-cache.py')),
                    str(resolved), str(cache)], check=True)
    app, package = output / 'app', output / 'MPVKit'
    app.mkdir(parents=True)
    for name in ('Aagedal Media Player', 'Aagedal Media Player Tests', 'Aagedal Media Player.xcodeproj'):
        shutil.copytree(repository / name, app / name, ignore=shutil.ignore_patterns('xcuserdata', '.DS_Store'))
    shutil.copytree(cache / 'checkouts/MPVKit/Sources', package / 'Sources')
    text = (cache / 'checkouts/MPVKit/Package.swift').read_text()
    artifacts = {}
    rebuilt = {'Libmpv', 'Libavcodec', 'Libavdevice', 'Libavfilter', 'Libavformat',
               'Libavutil', 'Libswresample', 'Libswscale'}
    def local_target(match):
        name = match.group(1)
        directory = package / 'Candidate' / name
        base = name.removesuffix('-GPL')
        if base in rebuilt:
            archive = build / 'MPVKit/dist/release' / (base + '.xcframework.zip')
            unpack_framework(archive, directory)
            artifacts[name] = {'source': 'rebuilt', 'archiveSHA256': builder.sha(archive)}
        else:
            shutil.copytree(cache / 'artifacts/mpvkit' / name, directory, symlinks=True)
            artifacts[name] = {'source': 'qualified shipping auxiliary'}
        frameworks = list(directory.glob('*.xcframework'))
        if len(frameworks) != 1:
            raise ValueError('expected exactly one local framework: ' + name)
        binary = frameworks[0]
        artifacts[name]['frameworkPath'] = str(binary)
        info = plistlib.loads((binary / 'Info.plist').read_bytes())
        artifacts[name]['macOSBinaries'] = {}
        for library in info['AvailableLibraries']:
            if library['SupportedPlatform'] != 'macos':
                continue
            path = binary / library['LibraryIdentifier'] / library['LibraryPath']
            if path.suffix == '.framework':
                path /= path.stem
            artifacts[name]['macOSBinaries'][str(path.relative_to(package))] = builder.sha(path)
        if not artifacts[name]['macOSBinaries']:
            raise ValueError('local target has no macOS binary: ' + name)
        return '.binaryTarget(name: ' + json.dumps(name) + ', path: ' + json.dumps(str(binary.relative_to(package))) + ')'
    text, count = re.subn(r'\.binaryTarget\(name:\s*"([^"]+)",\s*url:\s*"[^"]+",\s*checksum:\s*"[a-f0-9]+"\)', local_target, text)
    if count != 29:
        raise ValueError('unexpected shipping binary-target inventory')
    (package / 'Package.swift').write_text(text)
    project = app / 'Aagedal Media Player.xcodeproj/project.pbxproj'
    text = project.read_text()
    text, count = re.subn(r'isa = XCRemoteSwiftPackageReference;\s*repositoryURL = "https://github.com/aagedal/MPVKit";\s*requirement = \{[^}]+\};',
                         'isa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ' + json.dumps(str(package)) + ';', text)
    if count != 1:
        raise ValueError('expected exactly one MPVKit project reference')
    project.write_text(text)
    report = {'scope': 'Isolated local development candidate; no shipping repin or publication.',
              'buildReceiptSHA256': builder.sha(build / 'portable-build.json'),
              'shippingPackageResolvedSHA256': builder.sha(resolved), 'artifacts': artifacts,
              'candidateManifestSHA256': builder.sha(package / 'Package.swift'),
              'candidateProjectSHA256': builder.sha(project),
              'appSourceSHA256': {str(p.relative_to(app)): builder.sha(p) for p in sorted(app.rglob('*'))
                                  if p.is_file()}}
    (output / 'app-candidate.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Prepared local candidate project: ' + str(project))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repository', 'cache', 'build', 'output'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    prepare(args.repository, args.cache, args.build, args.output)
