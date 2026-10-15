#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify the native-scope delta, overlay a NEW pinned arm64 package, prepare app.

First restore the baseline with restore-mpv-decoder-raster-candidate.py. This
script verifies both inventories before replacing libmpv in a new package copy.
The baseline, source checkout, shipping pins and raster default-off gate remain
unchanged. No dependency compilation is required to use the prepared package.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil


def main():
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('restore', root/'scripts/restore-mpv-decoder-raster-candidate.py')
    restore = importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('baseline',type=Path);p.add_argument('archive',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--descriptor',type=Path,default=root/'docs/mpv-scopes-handoff.json')
    p.add_argument('--prepare-app',type=Path);p.add_argument('--app-output',type=Path)
    a = p.parse_args()
    if bool(a.prepare_app) != bool(a.app_output):p.error('both app options are required together')
    baseline,output = a.baseline.resolve(),a.output.resolve()
    restore.verify_restored(baseline,json.loads((root/'docs/mpv-decoder-raster-handoff.json').read_text()))
    if output.exists():raise ValueError('output must be new')
    output.mkdir(parents=True)
    metadata = restore.restore(a.archive,output/'delta',json.loads(a.descriptor.read_text()))
    if metadata['baselineInventorySHA256'] != restore.sha(baseline/'bundle.json'):
        raise ValueError('scope delta requires a different baseline')
    package = output/'MPVKit'
    shutil.copytree(baseline/'MPVKit',package,symlinks=True)
    binary = package/'Candidate/Libmpv-GPL/Libmpv.xcframework/macos-arm64/Libmpv.framework/Versions/A/Libmpv'
    shutil.copyfile(output/'delta/libmpv.a',binary)
    print('Prepared verified native scope package:',package)
    if a.prepare_app:
        restore.prepare_app(a.prepare_app,package,a.app_output)
        print('Prepared app:',a.app_output)


if __name__=='__main__':main()
