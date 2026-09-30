#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('power', Path(__file__).with_name('check-programme-profile-power.py'))
power = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power)


class PowerTests(unittest.TestCase):
    def test_window_boundaries_and_event_types(self):
        log = '''2026-09-12 11:34:59 +0200 Sleep               \tOld event
2026-09-12 11:35:00 +0200 Sleep               \tEntering Sleep due to Clamshell
2026-09-12 11:35:01 +0200 Wake Requests       \tUnrelated requests excluded
2026-09-12 11:35:02 +0200 PM Client Acks      \tUnrelated clients excluded
2026-09-12 11:35:03 +0200 DarkWake            \tDark wake
2026-09-12 11:35:04 +0200 Wake                \tFull wake
2026-09-12 11:35:05 +0200 Sleep               \tLater event'''
        events = power.events_during(log, '2026-09-12 11:35:00', '2026-09-12 11:35:04')
        self.assertEqual([event['kind'] for event in events], ['Sleep', 'DarkWake', 'Wake'])

    def test_no_sleep_and_invalid_clock(self):
        self.assertEqual(power.events_during('', '2026-09-12 11:35:00', '2026-09-12 11:35:04'), [])
        with self.assertRaises(ValueError):
            power.events_during('', '2026-09-12 11:35:04', '2026-09-12 11:35:00')


class RunnerTests(unittest.TestCase):
    """Exercise exit paths without starting native decoders or Xcode builds."""

    def run_profile(self, mode):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scripts = root / 'scripts'
            scripts.mkdir()
            for name in ('profile-programme-loudness.sh', 'check-programme-profile-power.py'):
                shutil.copy(Path(__file__).with_name(name), scripts / name)
            # The real detector pins pmset's system path. In this isolated copy,
            # let its subprocess read the synthetic power log through PATH.
            detector = scripts / 'check-programme-profile-power.py'
            detector.write_text(detector.read_text().replace("'/usr/bin/pmset'", "'pmset'"))
            (scripts / 'validate-programme-loudness-profile.py').write_text(
                "import pathlib, sys\n(pathlib.Path(sys.argv[1]) / 'summary.json').write_text('{}')\n"
            )
            binaries = root / 'bin'
            binaries.mkdir()
            stubs = {
                'git': "print('test-source')",
                'sw_vers': "print('test-host')",
                'system_profiler': "print('test-hardware')",
                'pmset': """import os, pathlib, sys
if 'log' in sys.argv and os.environ['PROFILE_STUB_MODE'] == 'sleep':
    print(pathlib.Path(os.environ['PROFILE_STUB_CLOCK']).read_text() + ' +0200 Sleep               \\tTest sleep')
else:
    print('AC Power')
""",
                'xcodebuild': """import datetime, os, pathlib, plistlib, sys
if '-version' in sys.argv:
    print('test-Xcode')
elif 'build-for-testing' in sys.argv:
    if os.environ['PROFILE_STUB_MODE'] == 'build-failure':
        sys.exit(1)
    products = pathlib.Path(sys.argv[sys.argv.index('-derivedDataPath') + 1]) / 'Build/Products'
    products.mkdir(parents=True)
    (products / 'Original.xctestrun').write_bytes(plistlib.dumps(
        {'TestConfigurations': [{'TestTargets': [{}]}]}))
else:
    pathlib.Path(os.environ['PROFILE_STUB_CLOCK']).write_text(datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    pathlib.Path(sys.argv[sys.argv.index('-resultBundlePath') + 1]).mkdir()
    print('retained test diagnostics')
    sys.exit(1 if os.environ['PROFILE_STUB_MODE'] == 'test-failure' else 0)
""",
                'xcrun': """import pathlib, sys
output = pathlib.Path(sys.argv[sys.argv.index('--output-path') + 1])
output.mkdir()
(output / 'diagnostic.txt').write_text('partial workload')
""",
            }
            for name, body in stubs.items():
                executable = binaries / name
                executable.write_text('#!/usr/bin/python3\n' + body + '\n')
                executable.chmod(0o755)
            media = root / 'input.m4a'
            media.write_bytes(b'test input')
            artifacts = root / 'artifacts'
            derived = root / 'derived'
            environment = dict(os.environ, PATH=str(binaries) + ':' + os.environ['PATH'],
                               PROFILE_STUB_MODE=mode,
                               PROFILE_STUB_CLOCK=str(root / 'measurement-clock.txt'),
                               PROGRAMME_LOUDNESS_PROFILE_DERIVED_DATA=str(derived))
            result = subprocess.run(['/bin/zsh', str(scripts / 'profile-programme-loudness.sh'),
                                     str(artifacts), str(media)], env=environment,
                                    capture_output=True, text=True, timeout=30)
            files = {str(path.relative_to(artifacts)): path.read_text()
                     for path in artifacts.rglob('*') if path.is_file()}
            self.assertEqual(list((derived / 'Build/Products').glob('ProgrammeLoudnessProfile.*.xctestrun')), [])
            return result, files

    def test_failed_measurement_retains_power_and_partial_attachments(self):
        result, files = self.run_profile('test-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('profile.log', files)
        self.assertIn('attachments/diagnostic.txt', files)
        self.assertIn('power-start.txt', files)
        self.assertIn('power-end.txt', files)
        self.assertFalse(json.loads(files['power-events.json'])['sleepObserved'])
        self.assertNotIn('summary.json', files)

    def test_success_validates_after_retaining_power_and_attachments(self):
        result, files = self.run_profile('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('summary.json', files)
        self.assertIn('attachments/diagnostic.txt', files)
        self.assertIn('power-events.json', files)

    def test_build_failure_leaves_diagnostics_and_no_passing_summary(self):
        result, files = self.run_profile('build-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('build.log', files)
        self.assertNotIn('summary.json', files)
        self.assertNotIn('power-events.json', files)

    def test_sleep_rejection_preserves_attachments_without_passing_summary(self):
        result, files = self.run_profile('sleep')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('attachments/diagnostic.txt', files)
        self.assertTrue(json.loads(files['power-events.json'])['sleepObserved'])
        self.assertNotIn('summary.json', files)


if __name__ == '__main__': unittest.main()
