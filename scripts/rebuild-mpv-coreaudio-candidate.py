#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Incrementally rebuild the pinned MPVKit CoreAudio objects into a LOCAL candidate.

Requires the matching, already built MPVKit checkout and the app's resolved
Libmpv.framework. Never edits either input or the project's dependency pin.
This is engineering tooling, not a clean release build or audible-output proof.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = ROOT / 'docs/evidence/live-meter-native-output-20260930/isolated-coreaudio-probe/source-identities.json'
PATCH = ROOT / 'docs/evidence/live-meter-native-output-20260930/isolated-coreaudio-probe/iina-18384-audio-channel.patch'
FILES = ('ao_coreaudio.c', 'ao_coreaudio_chmap.c')
ARCHES = ('arm64', 'x86_64')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(args, **kwargs):
    return subprocess.run([str(item) for item in args], check=True, **kwargs)


def capture(args, **kwargs):
    return run(args, stdout=subprocess.PIPE, **kwargs).stdout


def compile_command(entry, source, patched_source, output, sdk):
    """Reuse original flags and generated headers, writing ONLY to output."""
    cwd = Path(entry['directory'])
    tokens = shlex.split(entry['command'])
    if not tokens or tokens[0] != '/usr/bin/clang':
        raise ValueError('compile database must invoke /usr/bin/clang directly')
    result = [tokens[0]]
    index = 1
    while index < len(tokens):
        token = tokens[index]
        if token in ('-MD', '-MMD'):
            index += 1
            continue
        if token in ('-o', '-MF', '-MQ', '-MT', '-isysroot'):
            index += 2
            continue
        if token == '-c':
            result += ['-c', str(patched_source / 'audio/out' / Path(entry['file']).name)]
            index += 2
            continue
        if token.startswith('-I') and len(token) > 2:
            include = (cwd / token[2:]).resolve()
            if include == source or source in include.parents:
                include = patched_source / include.relative_to(source)
            token = '-I' + str(include)
        elif token in ('-arch', '-target'):
            value = tokens[index + 1]
            if token == '-arch' and value not in ARCHES:
                raise ValueError(f'unsupported architecture: {value}')
            if token == '-target' and value not in [arch + '-apple-macos12.0' for arch in ARCHES]:
                raise ValueError(f'unsupported target: {value}')
            result += [token, value]
            index += 2
            continue
        elif not (token.startswith('-D') or
                  re.fullmatch(r'-W(?:no-)?[a-z][a-z0-9-]*(?:=[a-z0-9-]+)?', token) or
                  token in ('-std=c11', '-O3', '-mmacosx-version-min=12.0',
                            '-fvisibility=hidden', '-fdiagnostics-color=always',
                            '-fno-math-errno', '-fno-signed-zeros', '-fno-trapping-math')):
            # Clang response files, diagnostic output, profiling and save-temps
            # can write outside -o. Fail closed on every unknown argument.
            raise ValueError(f'unsupported cached compile argument: {token}')
        result.append(token)
        index += 1
    return result + ['-isysroot', str(sdk), '-o', str(output)]


def source_tree_sha(directory):
    manifest = []
    for file in sorted(directory.rglob('*')):
        if file.is_file() and '.git' not in file.relative_to(directory).parts:
            manifest.append(str(file.relative_to(directory)) + '\0' + sha(file))
    return hashlib.sha256('\n'.join(manifest).encode()).hexdigest()


def archive_members(archive):
    names = [name for name in capture(['/usr/bin/ar', 't', archive]).decode().splitlines()
             if not name.startswith('__.SYMDEF')]
    # Duplicate names make extraction/comparison ambiguous. Refuse such input.
    if len(names) != len(set(names)):
        raise ValueError(f'duplicate archive members: {archive}')
    return names


def validate_inputs(mpvkit, framework, output):
    identity = json.loads(IDENTITY.read_text())
    source = mpvkit / 'dist/libmpv-v0.41.0'
    binary = framework / 'Libmpv'
    if output.exists():
        raise ValueError(f'output already exists: {output}')
    if any(p == output or p in output.parents for p in (mpvkit, framework)):
        raise ValueError('output must be outside both input directories')
    revision = capture(['git', '-C', mpvkit, 'rev-parse', 'HEAD']).decode().strip()
    if revision != identity['mpvkitRevision']:
        raise ValueError(f'MPVKit revision mismatch: {revision}')
    if sha(PATCH) != identity['iinaPatchSHA256']:
        raise ValueError('retained dependency patch hash mismatch')
    for name, expected in identity['sourceSHA256'].items():
        if sha(source / 'audio/out' / name) != expected:
            raise ValueError(f'pinned source hash mismatch: {name}')
    if not binary.is_file():
        raise ValueError('input must be the resolved Libmpv.framework')
    architectures = capture(['/usr/bin/lipo', '-archs', binary]).decode().split()
    if set(architectures) != set(ARCHES):
        raise ValueError(f'expected universal macOS framework, got: {architectures}')
    for arch in ARCHES:
        scratch = mpvkit / 'dist/libmpv/macos/scratch' / arch
        if not (scratch / 'compile_commands.json').is_file():
            raise ValueError(f'missing cached compile database: {arch}')
    return identity, source, binary


def framework_binary_destination(framework):
    destination = (framework / 'Libmpv').resolve()
    if framework.resolve() not in destination.parents:
        raise ValueError('framework binary symlink escapes isolated candidate')
    return destination


