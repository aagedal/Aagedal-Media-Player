#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Link native clients from a verified local rebuild and check numbered pixels.

The x86_64 client runs through Rosetta on Apple Silicon; this does not establish
Intel hardware acceptance. Neither this script nor its harness publishes assets.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess

spec = importlib.util.spec_from_file_location('builder', Path(__file__).with_name('build-mpv-coreaudio-clean-candidate.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def fixtures(output):
    raw = output / 'numbered-grid.rgb'
    raw.write_bytes(bytes(value for frame in range(10) for y in range(16) for x in range(16)
                          for value in ((x * 13 + frame * 17) % 256, y * 13, (x + y) * 7)))
    base = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y']
    grid = output / 'numbered-grid.mkv'
    run(base + ['-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '16x16', '-framerate', '5',
                '-i', str(raw), '-c:v', 'ffv1', '-pix_fmt', 'bgr0', str(grid)])
    square = output / 'square-rgb.mp4'
    rotated = output / 'square-rotated.mp4'
    anamorphic = output / 'anamorphic.mkv'
    duplicate = output / 'duplicate-pts.mkv'
    secondary_raw = output / 'secondary-grid.rgb'
    secondary_raw.write_bytes(bytes(value for frame in range(10) for y in range(16) for x in range(16)
                                    for value in ((x * 13 + frame * 17 + 85) % 256, y * 13, (x + y) * 7)))
    tracks = output / 'two-tracks.mkv'
    run(base + ['-i', str(grid), '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '16x16',
                '-framerate', '5', '-i', str(secondary_raw), '-map', '0:v', '-map', '1:v',
                '-c:v', 'ffv1', '-pix_fmt', 'bgr0', str(tracks)])
    run(base + ['-i', str(grid), '-c:v', 'libx264rgb', '-crf', '0', str(square)])
    run(base + ['-display_rotation', '90', '-i', str(square), '-c', 'copy', str(rotated)])
    run(base + ['-i', str(grid), '-vf', 'setsar=2/1', '-c:v', 'ffv1', str(anamorphic)])
    run(base + ['-i', str(grid), '-vf', r'setpts=if(eq(N\,1)\,0\,N/(5*TB))',
                '-fps_mode', 'passthrough', '-c:v', 'ffv1', str(duplicate)])
    times = json.loads(run(['ffprobe', '-v', 'error', '-show_entries', 'frame=pts_time',
                            '-of', 'json', str(duplicate)], capture_output=True).stdout)
    pts = [float(frame['pts_time']) for frame in times['frames']]
    if len(pts) != 10 or pts[:2] != [0, 0] or pts[-1] != 1.8:
        raise ValueError('fixture does not establish duplicate PTS followed by unique frames')
    rotation = json.loads(run(['ffprobe', '-v', 'error', '-show_entries', 'stream_side_data=rotation',
                               '-of', 'json', str(rotated)], capture_output=True).stdout)
    sar = json.loads(run(['ffprobe', '-v', 'error', '-show_entries', 'stream=sample_aspect_ratio',
                          '-of', 'json', str(anamorphic)], capture_output=True).stdout)
    if rotation['streams'][0]['side_data_list'][0]['rotation'] != 90 or sar['streams'][0]['sample_aspect_ratio'] != '2:1':
        raise ValueError('fixture metadata does not establish intended rejection case')
    return grid, rotated, anamorphic, duplicate, tracks


def validate(build, output, extended_fixtures=None):
    build, output = build.resolve(), output.resolve()
    if output.exists():
        raise ValueError('runtime output must be new')
    receipt = json.loads((build / 'portable-build.json').read_text())
    if not receipt.get('buildSucceeded') or not receipt.get('decoderRasterCandidate'):
        raise ValueError('requires a successful decoder-raster candidate rebuild')
    verified = builder.verify_build(build, receipt)
    output.mkdir(parents=True)
    report = {'passed': False, 'buildReceiptSHA256': builder.sha(build / 'portable-build.json'),
              'scope': 'Native decoder-grid validation for the declared build architectures; hardware cases require active VideoToolbox.',
              'architectures': {}, 'verification': verified}
    report_path = output / 'runtime-verification.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    grid, rotated, anamorphic, duplicate, tracks = fixtures(output)
    report['fixtures'] = {p.name: builder.sha(p) for p in (grid, rotated, anamorphic, duplicate, tracks)}
    source = Path(__file__).with_name('mpv-decoder-raster-harness.c')
    report['harnessSourceSHA256'] = builder.sha(source)
    extended = []
    if extended_fixtures:
        metadata = json.loads((extended_fixtures / 'fixtures.json').read_text())
        for name, identity in metadata['files'].items():
            path = extended_fixtures / name
            if builder.sha(path) != identity['sha256'] or path.stat().st_size != identity['sizeBytes']:
                raise ValueError('extended fixture identity mismatch: ' + name)
        extended = metadata['cases']
        report['extendedFixturesSHA256'] = builder.sha(extended_fixtures / 'fixtures.json')
        report['extendedFixtureCases'] = extended
    reference_source = Path(__file__).with_name('mpv-decoder-raster-reference-harness.c')
    report['referenceHarnessSourceSHA256'] = builder.sha(reference_source)
    scratch = build / 'MPVKit/dist/libmpv/macos/scratch'
    commands = run(['ninja', '-C', str(scratch / 'arm64'), '-t', 'commands', 'mpv'], capture_output=True).stdout.splitlines()
    template = shlex.split(commands[-1])
    if template.count('mpv.p/osdep_main-fn-mac.c.o') != 1 or template.count('-o') != 1:
        raise ValueError('unexpected retained native executable link command')
    for arch in receipt.get('architectures', ['arm64', 'x86_64']):
        directory = output / arch
        directory.mkdir()
        obj, binary = directory / 'harness.o', directory / 'harness'
        compile_command = ['clang', '-arch', arch, '-mmacosx-version-min=12.0',
                           '-I' + str(build / 'MPVKit/dist/libmpv-v0.41.0/include'), '-c', str(source), '-o', str(obj)]
        run(compile_command)
        link = [arg.replace('/arm64/', '/' + arch + '/').replace('arm64-apple-', arch + '-apple-')
                if arg != 'arm64' else arch for arg in template]
        link[link.index('-o') + 1] = str(binary)
        link[link.index('mpv.p/osdep_main-fn-mac.c.o')] = str(obj)
        run(link, cwd=scratch / arch)
        cases = [('enabled', grid, None), ('queue', grid, 'queue'), ('default', grid, 'default'),
                 ('disabled', grid, 'no'), ('anamorphic', anamorphic, 'reject'),
                 ('repeat', grid, 'repeat'), ('duplicate-pts', duplicate, 'duplicate'), ('tracks', tracks, 'tracks')]
        results = []
        report['architectures'][arch] = {'compileCommand': compile_command, 'linkCommand': link,
                                        'binarySHA256': builder.sha(binary), 'cases': results}
        for name, fixture, mode in cases:
            command = [str(binary), str(fixture)] + ([mode] if mode else [])
            with (directory / (name + '.jsonl')).open('w') as log, (directory / (name + '.stderr')).open('w') as errors:
                result = subprocess.run(command, stdout=log, stderr=errors, timeout=120)
            results.append({'name': name, 'exitCode': result.returncode})
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            if result.returncode:
                raise ValueError(f'{arch}/{name} failed: {result.returncode}; see {directory}')
            print(f'Passed {arch}/{name}', flush=True)
        reference_obj, reference_binary = directory / 'reference.o', directory / 'reference'
        reference_compile = ['clang', '-arch', arch, '-mmacosx-version-min=12.0',
                             '-I' + str(build / 'MPVKit/dist/libmpv-v0.41.0/include'), '-c', str(reference_source), '-o', str(reference_obj)]
        run(reference_compile)
        reference_link = [str(reference_binary) if a == str(binary) else str(reference_obj) if a == str(obj) else a for a in link]
        run(reference_link, cwd=scratch / arch)
        report['architectures'][arch]['referenceHarness'] = {'compileCommand':reference_compile, 'linkCommand':reference_link,
                                                            'binarySHA256':builder.sha(reference_binary)}
        gpu_binary = None
        if any(case['hardwareDecoder'] != 'no' for case in extended):
            gpu_obj, gpu_binary = directory / 'gpu-reference.o', directory / 'gpu-reference'
            gpu_compile = ['clang', '-x', 'objective-c', '-fobjc-arc', '-DAAGEDAL_GPU_HARNESS=1',
                           '-arch', arch, '-mmacosx-version-min=12.0',
                           '-I' + str(build / 'MPVKit/dist/libmpv-v0.41.0/include'), '-c', str(reference_source), '-o', str(gpu_obj)]
            run(gpu_compile)
            gpu_link = [str(gpu_binary) if a == str(binary) else str(gpu_obj) if a == str(obj) else a for a in link]
            run(gpu_link, cwd=scratch / arch)
            report['architectures'][arch]['gpuHarness'] = {'compileCommand':gpu_compile, 'linkCommand':gpu_link,
                                                          'binarySHA256':builder.sha(gpu_binary)}
        for case in extended:
            name = case['name']
            if case['reject']:
                command = [str(binary), case['input'], 'reject']
            else:
                harness = gpu_binary if case['hardwareDecoder'] != 'no' else reference_binary
                command = [str(harness), case['input'], *case['references'],
                    *[str(case[key]) for key in ('width','height','codedWidth','codedHeight','rotation')],
                    str(int(case['mirrored'])), str(case['depth']), case['transfer'], case['primaries'],
                    case['hardwareDecoder'], str(case['tolerance']), str(case['bytesPerPixel']), str(case['seekPTS'])]
            with (directory / (name + '.jsonl')).open('w') as log, (directory / (name + '.stderr')).open('w') as errors:
                result = subprocess.run(command, stdout=log, stderr=errors, timeout=120)
            results.append({'name':name, 'exitCode':result.returncode, 'command':command})
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            print(f'{"Passed" if result.returncode == 0 else "FAILED"} {arch}/{name}: {result.returncode}', flush=True)
    report['passed'] = all(case['exitCode'] == 0 for architecture in report['architectures'].values() for case in architecture['cases'])
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    if not report['passed']:
        raise ValueError('extended raster cases failed; see ' + str(report_path))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--extended-fixtures', type=Path)
    args = parser.parse_args()
    validate(args.build, args.output, args.extended_fixtures.resolve() if args.extended_fixtures else None)
