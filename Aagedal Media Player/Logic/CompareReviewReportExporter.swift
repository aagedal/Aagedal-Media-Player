// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

nonisolated enum CompareReviewReportFormat: String, CaseIterable, Sendable {
    case csv
    case pdf
    case resolveMarkersEDL
    case finalCutProXML
    case avidMarkersText

    var label: String {
        switch self {
        case .csv: "CSV Report"
        case .pdf: "PDF Report"
        case .resolveMarkersEDL: "DaVinci Resolve Markers"
        case .finalCutProXML: "Final Cut Pro Markers"
        case .avidMarkersText: "Avid Media Composer Markers"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .pdf: "pdf"
        case .resolveMarkersEDL: "edl"
        case .finalCutProXML: "fcpxml"
        case .avidMarkersText: "txt"
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

nonisolated enum CompareReviewReportExportError: Error, LocalizedError {
    case tooManyResolveMarkers(Int)
    case unsupportedResolveFrameRate(Int64)
    case unrepresentableMarkerRange
    case unrepresentableFinalCutProTime
    case incompatiblePrimaryFrameRate(Int)

    var errorDescription: String? {
        switch self {
        case .tooManyResolveMarkers(let count):
            "DaVinci Resolve marker EDL supports at most 999 markers; this review has \(count)."
        case .unsupportedResolveFrameRate(let nominalFPS):
            "DaVinci Resolve marker EDL export does not support \(nominalFPS) fps media."
        case .unrepresentableMarkerRange:
            "A comparison marker range exceeds the supported frame range. Check the review’s frame positions before exporting again."
        case .unrepresentableFinalCutProTime:
            "A comparison marker exceeds the supported Final Cut Pro time range at source A's frame rate. Check the review's frame positions before exporting again."
        case .incompatiblePrimaryFrameRate(let marker):
            "Review marker \(marker) was captured at a different source A frame rate. Load media at the original review frame rate before exporting editor markers. CSV and PDF reports remain available; markers are not automatically retimed."
        }
    }
}

nonisolated struct CompareReviewReportRow: Equatable, Sendable {
    let markerNumber: Int
    let primarySourceTimecode: String?
    let primaryRelativeTimecode: String
    let primaryFrame: Int64
    let primaryRateNumerator: Int64
    let primaryRateDenominator: Int64
    let primaryTime: TimeInterval
    let secondarySourceTimecode: String?
    let secondaryRelativeTimecode: String
    let secondaryFrame: Int64
    let secondaryRateNumerator: Int64
    let secondaryRateDenominator: Int64
    let secondaryTime: TimeInterval
    let note: String
    let primaryEndFrame: Int64?
    let severity: CompareReviewSeverity
    let category: CompareReviewCategory
    let status: CompareReviewStatus

    var classificationLabel: String {
        "Severity: \(severity.title) | Category: \(category.title) | Status: \(status.title)"
    }

    var rangeLabel: String? {
        primaryEndFrame.map { "A frames \(primaryFrame)–\($0) (inclusive)" }
    }
    let createdAt: Date
    let updatedAt: Date
}

/// An immutable snapshot keeps a report internally consistent even if the
/// user edits notes or replaces source B while the save panel is open.
nonisolated struct CompareReviewReportSnapshot: Equatable, Sendable {
    let primaryURL: URL
    let secondaryURL: URL
    let primaryFilename: String
    let secondaryFilename: String
    let primaryTechnicalLines: [String]
    let secondaryTechnicalLines: [String]
    let alignmentLabel: String
    let primaryRateNumerator: Int64
    let primaryRateDenominator: Int64
    let primaryStartFrame: Int64
    let primaryDurationFrames: Int64
    let primaryUsesDropFrame: Bool
    let rows: [CompareReviewReportRow]

    @MainActor
    init(
        primaryItem: MediaItem,
        secondaryItem: MediaItem,
        alignmentMode: CompareAlignmentMode,
        notes: [CompareReviewNote]
    ) {
        primaryURL = primaryItem.url
        secondaryURL = secondaryItem.url
        primaryFilename = primaryItem.url.lastPathComponent
        secondaryFilename = secondaryItem.url.lastPathComponent
        primaryTechnicalLines = ComparisonStillSourceDetails.technicalLines(
            for: CompareMediaDescriptor(item: primaryItem)
        )
        secondaryTechnicalLines = ComparisonStillSourceDetails.technicalLines(
            for: CompareMediaDescriptor(item: secondaryItem)
        )
        alignmentLabel = alignmentMode.label

        let startTimecode = TimecodeFormatter.effectiveStartTimecode(for: primaryItem)
        primaryUsesDropFrame = startTimecode?.contains(";") ?? false
        let rate = TimecodeFormatter.effectiveTimecodeRate(
            for: primaryItem,
            dropFrame: primaryUsesDropFrame
        )
        primaryRateNumerator = rate.numerator
        primaryRateDenominator = rate.denominator
        primaryStartFrame = startTimecode.flatMap(rate.frameCount(forTimecode:)) ?? 0

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
                    frame: note.primaryFrame,
                    numerator: note.primaryRateNumerator,
                    denominator: note.primaryRateDenominator
                ),
                primaryRelativeTimecode: TimecodeRate(
                    numerator: Int(note.primaryRateNumerator),
                    denominator: Int(note.primaryRateDenominator)
                ).timecode(forFrameCount: note.primaryFrame),
                primaryFrame: note.primaryFrame,
                primaryRateNumerator: note.primaryRateNumerator,
                primaryRateDenominator: note.primaryRateDenominator,
                primaryTime: ComparisonStillFrameExtractor.clampedTime(
                    primaryTime,
                    for: primaryItem
                ),
                secondarySourceTimecode: Self.sourceTimecode(
                    item: secondaryItem,
                    frame: note.secondaryFrame,
                    numerator: note.secondaryRateNumerator,
                    denominator: note.secondaryRateDenominator
                ),
                secondaryRelativeTimecode: TimecodeRate(
                    numerator: Int(note.secondaryRateNumerator),
                    denominator: Int(note.secondaryRateDenominator)
                ).timecode(forFrameCount: note.secondaryFrame),
                secondaryFrame: note.secondaryFrame,
                secondaryRateNumerator: note.secondaryRateNumerator,
                secondaryRateDenominator: note.secondaryRateDenominator,
                secondaryTime: ComparisonStillFrameExtractor.clampedTime(
                    secondaryTime,
                    for: secondaryItem
                ),
                note: note.text,
                primaryEndFrame: note.primaryEndFrame,
                severity: note.severity,
                category: note.category,
                status: note.status,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt
            )
        }

        let durationFrames = Int64(
            (max(0, primaryItem.durationSeconds) * rate.value).rounded(.up)
        )
        let finalMarkerFrame = rows.map { $0.primaryEndFrame ?? $0.primaryFrame }.max().map {
            $0 == Int64.max ? Int64.max : $0 + 1
        } ?? 0
        primaryDurationFrames = max(1, durationFrames, finalMarkerFrame)
    }

    @MainActor
    private static func sourceTimecode(
        item: MediaItem,
        frame: Int64,
        numerator: Int64,
        denominator: Int64
    ) -> String? {
        guard let start = TimecodeFormatter.effectiveStartTimecode(for: item) else { return nil }
        let rate = TimecodeFormatter.effectiveTimecodeRate(for: item, dropFrame: start.contains(";"))
        let storedRate = TimecodeRate(numerator: Int(numerator), denominator: Int(denominator))
        // A replacement's metadata cannot establish a source timecode for a
        // marker captured on another timebase. Keep its original relative TC.
        guard rate.numerator == storedRate.numerator,
              rate.denominator == storedRate.denominator,
              let startFrame = rate.frameCount(forTimecode: start) else { return nil }
        let (sourceFrame, overflow) = startFrame.addingReportingOverflow(frame)
        guard !overflow else { return nil }
        return rate.timecode(forFrameCount: sourceFrame)
    }
}

