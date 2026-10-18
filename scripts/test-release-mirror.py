#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("mirror", Path(__file__).with_name("prepare-release-mirror.py"))
mirror = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mirror)


class ReleaseMirrorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / "Aagedal_Media_Player_2-1-0.zip"
        self.archive.write_bytes(b"signed archive fixture")
        self.feed = self.root / "appcast.xml"
        signature = base64.b64encode(bytes(range(64))).decode()
        self.feed.write_text(f'''<rss xmlns:sparkle="{mirror.SPARKLE}"><channel>
          <title>Aagedal Media Player</title><item><title>Version 2.1.0</title>
          <sparkle:version>166</sparkle:version><sparkle:shortVersionString>2.1.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/{mirror.REPOSITORY}/releases/download/2.1.0/{self.archive.name}"
          length="{self.archive.stat().st_size}" sparkle:edSignature="{signature}" />
          <description><![CDATA[<p>Waveforms &amp; LUFS</p>]]></description></item>
          <item><title>Old release without a mirrored ZIP</title></item></channel></rss>''')
        self.payload = {"tag_name": "2.1.0", "draft": False, "prerelease": False,
                        "assets": [{"name": self.archive.name, "state": "uploaded",
                                    "size": self.archive.stat().st_size,
                                    "digest": "sha256:" + hashlib.sha256(self.archive.read_bytes()).hexdigest()}]}
        self.metadata = self.root / "release.json"
        self.output = self.root / "mirror"

    def prepare(self):
        self.metadata.write_text(json.dumps(self.payload))
        return mirror.prepare(self.feed, self.archive, self.metadata, self.output)

    def test_preserves_signed_metadata_and_notes_and_only_advertises_mirrored_zip(self):
        source = ET.parse(self.feed).find("channel/item")
        manifest = self.prepare()
        items = ET.parse(self.output / "mediaplayer.xml").findall("channel/item")
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].find("enclosure").get("url"), manifest["download_url"])
        source.find("enclosure").set("url", manifest["download_url"])
        self.assertEqual(ET.tostring(source), ET.tostring(items[0]))
        self.assertEqual(manifest["sha256"], hashlib.sha256(self.archive.read_bytes()).hexdigest())

    def test_rejects_same_size_archive_substitution_before_writing_feed(self):
        self.archive.write_bytes(b"x" * self.archive.stat().st_size)
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_rejects_wrong_release_draft_prerelease_and_missing_digest(self):
        for key, value in (("tag_name", "2.0.0"), ("draft", True), ("prerelease", True)):
            with self.subTest(key=key):
                previous = self.payload[key]
                self.payload[key] = value
                with self.assertRaises(ValueError):
                    self.prepare()
                self.payload[key] = previous
        del self.payload["assets"][0]["digest"]
        with self.assertRaises(ValueError):
            self.prepare()

    def test_rejects_unexpected_enclosure_and_invalid_signature(self):
        source = self.feed.read_text()
        for altered in (source.replace("https://github.com/", "https://example.com/"),
                        source.replace(base64.b64encode(bytes(range(64))).decode(), "bad")):
            self.feed.write_text(altered)
            with self.assertRaises(ValueError):
                self.prepare()


if __name__ == "__main__":
    unittest.main()
