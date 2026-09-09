#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create disposable media/reviews for actual editor interchange acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New output directory")
    parser.add_argument("--rate", choices=("29.97", "59.94", "23.976"), default="29.97")
    parser.add_argument("--historical-rounded", action="store_true",
                        help="Store legacy rounded note rates and seconds for migration checks; source media keeps its exact rate")
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    numerator = {"29.97": 30000, "59.94": 60000, "23.976": 24000}[args.rate]
    denominator = 1001
    # Older note snapshots rounded the encoded frame rate to three decimals.
    # Preserve frame ordinals, but reproduce that stored rate and its seconds.
    stored_numerator = round(numerator * 1000 / denominator) if args.historical_rounded else numerator
    stored_denominator = 1000 if args.historical_rounded else denominator
    nominal = round(numerator / denominator)
    frame_count = numerator * 610 // denominator
    primary, secondary = root / "source-a.mov", root / "source-b.mov"
    ffmpeg = Path(__file__).resolve().parents[1] / "Aagedal Media Player/Binaries/ffmpeg"
    command = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
               f"testsrc2=size=160x90:rate={numerator}/{denominator}", "-frames:v", str(frame_count),
               "-c:v", "libx264", "-preset", "ultrafast", "-crf", "35", "-pix_fmt", "yuv420p"]
    if args.rate != "23.976":
        command += ["-timecode", "00:00:58;00"]
    command += ["-n", str(primary)]
    subprocess.run(command, check=True, timeout=300)
    shutil.copyfile(primary, secondary)
    # Match the app's Foundation URL rules, which differ from pathlib for
    # /private/tmp on macOS. Isolate Swift's temporary module cache as well.
    with tempfile.TemporaryDirectory(prefix="aagedal-review-fixture-") as cache:
        canonical_paths = json.loads(subprocess.check_output([
            "swift", "-module-cache-path", cache, "-e",
            "import Foundation; let paths = CommandLine.arguments.dropFirst().map { "
            "URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }; "
            "print(String(data: try JSONEncoder().encode(paths), encoding: .utf8)!)",
            str(primary), str(secondary)
        ], text=True, timeout=120))
    minute = nominal * 2
    ten_minute = nominal * 600 - (2 if nominal == 30 else 4) * 9 - nominal * 58
    anchors = [0, 1, minute - 1, minute, minute, ten_minute - 1, ten_minute, frame_count - 1]
    if args.rate == "23.976":
        anchors = [0, 1, nominal * 60 - 1, nominal * 60, nominal * 60, nominal * 600 - 1,
                   nominal * 600, frame_count - 1]
    notes = []
    for i, frame in enumerate(anchors):
        note = dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL, f"aagedal-interchange:{args.rate}:{i}")),
                    primaryFrame=frame, secondaryFrame=frame,
                    primaryTime=frame * stored_denominator / stored_numerator,
                    secondaryTime=frame * stored_denominator / stored_numerator,
                    primaryRateNumerator=stored_numerator, primaryRateDenominator=stored_denominator,
                    secondaryRateNumerator=stored_numerator, secondaryRateDenominator=stored_denominator,
                    text=f"Fixture {i + 1}: æøå 日本語 & <picture> \"quoted\"\tcolumn\nSecond line",
                    severity=["info", "minor", "major", "critical"][i % 4],
                    category=["general", "picture", "audio", "sync", "metadata"][i % 5],
                    status=["open", "inProgress", "resolved"][i % 3],
                    createdAt=1788900000000 + i * 1000, updatedAt=1788900000000 + i * 1000)
        if i in (0, 2, 5):
            note["primaryEndFrame"] = frame if i == 0 else frame + 2
        notes.append(note)
    # Intentionally out of order, including two independently identified notes at one frame.
    document = dict(schemaVersion=2, primarySource={"canonicalPath": canonical_paths[0]},
                    secondarySource={"canonicalPath": canonical_paths[1]}, notes=list(reversed(notes)))
    suffix = 14695981039346656037
    for byte in canonical_paths[1].encode():
        suffix = ((suffix ^ byte) * 1099511628211) & ((1 << 64) - 1)
    sidecar = root / f"source-a vs source-b-{suffix:x}.aagedal-compare.json"
    sidecar.write_text(json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    manifest = dict(rateNumerator=numerator, rateDenominator=denominator, durationFrames=frame_count,
                    historicalRounded=args.historical_rounded,
                    storedRateNumerator=stored_numerator, storedRateDenominator=stored_denominator,
                    sourceStartTimecode=None if args.rate == "23.976" else "00:00:58;00",
                    markerCount=len(notes), command=command,
                    sha256={path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in (primary, secondary, sidecar)})
    (root / "fixture-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Created {len(notes)} findings at {args.rate} fps in {root}")
    if args.historical_rounded:
        print(f"Migration fixture: both sources encode {numerator}/{denominator} fps; "
              f"both note snapshots store {stored_numerator}/{stored_denominator} fps with matching portable seconds.")
    print("Open source-a.mov, compare source-b.mov, then export CSV and editor markers in the app.")


if __name__ == "__main__":
    main()
