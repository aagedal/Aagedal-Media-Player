#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pin final binaries and run focused then sustained diagnostics serially."""
from pathlib import Path
import hashlib, json, subprocess, sys
root = Path.cwd()
base = Path('/private/tmp/aagedal-post-test-retirement-20261017')
evidence = Path(__file__).resolve().parent
app = base/'derived/Build/Products/Release/Aagedal Media Player.app'
def sha(p):
    with p.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()
inputs = [base/'native-fixtures.json', Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json'),
          app/'Contents/MacOS/Aagedal Media Player',
          app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests']
(base/'execution-inputs.json').write_text(json.dumps({str(p):sha(p) for p in inputs},indent=2)+'\n')
scripts = [root/'scripts/validate-mpv-native-app.py', root/'scripts/test-mpv-native-app-runner.py',
           *sorted(evidence.glob('*.py'))]
(base/'validation-inputs.json').write_text(json.dumps({str(p):sha(p) for p in scripts},indent=2)+'\n')
with (base/'signature-verification.txt').open('w') as log:
    subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],stdout=log,stderr=subprocess.STDOUT,check=True)
with (base/'runner-regressions.log').open('w') as log:
    subprocess.run([sys.executable,'scripts/test-mpv-native-app-runner.py'],stdout=log,stderr=subprocess.STDOUT,check=True)
command = [sys.executable,str(evidence/'run-focused.py'),str(next((base/'derived/Build/Products').glob('*.xctestrun'))),
           str(base/'native-fixtures.json'),'/private/tmp/aagedal-continuation-20261016-fixtures',
           '/private/tmp/aagedal-scopes-delta-restored-r3-20261015/delta/validation/signal-fixtures',
           '/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json',str(base/'focused')]
(base/'run-focused-command.json').write_text(json.dumps(command,indent=2)+'\n')
with (base/'focused-runner.log').open('w') as log:
    subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run([sys.executable,str(evidence/'run-diagnostic.py')],check=True)
