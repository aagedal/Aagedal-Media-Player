#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reproduce the arm64 scope publication correctness check; build current sources first.

Arguments: xctestrun native-manifest media-fixtures scope-fixtures UHD60-manifest NEW_OUTPUT.
This short workload does not replace sustained performance receipts.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 7:
        raise SystemExit(__doc__)
    source, manifest, media, scopes, live = [Path(p).resolve(strict=True) for p in sys.argv[1:6]]
    output = Path(sys.argv[6]).resolve()
    configuration = plistlib.loads(source.read_bytes())
    targets = [v for v in configuration.values() if isinstance(v, dict) and 'TestBundlePath' in v]
    for config in configuration.get('TestConfigurations', []):
        targets.extend(config.get('TestTargets', []))
    targets = [t for t in targets if 'Aagedal Media Player Tests' in t.get('TestBundlePath', '')]
    if len(targets) != 1:
        raise SystemExit('Expected exactly one app test target')
    target = targets[0]
    environment = target.setdefault('EnvironmentVariables', {})
    for key in list(environment):
        if key.startswith(('LIVE_LOUPE_', 'MPV_DECODER_RASTER_')) or key in (
                'AAGEDAL_SCOPE_BACKEND', 'AAGEDAL_MPV_DECODER_RASTER_HWDEC',
                'MallocStackLogging', 'MallocStackLoggingNoCompact', 'MallocStackLoggingDirectory'):
            del environment[key]
    environment.update(AAGEDAL_MPV_DECODER_RASTER_CANDIDATE='1',
                       MPV_DECODER_RASTER_CASES=str(manifest), MEDIA_FIXTURE_DIR=str(media),
                       MPV_SCOPE_TEST_FIXTURES=str(scopes), LIVE_LOUPE_SCOPE_PROVENANCE_CASES=str(live))
    target['ParallelizationEnabled'] = False
    output.mkdir(parents=True, exist_ok=False)
    (output/'executed-configuration.plist').write_bytes(plistlib.dumps(configuration))
    command = ['xcodebuild', 'test-without-building', '-destination', 'platform=macOS,arch=arm64',
               '-parallel-testing-enabled', 'NO', '-resultBundlePath', str(output/'tests.xcresult')]
    suites = ['MPVDecoderRasterTests', 'LoupeCaptureGateTests', 'ScopeAnalysisDemandTests',
              'MPVScopePlotsTests', 'ScopeFrameDifferenceTests', 'LoupeTrackDecoderTests']
    command += ['-only-testing:Aagedal Media Player Tests/'+suite for suite in suites]
    for test in ['testComparisonScopePublicationsCarryExactDifferenceInputs', 'testResizingLensUpdatesOutputWithoutReloadingPrimary',
                 'testFileReplacementAndSurfaceRebindingReleaseOnlyObsoletePlayers',
                 'testOverlayStopsReadbackDuringLivePlaybackAndRestoresMainFrameOnPause',
                 'testScopeQualificationSettingsIgnorePersistentChangesAndRestoreArguments',
                 'testRetirementProbeDoesNotRetainObservedObjectsAndDeduplicatesLiveIdentities',
                 'testRetirementSnapshotsPreserveOriginsAndOnlyRecordScalarRelationships',
                 'testScalarMemoryDiagnosticsOmitRelationshipsAndKeepIdentityHistory',
                 'testAllocationCollectorHandshakeRejectsFailureWrongProcessAndTimeout']:
        command.append('-only-testing:Aagedal Media Player Tests/LiveLoupeSessionTests/'+test)
    command.append('-skip-testing:Aagedal Media Player Tests/MPVNativeScopeIntegrationTests/testUHDLiveScopeThroughputAgainstScreenshotBackend')
    # This test explicitly requires the shipping provider to be absent.
    command.append('-skip-testing:Aagedal Media Player Tests/LoupeTrackDecoderTests/testBundledMPVFallbackPreviewNeverCertifiesMatchingDimensions')
    # Integration tests are a second XCTestCase declared in MPVScopePlotsTests.swift.
    command.append('-only-testing:Aagedal Media Player Tests/MPVNativeScopeIntegrationTests')
    with tempfile.NamedTemporaryFile(suffix='.xctestrun', dir=source.parent) as copied:
        copied.write(plistlib.dumps(configuration)); copied.flush()
        command += ['-xctestrun', copied.name]
        (output/'command.json').write_text(json.dumps(command, indent=2)+'\n')
        with (output/'xcodebuild.log').open('w') as log:
            process_environment = {k: v for k, v in os.environ.items()
                                   if not k.startswith(('LIVE_LOUPE_', 'MPV_DECODER_RASTER_'))
                                   and k not in ('AAGEDAL_SCOPE_BACKEND', 'AAGEDAL_MPV_DECODER_RASTER_HWDEC',
                'MallocStackLogging', 'MallocStackLoggingNoCompact', 'MallocStackLoggingDirectory')}
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=process_environment)
    for name, args in [('summary.json', ['get', 'test-results', 'summary']),
                       ('action.log', ['get', 'log', '--type', 'action'])]:
        read = subprocess.run(['xcrun', 'xcresulttool', *args, '--path', str(output/'tests.xcresult')],
                              capture_output=True, text=True)
        (output/name).write_text(read.stdout)
        if read.returncode:
            raise SystemExit(read.stderr)
    summary = json.loads((output/'summary.json').read_text())
    text = (output/'xcodebuild.log').read_text() + (output/'action.log').read_text()
    required = ['MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases',
                'MPV_NATIVE_SCOPE_APP_ACCEPTANCE:', 'MPV_SCOPE_DEMAND_ACCEPTANCE:',
                'MPV_COMPARISON_SCOPE_PROVENANCE_ACCEPTANCE: 2 pairs, 3 modes, exact difference pixels, capture retirement and resume']
    if (result.returncode or summary['result'] != 'Passed' or summary['failedTests']
            or summary['skippedTests'] or summary['passedTests'] < 60
            or any(marker not in text for marker in required)):
        raise SystemExit('Scope provenance check failed; inspect '+str(output))
    print(f"MPV_SCOPE_PROVENANCE_ACCEPTANCE: {summary['passedTests']} tests, zero failures/skips; short correctness workload")


if __name__ == '__main__':
    main()
