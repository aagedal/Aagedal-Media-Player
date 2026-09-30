#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build every macOS mpv/FFmpeg object in a fresh isolated MPVKit checkout.

The upstream recipe uses prebuilt auxiliary dependencies, preserved here as
hash-identified ZIP inputs. This produces a local candidate, not a published
release or an app package repin. The original checkout is never built or patched.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/evidence/live-meter-native-output-20260930/isolated-coreaudio-probe'
IDENTITY = EVIDENCE / 'source-identities.json'
PATCH = EVIDENCE / 'iina-18384-audio-channel.patch'
MPVKIT_REVISION = '230c3174f1515898f24599147ad61c2a277d0dc2'
FFMPEG_REVISION = '38b88335f99e76ed89ff3c93f877fdefce736c13'


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def capture(args, **kwargs):
    return run(args, stdout=subprocess.PIPE, **kwargs).stdout.decode().strip()


def git(directory, *args):
    return capture(['git', '-C', directory, *args])


def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise ValueError(f'expected one pinned recipe fragment in {path.name}')
    path.write_text(text.replace(before, after))


def clone_clean(source, destination, revision):
    if git(source, 'rev-parse', 'HEAD') != revision:
        raise ValueError(f'cached source revision mismatch: {source}')
    run(['git', 'clone', '--no-hardlinks', '--no-checkout', source, destination])
    run(['git', '-C', destination, 'checkout', '--detach', revision])
    if git(destination, 'status', '--porcelain'):
        raise ValueError(f'clean clone unexpectedly modified: {destination}')


def commit(directory, message):
    run(['git', '-C', directory, 'add', '.'])
    run(['git', '-C', directory, '-c', 'user.name=Local dependency candidate',
         '-c', 'user.email=dependency-candidate@localhost', 'commit', '-m', message])
    return git(directory, 'rev-parse', 'HEAD')


def unpack_zip(archive, destination):
    # Cached release ZIPs are inputs, not instructions. Reject paths which can
    # escape the isolated destination and reject symlinks before extraction.
    with zipfile.ZipFile(archive) as file:
        for entry in file.infolist():
            path = Path(entry.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
                raise ValueError(f'unsafe cached ZIP path: {entry.filename}')
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f'cached ZIP symlink requires review: {entry.filename}')
        file.extractall(destination)


