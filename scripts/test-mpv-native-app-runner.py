#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify soak selection, isolated environment and acceptance evidence gating."""
import contextlib
import importlib.util
import io
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


class RunnerTests(unittest.TestCase):
    def run_fixture(self, options, marker, *, failure=0, legacy=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = {'TestBundlePath': '__TESTROOT__/Aagedal Media Player Tests.xctest',
                      'EnvironmentVariables': {'PRESERVE': 'yes', 'LIVE_LOUPE_SOAK_SECONDS': '999',
                                               'LIVE_LOUPE_SOAK_CYCLES': '99', 'LIVE_LOUPE_SOAK_CASES': 'old',
                                               'LIVE_LOUPE_COMPARISON_CASES': 'old',
                                               'LIVE_LOUPE_COMPARISON_SOAK_SECONDS': '999',
                                               'LIVE_LOUPE_COMPARISON_SOAK_CYCLES': '99'}}
            configuration = ({'Tests': target} if legacy else
                             {'TestConfigurations': [{'TestTargets': [target]}]})
            original = plistlib.dumps(configuration)
            source = root / 'original.xctestrun'
            source.write_bytes(original)
            manifest = root / 'fixtures.json'
            manifest.write_text('{}')
            observed = {}

            def run(command, **kwargs):
                if command[0] == 'xcodebuild':
                    observed['command'] = command
                    copied = plistlib.loads(Path(command[command.index('-xctestrun') + 1]).read_bytes())
                    copied_target = copied['Tests'] if legacy else copied['TestConfigurations'][0]['TestTargets'][0]
                    observed['environment'] = copied_target['EnvironmentVariables']
                    return subprocess.CompletedProcess(command, failure)
                return subprocess.CompletedProcess(command, 0, stdout=marker, stderr='')

            with patch.object(sys, 'argv', ['runner', str(source), str(manifest), str(root / 'output'), *options]), \
                 patch.object(runner.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                runner.main()
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

    def test_invalid_soak_arguments_fail_before_reading_inputs(self):
        for options in (['--comparison', '--live-viewer'], ['--comparison', '--playback'],
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
