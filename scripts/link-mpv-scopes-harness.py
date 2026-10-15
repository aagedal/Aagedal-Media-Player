#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Link a NEW client using the retained build's static dependencies."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('baseline',type=Path);p.add_argument('candidate',type=Path)
p.add_argument('--gpu',action='store_true');a=p.parse_args()
base=a.baseline/'MPVKit/dist/libmpv/macos/scratch/arm64'
out=a.candidate.resolve();source=Path(__file__).with_name('mpv-scopes-harness.c').resolve()
name='scope-gpu' if a.gpu else 'scope-native'
compile=['clang','-O3','-arch','arm64','-mmacosx-version-min=12.0','-I'+str(out/'source/include')]
if a.gpu:compile+=['-x','objective-c','-fobjc-arc','-DSCOPE_GPU']
compile+=['-c',str(source),'-o',str(out/(name+'.o'))]
subprocess.run(compile,check=True)
link=shlex.split(subprocess.check_output(['ninja','-C',str(base),'-t','commands','mpv'],text=True).splitlines()[-1])
link[link.index('mpv')]=str(out/name)
link[link.index('mpv.p/osdep_main-fn-mac.c.o')]=str(out/(name+'.o'))
for object_name in ('player_screenshot.c.o','player_command.c.o'):
    member='libmpv.a.p/'+object_name
    link[link.index(member)]=str(out/'objects'/member)
subprocess.run(link,cwd=base,check=True)
(out/(name+'-link.json')).write_text(json.dumps({'compile':compile,'link':link},indent=2)+'\n')
