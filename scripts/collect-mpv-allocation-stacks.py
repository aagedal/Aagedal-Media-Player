#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect opt-in, post-gate malloc histories for weakly observed live objects.

These are allocation histories, not ownership or autorelease-insertion evidence.
The caller keeps the XCTest host alive after its original gate measurements.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time


REQUEST = 'allocation-request.json'
COMPLETE = 'allocation-complete.json'


def atomic_json(path, value):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def collect(diagnostics, output, run=subprocess.run):
    """Consume an existing request, retain raw reports, and always release its waiter.

    Return the receipt; success requires every requested live identity to have a
    successful tool exit and an ALLOC record covering its address. Empty sets
    complete without stacks.
    """
    diagnostics, output = Path(diagnostics), Path(output)
    receipt = {'schemaVersion': 1, 'success': False, 'reports': [],
               'evidenceKind': 'allocation-history-only', 'errors': [], 'processChecks': []}
    created_output = False
    try:
        output.mkdir(parents=True, exist_ok=False)
        created_output = True
        request_bytes = (diagnostics / REQUEST).read_bytes()
        receipt['requestSHA256'] = digest(request_bytes)
        request = json.loads(request_bytes)
        if (not isinstance(request, dict) or type(request.get('schemaVersion')) is not int or request['schemaVersion'] != 1
                or type(request.get('pid')) is not int or request['pid'] <= 0
                or request.get('checkpoint') != 'final-delayed'
                or request.get('snapshotFile') != 'final-delayed.json'):
            raise ValueError('Invalid allocation request')
        pid = request['pid']
        receipt.update(pid=pid, checkpoint='final-delayed')
        snapshot_bytes = (diagnostics / request['snapshotFile']).read_bytes()
        receipt['snapshotSHA256'] = digest(snapshot_bytes)
        snapshot = json.loads(snapshot_bytes)
        if (not isinstance(snapshot, dict) or type(snapshot.get('schemaVersion')) is not int or snapshot['schemaVersion'] != 2
                or type(snapshot.get('pid')) is not int or snapshot['pid'] != pid
                or snapshot.get('checkpoint') != 'final-delayed'
                or not isinstance(snapshot.get('objects'), list)):
            raise ValueError('Invalid allocation snapshot or mismatching process')
        survivors, identities = [], set()
        for row in snapshot['objects']:
            if (not isinstance(row, dict) or type(row.get('id')) is not int or row['id'] <= 0
                    or row['id'] in identities or type(row.get('alive')) is not bool
                    or not isinstance(row.get('address'), str)
                    or not re.fullmatch(r'0x[0-9a-fA-F]+', row['address'])
                    or int(row['address'], 16) == 0):
                raise ValueError('Invalid or duplicate allocation identity')
            identities.add(row['id'])
            if row['alive']:
                survivors.append(row)
        if len(survivors) > 32:
            raise ValueError('At most 32 live identities are supported')
        receipt['survivorCount'] = len(survivors)
        receipt['allocationEvidenceCollected'] = False
        deadline = time.monotonic() + 500
        for row in survivors:
            if time.monotonic() + 20 > deadline:
                raise TimeoutError('Collector total time budget exhausted')
            # Recheck immediately before each access; never inspect an unrelated PID.
            check = {'id': row['id'], 'command': ['/bin/ps', '-p', str(pid), '-o', 'comm=']}
            receipt['processChecks'].append(check)
            try:
                process = run(check['command'], capture_output=True, text=True, timeout=5)
                check.update(stdout=process.stdout, stderr=process.stderr, exitCode=process.returncode, timedOut=False)
            except subprocess.TimeoutExpired as error:
                def decoded(value):
                    return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''
                check.update(stdout=decoded(error.stdout), stderr=decoded(error.stderr), exitCode=None, timedOut=True)
                raise
            except OSError as error:
                check.update(stdout='', stderr=str(error), exitCode=None, timedOut=False)
                raise
            if process.returncode or Path(process.stdout.strip()).name != 'Aagedal Media Player':
                raise ValueError('Target is absent or is not Aagedal Media Player')
            command = ['/usr/bin/malloc_history', str(pid), '-fullStacks', row['address']]
            report = {key: row[key] for key in ('id', 'address')}
            report.update({key: row.get(key) for key in ('label', 'origin')})
            report['command'] = command
            prefix = f"identity-{row['id']}"
            try:
                result = run(command, capture_output=True, text=True, timeout=15)
                stdout, stderr, status = result.stdout, result.stderr, result.returncode
                timed_out = False
            except subprocess.TimeoutExpired as error:
                stdout, stderr, status, timed_out = error.stdout or '', error.stderr or '', None, True
            except OSError as error:
                stdout, stderr, status, timed_out = '', str(error), None, False
            def as_bytes(value):
                return value if isinstance(value, bytes) else value.encode('utf-8')
            stdout, stderr = as_bytes(stdout), as_bytes(stderr)
            for kind, data in (('stdout', stdout), ('stderr', stderr)):
                name = f'{prefix}.{kind}.txt'
                (output / name).write_bytes(data)
                report[kind + 'File'] = name
                report[kind + 'SHA256'] = digest(data)
            # malloc_history emits ALLOC records for allocation histories. A zero
            # exit without a record covering the queried address is insufficient.
            address = int(row['address'], 16)
            allocation_ranges = re.findall(rb'^\s*ALLOC\s+(0x[0-9a-fA-F]+)(?:-(0x[0-9a-fA-F]+))?(?=\s|$)', stdout, re.MULTILINE)
            has_alloc = any(int(start, 16) <= address <= int(end or start, 16)
                            for start, end in allocation_ranges)
            report.update(exitCode=status, timedOut=timed_out, hasAllocationRecord=has_alloc,
                          success=status == 0 and not timed_out and has_alloc)
            receipt['reports'].append(report)
        receipt['success'] = all(report['success'] for report in receipt['reports'])
        receipt['allocationEvidenceCollected'] = bool(survivors) and receipt['success']
    except Exception as error:
        receipt['errors'].append(f'{type(error).__name__}: {error}')
    finally:
        # Receipt failure must also release the host. Do not overwrite any
        # pre-existing output directory's evidence on a failed mkdir.
        try:
            if created_output:
                atomic_json(output / 'receipt.json', receipt)
        except Exception as error:
            receipt['success'] = False
            receipt['errors'].append(f'Receipt write failed: {error}')
        completion = {'schemaVersion': 1, 'success': receipt['success'],
                      'pid': receipt.get('pid'), 'checkpoint': 'final-delayed',
                      'errors': receipt['errors']}
        atomic_json(diagnostics / COMPLETE, completion)
    return receipt


def watch(diagnostics, output, wait_seconds=1800, run=subprocess.run):
    """Wait a bounded time for the atomic request, then collect exactly once."""
    diagnostics = Path(diagnostics)
    deadline = time.monotonic() + wait_seconds
    while not (diagnostics / REQUEST).is_file():
        if time.monotonic() >= deadline:
            raise TimeoutError('Timed out waiting for allocation-request.json')
        time.sleep(min(0.2, max(0, deadline - time.monotonic())))
    return collect(diagnostics, output, run=run)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('diagnostics', type=Path)
    parser.add_argument('output', type=Path, help='new evidence directory')
    parser.add_argument('--wait-seconds', type=float, default=1800)
    args = parser.parse_args()
    if not math.isfinite(args.wait_seconds) or args.wait_seconds <= 0:
        parser.error('--wait-seconds must be finite and positive')
    try:
        receipt = watch(args.diagnostics, args.output, args.wait_seconds)
    except (TimeoutError, OSError) as error:
        parser.exit(1, str(error) + '\n')
    raise SystemExit(0 if receipt['success'] else 1)


if __name__ == '__main__':
    main()
