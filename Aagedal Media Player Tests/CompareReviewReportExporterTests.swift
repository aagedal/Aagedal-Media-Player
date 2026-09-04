// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareReviewReportExporterTests: XCTestCase {
    func testCSVSortsMarkersAndEscapesMultilineUnicodeNotes() {
        let primary = makeItem(
            path: "/tmp/Master, final.mov",
            duration: 10,
            startTimecode: "01:00:00:00"
        )
        let secondary = makeItem(
            path: "/tmp/Encode.mp4",
            duration: 10,
            startTimecode: nil
        )
        let later = CompareReviewNote(
            primaryFrame: 60,
            primaryTime: 2,
            secondaryFrame: 90,
            secondaryTime: 3,
            text: "Later"
        )
        let earlier = CompareReviewNote(
            primaryFrame: 30,
            primaryTime: 1,
            secondaryFrame: 60,
            secondaryTime: 2,
            text: "Quote \"one\", line\nblå",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.123),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001.456)
        )
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primary,
            secondaryItem: secondary,
            alignmentMode: .sourceTimecode,
            notes: [later, earlier]
        )

        let csv = CompareReviewReportExporter.csv(snapshot: snapshot)
        let lines = csv.components(separatedBy: "\r\n")

        XCTAssertEqual(lines[0], CompareReviewReportExporter.csvColumns.joined(separator: ","))
        XCTAssertTrue(lines[1].hasPrefix("1,\"Master, final.mov\",Encode.mp4,Source timecode,01:00:01:00,00:00:01:00,30,,00:00:02:00,60,"))
        XCTAssertTrue(csv.contains("\"Quote \"\"one\"\", line\nblå\""))
        XCTAssertTrue(csv.contains("2023-11-14T22:13:20.123Z"))
        XCTAssertTrue(lines[2].hasPrefix("2,"), "Embedded LF must not become a CRLF record break")
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testCSVDataAndPreferredFilenameAreDeterministic() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master: V2.mov", duration: 5),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .relative,
            notes: [CompareReviewNote(
                primaryFrame: 0,
                primaryTime: 0,
                secondaryFrame: 0,
                secondaryTime: 0,
                text: "Start"
            )]
        )

        XCTAssertEqual(
            String(
                decoding: try CompareReviewReportExporter.data(for: .csv, snapshot: snapshot),
                as: UTF8.self
            ),
            CompareReviewReportExporter.csv(snapshot: snapshot)
        )
        XCTAssertEqual(
            CompareReviewReportExporter.preferredFilename(for: .csv, snapshot: snapshot),
            "Master- V2_vs_Encode_review.csv"
        )
    }

    func testPDFDataIsReadableAndUsesPreferredFilename() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .relative,
            notes: [CompareReviewNote(
                primaryFrame: 0,
                primaryTime: 0,
                secondaryFrame: 0,
                secondaryTime: 0,
                text: "Check the opening frame — blå"
            )]
        )

        let data = try CompareReviewReportExporter.data(for: .pdf, snapshot: snapshot)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(
            CompareReviewReportExporter.preferredFilename(for: .pdf, snapshot: snapshot),
            "Master_vs_Encode_review.pdf"
        )
    }

    func testPDFPaginatesLargeReports() throws {
        let notes = (0..<80).map { index in
            CompareReviewNote(
                primaryFrame: Int64(index),
                primaryTime: Double(index) / 30,
                secondaryFrame: Int64(index),
                secondaryTime: Double(index) / 30,
                text: "Marker \(index): inspect compression detail and color continuity."
            )
        }
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .sourceTimecode,
            notes: notes
        )

        let data = try CompareReviewReportExporter.data(for: .pdf, snapshot: snapshot)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))

        XCTAssertGreaterThan(document.numberOfPages, 1)
    }

    private func makeItem(
        path: String,
        duration: TimeInterval,
        startTimecode: String? = nil
    ) -> MediaItem {
        let metadata = MediaMetadata(
            duration: duration,
            formatName: nil,
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: startTimecode,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [],
            subtitleStreams: [],
            chapters: []
        )
        return MediaItem(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            size: 1,
            durationSeconds: duration,
            metadata: metadata
        )
    }
}
