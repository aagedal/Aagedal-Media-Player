#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate full-app metadata memory profile attachments and publish summary.json."""
import json
import math
from pathlib import Path
import sys


CURRENT_MEMORY_FIELDS = (
    'initialResidentBytes', 'sampledPeakResidentBytes', 'afterLoadResidentBytes',
    'afterCachedReadResidentBytes', 'afterLocalReleaseResidentBytes',
)
LIFETIME_MEMORY_FIELDS = (
    'initialLifetimePeakResidentBytes', 'afterLoadLifetimePeakResidentBytes',
    'afterCachedReadLifetimePeakResidentBytes', 'afterLocalReleaseLifetimePeakResidentBytes',
)


def integer(value, label, minimum=0):
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f'Invalid {label}: {value}')
    return value


def number(value, label, *, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f'{label} must be numeric')
    if not math.isfinite(value) or value < 0 or (positive and value == 0):
        raise ValueError(f'Invalid {label}: {value}')
    return value


def validate_snapshot(snapshot, input_bytes):
    if not isinstance(snapshot, dict):
        raise ValueError('Metadata snapshot must be an object')
    duration = number(snapshot['durationSeconds'], 'metadata duration', positive=True)
    if duration < 60:
        raise ValueError('Metadata input must be at least 60 seconds')
    if snapshot['formatName'] is not None and not isinstance(snapshot['formatName'], str):
        raise ValueError('Invalid metadata format name')
    if integer(snapshot['sizeBytes'], 'metadata size', 1) != input_bytes:
        raise ValueError('Metadata size does not match the input file size')
    for key in ('videoStreamCount', 'audioStreamCount', 'subtitleStreamCount', 'chapterCount'):
        integer(snapshot[key], key)
    video = snapshot['videoStreams']
    audio = snapshot['audioStreams']
    if not isinstance(video, list) or not isinstance(audio, list):
        raise ValueError('Metadata stream snapshots must be arrays')
    if len(video) != snapshot['videoStreamCount'] or len(audio) != snapshot['audioStreamCount']:
        raise ValueError('Metadata stream counts are inconsistent')
    if not video and not audio:
        raise ValueError('Metadata profile requires at least one audio or video stream')
    return duration


def validate(rows, expected_count):
    integer(expected_count, 'input count', 1)
    if len(rows) != expected_count:
        raise ValueError(f'Expected {expected_count} profile records, got {len(rows)}')
    indices = []
    process_identifiers = []
    for row in rows:
        index = integer(row['inputIndex'], 'input index')
        indices.append(index)
        process_identifiers.append(integer(row['processIdentifier'], 'process identifier', 1))
        filename = row['file']
        if not isinstance(filename, str) or not filename:
            raise ValueError('Missing input filename')
        input_bytes = integer(row['inputFileBytes'], 'input file size', 1)
        integer(row['sampleIntervalMilliseconds'], 'sample interval', 1)
        integer(row['sampleCount'], 'sample count', 1)
        number(row['loadWallSeconds'], 'load wall time', positive=True)
        number(row['cachedReadWallSeconds'], 'cached-read wall time', positive=True)
        if row['cacheParity'] is not True:
            raise ValueError('Cached metadata differs from the uncached result')

        current = [integer(row[key], key, 1) for key in CURRENT_MEMORY_FIELDS]
        lifetime = [integer(row[key], key, 1) for key in LIFETIME_MEMORY_FIELDS]
        if current[1] < current[0] or current[1] < current[2]:
            raise ValueError('Sampled peak does not cover initial and after-load resident memory')
        if lifetime != sorted(lifetime):
            raise ValueError('Lifetime peak resident memory decreased')
        if any(peak < resident for peak, resident in zip(
                lifetime, (current[0], current[2], current[3], current[4]))):
            raise ValueError('Lifetime peak is below current resident memory')
        validate_snapshot(row['metadata'], input_bytes)
    if sorted(indices) != list(range(expected_count)):
        raise ValueError('Missing or duplicate input indices')
    if len(set(process_identifiers)) != expected_count:
        raise ValueError('Each input must run in a fresh process')
    return sorted(rows, key=lambda row: row['inputIndex'])


def main():
    root = Path(sys.argv[1])
    rows = []
    for path in (root / 'attachments').rglob('*'):
        if path.is_file():
            for line in path.read_text(errors='replace').splitlines():
                if line.startswith('PRODUCTION_METADATA_MEMORY_PROFILE '):
                    rows.append(json.loads(line.removeprefix('PRODUCTION_METADATA_MEMORY_PROFILE ')))
    rows = validate(rows, int(sys.argv[2]))
    (root / 'summary.json').write_text(json.dumps(rows, indent=2, allow_nan=False) + '\n')
    for row in rows:
        print(json.dumps(row, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (KeyError, TypeError, ValueError, OSError) as error:
        raise SystemExit(f'Invalid production metadata memory profile: {error}') from error
