// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import ImageIO
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

        let xml = CompareReviewReportExporter.finalCutProXML(snapshot: snapshot)
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

    func testAvidMarkersAreTabDelimitedAndUsePrimaryFrameCoordinates() {
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

        let text = CompareReviewReportExporter.avidMarkersText(snapshot: snapshot)
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
