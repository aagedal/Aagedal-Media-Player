# SPDX-License-Identifier: GPL-3.0-or-later
"""Serial workload with passive once-a-minute host process snapshots."""
from pathlib import Path
import datetime, json, subprocess, sys, threading
base=Path('/private/tmp/aagedal-retirement-origins-20261017')
stop=threading.Event()
def snapshot():
    with (base/'host-processes.txt').open('a') as log:
        while True:
            log.write('\n'+datetime.datetime.now().isoformat()+'\n'); log.flush()
            subprocess.run(['ps','-axo','pid,ppid,etime,%cpu,comm'],stdout=log,stderr=subprocess.STDOUT)
            if stop.wait(60): break
thread=threading.Thread(target=snapshot); thread.start()
# Capture reference paths only after every cadence and cycle-end memory gate.
# Forking a corpse isolates graph analysis from the still-running XCTest.
def reference_graph():
    checkpoint = base/'soak/memory-diagnostics/cycle-3.json'
    while not stop.wait(.1):
        if checkpoint.exists():
            sample = json.loads(checkpoint.read_text())
            command = ['/usr/bin/leaks', '--forkCorpse',
                       '--outputGraph='+str(base/'final.memgraph'), str(sample['pid'])]
            (base/'reference-graph-command.json').write_text(json.dumps(command, indent=2)+'\n')
            with (base/'reference-graph.log').open('w') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=120)
            (base/'reference-graph-exit.txt').write_text(str(result.returncode)+'\n')
            return
graph_thread=threading.Thread(target=reference_graph); graph_thread.start()
command=[sys.executable,'scripts/validate-mpv-native-app.py',
 str(next((base/'derived/Build/Products').glob('*.xctestrun'))),
 '/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json',str(base/'soak'),
 '--comparison','--active-scopes','--scope-provenance','--memory-diagnostics',
 '--scope-resolution','720','--scope-fps','15','--soak-seconds','10','--soak-cycles','3']
try:
    with (base/'soak-runner.log').open('w') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
finally:
    stop.set();thread.join();graph_thread.join()
sys.exit(result.returncode)
