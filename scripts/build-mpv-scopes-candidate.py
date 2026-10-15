#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Incrementally rebuild arm64 libmpv from a retained candidate build.

Copies objects/sources before editing. Verifies the pinned reusable package,
compiles changed objects with the retained compile commands, and replaces only
libmpv in a NEW local package. Does not alter the original build or shipping pins.
This requires retained build objects; see MPV_NATIVE_RASTER_HANDOFF.md for a
full source reconstruction when those objects are unavailable.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import shutil
import subprocess


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def apply_scope_source(source, root):
    """Apply only to a new decoder-raster candidate source checkout."""
    newsource = source
    command = newsource/'player/command.c'
    text = command.read_text()
    anchor = '    { "aagedal-decoder-raster", cmd_aagedal_decoder_raster },'
    if text.count(anchor) != 1 or '"aagedal-scopes"' in text:
        raise ValueError('unexpected or already patched baseline')
    inputs = {}
    for name in ('scope_math.h','scope_provider.inc'):
        p = root/'docs/dependency-patches/scopes'/name
        inputs[name] = sha(p)
        shutil.copyfile(p, newsource/'player'/name)
    screenshot = newsource/'player/screenshot.c'
    screenshot.write_text(screenshot.read_text()+'\n#include "scope_provider.inc"\n')
    header = newsource/'player/screenshot.h'
    header.write_text(header.read_text()+'\nvoid cmd_aagedal_scopes(void *p);\n')
    command.write_text(text.replace(anchor, anchor+'\n    { "aagedal-scopes", cmd_aagedal_scopes,\n        {{"width", OPT_INT(v.i), M_RANGE(64, 1440)}}, .spawn_thread = true },'))
    return inputs


def build(args):
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('restore', root/'scripts/restore-mpv-decoder-raster-candidate.py')
    restore = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restore)
    restore.verify_restored(args.bundle, json.loads((root/'docs/mpv-decoder-raster-handoff.json').read_text()))
    base = args.build/'MPVKit/dist/libmpv/macos/scratch/arm64'
    source = args.build/'MPVKit/dist/libmpv-v0.41.0'
    baseline = json.loads((args.build/'portable-build.json').read_text())
    if baseline['architectures'] != ['arm64'] or not baseline['buildSucceeded']:
        raise ValueError('requires validated arm64 baseline')
    revision = subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    dirty = subprocess.check_output(['git','-C',str(source),'status','--porcelain'],text=True)
    if dirty or revision != baseline['sourceInputs']['libmpv-v0.41.0']['candidateRevision']:
        raise ValueError('baseline source changed since its accepted build')
    out = args.output.resolve()
    out.mkdir(exist_ok=False, parents=True)
    newsource, objects = out/'source', out/'objects'
    shutil.copytree(source, newsource, symlinks=True, ignore=shutil.ignore_patterns('.git'))
    shutil.copytree(base, objects, symlinks=True)
    inputs = apply_scope_source(newsource, root)
    commands = []
    with (out/'build.log').open('w') as log:
        for row in json.loads((base/'compile_commands.json').read_text()):
            if Path(row['file']).name not in ('screenshot.c','command.c'): continue
            argv = shlex.split(row['command'])
            for i, arg in enumerate(argv):
                if 'libmpv-v0.41.0' in arg:
                    prefix = '-I' if arg.startswith('-I') else ''
                    argv[i] = prefix+str(newsource/arg.split('libmpv-v0.41.0',1)[1].lstrip('/'))
            commands.append(argv)
            subprocess.run(argv,cwd=objects,stdout=log,stderr=subprocess.STDOUT,check=True)
        # Replace freshly compiled members in the copied archive.
        subprocess.run(['ar','r','libmpv.a','libmpv.a.p/player_screenshot.c.o',
                        'libmpv.a.p/player_command.c.o'],cwd=objects,stdout=log,stderr=subprocess.STDOUT,check=True)
    package = out/'MPVKit'
    shutil.copytree(args.bundle/'MPVKit',package,symlinks=True)
    candidates = list((package/'Candidate/Libmpv-GPL').rglob('Libmpv.framework/Versions/A/Libmpv'))
    if len(candidates) != 1: raise ValueError('expected one arm64 framework')
    binary = candidates[0]
    shutil.copyfile(objects/'libmpv.a',binary)
    arch = subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()
    if arch != 'arm64': raise ValueError('unexpected architectures: '+arch)
    with (out/'source.patch').open('w') as patch:
        for name in ('screenshot.c','screenshot.h','command.c','scope_math.h','scope_provider.inc'):
            old = source/'player'/name
            subprocess.run(['diff','-u','--label','a/player/'+name if old.exists() else '/dev/null','--label','b/player/'+name,
                            str(old) if old.exists() else '/dev/null',str(newsource/'player'/name)],
                           stdout=patch,check=False)

    receipt = {'schemaVersion':1,'architectures':['arm64'],'providerInputs':inputs,
               'baselineReceiptSHA256':sha(args.build/'portable-build.json'),
               'baselineArchiveSHA256':sha(base/'libmpv.a'),'archiveSHA256':sha(binary),
               'compileCommands':commands,'package':str(package),'source':str(newsource),
               'scope':'Development candidate; new provider requires independent validation.'}
    (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(package)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build',type=Path)
    parser.add_argument('bundle',type=Path)
    parser.add_argument('output',type=Path)
    build(parser.parse_args())
