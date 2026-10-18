#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain actual results without promoting diagnostic collection to acceptance."""
from pathlib import Path
import gzip
import hashlib
import json
import shutil
import subprocess

root = Path.cwd()
base = Path('/private/tmp/aagedal-allocation-stacks-20261018')
out = Path(__file__).resolve().parent

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

for source in ('build.log', 'build-unsandboxed.log', 'validation.log', 'focused/xcodebuild.log',
               'focused/action.log', 'soak/xcodebuild.log', 'soak/action.log'):
    path = base/source
    if path.exists():
        (out/(source.replace('/', '-')+'.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
for name in ('execution-inputs.json', 'signature-verification.txt', 'runner-regressions.log',
             'collector-regressions.log', 'final-runner-regressions.log', 'final-collector-regressions.log',
             'final-verification-inputs.json', 'soak-command.json', 'soak-summary.json', 'validation-result.json',
             'focused-runner.log', 'soak-runner.log'):
    if (base/name).exists(): shutil.copy2(base/name, out/name)
for source, target in [('focused/summary.json', 'focused-summary.json'),
                       ('focused/executed-configuration.plist', 'focused-executed-configuration.plist'),
                       ('focused/command.json', 'focused-command.json'),
                       ('soak/executed-configuration.plist', 'soak-executed-configuration.plist'),
                       ('soak/command.json', 'soak-xcodebuild-command.json'),
                       ('soak/allocation-command.json', 'allocation-command.json'),
                       ('soak/allocation-collector.log', 'allocation-collector.log')]:
    if (base/source).exists(): shutil.copy2(base/source, out/target)
for directory in ('memory-diagnostics', 'allocation-stacks'):
    source = base/'soak'/directory
    if source.exists():
        shutil.copytree(source, out/directory, dirs_exist_ok=True)
        if directory == 'allocation-stacks':
            archives = {}
            for report in sorted((out/directory).glob('*.txt')):
                original = report.read_bytes()
                archive = report.with_name(report.name+'.gz')
                archive.write_bytes(gzip.compress(original, mtime=0))
                archives[report.name] = {'archive': archive.name, 'originalSHA256': sha(report), 'archiveSHA256': sha(archive)}
                report.unlink()
            (out/directory/'report-archives.json').write_text(json.dumps(archives, indent=2)+'\n')
subprocess.run(['python3', str(out/'summarize.py')], check=True)
(out/'host-processes.txt.gz').write_bytes(gzip.compress((base/'host-processes.txt').read_bytes(), mtime=0))
previous = json.loads((root/'docs/evidence/mpv-comparison-scope-provenance-20261016/candidate-receipt.json').read_text())
for path, expected in previous['fixturesSHA256'].items():
    assert sha(Path(path)) == expected, path
libmpv = Path('/private/tmp/aagedal-scopes-delta-restored-r3-20261015/MPVKit/Candidate/Libmpv-GPL/Libmpv.xcframework/macos-arm64/Libmpv.framework/Versions/A/Libmpv')
assert sha(libmpv) == previous['libmpvSHA256']
source_files = {}
for directory in ('Aagedal Media Player', 'Aagedal Media Player Tests'):
    for path in sorted((root/directory).rglob('*.swift')):
        relative = path.relative_to(root)
        assert sha(path) == sha(base/'app'/relative), relative
        source_files[str(relative)] = sha(path)
app = base/'derived/Build/Products/Release/Aagedal Media Player.app'
binaries = [app/'Contents/MacOS/Aagedal Media Player',
            app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests']
pins = {}
for path in binaries:
    archs = subprocess.check_output(['lipo', '-archs', str(path)], text=True).strip()
    assert archs == 'arm64', archs
    pins[str(path)] = {'sha256': sha(path), 'architectures': archs}
receipt = {'baseCommit': subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
           'sourceSHA256': source_files, 'binaries': pins,
           'fixturesSHA256': previous['fixturesSHA256'], 'libmpvSHA256': sha(libmpv),
           'shippingPinsSHA256': sha(root/'Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),
           'retentionScriptSHA256': sha(Path(__file__)),
           'retainedSHA256': {str(p.relative_to(out)): sha(p) for p in sorted(out.rglob('*'))
                              if p.is_file() and p.name != 'candidate-receipt.json' and '__pycache__' not in p.parts}}
(out/'candidate-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print('Retained results and arm64 source/binary identity; inspect summaries for actual acceptance')
