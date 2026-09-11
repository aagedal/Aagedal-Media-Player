#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate and independently check a silent RIFX bext fixture using libsndfile."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


# Compile against the installed header rather than duplicating the C ABI in ctypes.
GENERATOR = r'''
#include <sndfile.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    SF_INFO info = {0};
    info.samplerate = 48000;
    info.channels = 2;
    info.format = SF_FORMAT_WAV | SF_FORMAT_PCM_16 | SF_ENDIAN_BIG;
    SNDFILE *file = sf_open(argv[1], SFM_WRITE, &info);
    if (!file) { fprintf(stderr, "%s\n", sf_strerror(NULL)); return 1; }
    SF_BROADCAST_INFO bext = {0};
    strcpy(bext.description, "libsndfile RIFX interoperability");
    strcpy(bext.originator, "Aagedal fixture generator");
    strcpy(bext.originator_reference, "rifx-bext-001");
    memcpy(bext.origination_date, "2026-09-11", 10);
    memcpy(bext.origination_time, "12:34:56", 8);
    bext.time_reference_low = 0x9abcdef0;
    bext.time_reference_high = 0x12345678;
    bext.version = 2;
    bext.umid[0] = 1;
    bext.loudness_value = -2345;
    bext.loudness_range = 456;
    bext.max_true_peak_level = -123;
    bext.max_momentary_loudness = -2000;
    bext.max_shortterm_loudness = -2100;
    strcpy(bext.coding_history, "A=PCM,F=48000,W=16,M=stereo\r\n");
    bext.coding_history_size = (unsigned int) strlen(bext.coding_history);
    if (sf_command(file, SFC_SET_BROADCAST_INFO, &bext, sizeof bext) != SF_TRUE) {
        fprintf(stderr, "SET_BROADCAST_INFO failed: %s\n", sf_strerror(file));
        sf_close(file);
        return 1;
    }
    short silence[20] = {0};
    if (sf_writef_short(file, silence, 10) != 10) {
        fprintf(stderr, "Writing audio failed: %s\n", sf_strerror(file));
        sf_close(file);
        return 1;
    }
    if (sf_close(file)) return 1;
    puts(sf_version_string());
    return 0;
}
'''


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_fixture(path):
    data = path.read_bytes()
    require(data[:4] == b"RIFX" and data[8:12] == b"WAVE", "Expected RIFX/WAVE")
    require(struct.unpack_from(">I", data, 4)[0] + 8 == len(data), "Invalid container length")
    chunks = {}
    position = 12
    while position < len(data):
        require(position + 8 <= len(data), "Incomplete chunk header")
        tag, size = struct.unpack_from(">4sI", data, position)
        start = position + 8
        end = start + size
        require(end + size % 2 <= len(data), "Chunk extends beyond container")
        require(tag not in chunks, "Duplicate chunk")
        chunks[tag] = data[start:end]
        position = end + size % 2
    fmt = chunks[b"fmt "]
    require(struct.unpack_from(">HHIIHH", fmt) == (1, 2, 48000, 192000, 4, 16), "Unexpected PCM format")
    require(chunks[b"data"] == bytes(40), "Expected ten frames of stereo silence")
    bext = chunks[b"bext"]
    require(len(bext) >= 602, "Short bext")
    expected_text = [(0, 256, b"libsndfile RIFX interoperability"),
                     (256, 288, b"Aagedal fixture generator"), (288, 320, b"rifx-bext-001"),
                     (320, 330, b"2026-09-11"), (330, 338, b"12:34:56")]
    for start, end, expected in expected_text:
        require(bext[start:end].split(b"\0", 1)[0] == expected, f"Unexpected text at {start}")
    low, high, version = struct.unpack_from(">IIH", bext, 338)
    require((low, high, version) == (0x9abcdef0, 0x12345678, 2), "Incorrect low/high/version field order")
    require(bext[348:412] == bytes([1]) + bytes(63), "UMID changed")
    require(struct.unpack_from(">hhhhh", bext, 412) == (-2345, 456, -123, -2000, -2100), "Incorrect loudness encoding")
    # libsndfile appends its own coding-history entry; retain and report it.
    history = bext[602:].rstrip(b"\0").decode("ascii")
    require(history.startswith("A=PCM,F=48000,W=16,M=stereo\r\n"), "Coding history prefix changed")
    return {"sha256": hashlib.sha256(data).hexdigest(), "size_bytes": len(data),
            "container": "RIFX", "sample_rate": 48000, "channels": 2, "sample_frames": 10,
            "bext_version": version, "time_reference_samples": (high << 32) | low,
            "time_reference_bytes_hex": bext[338:346].hex(), "coding_history": history,
            "checks": "container/chunk bounds, format, silence, all fixed bext fields, coding history prefix"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New output directory (must not exist)")
    parser.add_argument("--prefix", type=Path, default=Path("/opt/homebrew"),
                        help="libsndfile installation prefix (default: /opt/homebrew)")
    parser.add_argument("--compiler", help="C compiler executable (default: xcrun clang on macOS, cc elsewhere)")
    parser.add_argument("--sdk", type=Path, help="Explicit macOS SDK path if the selected command-line SDK mismatches the compiler")
    args = parser.parse_args()
    compiler = args.compiler or (subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()
                                 if sys.platform == "darwin" else "cc")
    sdk_flags = (["-isysroot", str(args.sdk) if args.sdk else subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()]
                 if sys.platform == "darwin" else [])
    prefix = args.prefix.resolve()
    require((prefix / "include/sndfile.h").is_file(), "Missing installed sndfile.h")
    args.output.mkdir(parents=True, exist_ok=False)
    fixture = args.output.resolve() / "libsndfile-rifx-bext.wav"
    with tempfile.TemporaryDirectory(prefix="rifx-bext-generator-") as temp:
        source = Path(temp) / "generate.c"
        binary = Path(temp) / "generate"
        source.write_text(GENERATOR)
        subprocess.run([compiler, *sdk_flags, "-std=c11", "-Wall", "-Wextra", "-Werror", str(source),
                        "-I", str(prefix / "include"), "-L", str(prefix / "lib"),
                        "-Wl,-rpath," + str(prefix / "lib"), "-lsndfile", "-o", str(binary)], check=True)
        result = subprocess.run([str(binary), str(fixture)], check=True, capture_output=True, text=True)
    report = check_fixture(fixture)
    report["producer"] = result.stdout.strip()
    report["fixture"] = fixture.name
    (args.output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
