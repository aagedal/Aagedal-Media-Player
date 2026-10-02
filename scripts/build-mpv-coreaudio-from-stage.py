#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild retained GPL sources in a new workspace, without network access.

Requires prepare-mpv-coreaudio-publication.py and
build-mpv-coreaudio-clean-candidate.py beside this driver. Original build
environment gaps remain historical gaps; this records the new environment.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


publication = module('publication', 'prepare-mpv-coreaudio-publication.py')
builder = module('builder', 'build-mpv-coreaudio-clean-candidate.py')


def tree_identity(root):
    """Bind regular bytes and link targets, retaining SDK/header symlinks."""
    import hashlib
    records = []
    if not root.is_dir():
        raise ValueError('missing declared directory: ' + str(root))
    visited = {}

    def walk(path, relative):
        if path.is_symlink():
            records.append([relative, 'symlink', os.readlink(path)])
        if path.is_dir():
            resolved = path.resolve()
            if resolved in visited:
                records.append([relative, 'directory-reference', visited[resolved]])
                return
            visited[resolved] = relative
            for child in sorted(path.iterdir()):
                walk(child, relative + '/' + child.name)
        elif path.is_file():
            records.append([relative, 'file', builder.sha(path)])
        else:
            raise ValueError('unreadable declared input: ' + str(path))

    walk(root, '.')
    return {'path': str(root), 'entryCount': len(records),
            'manifestSHA256': hashlib.sha256(json.dumps(records, separators=(',', ':')).encode()).hexdigest()}


def adapt_recipe(checkout, metal, pkg_config_directories, tool_path):
    base = checkout / 'Sources/BuildScripts/XCFrameworkBuild/base.swift'
    main = checkout / 'Sources/BuildScripts/XCFrameworkBuild/main.swift'
    before = {str(p.relative_to(checkout)): builder.sha(p) for p in (base, main)}
    text = base.read_text()
    start = text.index('        if Utility.shell("which brew") == nil {')
    end = text.index('        let path = URL.currentDirectory + "dist"', start)
    text = text[:start] + text[end:]
    # Never install missing tools. The driver probes them before reconstruction.
    text = re.sub(r'Utility.shell\("brew install ([a-z0-9-]+)"\)',
                  r'preconditionFailure("Required preinstalled tool missing: \1")', text)
    text, count = re.subn(r'    static let defaultPath = "[^"\n]+"',
                         '    static let defaultPath = ' + json.dumps(tool_path), text)
    if count != 1:
        raise ValueError('unexpected default PATH recipe')
    fragment = 'let pkgConfigPathDefault = Utility.shell("pkg-config --variable pc_path pkg-config", isOutput: true)!'
    if text.count(fragment) != 1:
        raise ValueError('unexpected pkg-config recipe')
    text = text.replace(fragment, 'let pkgConfigPathDefault = ' + json.dumps(':'.join(pkg_config_directories)))
    # Source trees and auxiliary ZIPs have already been restored and verified.
    start = text.index('        // pull code from git')
    end = text.index('\n    func buildALL() throws {', start)
    text = text[:start] + '        throw NSError(domain: "Offline build requires retained source tree", code: 1)\n    }\n' + text[end:]
    fragment = '            try! Utility.launch(path: "wget", arguments: ["-O", outputFileName, library.url], currentDirectoryURL: directoryURL)'
    if text.count(fragment) != 1:
        raise ValueError('unexpected auxiliary download fallback')
    text = text.replace(fragment + '\n            try! Utility.launch(path: "/usr/bin/unzip", arguments: ["-o",outputFileName], currentDirectoryURL: directoryURL)',
                        '            throw NSError(domain: "Offline build requires retained auxiliary ZIP", code: 1)')
    base.write_text(text)
    text = main.read_text()
    text = re.sub(r'Utility.shell\("brew install ([a-z0-9-]+)"\)',
                  r'preconditionFailure("Required preinstalled tool missing: \1")', text)
    for option, name in [('metalcc', 'metal'), ('metallib', 'metallib')]:
        text, count = re.subn(r'arguments.append\("--' + option + r'=[^"\n]+"\)',
                             'arguments.append(' + json.dumps('--' + option + '=' + metal['tools'][name]['path']) + ')', text)
        if count != 1:
            raise ValueError('unexpected retained Metal path')
    main.write_text(text)
    return {'before': before, 'after': {str(p.relative_to(checkout)): builder.sha(p) for p in (base, main)},
            'policy': 'Explicit PATH/pkg-config inputs; no tool installation or network; configuration checked against retained build.'}


def configuration_differences(stage, verification):
    baseline = json.loads((stage / 'provenance/build-receipt.json').read_text())['verification']['shippingFeatureParity']
    differences = []
    for arch, headers in baseline['architectures'].items():
        for name, identity in headers.items():
            actual = verification['shippingFeatureParity']['architectures'][arch][name]
            if actual['booleanConfigurationSHA256'] != identity['booleanConfigurationSHA256']:
                differences.append(f'{arch}/{name}')
    return differences


