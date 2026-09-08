// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// SwiftMediaMetadata's video entry point does not read standalone WAVE.
/// Its separate audio parser copies data chunks and guesses surround layouts
/// from channel count; neither is suitable for long recordings or the explicit
/// speaker placement required by the loudness correction.
/// Read only RIFF headers here, seeking over audio and ancillary chunks so
/// metadata memory use is independent of the recording's duration.
nonisolated enum WaveMetadataReader {
    enum ReadError: Error, LocalizedError {
        case invalidWave
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .invalidWave: "The WAVE file has invalid or incomplete headers."
            case .unsupportedFormat: "This WAVE encoding is not supported by the metadata reader."
            }
        }
    }

    static func read(from url: URL) throws -> MediaMetadata? {
        guard url.isFileURL else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        try file.seek(toOffset: 0)
        let header = try file.read(upToCount: 12) ?? Data()
        guard header.count == 12,
              String(decoding: header[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        let end = UInt64(uint32(header, 4)) + 8
        guard end >= 12, end <= size else { throw ReadError.invalidWave }

        var position: UInt64 = 12
        var format: Data?
        var formatSize: UInt64 = 0
        var audioBytes: UInt64?
        while position < end {
            try Task.checkCancellation()
            guard end - position >= 8 else { throw ReadError.invalidWave }
            try file.seek(toOffset: position)
            let chunk = try readExactly(file, count: 8)
            let name = String(decoding: chunk[0..<4], as: UTF8.self)
            let count = UInt64(uint32(chunk, 4))
            let payload = position + 8
            guard count <= end - payload else { throw ReadError.invalidWave }
            if name == "fmt " {
                guard format == nil, count >= 16 else { throw ReadError.invalidWave }
                // Only the base and extensible format headers are needed.
                format = try readExactly(file, count: Int(min(count, 40)))
                formatSize = count
            } else if name == "data" {
                guard audioBytes == nil else { throw ReadError.invalidWave }
                audioBytes = count
            }
            position = payload + count + (count & 1)
            guard position <= end else { throw ReadError.invalidWave }
        }
        guard let format, let audioBytes else { throw ReadError.invalidWave }
        var tag = uint16(format, 0)
        let channels = Int(uint16(format, 2))
        let sampleRate = Int(uint32(format, 4))
        let byteRate = UInt64(uint32(format, 8))
        let alignment = UInt64(uint16(format, 12))
        let bits = Int(uint16(format, 14))
        var validBits = bits
        var mask: UInt32?
        if tag == 0xfffe {
            guard format.count >= 40, uint16(format, 16) >= 22,
                  UInt64(uint16(format, 16)) <= formatSize - 18 else { throw ReadError.invalidWave }
            validBits = Int(uint16(format, 18))
            if validBits == 0 { validBits = bits }
            mask = uint32(format, 20)
            // KSDATAFORMAT_SUBTYPE_PCM / IEEE_FLOAT, including the full GUID.
            guard Array(format[26..<40]) == [0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71] else {
                throw ReadError.unsupportedFormat
            }
            tag = uint16(format, 24)
        }
        guard tag == 1 || tag == 3 else { throw ReadError.unsupportedFormat }
        guard channels > 0, sampleRate > 0,
              [8, 16, 24, 32, 64].contains(bits), validBits > 0, validBits <= bits,
              alignment == UInt64(channels * (bits / 8)),
              byteRate == UInt64(sampleRate) * alignment,
              audioBytes % alignment == 0 else { throw ReadError.invalidWave }
        if tag == 3 && (bits != 32 && bits != 64 || validBits != bits) {
            throw ReadError.unsupportedFormat
        }
        let codec = tag == 3 ? "pcm_f\(bits)le" : (bits == 8 ? "pcm_u8" : "pcm_s\(bits)le")
        let stream = MediaMetadata.AudioStream(
            index: 0, languageCode: nil, title: nil, codec: codec,
            codecLongName: "PCM \(tag == 3 ? "floating-point" : "integer") \(bits)-bit little-endian",
            profile: nil, sampleRate: sampleRate, channels: channels,
            channelLayout: channelLayout(mask: mask, channels: channels),
            bitDepth: validBits, bitRate: Int64(byteRate * 8), isDefault: true
        )
        return MediaMetadata(
            duration: Double(audioBytes / alignment) / Double(sampleRate),
            formatName: "wav", containerLongName: "WAV / WAVE (Waveform Audio)",
            sizeBytes: Int64(size), bitRate: Int64(byteRate * 8), timecode: nil,
            comment: nil, encoder: nil, frameCount: nil,
            videoStreams: [], audioStreams: [stream], subtitleStreams: [], chapters: []
        )
    }

    private static func channelLayout(mask: UInt32?, channels: Int) -> String? {
        // Never infer surround placement from channel count. In particular,
        // the BS.1770 rear correction needs explicit conventional 7.1.
        guard let mask, mask != 0 else {
            return channels == 1 ? "mono" : (channels == 2 ? "stereo" : nil)
        }
        guard mask.nonzeroBitCount == channels else { return nil }
        switch mask {
        case 0x4: return "mono"
        case 0x3: return "stereo"
        case 0x3f: return "5.1"
        case 0x60f: return "5.1(side)"
        case 0x63f: return "7.1"
        default: return nil
        }
    }

    private static func readExactly(_ file: FileHandle, count: Int) throws -> Data {
        let data = try file.read(upToCount: count) ?? Data()
        guard data.count == count else { throw ReadError.invalidWave }
        return data
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(uint16(data, offset)) | UInt32(uint16(data, offset + 2)) << 16
    }
}
