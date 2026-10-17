#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run restored native-raster app fixtures, optionally with sustained UHD/HDR load.

Build for testing first using docs/MPV_NATIVE_RASTER_HANDOFF.md. This copies the
xctestrun beside the original so __TESTROOT__ keeps resolving to the built app.
It never changes the original test configuration or shipping dependency pins.
"""
import argparse
import json
import math
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


# Clear these in both sources of XCTest environment. A copied xctestrun alone
# does not isolate a run from workload flags inherited by xcodebuild.
WORKLOAD_ENVIRONMENT_KEYS = (
    'AAGEDAL_MPV_DECODER_RASTER_CANDIDATE',
    'MPV_DECODER_RASTER_CASES', 'MPV_DECODER_RASTER_FIXTURE',
    'MPV_DECODER_RASTER_STRESS_CYCLES', 'MPV_DECODER_RASTER_PLAYBACK_VALIDATION',
    'LIVE_LOUPE_CASES', 'LIVE_LOUPE_COMPARISON_CASES',
    'LIVE_LOUPE_COMPARISON_SOAK_SECONDS', 'LIVE_LOUPE_COMPARISON_SOAK_CYCLES',
    'LIVE_LOUPE_COMPARISON_ACTIVE_SCOPES', 'LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION',
    'LIVE_LOUPE_COMPARISON_SCOPE_FPS', 'LIVE_LOUPE_COMPARISON_SCOPE_PROVENANCE',
    'LIVE_LOUPE_SCOPE_PROVENANCE_CASES', 'LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS',
    'LIVE_LOUPE_COMPARISON_MEMORY_DIAGNOSTICS',
    'LIVE_LOUPE_SOAK_CASES', 'LIVE_LOUPE_SOAK_SECONDS', 'LIVE_LOUPE_SOAK_CYCLES',
)


def validate_memory_diagnostics(directory, cycles):
    """Require origin-aware observations and a separate post-gate checkpoint."""
    expected = {f'cycle-{cycle}.json' for cycle in range(cycles + 1)}
    if ({p.name for p in directory.glob('cycle-*.json')} != expected
            or not (directory / 'final-delayed.json').is_file()):
        raise SystemExit('Memory diagnostics incomplete; see ' + str(directory))

    def invalid():
        raise SystemExit('Memory diagnostics invalid; see ' + str(directory))

    def number(value):
        return type(value) in (int, float) and math.isfinite(value) and value >= 0

    pid = None
    previous = {}
    previous_uptime = None
    final_gate_uptime = None
    checkpoints = [f'cycle-{cycle}' for cycle in range(cycles + 1)] + ['final-delayed']
    for index, checkpoint in enumerate(checkpoints):
        cycle = min(index, cycles)
        delayed = checkpoint == 'final-delayed'
        try:
            sample = json.loads((directory / f'{checkpoint}.json').read_text())
        except (OSError, ValueError):
            invalid()
        if not isinstance(sample, dict):
            invalid()
        uptime = sample.get('uptime')
        gate = sample.get('gatePhysicalFootprintBytes')
        objects = sample.get('objects')
        if (type(sample.get('schemaVersion')) is not int or sample['schemaVersion'] != 2
                or sample.get('checkpoint') != checkpoint or sample.get('cycle') != cycle
                or type(sample.get('pid')) is not int or sample['pid'] <= 0
                or (pid is not None and sample['pid'] != pid)
                or type(sample.get('physicalFootprintBytes')) is not int
                or sample['physicalFootprintBytes'] < 0 or not number(uptime)
                or (previous_uptime is not None and uptime < previous_uptime)
                or (cycle > 0 and not delayed and (type(gate) is not int or gate < 0))
                or ((cycle == 0 or delayed) and gate is not None)
                or not isinstance(sample.get('retirement'), dict)
                or (cycle > 0 and not sample['retirement'])
                or not isinstance(objects, list) or (cycle == 0 and objects)
                or (cycle > 0 and not objects)):
            invalid()
        current = {}
        last_id = 0
        for row in objects:
            if not isinstance(row, dict):
                invalid()
            identity = row.get('id')
            origin = row.get('origin')
            match = re.fullmatch(r'cycle=([1-9][0-9]*),pair=(.+)', origin) if isinstance(origin, str) else None
            observed = row.get('observedUptime')
            teardown = row.get('teardownUptime')
            retired = row.get('firstRetiredCheckpoint')
            if (type(identity) is not int or identity <= last_id
                    or not isinstance(row.get('label'), str) or not row['label']
                    or not match or int(match[1]) > cycle
                    or type(row.get('alive')) is not bool or not number(observed) or observed > uptime
                    or 'teardownUptime' not in row or 'firstRetiredCheckpoint' not in row
                    or (teardown is not None and (not number(teardown) or teardown > uptime))
                    or (row['alive'] and retired is not None)
                    or (not row['alive'] and retired not in checkpoints[1:index + 1])):
                invalid()
            if identity in previous:
                prior = previous[identity]
                if (any(row[key] != prior[key] for key in ('label', 'origin', 'observedUptime'))
                        or (prior['teardownUptime'] is not None and teardown != prior['teardownUptime'])
                        or (prior['firstRetiredCheckpoint'] is not None and retired != prior['firstRetiredCheckpoint'])
                        or (not prior['alive'] and row['alive'])
                        or (prior['alive'] and not row['alive'] and retired != checkpoint)):
                    invalid()
            elif ((previous and identity <= max(previous))
                  or (not row['alive'] and retired != checkpoint)):
                invalid()
            current[identity] = row
            last_id = identity
        if not previous.keys() <= current.keys():
            invalid()
        if delayed and uptime - final_gate_uptime < 5:
            invalid()
        if cycle == cycles and not delayed:
            final_gate_uptime = uptime
        pid, previous, previous_uptime = sample['pid'], current, uptime


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
    parser.add_argument('--active-scopes', action='store_true', help='with sustained --comparison: mount production scopes and measure A/B/difference at selected resolution/update rate')
    parser.add_argument('--scope-resolution', type=int, choices=[360, 720, 1080, 1440],
                        help='with --active-scopes: production resolution (default 720)')
    parser.add_argument('--scope-fps', type=int, choices=range(5, 31), metavar='5–30',
                        help='with --active-scopes: production update rate (default 15)')
    parser.add_argument('--verify-difference-pixels', '--scope-provenance', action='store_true',
                        help='with --active-scopes: independently verify one completed difference publication per window and fresh capture resume')
    parser.add_argument('--memory-diagnostics', action='store_true',
                        help='with sustained --comparison: record cycle-end VM categories and weak object retirement')
    args = parser.parse_args()
    if args.memory_diagnostics and not (args.comparison and args.soak_seconds is not None):
        parser.error('--memory-diagnostics requires --comparison and --soak-seconds')
    if args.verify_difference_pixels and not args.active_scopes:
        parser.error('--verify-difference-pixels requires --active-scopes')
    if (args.scope_resolution is not None or args.scope_fps is not None) and not args.active_scopes:
        parser.error('--scope-resolution and --scope-fps require --active-scopes')
    args.scope_resolution = args.scope_resolution if args.scope_resolution is not None else 720
    args.scope_fps = args.scope_fps if args.scope_fps is not None else 15
    if args.active_scopes and not (args.comparison and args.soak_seconds is not None):
        parser.error('--active-scopes requires --comparison and --soak-seconds')
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
    process_environment = os.environ.copy()
    for key in WORKLOAD_ENVIRONMENT_KEYS:
        environment.pop(key, None)
        process_environment.pop(key, None)
    environment['AAGEDAL_MPV_DECODER_RASTER_CANDIDATE'] = '1'
    environment['MPV_DECODER_RASTER_CASES'] = str(args.manifest.resolve(strict=True))
    if args.memory_diagnostics:
        environment['LIVE_LOUPE_COMPARISON_MEMORY_DIAGNOSTICS'] = str(args.output.resolve() / 'memory-diagnostics')
    if args.verify_difference_pixels:
        environment['LIVE_LOUPE_COMPARISON_SCOPE_PROVENANCE'] = '1'
        environment['LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS'] = '1'
    if args.active_scopes:
        environment['LIVE_LOUPE_COMPARISON_ACTIVE_SCOPES'] = '1'
        environment['LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION'] = str(args.scope_resolution)
        environment['LIVE_LOUPE_COMPARISON_SCOPE_FPS'] = str(args.scope_fps)
        environment.pop('AAGEDAL_SCOPE_BACKEND', None)
        process_environment.pop('AAGEDAL_SCOPE_BACKEND', None)
    if args.comparison:
        environment['LIVE_LOUPE_COMPARISON_CASES'] = str(args.manifest.resolve(strict=True))
        environment['AAGEDAL_MPV_DECODER_RASTER_HWDEC'] = 'videotoolbox'
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
    (args.output / 'executed-configuration.plist').write_bytes(plistlib.dumps(configuration))
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
        (args.output / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
        with (args.output / 'xcodebuild.log').open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                    env=process_environment)
    # XCTest stdout can live only in the result bundle's action log.
    action = subprocess.run(['xcrun', 'xcresulttool', 'get', 'log', '--type', 'action',
                             '--path', str(args.output.resolve() / 'tests.xcresult')],
                            capture_output=True, text=True, env=process_environment)
    (args.output / 'action.log').write_text(action.stdout + action.stderr)
    marker = (f'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: {args.soak_cycles} cycles, 2 pairs, 3 modes, {args.soak_seconds} seconds per mode,' if args.comparison and args.soak_seconds is not None else
              'MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen' if args.comparison else
              f'MPV_LIVE_LOUPE_SOAK_ACCEPTANCE: {args.soak_cycles} cycles, 4 cases, 2 pairs, {args.soak_seconds} seconds per case,' if args.soak_seconds is not None else
              'MPV_LIVE_LOUPE_ACCEPTANCE: 4 cases' if args.live_viewer else
              'MPV_LOUPE_PLAYBACK_ACCEPTANCE: 4 cases' if args.playback else
              'MPV_NATIVE_STRESS_ACCEPTANCE:' if args.stress_cycles else
              'MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases')
    combined = (args.output / 'xcodebuild.log').read_text() + action.stdout
    scope_marker = (f'MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: {args.soak_cycles} cycles, 2 pairs, 3 modes, 3 scope sources, {args.soak_seconds} seconds per selection, resolution={args.scope_resolution}, targetFPS={args.scope_fps}')
    scope_receipt_matches = re.search(re.escape(scope_marker) + r'(?=$|[\s"\\])', combined)
    provenance_marker = (f'MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: {args.soak_cycles} cycles, 2 pairs, 3 modes, '
                         f'{args.soak_seconds} seconds per selection, resolution={args.scope_resolution}, targetFPS={args.scope_fps}, '
                         'exact difference pixels and occupied bins, capture retirement and resume')
    provenance_receipt_matches = re.search(re.escape(provenance_marker) + r'(?=$|[\s"\\])', combined)
    if (result.returncode or action.returncode or marker not in combined
            or (args.active_scopes and not scope_receipt_matches)
            or (args.verify_difference_pixels and not provenance_receipt_matches)):
        raise SystemExit('Native app acceptance failed or required marker missing; see ' + str(args.output))
    if args.memory_diagnostics:
        validate_memory_diagnostics(args.output / 'memory-diagnostics', args.soak_cycles)
    print('Native app acceptance passed; logs and xcresult:', args.output.resolve())


if __name__ == '__main__':
    main()
