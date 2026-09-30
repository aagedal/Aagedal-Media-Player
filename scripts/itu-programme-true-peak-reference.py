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
LIVE_TOLERANCE_DB = 1e-7  # Same published FIR on losslessly decoded PCM16, not a device tolerance.
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


def validate_live_measurements(rows):
    if not isinstance(rows, list) or len(rows) != len(programme.REFERENCES):
        raise ValueError('Require all three distinct live peak measurements')
    identities = {name: (digest, len(weights)) for name, digest, weights in programme.REFERENCES}
    validated = {}
    for row in rows:
        if (not isinstance(row, dict) or not isinstance(row.get('file'), str)
                or row['file'] not in identities or row['file'] in validated):
            raise ValueError('Unknown or duplicate live peak source')
        digest, channels = identities[row['file']]
        required = dict(schemaVersion=1, sha256=digest, channels=channels, sampleRate=48000,
                        channelLayout={1: 'mono', 2: 'stereo', 6: '5.1(side)'}[channels],
                        algorithm='bs1770-5-k-weighting-annex2-fir4-v1',
                        finalSnapshotIsFinal=True, reconstructionTailFrames=11,
                        syntheticInitialSilenceFrameCount=0, timestampTimeBase='1/48000')
        for key, expected in required.items():
            if type(row.get(key)) is not type(expected) or row[key] != expected:
                raise ValueError(f'Invalid live peak provenance: {key}')
        for key in ('decodedEndFrame', 'snapshotCount'):
            if type(row.get(key)) is not int or row[key] <= 0:
                raise ValueError(f'Invalid live peak coverage: {key}')
        if row['snapshotCount'] != row['decodedEndFrame'] // 2400 + 1:
            raise ValueError('Incomplete live peak snapshot coverage')
        if not isinstance(row.get('decoderVersion'), str) or not row['decoderVersion'].strip():
            raise ValueError('Missing live peak decoder identity')
        if channels == 6 and row.get('preparedPCMSHA256') != '5e1020672b02d963f98aab2d827961656f941da79ab4b14733f62b574737848f':
            raise ValueError('Missing sample-preserving live 5.1 identity')
        for key in ('maximumSamplePeakDBFS', 'maximumTruePeakDBTP'):
            values = row.get(key)
            if not isinstance(values, list) or len(values) != channels:
                raise ValueError(f'Incomplete live peak channel values: {key}')
            for value in values:
                if value is not None:
                    try:
                        valid = type(value) in (int, float) and math.isfinite(value)
                    except OverflowError:
                        valid = False
                    if not valid:
                        raise ValueError(f'Invalid live peak channel value: {key}')
        validated[row['file']] = row
    return validated


def compare_live_peaks(measurement, calculated):
    if measurement['decodedEndFrame'] != calculated['frameCount']:
        raise ValueError('Live peak decoder did not reach the exact PCM endpoint')
    channels = []
    for index, target in enumerate(calculated['perChannel']):
        row = dict(channel=index, passed=True)
        for live_key, target_key in [('maximumSamplePeakDBFS', 'samplePeakDBFS'),
                                     ('maximumTruePeakDBTP', 'truePeakDBTP')]:
            actual, expected = measurement[live_key][index], target[target_key]
            # Null denotes exact digital silence, never a missing measurement.
            difference = actual - expected if actual is not None and expected is not None else None
            passed = (actual is None and expected is None) or (
                difference is not None and abs(difference) <= LIVE_TOLERANCE_DB)
            row[target_key] = dict(production=actual, independent=expected,
                                   differenceDB=difference, passed=passed)
            row['passed'] = row['passed'] and passed
        channels.append(row)
    return dict(measurement=measurement, regressionToleranceDB=LIVE_TOLERANCE_DB,
                perChannel=channels, passed=all(row['passed'] for row in channels))


def compare(directory, measurements, live_measurements=None):
    measured = validate_measurements(measurements)
    live = validate_live_measurements(live_measurements) if live_measurements is not None else None
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
        row = dict(file=name, sha256=digest, channels=len(weights),
                         independentCalculation=result, productionTruePeakDBTP=measured[name],
                         differenceDB=difference, regressionToleranceDB=TOLERANCE_DB,
                         passed=abs(difference) <= TOLERANCE_DB)
        if live is not None:
            row['livePeakComparison'] = compare_live_peaks(live[name], result)
            row['passed'] = row['passed'] and row['livePeakComparison']['passed']
        rows.append(row)
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
    parser.add_argument('--live-measurements', type=Path, help='Optional complete live decoder/DSP peak evidence')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; choose a new artifact path')
    try:
        live = json.loads(args.live_measurements.read_text()) if args.live_measurements else None
        if args.live_measurements:
            # An explicitly supplied null document is malformed evidence, not
            # a request to omit the optional live comparison.
            validate_live_measurements(live)
        report = compare(args.reference_directory, json.loads(args.measurements.read_text()), live)
        with args.output.open('x') as destination:
            json.dump(report, destination, indent=2, sort_keys=True, allow_nan=False)
            destination.write('\n')
        for row in report['measurements']:
            print(f'{row["file"]}: independent {row["independentCalculation"]["truePeakDBTP"]:.4f} dBTP; '
                  f'production {row["productionTruePeakDBTP"]:.1f} dBTP; difference {row["differenceDB"]:+.4f} dB')
            if 'livePeakComparison' in row:
                live = row['livePeakComparison']
                print(f'  Live per-channel sample/true peaks: {"passed" if live["passed"] else "FAILED"}; '
                      f'{len(live["perChannel"])} channels; tolerance {LIVE_TOLERANCE_DB:g} dB')
                for channel in live['perChannel']:
                    if not channel['passed']:
                        print(f'  Channel {channel["channel"]}: {json.dumps(channel, allow_nan=False)}')
        return 0 if all(row['passed'] for row in report['measurements']) else 1
    except (ValueError, KeyError, TypeError, OSError, wave.Error) as error:
        parser.exit(1, f'Programme true-peak reference failed: {error}\n')


if __name__ == '__main__':
    sys.exit(main())
