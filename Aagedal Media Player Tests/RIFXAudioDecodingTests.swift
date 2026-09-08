// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class RIFXAudioDecodingTests: XCTestCase {
    func testEverySupportedEncodingDecodesActualBigEndianSamples() async throws {
        let ffmpeg = try XCTUnwrap(FFmpegService.ffmpegPath)
        for (tag, bits) in [(1, 8), (1, 16), (1, 24), (1, 32), (1, 64), (3, 32), (3, 64)] {
            let url = try writeWave(tag: tag, bits: bits, frames: 2) { frame in
                frame == 0 ? 0.25 : -0.25
            }
            defer { try? FileManager.default.removeItem(at: url) }
            let arguments = try RIFXAudioDecoding.ffmpegInputArguments(for: url)
            let result = try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: ffmpeg),
                arguments: ["-v", "error"] + arguments + [
                    "-i", url.path, "-f", "f32le", "-c:a", "pcm_f32le", "pipe:1",
                ]
            )
            XCTAssertEqual(result.terminationStatus, 0, "tag \(tag), \(bits) bits")
            var expected = Data()
            for value: Float in [0.25, 0.25, -0.25, -0.25] {
                var bytes = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bytes) { expected.append(contentsOf: $0) }
            }
            XCTAssertEqual(result.standardOutput, expected, "tag \(tag), \(bits) bits")
        }
    }

    func testProductionLoudnessMeasuresBigEndianPCMAndFloatCalibration() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        for (tag, bits) in [(1, 16), (1, 24), (1, 32), (1, 64), (3, 32), (3, 64)] {
            let url = try writeWave(tag: tag, bits: bits, frames: 3 * 48_000) { frame in
                pow(10, -23.0 / 20) * sin(2 * .pi * 1_000 * Double(frame) / 48_000)
            }
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTAssertEqual(result.integratedLoudness, -23, accuracy: 0.1, "tag \(tag), \(bits) bits")
            XCTAssertEqual(result.truePeak, -23, accuracy: 0.1, "tag \(tag), \(bits) bits")
        }
    }

    func testProductionWaveformsPreserveBigEndianAmplitudes() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        for (tag, bits) in [(1, 16), (3, 32), (3, 64)] {
            let url = try writeWave(tag: tag, bits: bits, frames: 48_000) { _ in 0.25 }
            defer { try? FileManager.default.removeItem(at: url) }
            let output = try await AudioWaveformGenerator.generateNativeWaveforms(request: .init(
                url: url, streamIndex: 0, channelCount: 2, duration: 1,
                colorHex: "FF00FF", gamma: 1, pixelsPerSecond: 400,
                channelHeight: 24, maxWidth: 400
            ))
            XCTAssertEqual(output.amplitudes.count, 2)
            for amplitude in output.amplitudes {
                XCTAssertEqual(amplitude.maxs[200], 0.25, accuracy: 0.0001)
                XCTAssertEqual(amplitude.mins[200], 0, accuracy: 0.0001)
            }
        }
    }

    func testOverrideUsesContainerSignatureAndRejectsInvalidRIFX() throws {
        let littleEndian = try writeWave(tag: 1, bits: 16, frames: 2, bigEndian: false) { _ in 0.25 }
        defer { try? FileManager.default.removeItem(at: littleEndian) }
        XCTAssertEqual(try RIFXAudioDecoding.ffmpegInputArguments(for: littleEndian), [])
        let bigEndian = try writeWave(tag: 1, bits: 16, frames: 2) { _ in 0.25 }
        defer { try? FileManager.default.removeItem(at: bigEndian) }
        XCTAssertEqual(try RIFXAudioDecoding.ffmpegInputArguments(for: bigEndian), ["-c:a", "pcm_s16be"])
        var malformed = try Data(contentsOf: bigEndian)
        malformed[32] = 0
        malformed[33] = 1 // Incorrect block alignment for stereo s16.
        try malformed.write(to: bigEndian)
        XCTAssertThrowsError(try RIFXAudioDecoding.ffmpegInputArguments(for: bigEndian))
    }

    func testPlaybackAndTrimReportActionableErrorWithoutMetadata() throws {
        let url = try writeWave(tag: 1, bits: 16, frames: 2) { _ in 0.25 }
        defer { try? FileManager.default.removeItem(at: url) }
        let player = MPVPlayer()
        player.load(url: url, autostart: true)
        XCTAssertEqual(player.error, RIFXAudioDecoding.playbackUnavailable)
        XCTAssertFalse(player.isFileLoaded)
        XCTAssertFalse(player.isPlaying)

        let operations = MediaOperationsController()
        operations.exportTrim(for: MediaItem(url: url, name: "RIFX", size: 0))
        XCTAssertEqual(operations.trimExportState, .failed(RIFXAudioDecoding.trimUnavailable))
    }

    private func writeWave(
        tag: Int, bits: Int, frames: Int, bigEndian: Bool = true,
        sample: (Int) -> Double
    ) throws -> URL {
        let alignment = 2 * bits / 8
        var data = Data()
        func append(_ value: UInt64, bytes: Int) {
            for byte in 0..<bytes {
                let shift = (bigEndian ? bytes - 1 - byte : byte) * 8
                data.append(UInt8(truncatingIfNeeded: value >> shift))
            }
        }
        data.append(contentsOf: (bigEndian ? "RIFX" : "RIFF").utf8)
        append(UInt64(36 + frames * alignment), bytes: 4)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(16, bytes: 4)
        append(UInt64(tag), bytes: 2)
        append(2, bytes: 2)
        append(48_000, bytes: 4)
        append(UInt64(48_000 * alignment), bytes: 4)
        append(UInt64(alignment), bytes: 2)
        append(UInt64(bits), bytes: 2)
        data.append(contentsOf: "data".utf8)
        append(UInt64(frames * alignment), bytes: 4)
        for frame in 0..<frames {
            let value = sample(frame)
            let encoded: UInt64
            if tag == 3 {
                encoded = bits == 32 ? UInt64(Float(value).bitPattern) : value.bitPattern
            } else if bits == 8 {
                encoded = UInt64(128 + Int(value * 128))
            } else {
                encoded = UInt64(bitPattern: Int64((value * pow(2, Double(bits - 1))).rounded()))
            }
            for _ in 0..<2 { append(encoded, bytes: bits / 8) }
        }
        // Deliberately avoid a WAVE extension: detection must follow the bytes.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rifx-decode-\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }
}
