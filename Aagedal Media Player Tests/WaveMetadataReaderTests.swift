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

    func testRIFXClassicPCMAndFloatReadBigEndianFields() throws {
        for (tag, bits, codec) in [(1, 8, "pcm_u8"), (1, 16, "pcm_s16be"),
                                    (1, 24, "pcm_s24be"), (1, 32, "pcm_s32be"),
                                    (1, 64, "pcm_s64be"), (3, 32, "pcm_f32be"), (3, 64, "pcm_f64be")] {
            let data = wave(format: format(tag: tag, channels: 2, bits: bits, bigEndian: true),
                            audio: Data(count: 2 * bits / 8 * 10),
                            before: chunk("JUNK", Data([1, 2, 3]), bigEndian: true), bigEndian: true)
            let metadata = try XCTUnwrap(read(data))
            let audio = try XCTUnwrap(metadata.audioStreams.first)
            XCTAssertEqual(audio.codec, codec)
            XCTAssertEqual(audio.codecLongName, "PCM \(tag == 3 ? "floating-point" : "integer") \(bits)-bit big-endian")
            XCTAssertEqual(audio.channels, 2)
            XCTAssertEqual(audio.channelLayout, "stereo")
            XCTAssertEqual(audio.sampleRate, 48_000)
            XCTAssertEqual(audio.bitDepth, bits)
            XCTAssertEqual(audio.bitRate, Int64(48_000 * 2 * bits))
            XCTAssertEqual(metadata.duration ?? -1, 10.0 / 48_000, accuracy: 0.0000001)
            XCTAssertEqual(metadata.sizeBytes, Int64(data.count))
        }
    }

    func testRIFXReachesMetadataServiceWithoutInventingSurroundLayout() async throws {
        let url = try write(wave(format: format(tag: 3, channels: 8, bits: 32, bigEndian: true),
                                 audio: Data(count: 320), bigEndian: true))
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MetadataService.shared.metadata(for: url)
        XCTAssertEqual(metadata.formatName, "wav")
        XCTAssertEqual(metadata.duration ?? -1, 10.0 / 48_000, accuracy: 0.0000001)
        XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_f32be")
        XCTAssertEqual(metadata.audioStreams.first?.channels, 8)
        XCTAssertNil(metadata.audioStreams.first?.channelLayout)
    }

    func testRIFXDataBeforeFormatAndOddAudioPadding() throws {
        let body = Data("WAVE".utf8) + chunk("data", Data([128, 128, 128]), bigEndian: true)
            + chunk("fmt ", format(tag: 1, channels: 1, bits: 8, bigEndian: true), bigEndian: true)
        let metadata = try XCTUnwrap(read(Data("RIFX".utf8) + big(UInt32(body.count)) + body))
        XCTAssertEqual(metadata.audioStreams.first?.channelLayout, "mono")
        XCTAssertEqual(metadata.duration ?? -1, 3.0 / 48_000, accuracy: 0.0000001)
        let missingPad = wave(format: format(tag: 1, channels: 1, bits: 8, bigEndian: true),
                              audio: Data([128]), bigEndian: true).dropLast()
        var malformed = Data(missingPad)
        malformed.replaceSubrange(4..<8, with: big(UInt32(malformed.count - 8)))
        XCTAssertThrowsError(try read(malformed))
    }

    func testRIFXRejectsMalformedAndMixedEndianHeaders() throws {
        let fmt = format(tag: 1, channels: 2, bits: 16, bigEndian: true)
        let good = wave(format: fmt, audio: Data(count: 40), bigEndian: true)
        for (range, replacement): (Range<Int>, Data) in [
            (4..<8, little(UInt32(good.count - 8))),
            (4..<8, big(UInt32.max)),
            (16..<20, little(UInt32(16))),
            (16..<20, big(UInt32.max)),
            (20..<22, little(UInt16(1))),
            (22..<24, big(UInt16(0))),
            (24..<28, big(UInt32(0))),
            (28..<32, big(UInt32(1))),
            (32..<34, big(UInt16(0))),
            (34..<36, big(UInt16(12)))
        ] {
            var malformed = good
            malformed.replaceSubrange(range, with: replacement)
            XCTAssertThrowsError(try read(malformed))
        }
        XCTAssertThrowsError(try read(good.dropLast()))
        XCTAssertThrowsError(try read(wave(format: fmt, audio: Data(count: 39), bigEndian: true)))
        XCTAssertThrowsError(try read(wave(format: Data(count: 12), audio: Data(), bigEndian: true)))
        for duplicate in [chunk("fmt ", fmt, bigEndian: true), chunk("data", Data(count: 40), bigEndian: true)] {
            XCTAssertThrowsError(try read(wave(format: fmt, audio: Data(count: 40), before: duplicate, bigEndian: true)))
        }
    }

    func testRIFXRejectsCompressedAndExtensibleFormatsAndSkipsUnspecifiedTags() throws {
        for tag in [6, 7, 0xfffe] {
            XCTAssertThrowsError(try read(wave(format: format(tag: tag, channels: 2, bits: 32, bigEndian: true),
                                               audio: Data(count: 40), bigEndian: true))) {
                guard case WaveMetadataReader.ReadError.unsupportedFormat = $0 else {
                    return XCTFail("Unsupported RIFX encoding should be explicit: \($0)")
                }
            }
        }
        // BWF is defined for little-endian RIFF; do not misreport tag byte order.
        let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16, bigEndian: true),
            audio: Data(count: 40), before: chunk("bext", bext(), bigEndian: true), bigEndian: true)))
        XCTAssertNil(metadata.broadcastWave)
        XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16be")
    }

    func testSparseRIFXAudioIsSkippedBeforeFollowingChunk() throws {
        let audioSize: UInt32 = 1 << 30
        let fmt = chunk("fmt ", format(tag: 3, channels: 8, bits: 32, bigEndian: true), bigEndian: true)
        let tail = chunk("JUNK", Data([1, 2, 3]), bigEndian: true)
        let header = Data("RIFX".utf8) + big(UInt32(4 + fmt.count + 8 + tail.count) + audioSize)
            + Data("WAVE".utf8) + fmt + Data("data".utf8) + big(audioSize)
        let url = try write(header)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.seek(toOffset: UInt64(header.count) + UInt64(audioSize))
        try file.write(contentsOf: tail)
        try file.close()
        let metadata = try XCTUnwrap(WaveMetadataReader.read(from: url))
        XCTAssertEqual(metadata.sizeBytes, Int64(header.count + tail.count) + Int64(audioSize))
        XCTAssertEqual(metadata.duration ?? -1, Double(audioSize) / (48_000 * 32), accuracy: 0.00001)
        XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_f32be")
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

    func testBroadcastWaveFieldsAndVersionTwoLoudness() throws {
        let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                                              audio: Data(count: 40), before: chunk("bext", bext()))))
        let bwf = try XCTUnwrap(metadata.broadcastWave)
        XCTAssertEqual(bwf.version, 2)
        XCTAssertEqual(bwf.description, "Field recording")
        XCTAssertEqual(bwf.originator, "Recorder")
        XCTAssertEqual(bwf.originatorReference, "take-42")
        XCTAssertEqual(bwf.originationDate, "2026-09-08")
        XCTAssertEqual(bwf.originationTime, "12:34:56")
        XCTAssertEqual(bwf.timeReferenceSamples, 0x1234_5678_9abc_def0)
        XCTAssertEqual(bwf.umid, "01" + String(repeating: "00", count: 63))
        XCTAssertEqual(bwf.integratedLoudness, -23.45)
        XCTAssertEqual(bwf.loudnessRange, 4.56)
        XCTAssertEqual(bwf.maxTruePeakLevel, -1.23)
        XCTAssertEqual(bwf.maxMomentaryLoudness, -20)
        XCTAssertEqual(bwf.maxShortTermLoudness, -21)
        XCTAssertEqual(bwf.codingHistory, "A=PCM,F=48000,W=16,M=stereo")
        XCTAssertFalse(bwf.codingHistoryTruncated)
        XCTAssertNil(metadata.timecode) // A sample reference is not a video-frame timecode.
    }

    func testBroadcastWaveVersionGatesReservedFields() throws {
        for version: UInt16 in [0, 1, 2, 3, .max] {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                audio: Data(count: 40), before: chunk("bext", bext(version: version)))))
            let bwf = try XCTUnwrap(metadata.broadcastWave)
            XCTAssertEqual(bwf.description, "Field recording")
            XCTAssertEqual(bwf.umid != nil, version == 1 || version == 2)
            XCTAssertEqual(bwf.integratedLoudness != nil, version == 2)
            XCTAssertEqual(bwf.codingHistory != nil, version <= 2)
        }
    }

    func testBroadcastWaveIgnoresInvalidAndUnspecifiedLoudness() throws {
        for values: [Int16] in [[.max, .max, .max, .max, .max], [-10_000, -1, 10_000, .min, .max]] {
            var bytes = bext()
            for (index, value) in values.enumerated() {
                bytes.replaceSubrange((412 + index * 2)..<(414 + index * 2), with: little(value))
            }
            let bwf = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                audio: Data(count: 40), before: chunk("bext", bytes)))?.broadcastWave)
            XCTAssertNil(bwf.integratedLoudness)
            XCTAssertNil(bwf.loudnessRange)
            XCTAssertNil(bwf.maxTruePeakLevel)
            XCTAssertNil(bwf.maxMomentaryLoudness)
            XCTAssertNil(bwf.maxShortTermLoudness)
        }
    }

    func testBroadcastWaveTextBoundsNullTerminationAndEmptyValues() throws {
        var bytes = bext(history: "line one\r\nline two\r\n")
        bytes.replaceSubrange(0..<256, with: Data(repeating: 65, count: 256))
        bytes.replaceSubrange(256..<288, with: Data(count: 32))
        bytes[288] = 255 // Invalid ASCII omits only this field.
        bytes[320] = 1 // Control characters must not reach the inspector.
        bytes.replaceSubrange(338..<346, with: little(UInt64.max))
        bytes.replaceSubrange(348..<412, with: Data(count: 64))
        let bwf = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
            audio: Data(count: 40), before: chunk("bext", bytes)))?.broadcastWave)
        XCTAssertEqual(bwf.description, String(repeating: "A", count: 256))
        XCTAssertNil(bwf.originator)
        XCTAssertNil(bwf.originatorReference)
        XCTAssertNil(bwf.originationDate)
        XCTAssertEqual(bwf.timeReferenceSamples, UInt64.max)
        XCTAssertNil(bwf.umid)
        XCTAssertEqual(bwf.codingHistory, "line one\r\nline two")
    }

    func testBroadcastWaveRejectsShortAndDuplicateChunks() throws {
        let fmt = format(tag: 1, channels: 2, bits: 16)
        XCTAssertThrowsError(try read(wave(format: fmt, audio: Data(count: 40), before: chunk("bext", Data(count: 601)))))
        XCTAssertThrowsError(try read(wave(format: fmt, audio: Data(count: 40),
            before: chunk("bext", bext()) + chunk("bext", bext()))))
    }

    func testBroadcastWaveExtendedLengthsAndChunkAfterAudio() throws {
        let fmt = format(tag: 1, channels: 2, bits: 16)
        let bytes = bext()
        for container in ["RF64", "BW64"] {
            let metadata = try read(extendedWave(container: container, format: fmt, audio: Data(count: 40),
                samples: 10, before: extendedChunk("bext", bytes), table: [("bext", UInt64(bytes.count))]))
            XCTAssertEqual(metadata?.broadcastWave?.originator, "Recorder")
        }
        let body = Data("WAVE".utf8) + chunk("fmt ", fmt) + chunk("data", Data(count: 40)) + chunk("bext", bytes)
        XCTAssertEqual(try read(Data("RIFF".utf8) + little(UInt32(body.count)) + body)?.broadcastWave?.originator, "Recorder")
    }

    func testSparseBroadcastWaveHistoryIsBounded() throws {
        let historySize: UInt32 = 1 << 30
        let prefix = bext(history: "") + Data(repeating: 65, count: 16_384)
        let tail = chunk("fmt ", format(tag: 1, channels: 2, bits: 16)) + chunk("data", Data(count: 40))
        let chunkSize = UInt32(602) + historySize
        let riffSize = UInt32(4 + 8 + tail.count) + chunkSize
        let header = Data("RIFF".utf8) + little(riffSize) + Data("WAVEbext".utf8) + little(chunkSize)
        let url = try write(header + prefix)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.seek(toOffset: UInt64(header.count) + UInt64(chunkSize))
        try file.write(contentsOf: tail)
        try file.close()
        let metadata = try XCTUnwrap(WaveMetadataReader.read(from: url))
        XCTAssertEqual(metadata.broadcastWave?.codingHistory?.count, 16_384)
        XCTAssertEqual(metadata.broadcastWave?.codingHistoryTruncated, true)
        XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
    }

    func testBroadcastWaveCodableAndInspectorJSONPreserveExactReference() throws {
        let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
            audio: Data(count: 40), before: chunk("bext", bext()))))
        let encoded = try JSONEncoder().encode(metadata)
        XCTAssertEqual(try JSONDecoder().decode(MediaMetadata.self, from: encoded), metadata)
        let exported = try MetadataInspectorView.metadataJSON(metadata: metadata, lufsResults: [:])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let bwf = try XCTUnwrap(json["broadcastWave"] as? [String: Any])
        XCTAssertEqual((bwf["timeReferenceSamples"] as? NSNumber)?.uint64Value, 0x1234_5678_9abc_def0)
        XCTAssertEqual(bwf["integratedLoudness"] as? Double, -23.45)
        var withoutBWF = metadata
        withoutBWF.broadcastWave = nil
        let oldJSON = try JSONEncoder().encode(withoutBWF)
        XCTAssertNil(try JSONDecoder().decode(MediaMetadata.self, from: oldJSON).broadcastWave)
    }

    func testIXMLRecordingTagsPreserveUnicodeEscapesAndBWF() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <BWFXML><IXML_VERSION>2.0</IXML_VERSION><PROJECT> Fjell &amp; sjø </PROJECT>
        <SCENE>021A</SCENE><TAKE>0003</TAKE><TAPE>Roll 7</TAPE>
        <NOTE><![CDATA[First line <quiet>]]>&#10;Second line</NOTE><CIRCLED>TRUE</CIRCLED>
        <FILE_UID>recorder-0003</FILE_UID></BWFXML>
        """
        let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
            audio: Data(count: 40), before: chunk("iXML", Data(xml.utf8)) + chunk("bext", bext()))))
        let recording = try XCTUnwrap(metadata.ixmlRecording)
        XCTAssertEqual(recording.version, "2.0")
        XCTAssertEqual(recording.project, "Fjell & sjø")
        XCTAssertEqual(recording.scene, "021A")
        XCTAssertEqual(recording.take, "0003")
        XCTAssertEqual(recording.tape, "Roll 7")
        XCTAssertEqual(recording.note, "First line <quiet>\nSecond line")
        XCTAssertEqual(recording.circled, true)
        XCTAssertEqual(recording.fileUID, "recorder-0003")
        XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
        XCTAssertEqual(metadata.broadcastWave?.timeReferenceSamples, 0x1234_5678_9abc_def0)
        XCTAssertNil(metadata.timecode)
        XCTAssertNil(metadata.comment)
    }

    func testIXMLReachesMetadataServiceAndInspectorJSON() async throws {
        let url = try write(wave(format: format(tag: 1, channels: 2, bits: 16), audio: Data(count: 40),
            before: chunk("iXML", Data("<BWFXML><SCENE>007</SCENE><CIRCLED>FALSE</CIRCLED></BWFXML>".utf8))))
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MetadataService.shared.metadata(for: url)
        XCTAssertEqual(metadata.ixmlRecording?.scene, "007")
        XCTAssertEqual(try JSONDecoder().decode(MediaMetadata.self, from: JSONEncoder().encode(metadata)), metadata)
        let exported = try MetadataInspectorView.metadataJSON(metadata: metadata, lufsResults: [:])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let tags = try XCTUnwrap(json["ixmlRecording"] as? [String: Any])
        XCTAssertEqual(tags["scene"] as? String, "007")
        XCTAssertEqual(tags["circled"] as? Bool, false)
        XCTAssertNil(json["broadcastWave"])
        var olderMetadata = metadata
        olderMetadata.ixmlRecording = nil
        XCTAssertNil(try JSONDecoder().decode(MediaMetadata.self, from: JSONEncoder().encode(olderMetadata)).ixmlRecording)
    }

    func testIXMLReadsExtendedLengthsAndChunkAfterAudio() throws {
        let fmt = format(tag: 1, channels: 2, bits: 16)
        let xml = Data("\u{FEFF}<?xml version='1.0' encoding='utf-8'?><BWFXML><TAKE>001</TAKE></BWFXML> ".utf8)
        for container in ["RF64", "BW64"] {
            let metadata = try read(extendedWave(container: container, format: fmt, audio: Data(count: 40),
                samples: 10, before: extendedChunk("iXML", xml), table: [("iXML", UInt64(xml.count))]))
            XCTAssertEqual(metadata?.ixmlRecording?.take, "001", container)
        }
        let body = Data("WAVE".utf8) + chunk("fmt ", fmt) + chunk("data", Data(count: 40)) + chunk("iXML", xml)
        XCTAssertEqual(try read(Data("RIFF".utf8) + little(UInt32(body.count)) + body)?.ixmlRecording?.take, "001")
    }

    func testIXMLUTF16BOMPreservesUnicodeCDATAAndByteOrder() throws {
        let body = "<BWFXML><PROJECT>Fjell &amp; sjø 🎙</PROJECT><TAKE>0003</TAKE>"
            + "<NOTE><![CDATA[声 <quiet> 🎬]]>&#10;Next line</NOTE><CIRCLED>TRUE</CIRCLED></BWFXML> \r\n"
        for bigEndian in [false, true] {
            for declaration in ["", "<?xml version='1.0'?>", "<?xml version='1.0' encoding='uTf-16'?>",
                                "<?xml version='1.0' encoding='UTF-16\(bigEndian ? "BE" : "LE")'?>"] {
                let xml = utf16XML(declaration + body, bigEndian: bigEndian)
                let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                    audio: Data(count: 40), before: chunk("iXML", xml) + chunk("bext", bext()))))
                XCTAssertEqual(metadata.ixmlRecording?.project, "Fjell & sjø 🎙", declaration)
                XCTAssertEqual(metadata.ixmlRecording?.take, "0003", declaration)
                XCTAssertEqual(metadata.ixmlRecording?.note, "声 <quiet> 🎬\nNext line", declaration)
                XCTAssertEqual(metadata.ixmlRecording?.circled, true, declaration)
                XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
                XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
            }
        }
    }

    func testIXMLUTF16ExplicitByteOrderWithoutBOMInExtendedContainers() throws {
        for bigEndian in [false, true] {
            let declaration = "<?xml version = \"1.0\"\r\nencoding = 'utf-16\(bigEndian ? "be" : "le")' standalone='yes'?>"
            let xml = utf16XML(declaration + "<BWFXML><SCENE>007</SCENE><NOTE><![CDATA[冬 🎬]]></NOTE></BWFXML>",
                               bigEndian: bigEndian, bom: false)
            for container in ["RF64", "BW64"] {
                let metadata = try read(extendedWave(container: container, format: format(tag: 1, channels: 2, bits: 16),
                    audio: Data(count: 40), samples: 10, before: extendedChunk("iXML", xml),
                    table: [("iXML", UInt64(xml.count))]))
                XCTAssertEqual(metadata?.ixmlRecording?.scene, "007", container)
                XCTAssertEqual(metadata?.ixmlRecording?.note, "冬 🎬", container)
                XCTAssertEqual(metadata?.audioStreams.first?.sampleRate, 48_000)
            }
        }
    }

    func testIXMLRejectsConflictingOrMissingUTF16EncodingDeclarations() throws {
        let body = "<BWFXML><PROJECT>Project</PROJECT></BWFXML>"
        var invalidXML = [Data("<?xml version='1.0' encoding='UTF-16'?>\(body)".utf8)]
        for bigEndian in [false, true] {
            let matchingName = "UTF-16\(bigEndian ? "BE" : "LE")"
            let oppositeName = "UTF-16\(bigEndian ? "LE" : "BE")"
            for bom in [false, true] {
                for declaration in ["<?xml version='1.0' encoding='UTF-8'?>",
                                    "<?xml version='1.0' encoding='\(oppositeName)'?>",
                                    "<?xml version='1.0' encoding='ISO-10646-UCS-2'?>",
                                    "<?xml version='1.0' encoding='\(matchingName)' encoding='UTF-8'?>",
                                    "<?xml version='1.0' ENCODING='\(matchingName)'?>",
                                    "<?xml version='1.0' encoding='\(matchingName)\"?>"] {
                    invalidXML.append(utf16XML(declaration + body, bigEndian: bigEndian, bom: bom))
                }
            }
            for declaration in ["", "<?xml version='1.0'?>", "<?xml version='1.0' encoding='UTF-16'?>"] {
                invalidXML.append(utf16XML(declaration + body, bigEndian: bigEndian, bom: false))
            }
        }
        for xml in invalidXML {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                audio: Data(count: 40), before: chunk("iXML", xml) + chunk("bext", bext()))))
            XCTAssertNil(metadata.ixmlRecording)
            XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
            XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
        }
    }

    func testIXMLRejectsMalformedUTF16AndUnsupportedUTF32() throws {
        let body = "<BWFXML><PROJECT>Project</PROJECT></BWFXML>"
        var invalidXML = [Data([0xff, 0xfe]), Data([0xfe, 0xff]), Data([0xef, 0xbb, 0xbf])]
        for bigEndian in [false, true] {
            let prefix = utf16XML("<BWFXML><PROJECT>", bigEndian: bigEndian)
            let suffix = utf16XML("</PROJECT></BWFXML>", bigEndian: bigEndian, bom: false)
            invalidXML += [
                utf16XML(body, bigEndian: bigEndian) + Data([32]), // Never drop an odd final byte.
                utf16XML(body + "\0", bigEndian: bigEndian),
                utf16XML("<BWFXML><PROJECT>before\0after</PROJECT></BWFXML>", bigEndian: bigEndian),
                prefix + (bigEndian ? big(UInt16(0xd800)) : little(UInt16(0xd800))) + suffix,
                prefix + (bigEndian ? big(UInt16(0xdc00)) : little(UInt16(0xdc00))) + suffix,
                Data(bigEndian ? [0xfe, 0xff] : [0xff, 0xfe]) + utf16XML(body, bigEndian: !bigEndian, bom: false)
            ]
            let utf32 = body.data(using: bigEndian ? .utf32BigEndian : .utf32LittleEndian)!
            invalidXML += [utf32, Data(bigEndian ? [0, 0, 0xfe, 0xff] : [0xff, 0xfe, 0, 0]) + utf32]
        }
        for xml in invalidXML {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                audio: Data(count: 40), before: chunk("iXML", xml) + chunk("bext", bext()))))
            XCTAssertNil(metadata.ixmlRecording)
            XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
            XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
        }
    }

    func testIXMLUTF16CannotHideDTDOrEntityDeclarations() throws {
        let documents = [
            "<!DOCTYPE BWFXML [<!ENTITY a 'expanded'>]><BWFXML><PROJECT>&a;</PROJECT></BWFXML>",
            "<!DOCTYPE BWFXML SYSTEM 'https://example.invalid/ixml.dtd'><BWFXML><PROJECT>Project</PROJECT></BWFXML>",
            "<!DOCTYPE BWFXML [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><BWFXML><NOTE>&a;</NOTE></BWFXML>",
            "<BWFXML><!-- <!DOCTYPE hidden> --><PROJECT>Project</PROJECT></BWFXML>",
            "<BWFXML><NOTE><![CDATA[<!ENTITY hidden>]]></NOTE><PROJECT>Project</PROJECT></BWFXML>"
        ]
        for bigEndian in [false, true] {
            for document in documents {
                let xml = utf16XML(document, bigEndian: bigEndian)
                let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                    audio: Data(count: 40), before: chunk("iXML", xml) + chunk("bext", bext()))))
                XCTAssertNil(metadata.ixmlRecording, document)
                XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
                XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
            }
        }
    }

    func testIXMLUTF16FieldLimitsCountDecodedUTF8Bytes() throws {
        for bigEndian in [false, true] {
            for excess in [0, 1] {
                let project = String(repeating: "界", count: 1_365) + String(repeating: "A", count: 1 + excess)
                let note = String(repeating: "🎬", count: 4_096) + String(repeating: "A", count: excess)
                let xml = utf16XML("<BWFXML><PROJECT>\(project)</PROJECT><NOTE><![CDATA[\(note)]]></NOTE><TAKE>005</TAKE></BWFXML>",
                                   bigEndian: bigEndian)
                let tags = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16), audio: Data(count: 40),
                    before: chunk("iXML", xml)))?.ixmlRecording)
                XCTAssertEqual(tags.project, excess == 0 ? project : nil)
                XCTAssertEqual(tags.note, excess == 0 ? note : nil)
                XCTAssertEqual(tags.take, "005")
            }
        }
    }

    func testIXMLIgnoresNestedUnknownAndNamespacedFields() throws {
        let xml = """
        <BWFXML xmlns:vendor="urn:vendor"><PROJECT>Location</PROJECT><vendor:TAKE>wrong</vendor:TAKE>
        <SPEED><NOTE>speed note</NOTE><FILE_SAMPLE_RATE>1</FILE_SAMPLE_RATE><TIMECODE_RATE>25/1</TIMECODE_RATE></SPEED>
        <BEXT><BWF_DESCRIPTION>not bext</BWF_DESCRIPTION><BWF_TIME_REFERENCE_LOW>42</BWF_TIME_REFERENCE_LOW></BEXT>
        <TRACK_LIST><TRACK><NAME>Left</NAME><FUNCTION>LEFT</FUNCTION></TRACK></TRACK_LIST>
        <SCENE>mixed <EM>markup</EM></SCENE><NOTE>  </NOTE><FILE_UID>bad&#x7F;control</FILE_UID></BWFXML>
        """
        let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 8, bits: 16),
            audio: Data(count: 160), before: chunk("iXML", Data(xml.utf8)))))
        XCTAssertEqual(metadata.ixmlRecording?.project, "Location")
        XCTAssertNil(metadata.ixmlRecording?.take)
        XCTAssertNil(metadata.ixmlRecording?.scene)
        XCTAssertNil(metadata.ixmlRecording?.note)
        XCTAssertNil(metadata.ixmlRecording?.fileUID)
        XCTAssertNil(metadata.broadcastWave)
        XCTAssertNil(metadata.timecode)
        XCTAssertNil(metadata.audioStreams.first?.channelLayout)
        XCTAssertEqual(metadata.audioStreams.first?.sampleRate, 48_000)
    }

    func testIXMLRequiresExplicitCircledBoolean() throws {
        for value in ["TRUE", "FALSE", "true", "false", "1", "", "yes"] {
            let xml = "<BWFXML><PROJECT>Project</PROJECT><CIRCLED>\(value)</CIRCLED></BWFXML>"
            let tags = try read(wave(format: format(tag: 1, channels: 2, bits: 16), audio: Data(count: 40),
                before: chunk("iXML", Data(xml.utf8))))?.ixmlRecording
            XCTAssertEqual(tags?.circled, value == "TRUE" ? true : (value == "FALSE" ? false : nil), value)
        }
    }

    func testIXMLRejectsMalformedOrUnsafeDocumentsWithoutDiscardingAudioOrBWF() throws {
        let invalidXML = [
            "", "<BWFXML><PROJECT>unfinished", "<OTHER><PROJECT>Wrong root</PROJECT></OTHER>",
            "<BWFXML xmlns='urn:other'><PROJECT>Wrong namespace</PROJECT></BWFXML>",
            "<BWFXML><TAKE>1</TAKE><TAKE>2</TAKE></BWFXML>",
            "<BWFXML><PROJECT>One</PROJECT></BWFXML><BWFXML/>",
            "<BWFXML><PROJECT>before\0after</PROJECT></BWFXML>",
            "<?xml version='1.0' encoding='ISO-8859-1'?><BWFXML><PROJECT>Æ</PROJECT></BWFXML>",
            "<!DOCTYPE BWFXML [<!ENTITY a 'expanded'>]><BWFXML><PROJECT>&a;</PROJECT></BWFXML>",
            "<!DOCTYPE BWFXML SYSTEM 'https://example.invalid/ixml.dtd'><BWFXML><PROJECT>External DTD</PROJECT></BWFXML>",
            "<!DOCTYPE BWFXML [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><BWFXML><NOTE>&a;</NOTE></BWFXML>",
            "<!DOCTYPE BWFXML [<!ENTITY a 'x'><!ENTITY b '&a;&a;'><!ENTITY c '&b;&b;'>]><BWFXML><NOTE>&c;</NOTE></BWFXML>",
            "<BWFXML><PROJECT>&undefined;</PROJECT></BWFXML>"
        ].map { Data($0.utf8) } + [
            Data("<BWFXML><PROJECT>".utf8) + Data([0xff]) + Data("</PROJECT></BWFXML>".utf8)
        ]
        for xml in invalidXML {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                audio: Data(count: 40), before: chunk("iXML", xml) + chunk("bext", bext()))))
            XCTAssertNil(metadata.ixmlRecording, String(decoding: xml.prefix(100), as: UTF8.self))
            XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
            XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
        }
    }

    func testIXMLDuplicateChunksAreOmittedEvenWhenFirstInvalid() throws {
        let valid = chunk("iXML", Data("<BWFXML><PROJECT>Project</PROJECT></BWFXML>".utf8))
        let invalid = chunk("iXML", Data("invalid".utf8))
        for before in [valid + valid, invalid + valid, valid + invalid] {
            let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                audio: Data(count: 40), before: before)))
            XCTAssertNil(metadata.ixmlRecording)
            XCTAssertEqual(metadata.audioStreams.first?.sampleRate, 48_000)
        }
    }

    func testIXMLFieldSizeBoundsOmitWholeFieldsWithoutTruncation() throws {
        for excess in [0, 1] {
            let project = String(repeating: "ø", count: 2_048) + String(repeating: "A", count: excess)
            let note = String(repeating: "N", count: 16_384 + excess)
            let xml = "<BWFXML><PROJECT>\(project)</PROJECT><NOTE>\(note)</NOTE><TAKE>005</TAKE></BWFXML>"
            let tags = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16), audio: Data(count: 40),
                before: chunk("iXML", Data(xml.utf8))))?.ixmlRecording)
            XCTAssertEqual(tags.project, excess == 0 ? project : nil)
            XCTAssertEqual(tags.note, excess == 0 ? note : nil)
            XCTAssertEqual(tags.take, "005")
        }
    }

    func testIXMLDepthAndElementBounds() throws {
        for excess in [0, 1] {
            let nesting = String(repeating: "<V>", count: 15 + excess) + String(repeating: "</V>", count: 15 + excess)
            let elements = String(repeating: "<V/>", count: 4_094 + excess)
            for children in [nesting, elements] {
                let xml = "<BWFXML><PROJECT>Project</PROJECT>\(children)</BWFXML>"
                for payload in [Data(xml.utf8), utf16XML(xml), utf16XML(xml, bigEndian: true)] {
                    let metadata = try XCTUnwrap(read(wave(format: format(tag: 1, channels: 2, bits: 16),
                        audio: Data(count: 40), before: chunk("iXML", payload))))
                    XCTAssertEqual(metadata.ixmlRecording?.project, excess == 0 ? "Project" : nil)
                    XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
                }
            }
        }
    }

    func testIXMLPayloadCapAndSparseOversizedChunk() throws {
        let xml = Data("<BWFXML><PROJECT>Project</PROJECT></BWFXML>".utf8)
        let fmt = format(tag: 1, channels: 2, bits: 16)
        for count in [262_144, 262_145] {
            let payload = xml + Data(repeating: 32, count: count - xml.count)
            XCTAssertEqual(try read(wave(format: fmt, audio: Data(count: 40), before: chunk("iXML", payload)))?
                .ixmlRecording?.project, count == 262_144 ? "Project" : nil)
        }
        for bigEndian in [false, true] {
            let prefix = utf16XML("<BWFXML><PROJECT>Project</PROJECT></BWFXML>", bigEndian: bigEndian)
            for count in [262_144, 262_146] {
                let padding = String(repeating: " ", count: (count - prefix.count) / 2)
                let payload = prefix + utf16XML(padding, bigEndian: bigEndian, bom: false)
                XCTAssertEqual(payload.count, count)
                XCTAssertEqual(try read(wave(format: fmt, audio: Data(count: 40), before: chunk("iXML", payload)))?
                    .ixmlRecording?.project, count == 262_144 ? "Project" : nil)
            }
        }
        let chunkSize: UInt32 = 1 << 30
        let tail = chunk("bext", bext()) + chunk("fmt ", fmt) + chunk("data", Data(count: 40))
        let riffSize = UInt32(4 + 8 + tail.count) + chunkSize
        let header = Data("RIFF".utf8) + little(riffSize) + Data("WAVEiXML".utf8) + little(chunkSize)
        let url = try write(header + xml)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.seek(toOffset: UInt64(header.count) + UInt64(chunkSize))
        try file.write(contentsOf: tail)
        try file.close()
        let metadata = try XCTUnwrap(WaveMetadataReader.read(from: url))
        XCTAssertNil(metadata.ixmlRecording)
        XCTAssertEqual(metadata.broadcastWave?.description, "Field recording")
        XCTAssertEqual(metadata.audioStreams.first?.codec, "pcm_s16le")
    }

    func testIXMLRIFXTagsAreSkippedAndChunkBoundsStillValidated() throws {
        let xml = Data("<BWFXML><PROJECT>Project</PROJECT></BWFXML>".utf8)
        let data = wave(format: format(tag: 1, channels: 2, bits: 16, bigEndian: true), audio: Data(count: 40),
            before: chunk("iXML", xml, bigEndian: true), bigEndian: true)
        XCTAssertNil(try read(data)?.ixmlRecording)
        var invalid = data
        invalid.replaceSubrange(16..<20, with: big(UInt32.max))
        XCTAssertThrowsError(try read(invalid))
    }

    private func utf16XML(_ text: String, bigEndian: Bool = false, bom: Bool = true) -> Data {
        let prefix = bom ? Data(bigEndian ? [0xfe, 0xff] : [0xff, 0xfe]) : Data()
        return prefix + text.data(using: bigEndian ? .utf16BigEndian : .utf16LittleEndian)!
    }

    private func bext(version: UInt16 = 2, history: String = "A=PCM,F=48000,W=16,M=stereo\r\n") -> Data {
        var bytes = Data(count: 602)
        for (offset, value) in [(0, "Field recording"), (256, "Recorder"), (288, "take-42"),
                                (320, "2026-09-08"), (330, "12:34:56")] {
            let data = Data(value.utf8)
            bytes.replaceSubrange(offset..<(offset + data.count), with: data)
        }
        bytes.replaceSubrange(338..<346, with: little(UInt64(0x1234_5678_9abc_def0)))
        bytes.replaceSubrange(346..<348, with: little(version))
        bytes[348] = 1
        for (index, value): (Int, Int16) in [-2345, 456, -123, -2000, -2100].enumerated() {
            bytes.replaceSubrange((412 + index * 2)..<(414 + index * 2), with: little(value))
        }
        return bytes + Data(history.utf8)
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

    private func wave(format: Data, audio: Data, before: Data = Data(), bigEndian: Bool = false) -> Data {
        let body = Data("WAVE".utf8) + before + chunk("fmt ", format, bigEndian: bigEndian)
            + chunk("data", audio, bigEndian: bigEndian)
        return Data((bigEndian ? "RIFX" : "RIFF").utf8)
            + (bigEndian ? big(UInt32(body.count)) : little(UInt32(body.count))) + body
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

    private func chunk(_ name: String, _ payload: Data, bigEndian: Bool = false) -> Data {
        Data(name.utf8) + (bigEndian ? big(UInt32(payload.count)) : little(UInt32(payload.count)))
            + payload + Data(count: payload.count % 2)
    }

    private func format(tag: Int, channels: Int, bits: Int, mask: UInt32 = 0, bigEndian: Bool = false) -> Data {
        let alignment = channels * bits / 8
        var data = little(UInt16(tag)) + little(UInt16(channels)) + little(UInt32(48_000))
        data += little(UInt32(48_000 * alignment)) + little(UInt16(alignment)) + little(UInt16(bits))
        if tag == 0xfffe {
            data += little(UInt16(22)) + little(UInt16(bits)) + little(mask)
            data += Data([3, 0, 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71])
        }
        if bigEndian {
            for range in [0..<2, 2..<4, 4..<8, 8..<12, 12..<14, 14..<16] {
                data.replaceSubrange(range, with: Array(data[range].reversed()))
            }
        }
        return data
    }

    private func big<T: FixedWidthInteger>(_ number: T) -> Data {
        var value = number.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private func little<T: FixedWidthInteger>(_ number: T) -> Data {
        var value = number.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
