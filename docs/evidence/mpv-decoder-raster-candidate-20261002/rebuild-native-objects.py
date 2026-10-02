# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Truls Aagedal
import json,shlex,subprocess,pathlib,shutil
base=pathlib.Path('/tmp/aagedal-coreaudio-clean-build-v4-20260930/MPVKit/dist/libmpv/macos/scratch/arm64');out=pathlib.Path('/tmp/aagedal-decoder-raster-runtime-20261002');new=pathlib.Path('/tmp/aagedal-decoder-raster-candidate-20261002')
if not out.exists():shutil.copytree(base,out,symlinks=True)
for row in json.loads((base/'compile_commands.json').read_text()):
 if pathlib.Path(row['file']).name not in ['f_decoder_wrapper.c','screenshot.c','command.c']:continue
 args=shlex.split(row['command']);result=[]
 for a in args:
  if 'libmpv-v0.41.0' in a:
   prefix='-I' if a.startswith('-I') else '';a=prefix+str(new/a.split('libmpv-v0.41.0',1)[1].lstrip('/'))
  result.append(a)
 subprocess.run(result,cwd=out,check=True)
link=subprocess.check_output(['ninja','-C',str(base),'-t','commands','mpv'],text=True).splitlines()[-1]
(out/'link-command.txt').write_text(link+'\n');subprocess.run(shlex.split(link),cwd=out,check=True)
