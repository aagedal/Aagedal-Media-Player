#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
"""Owned 128 MiB APFS fixture for native save-error/retry acceptance.

Run setup, then pass its printed root to fill/release/verify/cleanup.
Open mount/media/source-a.mov and compare source-b.mov before fill. Edit a
finding after fill; pending-edit.txt contains a large edit that requires new
allocation (the UI trims surrounding whitespace before saving). Verify before release to prove preservation, release, retry in the
app, then verify --recovered. For deletion acceptance, run checkpoint, fill --recovered,
attempt deletion, verify --recovered, release, retry in the app, then verify
--deleted. Close the media before cleanup. Cleanup detaches
and removes only the image; host-side baseline, manifest and logs remain.
This checks bytes, not UI behavior: record the visible error and retry manually.
"""
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import uuid

LIMIT = 136 * 1024 * 1024
TOKEN = '.aagedal-disk-full-token'


def run(*args):
    return subprocess.check_output(args, timeout=120)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def root_check(root):
    assert str(root) == os.path.realpath(root), 'Root must be canonical'
    assert root.parent == Path('/private/tmp') and root.name.startswith('aagedal-native-disk-full.'), 'Unowned root'
    info = root.stat()
    assert info.st_uid == os.getuid() and stat.S_ISDIR(info.st_mode), 'Wrong root owner/type'
    assert not info.st_mode & 0o022, 'Root must not be writable by other users'


def attest(root, state, require_token=True):
    root_check(root)
    mount = root / 'mount'
    assert str(mount) == os.path.realpath(mount), 'Aliased mount'
    assert str(uuid.UUID(state['token'])) == state['token'], 'Invalid token'
    image = root / 'fixture.dmg'
    assert image.is_file() and not image.is_symlink() and image.stat().st_size <= LIMIT, 'Invalid image'
    images = plistlib.loads(run('/usr/bin/hdiutil', 'info', '-plist'))['images']
    matches = [entry for entry in images if os.path.realpath(entry['image-path']) == str(image)]
    assert len(matches) == 1, 'Image is not uniquely attached'
    entities = matches[0]['system-entities']
    mounted = [e for e in entities if e.get('mount-point') == str(mount)]
    assert len(mounted) == 1, 'Mount does not belong to owned image'
    volume = plistlib.loads(run('/usr/sbin/diskutil', 'info', '-plist', str(mount)))
    assert volume['MountPoint'] == str(mount) and volume['FilesystemType'] == 'apfs', 'Wrong filesystem'
    device = volume['DeviceNode']
    assert device.startswith('/dev/disk') and device == mounted[0]['dev-entry'], 'Device mismatch'
    if 'device' in state:
        assert device == state['device'], 'Device changed'
    if 'volume_uuid' in state:
        assert volume['VolumeUUID'] == state['volume_uuid'], 'Volume identity changed'
    if 'stat_device' in state:
        assert mount.stat().st_dev == state['stat_device'], 'Filesystem device changed'
    size = volume['TotalSize']
    fs = os.statvfs(mount)
    assert 8 * 1024 * 1024 <= size <= LIMIT and 8 * 1024 * 1024 <= fs.f_blocks * fs.f_frsize <= LIMIT, 'Unbounded filesystem'
    assert mount.stat().st_dev != root.stat().st_dev, 'Mount is host filesystem'
    if require_token:
        token_file = mount / TOKEN
        assert not token_file.is_symlink() and token_file.read_text() == state['token'], 'Ownership token mismatch'
    return device


