// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// SwiftMediaMetadata's video entry point does not read standalone WAVE.
/// Its separate audio parser copies data chunks and guesses surround layouts
/// from channel count; neither is suitable for long recordings or the explicit
/// speaker placement required by the loudness correction.
/// Read only RIFF/RIFX/RF64/BW64 headers here, seeking over audio and ancillary chunks so
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
              String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        let container = String(decoding: header[0..<4], as: UTF8.self)
        guard ["RIFF", "RIFX", "RF64", "BW64"].contains(container) else { return nil }
        guard size <= UInt64(Int64.max) else { throw ReadError.invalidWave }
        let byteOrder: ByteOrder = container == "RIFX" ? .big : .little
        let size32 = uint32(header, 4, byteOrder: byteOrder)
        var end = UInt64(size32) + 8
        var position: UInt64 = 12
        var sizes64: ExtendedSizes?
        if container == "RF64" || container == "BW64" {
            // The mandatory ds64 is first, and its own length is always 32-bit.
            guard size >= 20 else { throw ReadError.invalidWave }
            let chunk = try readExactly(file, count: 8)
            let count = UInt64(uint32(chunk, 4))
            guard String(decoding: chunk[0..<4], as: UTF8.self) == "ds64",
                  count >= 28, count != UInt64(UInt32.max), count <= size - 20 else {
                throw ReadError.invalidWave
            }
            let fixed = try readExactly(file, count: 28)
            let riffSize = uint64(fixed, 0)
            if size32 == UInt32.max {
                guard riffSize <= size - 8 else { throw ReadError.invalidWave }
                end = riffSize + 8
            }
            guard end >= 20, end <= size, count <= end - 20,
                  count & 1 <= end - 20 - count else { throw ReadError.invalidWave }
            let entries = UInt64(uint32(fixed, 24))
            guard entries <= (count - 28) / 12 else { throw ReadError.invalidWave }
            // Bound header allocation even for hostile ds64 table lengths.
            guard entries <= 4_096 else { throw ReadError.unsupportedFormat }
            var table: [UInt32: [UInt64]] = [:]
            for _ in 0..<entries {
                try Task.checkCancellation()
                let entry = try readExactly(file, count: 12)
                table[uint32(entry, 0), default: []].append(uint64(entry, 4))
            }
            // Repeated IDs are resolved in occurrence order with constant-time pops.
            for key in Array(table.keys) { table[key]?.reverse() }
            sizes64 = ExtendedSizes(data: uint64(fixed, 8),
                                    samples: container == "RF64" ? uint64(fixed, 16) : 0,
                                    table: table)
            position = 20 + count + (count & 1)
        }
        guard end >= 12, end <= size else { throw ReadError.invalidWave }

        var format: Data?
        var formatSize: UInt64 = 0
        var audioBytes: UInt64?
        var factSamples: UInt32?
        var broadcastWave: MediaMetadata.BroadcastWave?
        var ixmlRecording: MediaMetadata.IXMLRecording?
        var sawIXML = false
        while position < end {
            try Task.checkCancellation()
            guard end - position >= 8 else { throw ReadError.invalidWave }
            try file.seek(toOffset: position)
            let chunk = try readExactly(file, count: 8)
            let name = String(decoding: chunk[0..<4], as: UTF8.self)
            let count32 = uint32(chunk, 4, byteOrder: byteOrder)
            var count = UInt64(count32)
            if count32 == UInt32.max, sizes64 != nil {
                if name == "data" {
                    count = sizes64!.data
                } else {
                    guard let extended = sizes64!.table[uint32(chunk, 0)]?.popLast() else {
                        throw ReadError.invalidWave
                    }
                    count = extended
                }
            }
            let payload = position + 8
            guard count <= end - payload,
                  count & 1 <= end - payload - count else { throw ReadError.invalidWave }
            if name == "ds64", sizes64 != nil { throw ReadError.invalidWave }
            if name == "fmt " {
                guard format == nil, count >= 16 else { throw ReadError.invalidWave }
                // Only the base and extensible format headers are needed.
                format = try readExactly(file, count: Int(min(count, 40)))
                formatSize = count
            } else if name == "data" {
                guard audioBytes == nil else { throw ReadError.invalidWave }
                audioBytes = count
            } else if name == "fact", container == "RF64" {
                guard factSamples == nil, count >= 4 else { throw ReadError.invalidWave }
                factSamples = uint32(try readExactly(file, count: 4), 0)
            } else if name == "bext", byteOrder == .little {
                // BWF defines little-endian RIFF fields; RIFX tags are skipped
                // until a producer-backed variant establishes their encoding.
                guard broadcastWave == nil, count >= 602 else { throw ReadError.invalidWave }
                // The remaining coding history can be arbitrarily large. Keep a
                // bounded prefix and seek past the rest with the enclosing loop.
                let bytes = try readExactly(file, count: Int(min(count, 602 + 16_384)))
                broadcastWave = readBroadcastWave(bytes, chunkSize: count)
            } else if name == "iXML", byteOrder == .little {
                // Parse at most one bounded payload. Duplicate optional chunks
                // are ambiguous, so omit their tags while retaining audio/BWF.
                if !sawIXML, count > 0, count <= 262_144 {
                    ixmlRecording = readIXML(try readExactly(file, count: Int(count)))
                    try Task.checkCancellation()
                } else {
                    ixmlRecording = nil
                }
                sawIXML = true
            }
            position = payload + count + (count & 1)
            guard position <= end else { throw ReadError.invalidWave }
        }
        guard let format, let audioBytes else { throw ReadError.invalidWave }
        var tag = uint16(format, 0, byteOrder: byteOrder)
        let channels = Int(uint16(format, 2, byteOrder: byteOrder))
        let sampleRate = Int(uint32(format, 4, byteOrder: byteOrder))
        let byteRate = UInt64(uint32(format, 8, byteOrder: byteOrder))
        let alignment = UInt64(uint16(format, 12, byteOrder: byteOrder))
        let bits = Int(uint16(format, 14, byteOrder: byteOrder))
        var validBits = bits
        var mask: UInt32?
        if tag == 0xfffe {
            // Extensible RIFX GUID/extension ordering is not established here.
            guard byteOrder == .little else { throw ReadError.unsupportedFormat }
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
        let sampleFrames = audioBytes / alignment
        // RF64 replaces fact's sample count only when its 32-bit value is a
        // sentinel. Some writers omit fact and provide the count only in ds64.
        let declaredSamples: UInt64?
        if let factSamples, factSamples != UInt32.max {
            declaredSamples = UInt64(factSamples)
        } else {
            declaredSamples = sizes64?.samples
        }
        if let samples = declaredSamples, samples != 0, samples != sampleFrames {
            throw ReadError.invalidWave
        }
        let suffix = byteOrder == .big ? "be" : "le"
        let endianness = byteOrder == .big ? "big-endian" : "little-endian"
        let codec = tag == 3 ? "pcm_f\(bits)\(suffix)" : (bits == 8 ? "pcm_u8" : "pcm_s\(bits)\(suffix)")
        let stream = MediaMetadata.AudioStream(
            index: 0, languageCode: nil, title: nil, codec: codec,
            codecLongName: "PCM \(tag == 3 ? "floating-point" : "integer") \(bits)-bit \(endianness)",
            profile: nil, sampleRate: sampleRate, channels: channels,
            channelLayout: channelLayout(mask: mask, channels: channels),
            bitDepth: validBits, bitRate: Int64(byteRate * 8), isDefault: true
        )
        return MediaMetadata(
            duration: Double(sampleFrames) / Double(sampleRate),
            formatName: "wav", containerLongName: "WAV / WAVE (Waveform Audio)",
            sizeBytes: Int64(size), bitRate: Int64(byteRate * 8), timecode: nil,
            comment: nil, encoder: nil, frameCount: nil,
            videoStreams: [], audioStreams: [stream], subtitleStreams: [], chapters: [],
            broadcastWave: broadcastWave, ixmlRecording: ixmlRecording
        )
    }

    private static func readIXML(_ bytes: Data) -> MediaMetadata.IXMLRecording? {
        // Restrict this implementation to UTF-8. Refuse declarations before
        // XMLParser sees them, preventing both external access and expansion
        // of internal entities. Even declarations inside comments are omitted.
        guard !bytes.contains(0), var text = String(data: bytes, encoding: .utf8),
              !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else { return nil }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        if text.hasPrefix("<?xml"), let end = text.range(of: "?>") {
            let declaration = String(text[..<end.lowerBound])
            if declaration.contains("encoding"),
               declaration.range(of: #"\bencoding\s*=\s*(?:"UTF-8"|'UTF-8')"#,
                                 options: [.regularExpression, .caseInsensitive]) == nil {
                return nil
            }
        }
        let delegate = IXMLDelegate()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), parser.parserError == nil, !delegate.invalid else { return nil }
        let fields = delegate.fields
        let circled: Bool? = fields["CIRCLED"] == "TRUE" ? true : (fields["CIRCLED"] == "FALSE" ? false : nil)
        guard fields.keys.contains(where: { $0 != "CIRCLED" }) || circled != nil else { return nil }
        return MediaMetadata.IXMLRecording(
            version: fields["IXML_VERSION"], project: fields["PROJECT"], scene: fields["SCENE"],
            take: fields["TAKE"], tape: fields["TAPE"], note: fields["NOTE"],
            circled: circled, fileUID: fields["FILE_UID"]
        )
    }

    private nonisolated final class IXMLDelegate: NSObject, XMLParserDelegate {
        private static let recognized: Set<String> = [
            "IXML_VERSION", "PROJECT", "SCENE", "TAKE", "TAPE", "NOTE", "CIRCLED", "FILE_UID"
        ]
        private(set) var fields: [String: String] = [:]
        private(set) var invalid = false
        private var depth = 0
        private var elements = 0
        private var seenFields: Set<String> = []
        private var field: String?
        private var value = ""
        private var valueBytes = 0
        private var invalidField = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            depth += 1
            elements += 1
            guard !Task.isCancelled, depth <= 16, elements <= 4_096 else { return reject(parser) }
            if depth == 1 {
                guard elementName == "BWFXML", namespaceURI?.isEmpty != false else { return reject(parser) }
            } else if depth == 2, namespaceURI?.isEmpty != false, Self.recognized.contains(elementName) {
                guard seenFields.insert(elementName).inserted else { return reject(parser) }
                field = elementName
                value = ""
                valueBytes = 0
                invalidField = false
            } else if depth > 2, field != nil {
                // Recording labels are scalar text. Do not flatten markup or
                // harvest same-named tags from SPEED, BEXT or vendor objects.
                invalidField = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            append(string, parser: parser)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let string = String(data: CDATABlock, encoding: .utf8) else { return reject(parser) }
            append(string, parser: parser)
        }

        private func append(_ string: String, parser: XMLParser) {
            guard !Task.isCancelled else { return reject(parser) }
            guard depth == 2, let field, !invalidField else { return }
            let count = string.utf8.count
            let limit = field == "NOTE" ? 16_384 : 4_096
            guard count <= limit - valueBytes else {
                invalidField = true
                value = ""
                return
            }
            valueBytes += count
            value += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if depth == 2, let field {
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !invalidField, !text.isEmpty,
                   text.unicodeScalars.allSatisfy({
                       !CharacterSet.controlCharacters.contains($0) || [9, 10, 13].contains($0.value)
                   }) {
                    fields[field] = text
                }
                self.field = nil
                value = ""
            }
            depth -= 1
        }

        func parser(_ parser: XMLParser, resolveExternalEntityName name: String,
                    systemID: String?) -> Data? {
            reject(parser)
            return nil
        }

        private func reject(_ parser: XMLParser) {
            invalid = true
            parser.abortParsing()
        }
    }

    private static func readBroadcastWave(_ bytes: Data, chunkSize: UInt64) -> MediaMetadata.BroadcastWave {
        let version = uint16(bytes, 346)
        // EBU Tech 3285 v2: older versions reserve the UMID/loudness bytes.
        // Future versions retain only the common fixed fields here.
        let hasUMID = version == 1 || version == 2
        let umidBytes = bytes[348..<412]
        let umid = hasUMID && umidBytes.contains(where: { $0 != 0 })
            ? umidBytes.map { String(format: "%02X", $0) }.joined() : nil
        func loudness(_ offset: Int, isRange: Bool = false) -> Double? {
            guard version == 2 else { return nil }
            let value = Int16(bitPattern: uint16(bytes, offset))
            // Includes 0x7fff (unspecified) and all out-of-range values.
            guard value >= (isRange ? 0 : -9_999), value <= 9_999 else { return nil }
            return Double(value) / 100
        }
        return MediaMetadata.BroadcastWave(
            version: version,
            description: ascii(bytes, 0..<256),
            originator: ascii(bytes, 256..<288),
            originatorReference: ascii(bytes, 288..<320),
            originationDate: ascii(bytes, 320..<330),
            originationTime: ascii(bytes, 330..<338),
            timeReferenceSamples: uint64(bytes, 338), umid: umid,
            integratedLoudness: loudness(412), loudnessRange: loudness(414, isRange: true),
            maxTruePeakLevel: loudness(416), maxMomentaryLoudness: loudness(418),
            maxShortTermLoudness: loudness(420),
            codingHistory: version <= 2 ? ascii(bytes, 602..<bytes.count, multiline: true) : nil,
            codingHistoryTruncated: version <= 2 && chunkSize > UInt64(bytes.count)
        )
    }

    private static func ascii(_ bytes: Data, _ range: Range<Int>, multiline: Bool = false) -> String? {
        let value = bytes[range].prefix(while: { $0 != 0 })
        // Do not guess encodings or display embedded control characters. A bad
        // optional field does not discard the recording's technical metadata.
        guard value.allSatisfy({ (32...126).contains($0) || (multiline && [9, 10, 13].contains($0)) }),
              let text = String(data: Data(value), encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private struct ExtendedSizes {
        let data: UInt64
        // BW64 reserves this field; zero RF64 counts are treated as unspecified.
        let samples: UInt64
        var table: [UInt32: [UInt64]]
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

    private enum ByteOrder { case little, big }

    private static func uint16(_ data: Data, _ offset: Int, byteOrder: ByteOrder = .little) -> UInt16 {
        if byteOrder == .big {
            return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int, byteOrder: ByteOrder = .little) -> UInt32 {
        if byteOrder == .big {
            return UInt32(uint16(data, offset, byteOrder: .big)) << 16
                | UInt32(uint16(data, offset + 2, byteOrder: .big))
        }
        return UInt32(uint16(data, offset)) | UInt32(uint16(data, offset + 2)) << 16
    }

    private static func uint64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(uint32(data, offset)) | UInt64(uint32(data, offset + 4)) << 32
    }
}
