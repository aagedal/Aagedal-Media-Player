// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ITUSevenPointOneLoudnessTests: XCTestCase {
    func testOfficialEightChannelReferenceWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ITU_7_1_REFERENCE_DIRECTORY"] else { return }
        XCTAssertFalse(directory.isEmpty)
        guard !directory.isEmpty else { return }
        let file = "1770Conf-23LKFS-8channel.wav"
        let original = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(file))
        let sourceHash = digest(original)
        XCTAssertEqual(sourceHash, "421f7441bbc7c0a922148f9b68d50640a8ab251bf2ceca376188fbbb952a240c")
        guard sourceHash == "421f7441bbc7c0a922148f9b68d50640a8ab251bf2ceca376188fbbb952a240c" else { return }

        // BS.2217-2, printed p.5: source order L/R/C/LFE/Lss/Rss/Lrs/Rrs.
        // This pinned original has a 44-byte PCM header with no speaker mask.
        // Give it an explicit conventional WAVE order (rear before side),
        // preserving every PCM word without decoding, resampling, or gain.
        var payload = Array(original.dropFirst(44))
        for frame in stride(from: 0, to: payload.count, by: 16) {
            for byte in 0..<4 { payload.swapAt(frame + 8 + byte, frame + 12 + byte) }
        }
        let payloadHash = digest(Data(payload))
        // Independently calculated from the downloaded original with Python.
        XCTAssertEqual(payloadHash, "3c585490610ff8e14d9e80c6967a2a0b848cc3d4cc8a4181642403daa4142f72")
        let prepared = FileManager.default.temporaryDirectory.appendingPathComponent("itu-prepared-7-1-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: prepared) }
        try explicitSevenPointOneWave(payload).write(to: prepared)

        let metadata = try await MetadataService.shared.metadata(for: prepared)
        XCTAssertEqual(metadata.audioStreams.count, 1)
        let stream = try XCTUnwrap(metadata.audioStreams.first)
        XCTAssertEqual(stream.channels, 8)
        XCTAssertEqual(stream.sampleRate, 48_000)
        XCTAssertEqual(stream.channelLayout, "7.1")
        let result = try await FFmpegService.analyzeLUFS(
            url: prepared, audioStreamIndex: 0, channels: stream.channels, channelLayout: stream.channelLayout
        )
        let report: [String: Any] = [
            "file": file, "sourceSHA256": sourceHash, "preparedPCMSHA256": payloadHash,
            "preparation": "Lossless PCM channel reorder [0,1,2,3,6,7,4,5]; WAVE speaker mask 0x63f",
            "channels": stream.channels ?? 0, "sampleRate": stream.sampleRate ?? 0,
            "channelLayout": stream.channelLayout ?? "unspecified",
            "expectedIntegratedLUFS": -23.0, "toleranceLU": 0.1,
            "integratedLUFS": String(result.integratedLoudness),
            "weightingCorrection": result.weightingCorrection?.rawValue ?? "none",
            "unreferencedObservations": [
                "loudnessRangeLU": String(result.loudnessRange), "truePeakDBTP": String(result.truePeak),
            ],
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let line = "ITU_7_1_LOUDNESS " + String(decoding: reportData, as: UTF8.self)
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "ITU prepared 7.1 channel gain reference"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNil(result.analysisRange)
        XCTAssertEqual(result.weightingCorrection, .bs1770Conventional7Point1RearChannels)
        // BS.2217-2 p.1 gives ±0.1 LKFS; p.5 gives this reference's −23 target.
        XCTAssertEqual(result.integratedLoudness, -23, accuracy: 0.1)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func explicitSevenPointOneWave(_ payload: [UInt8]) -> Data {
        var wave = Data()
        func integer<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wave.append(contentsOf: $0) }
        }
        wave.append(contentsOf: "RIFF".utf8)
        integer(UInt32(60 + payload.count))
        wave.append(contentsOf: "WAVEfmt ".utf8)
        integer(UInt32(40))
        integer(UInt16(0xFFFE))
        integer(UInt16(8))
        integer(UInt32(48_000))
        integer(UInt32(48_000 * 16))
        integer(UInt16(16))
        integer(UInt16(16))
        integer(UInt16(22))
        integer(UInt16(16))
        integer(UInt32(0x63F))
        wave.append(contentsOf: [1, 0, 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71])
        wave.append(contentsOf: "data".utf8)
        integer(UInt32(payload.count))
        wave.append(contentsOf: payload)
        return wave
    }
}
