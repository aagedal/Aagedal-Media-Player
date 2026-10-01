#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage an unpublished, macOS-only MPVKit-GPL release without changing app pins.

Requires a shipping-qualified retained build and an explicit proposed immutable
GitHub release URL. All bytes remain local; no URL is claimed to exist. The
offline reconstruction mode restores exact source/input identities without
compiling, downloading dependencies, or relocating the retained recipe.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tarfile
from urllib.parse import urlsplit

LIBRARIES = ('Libmpv', 'Libavcodec', 'Libavdevice', 'Libavfilter', 'Libavformat',
             'Libavutil', 'Libswresample', 'Libswscale')
AUXILIARIES = ('Libssl', 'Libcrypto', 'Libass', 'Libfreetype', 'Libfribidi', 'Libharfbuzz',
               'MoltenVK', 'Libshaderc_combined', 'lcms2', 'Libplacebo', 'Libdovi', 'Libunibreak',
               'Libsmbclient', 'gmp', 'nettle', 'hogweed', 'gnutls', 'Libdav1d', 'Libuavs3d',
               'Libuchardet', 'Libbluray')
SOURCE_ORIGINS = {'MPVKit-recipe': 'https://github.com/aagedal/MPVKit',
                  'libmpv-v0.41.0': 'https://github.com/mpv-player/mpv',
                  'FFmpeg-n8.1.2': 'https://github.com/FFmpeg/FFmpeg'}
BLOCKERS = [
    'Proposed release URLs have not been published or downloaded.',
    'Auxiliary binary target and build-input URLs/checksums are upstream recipe declarations, not remote authentication.',
    'Fresh ordinary SwiftPM resolution and the shipping app build against the published package remain required.',
    'Source/configuration reproducibility is retained; byte-identical rebuilds have not been demonstrated.',
    'Recipe contains host paths and autodetection; environment isolation and supported-macOS/hardware acceptance remain open.',
]


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def identity(path):
    return {'sha256': sha(path), 'sizeBytes': path.stat().st_size}


def capture(args):
    return subprocess.check_output([str(arg) for arg in args]).decode().strip()


def release_base(value):
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or parsed.netloc != 'github.com' or parsed.query or parsed.fragment
            or not re.fullmatch(r'/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/[A-Za-z0-9_.-]+', parsed.path)
            or parsed.path.split('/')[-1].lower() in {'latest', 'main', 'master'}):
        raise ValueError('release base must be an explicit HTTPS GitHub release tag URL without query/fragment')
    return value


def binary_targets(manifest):
    entries = re.findall(r'\.binaryTarget\(\s*name:\s*"([^"]+)",\s*url:\s*"([^"]+)",\s*checksum:\s*"([a-f0-9]{64})"\s*\)', manifest)
    result = {name: {'name': name, 'url': url, 'checksum': checksum} for name, url, checksum in entries}
    if len(result) != len(entries):
        raise ValueError('duplicate binary target in retained package manifest')
    return result


def package_manifest(targets):
    def names(items):
        return ', '.join(json.dumps(item) for item in items)
    mpv = ['Libmpv-GPL', '_FFmpeg-GPL', 'Libuchardet', 'Libbluray']
    ffmpeg = [name + '-GPL' for name in LIBRARIES[1:]] + list(AUXILIARIES[:-2])
    frameworks = ['AudioToolbox', 'CoreVideo', 'CoreFoundation', 'CoreMedia', 'Metal', 'VideoToolbox']
    settings = ',\n                '.join('.linkedFramework(' + json.dumps(name) + ')' for name in frameworks)
    settings += ',\n                ' + ', '.join('.linkedLibrary(' + json.dumps(name) + ')' for name in ['bz2', 'iconv', 'expat', 'resolv', 'xml2', 'z', 'c++'])
    binaries = ',\n'.join('        .binaryTarget(name: ' + json.dumps(target['name']) + ',\n'
                          '                      url: ' + json.dumps(target['url']) + ',\n'
                          '                      checksum: ' + json.dumps(target['checksum']) + ')' for target in targets)
    return '''// swift-tools-version:5.9
// Prepared locally; publish and validate every release asset before installing.
import PackageDescription
let package = Package(
    name: "MPVKit",
    platforms: [.macOS(.v12)],
    products: [.library(name: "MPVKit-GPL", targets: ["_MPVKit-GPL"])],
    targets: [
        .target(name: "_MPVKit-GPL", dependencies: [''' + names(mpv) + '''],
                path: "Sources/_MPVKit-GPL",
                linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("CoreAudio")]),
        .target(name: "_FFmpeg-GPL", dependencies: [''' + names(ffmpeg) + '''],
                path: "Sources/_FFmpeg-GPL", linkerSettings: [
                ''' + settings + ''']),
''' + binaries + '''
    ]
)
'''


