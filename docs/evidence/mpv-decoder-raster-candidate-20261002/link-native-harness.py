# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Truls Aagedal
from pathlib import Path
import shlex,subprocess
p=Path(__file__).resolve().parent
subprocess.run(['clang','-I/tmp/aagedal-decoder-raster-candidate-20261002/include','-arch','arm64','-mmacosx-version-min=12.0','-c',str(p/'harness.c'),'-o',str(p/'harness.o')],check=True)
a=shlex.split((p/'link-command.txt').read_text());a[a.index('mpv')]='harness';a[a.index('mpv.p/osdep_main-fn-mac.c.o')]='harness.o';subprocess.run(a,cwd=p,check=True)
(p/'harness-link-command.json').write_text(__import__('json').dumps(a,indent=2)+'\n')
