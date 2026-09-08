#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Independent 48 kHz PCM16 LRA comparison; no FFmpeg or third-party DSP.

This implements EBU Tech 3342 (2023), sections 3.1 and 5, using the 48 kHz
K-weighting coefficients of ITU-R BS.1770-3 Annex 1, Tables 1–3. Targets are
calculated from pinned original ITU programmes, not published programme LRA
values. This is a deliberately narrow reference tool, not a general WAV meter.
"""
import argparse
from array import array
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import sys
import wave

ALGORITHM = 'ebu3342-2023-48k-pcm16-v1'
SAMPLE_RATE = 48_000
HOP = 4_800
WINDOW_HOPS = 30
TRAILING_SILENCE_FRAMES = 72_000
# ITU specifies L/R/C/LFE/Ls/Rs for this particular unlabelled six-channel file.
# These are energy weights, applied after independently filtering each channel.
REFERENCES = (
    ('1770-2 Conf Mono Voice+Music-23LKFS.wav',
     'f8b318474b158c9f2ee842f0cfadf58ffcf504ffe8daa172220190d12dd0785b', (1.0,)),
    ('1770-2 Conf Stereo VinL+R-23LKFS.wav',
     '3ff26c997d838aff36b4319f9e0a673c0b51fe26722ecb0153887b66f38c296f', (1.0, 1.0)),
    ('1770-2 Conf 6ch VinCntr-23LKFS.wav',
     'ef2a0baef7f50db39eddfb1ba6f2a5445646050d113f81c6365cddca7f0448a0',
     (1.0, 1.0, 1.0, 0.0, 1.41, 1.41)),
)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def loudness(power):
    return -0.691 + 10 * math.log10(power) if power > 0 else -math.inf


def short_term_powers(path, weights):
    """3-second K-weighted powers every 100 ms, from a fresh zero filter state.

    Feed exactly 1.5 s of trailing silence, as Tech 3342 section 5 specifies
    for file-based calculation. Only complete 3 s windows on the 100 ms grid
    are retained. No leading partial windows or decoded/resampled audio.
    """
    if not weights or any(not math.isfinite(w) or w < 0 for w in weights):
        raise ValueError('Invalid channel weights')
    with wave.open(str(path), 'rb') as source:
        channels = source.getnchannels()
        if (source.getframerate(), source.getsampwidth(), channels, source.getcomptype()) != (
                SAMPLE_RATE, 2, len(weights), 'NONE'):
            raise ValueError('Reference requires 48 kHz uncompressed PCM16 with matching channels')
        # Transposed direct form II, two independent second-order stages per channel.
        states = [[0.0] * 4 for _ in weights]
        recent = deque(maxlen=WINDOW_HOPS)
        powers = []
        frame_count = source.getnframes()
        frames_read = 0
        for _ in range((frame_count + TRAILING_SILENCE_FRAMES) // HOP):
            raw = source.readframes(HOP)
            actual_frames = min(HOP, frame_count - frames_read)
            if len(raw) != actual_frames * channels * 2:
                raise ValueError('Truncated PCM payload')
            frames_read += actual_frames
            samples = array('h')
            samples.frombytes(raw)
            if sys.byteorder != 'little':
                samples.byteswap()
            samples.extend([0] * ((HOP - actual_frames) * channels))
            channel_energies = []
            for channel, weight in enumerate(weights):
                if weight == 0:  # LFE is excluded from loudness, not mixed into another channel.
                    continue
                s1, s2, h1, h2 = states[channel]
                energy = 0.0
                for pcm in samples[channel::channels]:
                    x = pcm / 32768.0
                    shelf = 1.53512485958697 * x + s1
                    s1 = -2.69169618940638 * x + 1.69065929318241 * shelf + s2
                    s2 = 1.19839281085285 * x - 0.73248077421585 * shelf
                    filtered = shelf + h1
                    h1 = -2.0 * shelf + 1.99004745483398 * filtered + h2
                    h2 = shelf - 0.99007225036621 * filtered
                    energy += filtered * filtered
                states[channel] = [s1, s2, h1, h2]
                channel_energies.append(weight * energy / HOP)
            recent.append(math.fsum(channel_energies))
            if len(recent) == WINDOW_HOPS:
                powers.append(math.fsum(recent) / WINDOW_HOPS)
        return powers


def lra_from_powers(powers):
    if any(not math.isfinite(p) or p < 0 for p in powers):
        raise ValueError('Short-term powers must be finite and non-negative')
    absolute = [p for p in powers if loudness(p) >= -70.0]
    if not absolute:
        raise ValueError('No short-term blocks survive the absolute gate')
    # Averaging energies, not LUFS values, sets the relative gate.
    relative_threshold = math.fsum(absolute) / len(absolute) / 100.0
    levels = sorted(loudness(p) for p in absolute if p >= relative_threshold)
    # MATLAB round for positive indices is half-up, unlike Python round.
    low = levels[math.floor((len(levels) - 1) * 0.10 + 0.5)]
    high = levels[math.floor((len(levels) - 1) * 0.95 + 0.5)]
    return dict(loudnessRangeLU=high - low, lowPercentileLUFS=low,
                highPercentileLUFS=high, shortTermBlocks=len(powers),
                absoluteGatedBlocks=len(absolute), relativeGatedBlocks=len(levels))


def validate_measurements(rows):
    expected = {name: (digest, len(weights)) for name, digest, weights in REFERENCES}
    if not isinstance(rows, list) or len(rows) != len(expected):
        raise ValueError('Require all three production programme measurements')
    seen = set()
    result = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('Programme measurement must be a JSON object')
        name = row.get('file')
        if not isinstance(name, str) or name not in expected or name in seen:
            raise ValueError('Unknown or duplicate programme measurement')
        seen.add(name)
        digest, channels = expected[name]
        if (row.get('sha256') != digest or type(row.get('channels')) is not int
                or row['channels'] != channels or type(row.get('sampleRate')) is not int
                or row['sampleRate'] != SAMPLE_RATE):
            raise ValueError(f'Production source identity mismatch: {name}')
        observations = row.get('unreferencedObservations')
        if not isinstance(observations, dict):
            raise ValueError(f'Missing production observations: {name}')
        value = observations.get('loudnessRangeLU')
        if type(value) not in (str, int, float):
            raise ValueError(f'Missing or invalid production LRA: {name}')
        try:
            measured = float(value)
        except (ValueError, OverflowError) as error:
            raise ValueError(f'Invalid production LRA: {name}') from error
        if not math.isfinite(measured) or measured < 0:
            raise ValueError(f'Invalid production LRA: {name}')
        result[name] = measured
    return result


def compare(directory, measurements):
    measured = validate_measurements(measurements)
    rows = []
    for name, digest, weights in REFERENCES:
        path = Path(directory) / name
        if sha256(path) != digest:
            raise ValueError(f'Original reference hash mismatch: {name}')
        result = lra_from_powers(short_term_powers(path, weights))
        difference = measured[name] - result['loudnessRangeLU']
        rows.append(dict(file=name, sha256=digest, channelEnergyWeights=weights,
                         independentCalculation=result, productionLoudnessRangeLU=measured[name],
                         differenceLU=difference, regressionToleranceLU=1.0,
                         passed=abs(difference) <= 1.0))
    return dict(algorithm=ALGORITHM, calculatorSHA256=sha256(__file__), pythonVersion=sys.version,
                targetProvenance='independent calculation, not published programme LRA targets',
                sampleRate=SAMPLE_RATE, windowSeconds=3.0, hopSeconds=0.1,
                trailingSilenceSeconds=1.5, measurements=rows)


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
            print(f'{row["file"]}: independent {row["independentCalculation"]["loudnessRangeLU"]:.4f} LU; '
                  f'production {row["productionLoudnessRangeLU"]:.1f} LU; difference {row["differenceLU"]:+.4f} LU')
        return 0 if all(row['passed'] for row in report['measurements']) else 1
    except (ValueError, KeyError, TypeError, OSError, wave.Error) as error:
        parser.exit(1, f'Programme LRA reference failed: {error}\n')


if __name__ == '__main__':
    sys.exit(main())
