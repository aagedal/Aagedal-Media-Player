#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

"""Prepare a website appcast for the exact ZIP already published on GitHub."""

import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
REPOSITORY = "aagedal/Aagedal-Media-Player"
BASE_URL = "https://aagedal.me/apps/mediaplayer"
ET.register_namespace("sparkle", SPARKLE)


def release_identity(feed):
    root = ET.parse(feed).getroot()
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise ValueError("Expected an RSS channel")
    item = channel.find("item")
    if item is None:
        raise ValueError("Appcast has no release")
    version = item.findtext(f"{{{SPARKLE}}}shortVersionString", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected a stable release version")
    name = f"Aagedal_Media_Player_{version.replace('.', '-')}.zip"
    enclosure = item.find("enclosure")
    url = f"https://github.com/{REPOSITORY}/releases/download/{version}/{name}"
    if enclosure is None or enclosure.get("url") != url:
        raise ValueError("Latest enclosure does not match the expected GitHub release")
    signature = base64.b64decode(enclosure.get(f"{{{SPARKLE}}}edSignature", ""), validate=True)
    if len(signature) != 64:
        raise ValueError("Missing or invalid Sparkle signature")
    return root, channel, item, enclosure, version, name


def prepare(feed, archive, release_json, output):
    root, channel, item, enclosure, version, name = release_identity(feed)
    if archive.name != name:
        raise ValueError("Archive filename does not match the appcast")
    payload = json.loads(release_json.read_text())
    if payload.get("tag_name") != version or payload.get("draft") is not False or payload.get("prerelease") is not False:
        raise ValueError("Expected the matching published stable release")
    size = archive.stat().st_size
    if enclosure.get("length") != str(size):
        raise ValueError("Archive length does not match the signed appcast")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    spec = importlib.util.spec_from_file_location("asset_validator", Path(__file__).with_name("validate-github-release-asset.py"))
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    validator.validate_asset(payload, expected_name=name, expected_size=size, expected_sha256=digest)
    # Only advertise the artifact that this publication actually mirrors.
    # Signatures, build, OS requirement and release notes remain unchanged.
    for previous in list(channel.findall("item")):
        if previous is not item:
            channel.remove(previous)
    enclosure.set("url", f"{BASE_URL}/{name}")
    output.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(output / "mediaplayer.xml", encoding="utf-8", xml_declaration=True)
    manifest = {"version": version, "filename": name, "size": size, "sha256": digest,
                "download_url": f"{BASE_URL}/{name}",
                "feed_url": "https://aagedal.me/apps/appcast/mediaplayer.xml"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", type=Path, default=Path("appcast.xml"))
    parser.add_argument("--identity", action="store_true", help="Print validated version and filename for download")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--release-json", type=Path)
    parser.add_argument("--output", type=Path, default=Path("build/website-mirror"))
    args = parser.parse_args()
    if args.identity:
        *_, version, name = release_identity(args.appcast)
        print(f"version={version}\nfilename={name}")
    else:
        if args.archive is None or args.release_json is None:
            parser.error("--archive and --release-json are required")
        print(json.dumps(prepare(args.appcast, args.archive, args.release_json, args.output), indent=2))


if __name__ == "__main__":
    main()
