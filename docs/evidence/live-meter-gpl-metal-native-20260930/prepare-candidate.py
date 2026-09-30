#!/usr/bin/env python3
"""Copy the current test host and replay its compiler-generated linker command."""
from pathlib import Path
import hashlib
import json
import plistlib
import shlex
import subprocess
import sys

repository = Path(__file__).resolve().parents[3]
link_log = Path(sys.argv[1]).resolve()
base = Path(sys.argv[2]).resolve()
derived = Path('/private/tmp/aagedal-2-continuation-focused-20260930/DerivedData')
original_app = derived / 'Build/Products/Release/Aagedal Media Player.app'
build = Path(sys.argv[3]).resolve()
receipt = json.loads((build / 'receipt.json').read_text())
assert receipt['verification']['shippingFeatureParity']['product'] == 'MPVKit-GPL'
verification = subprocess.check_output([
    sys.executable, str(build / 'builder.py'), '--verify', str(build)
], text=True)

commands = [shlex.split(line.strip()) for line in link_log.read_text().splitlines()
            if '/usr/bin/clang ' in line and ' -o ' in line]
commands = [command for command in commands if '-o' in command
            and command[command.index('-o') + 1].endswith('.app/Contents/MacOS/Aagedal Media Player')]
assert len(commands) == 1, len(commands)
command = commands[0]
base.mkdir(parents=True, exist_ok=False)
(base / 'dependency-verification.log').write_text(verification)
(base / 'dependency-verification.json').write_bytes((build / 'shipping-verification.json').read_bytes())
candidate_directory = base / 'candidate'
candidate_directory.mkdir()
app = candidate_directory / original_app.name
subprocess.run(['/usr/bin/ditto', str(original_app), str(app)], check=True)

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

original_paths = [original_app / 'Contents/MacOS/Aagedal Media Player',
                  original_app / 'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests']
(base / 'original-identities-before.json').write_text(json.dumps({str(p): sha(p) for p in original_paths}, indent=2) + '\n')
(candidate_directory / 'original-link-command.json').write_text(json.dumps(command, indent=2) + '\n')
command[command.index('-o') + 1] = str(app / 'Contents/MacOS/Aagedal Media Player')
for option, name in [('-object_path_lto', 'player_lto.o'), ('-dependency_info', 'player_dependency_info.dat')]:
    index = command.index(option) + 1
    assert command[index] == '-Xlinker'
    command[index + 1] = str(candidate_directory / name)
framework_roots = [build / 'MPVKit/dist/libmpv/macos', build / 'MPVKit/dist/FFmpeg/macos']
command[1:1] = ['-F' + str(p) for p in framework_roots]
command.extend(['-Xlinker', '-map', '-Xlinker', str(candidate_directory / 'link.map')])
(candidate_directory / 'relink-command.json').write_text(json.dumps(command, indent=2) + '\n')
with (candidate_directory / 'relink.log').open('w') as log:
    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], capture_output=True, check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, check=True)
frameworks = [p for root in framework_roots for p in root.glob('*.framework')]
assert len(frameworks) == 8
link_map = (candidate_directory / 'link.map').read_text(errors='replace')
origins = {}
for framework in frameworks:
    assert str(framework / framework.stem) in link_map, framework
    origins[framework.stem] = str(framework / framework.stem)
(candidate_directory / 'fresh-framework-link-origins.json').write_text(json.dumps(origins, indent=2) + '\n')

run_directory = base / 'authentic-5s'
run_directory.mkdir()
historical = Path('/private/tmp/aagedal-live-authentic-20260930')
inventory = json.loads((historical / 'input-inventory.json').read_text())
inputs = [{'path': inventory[i]['path'], 'sha256': inventory[i]['sha256'],
           'audioStreamOrderIndex': ordinal, 'audioTrackSelectionExplicit': True}
          for i, ordinal in [(0, 0), (2, 0), (2, 7)]]
for request in inputs:
    assert sha(request['path']) == request['sha256'], request['path']
(run_directory / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
run = plistlib.loads((historical / 'fullbuild-fx6-120s/candidate.xctestrun').read_bytes())
for target in run['TestConfigurations'][0]['TestTargets']:
    target['TestHostPath'] = str(app)
    environment = target.setdefault('EnvironmentVariables', {})
    environment['LIVE_AUDIO_METER_PROFILE_INPUTS'] = json.dumps(inputs)
    environment['LIVE_AUDIO_METER_PROFILE_SECONDS'] = '5'

def resolve(value):
    if isinstance(value, dict):
        return {key: resolve(item) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item) for item in value]
    if isinstance(value, str):
        return value.replace(str(historical / 'fullbuild-repaired-candidate/Aagedal Media Player.app'), str(app)).replace(
            '/private/tmp/aagedal-live-authentic-current-dd-20260930', str(derived))
    return value

(run_directory / 'candidate.xctestrun').write_bytes(plistlib.dumps(resolve(run)))
identity_paths = [app / 'Contents/MacOS/Aagedal Media Player',
                  app / 'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',
                  run_directory / 'candidate.xctestrun', candidate_directory / 'link.map',
                  candidate_directory / 'relink-command.json', build / 'receipt.json', build / 'builder.py']
identity_paths += [framework / framework.stem for framework in frameworks]
(run_directory / 'candidate-identities-before.json').write_text(json.dumps({str(p): sha(p) for p in identity_paths}, indent=2) + '\n')
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True)
status = subprocess.check_output(['git', 'status', '--short'], cwd=repository, text=True)
(base / 'source-status.txt').write_text(head + status)
(base / 'source.diff').write_text(subprocess.check_output(['git', 'diff'], cwd=repository, text=True))
sources = list((repository / 'Aagedal Media Player').rglob('*.swift')) + list((repository / 'Aagedal Media Player Tests').rglob('*.swift'))
(base / 'source-sha256.json').write_text(json.dumps({str(p.relative_to(repository)): sha(p) for p in sources}, indent=2) + '\n')
environment = head + status + subprocess.check_output(['sw_vers'], text=True)
environment += subprocess.check_output(['xcodebuild', '-version'], text=True)
environment += 'Build configuration: Release\nObservation seconds: 5\nCurrent dirty source host; copied test bundle; local GPL/Metal dependency candidate.\n'
(run_directory / 'environment.txt').write_text(environment)
print(run_directory)
