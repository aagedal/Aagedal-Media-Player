#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run restored native-raster app fixtures, optionally with sustained UHD/HDR load.

Build for testing first using docs/MPV_NATIVE_RASTER_HANDOFF.md. This copies the
xctestrun beside the original so __TESTROOT__ keeps resolving to the built app.
It never changes the original test configuration or shipping dependency pins.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xctestrun', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path, help='new directory for logs and xcresult')
    parser.add_argument('--stress-cycles', type=int, help='3–100 complete UHD/HDR lifecycle cycles')
    parser.add_argument('--playback', action='store_true', help='validate HDR playback preview and refresh cadence')
    parser.add_argument('--live-viewer', action='store_true', help='validate the secondary-player loupe using UHD 60 fps fixtures')
    parser.add_argument('--soak-seconds', type=int, help='with --live-viewer or --comparison: 10–3600 seconds per workload/mode')
    parser.add_argument('--soak-cycles', type=int, help='with --soak-seconds: 3–100 cycles (default 3)')
    parser.add_argument('--comparison', action='store_true', help='validate different-file UHD60 comparison canvas and paired loupes')
    args = parser.parse_args()
    if args.soak_seconds is not None:
        if not (args.live_viewer or args.comparison) or not 10 <= args.soak_seconds <= 3600:
            parser.error('--soak-seconds requires --live-viewer or --comparison and a value from 10 through 3600')
        if args.soak_cycles is None:
            args.soak_cycles = 3
        if not 3 <= args.soak_cycles <= 100:
            parser.error('--soak-cycles must be between 3 and 100')
    elif args.soak_cycles is not None:
        parser.error('--soak-cycles requires --soak-seconds')
    if args.stress_cycles is not None and not 3 <= args.stress_cycles <= 100:
        parser.error('--stress-cycles must be between 3 and 100')
    if sum([args.playback, args.live_viewer, args.stress_cycles is not None, args.comparison]) > 1:
        parser.error('--playback, --live-viewer, --comparison and --stress-cycles must run separately')
    configuration = plistlib.loads(args.xctestrun.read_bytes())
    # Xcode writes either legacy top-level test targets or format-2 configs.
    targets = [value for value in configuration.values()
               if isinstance(value, dict) and 'TestBundlePath' in value]
    for config in configuration.get('TestConfigurations', []):
        targets.extend(config.get('TestTargets', []))
    targets = [target for target in targets
               if 'Aagedal Media Player Tests' in target.get('TestBundlePath', '')]
    if len(targets) != 1:
        parser.error('expected exactly one Aagedal Media Player Tests target')
    environment = targets[0].setdefault('EnvironmentVariables', {})
    environment['AAGEDAL_MPV_DECODER_RASTER_CANDIDATE'] = '1'
    environment['MPV_DECODER_RASTER_CASES'] = str(args.manifest.resolve(strict=True))
    environment.pop('MPV_DECODER_RASTER_STRESS_CYCLES', None)
    environment.pop('MPV_DECODER_RASTER_PLAYBACK_VALIDATION', None)
    environment.pop('LIVE_LOUPE_CASES', None)
    environment.pop('LIVE_LOUPE_COMPARISON_CASES', None)
    for key in ('LIVE_LOUPE_COMPARISON_SOAK_SECONDS', 'LIVE_LOUPE_COMPARISON_SOAK_CYCLES'):
        environment.pop(key, None)
    if args.comparison:
        environment['LIVE_LOUPE_COMPARISON_CASES'] = str(args.manifest.resolve(strict=True))
        environment['AAGEDAL_MPV_DECODER_RASTER_HWDEC'] = 'videotoolbox'
    for key in ('LIVE_LOUPE_SOAK_CASES', 'LIVE_LOUPE_SOAK_SECONDS', 'LIVE_LOUPE_SOAK_CYCLES'):
        environment.pop(key, None)
    if args.comparison and args.soak_seconds is not None:
        environment['LIVE_LOUPE_COMPARISON_SOAK_SECONDS'] = str(args.soak_seconds)
        environment['LIVE_LOUPE_COMPARISON_SOAK_CYCLES'] = str(args.soak_cycles)
    elif args.soak_seconds is not None:
        environment['LIVE_LOUPE_SOAK_CASES'] = str(args.manifest.resolve(strict=True))
        environment['LIVE_LOUPE_SOAK_SECONDS'] = str(args.soak_seconds)
        environment['LIVE_LOUPE_SOAK_CYCLES'] = str(args.soak_cycles)
    if args.live_viewer:
        environment['LIVE_LOUPE_CASES'] = str(args.manifest.resolve(strict=True))
    if args.playback:
        environment['MPV_DECODER_RASTER_PLAYBACK_VALIDATION'] = '1'
    if args.stress_cycles is not None:
        environment['MPV_DECODER_RASTER_STRESS_CYCLES'] = str(args.stress_cycles)
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.NamedTemporaryFile(suffix='.xctestrun', dir=args.xctestrun.resolve().parent) as file:
        file.write(plistlib.dumps(configuration))
        file.flush()
        test = ('LiveLoupeSessionTests/testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory' if args.comparison and args.soak_seconds is not None else
                'LiveLoupeSessionTests/testComparisonCanvasKeepsPairedLiveLoupesAndRestoresPausedInspection' if args.comparison else
                'LiveLoupeSessionTests/testSustainedConcurrentViewersKeepCadenceAndBoundMemory' if args.soak_seconds is not None else
                'LiveLoupeSessionTests/testPlaybackViewerKeepsTransportAndReleasesDecoder' if args.live_viewer else
                'LoupeTrackDecoderTests/testMPVNativeRasterOptInUsesCurrentDecoderFrameAndRevokesOnResume')
        command = ['xcodebuild', 'test-without-building', '-xctestrun', file.name,
                   '-destination', 'platform=macOS,arch=arm64',
                   '-parallel-testing-enabled', 'NO',
                   '-only-testing:Aagedal Media Player Tests/' + test,
                   '-resultBundlePath', str(args.output.resolve() / 'tests.xcresult')]
        with (args.output / 'xcodebuild.log').open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    # XCTest stdout can live only in the result bundle's action log.
    action = subprocess.run(['xcrun', 'xcresulttool', 'get', 'log', '--type', 'action',
                             '--path', str(args.output.resolve() / 'tests.xcresult')],
                            capture_output=True, text=True)
    (args.output / 'action.log').write_text(action.stdout + action.stderr)
    marker = (f'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: {args.soak_cycles} cycles, 2 pairs, 3 modes, {args.soak_seconds} seconds per mode,' if args.comparison and args.soak_seconds is not None else
              'MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen' if args.comparison else
              f'MPV_LIVE_LOUPE_SOAK_ACCEPTANCE: {args.soak_cycles} cycles, 4 cases, 2 pairs, {args.soak_seconds} seconds per case,' if args.soak_seconds is not None else
              'MPV_LIVE_LOUPE_ACCEPTANCE: 4 cases' if args.live_viewer else
              'MPV_LOUPE_PLAYBACK_ACCEPTANCE: 4 cases' if args.playback else
              'MPV_NATIVE_STRESS_ACCEPTANCE:' if args.stress_cycles else
              'MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases')
    combined = (args.output / 'xcodebuild.log').read_text() + action.stdout
    if result.returncode or action.returncode or marker not in combined:
        raise SystemExit('Native app acceptance failed or required marker missing; see ' + str(args.output))
    print('Native app acceptance passed; logs and xcresult:', args.output.resolve())


if __name__ == '__main__':
    main()
