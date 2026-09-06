// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum CompareReviewDirection {
    case previous
    case next
}

nonisolated enum CompareReviewNavigation {
    static func filtered(_ notes: [CompareReviewNote], query: String) -> [CompareReviewNote] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            [$0.text, $0.severity.title, $0.category.title, $0.status.title]
                .contains { $0.localizedStandardContains(query) }
        }
    }

    /// Navigate distinct marked frames without wrapping. Half a stored frame
    /// treats small backend-clock rounding differences as the current marker.
    static func adjacent(
        in notes: [CompareReviewNote],
        to time: TimeInterval,
        duration: TimeInterval,
        direction: CompareReviewDirection
    ) -> CompareReviewNote? {
        guard time.isFinite, duration.isFinite, duration > 0 else { return nil }
        let candidates = notes.compactMap { note -> (CompareReviewNote, TimeInterval)? in
            let rate = Double(note.primaryRateNumerator) / Double(note.primaryRateDenominator)
            guard rate.isFinite, rate > 0 else { return nil }
            let position = CompareReviewTimeline.time(
                forFrame: note.primaryFrame, duration: duration, frameRate: rate
            )
            let delta = position - time
            switch direction {
            case .previous: guard delta < -0.5 / rate else { return nil }
            case .next: guard delta > 0.5 / rate else { return nil }
            }
            return (note, position)
        }
        return candidates.sorted {
            if $0.1 != $1.1 {
                return direction == .next ? $0.1 < $1.1 : $0.1 > $1.1
            }
            return ($0.0.createdAt, $0.0.id.uuidString) < ($1.0.createdAt, $1.0.id.uuidString)
        }.first?.0
    }
}

nonisolated enum CompareReviewTimeline {
    static func frameIndex(
        for time: TimeInterval,
        duration: TimeInterval,
        frameRate: Double
    ) -> Int64 {
        guard frameRate.isFinite, frameRate > 0 else { return 0 }
        let duration = max(0, duration.isFinite ? duration : 0)
        let time = max(0, min(time.isFinite ? time : 0, duration))
        let lastFrame = max(0, Int64((duration * frameRate).rounded(.up)) - 1)
        return min(Int64((time * frameRate).rounded()), lastFrame)
    }

    static func time(
        forFrame frame: Int64,
        duration: TimeInterval,
        frameRate: Double,
        fallback: TimeInterval = 0
    ) -> TimeInterval {
        guard frameRate.isFinite, frameRate > 0 else {
            return max(0, fallback.isFinite ? fallback : 0)
        }
        let duration = max(0, duration.isFinite ? duration : 0)
        return min(Double(max(0, frame)) / frameRate, duration)
    }
}

nonisolated enum CompareReviewSeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case info, minor, major, critical

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated enum CompareReviewCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, picture, audio, sync, metadata

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated enum CompareReviewStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case open, inProgress, resolved

    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In Progress"
        case .resolved: "Resolved"
        }
    }
}

