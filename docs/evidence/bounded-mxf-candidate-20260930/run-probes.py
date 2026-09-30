#!/usr/bin/env python3
"""Compare two isolated URL-reader probe binaries in fresh serial processes.

Build each package's Benchmark target with probe.swift temporarily substituted,
using identical Release flags. This runner never writes to media or sidecars.
It stores complete exporter output and checks source/binary SHA256 before/after.
"""
import argparse
import datetime
import hashlib
import json
import platform
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--candidate', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--qualification', required=True)
parser.add_argument('inputs', type=Path, nargs='+')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            sha.update(chunk)
    return {'bytes': path.stat().st_size, 'sha256': sha.hexdigest()}


tracked = [args.baseline, args.candidate, *args.inputs]
for path in args.inputs:
    tracked.extend(p for p in path.parent.iterdir()
                   if p.is_file() and p.suffix.lower() == '.xml' and p.stem.startswith(path.stem))
identities = {str(path): digest(path) for path in tracked}
environment = {
    'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'platform': platform.platform(), 'machine': platform.machine(),
    'qualification': args.qualification,
    'scope': 'Fresh standalone library URL-read processes; no app cache/production acceptance.',
    'ordering': 'Baseline then candidate for each input; filesystem cache is not controlled.',
    'identitiesBefore': identities,
}
(args.output / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
rows = []
for index, path in enumerate(args.inputs):
    results = {}
    for mode, binary in [('baseline', args.baseline), ('candidate', args.candidate)]:
        target = args.output / f'input-{index}-{mode}.json'
        subprocess.run([str(binary), str(path), str(target)], check=True)
        results[mode] = json.loads(target.read_text())
    parity = results['baseline']['exporter'] == results['candidate']['exporter']
    if not parity:
        raise RuntimeError(f'Complete exporter parity failed for {path}')
    row = {'path': str(path), 'inputBytes': path.stat().st_size, 'completeExporterParity': parity}
    for mode, result in results.items():
        row[mode] = {key: result[key] for key in ['wallSeconds', 'before', 'afterLoad', 'afterRelease']}
        row[mode]['lifetimePeakIncreaseBytes'] = (
            result['afterLoad']['lifetimePeakResidentBytes'] - result['before']['lifetimePeakResidentBytes'])
    rows.append(row)
    print(f'{path.name}: complete exporter parity passed', flush=True)
identities_after = {str(path): digest(path) for path in tracked}
assert identities == identities_after, 'Input or binary identity changed during probes'
environment['identitiesUnchangedAfter'] = True
environment['endedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(args.output / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
(args.output / 'summary.json').write_text(json.dumps(rows, indent=2) + '\n')
