// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Inspector panel showing file metadata: container, codec, resolution, etc.

import SwiftUI

struct MetadataInspectorView: View {
    let item: MediaItem

    private var metadata: MediaMetadata? { item.metadata }
    private var video: MediaMetadata.VideoStream? { metadata?.videoStreams.first }
    private var audio: MediaMetadata.AudioStream? { metadata?.audioStreams.first }

    var body: some View {
        List {
            if let metadata = metadata {
                // Container
                Section("Container") {
                    metadataRow("Format", value: formatDisplayName(metadata))
                    if let bitRate = metadata.bitRate, bitRate > 0 {
                        metadataRow("Bit Rate", value: formatBitRate(bitRate))
                    }
                }

                // Video
                if let video = video {
                    Section("Video") {
                        if let codec = video.codec {
                            metadataRow("Codec", value: codecDisplayName(codec, profile: video.profile))
                        }
                        if let width = video.width, let height = video.height {
                            metadataRow("Resolution", value: "\(width) \u{00D7} \(height)")
                        }
                        if let frameRate = video.frameRate {
                            metadataRow("Frame Rate", value: frameRateDisplay(frameRate))
                        }
                        if let chroma = video.chromaSubsampling {
                            let depth = video.bitDepth.map { "\(chroma) / \($0)-bit" } ?? chroma
                            metadataRow("Chroma", value: depth)
                        } else if let bitDepth = video.bitDepth {
                            metadataRow("Bit Depth", value: "\(bitDepth)-bit")
                        }
                        if let pixFmt = video.pixelFormat {
                            metadataRow("Pixel Format", value: pixFmt)
                        }
                        if let colorSpace = video.colorSpace {
                            metadataRow("Color Space", value: colorSpace)
                        }
                        if let colorTransfer = video.colorTransfer {
                            metadataRow("Transfer", value: colorTransfer)
                        }
                    }
                }

                // Audio
                if let audio = audio {
                    Section("Audio") {
                        if let codec = audio.codec {
                            metadataRow("Codec", value: codecDisplayName(codec, profile: audio.profile))
                        }
                        if let channels = audio.channels {
                            metadataRow("Channels", value: channelDescription(channels, layout: audio.channelLayout))
                        }
                        if let sampleRate = audio.sampleRate {
                            metadataRow("Sample Rate", value: formatSampleRate(sampleRate))
                        }
                        if let bitRate = audio.bitRate, bitRate > 0 {
                            metadataRow("Bit Rate", value: formatBitRate(bitRate))
                        }
                    }
                }

                // Additional audio streams
                if metadata.audioStreams.count > 1 {
                    Section("Additional Audio Tracks") {
                        ForEach(Array(metadata.audioStreams.dropFirst().enumerated()), id: \.offset) { index, stream in
                            let label = streamLabel(stream, index: index + 2)
                            metadataRow(label, value: audioStreamSummary(stream))
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Metadata", systemImage: "doc.questionmark", description: Text("Metadata not available for this file."))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240, idealWidth: 280)
    }

    // MARK: - Row

    private func metadataRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    // MARK: - Formatting

    private func formatDisplayName(_ metadata: MediaMetadata) -> String {
        if let long = metadata.containerLongName {
            return long
        }
        if let short = metadata.formatName {
            return short.uppercased()
        }
        return "Unknown"
    }

    private func codecDisplayName(_ codec: String, profile: String?) -> String {
        let name = codec.uppercased()
        if let profile = profile {
            return "\(name) (\(profile))"
        }
        return name
    }

    private func frameRateDisplay(_ frameRate: MediaMetadata.FrameRate) -> String {
        let value = Double(frameRate.numerator) / Double(frameRate.denominator)
        // Show common NTSC rates nicely
        if frameRate.denominator == 1001 {
            let formatted = String(format: "%.3f", value)
            return "\(formatted) fps"
        }
        if value == value.rounded() {
            return "\(Int(value)) fps"
        }
        return String(format: "%.2f fps", value)
    }

    private func channelDescription(_ channels: Int, layout: String?) -> String {
        if let layout = layout, !layout.isEmpty {
            return "\(channels) (\(layout))"
        }
        switch channels {
        case 1: return "1 (Mono)"
        case 2: return "2 (Stereo)"
        case 6: return "6 (5.1)"
        case 8: return "8 (7.1)"
        default: return "\(channels)"
        }
    }

    private func formatSampleRate(_ rate: Int) -> String {
        if rate % 1000 == 0 {
            return "\(rate / 1000) kHz"
        }
        return String(format: "%.1f kHz", Double(rate) / 1000.0)
    }

    private func formatBitRate(_ bitRate: Int64) -> String {
        if bitRate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitRate) / 1_000_000.0)
        }
        return "\(bitRate / 1000) kbps"
    }

    private func streamLabel(_ stream: MediaMetadata.AudioStream, index: Int) -> String {
        if let title = stream.title, !title.isEmpty {
            return title
        }
        if let lang = stream.languageCode, !lang.isEmpty {
            return "Track \(index) (\(lang))"
        }
        return "Track \(index)"
    }

    private func audioStreamSummary(_ stream: MediaMetadata.AudioStream) -> String {
        var parts: [String] = []
        if let codec = stream.codec { parts.append(codec.uppercased()) }
        if let ch = stream.channels { parts.append("\(ch)ch") }
        if let sr = stream.sampleRate { parts.append(formatSampleRate(sr)) }
        return parts.joined(separator: ", ")
    }
}