def recipe_input_declarations(text, receipt):
    versions = text.split('var version: String {', 1)[1].split('var url: String {', 1)[0]
    urls = text.split('var url: String {', 1)[1].split('var', 1)[0]
    result = []
    # Parse the pinned simple switch rather than guessing URLs from ZIP names.
    for name, version in re.findall(r'case \.(\w+):[^\n]*\n\s*return "([^"]+)"', versions):
        if name in {'libmpv', 'FFmpeg'}:
            continue
        match = re.search(r'case \.' + re.escape(name) + r':[^\n]*\n\s*return "([^"]+)"', urls)
        if not match:
            raise ValueError(f'cannot identify pinned build input URL: {name}')
        path = f'dist/{name}-{version}/{name}.zip'
        entries = [entry for entry in receipt['prebuiltAuxiliaryInputs'] if entry['relativePath'] == path]
        if len(entries) != 1:
            raise ValueError(f'input identity mismatch: {path}')
        result.append({'relativePath': path, 'recipeURL': match[1].replace(r'\(self.version)', version),
                       'sha256': entries[0]['sha256'], 'sizeBytes': entries[0]['sizeBytes'],
                       'publicationPath': 'inputs/' + path.removeprefix('dist/'),
                       'remoteAuthenticated': False, 'buildOnly': name == 'libluajit'})
    if len(result) != 20:
        raise ValueError('expected twenty exact auxiliary recipe inputs, including build-only LuaJIT')
    return result


def recipe_inputs(checkout, receipt):
    result = recipe_input_declarations((checkout / 'Sources/BuildScripts/XCFrameworkBuild/main.swift').read_text(), receipt)
    for entry in result:
        if identity(checkout / entry['relativePath']) != {key: entry[key] for key in ('sha256', 'sizeBytes')}:
            raise ValueError('retained auxiliary input identity mismatch')
    return result


def git_object(kind, data):
    return hashlib.sha1(kind.encode() + b' ' + str(len(data)).encode() + b'\0' + data).digest()


def archive_tree(archive):
    """Reconstruct Git tree identity from archive bytes without extracting files."""
    root = {}
    with tarfile.open(archive, 'r:gz') as tar:
        for entry in tar:
            path = Path(entry.name)
            if path.is_absolute() or '..' in path.parts or '.git' in path.parts:
                raise ValueError('unsafe committed source archive path')
            if entry.isdir():
                continue
            directory = root
            for part in path.parts[:-1]:
                directory = directory.setdefault(part, {})
                if not isinstance(directory, dict):
                    raise ValueError('source archive directory conflicts with file')
            if path.name in directory:
                raise ValueError('duplicate committed source archive entry')
            if entry.isfile():
                data = tar.extractfile(entry).read()
                mode = b'100755' if entry.mode & 0o111 else b'100644'
            elif entry.issym():
                data, mode = entry.linkname.encode(), b'120000'
            else:
                raise ValueError('unsupported committed source archive entry')
            directory[path.name] = (mode, git_object('blob', data))
    def tree(directory):
        data = b''
        for name, entry in sorted(directory.items(), key=lambda item: (item[0] + ('/' if isinstance(item[1], dict) else '')).encode()):
            mode, digest = (b'40000', tree(entry)) if isinstance(entry, dict) else entry
            data += mode + b' ' + name.encode() + b'\0' + digest
        return git_object('tree', data)
    return tree(root).hex()


