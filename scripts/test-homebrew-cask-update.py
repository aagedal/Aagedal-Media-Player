#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("update-homebrew-cask.py")
SPEC = importlib.util.spec_from_file_location("homebrew_cask_update", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class HomebrewCaskUpdateTests(unittest.TestCase):
    def test_updates_exact_declarations_and_preserves_comments(self) -> None:
        source = '''cask "aagedal-media-player" do
  version "1.6.0" # release
  sha256 "old" # archive
end
'''
        result = MODULE.updated_cask(source, "2.0.0-beta.1", "a" * 64)
        self.assertEqual(
            result,
            f'''cask "aagedal-media-player" do
  version "2.0.0-beta.1" # release
  sha256 "{'a' * 64}" # archive
end
''',
        )

    def test_rejects_missing_declarations(self) -> None:
        for source in ('sha256 "old"\n', 'version "1.0"\n'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                MODULE.updated_cask(source, "2.0.0", "a" * 64)

    def test_rejects_duplicate_declarations(self) -> None:
        for source in (
            'version "1"\nversion "2"\nsha256 "old"\n',
            'version "1"\nsha256 "old"\nsha256 "older"\n',
        ):
            with self.subTest(source=source), self.assertRaises(ValueError):
                MODULE.updated_cask(source, "2.0.0", "a" * 64)

    def test_does_not_match_comments_or_other_keys(self) -> None:
        source = '''# version "comment"
  app_version "1.0"
  # sha256 "comment"
  checksum_sha256 "old"
'''
        with self.assertRaises(ValueError):
            MODULE.updated_cask(source, "2.0.0", "a" * 64)


if __name__ == "__main__":
    unittest.main()
