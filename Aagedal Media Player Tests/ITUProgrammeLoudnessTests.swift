// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ITUProgrammeLoudnessTests: XCTestCase {
    /// The official programme audio remains outside the repository. Set the
    /// directory explicitly to run these independent, whole-file references.
    func testOfficialProgrammeReferencesWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ITU_LOUDNESS_REFERENCE_DIRECTORY"] else {
            throw XCTSkip("Set ITU_LOUDNESS_REFERENCE_DIRECTORY to run the official programme references")
        }
        XCTAssertFalse(directory.isEmpty, "Specify the directory containing all three official WAV files")
        guard !directory.isEmpty else { return }
        // ITU-R BS.2217-2, programme rows on printed pages 4–5: -23 ±0.1 LKFS.
        // https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BS.2217-2-2016-PDF-E.pdf
        // Archive downloads: https://www.itu.int/oth/R1102000001/en
        // These hashes identify the downloaded originals, not synthetic copies.
        let references: [(file: String, channels: Int, sha256: String)] = [
            ("1770-2 Conf Mono Voice+Music-23LKFS.wav", 1,
             "f8b318474b158c9f2ee842f0cfadf58ffcf504ffe8daa172220190d12dd0785b"),
            ("1770-2 Conf Stereo VinL+R-23LKFS.wav", 2,
             "3ff26c997d838aff36b4319f9e0a673c0b51fe26722ecb0153887b66f38c296f"),
            ("1770-2 Conf 6ch VinCntr-23LKFS.wav", 6,
             "ef2a0baef7f50db39eddfb1ba6f2a5445646050d113f81c6365cddca7f0448a0"),
        ]
        for reference in references {
            let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(reference.file)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, reference.sha256, "Reference bytes changed: \(reference.file)")
            guard digest == reference.sha256 else { continue }

            let metadata = try await MetadataService.shared.metadata(for: url)
            XCTAssertEqual(metadata.audioStreams.count, 1, reference.file)
            let stream = try XCTUnwrap(metadata.audioStreams.first)
            XCTAssertEqual(stream.channels, reference.channels, reference.file)
            XCTAssertEqual(stream.sampleRate, 48_000, reference.file)
            let result = try await FFmpegService.analyzeLUFS(
                url: url, audioStreamIndex: 0,
                channels: stream.channels, channelLayout: stream.channelLayout
            )
            let report: [String: Any] = [
                "file": reference.file, "sha256": digest,
                "channels": stream.channels ?? 0, "sampleRate": stream.sampleRate ?? 0,
                "channelLayout": stream.channelLayout ?? "unspecified",
                "expectedIntegratedLUFS": -23.0, "toleranceLU": 0.1,
                "integratedLUFS": String(result.integratedLoudness),
                // BS.2217-2 gives no LRA/true-peak targets for these programmes.
                "unreferencedObservations": [
                    "loudnessRangeLU": String(result.loudnessRange),
                    "truePeakDBTP": String(result.truePeak),
                ],
            ]
            let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let line = "ITU_PROGRAMME_LOUDNESS " + String(decoding: reportData, as: UTF8.self)
            print(line)
            let attachment = XCTAttachment(string: line)
            attachment.name = "ITU programme loudness — \(reference.channels) channels"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertNil(result.analysisRange)
            XCTAssertEqual(result.integratedLoudness, -23.0, accuracy: 0.1, reference.file)
            try await compareLiveLoudness(url: url, channels: reference.channels, sha256: digest)
        }
    }

    /// Independent C ebur128 window readings versus the shipping timestamp
    /// decoder and Swift DSP. This intentionally does not depend on an audio
    /// output device or claim native playback/presentation acceptance.
    private func compareLiveLoudness(url: URL, channels: Int, sha256: String) async throws {
        var decodeURL = url
        let prepared = FileManager.default.temporaryDirectory.appendingPathComponent("itu-live-5-1-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: prepared) }
        var preparedPayloadHash: String?
        if channels == 6 {
            // This hash-pinned original has a classic PCM header with no speaker
            // mask. BS.2217-2 declares L/R/C/LFE/Ls/Rs. Give those unchanged
            // samples an explicit side-surround mask; do not trust a decoder guess.
            let original = try Data(contentsOf: url)
            let payload = Data(original.dropFirst(44))
            let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, "5e1020672b02d963f98aab2d827961656f941da79ab4b14733f62b574737848f")
            var wave = Data()
            func integer<T: FixedWidthInteger>(_ value: T) {
                var littleEndian = value.littleEndian
                withUnsafeBytes(of: &littleEndian) { wave.append(contentsOf: $0) }
            }
            wave.append(contentsOf: "RIFF".utf8)
            integer(UInt32(60 + payload.count))
            wave.append(contentsOf: "WAVEfmt ".utf8)
            integer(UInt32(40)); integer(UInt16(0xFFFE)); integer(UInt16(6))
            integer(UInt32(48_000)); integer(UInt32(48_000 * 12))
            integer(UInt16(12)); integer(UInt16(16)); integer(UInt16(22)); integer(UInt16(16))
            integer(UInt32(0x60F))
            wave.append(contentsOf: [1, 0, 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71])
            wave.append(contentsOf: "data".utf8)
            integer(UInt32(payload.count))
            wave.append(payload)
            try wave.write(to: prepared)
            decodeURL = prepared
            preparedPayloadHash = hash
            let metadata = try await MetadataService.shared.metadata(for: prepared)
            XCTAssertEqual(metadata.audioStreams.first?.channelLayout, "5.1(side)")
        }
        let executable = try XCTUnwrap(FFmpegService.ffmpegPath)
        let arguments = [
            "-hide_banner", "-nostdin", "-nostats", "-v", "error",
            "-i", decodeURL.path, "-map", "0:a:0", "-vn", "-sn", "-dn",
            "-af", "ebur128=metadata=1:dualmono=false,ametadata=print:file=-",
            "-f", "null", "-",
        ]
        let oracle = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: executable), arguments: arguments,
            outputLimit: 4 * 1_024 * 1_024
        )
        XCTAssertEqual(oracle.terminationStatus, 0, String(decoding: oracle.standardError, as: UTF8.self))
        guard oracle.terminationStatus == 0 else { return }
        let rawReference = String(decoding: oracle.standardOutput, as: UTF8.self)
        let referenceAttachment = XCTAttachment(string: rawReference)
        referenceAttachment.name = "ITU live ebur128 oracle — \(channels) channels"
        referenceAttachment.lifetime = .keepAlways
        add(referenceAttachment)

        var expected: [Int64: [String: Double]] = [:]
        var endpoint: Int64?
        for line in rawReference.split(separator: "\n") {
            if line.hasPrefix("frame:") {
                let fields = line.split(separator: " ")
                let pts = try XCTUnwrap(fields.first(where: { $0.hasPrefix("pts:") }))
                // ametadata's pts is the START of each 100-ms audio frame.
                let start = try XCTUnwrap(Int64(pts.dropFirst(4)))
                let end = start + 4_800
                endpoint = end
                XCTAssertNil(expected[end], "Duplicate oracle endpoint")
                expected[end] = [:]
            } else if line.hasPrefix("lavfi.r128.M=") || line.hasPrefix("lavfi.r128.S=") {
                let parts = line.split(separator: "=", maxSplits: 1)
                let frame = try XCTUnwrap(endpoint)
                let value = try XCTUnwrap(Double(parts[1]))
                XCTAssertTrue(value.isFinite)
                expected[frame]?[String(parts[0].suffix(1))] = value
            }
        }
        XCTAssertGreaterThan(expected.count, 30, "Oracle must cover complete short-term windows")
        let layout: LiveAudioMeterFormat.Layout = switch channels {
        case 1: .mono
        case 2: .stereo
        case 6: .surround5Point1
        default: .unknown(channels: channels)
        }
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: layout)
        let request = try LiveAudioMeterDecodeRequest(
            url: decodeURL, audioStreamOrderIndex: 0, format: format,
            startSourceFrame: 0, startSourceTime: 0
        )
        let snapshots = LiveSnapshotBox()
        let completion = try await LiveAudioMeterDecoder.decode(request) { snapshots.append($0) }
        let final = try XCTUnwrap(completion.finalSnapshot)
        XCTAssertTrue(final.isFinal)
        XCTAssertEqual(completion.provenance.timestampTimeBase, "1/48000")
        XCTAssertEqual(completion.provenance.syntheticInitialSilenceFrameCount, 0)
        let completeWindows = snapshots.values.filter {
            !$0.isFinal && $0.loudnessEndFrame == $0.endFrame && $0.endFrame % 4_800 == 0
        }
        XCTAssertEqual(completeWindows.count, Int(final.endFrame / 4_800) - 3)
        var maximumMomentaryError = 0.0
        var maximumShortTermError = 0.0
        var momentaryCount = 0
        var shortTermCount = 0
        var rows: [[String: Any]] = []
        for snapshot in completeWindows {
            let target = try XCTUnwrap(expected[snapshot.endFrame], "Missing exact source-frame oracle")
            var row: [String: Any] = ["endFrame": snapshot.endFrame]
            for (key, reading, minimumFrames) in [
                ("M", snapshot.momentaryLUFS, Int64(19_200)),
                ("S", snapshot.shortTermLUFS, Int64(144_000)),
            ] {
                guard snapshot.endFrame >= minimumFrames else {
                    XCTAssertNil(reading, "Incomplete loudness windows must remain unavailable")
                    continue
                }
                let actual = try XCTUnwrap(reading)
                let reference = try XCTUnwrap(target[key])
                // ebur128 encodes exact digital silence as its -120.691 floor;
                // the app uses -infinity. Do not confuse either with missing data.
                let error = actual == -.infinity && reference <= -120.690 ? 0 : abs(actual - reference)
                XCTAssertTrue(error.isFinite)
                XCTAssertLessThanOrEqual(error, 0.1,
                    "\(url.lastPathComponent) \(key) at source frame \(snapshot.endFrame)")
                if key == "M" {
                    maximumMomentaryError = max(maximumMomentaryError, error)
                    momentaryCount += 1
                } else {
                    maximumShortTermError = max(maximumShortTermError, error)
                    shortTermCount += 1
                }
                row[key] = ["actualLUFS": String(actual), "referenceLUFS": reference, "errorLU": error]
            }
            rows.append(row)
        }
        XCTAssertGreaterThan(momentaryCount, 0)
        XCTAssertGreaterThan(shortTermCount, 0)
        var report: [String: Any] = [
            "file": url.lastPathComponent, "sha256": sha256, "channels": channels,
            "sampleRate": 48_000, "toleranceLU": 0.1,
            "momentaryCount": momentaryCount, "shortTermCount": shortTermCount,
            "maximumMomentaryErrorLU": maximumMomentaryError,
            "maximumShortTermErrorLU": maximumShortTermError,
            "decodedEndFrame": final.endFrame,
            "decoderVersion": completion.provenance.decoderVersion,
            "timestampTimeBase": completion.provenance.timestampTimeBase,
            "referenceArguments": arguments,
        ]
        if let preparedPayloadHash {
            report["preparedPCMSHA256"] = preparedPayloadHash
            report["preparation"] = "Unchanged PCM words/order; explicit 5.1(side) WAVE speaker mask 0x60f"
        }
        for (name, object) in [("ITU_LIVE_LOUDNESS", report), ("ITU_LIVE_LOUDNESS_WINDOWS", ["windows": rows])] {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let line = name + " " + String(decoding: data, as: UTF8.self)
            if name == "ITU_LIVE_LOUDNESS" { print(line) }
            let attachment = XCTAttachment(string: line)
            attachment.name = "\(name) — \(channels) channels"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private final class LiveSnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [LiveAudioMeterSnapshot] = []
        var values: [LiveAudioMeterSnapshot] { lock.withLock { storage } }
        func append(_ snapshot: LiveAudioMeterSnapshot) { lock.withLock { storage.append(snapshot) } }
    }
}
