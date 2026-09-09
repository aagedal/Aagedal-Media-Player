#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Independent BS.1770-5 Annex 2 true-peak comparison on original ITU PCM.

Uses only the standard library and the published four-phase FIR coefficients.
The resulting programme values are calculated references, not published targets.
Deliberately limited to the three hash-pinned 48 kHz PCM16 programme WAVs.
"""
import argparse
from array import array
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys
import wave

spec = importlib.util.spec_from_file_location(
    'programme_lra_reference', Path(__file__).with_name('itu-programme-lra-reference.py'))
programme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(programme)

ALGORITHM = 'bs1770-5-annex2-48k-pcm16-fir4-v1'
SOURCE = 'https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf'
TOLERANCE_DB = 0.4  # Project comparison tolerance; not an official programme target tolerance.
CHUNK_FRAMES = 4096
# BS.1770-5 Annex 2, printed pp. 18–19, table columns (newest sample first).
# Every published coefficient is an exact multiple of 1/8192. Integer dot
# products preserve those coefficients without rounding or requiring a DSP lib.
COEFFICIENT_SCALE = 8192
PHASES = (
    (14, 90, -161, 272, -487, 1125, 7964, -838, 390, -218, 122, -68),
    (-239, 240, -424, 730, -1364, 3810, 6388, -1641, 832, -477, 271, -155),
    (-155, 271, -477, 832, -1641, 6388, 3810, -1364, 730, -424, 240, -239),
    (-68, 122, -218, 390, -838, 7964, 1125, -487, 272, -161, 90, 14),
)
TAPS = 12
BOUND = max(sum(abs(coefficient) for coefficient in phase) for phase in PHASES)
PCM_SCALE = 32768


def decibels(amplitude):
    # Silence is representable in retained JSON without non-standard infinities.
    return 20 * math.log10(amplitude) if amplitude > 0 else None


class ChannelPeak:
    def __init__(self):
        self.history = [0] * (TAPS - 1)
        self.filtered_peak = 0
        self.sample_peak = 0
        self.filtered_blocks = 0
        self.skipped_blocks = 0

    def process(self, samples, skip_bounded_blocks=True):
        if not samples:
            return
        self.sample_peak = max(self.sample_peak, max(abs(sample) for sample in samples))
        combined = self.history + list(samples)
        self.history = combined[-(TAPS - 1):]
        # Triangle inequality gives an exact upper bound for every FIR output
        # in this block, including its 11 preceding source samples. This skips
        # only blocks that cannot raise the established peak. No peak threshold
        # or programme-specific region selection approximates the calculation.
        if skip_bounded_blocks and max(abs(sample) for sample in combined) * BOUND <= self.filtered_peak:
            self.skipped_blocks += 1
            return
        self.filtered_blocks += 1
        maximum = self.filtered_peak
        for offset in range(TAPS - 1, len(combined)):
            recent = combined[offset - TAPS + 1:offset + 1][::-1]
            for phase in PHASES:
                maximum = max(maximum, abs(sum(sample * coefficient
                                              for sample, coefficient in zip(recent, phase))))
        self.filtered_peak = maximum

    def report(self):
        reconstructed = self.filtered_peak / (COEFFICIENT_SCALE * PCM_SCALE)
        sample = self.sample_peak / PCM_SCALE
        return dict(truePeakDBTP=decibels(reconstructed), samplePeakDBFS=decibels(sample),
                    reconstructedPeakAmplitude=reconstructed, samplePeakAmplitude=sample,
                    filteredBlocks=self.filtered_blocks, boundedSkippedBlocks=self.skipped_blocks)


def pcm_true_peak(path, channels, chunk_frames=CHUNK_FRAMES, skip_bounded_blocks=True):
    if type(channels) is not int or channels not in (1, 2, 6):
        raise ValueError('Reference requires mono, stereo, or six channels')
    if type(chunk_frames) is not int or chunk_frames < 1:
        raise ValueError('Chunk size must be a positive integer')
    with wave.open(str(path), 'rb') as source:
        if (source.getframerate(), source.getsampwidth(), source.getnchannels(), source.getcomptype()) != (
                48000, 2, channels, 'NONE'):
            raise ValueError('Reference requires 48 kHz uncompressed PCM16 with matching channels')
        remaining = source.getnframes()
        if remaining == 0:
            raise ValueError('Reference contains no PCM frames')
        frame_count = remaining
        meters = [ChannelPeak() for _ in range(channels)]
        while remaining:
            count = min(chunk_frames, remaining)
            raw = source.readframes(count)
            if len(raw) != count * channels * 2:
                raise ValueError('Truncated PCM payload')
            samples = array('h')
            samples.frombytes(raw)
            if sys.byteorder != 'little':
                samples.byteswap()
            for channel, meter in enumerate(meters):
                meter.process(samples[channel::channels], skip_bounded_blocks)
            remaining -= count
        # Complete the full linear convolution, including peaks reconstructed
        # after the last stored sample. Fresh leading zeros are in each meter.
        for meter in meters:
            meter.process([0] * (TAPS - 1), skip_bounded_blocks)
        channel_results = [meter.report() for meter in meters]
        peak = max(row['reconstructedPeakAmplitude'] for row in channel_results)
        return dict(truePeakDBTP=decibels(peak), frameCount=frame_count,
                    perChannel=channel_results, trailingSilenceFrames=TAPS - 1)


def validate_measurements(rows):
    # Reuse only source identity / JSON validation, never the LRA calculator's
    # filter, channel weights, or results. Every channel, including LFE, is metered.
    programme.validate_measurements(rows)
    values = {}
    for row in rows:
        value = row['unreferencedObservations'].get('truePeakDBTP')
        if type(value) not in (str, int, float):
            raise ValueError(f'Invalid production true peak: {row["file"]}')
        try:
            measured = float(value)
        except (ValueError, OverflowError) as error:
            raise ValueError(f'Invalid production true peak: {row["file"]}') from error
        if not math.isfinite(measured):
            raise ValueError(f'Invalid production true peak: {row["file"]}')
        values[row['file']] = measured
    return values


def compare(directory, measurements):
    measured = validate_measurements(measurements)
    # Validate the complete original set before spending time on interpolation.
    for name, digest, _ in programme.REFERENCES:
        if programme.sha256(Path(directory) / name) != digest:
            raise ValueError(f'Original reference hash mismatch: {name}')
    rows = []
    for name, digest, weights in programme.REFERENCES:
        result = pcm_true_peak(Path(directory) / name, len(weights))
        expected = result['truePeakDBTP']
        if expected is None:
            raise ValueError(f'Original programme unexpectedly silent: {name}')
        difference = measured[name] - expected
        rows.append(dict(file=name, sha256=digest, channels=len(weights),
                         independentCalculation=result, productionTruePeakDBTP=measured[name],
                         differenceDB=difference, regressionToleranceDB=TOLERANCE_DB,
                         passed=abs(difference) <= TOLERANCE_DB))
    return dict(algorithm=ALGORITHM, calculatorSHA256=programme.sha256(__file__),
                sourceValidationSHA256=programme.sha256(programme.__file__),
                pythonVersion=sys.version, source=SOURCE,
                targetProvenance='independent calculation, not published programme true-peak targets',
                sampleRate=48000, oversamplingFactor=4, tapsPerPhase=TAPS,
                coefficientsSHA256=hashlib.sha256(repr(PHASES).encode('ascii')).hexdigest(),
                channelPolicy='maximum absolute reconstructed peak across all channels, including LFE',
                measurements=rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference_directory', type=Path)
    parser.add_argument('measurements', type=Path, help='Production runner measurements.json')
    parser.add_argument('output', type=Path, help='New independent comparison JSON artifact')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; choose a new artifact path')
    try:
        report = compare(args.reference_directory, json.loads(args.measurements.read_text()))
        with args.output.open('x') as destination:
            json.dump(report, destination, indent=2, sort_keys=True, allow_nan=False)
            destination.write('\n')
        for row in report['measurements']:
            print(f'{row["file"]}: independent {row["independentCalculation"]["truePeakDBTP"]:.4f} dBTP; '
                  f'production {row["productionTruePeakDBTP"]:.1f} dBTP; difference {row["differenceDB"]:+.4f} dB')
        return 0 if all(row['passed'] for row in report['measurements']) else 1
    except (ValueError, KeyError, TypeError, OSError, wave.Error) as error:
        parser.exit(1, f'Programme true-peak reference failed: {error}\n')


if __name__ == '__main__':
    sys.exit(main())
