#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('validator', Path(__file__).with_name('validate-programme-loudness-profile.py'))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ValidationTests(unittest.TestCase):
    def record(self):
        measurements = []
        for layout, roles in validator.LAYOUTS.items():
            for scope, start, end in [('whole', 0, 3600), ('early', 0, 30), ('late', 3570, 3600)]:
                measurements.append(dict(layout=layout, channelRoles=roles, audioStreamIndices=list(range(len(roles))),
                    scope=scope, rangeStartSeconds=start, rangeEndSeconds=end, wallSeconds=2,
                    selectedAudioSecondsPerWallSecond=(end-start)/2, initialResidentBytes=100,
                    sampledPeakResidentBytes=200, sampledPeakChildResidentBytes=50,
                    integratedLUFS='-23', loudnessRangeLU='0', truePeakDBTP='-20'))
        return dict(inputIndex=0, file='eight-mono.mov', durationSeconds=3600,
                    audioStreams=[dict(index=i, channels=1, sampleRate=48000, codec='pcm_s24le') for i in range(8)],
                    measurements=measurements)

    def test_complete_and_silent(self):
        row = self.record()
        validator.validate([row], 1)
        row['measurements'][0]['truePeakDBTP'] = '-inf'
        validator.validate([row], 1)

    def test_mixed_source_streams_use_audio_ordinals(self):
        row = self.record()
        row["audioStreams"].insert(0, dict(index=0, channels=2, sampleRate=44100, codec="aac"))
        for index, stream in enumerate(row["audioStreams"]): stream["index"] = index
        row["audioStreams"][1]["sampleRate"] = 96000
        for measurement in row["measurements"]:
            measurement["audioStreamIndices"] = [i + 1 for i in measurement["audioStreamIndices"]]
        validator.validate([row], 1)

    def test_incomplete_and_duplicate(self):
        row = self.record()
        for rows, count in [([], 1), ([row, row], 2)]:
            with self.assertRaises(ValueError): validator.validate(rows, count)
        row['measurements'].pop()
        with self.assertRaises(ValueError): validator.validate([row], 1)
        row = self.record()
        row['measurements'][-1] = row['measurements'][0]
        with self.assertRaises(ValueError): validator.validate([row], 1)

    def test_bad_assignment_roles_and_metadata(self):
        for key, value in [('layout', 'unknown'), ('audioStreamIndices', [0, 0]),
                           ('audioStreamIndices', [False, 1]), ('channelRoles', ['FR', 'FL'])]:
            row = self.record()
            row['measurements'][0][key] = value
            with self.assertRaises(ValueError): validator.validate([row], 1)
        for key, value in [('channels', 2), ('sampleRate', 0), ('index', 9), ('codec', '')]:
            row = self.record()
            row['audioStreams'][0][key] = value
            with self.assertRaises(ValueError): validator.validate([row], 1)

    def test_bad_metrics_ranges_and_memory(self):
        for key, value in [('wallSeconds', float('nan')), ('rangeStartSeconds', 1),
                           ('selectedAudioSecondsPerWallSecond', 0.5),
                           ('sampledPeakChildResidentBytes', 0), ('sampledPeakResidentBytes', 1),
                           ('integratedLUFS', 'nan'), ('loudnessRangeLU', '-inf')]:
            row = self.record()
            row['measurements'][0][key] = value
            with self.assertRaises(ValueError): validator.validate([row], 1)


if __name__ == '__main__': unittest.main()