def verify_build(output, receipt):
    """Verify immutable source, reconstructed inputs and actual output slices."""
    checkout = output / 'MPVKit'
    result = {'sourceInputs': {}, 'copiedAuxiliaryZIPsMatch': True, 'xcframeworks': {}, 'freshObjects': {}}
    if git(checkout, 'rev-parse', 'HEAD') != receipt['candidateMPVKitRevision']:
        raise ValueError('candidate MPVKit recipe revision changed during build')
    if git(checkout, 'status', '--porcelain'):
        raise ValueError('candidate MPVKit recipe changed during build')
    for name, source in receipt['sourceInputs'].items():
        directory = checkout / 'dist' / name
        current = {'revision': git(directory, 'rev-parse', 'HEAD'),
                   'tree': git(directory, 'rev-parse', 'HEAD^{tree}'),
                   'status': git(directory, 'status', '--porcelain')}
        if current['revision'] != source['candidateRevision'] or current['tree'] != source['candidateTree'] or current['status']:
            raise ValueError(f'candidate source changed during build: {name}')
        result['sourceInputs'][name] = current
    for entry in receipt['prebuiltAuxiliaryInputs']:
        copied = checkout / entry['relativePath']
        if sha(copied) != entry['sha256'] or sha(entry['path']) != entry['sha256']:
            raise ValueError(f'copied/original auxiliary ZIP mismatch: {entry["relativePath"]}')
    names = ['Libmpv', 'Libavcodec', 'Libavdevice', 'Libavfilter', 'Libavformat',
             'Libavutil', 'Libswresample', 'Libswscale']
    for name in names:
        archive = checkout / 'dist/release' / (name + '.xcframework.zip')
        # The upstream builder removes earlier expanded XCFrameworks while
        # packaging the next library. Verify the retained shipping ZIP itself.
        with zipfile.ZipFile(archive) as file:
            info = plistlib.loads(file.read(name + '.xcframework/Info.plist'))
            slices = info['AvailableLibraries']
            if len(slices) != 1 or slices[0]['SupportedPlatform'] != 'macos' or set(slices[0]['SupportedArchitectures']) != {'arm64', 'x86_64'}:
                raise ValueError(f'expected universal macOS XCFramework: {name}')
            binary_path = '/'.join([name + '.xcframework', slices[0]['LibraryIdentifier'],
                                    slices[0]['LibraryPath'], 'Versions/A', name])
            payload = file.read(binary_path)
        slices = info['AvailableLibraries']
        with tempfile.TemporaryDirectory(dir=output) as temporary:
            binary = Path(temporary) / name
            binary.write_bytes(payload)
            archs = capture(['/usr/bin/lipo', '-archs', binary]).split()
        if set(archs) != {'arm64', 'x86_64'}:
            raise ValueError(f'actual framework architecture mismatch: {name}')
        checksum = (checkout / 'dist/release' / (name + '.xcframework.checksum.txt')).read_text().strip()
        if sha(archive) != checksum:
            raise ValueError(f'SwiftPM archive checksum mismatch: {name}')
        result['xcframeworks'][name] = {'architectures': archs, 'binarySHA256': hashlib.sha256(payload).hexdigest(),
                                       'zipSHA256': checksum, 'libraryIdentifier': slices[0]['LibraryIdentifier']}
    for library in ['libmpv', 'FFmpeg']:
        result['freshObjects'][library] = {}
        for arch in ['arm64', 'x86_64']:
            scratch = checkout / 'dist' / library / 'macos/scratch' / arch
            objects = sorted(scratch.rglob('*.o'))
            if not objects:
                raise ValueError(f'no fresh objects for {library}/{arch}')
            manifest = [str(obj.relative_to(scratch)) + '\0' + sha(obj) for obj in objects]
            archives = sorted((checkout / 'dist' / library / 'macos/thin' / arch / 'lib').glob('*.a'))
            result['freshObjects'][library][arch] = {
                'objectCount': len(objects),
                'objectManifestSHA256': hashlib.sha256('\n'.join(manifest).encode()).hexdigest(),
                'staticArchives': {str(archive.relative_to(checkout)): sha(archive) for archive in archives},
            }
            if library == 'libmpv':
                database = scratch / 'compile_commands.json'
                entries = json.loads(database.read_text())
                result['freshObjects'][library][arch]['compileDatabaseSHA256'] = sha(database)
                patched_objects = {}
                for file in ['ao_coreaudio.c', 'ao_coreaudio_chmap.c']:
                    matches = [entry for entry in entries if Path(entry['file']).name == file]
                    if len(matches) != 1:
                        raise ValueError(f'missing fresh CoreAudio command: {arch}/{file}')
                    entry = matches[0]
                    source = (Path(entry['directory']) / entry['file']).resolve()
                    if source != (checkout / 'dist/libmpv-v0.41.0/audio/out' / file).resolve():
                        raise ValueError('CoreAudio compile command used a different source tree')
                    patched_objects[file] = {'objectSHA256': sha(scratch / entry['output']), 'sourceSHA256': sha(source)}
                result['freshObjects'][library][arch]['coreaudioObjects'] = patched_objects
    return result