/// A review note anchored to source A's frame timeline. Seconds are retained
/// as a portable fallback, while the frame index is the authoritative marker.
nonisolated struct CompareReviewNote: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let primaryFrame: Int64
    let primaryTime: TimeInterval
    let secondaryFrame: Int64
    let secondaryTime: TimeInterval
    let primaryRateNumerator: Int64
    let primaryRateDenominator: Int64
    let secondaryRateNumerator: Int64
    let secondaryRateDenominator: Int64
    var text: String
    var severity: CompareReviewSeverity
    var category: CompareReviewCategory
    var status: CompareReviewStatus
    /// Inclusive source A endpoint, measured at the stored primary rational
    /// frame rate. Nil denotes a single-frame note.
    var primaryEndFrame: Int64?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        primaryFrame: Int64,
        primaryTime: TimeInterval,
        secondaryFrame: Int64,
        secondaryTime: TimeInterval,
        primaryRateNumerator: Int64 = 30,
        primaryRateDenominator: Int64 = 1,
        secondaryRateNumerator: Int64 = 30,
        secondaryRateDenominator: Int64 = 1,
        text: String,
        severity: CompareReviewSeverity = .info,
        category: CompareReviewCategory = .general,
        status: CompareReviewStatus = .open,
        primaryEndFrame: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.primaryFrame = max(0, primaryFrame)
        self.primaryTime = max(0, primaryTime.isFinite ? primaryTime : 0)
        self.secondaryFrame = max(0, secondaryFrame)
        self.secondaryTime = max(0, secondaryTime.isFinite ? secondaryTime : 0)
        self.primaryRateNumerator = max(1, primaryRateNumerator)
        self.primaryRateDenominator = max(1, primaryRateDenominator)
        self.secondaryRateNumerator = max(1, secondaryRateNumerator)
        self.secondaryRateDenominator = max(1, secondaryRateDenominator)
        self.text = text
        self.severity = severity
        self.category = category
        self.status = status
        self.primaryEndFrame = primaryEndFrame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, primaryFrame, primaryTime, secondaryFrame, secondaryTime
        case primaryRateNumerator, primaryRateDenominator
        case secondaryRateNumerator, secondaryRateDenominator
        case text, severity, category, status, primaryEndFrame, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Decode original coordinates directly: invalid sidecars must be
        // rejected by the store, never silently repaired by the initializer.
        id = try values.decode(UUID.self, forKey: .id)
        primaryFrame = try values.decode(Int64.self, forKey: .primaryFrame)
        primaryTime = try values.decode(TimeInterval.self, forKey: .primaryTime)
        secondaryFrame = try values.decode(Int64.self, forKey: .secondaryFrame)
        secondaryTime = try values.decode(TimeInterval.self, forKey: .secondaryTime)
        primaryRateNumerator = try values.decode(Int64.self, forKey: .primaryRateNumerator)
        primaryRateDenominator = try values.decode(Int64.self, forKey: .primaryRateDenominator)
        secondaryRateNumerator = try values.decode(Int64.self, forKey: .secondaryRateNumerator)
        secondaryRateDenominator = try values.decode(Int64.self, forKey: .secondaryRateDenominator)
        text = try values.decode(String.self, forKey: .text)
        severity = try values.decodeIfPresent(CompareReviewSeverity.self, forKey: .severity) ?? .info
        category = try values.decodeIfPresent(CompareReviewCategory.self, forKey: .category) ?? .general
        status = try values.decodeIfPresent(CompareReviewStatus.self, forKey: .status) ?? .open
        primaryEndFrame = try values.decodeIfPresent(Int64.self, forKey: .primaryEndFrame)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

/// A path alone cannot distinguish a newly exported master from the previous
/// file that occupied that path. File-system identity and basic stat values
/// keep an old review from silently attaching to replacement media.
nonisolated struct CompareReviewSourceIdentity: Codable, Equatable, Sendable {
    let canonicalPath: String
    let fileSystemNumber: UInt64?
    let fileNumber: UInt64?
    let fileSize: Int64?
    let modificationDate: Date?

    init(url: URL, fileManager: FileManager = .default) {
        canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let attributes = try? fileManager.attributesOfItem(atPath: canonicalPath)
        fileSystemNumber = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        if let date = attributes?[.modificationDate] as? Date {
            let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.down)
            modificationDate = Date(timeIntervalSince1970: milliseconds / 1_000)
        } else {
            modificationDate = nil
        }
    }

    func matches(url: URL, fileManager: FileManager = .default) -> Bool {
        let current = Self(url: url, fileManager: fileManager)
        guard canonicalPath == current.canonicalPath else { return false }

        if let fileSystemNumber, let currentFileSystemNumber = current.fileSystemNumber,
           fileSystemNumber != currentFileSystemNumber {
            return false
        }
        if let fileNumber, let currentFileNumber = current.fileNumber,
           fileNumber != currentFileNumber {
            return false
        }
        if let fileSize, let currentFileSize = current.fileSize,
           fileSize != currentFileSize {
            return false
        }
        if let modificationDate, let currentModificationDate = current.modificationDate,
           modificationDate != currentModificationDate {
            return false
        }
        return true
    }
}

nonisolated struct CompareReviewDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    let primarySource: CompareReviewSourceIdentity
    let secondarySource: CompareReviewSourceIdentity
    var notes: [CompareReviewNote]

    init(
        primaryURL: URL,
        secondaryURL: URL,
        notes: [CompareReviewNote],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        primarySource = CompareReviewSourceIdentity(url: primaryURL)
        secondarySource = CompareReviewSourceIdentity(url: secondaryURL)
        self.notes = notes
    }

    func belongsTo(primaryURL: URL, secondaryURL: URL) -> Bool {
        primarySource.matches(url: primaryURL)
            && secondarySource.matches(url: secondaryURL)
    }
}
