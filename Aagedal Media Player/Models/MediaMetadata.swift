// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Media metadata structures (adapted from Aagedal Media Converter's VideoMetadata).

import Foundation

struct MediaMetadata: Equatable, Sendable, Codable {
    struct Ratio: Equatable, Sendable, Codable {
        let numerator: Int
        let denominator: Int
        let stringValue: String

        nonisolated var doubleValue: Double? {
            guard denominator != 0 else { return nil }
            return Double(numerator) / Double(denominator)
        }

        /// `stringValue` reduced to lowest terms — e.g. `1920:1080` → `16:9`,
        /// `5760:3240` → `16:9`. Useful for display where the colloquial ratio
        /// is more readable than the raw pixel grid.
        nonisolated var reducedStringValue: String {
            let n = abs(numerator)
            let d = abs(denominator)
            guard n > 0, d > 0 else { return stringValue }
            var a = n, b = d
            while b != 0 { (a, b) = (b, a % b) }
            let g = a
            return "\(numerator / g):\(denominator / g)"
        }

        nonisolated init?(numerator: Int, denominator: Int) {
            guard denominator != 0 else { return nil }
            self.numerator = numerator
            self.denominator = denominator
            self.stringValue = "\(numerator):\(denominator)"
        }

        nonisolated init?(ratioString: String) {
            let trimmed = ratioString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let parsed = Ratio.parse(trimmed, separator: ":") ?? Ratio.parse(trimmed, separator: "/") {
                self = parsed
                return
            }

            if let value = Double(trimmed) {
                let scaledNumerator = Int((value * 10_000).rounded())
                self.numerator = scaledNumerator
                self.denominator = 10_000
                self.stringValue = String(format: value >= 10 ? "%.2f" : "%.4f", value)
                return
            }

            return nil
        }

        nonisolated static func parse(_ string: String, separator: Character) -> Ratio? {
            let parts = string.split(separator: separator)
            guard parts.count == 2,
                  let numerator = Int(parts[0]),
                  let denominator = Int(parts[1]),
                  denominator != 0 else {
                return nil
            }
            return Ratio(numerator: numerator, denominator: denominator)
        }
    }

    struct FrameRate: Equatable, Sendable, Codable {
        let numerator: Int
        let denominator: Int
        let stringValue: String

        nonisolated var value: Double? {
            guard denominator != 0 else { return nil }
            return Double(numerator) / Double(denominator)
        }

        nonisolated init?(frameRateString: String) {
            let trimmed = frameRateString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if trimmed.contains("/") {
                let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]),
                      numerator > 0, denominator > 0,
                      Double(numerator) / Double(denominator) < Double(Int.max) / 1_000_000 else { return nil }
                // Explicit fractions stay exact; never reinterpret stored or
                // producer-declared rates as a nearby broadcast timebase.
                self.numerator = numerator
                self.denominator = denominator
                self.stringValue = String(format: "%.3f", Double(numerator) / Double(denominator))
                return
            }

            guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
            // Normalize broadcast decimal spellings to n/1001, retaining
            // micro-fps precision otherwise. Bound TimecodeRate's integer
            // conversion before handing untrusted metadata to it.
            let scaled = (value * 1_000_000).rounded()
            guard value >= 0.000_001, scaled.isFinite, scaled < Double(Int.max) else { return nil }
            let rate = TimecodeRate(frameRate: value)
            self.numerator = Int(rate.numerator)
            self.denominator = Int(rate.denominator)
            self.stringValue = String(format: "%.3f", rate.value)
        }
    }

    let duration: Double?
    let formatName: String?
    let containerLongName: String?
    let sizeBytes: Int64?
    let bitRate: Int64?
    let timecode: String?
    let comment: String?
    let encoder: String?
    let frameCount: Int?

    struct VideoStream: Equatable, Sendable, Codable {
        let codec: String?
        let codecLongName: String?
        let profile: String?
        let width: Int?
        let height: Int?
        // Display dimensions: rotation-aware and PAR-corrected when known.
        // Mirrors what ffprobe would report after applying side-data rotation
        // and sample aspect ratio. Differs from `width`/`height` for anamorphic
        // or rotated tracks (e.g. iPhone portrait HEVC: width 3840, height 2160,
        // displayWidth 2160, displayHeight 3840).
        let displayWidth: Int?
        let displayHeight: Int?
        let pixelFormat: String?
        let hasAlpha: Bool
        let pixelAspectRatio: Ratio?
        let displayAspectRatio: Ratio?
        let frameRate: FrameRate?
        let bitDepth: Int?
        let chromaSubsampling: String?
        let colorPrimaries: String?
        let colorTransfer: String?
        let colorSpace: String?
        let colorRange: String?
        let chromaLocation: String?
        let fieldOrder: String?
        let isInterlaced: Bool?
        let rotation: Int?           // Display rotation in degrees (90 / 180 / 270 / -90 etc.)
        // HDR luminance metadata
        let maxCLL: Int?            // MaxCLL (Maximum Content Light Level) in nits
        let maxFALL: Int?           // MaxFALL (Maximum Frame Average Light Level) in nits
        let masteringMaxLuminance: Double?  // Mastering display max luminance in nits
        let masteringMinLuminance: Double?  // Mastering display min luminance in nits
    }

    struct AudioStream: Equatable, Sendable, Codable {
        let index: Int?
        let languageCode: String?
        let title: String?
        let codec: String?
        let codecLongName: String?
        let profile: String?
        let sampleRate: Int?
        let channels: Int?
        let channelLayout: String?
        let bitDepth: Int?
        let bitRate: Int64?
        let isDefault: Bool
    }

    struct SubtitleStream: Equatable, Sendable, Codable {
        let index: Int?
        let languageCode: String?
        let title: String?
        let codec: String?
        let codecLongName: String?
        let isDefault: Bool
        let isForced: Bool
    }

    struct Chapter: Equatable, Sendable, Codable {
        let id: UInt64?
        let index: Int
        let startTime: TimeInterval
        let endTime: TimeInterval?
        let title: String?
        let languageCode: String?
    }

    let videoStreams: [VideoStream]
    let audioStreams: [AudioStream]
    let subtitleStreams: [SubtitleStream]
    let chapters: [Chapter]

    /// Embedded bext values, independent of measurements performed by the player.
    nonisolated struct BroadcastWave: Equatable, Sendable, Codable {
        let version: UInt16
        let description: String?
        let originator: String?
        let originatorReference: String?
        let originationDate: String?
        let originationTime: String?
        let timeReferenceSamples: UInt64
        let umid: String?
        let integratedLoudness: Double?
        let loudnessRange: Double?
        let maxTruePeakLevel: Double?
        let maxMomentaryLoudness: Double?
        let maxShortTermLoudness: Double?
        let codingHistory: String?
        let codingHistoryTruncated: Bool
    }

    var broadcastWave: BroadcastWave? = nil

    /// Explicit iXML recording labels; no timing, speaker-layout or BWF inference.
    nonisolated struct IXMLRecording: Equatable, Sendable, Codable {
        let version: String?
        let project: String?
        let scene: String?
        let take: String?
        let tape: String?
        let note: String?
        let circled: Bool?
        let fileUID: String?
    }

    var ixmlRecording: IXMLRecording? = nil

    var primaryVideoStream: VideoStream? {
        videoStreams.first
    }

    nonisolated func isDefaultAudioStream(index: Int) -> Bool {
        guard audioStreams.indices.contains(index) else { return false }
        return audioStreams[index].isDefault
    }
}
