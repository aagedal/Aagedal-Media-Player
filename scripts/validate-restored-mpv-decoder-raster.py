#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rerun the retained native arm64 clients without compiling MPVKit or fixtures."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location('handoff', Path(__file__).with_name('restore-mpv-decoder-raster-candidate.py'))
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


def validate(root, output):
    if output.exists() or root == output or root in output.parents:
        raise ValueError('runtime output must be new and outside the restored bundle')
    descriptor = json.loads((Path(__file__).resolve().parents[1] / 'docs/mpv-decoder-raster-handoff.json').read_text())
    handoff.verify_restored(root, descriptor)
    binaries = root / 'native-runtime/arm64'
    basic = [('enabled', 'numbered-grid.mkv', None), ('queue', 'numbered-grid.mkv', 'queue'),
             ('default', 'numbered-grid.mkv', 'default'), ('disabled', 'numbered-grid.mkv', 'no'),
             ('anamorphic', 'anamorphic.mkv', 'reject'), ('repeat', 'numbered-grid.mkv', 'repeat'),
             ('duplicate-pts', 'duplicate-pts.mkv', 'duplicate'), ('tracks', 'two-tracks.mkv', 'tracks')]
    commands = [(name, [str(binaries / 'harness'), str(root / 'native-runtime' / fixture)] + ([mode] if mode else []))
                for name, fixture, mode in basic]
    fixtures = json.loads((root / 'fixtures/fixtures.json').read_text())
    for case in fixtures['cases']:
        source = str(root / 'fixtures' / Path(case['input']).name)
        if case['reject']:
            command = [str(binaries / 'harness'), source, 'reject']
        else:
            binary = binaries / ('gpu-reference' if case['hardwareDecoder'] != 'no' else 'reference')
            command = [str(binary), source, *[str(root / 'fixtures' / Path(p).name) for p in case['references']],
                       *[str(case[key]) for key in ('width', 'height', 'codedWidth', 'codedHeight', 'rotation')],
                       str(int(case['mirrored'])), str(case['depth']), case['transfer'], case['primaries'],
                       case['hardwareDecoder'], str(case['tolerance']), str(case['bytesPerPixel']), str(case['seekPTS'])]
        commands.append((case['name'], command))
    output.mkdir(parents=True)
    results = []
    for name, command in commands:
        with (output / (name + '.jsonl')).open('w') as log, (output / (name + '.stderr')).open('w') as errors:
            result = subprocess.run(command, stdout=log, stderr=errors, timeout=120)
        results.append({'name': name, 'command': command, 'exitCode': result.returncode})
        print(f'{"Passed" if result.returncode == 0 else "FAILED"} arm64/{name}', flush=True)
        (output / 'runtime-verification.json').write_text(json.dumps({'architectures': ['arm64'], 'passed': all(r['exitCode'] == 0 for r in results), 'cases': results}, indent=2) + '\n')
    if any(result['exitCode'] != 0 for result in results):
        raise ValueError('retained native runtime case failed; inspect output logs')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    validate(args.candidate.resolve(), args.output.resolve())