def rebuild(mpvkit, framework, output):
    identity, source, binary = validate_inputs(mpvkit, framework, output)
    sdk = capture(['xcrun', '--sdk', 'macosx', '--show-sdk-path']).decode().strip()
    output.mkdir(parents=True)
    patched_source = output / 'source'
    shutil.copytree(source, patched_source, ignore=shutil.ignore_patterns('.git'))
    run(['git', 'apply', '--check', PATCH], cwd=patched_source)
    run(['git', 'apply', PATCH], cwd=patched_source)
    receipt = {
        'scope': 'local incremental dependency rebuild; neither published nor release accepted',
        'mpvkitRevision': identity['mpvkitRevision'],
        'retainedMPVSourceRevision': identity['mpvSourceRevision'],
        'sourceRevisionVerification': 'Revision from prior diagnosis; three patched files independently hash-checked. Full tree fingerprint below records current cached inputs, not an upstream clean checkout assertion.',
        'inputSourceTreeSHA256': source_tree_sha(source),
        'compilerVersion': capture(['/usr/bin/clang', '--version']).decode().strip(),
        'iinaPatchURL': identity['iinaPatchURL'],
        'iinaPatchRevision': identity['iinaPatchRevision'],
        'patchSHA256': sha(PATCH),
        'inputFrameworkSHA256': sha(binary),
        'sdkPath': sdk,
        'architectures': {},
        'limitations': ['Only two CoreAudio objects rebuilt; other objects retained byte-for-byte.',
                        'Device-switch refresh remains open in upstream repair candidate.',
                        'No audible-output, surround hardware, supported macOS or release acceptance.'],
    }
    archives = []
    for arch in ARCHES:
        directory = output / arch
        directory.mkdir()
        original = directory / 'original.a'
        candidate = directory / 'candidate.a'
        run(['/usr/bin/lipo', binary, '-thin', arch, '-output', original])
        names = archive_members(original)
        extraction = directory / 'original-objects'
        extraction.mkdir()
        run(['/usr/bin/ar', 'x', original], cwd=extraction)
        scratch = mpvkit / 'dist/libmpv/macos/scratch' / arch
        entries = json.loads((scratch / 'compile_commands.json').read_text())
        changed = {}
        for name in FILES:
            matches = [e for e in entries if Path(e['file']).name == name]
            if len(matches) != 1:
                raise ValueError(f'expected one compile command for {arch}/{name}')
            entry = matches[0]
            member = Path(entry['output']).name
            if member not in names:
                raise ValueError(f'linked framework missing original object: {member}')
            # Match each original object to this exact local build, not just source.
            if sha(extraction / member) != sha(scratch / entry['output']):
                raise ValueError(f'framework/build object mismatch: {arch}/{member}')
            if arch == 'arm64' and name == 'ao_coreaudio.c' and sha(extraction / member) != identity['linkedCoreAudioObjectSHA256']:
                raise ValueError('framework does not match retained native diagnosis')
            object_path = directory / member
            command = compile_command(entry, source, patched_source, object_path, sdk)
            with (directory / (name + '.log')).open('wb') as log:
                run(command, cwd=scratch, stdout=log, stderr=subprocess.STDOUT)
            changed[member] = {'originalSHA256': sha(extraction / member), 'rebuiltSHA256': sha(object_path), 'command': command}
        shutil.copy2(original, candidate)
        run(['/usr/bin/ar', 'r', candidate] + [directory / member for member in changed])
        run(['/usr/bin/ranlib', candidate])
        if archive_members(candidate) != names:
            raise ValueError(f'candidate archive member list changed: {arch}')
        verified = directory / 'candidate-objects'
        verified.mkdir()
        run(['/usr/bin/ar', 'x', candidate], cwd=verified)
        for member in names:
            expected = directory / member if member in changed else extraction / member
            if sha(verified / member) != sha(expected):
                raise ValueError(f'candidate member verification failed: {arch}/{member}')
        receipt['architectures'][arch] = {'originalArchiveSHA256': sha(original), 'candidateArchiveSHA256': sha(candidate), 'unchangedObjectCount': len(names) - len(changed), 'compileDatabaseSHA256': sha(scratch / 'compile_commands.json'), 'generatedHeaderSHA256': {str(header.relative_to(scratch)): sha(header) for header in sorted(scratch.rglob('*.h'))}, 'rebuiltObjects': changed}
        archives.append(candidate)
    candidate_framework = output / 'Libmpv.framework'
    shutil.copytree(framework, candidate_framework, symlinks=True)
    run(['/usr/bin/lipo', '-create'] + archives + ['-output', framework_binary_destination(candidate_framework)])
    xcframework = output / 'Libmpv.xcframework'
    run(['xcodebuild', '-create-xcframework', '-framework', candidate_framework, '-output', xcframework])
    archive = output / 'Libmpv.xcframework.zip'
    run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', xcframework, archive])
    receipt['candidateFrameworkSHA256'] = sha(candidate_framework / 'Libmpv')
    receipt['xcframeworkZIPChecksum'] = sha(archive)
    receipt['patchedSourceSHA256'] = {name: sha(patched_source / 'audio/out' / name) for name in identity['sourceSHA256']}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Local candidate and identity receipt: {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mpvkit', type=Path, help='matching local MPVKit checkout/build cache')
    parser.add_argument('framework', type=Path, help='resolved pinned Libmpv.framework used by app')
    parser.add_argument('output', type=Path, help='new directory outside both inputs')
    args = parser.parse_args()
    try:
        rebuild(args.mpvkit.resolve(), args.framework.resolve(), args.output.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Candidate rebuild failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
