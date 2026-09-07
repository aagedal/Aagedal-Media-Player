#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('profile_validator', Path(__file__).with_name('validate-audio-loudness-profile.py'))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def record():
    measurements = []
    for scope, start, end in [('whole', 0, 3600), ('early', 0, 30), ('late', 3570, 3600)]:
        measurements.append(dict(streamIndex=1, channels=6, sampleRate=48000, codec='alac',
            scope=scope, rangeStartSeconds=start, rangeEndSeconds=end, wallSeconds=2,
            selectedAudioSecondsPerWallSecond=(end-start)/2, initialResidentBytes=100,
            sampledPeakResidentBytes=200, sampledPeakChildResidentBytes=300,
            integratedLUFS='-23.0', loudnessRangeLU='0.0', truePeakDBTP='-20.0'))
    return dict(inputIndex=0, file='1h.m4a', durationSeconds=3600, multichannelStreams=1, measurements=measurements)


class ProfileValidationTests(unittest.TestCase):
    def test_valid_silence_and_multiple_inputs(self):
        first = record()
        first['measurements'][0]['integratedLUFS'] = '-inf'
        first['measurements'][0]['truePeakDBTP'] = '-inf'
        second = copy.deepcopy(first)
        second['inputIndex'] = 1
        self.assertEqual([row['inputIndex'] for row in validator.validate([second, first], 2)], [0, 1])

    def test_missing_duplicate_and_wrong_input_identity(self):
        for rows, count in [([], 1), ([record(), record()], 2), ([record()], 2)]:
            with self.subTest(rows=rows, count=count), self.assertRaises(ValueError):
                validator.validate(rows, count)
        row = record()
        row['inputIndex'] = True
        with self.assertRaises(ValueError):
            validator.validate([row], 1)

    def test_missing_and_duplicate_scopes(self):
        for change in ['missing', 'duplicate', 'stream']:
            row = record()
            if change == 'missing':
                row['measurements'].pop()
            elif change == 'duplicate':
                row['measurements'][2]['scope'] = 'early'
            else:
                row['measurements'][2]['streamIndex'] = 2
            with self.subTest(change=change), self.assertRaises(ValueError):
                validator.validate([row], 1)

    def test_invalid_measurements_are_not_accepted_as_profile_evidence(self):
        for key, value in [('wallSeconds', float('nan')), ('wallSeconds', float('inf')),
                           ('wallSeconds', 0), ('channels', 2), ('sampleRate', 0),
                           ('rangeStartSeconds', 1), ('rangeEndSeconds', 3599),
                           ('selectedAudioSecondsPerWallSecond', 42),
                           ('sampledPeakResidentBytes', 50), ('sampledPeakChildResidentBytes', 0),
                           ('integratedLUFS', 'nan'), ('truePeakDBTP', 'inf'),
                           ('loudnessRangeLU', '-inf'), ('loudnessRangeLU', '-1')]:
            row = record()
            row['measurements'][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validator.validate([row], 1)

    def test_inconsistent_stream_metadata(self):
        row = record()
        row['measurements'][2]['channels'] = 8
        with self.assertRaises(ValueError):
            validator.validate([row], 1)


if __name__ == '__main__':
    unittest.main()
