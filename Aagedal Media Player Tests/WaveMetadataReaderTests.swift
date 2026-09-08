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

    func testBundledFFmpegRF64ReachesMetadataService() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wave-rf64-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "anullsrc=r=48000:cl=7.1", "-t", "0.1",
            "-c:a", "pcm_f32le", "-rf64", "always", "-n", url.path
        ])
        let metadata = try await MetadataService.shared.metadata(for: url)
        XCTAssertEqual(metadata.duration ?? -1, 0.1, accuracy: 0.00001)
        XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_f32le")
        XCTAssertEqual(metadata.audioStreams.first?.channelLayout, "7.1")
    }

    func testRF64AndBW64FormatsAndSampleCountSemantics() throws {
        for container in ["RF64", "BW64"] {
            for (tag, bits) in [(1, 16), (3, 64), (0xfffe, 32)] {
                let fmt = format(tag: tag, channels: 8, bits: bits, mask: 0x63f)
                let audio = Data(count: 8 * bits / 8 * 10)
                let metadata = try XCTUnwrap(read(extendedWave(container: container, format: fmt,
                                                              audio: audio, samples: 10)))
                XCTAssertEqual(metadata.duration ?? -1, 10.0 / 48_000, accuracy: 0.0000001)
                XCTAssertEqual(metadata.audioStreams.first?.channels, 8)
                XCTAssertEqual(metadata.audioStreams.first?.channelLayout, tag == 0xfffe ? "7.1" : nil)
            }
        }
        let fmt = format(tag: 1, channels: 2, bits: 16)
        // RF64 zero is unspecified; BW64 reserves these eight bytes and readers ignore them.
        XCTAssertNotNil(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 0)))
        XCTAssertNotNil(try read(extendedWave(container: "BW64", format: fmt, audio: Data(count: 40), samples: .max)))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 9)))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 39), samples: 0)))
    }

    func testExtendedChunkTableResolvesRepeatedIDsAndPadding() throws {
        let before = extendedChunk("JUNK", Data([1, 2, 3]))
            + chunk("JUNK", Data([4, 5])) + extendedChunk("JUNK", Data([6]))
        let data = extendedWave(format: format(tag: 1, channels: 2, bits: 16), audio: Data(count: 40),
                                samples: 10, before: before, table: [("JUNK", 3), ("JUNK", 1)])
        XCTAssertEqual(try read(data)?.audioStreams.first?.codec, "pcm_s16le")
        XCTAssertThrowsError(try read(extendedWave(format: format(tag: 1, channels: 2, bits: 16),
                                                 audio: Data(count: 40), samples: 10, before: before,
                                                 table: [("JUNK", 3)])))
    }

    func testRF64FactSampleCountUsesSentinelPrecedence() throws {
        let fmt = format(tag: 1, channels: 2, bits: 16)
        // A normal fact count is authoritative, even when ds64's unused value disagrees.
        XCTAssertNotNil(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 9,
                                              before: chunk("fact", little(UInt32(10))))))
        XCTAssertNotNil(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                              before: chunk("fact", little(UInt32.max)))))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                                 before: chunk("fact", little(UInt32(9))))))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 9,
                                                 before: chunk("fact", little(UInt32.max)))))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                                 before: chunk("fact", Data(count: 3)))))
        let duplicateFacts = chunk("fact", little(UInt32(10))) + chunk("fact", little(UInt32(10)))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                                 before: duplicateFacts)))
    }

    func testExtendedContainerHonorsOrdinary32BitLengths() throws {
        var data = extendedWave(format: format(tag: 1, channels: 2, bits: 16), audio: Data(count: 40), samples: 10)
        data.replaceSubrange(4..<8, with: little(UInt32(data.count - 8)))
        data.replaceSubrange(20..<28, with: little(UInt64.max))
        data.replaceSubrange(28..<36, with: little(UInt64.max))
        let audioLengthOffset = data.count - 44
        data.replaceSubrange(audioLengthOffset..<(audioLengthOffset + 4), with: little(UInt32(40)))
        XCTAssertNotNil(try read(data))
    }

    func testMalformedDS64HeadersAreRejected() throws {
        let fmt = format(tag: 1, channels: 2, bits: 16)
        let good = extendedWave(format: fmt, audio: Data(count: 40), samples: 10)
        for (range, replacement): (Range<Int>, Data) in [
            (12..<16, Data("JUNK".utf8)), // Mandatory first chunk is missing.
            (16..<20, little(UInt32(27))),
            (16..<20, little(UInt32.max)),
            (20..<28, little(UInt64.max)), // Overflowing or out-of-file RIFF length.
            (20..<28, little(UInt64(20))), // ds64 exceeds declared container bounds.
            (28..<36, little(UInt64.max)), // Out-of-file data length.
            (44..<48, little(UInt32.max)) // Table does not fit ds64.
        ] {
            var malformed = good
            malformed.replaceSubrange(range, with: replacement)
            XCTAssertThrowsError(try read(malformed))
        }
        XCTAssertThrowsError(try read(good.dropLast()))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                                 before: chunk("ds64", Data(count: 28)))))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                                 before: extendedChunk("data", Data(count: 40)))))
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10,
                                                 before: extendedChunk("JUNK", Data()), table: [("JUNK", .max)])))
        let table = Array(repeating: ("JUNK", UInt64(0)), count: 4_097)
        XCTAssertThrowsError(try read(extendedWave(format: fmt, audio: Data(count: 40), samples: 10, table: table))) {
            guard case WaveMetadataReader.ReadError.unsupportedFormat = $0 else {
                return XCTFail("Oversized ds64 table should report unsupported format: \($0)")
            }
        }
    }

    func testSparseRF64AndBW64AudioBeyondFourGiBIsSkipped() throws {
        let audioSize: UInt64 = 1 << 33
        for container in ["RF64", "BW64"] {
            let fmt = chunk("fmt ", format(tag: 0xfffe, channels: 8, bits: 32, mask: 0x63f))
            let riffSize = UInt64(4 + 36 + fmt.count + 8) + audioSize
            let ds64 = little(riffSize) + little(audioSize) + little(audioSize / 32) + little(UInt32(0))
            let header = Data(container.utf8) + little(UInt32.max) + Data("WAVE".utf8)
                + chunk("ds64", ds64) + fmt + Data("data".utf8) + little(UInt32.max)
            let url = try write(header)
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try FileHandle(forWritingTo: url)
            try file.truncate(atOffset: riffSize + 8)
            try file.close()
            let metadata = try XCTUnwrap(WaveMetadataReader.read(from: url))
            XCTAssertEqual(metadata.sizeBytes, Int64(riffSize + 8))
            XCTAssertEqual(metadata.duration ?? -1, Double(audioSize / 32) / 48_000, accuracy: 0.00001)
            XCTAssertEqual(metadata.audioStreams.first?.channelLayout, "7.1")
        }
    }

    func testSparseExtendedAncillaryChunkBeyondFourGiBIsSkipped() throws {
        let ancillarySize: UInt64 = (1 << 32) + 1
        let audio = chunk("fmt ", format(tag: 1, channels: 2, bits: 16)) + extendedChunk("data", Data(count: 40))
        let riffSize = UInt64(4 + 48 + 8 + audio.count) + ancillarySize + 1
        var ds64 = little(riffSize) + little(UInt64(40)) + little(UInt64(10)) + little(UInt32(1))
        ds64 += Data("JUNK".utf8) + little(ancillarySize)
        let header = Data("RF64".utf8) + little(UInt32.max) + Data("WAVE".utf8)
            + chunk("ds64", ds64) + Data("JUNK".utf8) + little(UInt32.max)
        let url = try write(header)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.seek(toOffset: UInt64(header.count) + ancillarySize + 1)
        try file.write(contentsOf: audio)
        try file.close()
        XCTAssertEqual(try WaveMetadataReader.read(from: url)?.duration ?? -1, 10.0 / 48_000, accuracy: 0.0000001)
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

    private func extendedWave(container: String = "RF64", format: Data, audio: Data, samples: UInt64,
                              before: Data = Data(), table: [(String, UInt64)] = []) -> Data {
        let body = before + chunk("fmt ", format) + extendedChunk("data", audio)
        let riffSize = UInt64(4 + 8 + 28 + table.count * 12 + body.count)
        var ds64 = little(riffSize) + little(UInt64(audio.count)) + little(samples) + little(UInt32(table.count))
        for (name, size) in table { ds64 += Data(name.utf8) + little(size) }
        return Data(container.utf8) + little(UInt32.max) + Data("WAVE".utf8) + chunk("ds64", ds64) + body
    }

    private func extendedChunk(_ name: String, _ payload: Data) -> Data {
        Data(name.utf8) + little(UInt32.max) + payload + Data(count: payload.count % 2)
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
