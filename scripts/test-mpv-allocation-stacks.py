#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Isolated contract tests; never attach to a real process."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect-mpv-allocation-stacks.py'))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.diagnostics = self.root / 'diagnostics'
        self.diagnostics.mkdir()
        self.output = self.root / 'output'
        self.request = dict(schemaVersion=1, pid=123, checkpoint='final-delayed', snapshotFile='final-delayed.json')
        self.snapshot = dict(schemaVersion=2, pid=123, checkpoint='final-delayed', objects=[
            dict(id=1, address='0x1234', alive=True, label='window', origin='cycle=1,pair=A'),
            dict(id=2, address='0x5678', alive=False)])
        self.run = Mock(side_effect=[
            subprocess.CompletedProcess([], 0, '/path/Aagedal Media Player\n', ''),
            subprocess.CompletedProcess([], 0, 'ALLOC 0x1234 size=8\n frame\n', 'tool notice\n')])

    def write(self):
        collector.atomic_json(self.diagnostics / collector.REQUEST, self.request)
        collector.atomic_json(self.diagnostics / 'final-delayed.json', self.snapshot)

    def collect(self):
        self.write()
        return collector.collect(self.diagnostics, self.output, run=self.run)

    def completion(self):
        return json.loads((self.diagnostics / collector.COMPLETE).read_text())

    def test_success_has_exact_inputs_and_raw_hashes(self):
        result = self.collect()
        self.assertTrue(result['success'])
        self.assertTrue(result['allocationEvidenceCollected'])
        self.assertEqual(result['survivorCount'], 1)
        self.assertEqual(result['requestSHA256'], hashlib.sha256((self.diagnostics / collector.REQUEST).read_bytes()).hexdigest())
        self.assertEqual(result['snapshotSHA256'], hashlib.sha256((self.diagnostics / 'final-delayed.json').read_bytes()).hexdigest())
        report = result['reports'][0]
        for kind in ('stdout', 'stderr'):
            self.assertEqual(report[kind + 'SHA256'], hashlib.sha256((self.output / report[kind + 'File']).read_bytes()).hexdigest())
        self.assertEqual(self.run.call_args_list[1].args[0], ['/usr/bin/malloc_history', '123', '-fullStacks', '0x1234'])
        self.assertEqual(self.completion()['pid'], 123)
        self.assertTrue(self.completion()['success'])
        self.assertEqual(json.loads((self.output / 'receipt.json').read_text()), result)

    def test_no_allocation_records_fails_despite_zero_status(self):
        self.run.side_effect = [subprocess.CompletedProcess([], 0, 'Aagedal Media Player', ''),
                                subprocess.CompletedProcess([], 0, 'No stack history available', '')]
        result = self.collect()
        self.assertFalse(result['success'])
        self.assertFalse(result['reports'][0]['hasAllocationRecord'])
        self.assertFalse(self.completion()['success'])

    def test_allocation_record_must_match_exact_address_or_containing_range(self):
        for index, (record, expected) in enumerate([
                ('ALLOC 0x9876 size=8', False),
                ('ALLOC 0x1200-0x12ff [size=256]:', True),
                ('ALLOC 0x1200-0x1233 [size=52]:', False),
                ('ALLOC 0x1234-0x1234 [size=1]:', True)]):
            with self.subTest(record=record):
                self.output = self.root / f'range-{index}'
                self.run.side_effect = [subprocess.CompletedProcess([], 0, 'Aagedal Media Player', ''),
                                        subprocess.CompletedProcess([], 0, record, '')]
                self.assertEqual(self.collect()['success'], expected)

    def test_process_check_timeout_is_retained_and_never_attaches(self):
        self.run.side_effect = [subprocess.TimeoutExpired('ps', 5, output=b'partial process', stderr=b'partial error')]
        result = self.collect()
        self.assertFalse(result['success'])
        self.assertEqual(result['processChecks'][0]['stdout'], 'partial process')
        self.assertEqual(result['processChecks'][0]['stderr'], 'partial error')
        self.assertTrue(result['processChecks'][0]['timedOut'])
        self.assertEqual(self.run.call_count, 1)

    def test_nonzero_tool_exit_preserves_reports_and_fails(self):
        self.run.side_effect = [subprocess.CompletedProcess([], 0, 'Aagedal Media Player', ''),
                                subprocess.CompletedProcess([], 1, 'ALLOC 0x1234', 'permission denied')]
        result = self.collect()
        self.assertFalse(result['success'])
        self.assertEqual((self.output / result['reports'][0]['stderrFile']).read_text(), 'permission denied')

    def test_target_mismatch_never_attaches(self):
        self.run.side_effect = [subprocess.CompletedProcess([], 0, '/usr/bin/unrelated', '')]
        self.assertFalse(self.collect()['success'])
        self.assertEqual(self.run.call_count, 1)
        self.assertFalse(self.completion()['success'])
        self.assertEqual(json.loads((self.output / 'receipt.json').read_text())['processChecks'][0]['stdout'], '/usr/bin/unrelated')

    def test_tool_timeout_preserves_partial_bytes_and_completes(self):
        self.run.side_effect = [subprocess.CompletedProcess([], 0, 'Aagedal Media Player', ''),
                                subprocess.TimeoutExpired('malloc_history', 15, output=b'partial', stderr=b'timeout')]
        result = self.collect()
        self.assertFalse(result['success'])
        self.assertTrue(result['reports'][0]['timedOut'])
        self.assertEqual((self.output / 'identity-1.stdout.txt').read_bytes(), b'partial')
        self.assertFalse(self.completion()['success'])

    def test_invalid_snapshot_identity_and_pid_fail_before_commands(self):
        for mutation in ('pid', 'duplicate', 'address', 'alive'):
            with self.subTest(mutation=mutation):
                self.output = self.root / mutation
                original = json.loads(json.dumps(self.snapshot))
                if mutation == 'pid': self.snapshot['pid'] = 999
                elif mutation == 'duplicate': self.snapshot['objects'].append(self.snapshot['objects'][0].copy())
                elif mutation == 'address': self.snapshot['objects'][0]['address'] = '0x0'
                else: self.snapshot['objects'][0]['alive'] = 1
                self.assertFalse(self.collect()['success'])
                self.assertFalse(self.completion()['success'])
                self.snapshot = original
        self.run.assert_not_called()

    def test_snapshot_path_cannot_escape_diagnostics(self):
        self.request['snapshotFile'] = '../secret.json'
        self.assertFalse(self.collect()['success'])
        self.run.assert_not_called()
        self.assertFalse(self.completion()['success'])

    def test_survivor_limit_is_bounded(self):
        self.snapshot['objects'] = [dict(id=i, address=hex(i), alive=True) for i in range(1, 34)]
        self.assertFalse(self.collect()['success'])
        self.run.assert_not_called()

    def test_empty_survivors_complete_without_allocation_claim(self):
        self.snapshot['objects'][0]['alive'] = False
        result = self.collect()
        self.assertTrue(result['success'])
        self.assertFalse(result['allocationEvidenceCollected'])
        self.assertEqual(result['reports'], [])
        self.run.assert_not_called()
        self.assertTrue(self.completion()['success'])

    def test_existing_output_is_preserved_and_waiter_released(self):
        self.output.mkdir()
        receipt = self.output / 'receipt.json'
        receipt.write_text('original evidence')
        self.assertFalse(self.collect()['success'])
        self.assertEqual(receipt.read_text(), 'original evidence')
        self.assertFalse(self.completion()['success'])

    def test_watch_timeout_never_attaches_or_creates_completion(self):
        with self.assertRaises(TimeoutError):
            collector.watch(self.diagnostics, self.output, wait_seconds=0, run=self.run)
        self.run.assert_not_called()
        self.assertFalse((self.diagnostics / collector.COMPLETE).exists())

    def test_watch_consumes_existing_request_once(self):
        self.write()
        self.assertTrue(collector.watch(self.diagnostics, self.output, wait_seconds=1, run=self.run)['success'])
        self.assertEqual(self.run.call_count, 2)


if __name__ == '__main__':
    unittest.main()
