#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'profile_validator', Path(__file__).with_name('validate-production-metadata-memory-profile.py'))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def record():
    return {
        'inputIndex': 0, 'processIdentifier': 100, 'file': '8h.m4a', 'inputFileBytes': 2_000_000,
        'sampleIntervalMilliseconds': 10, 'sampleCount': 4,
        'loadWallSeconds': 0.4, 'cachedReadWallSeconds': 0.001, 'cacheParity': True,
        'initialResidentBytes': 10, 'sampledPeakResidentBytes': 90,
        'afterLoadResidentBytes': 20, 'afterCachedReadResidentBytes': 21,
        'afterLocalReleaseResidentBytes': 18,
        'initialLifetimePeakResidentBytes': 50, 'afterLoadLifetimePeakResidentBytes': 100,
        'afterCachedReadLifetimePeakResidentBytes': 100,
        'afterLocalReleaseLifetimePeakResidentBytes': 100,
        'metadata': {
            'durationSeconds': 28_800, 'formatName': 'mov,mp4,m4a,3gp,3g2,mj2',
            'sizeBytes': 2_000_000, 'bitRate': 1_000_000,
            'videoStreamCount': 0, 'audioStreamCount': 1,
            'subtitleStreamCount': 0, 'chapterCount': 0,
            'videoStreams': [], 'audioStreams': [{'codec': 'alac'}],
        },
    }


class ProductionMetadataMemoryProfileValidationTests(unittest.TestCase):
    def test_valid_multiple_inputs_are_sorted(self):
        first = record()
        second = copy.deepcopy(first)
        second['inputIndex'] = 1
        second['processIdentifier'] = 101
        second['file'] = '1h.m4a'
        self.assertEqual([row['inputIndex'] for row in validator.validate([second, first], 2)], [0, 1])

    def test_incomplete_duplicate_or_invalid_identity_is_rejected(self):
        for rows, count in [([], 1), ([record()], 2), ([record(), record()], 2)]:
            with self.subTest(rows=len(rows), count=count), self.assertRaises(ValueError):
                validator.validate(rows, count)
        row = record()
        row['inputIndex'] = True
        with self.assertRaises(ValueError):
            validator.validate([row], 1)

    def test_invalid_measurements_are_rejected(self):
        for key, value in [
            ('sampleCount', 0), ('loadWallSeconds', 0), ('cachedReadWallSeconds', float('nan')),
            ('cacheParity', False), ('initialResidentBytes', 0),
            ('sampledPeakResidentBytes', 9), ('afterLoadLifetimePeakResidentBytes', 40),
        ]:
            row = record()
            row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1)

    def test_lifetime_peak_below_current_or_decreasing_is_rejected(self):
        for key, value in [
            ('initialLifetimePeakResidentBytes', 9),
            ('afterCachedReadLifetimePeakResidentBytes', 99),
            ('afterLocalReleaseLifetimePeakResidentBytes', 17),
        ]:
            row = record()
            row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1)

    def test_invalid_metadata_snapshot_is_rejected(self):
        for key, value in [
            ('durationSeconds', 59), ('sizeBytes', 1), ('videoStreamCount', 1),
            ('audioStreamCount', 0), ('audioStreams', []),
        ]:
            row = record()
            row['metadata'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate([row], 1)


if __name__ == '__main__':
    unittest.main()
