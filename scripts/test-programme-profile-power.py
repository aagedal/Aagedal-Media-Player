#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('power', Path(__file__).with_name('check-programme-profile-power.py'))
power = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power)


class PowerTests(unittest.TestCase):
    def test_window_boundaries_and_event_types(self):
        log = '''2026-09-12 11:34:59 +0200 Sleep               \tOld event
2026-09-12 11:35:00 +0200 Sleep               \tEntering Sleep due to Clamshell
2026-09-12 11:35:01 +0200 Wake Requests       \tUnrelated requests excluded
2026-09-12 11:35:02 +0200 PM Client Acks      \tUnrelated clients excluded
2026-09-12 11:35:03 +0200 DarkWake            \tDark wake
2026-09-12 11:35:04 +0200 Wake                \tFull wake
2026-09-12 11:35:05 +0200 Sleep               \tLater event'''
        events = power.events_during(log, '2026-09-12 11:35:00', '2026-09-12 11:35:04')
        self.assertEqual([event['kind'] for event in events], ['Sleep', 'DarkWake', 'Wake'])

    def test_no_sleep_and_invalid_clock(self):
        self.assertEqual(power.events_during('', '2026-09-12 11:35:00', '2026-09-12 11:35:04'), [])
        with self.assertRaises(ValueError):
            power.events_during('', '2026-09-12 11:35:04', '2026-09-12 11:35:00')


if __name__ == '__main__': unittest.main()
