// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import ImageIO
import PDFKit
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareReviewReportExporterTests: XCTestCase {
    func testReportTimecodesPreserveStoredFramesBeyondReplacementDuration() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 1, startTimecode: "01:00:00:00", frameRate: "24000/1001"),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 1, startTimecode: "02:00:00;00", frameRate: "30000/1001"),
            alignmentMode: .sourceTimecode,
            notes: [CompareReviewNote(
                primaryFrame: 48, primaryTime: 0, secondaryFrame: 1_800, secondaryTime: 0,
                primaryRateNumerator: 24_000, primaryRateDenominator: 1_001,
                secondaryRateNumerator: 30_000, secondaryRateDenominator: 1_001,
                text: "Retain recorded coordinates"
            )]
        )
        let row = try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(row.primaryRelativeTimecode, "00:00:02:00")
        XCTAssertEqual(row.primarySourceTimecode, "01:00:02:00")
        XCTAssertEqual(row.secondaryRelativeTimecode, "00:01:00:00")
        XCTAssertEqual(row.secondarySourceTimecode, "02:01:00;02")
        XCTAssertEqual(row.primaryTime, 2.002, accuracy: 0.000_001)
        XCTAssertEqual(row.secondaryTime, 60.06, accuracy: 0.000_001)
        XCTAssertFalse(row.hasAvailableStillFrames)
    }

    func testAnnotatedStillsSkipUnavailablePairsAndPreserveReportText() async throws {
        let notes = [Int64(29), 30, 60].map { frame in
            CompareReviewNote(
                primaryFrame: frame, primaryTime: 0, secondaryFrame: frame, secondaryTime: 0,
                text: "Finding at frame \(frame)"
            )
        }
        // Test availability independently for each member of the pair.
        for (primaryDuration, secondaryDuration) in [(1.0, 3.0), (3.0, 1.0)] {
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: makeItem(path: "/tmp/Master.mov", duration: primaryDuration),
                secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: secondaryDuration),
                alignmentMode: .relative, notes: notes
            )
            let recorder = ReportFrameRequestRecorder()
            let frameImage = try makeSolidImage(red: 1, green: 0, blue: 0)
            let stills = try await CompareReviewReportExporter.annotatedStillData(snapshot: snapshot) { url, time in
                await recorder.record(url: url, time: time)
                return frameImage
            }
            XCTAssertEqual(Set(stills.keys), [1])
            let requests = await recorder.requests
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(requests.allSatisfy { abs($0.time - 29.0 / 30.0) < 0.000_001 })
            let pdf = try XCTUnwrap(PDFDocument(data: CompareReviewReportExporter.data(
                for: .pdf, snapshot: snapshot, annotatedStills: stills
            )))
            let reportText = try XCTUnwrap(pdf.string)
            XCTAssertTrue(reportText.contains("Finding at frame 30"))
            XCTAssertTrue(reportText.contains("Finding at frame 60"))
            XCTAssertTrue(reportText.contains("Still unavailable:"))
        }
    }

    func testResolveEDLRejectsMidnightWrapIncludingExclusiveEndpoint() throws {
        for (frameRate, startTimecode, numerator, denominator, lastFrame): (String, String, Int64, Int64, Int64) in [
            ("30/1", "23:59:59:00", 30, 1, 29),
            ("30000/1001", "23:59:59;00", 30_000, 1_001, 29),
            ("60000/1001", "23:59:59;00", 60_000, 1_001, 59),
        ] {
            for (frame, endFrame, isRepresentable): (Int64, Int64?, Bool) in [
                (lastFrame - 1, nil, true), (lastFrame, nil, false),
                (lastFrame + 1, nil, false), (lastFrame - 1, lastFrame, false),
            ] {
                let snapshot = CompareReviewReportSnapshot(
                    primaryItem: makeItem(path: "/tmp/Master.mov", duration: 10, startTimecode: startTimecode, frameRate: frameRate),
                    secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 10),
                    alignmentMode: .sourceTimecode,
                    notes: [CompareReviewNote(
                        primaryFrame: frame, primaryTime: 0, secondaryFrame: 0, secondaryTime: 0,
                        primaryRateNumerator: numerator, primaryRateDenominator: denominator,
                        text: "Near midnight", primaryEndFrame: endFrame
                    )]
                )
                if isRepresentable {
                    XCTAssertNoThrow(try CompareReviewReportExporter.resolveMarkersEDL(snapshot: snapshot))
                } else {
                    XCTAssertThrowsError(try CompareReviewReportExporter.resolveMarkersEDL(snapshot: snapshot)) { error in
                        guard case CompareReviewReportExportError.resolveTimecodeWrap(1) = error else {
                            return XCTFail("Expected actionable midnight-wrap error, got \(error)")
                        }
                    }
                    // Formats with rational times or absolute frames keep the position.
                    XCTAssertNoThrow(try CompareReviewReportExporter.finalCutProXML(snapshot: snapshot))
                    XCTAssertNoThrow(try CompareReviewReportExporter.avidMarkersText(snapshot: snapshot))
                }
            }
        }
    }

    func testReportsDoNotInventSourceTimecodesFromChangedRates() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 20, startTimecode: "01:00:00:00", frameRate: "30/1"),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 20, startTimecode: "02:00:00:00", frameRate: "24/1"),
            alignmentMode: .sourceTimecode,
            notes: [CompareReviewNote(
                primaryFrame: 240, primaryTime: 0, secondaryFrame: 300, secondaryTime: 0,
                primaryRateNumerator: 24, secondaryRateNumerator: 30,
                text: "Original capture rates"
            )]
        )
        let row = try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(row.primaryRelativeTimecode, "00:00:10:00")
        XCTAssertEqual(row.secondaryRelativeTimecode, "00:00:10:00")
        XCTAssertNil(row.primarySourceTimecode)
        XCTAssertNil(row.secondarySourceTimecode)
        let csv = CompareReviewReportExporter.csv(snapshot: snapshot)
        XCTAssertTrue(csv.contains(",,00:00:10:00,240,,00:00:10:00,300,"))
    }

    func testEditorExportsRejectChangedPrimaryRateWithoutRetimingReports() throws {
        for storedRate: (Int64, Int64) in [(24, 1), (30_000, 1_001)] {
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: makeItem(path: "/tmp/Replacement.mov", duration: 20),
                secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 20),
                alignmentMode: .relative,
                notes: [CompareReviewNote(
                    primaryFrame: 240, primaryTime: 0, secondaryFrame: 240, secondaryTime: 8,
                    primaryRateNumerator: storedRate.0, primaryRateDenominator: storedRate.1,
                    text: "Original-rate finding", primaryEndFrame: 263
                )]
            )
            for format: CompareReviewReportFormat in [.resolveMarkersEDL, .finalCutProXML, .avidMarkersText] {
                XCTAssertThrowsError(try CompareReviewReportExporter.data(for: format, snapshot: snapshot)) { error in
                    guard case CompareReviewReportExportError.incompatiblePrimaryFrameRate(1) = error else {
                        return XCTFail("Expected frame-rate mismatch for \(format), got \(error)")
                    }
                    XCTAssertTrue(error.localizedDescription.contains("original review frame rate"))
                }
            }
            XCTAssertEqual(snapshot.rows.first?.primaryFrame, 240)
            XCTAssertEqual(try XCTUnwrap(snapshot.rows.first).primaryTime, 240 * Double(storedRate.1) / Double(storedRate.0), accuracy: 0.000_001)
            XCTAssertNoThrow(try CompareReviewReportExporter.data(for: .csv, snapshot: snapshot))
            XCTAssertNoThrow(try CompareReviewReportExporter.data(for: .pdf, snapshot: snapshot))
        }
    }

    func testEditorExportsAcceptEquivalentRationalPrimaryRates() throws {
        for (currentRate, numerator, denominator): (String, Int64, Int64) in [
            ("30000/1001", 60_000, 2_002),
            // Cross multiplication of this equivalent 30 fps ratio would overflow.
            ("30/1", 9_000_000_000_000_000_000, 300_000_000_000_000_000),
        ] {
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: makeItem(path: "/tmp/Master.mov", duration: 20, frameRate: currentRate),
                secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 20),
                alignmentMode: .relative,
                notes: [CompareReviewNote(
                    primaryFrame: 240, primaryTime: 0, secondaryFrame: 240, secondaryTime: 8,
                    primaryRateNumerator: numerator, primaryRateDenominator: denominator,
                    text: "Equivalent-rate finding"
                )]
            )
            for format: CompareReviewReportFormat in [.resolveMarkersEDL, .finalCutProXML, .avidMarkersText] {
                XCTAssertNoThrow(try CompareReviewReportExporter.data(for: format, snapshot: snapshot))
            }
        }
    }

    func testAnnotatedStillCacheSeparatesIdenticalFrameNumbersAtDifferentStoredRates() async throws {
        let primary = makeItem(path: "/tmp/Master.mov", duration: 10)
        let secondary = makeItem(path: "/tmp/Encode.mp4", duration: 10)
        let notes = [Int64(24), 30].map { rate in
            CompareReviewNote(
                primaryFrame: 24, primaryTime: 0, secondaryFrame: 24, secondaryTime: 0,
                primaryRateNumerator: rate, secondaryRateNumerator: rate, text: "Rate \(rate)"
            )
        }
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primary, secondaryItem: secondary, alignmentMode: .relative, notes: notes
        )
        let recorder = ReportFrameRequestRecorder()
        let red = try makeSolidImage(red: 1, green: 0, blue: 0)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1)
        let stills = try await CompareReviewReportExporter.annotatedStillData(snapshot: snapshot) { url, time in
            await recorder.record(url: url, time: time)
            return time > 0.9 ? red : blue
        }
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.filter { $0.url == primary.url }.map(\.time).sorted(), [0.8, 1])
        XCTAssertEqual(requests.filter { $0.url == secondary.url }.map(\.time).sorted(), [0.8, 1])
        XCTAssertEqual(stills.count, 2)
        XCTAssertNotEqual(stills[1], stills[2])
    }

    func testCSVPreservesStoredRationalRatesAndDistinguishesSameNamedSources() throws {
        let primary = makeItem(path: "/tmp/original/Master.mov", duration: 20, frameRate: "30/1")
        let secondary = makeItem(path: "/tmp/replacement/Master.mov", duration: 20, frameRate: "30/1")
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primary,
            secondaryItem: secondary,
            alignmentMode: .relative,
            notes: [CompareReviewNote(
                primaryFrame: 240, primaryTime: 0,
                secondaryFrame: 600, secondaryTime: 0,
                primaryRateNumerator: 24_000, primaryRateDenominator: 1_001,
                secondaryRateNumerator: 60_000, secondaryRateDenominator: 1_001,
                text: "Original capture rates survive replacement metadata"
            )]
        )
        let csv = CompareReviewReportExporter.csv(snapshot: snapshot)
        let records = csv.components(separatedBy: "\r\n")
        let headings = records[0].components(separatedBy: ",")
        let fields = records[1].components(separatedBy: ",")
        XCTAssertEqual(fields.count, headings.count)
        let values = Dictionary(uniqueKeysWithValues: zip(headings, fields))
        XCTAssertEqual(values["A Rate Numerator"], "24000")
        XCTAssertEqual(values["A Rate Denominator"], "1001")
        XCTAssertEqual(values["B Rate Numerator"], "60000")
        XCTAssertEqual(values["B Rate Denominator"], "1001")
        XCTAssertEqual(values["Source A URL"], primary.url.absoluteString)
        XCTAssertEqual(values["Source B URL"], secondary.url.absoluteString)
        XCTAssertNotEqual(values["Source A URL"], values["Source B URL"])
        XCTAssertEqual(values["A Frame"], "240")
        XCTAssertEqual(values["B Frame"], "600")
    }

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

    func testAnnotatedStillPreparationUsesStoredFrameTimesAndCachesDuplicatePairs() async throws {
        let primary = makeItem(
            path: "/tmp/Master.mov",
            duration: 10,
            startTimecode: "01:00:00:00",
            frameRate: "24000/1001"
        )
        let secondary = makeItem(
            path: "/tmp/Encode.mp4",
            duration: 10,
            frameRate: "30000/1001"
        )
        let notes = ["First", "Same frame, second note"].map { text in
            CompareReviewNote(
                primaryFrame: 24,
                primaryTime: 0,
                secondaryFrame: 30,
                secondaryTime: 0,
                primaryRateNumerator: 24_000,
                primaryRateDenominator: 1_001,
                secondaryRateNumerator: 30_000,
                secondaryRateDenominator: 1_001,
                text: text
            )
        }
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primary,
            secondaryItem: secondary,
            alignmentMode: .sourceTimecode,
            notes: notes
        )
        let recorder = ReportFrameRequestRecorder()
        let red = try makeSolidImage(red: 1, green: 0, blue: 0)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1)
        let primaryURL = primary.url

        let stills = try await CompareReviewReportExporter.annotatedStillData(
            snapshot: snapshot
        ) { url, time in
            await recorder.record(url: url, time: time)
            return url == primaryURL ? red : blue
        }
        let requests = await recorder.requests

        XCTAssertEqual(stills.count, 2)
        XCTAssertEqual(requests.count, 2, "Duplicate A/B frame pairs should be extracted once")
        XCTAssertEqual(requests[0].url, primary.url)
        XCTAssertEqual(requests[0].time, 1.001, accuracy: 0.000_001)
        XCTAssertEqual(requests[1].url, secondary.url)
        XCTAssertEqual(requests[1].time, 1.001, accuracy: 0.000_001)

        let data = try XCTUnwrap(stills[1])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1_284)
        XCTAssertEqual(image.height, 760)
    }

    func testPDFEmbedsAnnotatedComparisonStill() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .relative,
            notes: [CompareReviewNote(
                primaryFrame: 0,
                primaryTime: 0,
                secondaryFrame: 0,
                secondaryTime: 0,
                text: "Red in A, blue in B"
            )]
        )
        let red = try makeSolidImage(red: 1, green: 0, blue: 0)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1)
        let still = try ComparisonStillRenderer.render(
            primaryImage: red,
            secondaryImage: blue,
            details: ComparisonStillDetails(
                primary: ComparisonStillSourceDetails(
                    filename: "Master.mov",
                    timecode: "REL TC 00:00:00:00",
                    technicalLines: []
                ),
                secondary: ComparisonStillSourceDetails(
                    filename: "Encode.mp4",
                    timecode: "REL TC 00:00:00:00",
                    technicalLines: []
                ),
                alignmentLabel: "Relative start"
            ),
            maximumPanelWidth: ComparisonStillLayout.minimumPanelWidth,
            maximumImageHeight: 360
        )
        let stillData = try ComparisonStillRenderer.jpegData(still, quality: 0.95)

        let pdfData = try CompareReviewReportExporter.data(
            for: .pdf,
            snapshot: snapshot,
            annotatedStills: [1: stillData]
        )
        let provider = try XCTUnwrap(CGDataProvider(data: pdfData as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let colors = rasterizedColorCounts(page: page)

        XCTAssertGreaterThan(colors.red, 1_000)
        XCTAssertGreaterThan(colors.blue, 1_000)
    }

    func testResolveMarkerEDLPreservesDropFrameBoundaryAndSanitizesNote() throws {
        let primary = makeItem(
            path: "/tmp/Master.mov",
            duration: 120,
            startTimecode: "01:00:00;00",
            frameRate: "30000/1001"
        )
        let rate = TimecodeRate(numerator: 30_000, denominator: 1_001, dropFrame: true)
        let start = try XCTUnwrap(rate.frameCount(forTimecode: "01:00:00;00"))
        let marker = try XCTUnwrap(rate.frameCount(forTimecode: "01:00:59;29"))
        let note = CompareReviewNote(
            primaryFrame: marker - start,
            primaryTime: 59.96,
            secondaryFrame: 1_797,
            secondaryTime: 59.96,
            primaryRateNumerator: 30_000,
            primaryRateDenominator: 1_001,
            secondaryRateNumerator: 30_000,
            secondaryRateDenominator: 1_001,
            text: "Check|edge\nnext line"
        )
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primary,
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 120),
            alignmentMode: .sourceTimecode,
            notes: [note]
        )

        let edl = try CompareReviewReportExporter.resolveMarkersEDL(snapshot: snapshot)

        XCTAssertTrue(edl.contains("FCM: DROP FRAME"))
        XCTAssertTrue(edl.contains(
            "01:00:59;29 01:01:00;02 01:00:59;29 01:01:00;02"
        ))
        XCTAssertTrue(edl.contains("|M:Check/edge next line"))
        XCTAssertEqual(
            CompareReviewReportExporter.preferredFilename(
                for: .resolveMarkersEDL,
                snapshot: snapshot
            ),
            "Master_vs_Encode_review.edl"
        )
    }

    func testFinalCutProXMLUsesExactRateAndEscapesComparisonContext() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(
                path: "/tmp/Master & \"approved\".mov",
                duration: 10,
                startTimecode: "01:00:00:00",
                frameRate: "24000/1001"
            ),
            secondaryItem: makeItem(path: "/tmp/Encode & web.mp4", duration: 10),
            alignmentMode: .sourceTimecode,
            notes: [CompareReviewNote(
                primaryFrame: 48,
                primaryTime: 2.002,
                secondaryFrame: 60,
                secondaryTime: 2,
                primaryRateNumerator: 24_000,
                primaryRateDenominator: 1_001,
                text: "Blacks <lifted> & noisy\nCheck again"
            )]
        )

        let xml = try CompareReviewReportExporter.finalCutProXML(snapshot: snapshot)
        let document = try XMLDocument(xmlString: xml)

        XCTAssertEqual(document.rootElement()?.name, "fcpxml")
        XCTAssertTrue(xml.contains("frameDuration=\"1001/24000s\""))
        XCTAssertTrue(xml.contains("start=\"18018/5s\""))
        XCTAssertTrue(xml.contains("Master%20&amp;%20%22approved%22.mov"))
        XCTAssertTrue(xml.contains("Blacks &lt;lifted&gt; &amp; noisy&#10;Check again"))
        XCTAssertEqual(
            try document.nodes(forXPath: "//marker").count,
            1
        )
        XCTAssertEqual(
            CompareReviewReportExporter.preferredFilename(
                for: .finalCutProXML,
                snapshot: snapshot
            ),
            "Master & \"approved\"_vs_Encode & web_review.fcpxml"
        )
    }

    func testFinalCutProXMLPreservesDropFrameMarkerAtMinuteBoundary() throws {
        for (numerator, startFrame, markerFrame) in [
            (Int64(30_000), Int64(107_892), Int64(1_800)),
            (Int64(60_000), Int64(215_784), Int64(3_600)),
        ] {
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: makeItem(
                    path: "/tmp/Master.mov",
                    duration: 120,
                    startTimecode: "01:00:00;00",
                    frameRate: "\(numerator)/1001"
                ),
                secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 120),
                alignmentMode: .sourceTimecode,
                notes: [CompareReviewNote(
                    primaryFrame: markerFrame,
                    primaryTime: 60.06,
                    secondaryFrame: 1_800,
                    secondaryTime: 60,
                    primaryRateNumerator: numerator,
                    primaryRateDenominator: 1_001,
                    text: "First frame after the dropped labels"
                )]
            )
            let document = try XMLDocument(xmlString: CompareReviewReportExporter.finalCutProXML(snapshot: snapshot))
            let clip = try XCTUnwrap(try document.nodes(forXPath: "//asset-clip").first as? XMLElement)
            let marker = try XCTUnwrap(try document.nodes(forXPath: "//marker").first as? XMLElement)
            XCTAssertEqual(clip.attribute(forName: "tcFormat")?.stringValue, "DF")
            XCTAssertEqual(snapshot.primaryStartFrame, startFrame)
            // Both rates describe the same instant, without a decimal-second roundoff.
            XCTAssertEqual(marker.attribute(forName: "start")?.stringValue, "9150141/2500s")
            XCTAssertEqual(snapshot.rows.first?.primarySourceTimecode, numerator == 30_000 ? "01:01:00;02" : "01:01:00;04")
        }
    }

    func testFinalCutProXMLKeepsTabsAndUnicodeWhileReplacingInvalidXMLScalars() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .relative,
            notes: [CompareReviewNote(
                primaryFrame: 0,
                primaryTime: 0,
                secondaryFrame: 0,
                secondaryTime: 0,
                text: "Blå 🎬\tcolumn\r\nnext\u{0}\u{8}\u{FFFE}\u{FFFF}"
            )]
        )
        let document = try XMLDocument(xmlString: CompareReviewReportExporter.finalCutProXML(snapshot: snapshot))
        let marker = try XCTUnwrap(try document.nodes(forXPath: "//marker").first as? XMLElement)
        XCTAssertEqual(
            marker.attribute(forName: "note")?.stringValue,
            "Blå 🎬\tcolumn\nnext���� | Source B: Encode.mp4, 00:00:00:00, frame 0 | Alignment: Relative start | Severity: Info | Category: General | Status: Open"
        )
        let clip = try XCTUnwrap(try document.nodes(forXPath: "//asset-clip").first as? XMLElement)
        XCTAssertEqual(clip.attribute(forName: "tcFormat")?.stringValue, "NDF")
    }

    func testFinalCutProXMLRejectsOverflowAtActualMetadataRate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = makeItem(
            path: directory.appendingPathComponent("Master.mov").path,
            duration: 5,
            startTimecode: "12:00:00:00",
            frameRate: "23987653/1000000"
        )
        let secondary = makeItem(path: directory.appendingPathComponent("Encode.mp4").path, duration: 5)
        // This position fits the sidecar's claimed 1 fps rate, including its
        // 24-hour source-timecode allowance. The actual metadata uses 24 fps
        // labels and therefore a larger nonzero source start.
        let note = CompareReviewNote(
            primaryFrame: Int64.max / 1_000_000 - 86_400 - 1,
            primaryTime: 0, secondaryFrame: 0, secondaryTime: 0,
            primaryRateNumerator: 1, primaryRateDenominator: 1, text: "Oversized"
        )
        let store = CompareReviewSidecarStore()
        let sidecar = directory.appendingPathComponent("review.json")
        try await store.save(
            CompareReviewDocument(primaryURL: primary.url, secondaryURL: secondary.url, notes: [note]),
            to: sidecar, revision: 1
        )
        let loaded = try await store.load(from: sidecar, primaryURL: primary.url, secondaryURL: secondary.url)
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primary, secondaryItem: secondary,
            alignmentMode: .sourceTimecode, notes: try XCTUnwrap(loaded).notes
        )
        XCTAssertThrowsError(try CompareReviewReportExporter.data(for: .finalCutProXML, snapshot: snapshot)) { error in
            guard case CompareReviewReportExportError.unrepresentableFinalCutProTime = error else {
                return XCTFail("Expected actionable export range error, got \(error)")
            }
        }
    }

    func testFinalCutProXMLReducesRationalTimeBeforeMultiplication() throws {
        let numerator: Int64 = 23_987_653
        let denominator: Int64 = 1_000_000
        let wholeRateUnits = Int64.max / denominator / numerator + 1
        let frame = wholeRateUnits * numerator - 1
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(
                path: "/tmp/Master.mov", duration: 5,
                startTimecode: "00:00:00:01", frameRate: "\(numerator)/\(denominator)"
            ),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .sourceTimecode,
            notes: [CompareReviewNote(
                primaryFrame: frame, primaryTime: 0,
                secondaryFrame: 0, secondaryTime: 0,
                primaryRateNumerator: numerator, primaryRateDenominator: denominator,
                text: "Representable after cancellation"
            )]
        )
        let document = try XMLDocument(xmlString: CompareReviewReportExporter.finalCutProXML(snapshot: snapshot))
        let marker = try XCTUnwrap(try document.nodes(forXPath: "//marker").first as? XMLElement)
        XCTAssertEqual(marker.attribute(forName: "start")?.stringValue, "\(wholeRateUnits * denominator)/1s")
    }

    func testAvidMarkersAreTabDelimitedAndUsePrimaryFrameCoordinates() throws {
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .relative,
            notes: [CompareReviewNote(
                primaryFrame: 42,
                primaryTime: 1.4,
                secondaryFrame: 45,
                secondaryTime: 1.5,
                text: "One\ttwo\nthree"
            )]
        )

        let text = try CompareReviewReportExporter.avidMarkersText(snapshot: snapshot)
        let fields = text.dropLast(2).split(separator: "\t", omittingEmptySubsequences: false)

        XCTAssertEqual(fields.count, 5)
        XCTAssertEqual(fields[0], "Aagedal")
        XCTAssertEqual(fields[1], "42")
        XCTAssertEqual(fields[2], "V1")
        XCTAssertEqual(fields[3], "blue")
        XCTAssertTrue(fields[4].contains("One two three"))
        XCTAssertTrue(fields[4].contains("Source B: Encode.mp4"))
    }

    func testResolveMarkerEDLRejectsMoreThan999Markers() {
        let notes = (0..<1_000).map { frame in
            CompareReviewNote(
                primaryFrame: Int64(frame),
                primaryTime: Double(frame) / 30,
                secondaryFrame: Int64(frame),
                secondaryTime: Double(frame) / 30,
                text: "Marker \(frame)"
            )
        }
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 40),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 40),
            alignmentMode: .relative,
            notes: notes
        )

        XCTAssertThrowsError(
            try CompareReviewReportExporter.resolveMarkersEDL(snapshot: snapshot)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "DaVinci Resolve marker EDL supports at most 999 markers; this review has 1000."
            )
        }
    }

    func testRangeAndClassificationArePreservedAcrossReportFormats() throws {
        let note = CompareReviewNote(
            primaryFrame: 48, primaryTime: 2.002,
            secondaryFrame: 60, secondaryTime: 2,
            primaryRateNumerator: 24_000, primaryRateDenominator: 1_001,
            text: "Visible banding",
            severity: .major, category: .picture, status: .inProgress,
            primaryEndFrame: 71
        )
        let snapshot = CompareReviewReportSnapshot(
            primaryItem: makeItem(path: "/tmp/Master.mov", duration: 1, frameRate: "24000/1001"),
            secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
            alignmentMode: .relative, notes: [note]
        )
        XCTAssertEqual(snapshot.primaryDurationFrames, 72, "Asset duration must include the last range frame")
        let row = try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(row.primaryEndFrame, 71)
        XCTAssertEqual(row.severity, .major)
        XCTAssertEqual(row.category, .picture)
        XCTAssertEqual(row.status, .inProgress)

        let csv = CompareReviewReportExporter.csv(snapshot: snapshot)
        XCTAssertTrue(csv.contains("Updated,Severity,Category,Status,A End Frame (Inclusive)"))
        XCTAssertTrue(csv.contains(",Major,Picture,In Progress,71,24000,1001,30,1,"))

        let edl = try CompareReviewReportExporter.resolveMarkersEDL(snapshot: snapshot)
        XCTAssertTrue(edl.contains("00:00:02:00 00:00:03:00 00:00:02:00 00:00:03:00"))
        XCTAssertTrue(edl.contains("|D:24"))
        XCTAssertTrue(edl.contains("Severity: Major / Category: Picture / Status: In Progress"))

        let xml = try XMLDocument(xmlString: CompareReviewReportExporter.finalCutProXML(snapshot: snapshot))
        let marker = try XCTUnwrap(try xml.nodes(forXPath: "//marker").first as? XMLElement)
        XCTAssertEqual(marker.attribute(forName: "start")?.stringValue, "1001/500s")
        XCTAssertEqual(marker.attribute(forName: "duration")?.stringValue, "1001/1000s")
        XCTAssertTrue(marker.attribute(forName: "note")?.stringValue?.contains(row.classificationLabel) == true)

        let avid = try CompareReviewReportExporter.avidMarkersText(snapshot: snapshot)
        XCTAssertTrue(avid.contains("A frames 48–71 (inclusive)"))
        XCTAssertTrue(avid.contains(row.classificationLabel))
        XCTAssertEqual(avid.dropLast(2).split(separator: "\t").count, 5)

        let pdf = try XCTUnwrap(PDFDocument(data: CompareReviewReportExporter.data(for: .pdf, snapshot: snapshot)))
        let pdfText = try XCTUnwrap(pdf.string)
        XCTAssertTrue(pdfText.contains("Severity: Major"))
        XCTAssertTrue(pdfText.contains("Category: Picture"))
        XCTAssertTrue(pdfText.contains("Status: In Progress"))
        XCTAssertTrue(pdfText.contains("A frames 48–71 (inclusive)"))
    }

    func testPointAndSingleFrameRangeKeepOneFrameMarkerDuration() throws {
        for endFrame: Int64? in [nil, 48] {
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5, frameRate: "24000/1001"),
                secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
                alignmentMode: .relative,
                notes: [CompareReviewNote(
                    primaryFrame: 48, primaryTime: 2.002,
                    secondaryFrame: 60, secondaryTime: 2,
                    primaryRateNumerator: 24_000, primaryRateDenominator: 1_001,
                    text: "One frame", primaryEndFrame: endFrame
                )]
            )
            let xml = try XMLDocument(xmlString: CompareReviewReportExporter.finalCutProXML(snapshot: snapshot))
            let marker = try XCTUnwrap(try xml.nodes(forXPath: "//marker").first as? XMLElement)
            XCTAssertEqual(marker.attribute(forName: "duration")?.stringValue, "1001/24000s")
            XCTAssertTrue(try CompareReviewReportExporter.resolveMarkersEDL(snapshot: snapshot).contains("|D:1"))
            let row = try XCTUnwrap(snapshot.rows.first)
            XCTAssertEqual(row.severity, .info)
            XCTAssertEqual(row.category, .general)
            XCTAssertEqual(row.status, .open)
        }
    }

    func testRangeExportRejectsReversedAndOverflowingDurations() {
        for endFrame in [Int64(41), Int64.max] {
            let startFrame: Int64 = endFrame == Int64.max ? 0 : 42
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: makeItem(path: "/tmp/Master.mov", duration: 5),
                secondaryItem: makeItem(path: "/tmp/Encode.mp4", duration: 5),
                alignmentMode: .relative,
                notes: [CompareReviewNote(
                    primaryFrame: startFrame, primaryTime: 0,
                    secondaryFrame: 0, secondaryTime: 0,
                    text: "Invalid range", primaryEndFrame: endFrame
                )]
            )
            for format: CompareReviewReportFormat in [.resolveMarkersEDL, .finalCutProXML] {
                XCTAssertThrowsError(try CompareReviewReportExporter.data(for: format, snapshot: snapshot))
            }
        }
    }

    private func makeItem(
        path: String,
        duration: TimeInterval,
        startTimecode: String? = nil,
        frameRate: String? = nil
    ) -> MediaItem {
        let videoStreams = frameRate.map { value in
            [MediaMetadata.VideoStream(
                codec: nil,
                codecLongName: nil,
                profile: nil,
                width: 1_920,
                height: 1_080,
                displayWidth: 1_920,
                displayHeight: 1_080,
                pixelFormat: nil,
                hasAlpha: false,
                pixelAspectRatio: nil,
                displayAspectRatio: nil,
                frameRate: MediaMetadata.FrameRate(frameRateString: value),
                bitDepth: nil,
                chromaSubsampling: nil,
                colorPrimaries: nil,
                colorTransfer: nil,
                colorSpace: nil,
                colorRange: nil,
                chromaLocation: nil,
                fieldOrder: nil,
                isInterlaced: nil,
                rotation: nil,
                maxCLL: nil,
                maxFALL: nil,
                masteringMaxLuminance: nil,
                masteringMinLuminance: nil
            )]
        } ?? []
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
            videoStreams: videoStreams,
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

    private func makeSolidImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        width: Int = 320,
        height: Int = 180
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func rasterizedColorCounts(page: CGPDFPage) -> (red: Int, blue: Int) {
        let width = 595
        let height = 842
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.concatenate(page.getDrawingTransform(
                .mediaBox,
                rect: CGRect(x: 0, y: 0, width: width, height: height),
                rotate: 0,
                preserveAspectRatio: true
            ))
            context.drawPDFPage(page)
        }

        var redCount = 0
        var blueCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[index]
            let green = pixels[index + 1]
            let blue = pixels[index + 2]
            if red > 170, green < 110, blue < 110 { redCount += 1 }
            if blue > 170, red < 110, green < 110 { blueCount += 1 }
        }
        return (redCount, blueCount)
    }
}

private actor ReportFrameRequestRecorder {
    private(set) var requests: [(url: URL, time: TimeInterval)] = []

    func record(url: URL, time: TimeInterval) {
        requests.append((url, time))
    }
}