def build(mpvkit, output):
    if output.exists():
        raise ValueError(f'output already exists: {output}')
    if mpvkit == output or mpvkit in output.parents:
        raise ValueError('output must be outside the input checkout')
    identity = json.loads(IDENTITY.read_text())
    if sha(PATCH) != identity['iinaPatchSHA256']:
        raise ValueError('retained CoreAudio patch hash mismatch')
    original_status = git(mpvkit, 'status', '--porcelain')
    output.mkdir(parents=True)
    shutil.copy2(Path(__file__), output / 'builder.py')
    checkout = output / 'MPVKit'
    clone_clean(mpvkit, checkout, MPVKIT_REVISION)
    dist = checkout / 'dist'
    dist.mkdir()
    receipt = {
        'scope': 'clean macOS mpv/FFmpeg build with upstream prebuilt auxiliary dependencies; local unpublished candidate',
        'upstreamMPVKitRevision': MPVKIT_REVISION,
        'patchSHA256': sha(PATCH),
        'patchURL': identity['iinaPatchURL'],
        'prebuiltAuxiliaryInputs': [],
        'sourceInputs': {},
        'architectures': ['arm64', 'x86_64'],
        'limitations': ['Auxiliary third-party dependencies use the upstream prebuilt ZIP recipe.',
                        'Local checksum identities do not authenticate auxiliary ZIPs against remote release provenance.',
                        'No remote artifact publication or shipping app package repin.',
                        'No audible-output, device-switch, surround, supported-macOS or release-floor acceptance.'],
    }
    # Only versioned release inputs are copied. No scratch, thin, object archive,
    # generated header, cached build database or existing framework is reused.
    for archive in sorted((mpvkit / 'dist').glob('*-*/*.zip')):
        destination = dist / archive.parent.name
        destination.mkdir(exist_ok=True)
        copied = destination / archive.name
        shutil.copy2(archive, copied)
        unpack_zip(copied, destination)
        receipt['prebuiltAuxiliaryInputs'].append({
            'path': str(archive), 'relativePath': str(archive.relative_to(mpvkit)),
            'sha256': sha(archive), 'sizeBytes': archive.stat().st_size,
        })
    for name, revision in [('libmpv-v0.41.0', identity['mpvSourceRevision']),
                           ('FFmpeg-n8.1.2', FFMPEG_REVISION)]:
        source = mpvkit / 'dist' / name
        destination = dist / name
        clone_clean(source, destination, revision)
        patches = checkout / 'Sources/BuildScripts/patch' / name.split('-')[0]
        applied = []
        if patches.exists():
            for patch in sorted(patches.glob('*.patch')):
                run(['git', '-C', destination, 'apply', '--check', patch])
                run(['git', '-C', destination, 'apply', patch])
                applied.append({'path': str(patch.relative_to(checkout)), 'sha256': sha(patch)})
        if name.startswith('libmpv'):
            # The pinned recipe's newer tvOS guard patch changes header context
            # absent from the old build cache. Preserve those platform guards
            # and port only the repair's declarations into the guarded header.
            changed = ['ao_coreaudio.c', 'ao_coreaudio_chmap.c', 'ao_coreaudio_chmap.h']
            before = {file: (destination / 'audio/out' / file).read_text() for file in changed}
            run(['git', '-C', destination, 'apply', '--exclude=audio/out/ao_coreaudio_chmap.h', '--check', PATCH])
            run(['git', '-C', destination, 'apply', '--exclude=audio/out/ao_coreaudio_chmap.h', PATCH])
            header = destination / 'audio/out/ao_coreaudio_chmap.h'
            replace_once(header, 'struct mp_chmap;', 'struct ao;\nstruct mp_chmap;')
            replace_once(header, '                         struct mp_chmap *out_map);',
                         '                         struct mp_chmap *out_map);\n'
                         'bool ca_get_output_chmap(struct ao *ao, AudioUnit unit, AudioDeviceID device,\n'
                         '                        struct mp_chmap *out_map);\n'
                         'bool ca_select_channel_map(struct mp_chmap *input, const struct mp_chmap *output,\n'
                         '                           SInt32 *map);')
            adapted_patch = checkout / 'Sources/BuildScripts/patch/libmpv/0004-coreaudio-typed-device-map.patch'
            adapted_patch.write_text(''.join(''.join(difflib.unified_diff(
                before[file].splitlines(keepends=True), (destination / 'audio/out' / file).read_text().splitlines(keepends=True),
                fromfile='a/audio/out/' + file, tofile='b/audio/out/' + file)) for file in changed))
            applied.append({'path': str(PATCH), 'sha256': sha(PATCH),
                            'headerAdaptation': 'Preserve pinned tvOS TargetConditionals guards around device HAL declarations.',
                            'appliedPatchSHA256': sha(adapted_patch)})
        else:
            # Record upstream BuildFFMPEG.beforeBuild's one source adjustment in
            # the immutable source commit, then skip its second application.
            video = destination / 'libavcodec/videotoolbox.c'
            lines = video.read_text().split('\n')
            index = next(i for i, line in enumerate(lines)
                         if 'kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey' in line)
            lines.insert(index + 2, '    CFDictionarySetValue(buffer_attributes, kCVPixelBufferMetalCompatibilityKey, kCFBooleanTrue);')
            video.write_text('\n'.join(lines))
        candidate_revision = commit(destination, 'Apply pinned MPVKit source changes and CoreAudio repair candidate')
        receipt['sourceInputs'][name] = {
            'upstreamRevision': revision, 'upstreamTree': git(source, 'rev-parse', revision + '^{tree}'),
            'candidateRevision': candidate_revision, 'candidateTree': git(destination, 'rev-parse', 'HEAD^{tree}'),
            'patches': applied,
        }
    base = checkout / 'Sources/BuildScripts/XCFrameworkBuild/base.swift'
    main = checkout / 'Sources/BuildScripts/XCFrameworkBuild/main.swift'
    replace_once(base, '    func generatePackageManagerFile() throws {',
                 '    func generatePackageManagerFile() throws {\n        if self is ZipBaseBuild { return } // Local offline candidate: omit remote auxiliary manifest generation.')
    replace_once(base, '        task.environment = environment',
                 '        for key in ["CLANG_MODULE_CACHE_PATH", "SWIFT_MODULECACHE_PATH", "TMPDIR"] {\n            if let value = ProcessInfo.processInfo.environment[key] { environment[key] = value }\n        }\n        task.environment = environment')
    # The source change above is identical to this upstream transformation.
    start = main.read_text().index('        let path = directoryURL + "libavcodec/videotoolbox.c"')
    end = main.read_text().index('\n    override func flagsDependencelibrarys()', start)
    text = main.read_text()
    main.write_text(text[:start] + '        // Source transformation recorded in immutable FFmpeg candidate commit.\n    }\n' + text[end:])
    receipt['recipeAdaptations'] = [
        'Skip network-only Swift package manifest entries for auxiliary ZIPs; their local payload identities are retained in this receipt.',
        'Pass isolated Clang/Swift module cache and temporary directory locations into spawned build processes.',
        'Apply upstream FFmpeg Metal pixel-buffer source change once before committing candidate source.',
    ]
    (checkout / 'local-candidate-inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')
    receipt['candidateMPVKitRevision'] = commit(checkout, 'Record isolated macOS CoreAudio candidate build recipe and immutable inputs')
    receipt['compilerVersion'] = capture(['/usr/bin/clang', '--version'])
    receipt['xcodeVersion'] = capture(['xcodebuild', '-version'])
    receipt['sdkPath'] = capture(['xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    receipt['mesonVersion'] = capture(['meson', '--version'])
    receipt['ninjaVersion'] = capture(['ninja', '--version'])
    receipt['builderSHA256'] = sha(Path(__file__))
    (output / 'input-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    env = os.environ.copy()
    env['CLANG_MODULE_CACHE_PATH'] = str(output / 'clang-cache')
    env['SWIFT_MODULECACHE_PATH'] = str(output / 'swift-cache')
    (output / 'temporary').mkdir()
    env['TMPDIR'] = str(output / 'temporary')
    command = ['swift', 'run', '--disable-sandbox', '--build-path', output / 'swift-build', '--cache-path', output / 'swift-package-cache',
               '--config-path', output / 'swift-package-config', '--security-path', output / 'swift-package-security',
               '--package-path', checkout / 'Sources/BuildScripts', '-Xswiftc', '-module-cache-path',
               '-Xswiftc', output / 'swift-cache', 'build', 'platform=macos', 'version=local-coreaudio-candidate']
    receipt['buildCommand'] = [str(arg) for arg in command]
    print(f'Fresh build log: {output / "build.log"}', flush=True)
    with (output / 'build.log').open('wb') as log:
        run(command, cwd=checkout, env=env, stdout=log, stderr=subprocess.STDOUT)
    receipt['artifacts'] = {str(file.relative_to(checkout)): {'sha256': sha(file), 'sizeBytes': file.stat().st_size}
                            for file in sorted((dist / 'release').glob('*.zip'))}
    if 'dist/release/Libmpv.xcframework.zip' not in receipt['artifacts']:
        raise ValueError('full build did not produce the libmpv XCFramework ZIP')
    receipt['verification'] = verify_build(output, receipt)
    for entry in receipt['prebuiltAuxiliaryInputs']:
        if sha(entry['path']) != entry['sha256']:
            raise ValueError('original auxiliary input changed during build')
    if git(mpvkit, 'status', '--porcelain') != original_status or git(mpvkit, 'rev-parse', 'HEAD') != MPVKIT_REVISION:
        raise ValueError('original MPVKit checkout changed during isolated build')
    receipt['originalCheckoutUnchanged'] = True
    receipt['buildSucceeded'] = True
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Fresh local dependency candidate: {output}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mpvkit', type=Path, nargs='?')
    parser.add_argument('output', type=Path, nargs='?', help='new directory outside the original checkout')
    parser.add_argument('--verify', type=Path, help='verify a completed build; writes a separate verification.json')
    args = parser.parse_args()
    try:
        if args.verify:
            if args.mpvkit or args.output:
                parser.error('--verify cannot be combined with build inputs')
            output = args.verify.resolve()
            receipt = json.loads((output / 'receipt.json').read_text())
            if not receipt.get('buildSucceeded') or sha(output / 'builder.py') != receipt['builderSHA256']:
                raise ValueError('completed build receipt/builder identity mismatch')
            result = verify_build(output, receipt)
            result['verifierSHA256'] = sha(Path(__file__))
            result['actualBuilderSnapshotSHA256'] = receipt['builderSHA256']
            (output / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
            print(f'Verified complete local candidate: {output}')
        else:
            if not args.mpvkit or not args.output:
                parser.error('provide the input MPVKit checkout and new output directory')
            build(args.mpvkit.resolve(), args.output.resolve())
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'Clean candidate build failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