def source_archive(directory, revision, destination):
    # git archive fixes entry order/timestamps to the retained commit; gzip has
    # no filename or wall-clock timestamp. These are snapshots, not new commits.
    with tempfile.TemporaryFile() as raw:
        subprocess.run(['git', '-C', str(directory), 'archive', '--format=tar', revision], stdout=raw, check=True)
        raw.seek(0)
        with destination.open('wb') as output, gzip.GzipFile(fileobj=output, mode='wb', filename='', mtime=0) as compressed:
            shutil.copyfileobj(raw, compressed)


def prepare(build, output, base):
    preparer_bytes = Path(__file__).read_bytes()
    preparer_identity = hashlib.sha256(preparer_bytes).hexdigest()
    base = release_base(base)
    if output.exists():
        raise ValueError('output must be a new directory; retained packages are never overwritten')
    if build == output or build in output.parents or output in build.parents:
        raise ValueError('publication output must be separate from retained build')
    receipt = json.loads((build / 'receipt.json').read_text())
    builder = build / 'builder.py'
    if not receipt.get('buildSucceeded') or sha(builder) != receipt['builderSHA256']:
        raise ValueError('completed build/builder identity mismatch')
    spec = importlib.util.spec_from_file_location('retained_builder', builder)
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    verified = verifier.verify_build(build, receipt)
    checkout = build / 'MPVKit'
    retained_targets = binary_targets((checkout / 'Package.swift').read_text())
    if any(name not in retained_targets for name in AUXILIARIES):
        raise ValueError('retained package lacks complete GPL auxiliary targets')
    inputs = recipe_inputs(checkout, receipt)
    output.mkdir(parents=True)
    for directory in ('assets', 'sources', 'provenance', 'package/Sources'):
        (output / directory).mkdir(parents=True)
    (output / 'provenance/preparer.py').write_bytes(preparer_bytes)
    targets = []
    for name in LIBRARIES:
        path = f'dist/release/{name}.xcframework.zip'
        asset = name + '-GPL.xcframework.zip'
        shutil.copyfile(checkout / path, output / 'assets' / asset)
        targets.append({'name': name + '-GPL', 'url': base + '/' + asset,
                        'checksum': receipt['artifacts'][path]['sha256'], 'assetPath': 'assets/' + asset,
                        'originalBuildPath': path, 'remoteAuthenticated': False})
    targets.extend(dict(retained_targets[name], remoteAuthenticated=False) for name in AUXILIARIES)
    for name in ('_MPVKit-GPL', '_FFmpeg-GPL'):
        shutil.copytree(checkout / 'Sources' / name, output / 'package/Sources' / name)
    shutil.copyfile(checkout / 'LICENSE', output / 'package/LICENSE')
    (output / 'package/Package.swift').write_text(package_manifest(targets))
    sources = [{'name': 'MPVKit-recipe', 'directory': checkout,
                'revision': receipt['candidateMPVKitRevision'],
                'tree': capture(['git', '-C', checkout, 'rev-parse', 'HEAD^{tree}']),
                'upstreamURL': 'https://github.com/aagedal/MPVKit', 'upstreamRevision': receipt['upstreamMPVKitRevision']}]
    for name, entry in receipt['sourceInputs'].items():
        sources.append({'name': name, 'directory': checkout / 'dist' / name,
                        'revision': entry['candidateRevision'], 'tree': entry['candidateTree'],
                        'upstreamRevision': entry['upstreamRevision'],
                        'upstreamURL': 'https://github.com/mpv-player/mpv' if name.startswith('libmpv') else 'https://github.com/FFmpeg/FFmpeg'})
    for entry in sources:
        entry['archivePath'] = 'sources/' + entry['name'] + '.tar.gz'
        directory = entry.pop('directory')
        source_archive(directory, entry['revision'], output / entry['archivePath'])
        entry['commitPath'] = 'sources/' + entry['name'] + '.commit'
        (output / entry['commitPath']).write_bytes(subprocess.check_output(['git', '-C', str(directory), 'cat-file', 'commit', entry['revision']]))
    for entry in inputs:
        destination = output / entry['publicationPath']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(checkout / entry['relativePath'], destination)
    for name, source in [('build-receipt.json', build / 'receipt.json'), ('builder.py', builder)]:
        shutil.copyfile(source, output / 'provenance' / name)
    shutil.copyfile(checkout / 'Package.swift', output / 'provenance/retained-package.swift')
    # Record the complete upstream-to-candidate FFmpeg source edit explicitly.
    ffmpeg = receipt['sourceInputs']['FFmpeg-n8.1.2']
    patch = capture(['git', '-C', checkout / 'dist/FFmpeg-n8.1.2', 'diff', ffmpeg['upstreamRevision'], ffmpeg['candidateRevision']])
    (output / 'provenance/ffmpeg-metal-source.patch').write_text(patch + '\n')
    original_patch = Path(receipt['sourceInputs']['libmpv-v0.41.0']['patches'][-1]['path'])
    if sha(original_patch) != receipt['patchSHA256']:
        raise ValueError('attributed original IINA patch identity mismatch')
    shutil.copyfile(original_patch, output / 'provenance/iina-18384-audio-channel.patch')
    metadata = {'schemaVersion': 1, 'status': 'prepared-local-unpublished', 'shippingProduct': 'MPVKit-GPL',
                'platforms': ['macos'], 'minimumMacOS': '12.0', 'architectures': ['arm64', 'x86_64'],
                'releaseBaseURL': base, 'luaEnabled': False, 'binaryTargets': targets, 'sourceSnapshots': sources,
                'auxiliaryBuildInputs': inputs, 'verification': verified, 'blockers': BLOCKERS,
                'buildReceiptSHA256': sha(build / 'receipt.json'),
                'preparerSHA256': preparer_identity,
                'files': {str(file.relative_to(output)): identity(file) for file in sorted(output.rglob('*')) if file.is_file()}}
    (output / 'publication.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
    verify(output)
    return metadata


def publication_manifest(output):
    path = output / 'publication.json'
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('publication file inventory mismatch: nonregular publication.json')
    return path


def verify_publication_inventory(output, files):
    """Reject undeclared directories, redirects and nonregular payloads before reading."""
    expected_files = set(files) | {'publication.json'}
    expected_directories = {Path('.')}
    for name in expected_files:
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or path.as_posix() != name:
            raise ValueError('publication file inventory mismatch: unsafe payload path')
        expected_directories.update(path.parents)
    actual_files, actual_directories = set(), {Path('.')}
    def walk_error(error):
        raise error
    for root, directories, names in os.walk(output, followlinks=False, onerror=walk_error):
        for name in directories:
            path = Path(root) / name
            relative = path.relative_to(output)
            if path.is_symlink():
                raise ValueError('publication file inventory mismatch: directory symlink ' + str(relative))
            actual_directories.add(relative)
        for name in names:
            path = Path(root) / name
            relative = str(path.relative_to(output))
            if not stat.S_ISREG(path.lstat().st_mode):
                if relative in files:
                    raise ValueError('publication payload identity mismatch: nonregular file ' + relative)
                raise ValueError('publication file inventory mismatch: nonregular file ' + relative)
            actual_files.add(relative)
    if actual_files != expected_files or actual_directories != expected_directories:
        raise ValueError('publication file inventory mismatch')


def verify(output):
    metadata = json.loads(publication_manifest(output).read_text())
    if metadata.get('schemaVersion') != 1 or metadata.get('status') != 'prepared-local-unpublished':
        raise ValueError('unexpected publication schema/status')
    if (metadata.get('shippingProduct') != 'MPVKit-GPL' or metadata.get('platforms') != ['macos']
            or metadata.get('architectures') != ['arm64', 'x86_64'] or metadata.get('luaEnabled') is not False
            or metadata.get('minimumMacOS') != '12.0' or metadata.get('blockers') != BLOCKERS):
        raise ValueError('publication shipping policy mismatch')
    release_base(metadata['releaseBaseURL'])
    files = metadata['files']
    verify_publication_inventory(output, files)
    for name, expected in files.items():
        path = output / name
        if path.is_symlink() or output.resolve() not in path.resolve().parents or identity(path) != expected:
            raise ValueError(f'publication payload identity mismatch: {name}')
    receipt_path = output / 'provenance/build-receipt.json'
    if sha(output / 'provenance/preparer.py') != metadata['preparerSHA256']:
        raise ValueError('retained preparer identity mismatch')
    if sha(receipt_path) != metadata['buildReceiptSHA256']:
        raise ValueError('retained build receipt identity mismatch')
    receipt = json.loads(receipt_path.read_text())
    if not receipt.get('buildSucceeded') or receipt.get('shippingProduct') != 'MPVKit-GPL':
        raise ValueError('unqualified build receipt')
    if (metadata['verification'] != receipt['verification']
            or not metadata['verification']['shippingFeatureParity']['passed']):
        raise ValueError('publication build verification differs from retained receipt')
    if sha(output / 'provenance/iina-18384-audio-channel.patch') != receipt['patchSHA256']:
        raise ValueError('attributed original IINA patch identity mismatch')
    if sha(output / 'provenance/builder.py') != receipt['builderSHA256']:
        raise ValueError('retained builder identity mismatch')
    snapshots = metadata['sourceSnapshots']
    if [entry['name'] for entry in snapshots] != ['MPVKit-recipe', 'libmpv-v0.41.0', 'FFmpeg-n8.1.2']:
        raise ValueError('incomplete committed source snapshots')
    if snapshots[0]['revision'] != receipt['candidateMPVKitRevision']:
        raise ValueError('retained recipe revision mismatch')
    for entry in snapshots:
        upstream_revision = (receipt['upstreamMPVKitRevision'] if entry['name'] == 'MPVKit-recipe'
                             else receipt['sourceInputs'][entry['name']]['upstreamRevision'])
        if (entry.get('upstreamRevision') != upstream_revision
                or entry.get('upstreamURL') != SOURCE_ORIGINS[entry['name']]):
            raise ValueError('source upstream provenance mismatch')
        if entry['archivePath'] not in files or entry['commitPath'] not in files:
            raise ValueError('source archive absent from publication inventory')
        commit = (output / entry['commitPath']).read_bytes()
        tree = archive_tree(output / entry['archivePath'])
        if (git_object('commit', commit).hex() != entry['revision'] or tree != entry['tree']
                or commit.splitlines()[0] != b'tree ' + tree.encode()):
            raise ValueError('source archive/commit Git identity mismatch')
    for entry in snapshots[1:]:
        original = receipt['sourceInputs'][entry['name']]
        if entry['revision'] != original['candidateRevision'] or entry['tree'] != original['candidateTree']:
            raise ValueError('retained source revision/tree mismatch')
    targets = metadata['binaryTargets']
    if [target['name'] for target in targets] != [name + '-GPL' for name in LIBRARIES] + list(AUXILIARIES):
        raise ValueError('incomplete or reordered GPL binary targets')
    if any(target.get('remoteAuthenticated') is not False for target in targets):
        raise ValueError('unverified binary target remote authentication claim')
    for target in targets[:8]:
        expected = receipt['artifacts'][target['originalBuildPath']]
        if identity(output / target['assetPath']) != expected or target['checksum'] != expected['sha256']:
            raise ValueError('GPL asset no longer matches immutable build receipt')
        if target['url'] != metadata['releaseBaseURL'] + '/' + Path(target['assetPath']).name:
            raise ValueError('GPL target URL mismatch')
    retained_targets = binary_targets((output / 'provenance/retained-package.swift').read_text())
    if targets[8:] != [dict(retained_targets[name], remoteAuthenticated=False) for name in AUXILIARIES]:
        raise ValueError('auxiliary targets differ from retained recipe declarations')
    if (output / 'package/Package.swift').read_text() != package_manifest(targets):
        raise ValueError('GPL package manifest differs from publication metadata')
    inputs = metadata['auxiliaryBuildInputs']
    if len(inputs) != 20 or len({entry['relativePath'] for entry in inputs}) != 20:
        raise ValueError('incomplete/duplicate auxiliary build inputs')
    with tarfile.open(output / snapshots[0]['archivePath'], 'r:gz') as archive:
        recipe = archive.extractfile('Sources/BuildScripts/XCFrameworkBuild/main.swift').read().decode()
        retained_package = archive.extractfile('Package.swift').read().decode()
        package_files = {'package/Package.swift'}
        for member in archive:
            if member.isfile() and (member.name.startswith(('Sources/_MPVKit-GPL/', 'Sources/_FFmpeg-GPL/')) or member.name == 'LICENSE'):
                path = 'package/' + member.name
                package_files.add(path)
                if (output / path).read_bytes() != archive.extractfile(member).read():
                    raise ValueError('package wrapper/license differs from committed recipe')
        if {path for path in files if path.startswith('package/')} != package_files:
            raise ValueError('package source file inventory differs from committed recipe')
    if (output / 'provenance/retained-package.swift').read_text() != retained_package:
        raise ValueError('retained package differs from committed recipe source')
    if inputs != recipe_input_declarations(recipe, receipt):
        raise ValueError('auxiliary input URLs/identities differ from committed recipe declarations')
    retained_inputs = {entry['relativePath']: {key: entry[key] for key in ('sha256', 'sizeBytes')}
                       for entry in receipt['prebuiltAuxiliaryInputs']}
    for entry in inputs:
        expected = {key: entry[key] for key in ('sha256', 'sizeBytes')}
        if identity(output / entry['publicationPath']) != expected or retained_inputs.get(entry['relativePath']) != expected:
            raise ValueError('auxiliary build input identity mismatch')
    return {'passed': True, 'status': metadata['status'], 'fileCount': len(files),
            'gplArtifactCount': 8, 'auxiliaryTargetCount': len(AUXILIARIES),
            'auxiliaryInputCount': len(metadata['auxiliaryBuildInputs']),
            'publicationSHA256': sha(output / 'publication.json'), 'blockers': metadata['blockers']}


def reconstruction_environment(receipt):
    """Declare only facts retained by the build, with missing identities explicit."""
    return {
        'schemaVersion': 1,
        'scope': 'Offline source/input reconstruction; dependency compilation has not run.',
        'recordedBuild': {key: receipt.get(key) for key in
                          ('compilerVersion', 'xcodeVersion', 'sdkPath', 'mesonVersion', 'ninjaVersion')},
        'recordedMetalToolchain': receipt.get('shippingPrerequisites', {}).get('metalToolchain'),
        'knownRecipeTools': ['git', 'python3', 'swift', 'clang', 'clang++', 'xcodebuild', 'xcrun',
                          'meson', 'ninja', 'pkg-config', 'nasm', 'sdl2-config', 'wget',
                          'make', 'libtool', 'lipo', 'otool', 'zip', 'unzip'],
        'unrecordedOriginalIdentities': [
            'Swift/Python/Git/pkg-config/nasm/SDL2 versions and executable hashes',
            'SDK content and external header identities',
            'Complete inherited environment and configure autodetection inputs',
        ],
        'requiredBeforeCompilation': [
            'Select Xcode/SDK and all required tools explicitly; compare the recorded versions.',
            'Probe and bind installed Metal compiler/linker identities, then record any recipe path relocation.',
            'Review recipe tool installation/network fallbacks and control optional feature autodetection.',
            'Capture environment, tool/header identities, fresh configuration and object receipts.',
            'Verify GPL/Metal/Samba parity and both actual binary architectures after compilation.',
        ],
        'byteIdenticalRebuildDemonstrated': False,
    }


def restore_source(archive_path, commit_path, destination, expected):
    """Restore a snapshot and its exact Git HEAD without fetching missing history."""
    with tarfile.open(archive_path, 'r:gz') as archive:
        members = archive.getmembers()
        # The retained snapshots have no symlinks. Refuse them instead of
        # letting a source path redirect a later extraction or Git operation.
        for member in members:
            path = Path(member.name)
            if (path.is_absolute() or '..' in path.parts or '.git' in path.parts
                    or '\\' in member.name or not (member.isdir() or member.isfile())):
                raise ValueError('unsafe reconstruction source archive entry')
        destination.mkdir(parents=True)
        for member in members:
            target = destination / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open('xb') as file:
                    shutil.copyfileobj(archive.extractfile(member), file)
                target.chmod(0o755 if member.mode & 0o111 else 0o644)
    # Ignore host Git config, attributes, templates, filters and hooks while materializing
    # exact retained tree bytes. There is no fetched parent history.
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_ATTR_NOSYSTEM='1')
    def git(*args, **kwargs):
        return subprocess.check_output(['git', '-C', str(destination), *args], env=env, **kwargs).decode().strip()
    git('init', '--quiet', '--template=')
    git('config', 'core.autocrlf', 'false')
    git('config', 'core.filemode', 'true')
    # Global/XDG attributes are loaded independently of Git config files.
    # Keep this override in the reconstructed repository for later inspection.
    git('config', 'core.attributesFile', os.devnull)
    git('add', '--force', '--all')
    if git('write-tree') != expected['tree']:
        raise ValueError('reconstructed source Git tree mismatch')
    revision = git('hash-object', '-w', '-t', 'commit', '--stdin', input=commit_path.read_bytes())
    if revision != expected['revision']:
        raise ValueError('reconstructed source Git commit mismatch')
    git('update-ref', 'HEAD', revision)
    # Mark a genuine shallow boundary so commands do not traverse absent
    # upstream parents; no replacement commit or invented history is created.
    if any(line.startswith(b'parent ') for line in commit_path.read_bytes().splitlines()):
        (destination / '.git/shallow').write_text(revision + '\n')
    if git('status', '--porcelain'):
        raise ValueError('reconstructed source unexpectedly modified')


