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
import re
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
SHIPPING_PRODUCT = 'MPVKit-GPL'
SMB_ZIP = 'dist/libsmbclient-4.15.13-2512/libsmbclient.zip'
SHIPPING_FLAGS = {
    'libmpv/config.h': dict.fromkeys([
        'HAVE_GPL', 'HAVE_COREAUDIO', 'HAVE_AVFOUNDATION', 'HAVE_COCOA',
        'HAVE_FFMPEG', 'HAVE_GL', 'HAVE_GL_COCOA', 'HAVE_LIBASS', 'HAVE_LIBBLURAY',
        'HAVE_MOLTENVK', 'HAVE_SWIFT', 'HAVE_VIDEOTOOLBOX_GL', 'HAVE_VIDEOTOOLBOX_PL', 'HAVE_VULKAN'], 1) | {'HAVE_LUA': 0},
    'FFmpeg/config.h': dict.fromkeys([
        'CONFIG_GPL', 'CONFIG_GPLV3', 'CONFIG_LIBSMBCLIENT', 'CONFIG_METAL',
        'CONFIG_LIBASS', 'CONFIG_LIBDAV1D', 'CONFIG_LIBPLACEBO', 'CONFIG_LIBUAVS3D',
        'CONFIG_VIDEOTOOLBOX', 'CONFIG_VULKAN'], 1) | {'CONFIG_LGPLV3': 0},
    'FFmpeg/config_components.h': dict.fromkeys([
        'CONFIG_LIBSMBCLIENT_PROTOCOL', 'CONFIG_DELOGO_FILTER', 'CONFIG_PAN_FILTER',
        'CONFIG_ARESAMPLE_FILTER', 'CONFIG_ASS_FILTER', 'CONFIG_SUBTITLES_FILTER',
        'CONFIG_LIBPLACEBO_FILTER', 'CONFIG_LIBDAV1D_DECODER', 'CONFIG_LIBUAVS3D_DECODER',
        'CONFIG_ADPCM_CIRCUS_DECODER', 'CONFIG_ADPCM_IMA_ESCAPE_DECODER',
        'CONFIG_ADPCM_IMA_HVQM2_DECODER', 'CONFIG_ADPCM_IMA_HVQM4_DECODER',
        'CONFIG_ADPCM_IMA_MAGIX_DECODER', 'CONFIG_ADPCM_IMA_PDA_DECODER',
        'CONFIG_ADPCM_N64_DECODER', 'CONFIG_ADPCM_PSXC_DECODER',
        'CONFIG_AHX_PARSER', 'CONFIG_AHX_TO_MP2_BSF'], 1),
}


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


