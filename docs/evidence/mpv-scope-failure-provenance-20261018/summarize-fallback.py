#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarize bounded diagnostic samples; never infer reasons for unlogged events."""
from collections import Counter
import itertools
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
source = root/('soak-action.log.gz' if (root/'soak-action.log.gz').exists() else 'action.log.gz')

def outputs(node):
    if isinstance(node, dict):
        if node.get('testName') == 'testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory()' and isinstance(node.get('emittedOutput'), str):
            yield node['emittedOutput']
        for value in node.values():
            yield from outputs(value)
    elif isinstance(node, list):
        for value in node:
            yield from outputs(value)

text = list(outputs(json.loads(gzip.decompress(source.read_bytes()))))
assert len(text) == 1, 'Expected exactly one source-test output'
details = []
counters = []
for line in text[0].splitlines():
    fields = dict(re.findall(r'(\w+)=([^,]+)', line))
    if line.startswith('MPV_COMPARISON_SCOPE_NATIVE_FALLBACK:'):
        details.append(fields)
    elif line.startswith('MPV_COMPARISON_SCOPE_NATIVE_FALLBACK_COUNTS:'):
        counters.append(fields)
expected = set(itertools.product(('1', '2', '3'),
    ('uhd-h264-hardware/pq-hevc-hardware', 'pq-hevc-hardware/hlg-hevc-hardware')))
assert len(counters) == 6 and {(row['cycle'], row['pair']) for row in counters} == expected
assert all((row['cycle'], row['pair']) in expected and row['source'] in ('0', '1') for row in details)
assert len({(row['cycle'], row['pair'], row['source'], row['sequence']) for row in details}) == len(details)
observed = Counter((row['cycle'], row['pair'], row['source']) for row in details)
for row in counters:
    for index, field in enumerate(('primary', 'secondary')):
        assert observed[row['cycle'], row['pair'], str(index)] == min(8, int(row[field]))
sampled = Counter((row['reason'], row['status'], row['payload']) for row in details)
summary = dict(
    detailBudgetPerSourcePerPair=8,
    sampledPublications=len(details),
    totalPublicationsFromCompletedPairCounters=sum(int(row['primary']) + int(row['secondary']) for row in counters),
    completedPairCounters=counters,
    sampledReasonStatusPayloadCounts=[dict(reason=k[0], status=k[1], payload=k[2], count=v) for k, v in sorted(sampled.items())],
    samples=details,
    sourceArchiveSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
    analysisScriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    limits='Details are bounded samples; counters include unlogged events. No reason is inferred for unlogged events; no internal provider cause is attributed.'
)
(root/'native-fallback-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps({k: summary[k] for k in ('sampledPublications', 'totalPublicationsFromCompletedPairCounters', 'sampledReasonStatusPayloadCounts')}, indent=2))
