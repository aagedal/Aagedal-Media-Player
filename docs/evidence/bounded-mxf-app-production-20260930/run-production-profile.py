#!/usr/bin/env python3
"""Run the unmodified production MetadataService profiler in an isolated app build.

This retained runner is specific to the temporary local-package candidate below.
It executes metadata-only fresh XCTest hosts, retains native memory/cache records,
and validates all media, source, manifest and binary hashes before and after.
"""
from pathlib import Path
import datetime
import hashlib
import json
import plistlib
import subprocess

repo = Path('/Users/truls.aagedal/Developer/Aagedal-Media-Player')
project = Path('/private/tmp/aagedal-bounded-mxf-app-production-20260930')
package = Path('/private/tmp/aagedal-bounded-mxf-candidate-20260930')
derived = Path('/private/tmp/aagedal-bounded-mxf-app-dd-20260930')
artifacts = Path('/private/tmp/aagedal-bounded-mxf-app-artifacts-20260930')
app = derived / 'Build/Products/Release/Aagedal Media Player.app'
template = next((derived / 'Build/Products').glob('*.xctestrun'))
inputs = [
    Path('/Users/truls.aagedal/Movies/TestVideo/testmappe_agedal_media_stitch/M4ROOT/CLIP/rre_8073.MP4'),
    Path('/Users/truls.aagedal/Movies/TestVideo/Sony A1 Card/M4ROOT/CLIP/20260502_TRA_MOV_0240.MP4'),
    Path('/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF'),
]

def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            sha.update(chunk)
    return {'bytes': path.stat().st_size, 'sha256': sha.hexdigest()}

filelist = next((derived / 'Build/Intermediates.noindex/SwiftMediaMetadata.build').rglob('SwiftMediaMetadata.SwiftFileList'))
compiled_sources = [Path(line.strip()) for line in filelist.read_text().splitlines() if line.strip()]
assert any(p.name == 'MXFFileCursor.swift' for p in compiled_sources)
assert all(str(p).startswith(str(package)) or 'DerivedSources' in str(p) for p in compiled_sources)
tracked = [app / 'Contents/MacOS/Aagedal Media Player',
           app / 'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',
           derived / 'Build/Products/Release/SwiftMediaMetadata.o',
           project / 'Aagedal Media Player.xcodeproj/project.pbxproj',
           project / 'Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
           project / 'Aagedal Media Player/Logic/MetadataService.swift',
           project / 'Aagedal Media Player/Models/MediaMetadata.swift',
           project / 'Aagedal Media Player Tests/ProductionMetadataMemoryPerformanceTests.swift',
           package / 'Package.swift', template, filelist, *compiled_sources, *inputs]
for path in inputs:
    tracked += [p for p in path.parent.iterdir() if p.is_file() and p.suffix.lower() == '.xml' and p.stem.startswith(path.stem)]
before = {str(path): digest(path) for path in tracked}
environment = {
    'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'temporaryAppHEAD': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=project, text=True).strip(),
    'temporaryAppStatus': subprocess.check_output(['git', 'status', '--short'], cwd=project, text=True),
    'compiledPackageRoot': str(package), 'compiledSourceFileList': str(filelist),
    'intentionallyLocalPackage': 'Temporary XCLocalSwiftPackageReference to the bounded MXF candidate; package manifest omits ArgumentParser/CLI targets.',
    'qualification': 'Production app MetadataService path on this host; concurrent root app/dependency/native work possible. No decoder/transport requested. No external-volume/base-M1/multi-hour acceptance.',
    'identitiesBefore': before,
}
(artifacts / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
for index, path in enumerate(inputs):
    run = plistlib.loads(template.read_bytes().replace(b'__TESTROOT__', str(derived / 'Build/Products').encode()))
    for config in run['TestConfigurations']:
        for target in config['TestTargets']:
            target.setdefault('EnvironmentVariables', {}).update({
                'METADATA_MEMORY_PROFILE_INPUT': str(path),
                'METADATA_MEMORY_PROFILE_INPUT_INDEX': str(index),
            })
    manifest = artifacts / f'input-{index}.xctestrun'
    manifest.write_bytes(plistlib.dumps(run))
    run_directory = artifacts / 'runs' / f'input-{index}'
    run_directory.mkdir(parents=True)
    print(f'Profiling input {index}: {path.name}', flush=True)
    with (run_directory / 'profile.log').open('w') as log:
        subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(manifest),
                        '-destination', 'platform=macOS', '-derivedDataPath', str(derived),
                        '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'NO',
                        '-resultBundlePath', str(run_directory / 'Profile.xcresult'),
                        '-only-testing:Aagedal Media Player Tests/ProductionMetadataMemoryPerformanceTests/testProductionMetadataMemoryProfileWhenRequested'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(run_directory / 'Profile.xcresult'),
                    '--output-path', str(artifacts / 'attachments' / f'input-{index}')], check=True, stdout=subprocess.DEVNULL)
after = {str(path): digest(path) for path in tracked}
assert before == after, 'Tracked app/package/source/media identities changed during run'
environment['identitiesUnchangedAfter'] = True
environment['endedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(artifacts / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
with (artifacts / 'validation.log').open('w') as log:
    subprocess.run(['python3', str(project / 'scripts/validate-production-metadata-memory-profile.py'), str(artifacts), '3'],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
print('All three production candidate profiles and identity checks passed.', flush=True)
