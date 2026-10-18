#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify soak selection, isolated environment and acceptance evidence gating."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('validate-mpv-native-app.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def write_memory_diagnostics(directory, cycles=3, post_test=False, scalar_only=False):
    directory.mkdir(exist_ok=True)
    checkpoints = [f'cycle-{n}' for n in range(cycles + 1)] + ['final-delayed']
    if post_test:
        checkpoints += ['post-test-entry', 'post-test-delayed']
    for index, checkpoint in enumerate(checkpoints):
        cycle = min(index, cycles)
        delayed = not checkpoint.startswith('cycle-')
        objects = [{'id': n, 'label': 'host', 'origin': f'cycle={n},pair=A/B',
                    'address': f'0x{n:016x}', 'alive': False, 'observedUptime': n * 10.0 - 2,
                    'teardownUptime': n * 10.0 - 1, 'firstRetiredCheckpoint': f'cycle-{n}'}
                   for n in range(1, cycle + 1)]
        (directory / f'{checkpoint}.json').write_text(json.dumps({
            'schemaVersion': 2, 'checkpoint': checkpoint, 'cycle': cycle, 'pid': 123,
            'uptime': cycle * 10.0 + max(0, index - cycles) * 5, 'physicalFootprintBytes': 10,
            'gatePhysicalFootprintBytes': 10 if cycle and not delayed else None,
            'objects': objects, 'sourceTestFinishedUptime': cycles * 10.0 + 5 if checkpoint.startswith('post-test-') else None,
            'sourceTestFinished': checkpoint.startswith('post-test-'),
            'observationKind': 'subsequent-test-scalar-only' if checkpoint.startswith('post-test-') else 'in-workload-scalar-only' if scalar_only else 'in-workload-relationships',
            'retirement': {'host': {'observed': cycle, 'alive': 0}} if cycle else {}}))


