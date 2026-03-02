// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Inspector panel showing file metadata: container, codec, resolution, etc.

import SwiftUI
import AppKit

struct MetadataInspectorView: View {
    let item: MediaItem
    let useMPV: Bool
    @Binding var isPresented: Bool
    @State private var showCopiedConfirmation = false

    private var metadata: MediaMetadata? { item.metadata }
    private var video: MediaMetadata.VideoStream? { metadata?.videoStreams.first }
    private var audio: MediaMetadata.AudioStream? { metadata?.audioStreams.first }

    var body: some View {
        List {
            if let metadata = metadata {
                // File
                Section("File") {
                    metadataRow("Name", value: item.name)
                    if let duration = metadata.duration, duration > 0 {
                        metadataRow("Duration", value: formatDuration(duration))
                    }
                    metadataRow("Size", value: item.formattedSize)
                }

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
                            metadataRow("Resolution", value: resolutionDisplay(width: width, height: height, dar: video.displayAspectRatio))
                        }
                        if let frameRate = video.frameRate {
                            metadataRow("Frame Rate", value: frameRateDisplay(frameRate))
                        }
                        if let scanType = scanTypeDisplay(video) {
                            metadataRow("Scan", value: scanType)
                        }
                        if let chroma = video.chromaSubsampling {
                            metadataRow("Chroma Subsampling", value: chroma)
                        }
                        if let chroma = video.chromaSubsampling,
                           let w = video.width, let h = video.height,
                           let chromaRes = chromaResolution(chroma: chroma, width: w, height: h) {
                            metadataRow("Chroma Resolution", value: chromaRes)
                        }
                        if let bitDepth = video.bitDepth {
                            metadataRow("Bit Depth", value: "\(bitDepth)-bit")
                        }
                        if let pixFmt = video.pixelFormat {
                            metadataRow("Pixel Format", value: pixFmt)
                        }
                        if let colorPrimaries = video.colorPrimaries {
                            metadataRow("Color Primaries", value: colorPrimaries)
                        }
                        if let colorSpace = video.colorSpace {
                            metadataRow("Color Space", value: colorSpace)
                        }
                        if let colorTransfer = video.colorTransfer {
                            metadataRow("Transfer", value: colorTransfer)
                        }
                        if let colorRange = video.colorRange {
                            metadataRow("Range", value: colorRange)
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
                        if let bitDepth = audio.bitDepth {
                            metadataRow("Bit Depth", value: "\(bitDepth)-bit")
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

                // Subtitle streams
                if !metadata.subtitleStreams.isEmpty {
                    Section("Subtitles") {
                        ForEach(Array(metadata.subtitleStreams.enumerated()), id: \.offset) { index, stream in
                            let label = subtitleLabel(stream, index: index + 1)
                            metadataRow(label, value: subtitleSummary(stream))
                        }
                    }
                }

                // Info (timecode, comment, encoder)
                if metadata.timecode != nil || metadata.comment != nil || metadata.encoder != nil {
                    Section("Info") {
                        if let timecode = metadata.timecode {
                            metadataRow("Timecode", value: timecode)
                        }
                        if let comment = metadata.comment {
                            metadataRow("Comment", value: comment)
                        }
                        if let encoder = metadata.encoder {
                            metadataRow("Encoder", value: encoder)
                        }
                    }
                }

                // Playback
                Section("Playback") {
                    metadataRow("Engine", value: useMPV ? "mpv" : "Apple AVFoundation")
                }
            } else {
                ContentUnavailableView("No Metadata", systemImage: "doc.questionmark", description: Text("Metadata not available for this file."))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 280, idealWidth: 320)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                HStack {
                    Text("Metadata")
                        .font(.headline)
                    Spacer()
                    Button(action: { revealInFinder() }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                    Button(action: { copyMetadataAsJSON() }) {
                        Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(showCopiedConfirmation ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy metadata as JSON")
                    .disabled(metadata == nil)
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close inspector")
                }

                if video != nil || audio != nil {
                    HStack(spacing: 6) {
                        if let video = video {
                            if let badge = resolutionBadge(video) {
                                mediaBadge(badge.label, color: badge.color)
                            }
                            mediaBadge(isHDR(video) ? "HDR" : "SDR",
                                       color: isHDR(video) ? .orange : .gray)
                        }
                        if let metadata = metadata, let badge = audioBadge(metadata) {
                            mediaBadge(badge.label, color: badge.color)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar, ignoresSafeAreaEdges: .top)
        }
        .onExitCommand {
            isPresented = false
        }
    }

    // MARK: - Actions

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func copyMetadataAsJSON() {
        guard let metadata = metadata else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metadata),
              let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)

        withAnimation { showCopiedConfirmation = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedConfirmation = false }
        }
    }

    // MARK: - Badges

    private func mediaBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: .capsule)
    }

    private struct ResolutionBadge {
        let label: String
        let color: Color
    }

    private func resolutionBadge(_ video: MediaMetadata.VideoStream) -> ResolutionBadge? {
        guard let width = video.width, let height = video.height else { return nil }
        let shortEdge = min(width, height)
        if shortEdge >= 4320 {
            return ResolutionBadge(label: "8K", color: .yellow)
        } else if shortEdge >= 2160 {
            return ResolutionBadge(label: "4K", color: .purple)
        } else if shortEdge >= 720 {
            return ResolutionBadge(label: "HD", color: .blue)
        } else {
            return ResolutionBadge(label: "SD", color: .gray)
        }
    }

    private struct AudioBadge {
        let label: String
        let color: Color
    }

    private func audioChannelLabel(_ channels: Int) -> String {
        if channels >= 6 { return "Surround" }
        if channels == 2 { return "Stereo" }
        if channels == 1 { return "Mono" }
        return "\(channels)ch"
    }

    private func audioBadge(_ metadata: MediaMetadata) -> AudioBadge? {
        let streams = metadata.audioStreams
        guard !streams.isEmpty else { return nil }

        // Deduplicate by channel count, preserving stream order
        var seen = Set<Int>()
        var labels: [String] = []
        for stream in streams {
            guard let channels = stream.channels, seen.insert(channels).inserted else { continue }
            labels.append(audioChannelLabel(channels))
        }

        guard !labels.isEmpty else { return nil }
        let hasSurround = streams.contains { ($0.channels ?? 0) >= 6 }
        return AudioBadge(
            label: labels.joined(separator: " + "),
            color: hasSurround ? .teal : .gray
        )
    }

    private func isHDR(_ video: MediaMetadata.VideoStream) -> Bool {
        if let transfer = video.colorTransfer?.lowercased() {
            if transfer.contains("smpte2084") || transfer == "smpte st 2084"
                || transfer.contains("arib-std-b67") || transfer == "hlg" {
                return true
            }
        }
        if let primaries = video.colorPrimaries?.lowercased() {
            if primaries.contains("bt2020") {
                return true
            }
        }
        return false
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

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func resolutionDisplay(width: Int, height: Int, dar: MediaMetadata.Ratio?) -> String {
        var result = "\(width) \u{00D7} \(height)"
        if let dar = dar {
            result += " (\(dar.stringValue))"
        }
        return result
    }

    private func chromaResolution(chroma: String, width: Int, height: Int) -> String? {
        let (cw, ch): (Int, Int)
        switch chroma {
        case "4:2:0": (cw, ch) = (width / 2, height / 2)
        case "4:2:2": (cw, ch) = (width / 2, height)
        case "4:1:1": (cw, ch) = (width / 4, height)
        case "4:1:0": (cw, ch) = (width / 4, height / 2)
        case "4:4:4": return nil // same as luma, not useful to show
        default: return nil
        }
        return "\(cw) \u{00D7} \(ch)"
    }

    private func scanTypeDisplay(_ video: MediaMetadata.VideoStream) -> String? {
        guard let fieldOrder = video.fieldOrder else { return nil }
        let value = fieldOrder.lowercased()
        if value == "progressive" { return "Progressive" }
        if value == "unknown" { return nil }
        // Interlaced — show field order
        if value == "tt" || value == "tb" { return "Interlaced (TFF)" }
        if value == "bb" || value == "bt" { return "Interlaced (BFF)" }
        return "Interlaced"
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

    private func subtitleLabel(_ stream: MediaMetadata.SubtitleStream, index: Int) -> String {
        if let title = stream.title, !title.isEmpty {
            return title
        }
        if let lang = stream.languageCode, !lang.isEmpty {
            return "Track \(index) (\(lang))"
        }
        return "Track \(index)"
    }

    private func subtitleSummary(_ stream: MediaMetadata.SubtitleStream) -> String {
        var parts: [String] = []
        if let codec = stream.codec { parts.append(codec.uppercased()) }
        if stream.isForced { parts.append("Forced") }
        if stream.isDefault { parts.append("Default") }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: ", ")
    }
}
