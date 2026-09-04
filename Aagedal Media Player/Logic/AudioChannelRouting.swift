// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Non-destructive monitoring state for one decoded audio track.
///
/// A non-empty solo set limits output to those channels, and mute is then
/// applied on top. The encoded file and the user's global mute preference are
/// never changed.
nonisolated struct AudioChannelRouting: Equatable, Sendable {
    let channelCount: Int
    let mutedChannels: Set<Int>
    let soloedChannels: Set<Int>

    init(
        channelCount: Int = 0,
        mutedChannels: Set<Int> = [],
        soloedChannels: Set<Int> = []
    ) {
        self.channelCount = max(0, channelCount)
        let validChannels = Set(0..<self.channelCount)
        self.mutedChannels = mutedChannels.intersection(validChannels)
        self.soloedChannels = soloedChannels.intersection(validChannels)
    }

    var audibleChannels: Set<Int> {
        let candidates = soloedChannels.isEmpty
            ? Set(0..<channelCount)
            : soloedChannels
        return candidates.subtracting(mutedChannels)
    }

    var isBypassed: Bool {
        channelCount == 0 || audibleChannels.count == channelCount
    }

    func isAudible(_ channel: Int) -> Bool {
        audibleChannels.contains(channel)
    }

    func togglingMute(for channel: Int) -> Self {
        guard (0..<channelCount).contains(channel) else { return self }
        var muted = mutedChannels
        if !muted.insert(channel).inserted {
            muted.remove(channel)
        }
        return Self(
            channelCount: channelCount,
            mutedChannels: muted,
            soloedChannels: soloedChannels
        )
    }

    func togglingSolo(for channel: Int) -> Self {
        guard (0..<channelCount).contains(channel) else { return self }
        let soloed = soloedChannels == [channel] ? Set<Int>() : [channel]
        return Self(
            channelCount: channelCount,
            mutedChannels: mutedChannels,
            soloedChannels: soloed
        )
    }

    /// mpv's `af` value for an in-place channel-preserving pan matrix.
    /// Returning nil removes the filter when every channel is audible.
    var mpvAudioFilter: String? {
        guard !isBypassed else { return nil }
        let outputs = (0..<channelCount).map { channel in
            "c\(channel)=" + (isAudible(channel) ? "c\(channel)" : "0*c\(channel)")
        }
        return "lavfi=[pan=\(channelCount)c|\(outputs.joined(separator: "|"))]"
    }
}

nonisolated enum AudioChannelLabels {
    static func names(count: Int, layout: String?) -> [String] {
        let count = max(0, count)
        if let layout, !layout.isEmpty {
            let knownLayouts: [String: [String]] = [
                "mono": ["Mono"],
                "stereo": ["Left", "Right"],
                "2.1": ["Left", "Right", "LFE"],
                "3.0": ["Left", "Right", "Center"],
                "3.0(back)": ["Left", "Right", "Back Center"],
                "3.1": ["Left", "Right", "Center", "LFE"],
                "4.0": ["Left", "Right", "Center", "Back Center"],
                "quad": ["Left", "Right", "Back Left", "Back Right"],
                "quad(side)": ["Left", "Right", "Side Left", "Side Right"],
                "5.0": ["Left", "Right", "Center", "Back Left", "Back Right"],
                "5.0(side)": ["Left", "Right", "Center", "Side Left", "Side Right"],
                "5.1": ["Left", "Right", "Center", "LFE", "Back Left", "Back Right"],
                "5.1(side)": ["Left", "Right", "Center", "LFE", "Side Left", "Side Right"],
                "6.1": ["Left", "Right", "Center", "LFE", "Back Center", "Side Left", "Side Right"],
                "7.1": ["Left", "Right", "Center", "LFE", "Back Left", "Back Right", "Side Left", "Side Right"],
                "7.1(wide)": ["Left", "Right", "Center", "LFE", "Back Left", "Back Right", "Front Left of Center", "Front Right of Center"],
            ]
            if let names = knownLayouts[layout.lowercased()], names.count == count {
                return names
            }
        }

        if count == 1 { return ["Mono"] }
        if count == 2 { return ["Left", "Right"] }
        return (0..<count).map { "Channel \($0 + 1)" }
    }

    static func hasKnownLayout(count: Int, layout: String?) -> Bool {
        let labels = names(count: count, layout: layout)
        guard labels.count == count, count > 0 else { return false }
        return count <= 2 || !(labels.first?.hasPrefix("Channel ") ?? true)
    }
}

nonisolated struct CompareAudioChannelOption: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let primaryIndex: Int
    let secondaryIndex: Int
}

nonisolated enum CompareAudioChannelMatcher {
    static func options(
        primaryCount: Int,
        primaryLayout: String?,
        secondaryCount: Int,
        secondaryLayout: String?
    ) -> [CompareAudioChannelOption] {
        guard primaryCount > 0, secondaryCount > 0 else { return [] }
        let primaryLabels = AudioChannelLabels.names(count: primaryCount, layout: primaryLayout)
        let secondaryLabels = AudioChannelLabels.names(count: secondaryCount, layout: secondaryLayout)
        let bothKnown = AudioChannelLabels.hasKnownLayout(count: primaryCount, layout: primaryLayout)
            && AudioChannelLabels.hasKnownLayout(count: secondaryCount, layout: secondaryLayout)

        // Ordinal mapping is safe only when the layouts have the same size.
        if !bothKnown {
            guard primaryCount == secondaryCount else { return [] }
            return primaryLabels.indices.map { index in
                CompareAudioChannelOption(
                    id: "ordinal-\(index)",
                    label: primaryLabels[index],
                    primaryIndex: index,
                    secondaryIndex: index
                )
            }
        }

        var usedSecondary = Set<Int>()
        return primaryLabels.indices.compactMap { primaryIndex in
            let label = primaryLabels[primaryIndex]
            guard let secondaryIndex = secondaryLabels.indices.first(where: {
                !usedSecondary.contains($0)
                    && secondaryLabels[$0].localizedCaseInsensitiveCompare(label) == .orderedSame
            }) else { return nil }
            usedSecondary.insert(secondaryIndex)
            return CompareAudioChannelOption(
                id: label.lowercased(),
                label: label,
                primaryIndex: primaryIndex,
                secondaryIndex: secondaryIndex
            )
        }
    }
}
