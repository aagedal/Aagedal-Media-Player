// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum CompareReviewTimebaseMigrationError: Error, LocalizedError {
    case unavailable
    case noChanges
    case unsupportedRate(Int, String)
    case unavailableFrame(Int, String)
    case sourceChanged
    case previewChanged
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Timebase migration requires a saved review and readable A/B media with known frame rates and durations."
        case .noChanges:
            "This review has no historical rounded broadcast rates to migrate."
        case .unsupportedRate(let number, let source):
            "Note \(number), source \(source), has a different rate that is not a recognized historical rounded broadcast rate. Migration cannot infer a new frame position."
        case .unavailableFrame(let number, let source):
            "Note \(number), source \(source), would be outside the current media. Check the original sources and review range before migrating."
        case .sourceChanged:
            "The review's source files are unavailable or changed. Restore the original A/B sources before migrating."
        case .previewChanged:
            "The saved review changed after preview. Preview the migration again."
        case .destinationExists:
            "A file already exists at the migration destination. Existing files are never replaced."
        }
    }
}

/// A concrete, immutable proposal. Frame indices are authoritative; this
/// corrects their timebase without guessing a different captured frame.
nonisolated struct CompareReviewTimebaseMigration: Equatable, Sendable {
    let original: CompareReviewDocument
    let migrated: CompareReviewDocument
    let primarySource: CompareReviewSourceIdentity
    let secondarySource: CompareReviewSourceIdentity
    let primaryRate: TimecodeRate
    let secondaryRate: TimecodeRate
    let primaryDuration: TimeInterval
    let secondaryDuration: TimeInterval

    var changedNotes: [CompareReviewNote] {
        zip(original.notes, migrated.notes).compactMap { old, new in old != new ? new : nil }
    }

    /// Compare the representation that the sidecar actually saves. Date's
    /// reference epoch and the JSON millisecond epoch can round differently
    /// at sub-microsecond precision, while every other note field must agree.
    static func hasSameSavedNotes(_ lhs: [CompareReviewNote], _ rhs: [CompareReviewNote]) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let left = lhs.sorted { $0.id.uuidString < $1.id.uuidString }
        let right = rhs.sorted { $0.id.uuidString < $1.id.uuidString }
        return try encoder.encode(left) == encoder.encode(right)
    }

    init(
        document: CompareReviewDocument,
        primaryURL: URL,
        secondaryURL: URL,
        primaryRate: TimecodeRate,
        secondaryRate: TimecodeRate,
        primaryDuration: TimeInterval,
        secondaryDuration: TimeInterval,
        migratedAt: Date = Date()
    ) throws {
        guard primaryDuration.isFinite, primaryDuration > 0,
              secondaryDuration.isFinite, secondaryDuration > 0 else {
            throw CompareReviewTimebaseMigrationError.unavailable
        }
        guard document.belongsTo(primaryURL: primaryURL, secondaryURL: secondaryURL) else {
            throw CompareReviewTimebaseMigrationError.sourceChanged
        }
        for sourceURL in [primaryURL, secondaryURL] {
            let canonical = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            let attributes = try? FileManager.default.attributesOfItem(atPath: canonical.path)
            guard sourceURL.isFileURL,
                  attributes?[.type] as? FileAttributeType == .typeRegular,
                  FileManager.default.isReadableFile(atPath: canonical.path) else {
                throw CompareReviewTimebaseMigrationError.sourceChanged
            }
        }
        self.original = document
        self.primarySource = CompareReviewSourceIdentity(url: primaryURL)
        self.secondarySource = CompareReviewSourceIdentity(url: secondaryURL)
        self.primaryRate = primaryRate
        self.secondaryRate = secondaryRate
        self.primaryDuration = primaryDuration
        self.secondaryDuration = secondaryDuration
        var migrated = document
        migrated.schemaVersion = CompareReviewDocument.currentSchemaVersion
        migrated.notes = try document.notes.enumerated().map { index, note in
            let number = index + 1
            let changeA = try Self.needsCorrection(
                numerator: note.primaryRateNumerator, denominator: note.primaryRateDenominator,
                target: primaryRate, number: number, source: "A"
            )
            let changeB = try Self.needsCorrection(
                numerator: note.secondaryRateNumerator, denominator: note.secondaryRateDenominator,
                target: secondaryRate, number: number, source: "B"
            )
            for (frame, rate, duration, source) in [
                (note.primaryFrame, primaryRate, primaryDuration, "A"),
                (note.primaryEndFrame ?? note.primaryFrame, primaryRate, primaryDuration, "A range end"),
                (note.secondaryFrame, secondaryRate, secondaryDuration, "B")
            ] {
                guard frame >= 0, rate.seconds(forFrameCount: frame) < duration else {
                    throw CompareReviewTimebaseMigrationError.unavailableFrame(number, source)
                }
            }
            guard changeA || changeB else { return note }
            return CompareReviewNote(
                id: note.id, primaryFrame: note.primaryFrame,
                primaryTime: changeA ? primaryRate.seconds(forFrameCount: note.primaryFrame) : note.primaryTime,
                secondaryFrame: note.secondaryFrame,
                secondaryTime: changeB ? secondaryRate.seconds(forFrameCount: note.secondaryFrame) : note.secondaryTime,
                primaryRateNumerator: changeA ? primaryRate.numerator : note.primaryRateNumerator,
                primaryRateDenominator: changeA ? primaryRate.denominator : note.primaryRateDenominator,
                secondaryRateNumerator: changeB ? secondaryRate.numerator : note.secondaryRateNumerator,
                secondaryRateDenominator: changeB ? secondaryRate.denominator : note.secondaryRateDenominator,
                text: note.text, severity: note.severity, category: note.category, status: note.status,
                primaryEndFrame: note.primaryEndFrame, createdAt: note.createdAt, updatedAt: migratedAt
            )
        }
        guard migrated.notes != document.notes else { throw CompareReviewTimebaseMigrationError.noChanges }
        self.migrated = migrated
    }

    private static func needsCorrection(
        numerator: Int64, denominator: Int64, target: TimecodeRate, number: Int, source: String
    ) throws -> Bool {
        // Reduce without cross-multiplying untrusted Int64 components.
        guard numerator > 0, denominator > 0 else {
            throw CompareReviewTimebaseMigrationError.unsupportedRate(number, source)
        }
        var a = numerator
        var b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        let storedNumerator = numerator / a
        let storedDenominator = denominator / a
        if storedNumerator == target.numerator, storedDenominator == target.denominator { return false }
        let historical: [Int64: Int] = [24_000: 23_976, 30_000: 29_970, 48_000: 47_952,
                                       60_000: 59_940, 120_000: 119_880]
        guard target.denominator == 1_001, let decimal = historical[target.numerator] else {
            throw CompareReviewTimebaseMigrationError.unsupportedRate(number, source)
        }
        let rounded = TimecodeRate(numerator: decimal, denominator: 1_000)
        guard storedNumerator == rounded.numerator, storedDenominator == rounded.denominator else {
            throw CompareReviewTimebaseMigrationError.unsupportedRate(number, source)
        }
        return true
    }
}
