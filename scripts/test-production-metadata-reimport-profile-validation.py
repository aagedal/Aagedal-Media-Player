#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'reimport_validator', Path(__file__).with_name('validate-production-metadata-reimport-profile.py'))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def record():
    return {
        'inputIndex': 0, 'processIdentifier': 100, 'file': 'camera.mxf', 'inputFileBytes': 2000,
        'importCount': 3, 'sampleIntervalMilliseconds': 10,
        'inputStrategy': 'distinctDirectorySymlinkURLsPreservingSidecars',
        'initialResidentBytes': 10, 'initialLifetimePeakResidentBytes': 20,
        'initialOpenDescriptors': 10, 'revisitWallSeconds': 0.001, 'revisitParity': True,
        'afterRevisitResidentBytes': 22, 'afterRevisitLifetimePeakResidentBytes': 35,
        'afterRevisitOpenDescriptors': 11,
        'metadata': {
            'durationSeconds': 100, 'formatName': 'mxf', 'sizeBytes': 2000,
            'videoStreamCount': 1, 'audioStreamCount': 0, 'subtitleStreamCount': 0,
            'chapterCount': 0, 'videoStreams': [{'codec': 'h264'}], 'audioStreams': [],
        },
        'imports': [{
            'importIndex': index, 'sampleCount': 2, 'loadWallSeconds': 0.1,
            'cachedReadWallSeconds': 0.001, 'cacheParity': True, 'baselineParity': True,
            'beforeLoadResidentBytes': 10 + index, 'sampledPeakResidentBytes': 30,
            'afterLoadResidentBytes': 25, 'afterLoadLifetimePeakResidentBytes': 35,
            'afterLocalReleaseResidentBytes': 20 + index,
            'afterLocalReleaseLifetimePeakResidentBytes': 35,
            'afterLocalReleaseOpenDescriptors': 11,
        } for index in range(3)],
    }


class ReimportProfileValidationTests(unittest.TestCase):
    def test_valid_fresh_inputs_sorted_and_explicit_resource_bounds(self):
        first = record()
        second = copy.deepcopy(first)
        second.update(inputIndex=1, processIdentifier=101)
        self.assertEqual([row['inputIndex'] for row in validator.validate(
            [second, first], 2, 3, 2, 1)], [0, 1])

    def test_missing_duplicate_or_invalid_identity_is_rejected(self):
        for rows, count in [([], 1), ([record()], 2), ([record(), record()], 2)]:
            with self.subTest(count=count), self.assertRaises(ValueError):
                validator.validate(rows, count, 3)
        row = record()
        row['processIdentifier'] = True
        with self.assertRaises(ValueError):
            validator.validate([row], 1, 3)

    def test_missing_observations_or_alias_strategy_are_rejected(self):
        for key, value in [('importCount', 2), ('imports', []), ('inputStrategy', 'sameURL')]:
            row = record()
            row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1, 3)

    def test_parity_revisit_duration_and_initial_memory_are_enforced(self):
        for key, value in [('revisitParity', False), ('revisitWallSeconds', float('nan')),
                           ('initialLifetimePeakResidentBytes', 9)]:
            row = record()
            row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1, 3)
        row = record()
        row['metadata']['durationSeconds'] = 59
        with self.assertRaises(ValueError):
            validator.validate([row], 1, 3)

    def test_bad_import_observations_are_rejected(self):
        for key, value in [('importIndex', 2), ('sampleCount', 0), ('cacheParity', False),
                           ('baselineParity', False), ('loadWallSeconds', 0),
                           ('sampledPeakResidentBytes', 24),
                           ('afterLoadLifetimePeakResidentBytes', 19),
                           ('afterLocalReleaseLifetimePeakResidentBytes', 34),
                           ('afterLocalReleaseOpenDescriptors', True)]:
            row = record()
            row['imports'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1, 3)

    def test_descriptor_growth_is_always_bounded(self):
        row = record()
        row['imports'][1]['afterLocalReleaseOpenDescriptors'] = 15
        with self.assertRaisesRegex(ValueError, 'descriptor growth'):
            validator.validate([row], 1, 3)

    def test_memory_budget_checks_middle_cycle_even_if_final_recovers(self):
        row = record()
        row['imports'][1]['afterLocalReleaseResidentBytes'] = 30
        with self.assertRaisesRegex(ValueError, 'Resident growth'):
            validator.validate([row], 1, 3, 5)
        self.assertEqual(validator.validate([row], 1, 3), [row])

    def test_invalid_budgets_and_counts_are_rejected(self):
        for arguments in [(True, 3, None, 4), (1, True, None, 4), (1, 1001, None, 4),
                          (1, 3, -1, 4), (1, 3, None, -1)]:
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                validator.validate([record()], *arguments)

    def test_revisit_resources_are_validated_and_bounded(self):
        for key, value in [('afterRevisitResidentBytes', 30),
                           ('afterRevisitLifetimePeakResidentBytes', 34),
                           ('afterRevisitOpenDescriptors', 15)]:
            row = record()
            row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1, 3, 5)

    def test_failed_revalidation_removes_previous_passing_receipts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            attachments = root / 'attachments'
            attachments.mkdir()
            (attachments / 'profile.txt').write_text(
                'PRODUCTION_METADATA_REIMPORT_PROFILE ' + json.dumps(record()) + '\n')
            script = str(Path(__file__).with_name('validate-production-metadata-reimport-profile.py'))
            result = subprocess.run([sys.executable, script, str(root), '1', '3'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / 'summary.json').exists())
            self.assertTrue((root / 'validation.json').exists())
            result = subprocess.run([sys.executable, script, str(root), '1', '3',
                                     '--max-descriptor-growth', '0'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'summary.json').exists())
            self.assertFalse((root / 'validation.json').exists())

    def test_invalid_runner_configuration_fails_before_artifact_creation(self):
        configurations = [
            {'METADATA_MEMORY_PROFILE_REIMPORT_COUNT': '1'},
            {'METADATA_MEMORY_PROFILE_REIMPORT_COUNT': '1001'},
            {'METADATA_MEMORY_PROFILE_REIMPORT_COUNT': '2+2'},
            {'METADATA_MEMORY_PROFILE_REIMPORT_COUNT': '3',
             'METADATA_MEMORY_PROFILE_MAX_RESIDENT_GROWTH_MIB': '-1'},
            {'METADATA_MEMORY_PROFILE_REIMPORT_COUNT': '3',
             'METADATA_MEMORY_PROFILE_MAX_DESCRIPTOR_GROWTH': 'nan'},
            {'METADATA_MEMORY_PROFILE_MAX_RESIDENT_GROWTH_MIB': '32'},
            {'METADATA_MEMORY_PROFILE_MAX_DESCRIPTOR_GROWTH': '4'},
        ]
        runner = Path(__file__).with_name('profile-production-metadata-memory.sh')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / 'input.mxf'
            media.write_bytes(b'input')
            for index, configuration in enumerate(configurations):
                artifacts = root / f'artifacts-{index}'
                environment = {key: value for key, value in os.environ.items()
                               if not key.startswith('METADATA_MEMORY_PROFILE_')}
                environment.update(configuration)
                result = subprocess.run(['/bin/zsh', str(runner), str(artifacts), str(media)],
                                        env=environment, capture_output=True, text=True)
                with self.subTest(configuration=configuration):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(artifacts.exists())
                    self.assertNotIn('Building', result.stderr)


if __name__ == '__main__':
    unittest.main()
