#!/usr/bin/env python3
"""Qualify a newly clocked DTS-HD MA preparation without changing coded audio.

All media stays in the explicitly supplied scratch directory. Retained evidence
contains commands, timing, checksums and identities, never audio or packet bytes.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, default=Path(__file__).parent)
    parser.add_argument("--bundled-ffmpeg", type=Path, required=True)
    parser.add_argument("--independent-ffmpeg", type=Path, required=True)
    parser.add_argument("--independent-ffprobe", type=Path, required=True)
    args = parser.parse_args()
    args.scratch.mkdir(parents=True, exist_ok=True)
    args.evidence.mkdir(parents=True, exist_ok=True)
    source_hash = sha256(args.source)
    raw = args.scratch / "source-copy.dtshd"
    prepared = args.scratch / "source-copy.mka"

    def run(name, command, compressed=False):
        result = subprocess.run(list(map(str, command)), capture_output=True, check=False)
        write_json(args.evidence / f"{name}-command.json", {
            "arguments": list(map(str, command)), "exitCode": result.returncode,
            "stdoutSHA256": hashlib.sha256(result.stdout).hexdigest(),
        })
        (args.evidence / f"{name}-stderr.txt").write_bytes(result.stderr)
        if compressed:
            # Deterministic compression prevents timestamps from changing receipts.
            (args.evidence / f"{name}-stdout.json.gz").write_bytes(
                gzip.compress(result.stdout, mtime=0)
            )
        else:
            (args.evidence / f"{name}-stdout.txt").write_bytes(result.stdout)
        if result.returncode:
            raise RuntimeError(f"{name} failed: {result.stderr.decode(errors='replace')}")
        return result.stdout

    for name, tool in [("bundled-version", args.bundled_ffmpeg),
                       ("independent-version", args.independent_ffmpeg),
                       ("independent-probe-version", args.independent_ffprobe)]:
        run(name, [tool, "-version"])
    ff = [args.independent_ffmpeg, "-hide_banner", "-nostdin", "-v", "error"]
    run("extract", ff + ["-i", args.source, "-map", "0:a:0", "-t", "30",
                         "-c:a", "copy", "-f", "dts", "-y", raw])
    run("remux", ff + ["-f", "dts", "-i", raw, "-map", "0:a:0",
                       "-c:a", "copy", "-y", prepared])

    def packets(name, path, limit=None):
        command = [args.independent_ffprobe, "-v", "error", "-select_streams", "a:0"]
        if limit is not None:
            command += ["-read_intervals", f"%+{limit}"]
        command += ["-show_packets", "-show_streams", "-show_data_hash", "sha256",
                    "-of", "json", path]
        return json.loads(run(name, command, compressed=True))

    original = packets("source-packets", args.source, 31)
    extracted = packets("elementary-packets", raw)
    remuxed = packets("prepared-packets", prepared)
    count = len(extracted["packets"])
    assert count > 0
    assert len(original["packets"]) >= count
    assert len(remuxed["packets"]) == count
    def coded_packets(records):
        return [(int(record["size"]), record["data_hash"]) for record in records]
    coded = coded_packets(extracted["packets"])
    assert coded_packets(original["packets"][:count]) == coded
    assert coded_packets(remuxed["packets"]) == coded
    for probe in [original, extracted, remuxed]:
        stream = probe["streams"][0]
        assert stream["profile"] == "DTS-HD MA"
        assert stream["sample_rate"] == "48000"
        assert stream["channels"] == 6
        assert stream["channel_layout"] == "5.1(side)"

    def pcm(name, tool, path):
        command = [str(tool), "-hide_banner", "-nostdin", "-v", "error",
                   "-drc_scale", "0", "-target_level", "0", "-i", str(path),
                   "-map", "0:a:0", "-frames:a", str(count), "-c:a", "pcm_f32le",
                   "-f", "f32le", "pipe:1"]
        digest = hashlib.sha256()
        byte_count = 0
        # stderr is tiny at this log level; retain it in a file so no pipe can block.
        with (args.evidence / f"{name}-stderr.txt").open("wb") as error:
            with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=error) as process:
                for block in iter(lambda: process.stdout.read(1 << 20), b""):
                    digest.update(block)
                    byte_count += len(block)
                exit_code = process.wait()
        result = {"arguments": command, "exitCode": exit_code,
                  "pcmByteCount": byte_count, "pcmSHA256": digest.hexdigest()}
        write_json(args.evidence / f"{name}-command.json", result)
        assert exit_code == 0
        return {"pcmByteCount": byte_count, "pcmSHA256": digest.hexdigest()}

    decoded = {}
    for tool_name, tool in [("bundled", args.bundled_ffmpeg),
                            ("independent", args.independent_ffmpeg)]:
        for source_name, path in [("original", args.source), ("elementary", raw),
                                  ("prepared", prepared)]:
            name = f"{tool_name}-{source_name}-pcm"
            decoded[name] = pcm(name, tool, path)
    assert all(value == next(iter(decoded.values())) for value in decoded.values())
    assert next(iter(decoded.values()))["pcmByteCount"] == count * 512 * 6 * 4

    base = [args.bundled_ffmpeg, "-hide_banner", "-nostdin", "-v", "error",
            "-ss", "0.000000000", "-accurate_seek", "-drc_scale", "0",
            "-target_level", "0", "-i", prepared, "-map", "0:a:0",
            "-vn", "-sn", "-dn", "-map_metadata", "-1", "-af",
            "asettb=expr=1/sr,atrim=start_pts=0,asetpts=PTS-0", "-c:a", "pcm_f32le"]
    framecrc = run("prepared-production-filter-framecrc", base + ["-f", "framecrc", "pipe:1"])
    records = [[field.strip() for field in line.split(",")]
               for line in framecrc.decode().splitlines() if line[:1].isdigit()]
    assert len(records) == count
    next_pts = 0
    for record in records:
        assert int(record[1]) == next_pts and int(record[2]) == next_pts
        assert int(record[3]) == 512 and int(record[4]) == 512 * 6 * 4
        next_pts += 512
    # The copy operations must never have modified the retained original.
    assert sha256(args.source) == source_hash
    summary = {
        "source": {"path": str(args.source), "sha256": source_hash},
        "elementary": {"path": str(raw), "sha256": sha256(raw), "bytes": raw.stat().st_size},
        "prepared": {"path": str(prepared), "sha256": sha256(prepared),
                     "bytes": prepared.stat().st_size},
        "packetCount": count, "sourceFrameCount": next_pts, "sampleRate": 48000,
        "sourceChannels": 6, "channelLayout": "5.1(side)", "profile": "DTS-HD MA",
        "codedPacketSequenceSHA256": hashlib.sha256(json.dumps(coded).encode()).hexdigest(),
        "originalPrefixElementaryAndPreparedCodedPacketsMatch": True,
        "toolIdentities": {
            name: {"path": str(tool), "sha256": sha256(tool)}
            for name, tool in [("bundledFFmpeg", args.bundled_ffmpeg),
                               ("independentFFmpeg", args.independent_ffmpeg),
                               ("independentFFprobe", args.independent_ffprobe)]
        },
        "decodedPCM": decoded, "allSixPCMDecodesMatch": True,
        "preparedProductionFilterInitialPTS": 0,
        "preparedProductionFilterMaximumAbsoluteTimestampDeviationFrames": 0,
        "scope": "New source clock from lossless elementary stream preparation; original container timestamps remain rejected.",
    }
    write_json(args.evidence / "qualification-summary.json", summary)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
