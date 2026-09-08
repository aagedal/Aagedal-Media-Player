// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// FFmpeg's WAVE demuxer reads RIFX headers in big endian, but assigns the
/// corresponding little-endian PCM decoder. Choose the decoder only after
/// validating the actual container and sample format, never from an extension.
nonisolated enum RIFXAudioDecoding {
    static let playbackUnavailable = "Playback of big-endian RIFX WAVE is not supported yet. Convert the file to little-endian WAVE with a converter that supports RIFX. Metadata, waveforms, and loudness analysis remain available."
    static let trimUnavailable = "Trim export of big-endian RIFX WAVE is not supported yet. Convert the file to little-endian WAVE with a converter that supports RIFX, then trim the converted file."

    static func isRIFX(_ url: URL) throws -> Bool {
        guard url.isFileURL else { return false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 12) ?? Data()
        return header.count == 12
            && header.prefix(4) == Data("RIFX".utf8)
            && header.suffix(4) == Data("WAVE".utf8)
    }

    static func ffmpegInputArguments(for url: URL) throws -> [String] {
        guard try isRIFX(url) else { return [] }
        guard let metadata = try WaveMetadataReader.read(from: url),
              let codec = metadata.audioStreams.first?.codec,
              ["pcm_u8", "pcm_s16be", "pcm_s24be", "pcm_s32be", "pcm_s64be",
               "pcm_f32be", "pcm_f64be"].contains(codec) else {
            throw WaveMetadataReader.ReadError.unsupportedFormat
        }
        return ["-c:a", codec]
    }
}
