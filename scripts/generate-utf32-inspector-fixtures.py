#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate disposable, silent UTF-32 iXML fixtures in a new directory."""

import argparse
import hashlib
import json
from pathlib import Path
import struct


def chunk(tag, data):
    return tag.encode("ascii") + struct.pack("<I", len(data)) + data + (b"\0" if len(data) % 2 else b"")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New output directory (must not exist)")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    records = {}
    for order, bom in [("le", b"\xff\xfe\0\0"), ("be", b"\0\0\xfe\xff")]:
        xml = (
            f"<?xml version='1.0' encoding='UTF-32{order.upper()}'?>"
            "<BWFXML><PROJECT>Fjell &amp; sjø 🎙</PROJECT><SCENE>021A</SCENE>"
            "<TAKE>0003</TAKE><NOTE>UTF-32 native validation</NOTE><TRACK_LIST>"
            "<TRACK_COUNT>1</TRACK_COUNT><TRACK><CHANNEL_INDEX>6</CHANNEL_INDEX>"
            "<INTERLEAVE_INDEX>2</INTERLEAVE_INDEX><NAME>声 🎙</NAME>"
            "</TRACK></TRACK_LIST></BWFXML>"
        )
        content = (
            b"WAVE"
            + chunk("fmt ", struct.pack("<HHIIHH", 1, 2, 48000, 192000, 4, 16))
            + chunk("iXML", bom + xml.encode("utf-32-" + order))
            + chunk("data", bytes(384000))
        )
        data = b"RIFF" + struct.pack("<I", len(content)) + content
        name = f"utf32{order}.wav"
        with (args.output / name).open("xb") as output:
            output.write(data)
        records[name] = hashlib.sha256(data).hexdigest()
    with (args.output / "hashes.json").open("x") as output:
        json.dump(records, output, indent=2)
        output.write("\n")
    print(args.output)


if __name__ == "__main__":
    main()
