#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain a complete local run: retain.py NEW_RUN_ROOT [--rejected]."""
import gzip
import hashlib
import json
import plistlib
import itertools
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path.cwd()
base = Path(sys.argv[1]).resolve(strict=True)
out = Path(__file__).resolve().parent
rejected = sys.argv[2:] == ['--rejected']
assert len(sys.argv) == (3 if rejected else 2), __doc__

def sha(path):
    return hashlib.file_digest(Path(path).open('rb'), 'sha256').hexdigest()

def write(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def command(*args):
    return subprocess.check_output(args, text=True).strip()

# Diagnostics must cover the same process and every cycle, even for rejection.
import importlib.util
spec = importlib.util.spec_from_file_location('runner', root/'scripts/validate-mpv-native-app.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
runner.validate_memory_diagnostics(base/'soak/memory-diagnostics', 3, post_test=True, scalar_only=True)
for checkpoint in ('post-test-entry', 'post-test-delayed'):
    shutil.copyfile(base/'soak/memory-diagnostics'/f'{checkpoint}.json', out/f'memory-{checkpoint}.json')
shutil.copyfile(base/'soak/memory-diagnostics/final-delayed.json', out/'memory-final-delayed.json')
for cycle in range(4):
    source = base/'soak/memory-diagnostics'/f'cycle-{cycle}.json'
    shutil.copyfile(source, out/f'memory-cycle-{cycle}.json')
shutil.copyfile(base/'runner-regressions.log', out/'runner-regressions.log')
shutil.copyfile(base/'signature-verification.txt', out/'signature-verification.txt')
(out/'host-processes.txt.gz').write_bytes(gzip.compress((base/'host-processes.txt').read_bytes(), mtime=0))

for name in ('focused', 'soak'):
    run = base / (name)
    summary = json.loads(command('xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(run/'tests.xcresult')))
    if name == 'soak' and rejected:
        assert summary['result'] == 'Failed' and summary['failedTests'] == 1 and summary['skippedTests'] == 0, summary
        assert summary['passedTests'] == 1, summary
    else:
        assert summary['result'] == 'Passed' and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
        assert summary['passedTests'] == (72 if name == 'focused' else 2), summary
    write(name+'-summary.json', summary)
    for source, target in [('xcodebuild.log', name+'-tests.log.gz'), ('action.log', name+'-action.log.gz')]:
        (out/target).write_bytes(gzip.compress((run/source).read_bytes(), mtime=0))
    for file in ('executed-configuration.plist', 'command.json'):
        shutil.copyfile(run/file, out/(name+'-'+file))
    shutil.copyfile(base/(name+'-runner.log'), out/(name+'-runner.log'))

def emitted_output(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if (key == 'emittedOutput' and isinstance(value, str)
                    and node.get('testName') == 'testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory()'):
                yield value
            else:
                yield from emitted_output(value)
    elif isinstance(node, list):
        for value in node:
            yield from emitted_output(value)

outputs = list(emitted_output(json.loads((base/'soak/action.log').read_text())))
assert len(outputs) == 1, 'Expected exactly one sustained comparison test output'
text = outputs[0]
required = [
    'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,',
    'MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 3 scope sources, 10 seconds per selection, resolution=720, targetFPS=15',
    'MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per selection, resolution=720, targetFPS=15, exact difference pixels and occupied bins, capture retirement and resume']
assert all(re.search(re.escape(marker) + r'(?=$|[\s])', text) for marker in required)

lines = [line.strip() for line in text.splitlines() if 'MPV_COMPARISON_' in line or 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE:' in line]
(out/'measurements.txt').write_text('\n'.join(lines)+'\n')
loupe = [line for line in lines if 'MPV_COMPARISON_LOUPE_WINDOW:' in line]
scopes = [line for line in lines if 'MPV_COMPARISON_SCOPE_WINDOW:' in line]
pixels = [line for line in lines if 'MPV_COMPARISON_DIFFERENCE_PUBLICATION:' in line]
resumes = [line for line in lines if 'MPV_COMPARISON_DIFFERENCE_RESUME:' in line]
cycles = [line for line in lines if 'MPV_COMPARISON_LOUPE_SOAK_CYCLE:' in line]
def numbers(pattern, rows):
    return [float(re.search(pattern, line)[1]) for line in rows]

fps = numbers(r'fps=([\d.]+)', loupe)
drift = numbers(r'maxDrift=([\d.eE+-]+)', loupe)
valid = numbers(r'validSamples=(\d+)/30', loupe)
footprints = numbers(r'physicalFootprintBytes=(\d+)', cycles)
coverage = {}
for line in scopes:
    key = tuple(re.search(pattern, line)[1] for pattern in (r'cycle=(\d+)', r'pair=([^,]+)', r'mode=([^,]+)', r'selection=([^,]+)'))
    coverage[key] = max(coverage.get(key, 0), float(re.search(r'measuredSeconds=([\d.]+)', line)[1]))
pairs = ['uhd-h264-hardware/pq-hevc-hardware', 'pq-hevc-hardware/hlg-hevc-hardware']
expected = set(itertools.product(['1', '2', '3'], pairs, ['sideBySide', 'verticalWipe', 'overlay'], ['primary', 'secondary', 'difference']))
assert set(coverage) == expected and min(coverage.values()) >= 10, coverage
assert all('resolution=720, targetFPS=15,' in line for line in scopes)
def identity(line, fields):
    return tuple(re.search(rf'{field}=([^,]+)', line)[1] for field in fields)
def unique_keys(rows, fields):
    keys = [identity(line, fields) for line in rows]
    assert len(keys) == len(set(keys)), 'Duplicate measurement identity'
    return set(keys)
fields = ['cycle', 'pair', 'mode', 'window']
scope_keys = unique_keys(scopes, fields+['selection'])
loupe_keys = unique_keys(loupe, fields+['scopeSelection', 'source'])
assert loupe_keys == {(*key, source) for key in scope_keys for source in ['0', '1']}
difference_keys = unique_keys([line for line in scopes if 'selection=difference,' in line], fields)
assert unique_keys(pixels, fields) == difference_keys
assert unique_keys(resumes, ['cycle', 'pair']) == set(itertools.product(['1', '2', '3'], pairs))
assert [identity(line, ['cycle'])[0] for line in cycles] == ['1', '2', '3']
assert len(footprints) == 3
for cycle, footprint in enumerate(footprints, 1):
    sample = json.loads((out/f'memory-cycle-{cycle}.json').read_text())
    assert sample['gatePhysicalFootprintBytes'] == int(footprint)
    counts = sample['retirement']
    for label in ('host', 'window', 'primaryController', 'secondaryController', 'comparisonController',
                  'loupeState', 'primaryLoupeCapture', 'secondaryLoupeCapture', 'primaryScopeCapture',
                  'secondaryScopeCapture', 'scopeProbe', 'scopeWorker', 'loupeSurface', 'loupeLayer',
                  'loupeSession', 'followerPlayer', 'primaryPlayer', 'secondaryPlayer'):
        assert counts[label]['observed'] >= cycle * 2, (cycle, label, counts)

memory_passed = max(footprints) - footprints[0] <= 268435456
cadence_passed = min(fps) >= 45
clock_passed = max(drift) <= .1 and min(valid) >= 29
if not rejected:
    assert memory_passed and cadence_passed and clock_passed
assert len(pixels) == sum('selection=difference,' in line for line in scopes)
assert len(resumes) == 6
assert all(n == 291600 for n in numbers(r'pixels=(\d+)', pixels+resumes))
write('stats.json', dict(accepted=not rejected, memoryGatePassed=memory_passed,
    cadenceGatePassed=cadence_passed, clockGatePassed=clock_passed, loupeWindows=len(loupe), scopeWindows=len(scopes),
    sampledDifferencePublications=len(pixels), resumedDifferencePublications=len(resumes),
    pixelsPerSample=291600, minimumLoupePresentationsPerSecond=min(fps), maximumFollowerDriftSeconds=max(drift),
    usableClockSamples=int(sum(valid)), totalClockSamples=len(valid)*30,
    minimumMeasuredSecondsPerSelection=min(coverage.values()), measuredSelections=len(coverage),
    cycleEndFootprintBytes=[int(n) for n in footprints], maximumCycleEndGrowthBytes=int(max(footprints)-footprints[0]),
    scopeConfiguration=dict(resolution=720, targetFPS=15, secondsPerSelection=10, cycles=3)))

sources = {}
for folder in ('Aagedal Media Player', 'Aagedal Media Player Tests'):
    current_paths = {p.relative_to(root) for p in (root/folder).rglob('*.swift')}
    prepared_paths = {p.relative_to(base/'app') for p in (base/'app'/folder).rglob('*.swift')}
    assert current_paths == prepared_paths, 'Prepared/current Swift file sets differ'
for folder in ('Aagedal Media Player', 'Aagedal Media Player Tests'):
    for path in sorted((root/folder).rglob('*.swift')):
        relative = str(path.relative_to(root))
        assert sha(path) == sha(base/'app'/relative), relative
        sources[relative] = sha(path)
app = base/'derived/Build/Products/Release/Aagedal Media Player.app'
binaries = {}
for path in [app/'Contents/MacOS/Aagedal Media Player', app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests']:
    architecture = command('lipo', '-archs', str(path))
    assert architecture == 'arm64', architecture
    binaries[str(path.relative_to(app))] = dict(sha256=sha(path), architecture=architecture)
previous = json.loads((root/'docs/evidence/mpv-comparison-scope-provenance-20261016/candidate-receipt.json').read_text())
fixtures = previous['fixturesSHA256']
for path, expected in fixtures.items():
    assert sha(path) == expected, path
libmpv = Path('/private/tmp/aagedal-scopes-delta-restored-r3-20261015/MPVKit/Candidate/Libmpv-GPL/Libmpv.xcframework/macos-arm64/Libmpv.framework/Versions/A/Libmpv')
assert sha(libmpv) == previous['libmpvSHA256']
inputs = json.loads((base/'execution-inputs.json').read_text())
expected_inputs = {str(base/'native-fixtures.json'),
    '/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json',
    str(app/'Contents/MacOS/Aagedal Media Player'),
    str(app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests')}
assert set(inputs) == expected_inputs, 'Pre-run input pins must cover both manifests and executables'
for path, expected in inputs.items():
    assert sha(path) == expected, path
shutil.copyfile(base/'execution-inputs.json', out/'execution-inputs.json')
validation_inputs = json.loads((base/'validation-inputs.json').read_text())
for path, expected in validation_inputs.items():
    assert sha(path) == expected, path
shutil.copyfile(base/'validation-inputs.json', out/'validation-inputs.json')
for name in ('reference-graph-command.json', 'reference-graph-exit.txt'):
    if (base/name).exists(): shutil.copyfile(base/name, out/name)
if (base/'reference-graph.log').exists():
    (out/'reference-graph.log.gz').write_bytes(gzip.compress((base/'reference-graph.log').read_bytes(), mtime=0))
for name, key, manifest in [('focused', 'MPV_DECODER_RASTER_CASES', base/'native-fixtures.json'),
                            ('focused', 'LIVE_LOUPE_SCOPE_PROVENANCE_CASES', Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json')),
                            ('soak', 'LIVE_LOUPE_COMPARISON_CASES', Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json'))]:
    config = plistlib.loads((base/name/'executed-configuration.plist').read_bytes())
    targets = [v for v in config.values() if isinstance(v, dict) and 'TestBundlePath' in v]
    for item in config.get('TestConfigurations', []):
        targets.extend(item.get('TestTargets', []))
    targets = [t for t in targets if 'Aagedal Media Player Tests' in t.get('TestBundlePath', '')]
    assert len(targets) == 1
    assert Path(targets[0]['EnvironmentVariables'][key]).resolve() == manifest.resolve()
assert sha(base/'prepare.py') == sha(out/'prepare.py')
for name in ('build.log', 'build-retry.log', 'build-final.log', 'build-final-check.log'):
    (out/(name+'.gz')).write_bytes(gzip.compress((base/name).read_bytes(), mtime=0))
write('candidate-receipt.json', dict(accepted=not rejected, sourceCommit=command('git', 'rev-parse', 'HEAD'), sourceFilesSHA256=sources,
    binaries=binaries, libmpvSHA256=sha(libmpv), fixturesSHA256=fixtures,
    fixtureManifestsSHA256={str(p):sha(p) for p in [base/'native-fixtures.json', Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json')]},
    dependencyDescriptorsSHA256={p:sha(root/p) for p in previous['dependencyDescriptorsSHA256']},
    validationScriptsSHA256={p:sha(root/p) for p in ['scripts/validate-mpv-native-app.py', 'scripts/test-mpv-native-app-runner.py',
        str(out.relative_to(root)/'run-validation.py'), str(out.relative_to(root)/'run-focused.py'), str(out.relative_to(root)/'summarize-retirement.py'), str(out.relative_to(root)/'run-diagnostic.py'), str(out.relative_to(root)/'prepare.py'), str(out.relative_to(root)/'retain.py')]},
    host=dict(sw_vers=command('sw_vers'), architecture=command('uname', '-m'), cpu=command('sysctl','-n','machdep.cpu.brand_string'), memoryBytes=command('sysctl','-n','hw.memsize')),
    buildLogSHA256={name:sha(base/name) for name in ('build.log', 'build-retry.log', 'build-final.log', 'build-final-check.log')}))
patch = subprocess.check_output(['git','diff','HEAD','--','Aagedal Media Player','Aagedal Media Player Tests','scripts/validate-mpv-native-app.py','scripts/test-mpv-native-app-runner.py'])
(out/'source.patch.gz').write_bytes(gzip.compress(patch, mtime=0))
print('Retained '+('rejected sustained run' if rejected else 'accepted sustained run')+' and passing focused checks; source/binary/fixture checks passed')

subprocess.run([sys.executable, str(out/'summarize-retirement.py')], check=True)
