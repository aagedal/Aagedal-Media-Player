#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reject incomplete or unusable production loudness profile attachments."""
import json
import math
from pathlib import Path
import sys


def number(value, label, *, minimum=0, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f'{label} must be numeric')
    if not math.isfinite(value) or value < minimum or (positive and value == 0):
        raise ValueError(f'Invalid {label}: {value}')
    return value


def integer(value, label, *, minimum=0):
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f'Invalid {label}: {value}')
    return value


def validate(rows, expected_count):
    integer(expected_count, 'input count', minimum=1)
    if len(rows) != expected_count:
        raise ValueError(f'Expected {expected_count} profile records, got {len(rows)}')
    indices = []
    for row in rows:
        indices.append(integer(row['inputIndex'], 'input index'))
        if not isinstance(row['file'], str) or not row['file']:
            raise ValueError('Missing input filename')
        duration = number(row['durationSeconds'], 'duration', minimum=60)
        stream_count = integer(row['multichannelStreams'], 'stream count', minimum=1)
        measurements = row['measurements']
        if len(measurements) != stream_count * 3:
            raise ValueError('Incomplete loudness profile')
        streams = {}
        for measurement in measurements:
            stream_index = integer(measurement['streamIndex'], 'stream index')
            scopes = streams.setdefault(stream_index, {})
            scope = measurement['scope']
            if scope not in ('early', 'late', 'whole') or scope in scopes:
                raise ValueError('Invalid or duplicate loudness workload scope')
            scopes[scope] = measurement
            integer(measurement['channels'], 'channels', minimum=6)
            number(measurement['sampleRate'], 'sample rate', positive=True)
            if not isinstance(measurement['codec'], str) or not measurement['codec']:
                raise ValueError('Missing codec')
            wall = number(measurement['wallSeconds'], 'wall time', positive=True)
            start = number(measurement['rangeStartSeconds'], 'range start')
            end = number(measurement['rangeEndSeconds'], 'range end', positive=True)
            expected = {'whole': (0, duration), 'early': (0, 30), 'late': (duration - 30, duration)}[scope]
            if not (math.isclose(start, expected[0], rel_tol=0, abs_tol=1e-6)
                    and math.isclose(end, expected[1], rel_tol=0, abs_tol=1e-6)):
                raise ValueError('Incorrect workload range')
            speed = number(measurement['selectedAudioSecondsPerWallSecond'], 'throughput', positive=True)
            if not math.isclose(speed, (end - start) / wall, rel_tol=1e-6):
                raise ValueError('Inconsistent throughput')
            initial = integer(measurement['initialResidentBytes'], 'initial resident memory', minimum=1)
            integer(measurement['sampledPeakResidentBytes'], 'peak resident memory', minimum=initial)
            integer(measurement['sampledPeakChildResidentBytes'], 'child resident memory', minimum=1)
            for key in ('integratedLUFS', 'loudnessRangeLU', 'truePeakDBTP'):
                value = measurement[key]
                if not isinstance(value, str):
                    raise ValueError(f'{key} must be a string')
                metric = float(value)
                if math.isnan(metric) or metric == math.inf:
                    raise ValueError(f'Invalid {key}')
                if key == 'loudnessRangeLU' and (not math.isfinite(metric) or metric < 0):
                    raise ValueError('Invalid loudness range')
        if len(streams) != stream_count or any(set(scopes) != {'early', 'late', 'whole'} for scopes in streams.values()):
            raise ValueError('Incomplete loudness workload scopes')
        for scopes in streams.values():
            for key in ('channels', 'sampleRate', 'codec'):
                if len({measurement[key] for measurement in scopes.values()}) != 1:
                    raise ValueError(f'Inconsistent stream {key}')
    if sorted(indices) != list(range(expected_count)):
        raise ValueError('Missing or duplicate input records')
    return sorted(rows, key=lambda row: row['inputIndex'])


def main():
    root = Path(sys.argv[1])
    rows = []
    for path in (root / 'attachments').rglob('*'):
        if path.is_file():
            for line in path.read_text(errors='replace').splitlines():
                if line.startswith('LOUDNESS_PROFILE '):
                    rows.append(json.loads(line.removeprefix('LOUDNESS_PROFILE ')))
    rows = validate(rows, int(sys.argv[2]))
    (root / 'summary.json').write_text(json.dumps(rows, indent=2, allow_nan=False) + '\n')
    for row in rows:
        print(json.dumps(row, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (KeyError, TypeError, ValueError, OSError) as error:
        raise SystemExit(f'Invalid loudness profile: {error}') from error
