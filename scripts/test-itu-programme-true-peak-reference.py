#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Analytic calibration and rejection checks for the independent FIR reference."""
from array import array
import copy
import importlib.util
import math
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

spec = importlib.util.spec_from_file_location(
    'true_peak_reference', Path(__file__).with_name('itu-programme-true-peak-reference.py'))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def write_pcm(path, channels, samples, rate=48000, width=2):
    values = array('h', samples)
    if sys.byteorder != 'little':
        values.byteswap()
    with wave.open(str(path), 'wb') as output:
        output.setparams((channels, width, rate, 0, 'NONE', 'not compressed'))
        output.writeframes(values.tobytes())


def measurement_rows():
    return [dict(file=name, sha256=digest, channels=len(weights), sampleRate=48000,
                 unreferencedObservations=dict(loudnessRangeLU='10.0', truePeakDBTP='-6.0'))
            for name, digest, weights in reference.programme.REFERENCES]


class ProgrammeTruePeakReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.path = self.directory / 'reference.wav'

    def test_ebu_3341_true_peak_cases_15_to_19(self):
        # Tech 3341 Table 1. The same analytic target applies to either polarity.
        # 10 ms ramps avoid a hard start/stop adding unrelated transient peaks.
        for divisor, phase, amplitude, expected in [(4, 0, .5, -6), (4, 45, .5, -6),
                                                   (6, 60, .5, -6), (8, 67.5, .5, -6),
                                                   (4, 45, 1.41, 3)]:
            for sign in (-1, 1):
                with self.subTest(divisor=divisor, phase=phase, amplitude=amplitude, sign=sign):
                    samples = [round(32768 * sign * amplitude * min(1, n / 480, (4799 - n) / 480)
                                     * math.sin(2 * math.pi * n / divisor + math.radians(phase)))
                               for n in range(4800)]
                    self.assertLess(max(abs(value) for value in samples), 32768)
                    write_pcm(self.path, 2, [sample for value in samples for sample in (value, value)])
                    result = reference.pcm_true_peak(self.path, 2)
                    self.assertGreaterEqual(result['truePeakDBTP'], expected - .4)
                    self.assertLessEqual(result['truePeakDBTP'], expected + .2)
                    if phase == 45:
                        self.assertGreater(result['truePeakDBTP'] - result['perChannel'][0]['samplePeakDBFS'], 2.5)

    def test_channel_isolation_polarity_and_lfe_inclusion(self):
        mono = [round(12000 * math.sin(2 * math.pi * n / 4 + math.pi / 4)) for n in range(512)]
        write_pcm(self.path, 1, mono)
        expected = reference.pcm_true_peak(self.path, 1)['truePeakDBTP']
        # The fourth channel is LFE in the ITU programme. A loud LFE must not be
        # excluded from true peak, and opposite stereo polarities must not cancel.
        for gains in [(1, -1), (0, 0, 0, 1, 0, 0), (0, 0, 0, 0, -1, 0)]:
            with self.subTest(gains=gains):
                write_pcm(self.path, len(gains), [value * gain for value in mono for gain in gains])
                result = reference.pcm_true_peak(self.path, len(gains))
                self.assertEqual(result['truePeakDBTP'], expected)
                for row, gain in zip(result['perChannel'], gains):
                    self.assertEqual(row['truePeakDBTP'], expected if gain else None)

    def test_final_sample_is_fully_flushed_and_peak_is_chunk_independent(self):
        for offset in (0, 10, 11, 12, 62, 63, 64, 100):
            write_pcm(self.path, 1, [0] * offset + [-16000])
            for chunk in (1, 11, 12, 64, 4096):
                with self.subTest(offset=offset, chunk=chunk):
                    result = reference.pcm_true_peak(self.path, 1, chunk_frames=chunk)
                    self.assertEqual(result['perChannel'][0]['reconstructedPeakAmplitude'],
                                     16000 * .97216796875 / 32768)
                    self.assertEqual(result['frameCount'], offset + 1)
                    self.assertEqual(result['trailingSilenceFrames'], 11)

    def test_conservative_block_skipping_matches_full_convolution(self):
        rng = random.Random(1770)
        samples = [rng.randrange(-28000, 28000) for _ in range(400)]
        samples += [rng.randrange(-300, 300) for _ in range(400)]
        samples += [0] * 400 + [16000, -14000]
        write_pcm(self.path, 1, samples)
        expected = reference.pcm_true_peak(self.path, 1, skip_bounded_blocks=False)
        for chunk in (1, 11, 12, 64, 400, 4096):
            with self.subTest(chunk=chunk):
                result = reference.pcm_true_peak(self.path, 1, chunk_frames=chunk)
                self.assertEqual(result['truePeakDBTP'], expected['truePeakDBTP'])
                self.assertEqual(result['perChannel'][0]['samplePeakAmplitude'],
                                 expected['perChannel'][0]['samplePeakAmplitude'])
                if chunk <= 400:
                    self.assertGreater(result['perChannel'][0]['boundedSkippedBlocks'], 0)

    def test_silence_is_explicit_and_empty_payload_is_rejected(self):
        write_pcm(self.path, 1, [0] * 500)
        result = reference.pcm_true_peak(self.path, 1)
        self.assertIsNone(result['truePeakDBTP'])
        self.assertEqual(result['perChannel'][0]['reconstructedPeakAmplitude'], 0)
        write_pcm(self.path, 1, [])
        with self.assertRaisesRegex(ValueError, 'no PCM frames'):
            reference.pcm_true_peak(self.path, 1)

    def test_wrong_format_and_truncated_pcm_fail(self):
        for rate, width, channels in [(44100, 2, 2), (48000, 1, 2), (48000, 2, 1)]:
            with self.subTest(rate=rate, width=width, channels=channels):
                write_pcm(self.path, 2, [1000] * 512, rate=rate, width=width)
                with self.assertRaises(ValueError):
                    reference.pcm_true_peak(self.path, channels)
        write_pcm(self.path, 2, [1000] * 512)
        self.path.write_bytes(self.path.read_bytes()[:-2])
        with self.assertRaisesRegex(ValueError, 'Truncated PCM'):
            reference.pcm_true_peak(self.path, 2)
        for channels in (True, 1.0, 8, 0, []):
            with self.subTest(channels=channels), self.assertRaises(ValueError):
                reference.pcm_true_peak(self.path, channels)
        for chunk in (True, 0, -1, .5):
            with self.subTest(chunk=chunk), self.assertRaises(ValueError):
                reference.pcm_true_peak(self.path, 2, chunk_frames=chunk)

    def test_complete_production_identity_is_required(self):
        rows = measurement_rows()
        self.assertEqual(len(reference.validate_measurements(rows)), 3)
        for invalid in (None, {}, rows[:2], rows + [rows[0]], [rows[0], rows[0], rows[2]]):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                reference.validate_measurements(invalid)
        for key, value in [('sha256', 'wrong'), ('channels', 8), ('sampleRate', 44100),
                           ('file', 'unknown.wav'), ('channels', True)]:
            changed = copy.deepcopy(rows)
            changed[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                reference.validate_measurements(changed)

    def test_invalid_true_peak_is_rejected(self):
        for value in ('nan', 'inf', '-inf', 'invalid', None, [], {}, True, False, 10 ** 400):
            changed = measurement_rows()
            changed[0]['unreferencedObservations']['truePeakDBTP'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                reference.validate_measurements(changed)
        changed = measurement_rows()
        del changed[0]['unreferencedObservations']['truePeakDBTP']
        with self.assertRaises(ValueError):
            reference.validate_measurements(changed)

    def test_changed_original_is_rejected_before_dsp(self):
        (self.directory / reference.programme.REFERENCES[0][0]).write_bytes(b'changed original')
        with patch.object(reference, 'pcm_true_peak') as calculate:
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                reference.compare(self.directory, measurement_rows())
            calculate.assert_not_called()

    def test_comparison_records_failure_outside_regression_tolerance(self):
        rows = measurement_rows()
        digests = [digest for _, digest, _ in reference.programme.REFERENCES]
        with patch.object(reference.programme, 'sha256', side_effect=digests + ['calculator', 'identity']), \
                patch.object(reference, 'pcm_true_peak', return_value=dict(truePeakDBTP=-5.5)):
            result = reference.compare(self.directory, rows)
        self.assertTrue(all(not row['passed'] for row in result['measurements']))
        self.assertIn('not published', result['targetProvenance'])

    def test_existing_output_is_never_overwritten(self):
        output = self.directory / 'result.json'
        output.write_text('preserve existing artifact')
        result = subprocess.run([sys.executable, str(Path(reference.__file__)), str(self.directory),
                                 str(self.directory / 'absent.json'), str(output)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Output already exists', result.stderr)
        self.assertEqual(output.read_text(), 'preserve existing artifact')


if __name__ == '__main__':
    unittest.main()
