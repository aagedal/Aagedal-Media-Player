// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    static let currentSchemaVersion = 1

    let schemaVersion: Int
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