def build(args):
    stage, output = args.stage.resolve(), args.output.resolve()
    if output.exists():
        raise ValueError('output must be new')
    # Probe network denial before allocating the build workspace.
    policy = '(version 1) (allow default) (deny network*)'
    subprocess.run(['/usr/bin/sandbox-exec', '-p', policy, '/usr/bin/true'], check=True)
    tools = {}
    for name in ('python3', 'swift', 'git', 'clang', 'clang++', 'xcodebuild', 'xcrun',
                 'meson', 'ninja', 'pkg-config', 'nasm', 'sdl2-config', 'make', 'libtool', 'lipo', 'otool', 'zip', 'unzip'):
        path = shutil.which(name)
        if not path:
            raise ValueError('required preinstalled tool missing: ' + name)
        resolved = Path(path).resolve()
        tools[name] = {'path': path, 'resolvedPath': str(resolved), 'sha256': builder.sha(resolved)}
    for name in ('clang', 'clang++', 'swift', 'ld', 'ar'):
        resolved = Path(builder.capture(['xcrun', '--find', name])).resolve()
        tools['selected-' + name] = {'path': str(resolved), 'resolvedPath': str(resolved), 'sha256': builder.sha(resolved)}
    metal = builder.metal_toolchain_prerequisite(args.metal_toolchain.resolve())
    directories = [str(p.resolve()) for p in args.pkg_config_directory]
    if any(not Path(p).is_dir() for p in directories):
        raise ValueError('explicit pkg-config directory missing')
    tool_path = ':'.join(dict.fromkeys(str(Path(t['path']).parent) for t in tools.values())) + ':/usr/bin:/bin:/usr/sbin:/sbin'
    sdk = Path(builder.capture(['xcrun', '--sdk', 'macosx', '--show-sdk-path']))
    environment_identity = {'tools': tools, 'sdk': tree_identity(sdk),
                            'pkgConfigDirectories': [tree_identity(Path(p)) for p in directories],
                            'externalHeaders': [tree_identity(p.resolve()) for p in args.external_headers],
                            'xcodeVersion': builder.capture(['xcodebuild', '-version']),
                            'compilerVersion': builder.capture(['clang', '--version']),
                            'swiftVersion': builder.capture(['swift', '--version']),
                            'mesonVersion': builder.capture(['meson', '--version']),
                            'ninjaVersion': builder.capture(['ninja', '--version'])}
    reconstruction = publication.reconstruct(stage, output, args.expected_publication_sha256)
    checkout = output / 'MPVKit'
    adaptations = adapt_recipe(checkout, metal, directories, tool_path)
    receipt = {'schemaVersion': 1, 'buildSucceeded': False,
               'publicationSHA256': args.expected_publication_sha256,
               'newEnvironment': environment_identity, 'recipeAdaptations': adaptations,
               'shippingPrerequisites': {'metalToolchain': metal},
               'sourceInputs': {s['name']: {'candidateRevision': s['revision'], 'candidateTree': s['tree']}
                                for s in reconstruction['sourceSnapshots'] if s['name'] != 'MPVKit-recipe'},
               'prebuiltAuxiliaryInputs': [{**e, 'path': str(stage / e['publicationPath'])}
                                          for e in json.loads((stage / 'publication.json').read_text())['auxiliaryBuildInputs']],
               'candidateMPVKitRevision': builder.commit(checkout, 'Make retained GPL recipe portable and prohibit network fallbacks'),
               'originalEnvironmentGaps': reconstruction['environmentDeclaration']['unrecordedOriginalIdentities'],
               'byteIdenticalRebuildDemonstrated': False}
    # ZIPs are already present: unpack explicitly, without cached expanded dirs.
    for entry in receipt['prebuiltAuxiliaryInputs']:
        path = checkout / entry['relativePath']
        builder.unpack_zip(path, path.parent)
    env = {key: os.environ[key] for key in ('HOME',) if key in os.environ}
    env.update(reconstruction['isolatedEnvironmentPaths'], PATH=tool_path,
               DEVELOPER_DIR=builder.capture(['xcode-select', '-p']), LC_ALL='C')
    receipt['buildEnvironment'] = env
    receipt['buildCommand'] = ['/usr/bin/sandbox-exec', '-p', policy] + reconstruction['candidateBuildCommand']
    for filename in ('build-mpv-coreaudio-from-stage.py', 'prepare-mpv-coreaudio-publication.py', 'build-mpv-coreaudio-clean-candidate.py'):
        shutil.copyfile(Path(__file__).with_name(filename), output / filename)
    (output / 'portable-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Build log: {output / "build.log"}', flush=True)
    with (output / 'build.log').open('wb') as log:
        subprocess.run(receipt['buildCommand'], cwd=checkout, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    receipt['artifacts'] = {str(p.relative_to(checkout)): publication.identity(p)
                            for p in sorted((checkout / 'dist/release').glob('*.zip'))}
    receipt['verification'] = builder.verify_build(output, receipt)
    receipt['configurationDifferences'] = configuration_differences(stage, receipt['verification'])
    for tool in tools.values():
        if builder.sha(Path(tool['resolvedPath'])) != tool['sha256']:
            raise ValueError('declared tool changed during build: ' + tool['path'])
    for declaration in [environment_identity['sdk'], *environment_identity['pkgConfigDirectories'], *environment_identity['externalHeaders']]:
        if tree_identity(Path(declaration['path'])) != declaration:
            raise ValueError('declared input tree changed during build: ' + declaration['path'])
    (output / 'portable-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt['configurationDifferences']:
        raise ValueError('optional feature configuration changed: ' + ', '.join(receipt['configurationDifferences']))
    receipt['buildSucceeded'] = True
    (output / 'portable-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Portable rebuild verified; shipping/runtime acceptance remains separate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--expected-publication-sha256', required=True)
    parser.add_argument('--metal-toolchain', type=Path, required=True)
    parser.add_argument('--pkg-config-directory', type=Path, action='append', default=[])
    parser.add_argument('--external-headers', type=Path, action='append', default=[])
    args = parser.parse_args()
    try:
        build(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Portable rebuild failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
