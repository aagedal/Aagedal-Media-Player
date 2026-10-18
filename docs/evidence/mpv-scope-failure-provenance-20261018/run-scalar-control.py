# SPDX-License-Identifier: GPL-3.0-or-later
"""Fresh-process scalar control; require unchanged accepted candidate inputs."""
from pathlib import Path
import datetime, hashlib, json, subprocess, sys, threading
base=Path('/private/tmp/aagedal-scope-failure-provenance-20261018')
pins=json.loads((base/'execution-inputs.json').read_text())
for path, expected in pins.items():
    assert hashlib.file_digest(Path(path).open('rb'), 'sha256').hexdigest() == expected, path
control_inputs = dict(pins)
for path in [Path(__file__).resolve(), Path('scripts/validate-mpv-native-app.py').resolve()]:
    control_inputs[str(path)] = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
(base/'scalar-control-execution-inputs.json').write_text(json.dumps(control_inputs, indent=2)+'\n')
stop=threading.Event()
def snapshot():
    with (base/'host-processes.txt').open('a') as log:
        while True:
            log.write('\n'+datetime.datetime.now().isoformat()+'\n'); log.flush()
            subprocess.run(['ps','-axo','pid,ppid,etime,%cpu,comm'],stdout=log,stderr=subprocess.STDOUT)
            if stop.wait(60): break
thread=threading.Thread(target=snapshot); thread.start()
command=[sys.executable,'scripts/validate-mpv-native-app.py',
 str(next((base/'derived/Build/Products').glob('*.xctestrun'))),
 '/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json',str(base/'scalar-control'),
 '--comparison','--active-scopes','--scope-provenance','--memory-diagnostics',
 '--post-test-retirement','--scalar-memory-diagnostics','--scope-resolution','720','--scope-fps','15','--soak-seconds','10','--soak-cycles','3']
try:
    with (base/'scalar-control-runner.log').open('w') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
finally:
    stop.set();thread.join()
sys.exit(result.returncode)
