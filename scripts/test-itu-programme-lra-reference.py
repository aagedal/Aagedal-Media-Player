#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Analytic and rejection checks for the independent programme LRA calculator."""
import copy
import importlib.util
import math
from pathlib import Path
import struct
import tempfile
import unittest
import wave

spec = importlib.util.spec_from_file_location(
    'lra_reference', Path(__file__).with_name('itu-programme-lra-reference.py'))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def write_tones(path, segments, gains=(1.0, 1.0), sample_rate=48000, sample_width=2):
    """Direct PCM16 synthesis, with per-channel peak dBFS and 1 kHz sine."""
    with wave.open(str(path), 'wb') as output:
        output.setparams((len(gains), sample_width, sample_rate, 0, 'NONE', 'not compressed'))
        for peak_dbfs, seconds in segments:
            amplitude = 10 ** (peak_dbfs / 20)
            period = b''.join(struct.pack('<h', round(32767 * amplitude * gain * math.sin(2 * math.pi * n / 48)))
                              for n in range(48) for gain in gains)
            output.writeframes(period * round(seconds * 1000))


def measurement_rows():
    return [dict(file=name, sha256=digest, channels=len(weights), sampleRate=48000,
                 unreferencedObservations=dict(loudnessRangeLU='10.0'))
            for name, digest, weights in reference.REFERENCES]


class ProgrammeLRAReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'reference.wav'

    def test_official_analytic_lra_sequences(self):
        # EBU Tech 3342 (2023), Table 1, cases 1–4: all segments are 20 s.
        for levels, expected in [([-20, -30], 10), ([-20, -15], 5),
                                 ([-40, -20], 20), ([-50, -35, -20, -35, -50], 15)]:
            with self.subTest(levels=levels):
                write_tones(self.path, [(level, 20) for level in levels])
                result = reference.lra_from_powers(reference.short_term_powers(self.path, (1, 1)))
                self.assertAlmostEqual(result['loudnessRangeLU'], expected, delta=1.0)

    def test_absolute_stereo_calibration_and_window_count(self):
        # EBU Tech 3341 Table 1 case 1: 1 kHz, stereo peak -23 dBFS => -23 LUFS.
        write_tones(self.path, [(-23, 4)])
        powers = reference.short_term_powers(self.path, (1, 1))
        self.assertAlmostEqual(reference.loudness(powers[0]), -23, delta=0.02)
        # 4 s input + 1.5 s silence, first complete window at 3 s, 100 ms hop.
        self.assertEqual(len(powers), 26)
        self.assertLess(powers[-1], powers[0])

    def test_channels_filter_independently_and_lfe_is_excluded(self):
        write_tones(self.path, [(-23, 4)], gains=(1,))
        mono = reference.short_term_powers(self.path, (1,))[0]
        for gains, ratio in [((1, 1, 0, 0, 0, 0), 2),
                             ((1, -1, 0, 0, 0, 0), 2),
                             ((0, 0, 1, 0, 0, 0), 1),
                             ((0, 0, 0, 0, 1, 0), 1.41),
                             ((0, 0, 0, 0, 0, 1), 1.41),
                             ((1, 0, 0, 10, 0, 0), 1)]:
            with self.subTest(gains=gains):
                write_tones(self.path, [(-23, 4)], gains=gains)
                power = reference.short_term_powers(self.path, (1, 1, 1, 0, 1.41, 1.41))[0]
                self.assertAlmostEqual(power / mono, ratio, places=10)

    def test_gates_use_energy_average_and_reject_silence(self):
        def power(lufs):
            return 10 ** ((lufs + 0.691) / 10)
        # Absolute gate rejects -80; relative gate rejects -60 with louder -20.
        result = reference.lra_from_powers([power(-80)] * 10 + [power(-60)] * 10 + [power(-20)] * 10)
        self.assertEqual(result['absoluteGatedBlocks'], 20)
        self.assertEqual(result['relativeGatedBlocks'], 10)
        self.assertEqual(result['loudnessRangeLU'], 0)
        # Averaging dB instead would retain -45; the power average excludes it.
        result = reference.lra_from_powers([power(-45)] * 50 + [power(-20)] * 50)
        self.assertEqual(result['relativeGatedBlocks'], 50)
        for powers in [[], [0] * 50, [power(-80)], [-1], [math.nan], [math.inf]]:
            with self.subTest(powers=powers), self.assertRaises(ValueError):
                reference.lra_from_powers(powers)

    def test_percentiles_use_matlab_half_up_index(self):
        # 31 ordered levels have high index round(30 * .95) = 29. Python's
        # ties-to-even round would pick 28 and yield 2.5 instead of 2.6 LU.
        powers = [10 ** (index / 100) for index in range(31)]
        self.assertAlmostEqual(reference.lra_from_powers(powers)['loudnessRangeLU'], 2.6)

    def test_wrong_format_and_truncated_audio_fail(self):
        for rate, width, weights in [(44100, 2, (1, 1)), (48000, 1, (1, 1)), (48000, 2, (1,))]:
            with self.subTest(rate=rate, width=width, weights=weights):
                write_tones(self.path, [(-23, 4)], sample_rate=rate, sample_width=width)
                with self.assertRaises(ValueError):
                    reference.short_term_powers(self.path, weights)
        write_tones(self.path, [(-23, 4)])
        self.path.write_bytes(self.path.read_bytes()[:-100])
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            reference.short_term_powers(self.path, (1, 1))

    def test_production_measurement_identity_and_values(self):
        rows = measurement_rows()
        self.assertEqual(len(reference.validate_measurements(rows)), 3)
        for invalid in [rows[:2], rows + [rows[0]], [rows[0], rows[0], rows[2]]]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                reference.validate_measurements(invalid)
        for key, value in [('sha256', 'wrong'), ('channels', 8), ('sampleRate', 44100),
                           ('file', 'unknown.wav'), ('file', []), ('channels', True),
                           ('channels', 1.0), ('sampleRate', 48000.0)]:
            changed = copy.deepcopy(rows)
            changed[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                reference.validate_measurements(changed)
        for value in ['nan', 'inf', '-inf', '-1', 'invalid', True, False, None, [], {}, 10 ** 400]:
            changed = copy.deepcopy(rows)
            changed[0]['unreferencedObservations']['loudnessRangeLU'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                reference.validate_measurements(changed)

    def test_missing_observations_and_malformed_rows_fail_clearly(self):
        rows = measurement_rows()
        for invalid in [None, {}, 'invalid', [None, rows[1], rows[2]],
                        [[], rows[1], rows[2]], [{}, rows[1], rows[2]]]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                reference.validate_measurements(invalid)
        for key in ['file', 'sha256', 'channels', 'sampleRate', 'unreferencedObservations']:
            changed = copy.deepcopy(rows)
            del changed[0][key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                reference.validate_measurements(changed)
        for observations in [None, [], True, 'invalid', {}]:
            changed = copy.deepcopy(rows)
            changed[0]['unreferencedObservations'] = observations
            with self.subTest(observations=observations), self.assertRaises(ValueError):
                reference.validate_measurements(changed)

    def test_modified_original_fails_before_calculation(self):
        (Path(self.temporary.name) / reference.REFERENCES[0][0]).write_bytes(b'wrong reference')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            reference.compare(self.temporary.name, measurement_rows())


if __name__ == '__main__':
    unittest.main()