def reconstruction_build_plan(output):
    """Declare a workspace-specific command and caches without running tools."""
    checkout = output / 'MPVKit'
    command = ['swift', 'run', '--disable-sandbox']
    for option, directory in [('build-path', 'swift-build'), ('cache-path', 'swift-package-cache'),
                              ('config-path', 'swift-package-config'), ('security-path', 'swift-package-security')]:
        command += ['--' + option, str(output / directory)]
    command += ['--package-path', str(checkout / 'Sources/BuildScripts'), '-Xswiftc', '-module-cache-path',
                '-Xswiftc', str(output / 'swift-cache'), 'build', 'enable-gpl', 'platform=macos',
                'version=local-coreaudio-gpl-candidate']
    return {'candidateBuildCommand': command, 'buildWorkingDirectory': str(checkout),
            'isolatedEnvironmentPaths': {key: str(output / directory) for key, directory in
                                        [('CLANG_MODULE_CACHE_PATH', 'clang-cache'),
                                         ('SWIFT_MODULECACHE_PATH', 'swift-cache'), ('TMPDIR', 'temporary')]}}


def reconstruct(stage, output, expected_publication_sha256):
    """Materialize exact retained sources and inputs; never invoke the recipe."""
    if not re.fullmatch(r'[a-f0-9]{64}', expected_publication_sha256):
        raise ValueError('expected publication SHA-256 must be an externally retained lowercase digest')
    if sha(publication_manifest(stage)) != expected_publication_sha256:
        raise ValueError('publication does not match externally retained SHA-256')
    if output.exists():
        raise ValueError('reconstruction output must be new; retained workspaces are never overwritten')
    if stage == output or stage in output.parents or output in stage.parents:
        raise ValueError('reconstruction output must be separate from publication stage')
    driver_bytes = Path(__file__).read_bytes()
    verified = verify(stage)
    metadata = json.loads((stage / 'publication.json').read_text())
    receipt = json.loads((stage / 'provenance/build-receipt.json').read_text())
    output.mkdir(parents=True)
    (output / 'reconstruction-driver.py').write_bytes(driver_bytes)
    for directory in ('clang-cache', 'swift-cache', 'temporary'):
        (output / directory).mkdir()
    checkout = output / 'MPVKit'
    for snapshot in metadata['sourceSnapshots']:
        destination = checkout if snapshot['name'] == 'MPVKit-recipe' else checkout / 'dist' / snapshot['name']
        restore_source(stage / snapshot['archivePath'], stage / snapshot['commitPath'], destination, snapshot)
    input_receipts = []
    for entry in metadata['auxiliaryBuildInputs']:
        destination = checkout / entry['relativePath']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(stage / entry['publicationPath'], destination)
        if identity(destination) != {key: entry[key] for key in ('sha256', 'sizeBytes')}:
            raise ValueError('reconstructed auxiliary input identity mismatch')
        # Retain ZIPs exactly as the original recipe expects. Its ZipBaseBuild
        # extracts them; source reconstruction does not execute that recipe.
        input_receipts.append({'relativePath': entry['relativePath'], **identity(destination)})
    result = {'schemaVersion': 1, 'status': 'reconstructed-inputs-not-built',
              'publicationSHA256': verified['publicationSHA256'],
              'reconstructionDriverSHA256': sha(output / 'reconstruction-driver.py'),
              'sourceSnapshots': metadata['sourceSnapshots'], 'auxiliaryBuildInputs': input_receipts,
              **reconstruction_build_plan(output),
              'environmentDeclaration': reconstruction_environment(receipt),
              'sourceHistory': 'Exact retained commits/trees, with shallow boundaries; upstream parent history is not included.',
              'recipePathRelocations': [], 'buildExecuted': False, 'blockers': metadata['blockers']}
    (output / 'reconstruction.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path, nargs='?')
    parser.add_argument('output', type=Path, nargs='?')
    parser.add_argument('--release-base-url')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--verify', type=Path)
    modes.add_argument('--reconstruct', type=Path, help='verified stage to restore offline into a new workspace; does not compile')
    parser.add_argument('--reconstruction-output', type=Path)
    parser.add_argument('--expected-publication-sha256', help='publication manifest digest retained outside the stage')
    args = parser.parse_args()
    try:
        if args.reconstruct:
            if args.build or args.output or args.release_base_url or not args.reconstruction_output or not args.expected_publication_sha256:
                parser.error('--reconstruct requires --reconstruction-output and --expected-publication-sha256 only')
            result = reconstruct(args.reconstruct.resolve(), args.reconstruction_output.resolve(), args.expected_publication_sha256)
        elif args.verify:
            if args.build or args.output or args.release_base_url or args.reconstruction_output or args.expected_publication_sha256:
                parser.error('--verify cannot be combined with preparation inputs')
            result = verify(args.verify.resolve())
        else:
            if args.reconstruction_output or args.expected_publication_sha256:
                parser.error('reconstruction options require --reconstruct')
            if not args.build or not args.output or not args.release_base_url:
                parser.error('build, output and --release-base-url are required')
            prepare(args.build.resolve(), args.output.resolve(), args.release_base_url)
            result = verify(args.output.resolve())
        print(json.dumps(result, indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f'Publication preparation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
