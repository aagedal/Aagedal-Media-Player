#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
"""No disk images or writes: guard regression tests for the native fixture."""
import importlib.util
import os
import copy
import json
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('fixture', Path(__file__).with_name('native-review-disk-full.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class FillerGuardTests(unittest.TestCase):
    def check_descriptor(self, *, device=22, capacity=128 * 1024 * 1024,
                         mode=stat.S_IFREG | 0o600, links=1, uid=None, accepted=False):
        metadata = SimpleNamespace(st_dev=device, st_uid=os.getuid() if uid is None else uid,
                                   st_mode=mode, st_nlink=links)
        with patch.object(fixture, 'attest'), \
             patch.object(Path, 'stat', return_value=SimpleNamespace(st_dev=1)), \
             patch.object(os, 'open', return_value=123) as opened, \
             patch.object(os, 'fstat', return_value=metadata), \
             patch.object(os, 'fstatvfs', return_value=SimpleNamespace(f_blocks=capacity // 4096, f_frsize=4096)), \
             patch.object(os, 'close') as closed, \
             patch.object(os, 'write') as written, \
             patch.object(os, 'ftruncate') as truncated:
            if accepted:
                self.assertEqual(fixture.open_filler(Path('/private/tmp/unused'), {'stat_device': 22}, os.O_WRONLY), 123)
                closed.assert_not_called()
            else:
                with self.assertRaises(AssertionError):
                    fixture.open_filler(Path('/private/tmp/unused'), {'stat_device': 22}, os.O_WRONLY)
                closed.assert_called_once_with(123)
            self.assertTrue(opened.call_args.args[1] & os.O_NOFOLLOW)
            written.assert_not_called()
            truncated.assert_not_called()

    def test_owned_bounded_descriptor_allowed(self):
        self.check_descriptor(accepted=True)

    def test_detached_mount_host_descriptor_rejected(self):
        self.check_descriptor(device=1)

    def test_different_device_rejected(self):
        self.check_descriptor(device=23)

    def test_oversized_filesystem_rejected(self):
        self.check_descriptor(capacity=500 * 1024 * 1024)

    def test_undersized_filesystem_rejected(self):
        self.check_descriptor(capacity=4096)

    def test_nonregular_descriptor_rejected(self):
        self.check_descriptor(mode=stat.S_IFDIR | 0o700)

    def test_hardlinked_filler_rejected(self):
        self.check_descriptor(links=2)

    def test_other_owner_rejected(self):
        self.check_descriptor(uid=os.getuid() + 1)

    def test_host_root_rejected_before_tools(self):
        with self.assertRaises(AssertionError):
            fixture.root_check(Path('/private/tmp'))

    def test_alias_root_rejected_before_tools(self):
        with self.assertRaises(AssertionError):
            fixture.root_check(Path('/tmp/aagedal-native-disk-full.invalid'))


class DocumentProofTests(unittest.TestCase):
    def setUp(self):
        self.original = dict(schemaVersion=2, primarySource={'canonicalPath': '/a.mov'},
                             secondarySource={'canonicalPath': '/b.mov'},
                             notes=[dict(id='abcdef01-0000-0000-0000-000000000001', text='Original',
                                         updatedAt=1, createdAt=1, primaryFrame=25, severity='minor')])
        self.recovered = copy.deepcopy(self.original)
        self.recovered['notes'][0].update(id=self.original['notes'][0]['id'].upper(), text='Recovered', updatedAt=2)

    def validate(self, value, deleted=False):
        fixture.validate_document(json.dumps(value), json.dumps(self.original), ' Recovered ', deleted)

    def test_recovery_allows_ui_trimming_uuid_case_and_update_time(self):
        self.validate(self.recovered)

    def test_recovery_rejects_severity_change(self):
        self.recovered['notes'][0]['severity'] = 'major'
        with self.assertRaises(AssertionError):
            self.validate(self.recovered)

    def test_recovery_rejects_missing_note(self):
        self.recovered['notes'] = []
        with self.assertRaises(AssertionError):
            self.validate(self.recovered)

    def test_deletion_preserves_sources_and_schema(self):
        self.recovered['notes'] = []
        self.validate(self.recovered, deleted=True)

    def test_deletion_rejects_remaining_note(self):
        with self.assertRaises(AssertionError):
            self.validate(self.recovered, deleted=True)

    def test_deletion_rejects_changed_source(self):
        self.recovered['notes'] = []
        self.recovered['primarySource']['canonicalPath'] = '/wrong.mov'
        with self.assertRaises(AssertionError):
            self.validate(self.recovered, deleted=True)

    def test_deletion_rejects_schema_change(self):
        self.recovered['notes'] = []
        self.recovered['schemaVersion'] = 3
        with self.assertRaises(AssertionError):
            self.validate(self.recovered, deleted=True)


if __name__ == '__main__':
    unittest.main()
