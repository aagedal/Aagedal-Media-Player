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

            if let ratio = Ratio.parse(trimmed, separator: "/") {
                self.numerator = ratio.numerator
                self.denominator = ratio.denominator
                if let value = ratio.doubleValue {
                    self.stringValue = String(format: "%.3f", value)
                } else {
                    self.stringValue = trimmed
                }
                return
            }

            if let value = Double(trimmed), value > 0 {
                self.numerator = Int((value * 1_000).rounded())
                self.denominator = 1_000
                self.stringValue = String(format: "%.3f", value)
                return
            }

            return nil
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

    let videoStreams: [VideoStream]
    let audioStreams: [AudioStream]
    let subtitleStreams: [SubtitleStream]

    var primaryVideoStream: VideoStream? {
        videoStreams.first
    }

    nonisolated func isDefaultAudioStream(index: Int) -> Bool {
        guard audioStreams.indices.contains(index) else { return false }
        return audioStreams[index].isDefault
    }
}
