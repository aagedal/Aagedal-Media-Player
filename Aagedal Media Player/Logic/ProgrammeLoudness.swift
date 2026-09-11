// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum ProgrammeLoudnessLayout: String, CaseIterable, Codable, Sendable {
    case stereo
    case surround5Point1

    nonisolated var displayName: String {
        switch self {
        case .stereo: "Stereo"
        case .surround5Point1: "5.1"
        }
    }

    nonisolated var channelRoles: [String] {
        switch self {
        case .stereo: ["FL", "FR"]
        case .surround5Point1: ["FL", "FR", "FC", "LFE", "SL", "SR"]
        }
    }

    nonisolated var ffmpegLayout: String {
        switch self {
        case .stereo: "stereo"
        case .surround5Point1: "5.1(side)"
        }
    }
}

enum ProgrammeLoudnessError: Error, LocalizedError, Equatable {
    case incompleteMapping
    case duplicateStream
    case invalidStream
    case monoRequired
    case durationRequired
    case sampleRateRequired

    nonisolated var errorDescription: String? {
        switch self {
        case .incompleteMapping: "Assign one mono track to every programme channel."
        case .duplicateStream: "Assign a different mono track to each programme channel."
        case .invalidStream: "One of the selected audio tracks is no longer available."
        case .monoRequired: "Programme mapping requires tracks with a known mono channel count."
        case .durationRequired: "Programme analysis requires a known, finite file duration."
        case .sampleRateRequired: "Programme analysis requires a known sample rate for every selected track."
        }
    }
}

struct ProgrammeLoudnessMapping: Codable, Equatable, Sendable {
    let layout: ProgrammeLoudnessLayout
    /// Zero-based audio stream ordinals, in layout.channelRoles order.
    /// These are not the container's absolute stream indices.
    let audioStreamIndices: [Int]

    nonisolated func validate(audioStreams: [MediaMetadata.AudioStream]) throws {
        guard audioStreamIndices.count == layout.channelRoles.count, !audioStreamIndices.contains(-1) else {
            throw ProgrammeLoudnessError.incompleteMapping
        }
        guard Set(audioStreamIndices).count == audioStreamIndices.count else {
            throw ProgrammeLoudnessError.duplicateStream
        }
        for index in audioStreamIndices {
            guard audioStreams.indices.contains(index) else { throw ProgrammeLoudnessError.invalidStream }
            guard audioStreams[index].channels == 1 else { throw ProgrammeLoudnessError.monoRequired }
            guard let rate = audioStreams[index].sampleRate, rate > 0, rate <= 768_000 else {
                throw ProgrammeLoudnessError.sampleRateRequired
            }
        }
    }
}

struct ProgrammeLoudnessResult: Codable, Sendable {
    let mapping: ProgrammeLoudnessMapping
    let loudness: FFmpegService.LUFSResult
}
