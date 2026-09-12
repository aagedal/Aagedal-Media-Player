#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain profile-interval power events and reject timings interrupted by sleep."""
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

PATTERN = re.compile(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) [+-]\d{4}\s+(Sleep|DarkWake|Wake)\s+\t(.*)$')


def events_during(log, start, end):
    start_time = datetime.strptime(start, '%Y-%m-%d %H:%M:%S')
    end_time = datetime.strptime(end, '%Y-%m-%d %H:%M:%S')
    if end_time < start_time:
        raise ValueError('Profile clock moved backwards')
    events = []
    for line in log.splitlines():
        match = PATTERN.match(line)
        if match:
            stamp, kind, detail = match.groups()
            if start_time <= datetime.strptime(stamp, '%Y-%m-%d %H:%M:%S') <= end_time:
                events.append(dict(time=stamp, kind=kind, detail=detail.strip()))
    return events


def main():
    start, end, directory = sys.argv[1:]
    result = subprocess.run(['/usr/bin/pmset', '-g', 'log'], check=True, capture_output=True, text=True)
    events = events_during(result.stdout, start, end)
    report = dict(start=start, end=end, events=events,
                  sleepObserved=any(event['kind'] == 'Sleep' for event in events))
    (Path(directory) / 'power-events.json').write_text(json.dumps(report, indent=2) + '\n')
    if report['sleepObserved']:
        raise ValueError('System sleep interrupted this profile; retained measurements are not clean performance evidence')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f'Invalid programme profile power evidence: {error}') from error
