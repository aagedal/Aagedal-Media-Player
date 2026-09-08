// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class WaveMetadataReaderTests: XCTestCase {
    func testBundledFFmpegFloat71WaveMetadata() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wave-ffmpeg-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "aevalsrc=0|0|0|0|0.1*sin(2*PI*1000*t)|0|0|0:s=48000:d=2:c=7.1",
            "-c:a", "pcm_f32le", "-n", url.path
        ])
        let metadata = try await MetadataService.shared.metadata(for: url)
        XCTAssertEqual(metadata.duration ?? -1, 2, accuracy: 0.00001)
        let stream = try XCTUnwrap(metadata.audioStreams.first)
        XCTAssertEqual(stream.channelLayout, "7.1")
        XCTAssertEqual(stream.codec, "pcm_f32le")
        XCTAssertEqual(stream.channels, 8)
        let measurement = try await FFmpegService.analyzeLUFS(
            url: url, audioStreamIndex: 0, channels: stream.channels, channelLayout: stream.channelLayout
        )
        XCTAssertEqual(measurement.weightingCorrection, .bs1770Conventional7Point1RearChannels)
        XCTAssertEqual(measurement.integratedLoudness, -23, accuracy: 0.1)
        XCTAssertEqual(measurement.truePeak, -20, accuracy: 0.1)
    }

    func testExtensibleFloat71ReachesMetadataService() async throws {
        let url = try write(wave(format: format(tag: 0xfffe, channels: 8, bits: 32, mask: 0x63f), audio: Data(count: 320)))
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MetadataService.shared.metadata(for: url)
        let audio = try XCTUnwrap(metadata.audioStreams.first)
        XCTAssertEqual(metadata.formatName, "wav")
        XCTAssertEqual(metadata.duration ?? -1, 10.0 / 48_000, accuracy: 0.0000001)
        XCTAssertEqual(audio.index, 0)
        XCTAssertEqual(audio.codec, "pcm_f32le")
        XCTAssertEqual(audio.channels, 8)
        XCTAssertEqual(audio.sampleRate, 48_000)
        XCTAssertEqual(audio.bitDepth, 32)
        XCTAssertEqual(audio.bitRate, 12_288_000)
        XCTAssertEqual(audio.channelLayout, "7.1")
        XCTAssertTrue(metadata.videoStreams.isEmpty)
    }

    func testClassicPCMAndFloatAndOddAncillaryChunk() throws {
        for (tag, bits, codec) in [(1, 16, "pcm_s16le"), (1, 8, "pcm_u8"), (3, 32, "pcm_f32le")] {
            let data = wave(format: format(tag: tag, channels: 2, bits: bits), audio: Data(count: 32),
                            before: chunk("JUNK", Data([1, 2, 3])))
            let metadata = try XCTUnwrap(read(data))
            XCTAssertEqual(metadata.audioStreams.first?.codec, codec)
            XCTAssertEqual(metadata.audioStreams.first?.channelLayout, "stereo")
        }
    }

    func testUnknownOrMismatchedSurroundMaskDoesNotInvent71() throws {
        for mask: UInt32 in [0, 0x3f, 0xff] {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 0xfffe, channels: 8, bits: 32, mask: mask), audio: Data(count: 32))))
            XCTAssertNil(metadata.audioStreams.first?.channelLayout)
        }
        let classic = try XCTUnwrap(read(wave(format: format(tag: 3, channels: 8, bits: 32), audio: Data(count: 32))))
        XCTAssertNil(classic.audioStreams.first?.channelLayout)
    }

    func testExplicitSideAndRear51MasksRemainDistinct() throws {
        for (mask, layout): (UInt32, String) in [(0x3f, "5.1"), (0x60f, "5.1(side)")] {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 0xfffe, channels: 6, bits: 32, mask: mask), audio: Data(count: 24))))
            XCTAssertEqual(metadata.audioStreams.first?.channelLayout, layout)
        }
    }

    func testMalformedSizesFormatsAndIncompleteFramesAreRejected() throws {
        let goodFormat = format(tag: 0xfffe, channels: 8, bits: 32, mask: 0x63f)
        let good = wave(format: goodFormat, audio: Data(count: 32))
        XCTAssertThrowsError(try read(good.dropLast()))
        XCTAssertThrowsError(try read(wave(format: goodFormat, audio: Data(count: 31))))
        XCTAssertThrowsError(try read(wave(format: Data(count: 12), audio: Data())))
        var badGUID = goodFormat
        badGUID[39] = 0
        XCTAssertThrowsError(try read(wave(format: badGUID, audio: Data(count: 32))))
        var badRate = goodFormat
        badRate[8] = 1
        XCTAssertThrowsError(try read(wave(format: badRate, audio: Data(count: 32))))
        var badAlignment = goodFormat
        badAlignment[12] = 0
        XCTAssertThrowsError(try read(wave(format: badAlignment, audio: Data(count: 32))))
        var badExtension = goodFormat
        badExtension[16] = 255
        XCTAssertThrowsError(try read(wave(format: badExtension, audio: Data(count: 32))))
        var oversizedChunk = good
        oversizedChunk.replaceSubrange(16..<20, with: little(UInt32.max))
        XCTAssertThrowsError(try read(oversizedChunk))
        XCTAssertThrowsError(try read(wave(format: goodFormat, audio: Data(count: 32), before: chunk("fmt ", goodFormat))))
    }

    func testDataBeforeFormatAndNonWaveInput() throws {
        let body = Data("WAVE".utf8) + chunk("data", Data(count: 32)) + chunk("fmt ", format(tag: 3, channels: 2, bits: 32))
        XCTAssertNotNil(try read(Data("RIFF".utf8) + little(UInt32(body.count)) + body))
        XCTAssertNil(try read(Data("unrelated file contents".utf8)))
    }

    func testLargeSparseAudioChunkIsSkipped() throws {
        let audioSize: UInt32 = 1 << 30
        let fmt = chunk("fmt ", format(tag: 3, channels: 8, bits: 32))
        let header = Data("RIFF".utf8) + little(UInt32(4 + fmt.count + 8) + audioSize)
            + Data("WAVE".utf8) + fmt + Data("data".utf8) + little(audioSize)
        let url = try write(header)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(header.count) + UInt64(audioSize))
        try file.close()
        let metadata = try XCTUnwrap(WaveMetadataReader.read(from: url))
        XCTAssertEqual(metadata.sizeBytes, Int64(header.count) + Int64(audioSize))
        XCTAssertEqual(metadata.duration ?? -1, Double(audioSize) / (48_000 * 32), accuracy: 0.00001)
    }

    private func read(_ data: Data) throws -> MediaMetadata? {
        let url = try write(data)
        defer { try? FileManager.default.removeItem(at: url) }
        return try WaveMetadataReader.read(from: url)
    }

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wave-metadata-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    private func wave(format: Data, audio: Data, before: Data = Data()) -> Data {
        let body = Data("WAVE".utf8) + before + chunk("fmt ", format) + chunk("data", audio)
        return Data("RIFF".utf8) + little(UInt32(body.count)) + body
    }

    private func chunk(_ name: String, _ payload: Data) -> Data {
        Data(name.utf8) + little(UInt32(payload.count)) + payload + Data(count: payload.count % 2)
    }

    private func format(tag: Int, channels: Int, bits: Int, mask: UInt32 = 0) -> Data {
        let alignment = channels * bits / 8
        var data = little(UInt16(tag)) + little(UInt16(channels)) + little(UInt32(48_000))
        data += little(UInt32(48_000 * alignment)) + little(UInt16(alignment)) + little(UInt16(bits))
        if tag == 0xfffe {
            data += little(UInt16(22)) + little(UInt16(bits)) + little(mask)
            data += Data([3, 0, 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71])
        }
        return data
    }

    private func little<T: FixedWidthInteger>(_ number: T) -> Data {
        var value = number.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