def open_filler(root, state, flags):
    attest(root, state)
    mount = root / 'mount'
    expected_device = state['stat_device']
    assert expected_device != root.stat().st_dev
    fd = os.open(mount / 'filler', flags | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        fs = os.fstatvfs(fd)
        assert info.st_dev == expected_device and info.st_dev != root.stat().st_dev
        assert info.st_uid == os.getuid() and stat.S_ISREG(info.st_mode) and info.st_nlink == 1
        assert 8 * 1024 * 1024 <= fs.f_blocks * fs.f_frsize <= LIMIT
        return fd
    except BaseException:
        os.close(fd)
        raise


def log(root, message):
    with (root / 'phases.log').open('a') as handle:
        handle.write(message + '\n')
    print(message)


def validate_document(current, original, pending_text, deleted=False):
    document, baseline = json.loads(current), json.loads(original)
    if deleted:
        assert document['notes'] == [], 'Deletion has not persisted'
        baseline['notes'] = []
    else:
        assert len(document['notes']) == len(baseline['notes']) == 1, 'Unexpected finding count'
        assert document['notes'][0]['text'] == pending_text.strip(), 'Expected pending edit was not persisted'
        for value in [document, baseline]:
            value['notes'][0]['id'] = str(uuid.UUID(value['notes'][0]['id']))
            value['notes'][0].pop('text')
            value['notes'][0].pop('updatedAt')
    assert document == baseline, 'Retry changed fields beyond the intended edit/deletion'


def retain_bytes(path, data):
    # Evidence is immutable once created; reruns must match the same bytes.
    if path.exists() or path.is_symlink():
        assert not path.is_symlink() and path.read_bytes() == data, 'Retained evidence changed'
    else:
        with path.open('xb') as handle:
            handle.write(data)


def verify(root, state, recovered=False, deleted=False):
    assert not (recovered and deleted), 'Choose one expected state'
    attest(root, state)
    media = root / 'mount/media'
    assert str(media) == os.path.realpath(media) and media.stat().st_dev == state['stat_device'], 'Aliased media directory'
    assert {path.name for path in media.iterdir()} == set(state['media_sha256']) | {state['sidecar']}, 'Unexpected files in review directory'
    for name, expected in state['media_sha256'].items():
        assert not (media / name).is_symlink() and digest(media / name) == expected, 'Source bytes changed'
    sidecar = media / state['sidecar']
    assert not sidecar.is_symlink(), 'Aliased sidecar'
    data = sidecar.read_bytes()
    if recovered or deleted:
        assert hashlib.sha256(data).hexdigest() != state['sidecar_sha256'], 'Retry has not persisted a change'
        original = root / 'original-sidecar.json'
        assert not original.is_symlink() and digest(original) == state['sidecar_sha256'], 'Baseline changed'
        validate_document(data, original.read_bytes(), (root / 'pending-edit.txt').read_text(), deleted)
        if recovered and 'recovered_sha256' in state:
            checkpoint = root / 'recovered-sidecar.json'
            assert not checkpoint.is_symlink() and digest(checkpoint) == state['recovered_sha256'], 'Recovered checkpoint changed'
            assert hashlib.sha256(data).hexdigest() == state['recovered_sha256'], 'Recovered sidecar bytes changed after checkpoint'
        if deleted:
            assert 'recovered_sha256' in state, 'Deletion requires a recovered checkpoint'
            checkpoint = root / 'recovered-sidecar.json'
            assert not checkpoint.is_symlink() and digest(checkpoint) == state['recovered_sha256'], 'Recovered checkpoint changed'
            retain_bytes(root / 'deleted-sidecar.json', data)
    else:
        assert hashlib.sha256(data).hexdigest() == state['sidecar_sha256'], 'Original sidecar changed'
    phase = 'persisted deletion.' if deleted else ('exact retry edit.' if recovered else 'original sidecar preservation.')
    log(root, 'Verified source preservation and ' + phase)
    return data


def checkpoint(root, state):
    data = verify(root, state, recovered=True)
    retain_bytes(root / 'recovered-sidecar.json', data)
    state['recovered_sha256'] = hashlib.sha256(data).hexdigest()
    (root / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
    verify(root, state, recovered=True)
    log(root, 'Pinned recovered sidecar bytes for deletion failure/retry acceptance.')


def setup():
    root = Path(tempfile.mkdtemp(prefix='aagedal-native-disk-full.', dir='/private/tmp'))
    print(f'Fixture root: {root}', flush=True)
    root_check(root)
    (root / 'mount').mkdir()
    state = {'token': str(uuid.uuid4())}
    (root / 'state.json').write_text(json.dumps(state))
    try:
        run('/usr/bin/hdiutil', 'create', '-size', '128m', '-fs', 'APFS', '-volname', 'AagedalNativeDiskFull', str(root / 'fixture.dmg'))
        run('/usr/bin/hdiutil', 'attach', '-nobrowse', '-mountpoint', str(root / 'mount'), str(root / 'fixture.dmg'))
        state['device'] = attest(root, state, require_token=False)
        state['stat_device'] = (root / 'mount').stat().st_dev
        state['volume_uuid'] = plistlib.loads(run('/usr/sbin/diskutil', 'info', '-plist', str(root / 'mount')))['VolumeUUID']
        (root / 'mount' / TOKEN).write_text(state['token'])
        attest(root, state)
        media = root / 'mount/media'
        media.mkdir()
        ffmpeg = Path(__file__).resolve().parents[1] / 'Aagedal Media Player/Binaries/ffmpeg'
        run(str(ffmpeg), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=25', '-t', '5', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '28', '-n', str(media / 'source-a.mov'))
        attest(root, state)
        shutil.copyfile(media / 'source-a.mov', media / 'source-b.mov')
        # Foundation resolves /private/tmp as /tmp, unlike POSIX realpath.
        paths = json.loads(run('/usr/bin/swift', '-module-cache-path', str(root / 'swift-cache'), '-e',
            'import Foundation; let paths = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }; print(String(data: try JSONEncoder().encode(paths), encoding: .utf8)!)',
            str(media / 'source-a.mov'), str(media / 'source-b.mov')))
        suffix = 14695981039346656037
        for byte in paths[1].encode():
            suffix = ((suffix ^ byte) * 1099511628211) & ((1 << 64) - 1)
        state['sidecar'] = f'source-a vs source-b-{suffix:x}.aagedal-compare.json'
        note = dict(id=str(uuid.uuid4()).upper(), primaryFrame=25, secondaryFrame=25, primaryTime=1, secondaryTime=1,
                    primaryRateNumerator=25, primaryRateDenominator=1, secondaryRateNumerator=25, secondaryRateDenominator=1,
                    text='Original native disk-full finding', severity='minor', category='picture', status='open',
                    createdAt=1788900000000, updatedAt=1788900000000)
        document = dict(schemaVersion=2, primarySource={'canonicalPath': paths[0]}, secondarySource={'canonicalPath': paths[1]}, notes=[note])
        attest(root, state)
        sidecar = media / state['sidecar']
        sidecar.write_text(json.dumps(document, indent=2) + '\n')
        shutil.copyfile(sidecar, root / 'original-sidecar.json')
        state['sidecar_sha256'] = digest(sidecar)
        state['media_sha256'] = {name: digest(media / name) for name in ['source-a.mov', 'source-b.mov']}
        (root / 'pending-edit.txt').write_text('Recovered native edit ' * 768)
        (root / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
        verify(root, state)
        print(f'Open {media / "source-a.mov"}, then compare source-b.mov.')
    except BaseException:
        try:
            attest(root, state, require_token=False)
            run('/usr/bin/hdiutil', 'detach', str(root / 'mount'))
            print(f'Detached incomplete fixture; evidence retained at {root}')
        except Exception as cleanup_error:
            print(f'Could not attest/detach incomplete fixture at {root}: {cleanup_error}')
        raise



def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['setup', 'fill', 'release', 'verify', 'checkpoint', 'cleanup'])
    parser.add_argument('root', nargs='?', type=Path)
    expected = parser.add_mutually_exclusive_group()
    expected.add_argument('--recovered', action='store_true')
    expected.add_argument('--deleted', action='store_true')
    args = parser.parse_args()
    if args.recovered and args.command not in ('verify', 'fill'):
        parser.error('--recovered is supported only by verify/fill')
    if args.deleted and args.command != 'verify':
        parser.error('--deleted is supported only by verify')
    if args.command == 'setup':
        assert args.root is None and not args.recovered
        setup()
        return
    assert args.root is not None, 'Root required'
    root = args.root
    root_check(root)
    assert not (root / 'state.json').is_symlink(), 'Aliased state'
    state = json.loads((root / 'state.json').read_text())
    attest(root, state)
    filler = root / 'mount/filler'
    if args.command == 'fill':
        if args.recovered:
            assert 'recovered_sha256' in state, 'Run checkpoint before refilling for deletion'
        verify(root, state, recovered=args.recovered)
        fd = open_filler(root, state, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        exhausted = False
        try:
            assert os.fstat(fd).st_dev == (root / 'mount').stat().st_dev
            for _ in range(LIMIT // 4096):
                try:
                    assert os.write(fd, b'a' * 4096) > 0
                except OSError as error:
                    if error.errno != errno.ENOSPC:
                        raise
                    exhausted = True
                    break
        finally:
            os.close(fd)
        assert exhausted, 'Bounded fill did not reach ENOSPC; stop acceptance'
        verify(root, state, recovered=args.recovered)
        log(root, 'Reached real ENOSPC. Attempt ' + ('deletion' if args.recovered else 'the pending edit') + ' in the app; record visible save error.')
    elif args.command == 'release':
        fd = open_filler(root, state, os.O_WRONLY)
        try:
            assert os.fstat(fd).st_dev == (root / 'mount').stat().st_dev
            assert stat.S_ISREG(os.fstat(fd).st_mode) and os.fstat(fd).st_nlink == 1
            os.ftruncate(fd, 0)
            os.fsync(fd)
        finally:
            os.close(fd)
        attest(root, state)
        filler.unlink()
        log(root, 'Released filler. Retry the pending save in the app, then verify --recovered or --deleted for the current cycle.')
    elif args.command == 'verify':
        verify(root, state, args.recovered, args.deleted)
    elif args.command == 'checkpoint':
        checkpoint(root, state)
    else:
        run('/usr/bin/hdiutil', 'detach', str(root / 'mount'))
        root_check(root)
        assert not os.path.ismount(root / 'mount'), 'Mount still attached'
        (root / 'fixture.dmg').unlink()
        log(root, f'Detached and removed image; retained evidence in {root}')


if __name__ == '__main__':
    # Safety checks are deliberately non-optional even if PYTHONOPTIMIZE is set.
    if not __debug__:
        raise SystemExit('Run without Python optimization; safety assertions are required')
    main()