class RunnerTests(unittest.TestCase):
    def run_fixture(self, options, marker, *, failure=0, legacy=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = {'TestBundlePath': '__TESTROOT__/Aagedal Media Player Tests.xctest',
                      'EnvironmentVariables': {'PRESERVE': 'yes', 'LIVE_LOUPE_SOAK_SECONDS': '999',
                                               'LIVE_LOUPE_SOAK_CYCLES': '99', 'LIVE_LOUPE_SOAK_CASES': 'old',
                                               'LIVE_LOUPE_COMPARISON_CASES': 'old',
                                               'LIVE_LOUPE_SCOPE_PROVENANCE_CASES': 'old',
                                               'LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS': '1',
                                               'LIVE_LOUPE_COMPARISON_SOAK_SECONDS': '999',
                                               'LIVE_LOUPE_COMPARISON_SOAK_CYCLES': '99',
                                               'LIVE_LOUPE_COMPARISON_ACTIVE_SCOPES': '1',
                                               'LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION': '1080',
                                               'LIVE_LOUPE_COMPARISON_SCOPE_FPS': '27',
                                               'AAGEDAL_SCOPE_BACKEND': 'screenshot'}}
            # Deliberately independent of the runner's sanitation list: omitting
            # a workload key there must leave a hostile inherited value here.
            inherited = dict.fromkeys((
                'AAGEDAL_MPV_DECODER_RASTER_CANDIDATE',
                'MPV_DECODER_RASTER_CASES', 'MPV_DECODER_RASTER_FIXTURE',
                'MPV_DECODER_RASTER_STRESS_CYCLES', 'MPV_DECODER_RASTER_PLAYBACK_VALIDATION',
                'LIVE_LOUPE_CASES', 'LIVE_LOUPE_COMPARISON_CASES',
                'LIVE_LOUPE_COMPARISON_SOAK_SECONDS', 'LIVE_LOUPE_COMPARISON_SOAK_CYCLES',
                'LIVE_LOUPE_COMPARISON_ACTIVE_SCOPES', 'LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION',
                'LIVE_LOUPE_COMPARISON_SCOPE_FPS', 'LIVE_LOUPE_COMPARISON_SCOPE_PROVENANCE',
                'LIVE_LOUPE_SCOPE_PROVENANCE_CASES', 'LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS',
                'LIVE_LOUPE_COMPARISON_MEMORY_DIAGNOSTICS', 'LIVE_LOUPE_COMPARISON_POST_TEST_RETIREMENT',
                'LIVE_LOUPE_COMPARISON_SCALAR_MEMORY_DIAGNOSTICS',
                'LIVE_LOUPE_SOAK_CASES', 'LIVE_LOUPE_SOAK_SECONDS', 'LIVE_LOUPE_SOAK_CYCLES',
            ), 'inherited')
            workload_keys = set(inherited)
            target['EnvironmentVariables'].update(inherited)
            configuration = ({'Tests': target} if legacy else
                             {'TestConfigurations': [{'TestTargets': [target]}]})
            original = plistlib.dumps(configuration)
            source = root / 'original.xctestrun'
            source.write_bytes(original)
            manifest = root / 'fixtures.json'
            manifest.write_text('{}')
            observed = {'process_environments': []}
            inherited.update({'PRESERVE_PROCESS': 'yes', 'PRESERVE_TEST': 'yes', 'PATH': '/usr/bin:/bin',
                              'AAGEDAL_SCOPE_BACKEND': 'screenshot'})

            def run(command, **kwargs):
                observed['process_environments'].append(kwargs.get('env'))
                if command[0] == 'xcodebuild':
                    observed['command'] = command
                    observed['process_environment'] = kwargs['env']
                    copied = plistlib.loads(Path(command[command.index('-xctestrun') + 1]).read_bytes())
                    copied_target = copied['Tests'] if legacy else copied['TestConfigurations'][0]['TestTargets'][0]
                    observed['environment'] = copied_target['EnvironmentVariables']
                    self.assertEqual(plistlib.loads((root / 'output' / 'executed-configuration.plist').read_bytes()), copied)
                    self.assertEqual(json.loads((root / 'output' / 'command.json').read_text()), command)
                    if '--memory-diagnostics' in options:
                        directory = root / 'output' / 'memory-diagnostics'
                        cycles = int(observed['environment']['LIVE_LOUPE_COMPARISON_SOAK_CYCLES'])
                        write_memory_diagnostics(directory, cycles, post_test='--post-test-retirement' in options,
                                                 scalar_only='--scalar-memory-diagnostics' in options)
                    return subprocess.CompletedProcess(command, failure)
                return subprocess.CompletedProcess(command, 0, stdout=marker, stderr='')

            with patch.object(sys, 'argv', ['runner', str(source), str(manifest), str(root / 'output'), *options]), \
                 patch.object(runner.subprocess, 'run', side_effect=run), \
                 patch.dict(os.environ, inherited, clear=True), contextlib.redirect_stdout(io.StringIO()):
                runner.main()
            self.assertEqual(len(observed['process_environments']), 2)
            for environment in observed['process_environments']:
                self.assertIsNotNone(environment)
                self.assertFalse(workload_keys & environment.keys())
                self.assertEqual(environment['PRESERVE_PROCESS'], 'yes')
                self.assertEqual(environment['PATH'], '/usr/bin:/bin')
                if '--active-scopes' in options:
                    self.assertNotIn('AAGEDAL_SCOPE_BACKEND', environment)
                else:
                    self.assertEqual(environment['AAGEDAL_SCOPE_BACKEND'], 'screenshot')
            self.assertEqual(source.read_bytes(), original)
            self.assertEqual(list(root.glob('*.xctestrun')), [source])
            return observed

    def test_soak_selects_concurrent_test_and_requires_matching_receipt(self):
        observed = self.run_fixture(['--live-viewer', '--soak-seconds', '10'],
            'MPV_LIVE_LOUPE_SOAK_ACCEPTANCE: 3 cycles, 4 cases, 2 pairs, 10 seconds per case, baselineBytes=1')
        self.assertIn('-only-testing:Aagedal Media Player Tests/LiveLoupeSessionTests/testSustainedConcurrentViewersKeepCadenceAndBoundMemory', observed['command'])
        self.assertIn('platform=macOS,arch=arm64', observed['command'])
        environment = observed['environment']
        self.assertEqual(environment['LIVE_LOUPE_SOAK_SECONDS'], '10')
        self.assertEqual(environment['LIVE_LOUPE_SOAK_CYCLES'], '3')
        self.assertEqual(environment['PRESERVE'], 'yes')
        self.assertNotEqual(environment['LIVE_LOUPE_SOAK_CASES'], 'old')

    def test_short_run_clears_inherited_soak_environment_in_legacy_configuration(self):
        observed = self.run_fixture(['--live-viewer'], 'MPV_LIVE_LOUPE_ACCEPTANCE: 4 cases', legacy=True)
        self.assertFalse(any(key.startswith('LIVE_LOUPE_SOAK_') for key in observed['environment']))
        self.assertNotIn('LIVE_LOUPE_COMPARISON_CASES', observed['environment'])
        self.assertFalse(any(key.startswith('LIVE_LOUPE_COMPARISON_SOAK_') for key in observed['environment']))

    def test_rejects_short_or_mismatched_acceptance_even_on_successful_xcode_exit(self):
        for marker in ('MPV_LIVE_LOUPE_ACCEPTANCE: 4 cases',
                       'MPV_LIVE_LOUPE_SOAK_ACCEPTANCE: 3 cycles, 4 cases, 2 pairs, 10 seconds per case,'):
            with self.subTest(marker=marker), self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(['--live-viewer', '--soak-seconds', '20'], marker)

    def test_comparison_selects_canvas_test_and_requires_its_own_marker(self):
        marker = 'MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen'
        observed = self.run_fixture(['--comparison'], marker)
        self.assertIn('-only-testing:Aagedal Media Player Tests/LiveLoupeSessionTests/testComparisonCanvasKeepsPairedLiveLoupesAndRestoresPausedInspection', observed['command'])
        self.assertNotEqual(observed['environment']['LIVE_LOUPE_COMPARISON_CASES'], 'old')
        self.assertEqual(observed['environment']['AAGEDAL_MPV_DECODER_RASTER_HWDEC'], 'videotoolbox')
        self.assertNotIn('LIVE_LOUPE_SOAK_CASES', observed['environment'])
        self.assertFalse(any(key.startswith('LIVE_LOUPE_COMPARISON_SOAK_') for key in observed['environment']))
        for receipt in ('MPV_LIVE_LOUPE_ACCEPTANCE: 4 cases', marker):
            with self.subTest(receipt=receipt), self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(['--comparison'], receipt, failure=65 if receipt == marker else 0)

    def test_comparison_soak_selects_sustained_test_and_exact_receipt(self):
        marker = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 4 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        options = ['--comparison', '--soak-seconds', '10', '--soak-cycles', '4']
        observed = self.run_fixture(options, marker)
        self.assertIn('-only-testing:Aagedal Media Player Tests/LiveLoupeSessionTests/testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory', observed['command'])
        environment = observed['environment']
        self.assertEqual(environment['LIVE_LOUPE_COMPARISON_SOAK_SECONDS'], '10')
        self.assertEqual(environment['LIVE_LOUPE_COMPARISON_SOAK_CYCLES'], '4')
        self.assertFalse(any(key.startswith('LIVE_LOUPE_SOAK_') for key in environment))
        for receipt in ('MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen',
                        marker.replace('4 cycles', '3 cycles'), marker.replace('10 seconds', '30 seconds')):
            with self.subTest(receipt=receipt), self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(options, receipt)
        with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
            self.run_fixture(options, marker, failure=65)

    def test_xcode_failure_cannot_be_overridden_by_acceptance_marker(self):
        with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
            self.run_fixture(['--live-viewer', '--soak-seconds', '10'],
                'MPV_LIVE_LOUPE_SOAK_ACCEPTANCE: 3 cycles, 4 cases, 2 pairs, 10 seconds per case,', failure=65)

    def test_active_scopes_requires_both_matching_receipts_and_successful_xcode(self):
        options = ['--comparison', '--soak-seconds', '10', '--soak-cycles', '4', '--active-scopes']
        comparison = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 4 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        scopes = ('MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 4 cycles, 2 pairs, 3 modes, '
                  '3 scope sources, 10 seconds per selection, resolution=720, targetFPS=15')
        observed = self.run_fixture(options, comparison + '\n' + scopes)
        self.assertIn('-only-testing:Aagedal Media Player Tests/LiveLoupeSessionTests/testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory', observed['command'])
        self.assertEqual(observed['environment']['LIVE_LOUPE_COMPARISON_ACTIVE_SCOPES'], '1')
        self.assertEqual(observed['environment']['LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION'], '720')
        self.assertEqual(observed['environment']['LIVE_LOUPE_COMPARISON_SCOPE_FPS'], '15')
        self.assertNotIn('AAGEDAL_SCOPE_BACKEND', observed['environment'])
        for receipt in (comparison, scopes,
                        comparison + '\n' + scopes.replace('4 cycles', '3 cycles'),
                        comparison + '\n' + scopes.replace('10 seconds', '30 seconds'),
                        comparison + '\n' + scopes.replace('resolution=720', 'resolution=64'),
                        comparison + '\n' + scopes.replace('targetFPS=15', 'targetFPS=30')):
            with self.subTest(receipt=receipt), self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(options, receipt)
        with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
            self.run_fixture(options, comparison + '\n' + scopes, failure=65)

    def test_ordinary_runs_clear_inherited_active_scopes_and_preserve_backend_override(self):
        cases = [([], 'MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases'),
                 (['--comparison'], 'MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen'),
                 (['--comparison', '--soak-seconds', '10'],
                  'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,')]
        for options, marker in cases:
            for legacy in (False, True):
                with self.subTest(options=options, legacy=legacy):
                    environment = self.run_fixture(options, marker, legacy=legacy)['environment']
                    for key in ('LIVE_LOUPE_COMPARISON_ACTIVE_SCOPES', 'LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION',
                                'LIVE_LOUPE_COMPARISON_SCOPE_FPS', 'LIVE_LOUPE_COMPARISON_SCOPE_PROVENANCE',
                                'LIVE_LOUPE_SCOPE_PROVENANCE_CASES'):
                        self.assertNotIn(key, environment)
                    self.assertEqual(environment['AAGEDAL_SCOPE_BACKEND'], 'screenshot')

    def test_selected_scope_settings_require_exact_receipt_in_both_configuration_formats(self):
        comparison = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        for resolution, fps in [(1440, 30), (360, 5), (1080, 21), (720, 15)]:
            options = ['--comparison', '--soak-seconds', '10', '--active-scopes',
                       '--scope-resolution', str(resolution), '--scope-fps', str(fps)]
            scopes = ('MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, '
                      f'3 scope sources, 10 seconds per selection, resolution={resolution}, targetFPS={fps}')
            for legacy in (False, True):
                with self.subTest(resolution=resolution, fps=fps, legacy=legacy):
                    environment = self.run_fixture(options, comparison + '\n' + scopes, legacy=legacy)['environment']
                    self.assertEqual(environment['LIVE_LOUPE_COMPARISON_SCOPE_RESOLUTION'], str(resolution))
                    self.assertEqual(environment['LIVE_LOUPE_COMPARISON_SCOPE_FPS'], str(fps))
                    for receipt in (scopes.replace(f'resolution={resolution}', 'resolution=64'),
                                    scopes.replace(f'targetFPS={fps}', 'targetFPS=99'),
                                    scopes + '0', scopes + '.5'):
                        with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                            self.run_fixture(options, comparison + '\n' + receipt, legacy=legacy)

    def test_provenance_soak_requires_three_exact_receipts(self):
        options = ['--comparison', '--active-scopes', '--verify-difference-pixels',
                   '--soak-seconds', '10', '--scope-resolution', '1440', '--scope-fps', '30']
        comparison = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        scopes = ('MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, '
                  '3 scope sources, 10 seconds per selection, resolution=1440, targetFPS=30')
        provenance = ('MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, '
                      '10 seconds per selection, resolution=1440, targetFPS=30, '
                      'exact difference pixels and occupied bins, capture retirement and resume')
        for legacy in (False, True):
            with self.subTest(legacy=legacy):
                observed = self.run_fixture(options, '\n'.join([comparison, scopes, provenance]), legacy=legacy)
                environment = observed['environment']
                self.assertEqual(environment['LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS'], '1')
                self.assertNotIn('LIVE_LOUPE_SCOPE_PROVENANCE_CASES', environment)
                for receipt in ('\n'.join([comparison, scopes]), '\n'.join([comparison, provenance]),
                                '\n'.join([scopes, provenance]),
                                '\n'.join([comparison, scopes, provenance.replace('3 cycles', '4 cycles')]),
                                '\n'.join([comparison, scopes, provenance.replace('10 seconds', '20 seconds')]),
                                '\n'.join([comparison, scopes, provenance.replace('resolution=1440', 'resolution=720')]),
                                '\n'.join([comparison, scopes, provenance.replace('targetFPS=30', 'targetFPS=15')]),
                                '\n'.join([comparison, scopes, provenance + 'garbage'])):
                    with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                        self.run_fixture(options, receipt, legacy=legacy)
                with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                    self.run_fixture(options, '\n'.join([comparison, scopes, provenance]), failure=65, legacy=legacy)

    def test_all_modes_clear_inherited_provenance_workloads(self):
        comparison = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        scopes = ('MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, '
                  '3 scope sources, 10 seconds per selection, resolution=720, targetFPS=15')
        for options, marker in [([], 'MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases'),
                                (['--comparison'], 'MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen'),
                                (['--comparison', '--soak-seconds', '10', '--active-scopes'], comparison + '\n' + scopes)]:
            for legacy in (False, True):
                with self.subTest(options=options, legacy=legacy), patch.dict(os.environ, {
                    'LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS': '1',
                    'LIVE_LOUPE_SCOPE_PROVENANCE_CASES': 'old',
                    'AAGEDAL_SCOPE_BACKEND': 'screenshot', 'PRESERVE_TEST': 'yes'}):
                    observed = self.run_fixture(options, marker, legacy=legacy)
                    for key in ('LIVE_LOUPE_COMPARISON_VERIFY_DIFFERENCE_PIXELS', 'LIVE_LOUPE_SCOPE_PROVENANCE_CASES'):
                        self.assertNotIn(key, observed['environment'])
                        self.assertNotIn(key, observed['process_environment'])
                    self.assertEqual(observed['process_environment']['PRESERVE_TEST'], 'yes')
                    if '--active-scopes' in options:
                        self.assertNotIn('AAGEDAL_SCOPE_BACKEND', observed['process_environment'])

    def test_provenance_requires_all_exact_receipts_in_both_configuration_formats(self):
        options = ['--comparison', '--soak-seconds', '20', '--soak-cycles', '4',
                   '--active-scopes', '--scope-provenance', '--scope-resolution', '1440', '--scope-fps', '30']
        comparison = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 4 cycles, 2 pairs, 3 modes, 20 seconds per mode,'
        scopes = ('MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 4 cycles, 2 pairs, 3 modes, '
                  '3 scope sources, 20 seconds per selection, resolution=1440, targetFPS=30')
        provenance = ('MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: 4 cycles, 2 pairs, 3 modes, '
                      '20 seconds per selection, resolution=1440, targetFPS=30, '
                      'exact difference pixels and occupied bins, capture retirement and resume')
        for legacy in (False, True):
            with self.subTest(legacy=legacy):
                observed = self.run_fixture(options, '\n'.join((comparison, scopes, provenance)), legacy=legacy)
                self.assertEqual(observed['environment']['LIVE_LOUPE_COMPARISON_SCOPE_PROVENANCE'], '1')
                self.assertNotIn('LIVE_LOUPE_SCOPE_PROVENANCE_CASES', observed['environment'])
                for receipts in ((comparison, scopes), (comparison, provenance), (scopes, provenance)):
                    with self.subTest(receipts=receipts), self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                        self.run_fixture(options, '\n'.join(receipts), legacy=legacy)
                for receipt in (provenance.replace('4 cycles', '3 cycles'),
                                provenance.replace('2 pairs', '1 pairs'),
                                provenance.replace('3 modes', '2 modes'),
                                provenance.replace('20 seconds', '10 seconds'),
                                provenance.replace('resolution=1440', 'resolution=720'),
                                provenance.replace('targetFPS=30', 'targetFPS=15'),
                                provenance + '0', provenance + '.5', provenance + '_extra',
                                provenance.replace('_SOAK_ACCEPTANCE', '_ACCEPTANCE')):
                    with self.subTest(receipt=receipt), self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                        self.run_fixture(options, '\n'.join((comparison, scopes, receipt)), legacy=legacy)
                with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                    self.run_fixture(options, '\n'.join((comparison, scopes, provenance)), failure=65, legacy=legacy)

    def test_active_scopes_without_provenance_clears_inherited_provenance_opt_ins(self):
        comparison = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        scopes = ('MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, '
                  '3 scope sources, 10 seconds per selection, resolution=720, targetFPS=15')
        for legacy in (False, True):
            observed = self.run_fixture(['--comparison', '--soak-seconds', '10', '--active-scopes'],
                                        comparison + '\n' + scopes, legacy=legacy)
            self.assertNotIn('LIVE_LOUPE_COMPARISON_SCOPE_PROVENANCE', observed['environment'])
            self.assertNotIn('LIVE_LOUPE_SCOPE_PROVENANCE_CASES', observed['environment'])

    def test_memory_diagnostics_are_explicit_and_isolated(self):
        marker = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        for legacy in (False, True):
            options = ['--comparison', '--soak-seconds', '10']
            ordinary = self.run_fixture(options, marker, legacy=legacy)
            self.assertNotIn('LIVE_LOUPE_COMPARISON_MEMORY_DIAGNOSTICS', ordinary['environment'])
            diagnostic = self.run_fixture(options + ['--memory-diagnostics'], marker, legacy=legacy)
            self.assertTrue(diagnostic['environment']['LIVE_LOUPE_COMPARISON_MEMORY_DIAGNOSTICS'].endswith('/output/memory-diagnostics'))
            self.assertNotIn('LIVE_LOUPE_COMPARISON_MEMORY_DIAGNOSTICS', diagnostic['process_environment'])
            with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(options + ['--memory-diagnostics'], marker, failure=65, legacy=legacy)

    def test_scalar_diagnostics_are_explicit_and_isolated(self):
        marker = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        options = ['--comparison', '--soak-seconds', '10', '--memory-diagnostics']
        for legacy in (False, True):
            ordinary = self.run_fixture(options, marker, legacy=legacy)
            self.assertNotIn('LIVE_LOUPE_COMPARISON_SCALAR_MEMORY_DIAGNOSTICS', ordinary['environment'])
            observed = self.run_fixture(options + ['--scalar-memory-diagnostics'], marker, legacy=legacy)
            self.assertEqual(observed['environment']['LIVE_LOUPE_COMPARISON_SCALAR_MEMORY_DIAGNOSTICS'], '1')
            self.assertNotIn('LIVE_LOUPE_COMPARISON_SCALAR_MEMORY_DIAGNOSTICS', observed['process_environment'])
            with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(options + ['--scalar-memory-diagnostics'], marker, failure=65, legacy=legacy)

    def test_scalar_diagnostics_reject_relationships_and_mixed_modes(self):
        for post_test in (False, True):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                write_memory_diagnostics(root, post_test=post_test, scalar_only=True)
                runner.validate_memory_diagnostics(root, 3, post_test=post_test, scalar_only=True)
                with self.assertRaisesRegex(SystemExit, 'invalid'):
                    runner.validate_memory_diagnostics(root, 3, post_test=post_test)
                for checkpoint in ('cycle-1', 'final-delayed'):
                    file = root / f'{checkpoint}.json'
                    original = file.read_text()
                    for relationship in ('window', 'host', 'controller', 'session', 'view', 'unknown'):
                        sample = json.loads(original)
                        sample['objects'][0][relationship] = {}
                        file.write_text(json.dumps(sample))
                        with self.assertRaisesRegex(SystemExit, 'invalid'):
                            runner.validate_memory_diagnostics(root, 3, post_test=post_test, scalar_only=True)
                    sample = json.loads(original)
                    sample['observationKind'] = 'in-workload-relationships'
                    file.write_text(json.dumps(sample))
                    with self.assertRaisesRegex(SystemExit, 'invalid'):
                        runner.validate_memory_diagnostics(root, 3, post_test=post_test, scalar_only=True)
                    file.write_text(original)

    def test_post_test_retirement_is_explicit_and_requires_matching_marker(self):
        marker = 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,'
        receipt = 'MPV_COMPARISON_POST_TEST_RETIREMENT: same-process subsequent test, scalar-only, 5 second delay'
        options = ['--comparison', '--soak-seconds', '10', '--memory-diagnostics']
        for legacy in (False, True):
            ordinary = self.run_fixture(options, marker, legacy=legacy)
            self.assertNotIn('LIVE_LOUPE_COMPARISON_POST_TEST_RETIREMENT', ordinary['environment'])
            observed = self.run_fixture(options + ['--post-test-retirement'], marker + '\n' + receipt, legacy=legacy)
            self.assertEqual(observed['environment']['LIVE_LOUPE_COMPARISON_POST_TEST_RETIREMENT'], '1')
            self.assertIn('-only-testing:Aagedal Media Player Tests/LiveLoupeSessionTests/testZZComparisonPostTestRetirement', observed['command'])
            with self.assertRaisesRegex(SystemExit, 'marker missing'):
                self.run_fixture(options + ['--post-test-retirement'], marker, legacy=legacy)
            with self.assertRaisesRegex(SystemExit, 'acceptance failed'):
                self.run_fixture(options + ['--post-test-retirement'], marker + '\n' + receipt, failure=65, legacy=legacy)

    def test_post_test_observations_require_completion_identity_and_delay(self):
        cases = [
            ('post-test-entry', lambda s: s.update(sourceTestFinished=False)),
            ('post-test-entry', lambda s: s.update(observationKind='in-workload-relationships')),
            ('post-test-entry', lambda s: s.update(pid=456)),
            ('post-test-entry', lambda s: s.update(sourceTestFinishedUptime=34.99)),
            ('post-test-entry', lambda s: s.update(sourceTestFinishedUptime=41)),
            ('post-test-delayed', lambda s: s.update(sourceTestFinishedUptime=36)),
            ('post-test-entry', lambda s: s['objects'][0].update(address='0xbeef')),
            ('post-test-entry', lambda s: s['objects'][0].pop('address')),
            ('post-test-entry', lambda s: s.update(gatePhysicalFootprintBytes=10)),
            ('post-test-entry', lambda s: s['objects'][0].update(window={})),
            ('post-test-entry', lambda s: s['objects'][0].update(origin='cycle=1,pair=C/D')),
            ('post-test-delayed', lambda s: s.update(uptime=44.99)),
            ('post-test-delayed', lambda s: s['objects'].pop(0)),
        ]
        for checkpoint, mutate in cases:
            with self.subTest(checkpoint=checkpoint), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                write_memory_diagnostics(root, post_test=True)
                runner.validate_memory_diagnostics(root, 3, post_test=True)
                file = root / f'{checkpoint}.json'
                sample = json.loads(file.read_text()); mutate(sample)
                file.write_text(json.dumps(sample))
                with self.assertRaisesRegex(SystemExit, 'invalid'):
                    runner.validate_memory_diagnostics(root, 3, post_test=True)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_memory_diagnostics(root)
            with self.assertRaisesRegex(SystemExit, 'incomplete'):
                runner.validate_memory_diagnostics(root, 3, post_test=True)

    def test_memory_diagnostics_require_all_gate_and_delayed_checkpoints(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(SystemExit, 'incomplete'):
                runner.validate_memory_diagnostics(root, 3)
            write_memory_diagnostics(root)
            runner.validate_memory_diagnostics(root, 3)
            (root / 'final-delayed.json').unlink()
            with self.assertRaisesRegex(SystemExit, 'incomplete'):
                runner.validate_memory_diagnostics(root, 3)
            write_memory_diagnostics(root)
            (root / 'cycle-2.json').unlink()
            with self.assertRaisesRegex(SystemExit, 'incomplete'):
                runner.validate_memory_diagnostics(root, 3)

    def test_memory_diagnostics_accept_retirement_first_observed_after_final_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_memory_diagnostics(root)
            for checkpoint in ('cycle-1', 'cycle-2', 'cycle-3', 'final-delayed'):
                file = root / f'{checkpoint}.json'
                sample = json.loads(file.read_text())
                row = sample['objects'][0]
                row.update(alive=checkpoint != 'final-delayed',
                           firstRetiredCheckpoint='final-delayed' if checkpoint == 'final-delayed' else None)
                file.write_text(json.dumps(sample))
            runner.validate_memory_diagnostics(root, 3)

    def test_memory_diagnostics_accept_late_registration_after_origin_teardown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_memory_diagnostics(root)
            file = root / 'final-delayed.json'
            sample = json.loads(file.read_text())
            sample['objects'].append({
                'id': 4, 'address': '0x4', 'label': 'scopeWorker', 'origin': 'cycle=3,pair=A/B',
                'alive': True, 'observedUptime': 34.0, 'teardownUptime': 29.0,
                'firstRetiredCheckpoint': None})
            sample['retirement']['scopeWorker'] = {'observed': 1, 'alive': 1}
            file.write_text(json.dumps(sample))
            runner.validate_memory_diagnostics(root, 3)

    def test_memory_diagnostics_reject_stale_or_inconsistent_object_evidence(self):
        cases = [
            ('cycle-3', lambda s: s.update(pid=456)),
            ('cycle-3', lambda s: s.update(schemaVersion=1)),
            ('cycle-3', lambda s: s.pop('schemaVersion')),
            ('cycle-3', lambda s: s.update(checkpoint='cycle-2')),
            ('cycle-3', lambda s: s.update(objects=[])),
            ('cycle-0', lambda s: s.update(objects=[{}])),
            ('cycle-3', lambda s: s['objects'][0].update(origin='cycle=1,pair=C/D')),
            ('cycle-3', lambda s: s['objects'][0].update(label='window')),
            ('cycle-3', lambda s: s['objects'][0].update(observedUptime=9)),
            ('cycle-3', lambda s: s['objects'][0].update(teardownUptime=9.5)),
            ('cycle-3', lambda s: s['objects'][0].update(alive=True, firstRetiredCheckpoint=None)),
            ('cycle-3', lambda s: s['objects'][0].update(firstRetiredCheckpoint='cycle-3')),
            ('cycle-3', lambda s: s['objects'][0].update(firstRetiredCheckpoint=None)),
            ('cycle-3', lambda s: s['objects'][0].update(id=True)),
            ('cycle-3', lambda s: s['objects'][1].update(id=1)),
            ('cycle-3', lambda s: s['objects'].reverse()),
            ('cycle-3', lambda s: s['objects'].pop(0)),
            ('cycle-3', lambda s: s['objects'][-1].update(origin='cycle=4,pair=A/B')),
            ('cycle-3', lambda s: s['objects'][-1].update(observedUptime=float('nan'))),
            ('cycle-3', lambda s: s.update(uptime=float('inf'))),
            ('final-delayed', lambda s: s.update(uptime=34.999)),
            ('final-delayed', lambda s: s.update(gatePhysicalFootprintBytes=10)),
            ('final-delayed', lambda s: s.update(cycle=4)),
        ]
        for index, (checkpoint, mutate) in enumerate(cases):
            with self.subTest(checkpoint=checkpoint, mutation=index), \
                 tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                write_memory_diagnostics(root)
                file = root / f'{checkpoint}.json'
                sample = json.loads(file.read_text())
                mutate(sample)
                file.write_text(json.dumps(sample))
                with self.assertRaisesRegex(SystemExit, 'invalid'):
                    runner.validate_memory_diagnostics(root, 3)

    def test_invalid_soak_arguments_fail_before_reading_inputs(self):
        for options in (['--scalar-memory-diagnostics'], ['--comparison', '--soak-seconds', '10', '--scalar-memory-diagnostics'], ['--post-test-retirement'], ['--comparison', '--soak-seconds', '10', '--post-test-retirement'], ['--memory-diagnostics'], ['--comparison', '--memory-diagnostics'],
                        ['--live-viewer', '--soak-seconds', '10', '--memory-diagnostics'],
                        ['--scope-provenance'], ['--comparison', '--scope-provenance'],
                        ['--comparison', '--soak-seconds', '10', '--scope-provenance'],
                        ['--verify-difference-pixels'],
                        ['--comparison', '--verify-difference-pixels'],
                        ['--comparison', '--soak-seconds', '10', '--verify-difference-pixels'],
                        ['--live-viewer', '--soak-seconds', '10', '--verify-difference-pixels'],
                        ['--scope-resolution', '1440'], ['--scope-fps', '30'],
                        ['--comparison', '--soak-seconds', '10', '--active-scopes', '--scope-resolution', '64'],
                        ['--comparison', '--soak-seconds', '10', '--active-scopes', '--scope-fps', '31'],
                        ['--comparison', '--soak-seconds', '10', '--active-scopes', '--scope-fps', '4'],
                        ['--comparison', '--soak-seconds', '10', '--active-scopes', '--scope-fps', '15.5'],
                        ['--active-scopes'], ['--comparison', '--active-scopes'],
                        ['--live-viewer', '--soak-seconds', '10', '--active-scopes'],
                        ['--soak-seconds', '10', '--active-scopes'],
                        ['--comparison', '--live-viewer'], ['--comparison', '--playback'],
                        ['--comparison', '--stress-cycles', '3'], ['--comparison', '--soak-seconds', '9'],
                        ['--soak-seconds', '10'], ['--live-viewer', '--soak-seconds', '9'],
                        ['--live-viewer', '--soak-seconds', '3601'], ['--soak-cycles', '3'],
                        ['--live-viewer', '--soak-seconds', '10', '--soak-cycles', '2'],
                        ['--live-viewer', '--soak-seconds', '10', '--soak-cycles', '101']):
            with self.subTest(options=options), patch.object(sys, 'argv', ['runner', 'missing', 'missing', 'missing', *options]), \
                 contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failure:
                runner.main()
            self.assertEqual(failure.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
