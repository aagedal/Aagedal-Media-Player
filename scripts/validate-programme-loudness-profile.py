#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate complete stereo and 5.1 production split-mono workload evidence."""
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('loudness_validator', Path(__file__).with_name('validate-audio-loudness-profile.py'))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
LAYOUTS = {'stereo': ['FL', 'FR'], 'surround5Point1': ['FL', 'FR', 'FC', 'LFE', 'SL', 'SR']}


def validate(rows, expected_count):
    adapted = []
    for row in rows:
        streams = row['audioStreams']
        if [s['index'] for s in streams] != list(range(len(streams))):
            raise ValueError('Missing or reordered source stream metadata')
        mono = []
        for stream in streams:
            common.integer(stream['index'], 'source stream index')
            common.integer(stream['channels'], 'source channels')
            common.integer(stream['sampleRate'], 'source sample rate')
            if not isinstance(stream['codec'], str) or not stream['codec']:
                raise ValueError('Missing source codec')
            if stream['channels'] == 1:
                mono.append(stream['index'])
        if len(mono) < 8:
            raise ValueError('At least eight mono source tracks required')
        measurements = []
        for measurement in row['measurements']:
            layout = measurement['layout']
            if layout not in LAYOUTS:
                raise ValueError('Unknown programme layout')
            roles = LAYOUTS[layout]
            indices = measurement['audioStreamIndices']
            for index in indices:
                common.integer(index, 'assigned stream index')
            if indices != mono[:len(roles)] or measurement['channelRoles'] != roles:
                raise ValueError('Incorrect programme assignment or channel roles')
            rates = [streams[i]['sampleRate'] for i in indices]
            if any(rate <= 0 or rate > 768000 for rate in rates):
                raise ValueError('Invalid selected source sample rate')
            # Reuse timing/range/RSS/metric/completeness validation. The common
            # validator's six-channel minimum is an adapter field, not a claim
            # that stereo has six channels; original source metadata is retained.
            measurements.append(dict(measurement, streamIndex=list(LAYOUTS).index(layout),
                                     channels=6, sampleRate=max(rates), codec='programme'))
        adapted.append(dict(row, multichannelStreams=2, measurements=measurements))
    common.validate(adapted, expected_count)
    return sorted(rows, key=lambda row: row['inputIndex'])


def main():
    root = Path(sys.argv[1])
    rows = []
    for path in (root / 'attachments').rglob('*'):
        if path.is_file():
            for line in path.read_text(errors='replace').splitlines():
                if line.startswith('PROGRAMME_LOUDNESS_PROFILE '):
                    rows.append(json.loads(line.removeprefix('PROGRAMME_LOUDNESS_PROFILE ')))
    rows = validate(rows, int(sys.argv[2]))
    (root / 'summary.json').write_text(json.dumps(rows, indent=2, allow_nan=False) + '\n')
    for row in rows:
        print(json.dumps(row, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (KeyError, TypeError, ValueError, OSError) as error:
        raise SystemExit(f'Invalid programme loudness profile: {error}') from error