def metal_toolchain_prerequisite(toolchain):
    """Validate an explicitly selected installed compiler with a real kernel/link."""
    toolchain = toolchain.resolve()
    tools = {name: toolchain / 'usr/bin' / name for name in ('metal', 'metallib')}
    for name, path in tools.items():
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError(f'explicit Metal toolchain has no executable {name}: {path}')
    for path in tools.values():
        if not re.fullmatch(r'/[A-Za-z0-9_./+\-]+', str(path)):
            raise ValueError(f'Metal executable path cannot be represented by FFmpeg configure: {path}')
    identities = {name: {'path': str(path), 'sha256': sha(path)} for name, path in tools.items()}
    version = capture([tools['metal'], '-v'], stderr=subprocess.STDOUT)
    for name in tools:
        payload = toolchain / 'usr/metal/current/bin' / name
        if payload.is_file():
            identities[name]['implementation'] = {'entryPath': str(payload), 'path': str(payload.resolve()), 'sha256': sha(payload)}
    with tempfile.TemporaryDirectory(prefix='aagedal-metal-probe-') as temporary:
        root = Path(temporary)
        source = root / 'probe.metal'
        source.write_text('#include <metal_stdlib>\nusing namespace metal;\n'
                          'kernel void probe(device float *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = 0.0f; }\n')
        air = root / 'probe.air'
        library = root / 'probe.metallib'
        run([tools['metal'], '-c', source, '-o', air], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        run([tools['metallib'], air, '-o', library], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if not air.is_file() or not library.is_file() or not air.stat().st_size or not library.stat().st_size:
            raise ValueError('explicit Metal toolchain did not produce compiled AIR and linked metallib')
        artifacts = {'airSHA256': sha(air), 'metallibSHA256': sha(library)}
    return {'root': str(toolchain), 'tools': identities, 'version': version, 'kernelProbe': artifacts}


def apply_metal_toolchain_recipe(main, identity):
    # FFmpeg expands these command values without an eval, so embedded shell
    # quotes cannot preserve spaces. Require one unambiguous executable word.
    for name in ('metal', 'metallib'):
        path = identity['tools'][name]['path']
        if not re.fullmatch(r'/[A-Za-z0-9_./+\-]+', path):
            raise ValueError(f'Metal executable path cannot be represented by FFmpeg configure: {path}')
    options = [f'--{option}={identity["tools"][name]["path"]}'
               for option, name in [('metalcc', 'metal'), ('metallib', 'metallib')]]
    fragment = '        var arguments = ffmpegConfiguers'
    replacement = fragment + ''.join('\n        arguments.append(' + json.dumps(option) + ')' for option in options)
    replace_once(main, fragment, replacement)


def verify_metal_toolchain(identity):
    for name, tool in identity['tools'].items():
        path = Path(tool['path'])
        if not path.is_file() or sha(path) != tool['sha256']:
            raise ValueError(f'explicit Metal toolchain changed: {name}')
        implementation = tool.get('implementation')
        if implementation and (Path(implementation.get('entryPath', implementation['path'])).resolve() != Path(implementation['path'])
                               or not Path(implementation['path']).is_file() or sha(implementation['path']) != implementation['sha256']):
            raise ValueError(f'explicit Metal implementation changed: {name}')


def shipping_prerequisites(mpvkit, metal_toolchain=None):
    """Refuse known feature loss before allocating/building a new candidate."""
    archive = mpvkit / SMB_ZIP
    if not archive.is_file():
        raise ValueError(f'{SHIPPING_PRODUCT} requires pinned cached Samba input: {archive}')
    with zipfile.ZipFile(archive) as file:
        for arch in ('arm64', 'x86_64'):
            prefix = f'lib/macos/thin/{arch}/lib/'
            if not any(name.startswith(prefix) and name.endswith('.a') for name in file.namelist()):
                raise ValueError(f'{SHIPPING_PRODUCT} Samba input lacks macOS/{arch} static libraries')
    if metal_toolchain is not None:
        return {'sambaZIP': {'relativePath': SMB_ZIP, 'sha256': sha(archive)},
                'metalToolchain': metal_toolchain_prerequisite(metal_toolchain)}
    probe = subprocess.run(['xcrun', '--sdk', 'macosx', 'metal', '-v'],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    if probe.returncode:
        raise ValueError(f'{SHIPPING_PRODUCT} requires a working Metal compiler to preserve CONFIG_METAL=1. '
                         f'Native prerequisite command xcrun --sdk macosx metal -v failed:\n{probe.stdout.strip()}')
    return {'sambaZIP': {'relativePath': SMB_ZIP, 'sha256': sha(archive)},
            'metalCompilerProbe': {'command': ['xcrun', '--sdk', 'macosx', 'metal', '-v'],
                                   'output': probe.stdout.strip(), 'exitCode': probe.returncode}}


def shipping_configuration(output, require_shipping):
    result = {'product': SHIPPING_PRODUCT, 'architectures': {}, 'mismatches': []}
    for arch in ('arm64', 'x86_64'):
        actual = {}
        for identity, expected in SHIPPING_FLAGS.items():
            library, header = identity.split('/')
            path = output / 'MPVKit/dist' / library / 'macos/scratch' / arch / header
            macros = {key: int(value) for key, value in re.findall(
                r'^#define ((?:HAVE|CONFIG)_[A-Z0-9_]+) ([01])$', path.read_text(), re.MULTILINE)}
            relevant = {key: macros.get(key) for key in expected}
            actual[identity] = {'headerSHA256': sha(path), 'requiredFeatures': relevant,
                               'booleanConfigurationSHA256': hashlib.sha256(
                                   json.dumps(macros, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
            for key, value in expected.items():
                if relevant[key] != value:
                    result['mismatches'].append({'architecture': arch, 'header': identity,
                                                 'feature': key, 'expected': value, 'actual': relevant[key]})
        result['architectures'][arch] = actual
    result['passed'] = not result['mismatches']
    if require_shipping and not result['passed']:
        details = ', '.join(f'{item["architecture"]}/{item["feature"]}={item["actual"]}, expected {item["expected"]}'
                            for item in result['mismatches'])
        raise ValueError(f'{SHIPPING_PRODUCT} feature parity failed: {details}')
    return result


def verify_build(output, receipt, require_shipping=True):
    """Verify immutable source, reconstructed inputs and actual output slices."""
    checkout = output / 'MPVKit'
    metal_identity = receipt.get('shippingPrerequisites', {}).get('metalToolchain')
    if metal_identity:
        verify_metal_toolchain(metal_identity)
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
    recorded_artifacts = receipt.get('artifacts')
    if not recorded_artifacts:
        raise ValueError('build receipt has no immutable artifact identities')
    for name, identity in recorded_artifacts.items():
        archive = (checkout / name).resolve()
        if checkout.resolve() not in archive.parents:
            raise ValueError('recorded artifact path escapes candidate checkout')
        if not archive.is_file() or archive.stat().st_size != identity['sizeBytes'] or sha(archive) != identity['sha256']:
            raise ValueError(f'artifact differs from immutable build receipt: {name}')
    names = ['Libmpv', 'Libavcodec', 'Libavdevice', 'Libavfilter', 'Libavformat',
             'Libavutil', 'Libswresample', 'Libswscale']
    for name in names:
        archive = checkout / 'dist/release' / (name + '.xcframework.zip')
        if str(archive.relative_to(checkout)) not in recorded_artifacts:
            raise ValueError(f'missing immutable artifact receipt identity: {name}')
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
    result['shippingFeatureParity'] = shipping_configuration(output, require_shipping)
    recorded_verification = receipt.get('verification', {})
    for identity in ('xcframeworks', 'freshObjects'):
        if identity in recorded_verification and result[identity] != recorded_verification[identity]:
            raise ValueError(f'candidate {identity} differ from recorded build verification')
    recorded_features = recorded_verification.get('shippingFeatureParity', {}).get('architectures')
    if recorded_features is not None and result['shippingFeatureParity']['architectures'] != recorded_features:
        raise ValueError('candidate configuration differs from recorded build verification')
    return result


def snapshot_builder(source, destination):
    identity = sha(source)
    shutil.copy2(source, destination)
    if sha(destination) != identity:
        raise ValueError('builder source changed while retaining its snapshot')
    return identity


def build(mpvkit, output, metal_toolchain=None):
    if output.exists():
        raise ValueError(f'output already exists: {output}')
    if mpvkit == output or mpvkit in output.parents:
        raise ValueError('output must be outside the input checkout')
    identity = json.loads(IDENTITY.read_text())
    if sha(PATCH) != identity['iinaPatchSHA256']:
        raise ValueError('retained CoreAudio patch hash mismatch')
    prerequisites = shipping_prerequisites(mpvkit, metal_toolchain)
    original_status = git(mpvkit, 'status', '--porcelain')
    output.mkdir(parents=True)
    builder_identity = snapshot_builder(Path(__file__), output / 'builder.py')
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
        'shippingProduct': SHIPPING_PRODUCT,
        'enableGPL': True,
        'shippingPrerequisites': prerequisites,
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
    if 'metalToolchain' in prerequisites:
        apply_metal_toolchain_recipe(main, prerequisites['metalToolchain'])
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
    if 'metalToolchain' in prerequisites:
        receipt['recipeAdaptations'].append('Use explicit verified Metal compiler/linker paths through FFmpeg configure, preserving CONFIG_METAL on both slices.')
    (checkout / 'local-candidate-inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')
    receipt['candidateMPVKitRevision'] = commit(checkout, 'Record isolated macOS CoreAudio candidate build recipe and immutable inputs')
    receipt['compilerVersion'] = capture(['/usr/bin/clang', '--version'])
    receipt['xcodeVersion'] = capture(['xcodebuild', '-version'])
    receipt['sdkPath'] = capture(['xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    receipt['mesonVersion'] = capture(['meson', '--version'])
    receipt['ninjaVersion'] = capture(['ninja', '--version'])
    receipt['builderSHA256'] = builder_identity
    (output / 'input-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    env = os.environ.copy()
    env['CLANG_MODULE_CACHE_PATH'] = str(output / 'clang-cache')
    env['SWIFT_MODULECACHE_PATH'] = str(output / 'swift-cache')
    (output / 'temporary').mkdir()
    env['TMPDIR'] = str(output / 'temporary')
    command = ['swift', 'run', '--disable-sandbox', '--build-path', output / 'swift-build', '--cache-path', output / 'swift-package-cache',
               '--config-path', output / 'swift-package-config', '--security-path', output / 'swift-package-security',
               '--package-path', checkout / 'Sources/BuildScripts', '-Xswiftc', '-module-cache-path',
               '-Xswiftc', output / 'swift-cache', 'build', 'enable-gpl', 'platform=macos', 'version=local-coreaudio-gpl-candidate']
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
    parser.add_argument('--metal-toolchain', type=Path, help='installed Metal.xctoolchain root; probe and bind compiler/linker identities explicitly')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--verify', type=Path, help='require shipping feature parity and verify a completed build')
    modes.add_argument('--diagnose-historical', type=Path, help='record identity provenance and failed parity of an earlier diagnostic artifact')
    args = parser.parse_args()
    try:
        if args.verify or args.diagnose_historical:
            if args.mpvkit or args.output or args.metal_toolchain:
                parser.error('verification/diagnosis cannot be combined with build inputs')
            output = (args.verify or args.diagnose_historical).resolve()
            receipt = json.loads((output / 'receipt.json').read_text())
            if not receipt.get('buildSucceeded') or sha(output / 'builder.py') != receipt['builderSHA256']:
                raise ValueError('completed build receipt/builder identity mismatch')
            result = verify_build(output, receipt, require_shipping=not args.diagnose_historical)
            result['verifierSHA256'] = sha(Path(__file__))
            result['actualBuilderSnapshotSHA256'] = receipt['builderSHA256']
            name = 'historical-parity-diagnostic.json' if args.diagnose_historical else 'shipping-verification.json'
            (output / name).write_text(json.dumps(result, indent=2) + '\n')
            parity = 'passed' if result['shippingFeatureParity']['passed'] else 'FAILED (historical artifact is not shipping-feature-equivalent)'
            print(f'Verified local artifact identities: {output}; {SHIPPING_PRODUCT} feature parity: {parity}')
        else:
            if not args.mpvkit or not args.output:
                parser.error('provide the input MPVKit checkout and new output directory')
            build(args.mpvkit.resolve(), args.output.resolve(), args.metal_toolchain)
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'Clean candidate build failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
