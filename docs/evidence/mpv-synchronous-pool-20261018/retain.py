#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain exact experiment and focused verification evidence after validation."""
from pathlib import Path
import gzip
import hashlib
import json
import shutil
import subprocess

root = Path.cwd()
evidence = Path(__file__).resolve().parent
base = Path('/private/tmp/aagedal-synchronous-pool-20261018')
summary = json.loads((base/'focused/summary.json').read_text())
assert summary['result'] == 'Passed' and summary['failedTests'] == 0 and summary['skippedTests'] == 0
assert (base/'pool-summary.json').is_file()
files = ['execution-inputs.json', 'collection-inputs.json', 'signature-verification.txt', 'pool-summary.json',
         'focused/summary.json', 'focused/command.json', 'focused/executed-configuration.plist']
for name in files:
    target = evidence/name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(base/name, target)
for name in ['build.log', 'focused/xcodebuild.log', 'focused/action.log', 'pool-observations.json',
             'initial-run-validation.py', 'initial-collection-rejection.log']:
    target = evidence/(name+'.gz')
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('wb') as out:
        with gzip.GzipFile(filename='', mode='wb', fileobj=out, mtime=0) as compressed:
            compressed.write((base/name).read_bytes())
source = root/'Aagedal Media Player Tests/LiveLoupeSessionTests.swift'
prepared = base/'app/Aagedal Media Player Tests/LiveLoupeSessionTests.swift'
assert source.read_bytes() == prepared.read_bytes()
receipt = {
    'sourceBaseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'testSourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'architecture': 'arm64', 'configuration': 'Release',
    'mpvRebuilt': False, 'productionBehaviorChanged': False,
    'focusedPassedTests': summary['passedTests'], 'failedTests': 0, 'skippedTests': 0,
    'rawPoolObservationsSHA256': hashlib.sha256((base/'pool-observations.json').read_bytes()).hexdigest(),
    'fixtureManifestsSHA256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [
        base/'native-fixtures.json',
        Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json')]},
}
(evidence/'candidate-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
delta = subprocess.check_output(['git', 'diff', '--', str(source.relative_to(root))])
with (evidence/'test-source.patch.gz').open('wb') as out:
    with gzip.GzipFile(filename='', mode='wb', fileobj=out, mtime=0) as compressed:
        compressed.write(delta)
# Record retained-byte identity, including helpers and interpretation written
# before this retention step. The manifest itself is excluded.
checksums = {str(p.relative_to(evidence)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(evidence.rglob('*'))
             if p.is_file() and '__pycache__' not in p.parts and p.name != 'evidence-sha256.json'}
(evidence/'evidence-sha256.json').write_text(json.dumps(checksums, indent=2)+'\n')
print('Retained focused verification and complete scalar observations')