nonisolated enum CompareReviewReportExporter {
    typealias FrameImageProvider = @Sendable (URL, TimeInterval) async throws -> CGImage

    private struct FramePair: Hashable {
        let primaryTime: TimeInterval
        let secondaryTime: TimeInterval
        let primaryTimecode: String
        let secondaryTimecode: String
    }

    /// PDF stills are prepared asynchronously and compressed before the
    /// synchronous Core Graphics renderer sees them. This bounds memory for
    /// long reviews while preserving the same cross-backend extraction path
    /// used by the standalone comparison-still export.
    static func annotatedStillData(
        snapshot: CompareReviewReportSnapshot,
        frameImageProvider: @escaping FrameImageProvider = ComparisonStillFrameExtractor.image
    ) async throws -> [Int: Data] {
        var results: [Int: Data] = [:]
        var cache: [FramePair: Data] = [:]
        results.reserveCapacity(snapshot.rows.count)

        for row in snapshot.rows {
            try Task.checkCancellation()
            let pair = FramePair(
                primaryTime: row.primaryTime,
                secondaryTime: row.secondaryTime,
                primaryTimecode: reportTimecode(source: row.primarySourceTimecode, relative: row.primaryRelativeTimecode),
                secondaryTimecode: reportTimecode(source: row.secondarySourceTimecode, relative: row.secondaryRelativeTimecode)
            )
            if let cached = cache[pair] {
                results[row.markerNumber] = cached
                continue
            }

            let primaryImage = try await frameImageProvider(
                snapshot.primaryURL,
                row.primaryTime
            )
            try Task.checkCancellation()
            let secondaryImage = try await frameImageProvider(
                snapshot.secondaryURL,
                row.secondaryTime
            )
            try Task.checkCancellation()

            let details = ComparisonStillDetails(
                primary: ComparisonStillSourceDetails(
                    filename: snapshot.primaryFilename,
                    timecode: reportTimecode(
                        source: row.primarySourceTimecode,
                        relative: row.primaryRelativeTimecode
                    ),
                    technicalLines: snapshot.primaryTechnicalLines
                ),
                secondary: ComparisonStillSourceDetails(
                    filename: snapshot.secondaryFilename,
                    timecode: reportTimecode(
                        source: row.secondarySourceTimecode,
                        relative: row.secondaryRelativeTimecode
                    ),
                    technicalLines: snapshot.secondaryTechnicalLines
                ),
                alignmentLabel: snapshot.alignmentLabel
            )
            let image = try ComparisonStillRenderer.render(
                primaryImage: primaryImage,
                secondaryImage: secondaryImage,
                details: details,
                maximumPanelWidth: ComparisonStillLayout.minimumPanelWidth,
                maximumImageHeight: 360
            )
            let data = try ComparisonStillRenderer.jpegData(image)
            cache[pair] = data
            results[row.markerNumber] = data
        }
        return results
    }

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
        "Severity",
        "Category",
        "Status",
        "A End Frame (Inclusive)",
        "A Rate Numerator",
        "A Rate Denominator",
        "B Rate Numerator",
        "B Rate Denominator",
        "Source A URL",
        "Source B URL",
    ]

    static func data(
        for format: CompareReviewReportFormat,
        snapshot: CompareReviewReportSnapshot,
        annotatedStills: [Int: Data] = [:]
    ) throws -> Data {
        switch format {
        case .csv:
            Data(csv(snapshot: snapshot).utf8)
        case .pdf:
            try CompareReviewPDFRenderer.render(
                snapshot: snapshot,
                annotatedStills: annotatedStills
            )
        case .resolveMarkersEDL:
            Data(try resolveMarkersEDL(snapshot: snapshot).utf8)
        case .finalCutProXML:
            Data(try finalCutProXML(snapshot: snapshot).utf8)
        case .avidMarkersText:
            Data(try avidMarkersText(snapshot: snapshot).utf8)
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
                row.severity.title,
                row.category.title,
                row.status.title,
                row.primaryEndFrame.map(String.init) ?? "",
                String(row.primaryRateNumerator),
                String(row.primaryRateDenominator),
                String(row.secondaryRateNumerator),
                String(row.secondaryRateDenominator),
                snapshot.primaryURL.absoluteString,
                snapshot.secondaryURL.absoluteString,
            ])
        }

        return records
            .map { $0.map(escapedCSVField).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// Resolve's marker-EDL extension uses CMX events with marker
    /// metadata in comments. The target timeline must use source A's rate.
    static func resolveMarkersEDL(snapshot: CompareReviewReportSnapshot) throws -> String {
        let rate = TimecodeRate(
            numerator: Int(snapshot.primaryRateNumerator),
            denominator: Int(snapshot.primaryRateDenominator),
            dropFrame: snapshot.primaryUsesDropFrame
        )
        guard snapshot.rows.count <= 999 else {
            throw CompareReviewReportExportError.tooManyResolveMarkers(snapshot.rows.count)
        }
        guard rate.nominalFPS <= 60 else {
            throw CompareReviewReportExportError.unsupportedResolveFrameRate(rate.nominalFPS)
        }
        var lines = [
            "TITLE: \(edlText("\(snapshot.primaryFilename) vs \(snapshot.secondaryFilename) Review"))",
            "FCM: \(snapshot.primaryUsesDropFrame ? "DROP FRAME" : "NON-DROP FRAME")",
            "",
        ]

        for row in snapshot.rows {
            let durationFrames = try markerDurationFrames(row)
            let (markerFrame, startOverflow) = snapshot.primaryStartFrame.addingReportingOverflow(row.primaryFrame)
            let (endFrame, endOverflow) = markerFrame.addingReportingOverflow(durationFrames)
            guard !startOverflow, !endOverflow else {
                throw CompareReviewReportExportError.unrepresentableMarkerRange
            }
            let input = rate.timecode(forFrameCount: markerFrame)
            let output = rate.timecode(forFrameCount: endFrame)
            lines.append(String(
                format: "%03d  001      V     C        %@ %@ %@ %@",
                row.markerNumber,
                input,
                output,
                input,
                output
            ))
            lines.append(
                " |C:ResolveColorBlue |M:\(edlText(markerNote(row: row, snapshot: snapshot))) |D:\(durationFrames)"
            )
            lines.append("")
        }
        try validateEditorMarkerRates(snapshot)
        return lines.joined(separator: "\r\n")
    }

    /// Avid's marker interchange is a tab-delimited, frame-addressed format.
    static func avidMarkersText(snapshot: CompareReviewReportSnapshot) throws -> String {
        try validateEditorMarkerRates(snapshot)
        return snapshot.rows.map { row in
            [
                "Aagedal",
                String(row.primaryFrame),
                "V1",
                "blue",
                avidText(markerNote(row: row, snapshot: snapshot)),
            ].joined(separator: "\t")
        }.joined(separator: "\r\n") + "\r\n"
    }

    /// FCPXML browser-clip markers stay attached to source A and use rational
    /// time values so fractional rates never pass through floating point.
    static func finalCutProXML(snapshot: CompareReviewReportSnapshot) throws -> String {
        let frameDuration = try rationalTime(
            frames: 1,
            rateNumerator: snapshot.primaryRateNumerator,
            rateDenominator: snapshot.primaryRateDenominator
        )
        let sourceStart = try rationalTime(
            frames: snapshot.primaryStartFrame,
            rateNumerator: snapshot.primaryRateNumerator,
            rateDenominator: snapshot.primaryRateDenominator
        )
        let duration = try rationalTime(
            frames: snapshot.primaryDurationFrames,
            rateNumerator: snapshot.primaryRateNumerator,
            rateDenominator: snapshot.primaryRateDenominator
        )
        let reviewName = "\(snapshot.primaryFilename) vs \(snapshot.secondaryFilename) Review"

        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE fcpxml>",
            "<fcpxml version=\"1.9\">",
            "  <resources>",
            "    <format id=\"r1\" frameDuration=\"\(frameDuration)\"/>",
            "    <asset id=\"r2\" name=\"\(xmlAttribute(snapshot.primaryFilename))\" start=\"\(sourceStart)\" duration=\"\(duration)\" hasVideo=\"1\" format=\"r1\">",
            "      <media-rep kind=\"original-media\" src=\"\(xmlAttribute(snapshot.primaryURL.absoluteString))\"/>",
            "    </asset>",
            "  </resources>",
            "  <event name=\"Aagedal Compare Review\">",
            "    <asset-clip name=\"\(xmlAttribute(reviewName))\" ref=\"r2\" format=\"r1\" start=\"\(sourceStart)\" duration=\"\(duration)\" tcFormat=\"\(snapshot.primaryUsesDropFrame ? "DF" : "NDF")\">",
        ]

        for row in snapshot.rows {
            let (markerFrame, overflow) = snapshot.primaryStartFrame.addingReportingOverflow(row.primaryFrame)
            guard !overflow else {
                throw CompareReviewReportExportError.unrepresentableFinalCutProTime
            }
            let markerStart = try rationalTime(
                frames: markerFrame,
                rateNumerator: snapshot.primaryRateNumerator,
                rateDenominator: snapshot.primaryRateDenominator
            )
            let markerDuration = try rationalTime(
                frames: markerDurationFrames(row),
                rateNumerator: snapshot.primaryRateNumerator,
                rateDenominator: snapshot.primaryRateDenominator
            )
            lines.append(
                "      <marker start=\"\(markerStart)\" duration=\"\(markerDuration)\" value=\"QC \(String(format: "%03d", row.markerNumber))\" note=\"\(xmlAttribute(markerNote(row: row, snapshot: snapshot)))\"/>"
            )
        }

        lines.append(contentsOf: [
            "    </asset-clip>",
            "  </event>",
            "</fcpxml>",
            "",
        ])
        try validateEditorMarkerRates(snapshot)
        return lines.joined(separator: "\n")
    }

    /// Stored frames can only be emitted unchanged on an equivalent timebase.
    /// Reduce each ratio separately to avoid overflowing cross multiplication.
    private static func validateEditorMarkerRates(_ snapshot: CompareReviewReportSnapshot) throws {
        let currentDivisor = greatestCommonDivisor(snapshot.primaryRateNumerator, snapshot.primaryRateDenominator)
        let numerator = snapshot.primaryRateNumerator / currentDivisor
        let denominator = snapshot.primaryRateDenominator / currentDivisor
        for row in snapshot.rows {
            let divisor = greatestCommonDivisor(row.primaryRateNumerator, row.primaryRateDenominator)
            guard row.primaryRateNumerator / divisor == numerator,
                  row.primaryRateDenominator / divisor == denominator else {
                throw CompareReviewReportExportError.incompatiblePrimaryFrameRate(row.markerNumber)
            }
        }
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

    private static func markerNote(
        row: CompareReviewReportRow,
        snapshot: CompareReviewReportSnapshot
    ) -> String {
        let secondaryTimecode = row.secondarySourceTimecode ?? row.secondaryRelativeTimecode
        return "\(row.note) | Source B: \(snapshot.secondaryFilename), \(secondaryTimecode), frame \(row.secondaryFrame) | Alignment: \(snapshot.alignmentLabel) | \(row.classificationLabel)\(row.rangeLabel.map { " | \($0)" } ?? "")"
    }

    private static func markerDurationFrames(_ row: CompareReviewReportRow) throws -> Int64 {
        guard let end = row.primaryEndFrame else { return 1 }
        let (difference, subtractionOverflow) = end.subtractingReportingOverflow(row.primaryFrame)
        let (duration, additionOverflow) = difference.addingReportingOverflow(1)
        guard !subtractionOverflow, !additionOverflow, duration > 0 else {
            throw CompareReviewReportExportError.unrepresentableMarkerRange
        }
        return duration
    }

    private static func reportTimecode(source: String?, relative: String) -> String {
        "\(source == nil ? "REL TC" : "SRC TC") \(source ?? relative)"
    }

    private static func edlText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "/")
    }

    private static func avidText(_ value: String) -> String {
        String(value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(32_000))
    }

    private static func xmlAttribute(_ value: String) -> String {
        // Pasted notes can contain characters that XML 1.0 cannot represent,
        // even as numeric references. Replace only those scalars, preserving
        // Unicode text and encoding tabs so attribute normalization keeps them.
        let validXML = String(String.UnicodeScalarView(value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                scalar
            default:
                Unicode.Scalar(0xFFFD)!
            }
        }))
        return validXML
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\t", with: "&#9;")
            .replacingOccurrences(of: "\r\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "&#10;")
            .replacingOccurrences(of: "\n", with: "&#10;")
    }

    private static func rationalTime(
        frames: Int64,
        rateNumerator: Int64,
        rateDenominator: Int64
    ) throws -> String {
        // Cancel denominator factors before multiplication: the final rational
        // time may fit Int64 even when the unreduced intermediate would not.
        let frameCount = max(0, frames)
        let rateDivisor = greatestCommonDivisor(max(1, rateDenominator), max(1, rateNumerator))
        let scale = max(1, rateDenominator) / rateDivisor
        let denominator = max(1, rateNumerator) / rateDivisor
        let frameDivisor = greatestCommonDivisor(frameCount, denominator)
        let (numerator, overflow) = (frameCount / frameDivisor).multipliedReportingOverflow(by: scale)
        guard !overflow else {
            throw CompareReviewReportExportError.unrepresentableFinalCutProTime
        }
        return "\(numerator)/\(denominator / frameDivisor)s"
    }

    private static func greatestCommonDivisor(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }

    private static func sanitizedFilenameStem(_ filename: String) -> String {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let sanitized = stem
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "Untitled" : sanitized).prefix(60))
    }
}
