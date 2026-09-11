// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Select WAVE from its container signature: FFmpeg can mistake some valid
/// periodic float PCM payloads for MPEG-TS during format probing. For RIFX,
/// also correct its little-endian decoder selection after format validation.
/// Neither override is inferred from the filename extension.
nonisolated enum RIFXAudioDecoding {
    static let playbackUnavailable = "Playback of big-endian RIFX WAVE is not supported yet. Convert the file to little-endian WAVE with a converter that supports RIFX. Metadata, waveforms, and loudness analysis remain available."
    static let trimUnavailable = "Trim export of big-endian RIFX WAVE is not supported yet. Convert the file to little-endian WAVE with a converter that supports RIFX, then trim the converted file."

    static func isRIFX(_ url: URL) throws -> Bool {
        try waveSignature(url) == "RIFX"
    }

    private static func waveSignature(_ url: URL) throws -> String? {
        guard url.isFileURL else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 12) ?? Data()
        guard header.count == 12, header.suffix(4) == Data("WAVE".utf8),
              let signature = String(data: header.prefix(4), encoding: .ascii),
              ["RIFF", "RIFX", "RF64", "BW64"].contains(signature) else { return nil }
        return signature
    }

    static func ffmpegInputArguments(for url: URL) throws -> [String] {
        guard let signature = try waveSignature(url) else { return [] }
        guard signature == "RIFX" else { return ["-f", "wav"] }
        guard let metadata = try WaveMetadataReader.read(from: url),
              let codec = metadata.audioStreams.first?.codec,
              ["pcm_u8", "pcm_s16be", "pcm_s24be", "pcm_s32be", "pcm_s64be",
               "pcm_f32be", "pcm_f64be"].contains(codec) else {
            throw WaveMetadataReader.ReadError.unsupportedFormat
        }
        return ["-f", "wav", "-c:a", codec]
    }
}
