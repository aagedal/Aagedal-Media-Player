#!/usr/bin/env python3
"""Bind the qualified preparation to the existing GPL/Metal native test host."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess


repository = Path('/Users/truls.aagedal/Developer/Aagedal-Media-Player')
evidence = Path(__file__).resolve().parent
previous = repository / 'docs/evidence/live-meter-gpl-metal-native-20260930'
profile = Path('/private/tmp/aagedal-dts-lossless-native-20260930')
profile.mkdir(exist_ok=False)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


identities = json.loads((previous / 'authentic-5s/candidate-identities-after.json').read_text())
for path, expected in identities.items():
    assert sha(path) == expected, path
write(profile / 'candidate-identities-before.json', identities)
qualification = json.loads((evidence / 'qualification-summary.json').read_text())
media = qualification['prepared']
assert sha(media['path']) == media['sha256']
inputs = [{'path': media['path'], 'sha256': media['sha256'],
           'audioStreamOrderIndex': 0, 'audioTrackSelectionExplicit': True}]
write(profile / 'inputs.json', inputs)
run = plistlib.loads(Path('/private/tmp/aagedal-live-meter-gpl-metal-native-ready-20260930/authentic-5s/candidate.xctestrun').read_bytes())
for target in run['TestConfigurations'][0]['TestTargets']:
    env = target.setdefault('EnvironmentVariables', {})
    env['LIVE_AUDIO_METER_PROFILE_INPUTS'] = json.dumps(inputs)
    env['LIVE_AUDIO_METER_PROFILE_SECONDS'] = '20'
(profile / 'candidate.xctestrun').write_bytes(plistlib.dumps(run))
sources = json.loads((previous / 'source-sha256.json').read_text())
source_check = {}
for path, retained in sources.items():
    if 'LiveAudioMeter' not in path:
        continue
    current = sha(repository / path)
    result = {'retainedBuildSHA256': retained, 'currentSHA256': current,
              'exactMatch': current == retained}
    if not result['exactMatch'] and path.endswith('/LiveAudioMeterDecoder.swift'):
        baseline = subprocess.check_output(['git', 'show', '060f611f7ba1d669a1af7b7846cdf1812f53b531:' + path], cwd=repository)
        assert hashlib.sha256(baseline).hexdigest() == retained
        def code(data):
            return '\n'.join(line for line in data.decode().splitlines()
                             if not line.strip().startswith('//'))
        result['onlyFullLineCommentChanges'] = code(baseline) == code((repository / path).read_bytes())
        assert result['onlyFullLineCommentChanges']
    source_check[path] = result
write(profile / 'meter-source-comparison-before.json', source_check)
context = {
    'candidateBuildSourceHEAD': '060f611f7ba1d669a1af7b7846cdf1812f53b531',
    'candidateBuildDirtyInputs': str(previous / 'source.diff'),
    'currentRunContextHEAD': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip(),
    'candidateSourceHashes': str(previous / 'source-sha256.json'),
    'qualificationSummarySHA256': sha(evidence / 'qualification-summary.json'),
    'newManifestSHA256': sha(profile / 'inputs.json'),
    'newXCTestRunSHA256': sha(profile / 'candidate.xctestrun'),
    'observationSeconds': 20,
    'scope': 'Existing development test host, authentic DTS-HD MA coded payload on explicitly new source clock; stereo native output; no audible claim.',
}
write(profile / 'native-context.json', context)
(profile / 'environment.txt').write_text(
    context['currentRunContextHEAD'] + '\n' + subprocess.check_output(['sw_vers'], text=True)
    + 'Build configuration: Release\nObservation seconds: 20\n'
    + 'Existing feature-qualified GPL/Metal candidate; original source context 060f611 plus retained dirty clock correction.\n'
)
for name in ['candidate-identities-before.json', 'inputs.json', 'candidate.xctestrun',
             'meter-source-comparison-before.json', 'native-context.json', 'environment.txt']:
    (evidence / name).write_bytes((profile / name).read_bytes())
print(profile)
