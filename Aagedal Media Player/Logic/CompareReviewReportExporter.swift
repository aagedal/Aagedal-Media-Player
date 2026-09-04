// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum CompareReviewReportFormat: String, CaseIterable, Sendable {
    case csv

    var label: String {
        switch self {
        case .csv: "CSV Report"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        }
    }
}

nonisolated enum CompareReviewExportState: Equatable, Sendable {
    case idle
    case exporting
    case succeeded(URL)
    case failed(String)

    var isInFlight: Bool { self == .exporting }
}

nonisolated struct CompareReviewReportRow: Equatable, Sendable {
    let markerNumber: Int
    let primarySourceTimecode: String?
    let primaryRelativeTimecode: String
    let primaryFrame: Int64
    let secondarySourceTimecode: String?
    let secondaryRelativeTimecode: String
    let secondaryFrame: Int64
    let note: String
    let createdAt: Date
    let updatedAt: Date
}

/// An immutable snapshot keeps a report internally consistent even if the
/// user edits notes or replaces source B while the save panel is open.
nonisolated struct CompareReviewReportSnapshot: Equatable, Sendable {
    let primaryFilename: String
    let secondaryFilename: String
    let alignmentLabel: String
    let rows: [CompareReviewReportRow]

    @MainActor
    init(
        primaryItem: MediaItem,
        secondaryItem: MediaItem,
        alignmentMode: CompareAlignmentMode,
        notes: [CompareReviewNote]
    ) {
        primaryFilename = primaryItem.url.lastPathComponent
        secondaryFilename = secondaryItem.url.lastPathComponent
        alignmentLabel = alignmentMode.label

        let sortedNotes = notes.sorted {
            if $0.primaryFrame != $1.primaryFrame {
                return $0.primaryFrame < $1.primaryFrame
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        rows = sortedNotes.enumerated().map { index, note in
            let primaryTime = CompareReviewTimeline.time(
                forFrame: note.primaryFrame,
                duration: primaryItem.durationSeconds,
                frameRate: Double(note.primaryRateNumerator)
                    / Double(note.primaryRateDenominator),
                fallback: note.primaryTime
            )
            let secondaryTime = CompareReviewTimeline.time(
                forFrame: note.secondaryFrame,
                duration: secondaryItem.durationSeconds,
                frameRate: Double(note.secondaryRateNumerator)
                    / Double(note.secondaryRateDenominator),
                fallback: note.secondaryTime
            )

            return CompareReviewReportRow(
                markerNumber: index + 1,
                primarySourceTimecode: Self.sourceTimecode(
                    item: primaryItem,
                    time: primaryTime
                ),
                primaryRelativeTimecode: TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: primaryTime,
                    item: primaryItem,
                    mode: .relative
                ),
                primaryFrame: note.primaryFrame,
                secondarySourceTimecode: Self.sourceTimecode(
                    item: secondaryItem,
                    time: secondaryTime
                ),
                secondaryRelativeTimecode: TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: secondaryTime,
                    item: secondaryItem,
                    mode: .relative
                ),
                secondaryFrame: note.secondaryFrame,
                note: note.text,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt
            )
        }
    }

    @MainActor
    private static func sourceTimecode(item: MediaItem, time: TimeInterval) -> String? {
        guard TimecodeFormatter.effectiveStartTimecode(for: item) != nil else { return nil }
        return TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: time,
            item: item,
            mode: .source
        )
    }
}

nonisolated enum CompareReviewReportExporter {
    static let csvColumns = [
        "Marker",
        "Source A",
        "Source B",
        "Alignment",
        "A Source TC",
        "A Relative TC",
        "A Frame",
        "B Source TC",
        "B Relative TC",
        "B Frame",
        "Note",
        "Created",
        "Updated",
    ]

    static func data(
        for format: CompareReviewReportFormat,
        snapshot: CompareReviewReportSnapshot
    ) -> Data {
        switch format {
        case .csv:
            Data(csv(snapshot: snapshot).utf8)
        }
    }

    static func preferredFilename(
        for format: CompareReviewReportFormat,
        snapshot: CompareReviewReportSnapshot
    ) -> String {
        let primary = sanitizedFilenameStem(snapshot.primaryFilename)
        let secondary = sanitizedFilenameStem(snapshot.secondaryFilename)
        return "\(primary)_vs_\(secondary)_review.\(format.fileExtension)"
    }

    static func csv(snapshot: CompareReviewReportSnapshot) -> String {
        var records = [csvColumns]
        records.reserveCapacity(snapshot.rows.count + 1)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        for row in snapshot.rows {
            records.append([
                String(row.markerNumber),
                snapshot.primaryFilename,
                snapshot.secondaryFilename,
                snapshot.alignmentLabel,
                row.primarySourceTimecode ?? "",
                row.primaryRelativeTimecode,
                String(row.primaryFrame),
                row.secondarySourceTimecode ?? "",
                row.secondaryRelativeTimecode,
                String(row.secondaryFrame),
                row.note,
                dateFormatter.string(from: row.createdAt),
                dateFormatter.string(from: row.updatedAt),
            ])
        }

        return records
            .map { $0.map(escapedCSVField).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    private static func escapedCSVField(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\r")
                || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func sanitizedFilenameStem(_ filename: String) -> String {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let sanitized = stem
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "Untitled" : sanitized).prefix(60))
    }
}
