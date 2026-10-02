# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Truls Aagedal
from pathlib import Path
import subprocess,json,hashlib,gzip
p=Path(__file__).resolve().parent;r=Path('/tmp/aagedal-decoder-raster-candidate-20261002')
(p/'provider-qualified-candidate.patch').write_bytes(subprocess.check_output(['git','-C',str(r),'diff']))
subprocess.run(['python3',str(p/'verify-qualified.py'),'/tmp/aagedal-coreaudio-clean-build-v4-20260930/MPVKit/dist/libmpv-v0.41.0','/tmp/aagedal-coreaudio-clean-build-v4-20260930/MPVKit/dist/libmpv/macos/scratch','--report',str(p/'syntax-qualified.json')],check=True)
runs=[]
for mode in ['enabled','queue','default','no']:
 args=[str(p/'harness'),str(p/'numbered-grid.mkv')]+([] if mode=='enabled' else [mode])
 with (p/f'runtime-{mode}.jsonl').open('w') as f:completed=subprocess.run(args,stdout=f)
 runs.append({'mode':mode,'arguments':args,'exitCode':completed.returncode,'results':(p/f'runtime-{mode}.jsonl').read_text()})
 with gzip.open(p/f'native-runtime-{mode}.log.gz','wb') as log:log.write(Path('/tmp/aagedal-decoder-provider-runtime.log').read_bytes())
 print(mode,completed.returncode,flush=True)
for case in ['square-rotated.mp4','anamorphic.mkv']:
 args=[str(p/'harness'),str(p/case),'reject']
 with (p/f'runtime-{case}.jsonl').open('w') as output:completed=subprocess.run(args,stdout=output)
 with gzip.open(p/f'native-runtime-{case}.log.gz','wb') as log:log.write(Path('/tmp/aagedal-decoder-provider-runtime.log').read_bytes())
 runs.append({'mode':case,'arguments':args,'exitCode':completed.returncode,'results':(p/f'runtime-{case}.jsonl').read_text()})
 print(case,completed.returncode,flush=True)
files=['square-rotated.mp4','anamorphic.mkv','provider-qualified-candidate.patch','harness.c','harness','harness.o','link-command.txt','harness-link-command.json','numbered-grid.mkv','numbered-grid.rgb','generate-grid.py','syntax-qualified.json']
(p/'runtime-receipt.json').write_text(json.dumps({'runs':runs,'sha256':{n:hashlib.sha256((p/n).read_bytes()).hexdigest() for n in files},'scope':'isolated arm64 native libmpv object-linked harness; no published package or app integration; no hardware/rotated/reflected/PAR positive qualification'},indent=2)+'\n')
if any(run['exitCode'] for run in runs):raise SystemExit(1)
