#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create independent decoded references for UHD, hardware, and HDR rasters."""
import argparse
from array import array
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys


def run(command):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def probe(path):
    return json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(path)]))['streams'][0]


def rgb(path, width, height):
    with path.open('wb') as file:
        for frame in range(4):
            rows = [bytes(v for x in range(width) for v in (((x % 16) * 13 + frame * 17) % 256,
                    y * 13, ((x % 16) + y) * 7)) for y in range(16)]
            for y in range(height): file.write(rows[y % 16])


def yuv10(path, width, height):
    with path.open('wb') as file:
        for frame in range(4):
            row = array('H', (64 + ((x * 877 // width + frame * 7) % 877) for x in range(width)))
            neutral = array('H', [512]) * (width // 2)
            if sys.byteorder != 'little': row.byteswap(); neutral.byteswap()
            file.write(row.tobytes() * height)
            file.write(neutral.tobytes() * (height // 2) * 2)


def replace_matrix(path, matrix):
    data = bytearray(path.read_bytes())
    def boxes(start, end):
        offset = start
        while offset + 8 <= end:
            size, kind = struct.unpack_from('>I4s', data, offset)
            if size < 8 or offset + size > end: raise ValueError('unsupported MP4 box layout')
            payload = offset + 8
            if kind in (b'moov', b'trak'): boxes(payload, offset + size)
            if kind == b'tkhd':
                position = payload + (52 if data[payload] == 1 else 40)
                struct.pack_into('>9i', data, position, *matrix)
                return True
            offset += size
        return False
    boxes(0, len(data))
    path.write_bytes(data)
    actual = probe(path).get('side_data_list', [])
    if not any('displaymatrix' in side for side in actual): raise ValueError('patched matrix was not independently detected')


def generate(output):
    if output.exists(): raise ValueError('fixture output must be new')
    output.mkdir(parents=True)
    base = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y']
    cases = []
    def encode(raw, path, width, height, pixel_format, codec, color=None):
        command = base + ['-f', 'rawvideo', '-pixel_format', pixel_format, '-video_size', f'{width}x{height}',
                          '-framerate', '2', '-i', str(raw), '-an']
        if color:
            command += ['-vf', f'setparams=range=limited:color_primaries={color[0]}:color_trc={color[1]}:colorspace={color[2]}']
        if codec == 'ffv1': command += ['-c:v', codec, '-level', '3', '-pix_fmt', 'bgr0' if pixel_format == 'rgb24' else pixel_format]
        elif codec == 'rgb': command += ['-c:v', 'libx264rgb', '-crf', '0', '-preset', 'ultrafast']
        elif codec == 'h264': command += ['-c:v', 'libx264', '-crf', '16', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p']
        else: command += ['-c:v', 'libx265', '-preset', 'ultrafast', '-crf', '16', '-pix_fmt', 'yuv420p10le',
                         '-x265-params', 'pools=1:frame-threads=1:log-level=error:keyint=4:bframes=0', '-tag:v', 'hvc1']
        if color: command += ['-color_primaries', color[0], '-color_trc', color[1], '-colorspace', color[2], '-color_range', 'tv']
        run(command + [str(path)])
    def add(name, path, depth=8, transfer='srgb', primaries='bt709', hardware='no', tolerance=0, reject=False):
        stream = probe(path)
        w, h = stream['width'], stream['height']
        rotation, mirrored = 0, False
        for side in stream.get('side_data_list', []):
            if 'displaymatrix' in side:
                matrix = [int(value) for line in side['displaymatrix'].strip().splitlines()
                          for value in line.split(':', 1)[1].split()]
                mirrored = matrix[0] * matrix[4] - matrix[1] * matrix[3] < 0
                rotation = int(-side['rotation']) % 360
        swapped = rotation in (90, 270)
        high = depth > 8 or transfer in ('pq', 'hlg')
        case = {'name': name, 'input': str(path), 'codedWidth': w, 'codedHeight': h,
                'width': h if swapped else w, 'height': w if swapped else h, 'rotation': rotation,
                'mirrored': mirrored, 'depth': depth, 'transfer': transfer, 'primaries': primaries,
                'hardwareDecoder': hardware, 'tolerance': tolerance, 'bytesPerPixel': 8 if high else 4,
                'seekPTS': 1, 'reject': reject, 'sourceMetadata': stream}
        if not reject:
            references = []
            for pts in (0, 1):
                reference = output / f'{name}-{pts}.raw'
                run(base + ['-i', str(path), '-ss', str(pts), '-frames:v', '1', '-sws_flags', 'bilinear',
                            '-pix_fmt', 'rgba64le' if high else 'bgra', '-f', 'rawvideo', str(reference)])
                expected_size = case['width'] * case['height'] * case['bytesPerPixel']
                if reference.stat().st_size != expected_size: raise ValueError('reference geometry mismatch: ' + name)
                references.append(str(reference))
            case['references'] = references
        cases.append(case)
    small_raw = output / 'small.rgb'; rgb(small_raw, 24, 16)
    small = output / 'small.mp4'; encode(small_raw, small, 24, 16, 'rgb24', 'rgb')
    for angle in (0, 90, 180, 270):
        for flip in (False, True):
            path = output / f'orientation-{angle}-{int(flip)}.mp4'
            run(base + ['-display_rotation', str(angle)] + (['-display_vflip'] if flip else []) +
                ['-i', str(small), '-c', 'copy', str(path)])
            add(f'orientation-{angle}-{int(flip)}', path)
    for name, matrix in [('scale', [131072,0,0,0,65536,0,0,0,1<<30]),
                         ('shear', [65536,0,0,32768,65536,0,0,0,1<<30]),
                         ('fractional-translation', [65536,0,0,0,65536,0,32768,0,1<<30])]:
        path = output / (name + '.mp4'); path.write_bytes(small.read_bytes()); replace_matrix(path, matrix)
        add(name, path, reject=True)
    for width in (3840, 4096):
        raw = output / f'uhd-{width}.rgb'; rgb(raw, width, 2160)
        path = output / f'uhd-{width}.mkv'; encode(raw, path, width, 2160, 'rgb24', 'ffv1')
        add(f'uhd-{width}', path)
        if width == 3840:
            hardware = output / 'uhd-h264.mp4'; encode(raw, hardware, width, 2160, 'rgb24', 'h264', ('bt709','bt709','bt709'))
            add('uhd-h264-software', hardware, transfer='bt1886', tolerance=3)
            add('uhd-h264-hardware', hardware, transfer='bt1886', hardware='videotoolbox', tolerance=3)
    for width, height in ((1024,16), (3840,2160)):
        raw = output / f'hdr-{width}.yuv'; yuv10(raw, width, height)
        for transfer, tag in [('pq','smpte2084'), ('hlg','arib-std-b67')]:
            path = output / f'{transfer}-{width}.mkv'; encode(raw, path, width, height, 'yuv420p10le', 'ffv1', ('bt2020',tag,'bt2020nc'))
            stream = probe(path)
            if stream['color_transfer'] != tag or stream['color_primaries'] != 'bt2020' or stream['pix_fmt'] != 'yuv420p10le':
                raise ValueError('HDR fixture metadata mismatch')
            add(f'{transfer}-{width}', path, depth=10, transfer=transfer, primaries='bt2020', tolerance=256)
            if width == 3840:
                hardware = output / f'{transfer}-hevc.mp4'; encode(raw, hardware, width, height, 'yuv420p10le', 'hevc', ('bt2020',tag,'bt2020nc'))
                add(f'{transfer}-hevc-software', hardware, depth=10, transfer=transfer, primaries='bt2020', tolerance=256)
                add(f'{transfer}-hevc-hardware', hardware, depth=10, transfer=transfer, primaries='bt2020', hardware='videotoolbox', tolerance=256)
    identities = {p.name: {'sha256': hashlib.file_digest(p.open('rb'), 'sha256').hexdigest(), 'sizeBytes': p.stat().st_size}
                  for p in output.iterdir() if p.is_file()}
    (output / 'fixtures.json').write_text(json.dumps({'schemaVersion':1, 'cases':cases, 'files':identities}, indent=2) + '\n')
    print(f'Generated {len(cases)} independent raster cases: {output}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    generate(parser.parse_args().output.resolve())
