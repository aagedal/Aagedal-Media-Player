#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Apply and syntax-check the restricted decoder-raster patch without shipping it."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import tempfile

UPSTREAM = '41f6a645068483470267271e1d09966ca3b9f413'
UNITS = {'f_decoder_wrapper.c', 'screenshot.c', 'command.c'}


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='retained clean mpv 0.41.0 source tree')
    parser.add_argument('scratch', type=Path, help='parent of architecture build directories')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    patch = Path(__file__).resolve().parents[1] / 'docs/dependency-patches/mpv-0.41.0-decoder-raster-candidate.patch'
    run(['git', '-C', str(source), 'merge-base', '--is-ancestor', UPSTREAM, 'HEAD'])
    if run(['git', '-C', str(source), 'status', '--porcelain'], capture_output=True).stdout:
        raise ValueError('source tree must be clean')
    revision = run(['git', '-C', str(source), 'rev-parse', 'HEAD'], capture_output=True).stdout.strip()
    checked = []
    compile_identities = {}
    with tempfile.TemporaryDirectory(prefix='aagedal-decoder-raster-') as temporary:
        candidate = Path(temporary) / 'mpv'
        run(['git', 'clone', '--quiet', '--no-hardlinks', '--no-checkout', str(source), str(candidate)])
        run(['git', '-C', str(candidate), 'checkout', '--quiet', '--detach', revision])
        run(['git', '-C', str(candidate), 'apply', '--check', str(patch)])
        run(['git', '-C', str(candidate), 'apply', str(patch)])
        for arch in ('arm64', 'x86_64'):
            database = args.scratch / arch / 'compile_commands.json'
            compile_identities[arch] = hashlib.sha256(database.read_bytes()).hexdigest()
            rows = json.loads(database.read_text())
            found = set()
            for row in rows:
                unit = Path(row['file']).name
                if unit not in UNITS:
                    continue
                found.add(unit)
                command = shlex.split(row['command'])
                rewritten = []
                index = 0
                while index < len(command):
                    argument = command[index]
                    if argument in ('-o', '-MF', '-MQ'):
                        index += 2
                        continue
                    if argument in ('-MD', '-c'):
                        index += 1
                        continue
                    if 'libmpv-v0.41.0' in argument:
                        prefix = '-I' if argument.startswith('-I') else ''
                        suffix = argument.split('libmpv-v0.41.0', 1)[1].lstrip('/')
                        argument = prefix + str(candidate / suffix)
                    rewritten.append(argument)
                    index += 1
                run(rewritten + ['-fsyntax-only'], cwd=row['directory'])
                checked.append({'architecture': arch, 'unit': unit, 'result': 'syntax-check-passed',
                    'retainedCompileCommand': row['command'],
                    'candidateSourceSHA256': hashlib.sha256((candidate / row['file'].split('libmpv-v0.41.0/', 1)[1]).read_bytes()).hexdigest()})
            if found != UNITS:
                raise ValueError(f'{arch} missing compile commands: {UNITS - found}')
    args.report.write_text(json.dumps({'upstreamRevision': UPSTREAM, 'retainedRevision': revision,
        'patchSHA256': hashlib.sha256(patch.read_bytes()).hexdigest(),
        'compileCommandsSHA256': compile_identities, 'patchApply': 'passed', 'checks': checked,
        'scope': 'C syntax checks only; no linking, runtime, pixel, ownership, or presentation proof'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
