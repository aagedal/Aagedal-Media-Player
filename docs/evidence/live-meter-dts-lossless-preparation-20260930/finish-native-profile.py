#!/usr/bin/env python3
"""Independently recheck the native run and retain compact non-media evidence."""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

repository = Path('/Users/truls.aagedal/Developer/Aagedal-Media-Player')
evidence = Path(__file__).resolve().parent
profile = Path('/private/tmp/aagedal-dts-lossless-native-20260930')


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


identities = json.loads((profile / 'candidate-identities-before.json').read_text())
after = {path: sha(path) for path in identities}
assert after == identities
write(profile / 'candidate-identities-after.json', after)
qualification = json.loads((evidence / 'qualification-summary.json').read_text())
for form in ['source', 'elementary', 'prepared']:
    assert sha(qualification[form]['path']) == qualification[form]['sha256']
sources = json.loads((profile / 'meter-source-comparison-before.json').read_text())
for path, identity in sources.items():
    assert sha(repository / path) == identity['currentSHA256'], path
write(profile / 'meter-source-comparison-after.json', sources)
command = ['/usr/bin/python3', str(repository / 'scripts/validate-live-audio-meter-profile.py'), str(profile)]
result = subprocess.run(command, capture_output=True, text=True)
write(evidence / 'native-validation-command.json', {
    'arguments': command, 'exitCode': result.returncode,
    'stdout': result.stdout, 'stderr': result.stderr,
})
assert result.returncode == 0
command = ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
           '--path', str(profile / 'LiveAudioMeterProfile.xcresult')]
result = subprocess.run(command, capture_output=True, text=True)
assert result.returncode == 0
summary = json.loads(result.stdout)
assert summary['result'] == 'Passed' and summary['passedTests'] == 1
assert summary['failedTests'] == 0 and summary['skippedTests'] == 0
write(evidence / 'native-xcresult-command.json', {'arguments': command, 'exitCode': result.returncode})
(profile / 'xcresult-summary.json').write_text(result.stdout)
for name in ['candidate-identities-after.json', 'meter-source-comparison-after.json',
             'summary.json', 'xcresult-summary.json', 'power-start.txt', 'power-end.txt',
             'power-events.json', 'profile-start.txt', 'profile-end.txt',
             'concurrent-processes-start.txt', 'runner.log']:
    (evidence / ('native-' + name)).write_bytes((profile / name).read_bytes())
(evidence / 'native-profile.log.gz').write_bytes(gzip.compress((profile / 'profile.log').read_bytes(), mtime=0))
attachment_dir = evidence / 'native-attachments'
attachment_dir.mkdir(exist_ok=True)
for path in (profile / 'attachments').iterdir():
    if path.is_file():
        (attachment_dir / path.name).write_bytes(path.read_bytes())
write(evidence / 'native-external-results-sha256.json', {
    str(path): sha(path) for path in (profile / 'LiveAudioMeterProfile.xcresult').rglob('*')
    if path.is_file()
})
log = (profile / 'profile.log').read_text()
marker = 'LIVE_AUDIO_METER_PLAYBACK_DIAGNOSTIC '
diagnostics = [json.loads(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]
assert len(diagnostics) == 2
assert {diagnostic['stage'] for diagnostic in diagnostics} == {'observation-start', 'eof-start'}
for diagnostic in diagnostics:
    assert diagnostic['mpvDecodedAudioChannels'] == 6
    assert diagnostic['mpvOutputAudioChannels'] == 2
    assert diagnostic['mpvAudioOutputDriver'] == 'coreaudio'
write(evidence / 'native-playback-diagnostics.json', diagnostics)
row = json.loads((profile / 'summary.json').read_text())[0]
assert row['eof']['endSourceFrame'] == qualification['sourceFrameCount']
assert row['eof']['syntheticInitialSilenceFrameCount'] == 0
proof = {
    'xcresult': str(profile / 'LiveAudioMeterProfile.xcresult'),
    'passedTests': 1, 'profileValidationExitCode': 0,
    'appTestFrameworkIdentitiesUnchanged': True,
    'mediaIdentitiesUnchanged': True, 'meterSourceContextUnchangedDuringRun': True,
    'preparedExactFrameEndpointMatchesIndependentQualification': True,
    'nativeOutputDriver': 'coreaudio', 'nativeOutputChannels': 2,
    'decodedSourceChannels': 6, 'diagnosticCount': len(diagnostics),
    'scope': 'Authentic DTS-HD MA coded prefix on explicitly prepared new source clock, existing GPL/Metal development candidate; no original-container, audible, surround-device or numerical calibration acceptance.',
    'row': row,
}
write(evidence / 'native-proof-summary.json', proof)
print(json.dumps(proof, indent=2))
