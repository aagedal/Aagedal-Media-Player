# SPDX-License-Identifier: GPL-3.0-or-later
"""Serial workload with passive once-a-minute host process snapshots."""
from pathlib import Path
import datetime, json, subprocess, sys, threading
base=Path('/private/tmp/aagedal-scalar-retirement-20261017')
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
 '/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json',str(base/('relationship-control' if '--relationships' in sys.argv else 'soak')),
 '--comparison','--active-scopes','--scope-provenance','--memory-diagnostics',
 '--post-test-retirement','--scope-resolution','720','--scope-fps','15','--soak-seconds','10','--soak-cycles','3']
if '--relationships' not in sys.argv:
    command.append('--scalar-memory-diagnostics')
try:
    with (base/('relationship-control-runner.log' if '--relationships' in sys.argv else 'soak-runner.log')).open('w') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
finally:
    stop.set();thread.join()
sys.exit(result.returncode)
