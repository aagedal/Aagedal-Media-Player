#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarize retained scalar observations; this does not infer ownership or leaks."""
from collections import Counter
import json
from pathlib import Path

root = Path(__file__).resolve().parent
samples = [json.loads((root / f'memory-cycle-{cycle}.json').read_text()) for cycle in range(4)]
for checkpoint in ('final-delayed', 'post-test-entry', 'post-test-delayed'):
    samples.append(json.loads((root / f'memory-{checkpoint}.json').read_text()))
summary = {}
previous = {}
for sample in samples:
    rows = {row['id']: row for row in sample['objects']}
    alive = [row for row in rows.values() if row['alive']]
    grouped = {}
    for origin in sorted({row['origin'] for row in alive}):
        grouped[origin] = dict(Counter(row['label'] for row in alive if row['origin'] == origin))
    summary[sample['checkpoint']] = dict(
        uptime=sample['uptime'],
        aliveByOrigin=grouped,
        newlyRetiredIDs=[identity for identity, row in rows.items()
                         if not row['alive'] and previous.get(identity, {}).get('alive', False)],
        aliveObjects=alive,
    )
    previous = rows
(root / 'retirement-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
