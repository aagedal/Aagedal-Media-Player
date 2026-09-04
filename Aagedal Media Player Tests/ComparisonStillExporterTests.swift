// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import ImageIO
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ComparisonStillExporterTests: XCTestCase {
    func testLayoutAspectFitsLandscapeAndPortraitWithoutStretching() {
        let landscape = CGSize(width: 1_920, height: 1_080)
        let portrait = CGSize(width: 1_080, height: 1_920)
        let layout = ComparisonStillLayout(
            primarySize: landscape,
            secondarySize: portrait
        )

        let primaryRect = layout.imageRect(for: landscape, sourceIndex: 0)
        let secondaryRect = layout.imageRect(for: portrait, sourceIndex: 1)

        XCTAssertEqual(primaryRect.width / primaryRect.height, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(secondaryRect.width / secondaryRect.height, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(primaryRect.width, CGFloat(layout.panelWidth))
        XCTAssertLessThanOrEqual(primaryRect.height, CGFloat(layout.imageHeight))
        XCTAssertLessThanOrEqual(secondaryRect.width, CGFloat(layout.panelWidth))
        XCTAssertLessThanOrEqual(secondaryRect.height, CGFloat(layout.imageHeight))
        XCTAssertGreaterThanOrEqual(secondaryRect.minX, CGFloat(layout.panelWidth + ComparisonStillLayout.panelGap))
    }

    func testLayoutBoundsVeryLargeSources() {
        let layout = ComparisonStillLayout(
            primarySize: CGSize(width: 15_360, height: 8_640),
            secondarySize: CGSize(width: 8_640, height: 15_360)
        )

        XCTAssertEqual(layout.panelWidth, ComparisonStillLayout.maximumPanelWidth)
        XCTAssertEqual(layout.imageHeight, ComparisonStillLayout.maximumImageHeight)
        XCTAssertEqual(
            layout.canvasWidth,
            ComparisonStillLayout.maximumPanelWidth * 2 + ComparisonStillLayout.panelGap
        )
    }

    func testTechnicalLinesIncludeSelectedMetadataAndUnavailableValues() {
        let populated = CompareMediaDescriptor(
            videoCodec: "ProRes 422 HQ",
            rasterWidth: 3_840,
            rasterHeight: 2_160,
            duration: 12,
            frameRate: 23.976,
            transferFunction: "PQ",
            colorPrimaries: "BT.2020",
            colorRange: "Limited"
        )
        let unavailable = CompareMediaDescriptor(
            duration: nil,
            frameRate: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            colorRange: nil
        )

        XCTAssertEqual(
            ComparisonStillSourceDetails.technicalLines(for: populated),
            [
                "Codec: ProRes 422 HQ    Raster: 3840 × 2160    Frame rate: 23.976 fps",
                "Transfer: PQ    Primaries: BT.2020    Range: Limited",
            ]
        )
        XCTAssertEqual(
            ComparisonStillSourceDetails.technicalLines(for: unavailable),
            [
                "Codec: Unavailable    Raster: Unavailable    Frame rate: Unavailable",
                "Transfer: Unavailable    Primaries: Unavailable    Range: Unavailable",
            ]
        )
    }

    func testCaptureTimeClampsToLastFrameInsteadOfExclusiveDuration() {
        var item = MediaItem(
            url: URL(fileURLWithPath: "/tmp/master.mov"),
            name: "master.mov",
            size: 1,
            durationSeconds: 10
        )

        XCTAssertEqual(
            ComparisonStillFrameExtractor.clampedTime(10, for: item),
            10 - 1.0 / 30.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(ComparisonStillFrameExtractor.clampedTime(4.5, for: item), 4.5)

        item.durationSeconds = 0
        XCTAssertEqual(ComparisonStillFrameExtractor.clampedTime(4.5, for: item), 4.5)
        XCTAssertEqual(ComparisonStillFrameExtractor.clampedTime(.infinity, for: item), 0)
    }

    func testSourceDetailsUseFilenameAndAvailableSourceTimecode() {
        let metadata = MediaMetadata(
            duration: 10,
            formatName: nil,
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: "01:00:00:00",
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [],
            subtitleStreams: [],
            chapters: []
        )
        let sourceItem = MediaItem(
            url: URL(fileURLWithPath: "/tmp/source master.mov"),
            name: "source master.mov",
            size: 1,
            durationSeconds: 10,
            metadata: metadata
        )
        let relativeItem = MediaItem(
            url: URL(fileURLWithPath: "/tmp/encode.mp4"),
            name: "encode.mp4",
            size: 1,
            durationSeconds: 10
        )

        let source = ComparisonStillSourceDetails(item: sourceItem, time: 2)
        let relative = ComparisonStillSourceDetails(item: relativeItem, time: 2)

        XCTAssertEqual(source.filename, "source master.mov")
        XCTAssertEqual(source.timecode, "SRC TC 01:00:02:00")
        XCTAssertEqual(relative.filename, "encode.mp4")
        XCTAssertEqual(relative.timecode, "REL TC 00:00:02:00")
    }

    func testRendererProducesExpectedAnnotatedCanvas() throws {
        let primary = try makeImage(width: 16, height: 9, red: 1, green: 0, blue: 0)
        let secondary = try makeImage(width: 9, height: 16, red: 0, green: 0, blue: 1)
        let details = ComparisonStillDetails(
            primary: ComparisonStillSourceDetails(
                filename: "master.mov",
                timecode: "SRC TC 01:00:00:00",
                technicalLines: ["Codec: ProRes", "Transfer: BT.709"]
            ),
            secondary: ComparisonStillSourceDetails(
                filename: "encode.mp4",
                timecode: "SRC TC 01:00:00:00",
                technicalLines: ["Codec: HEVC", "Transfer: BT.709"]
            ),
            alignmentLabel: "Source timecode"
        )
        let layout = ComparisonStillLayout(
            primarySize: CGSize(width: primary.width, height: primary.height),
            secondarySize: CGSize(width: secondary.width, height: secondary.height)
        )

        let rendered = try ComparisonStillRenderer.render(
            primaryImage: primary,
            secondaryImage: secondary,
            details: details
        )

        XCTAssertEqual(rendered.width, layout.canvasWidth)
        XCTAssertEqual(rendered.height, layout.canvasHeight)
        XCTAssertEqual(rendered.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testPNGWriterProducesDecodableImage() throws {
        let image = try makeImage(width: 32, height: 18, red: 0.2, green: 0.4, blue: 0.6)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comparison-still-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ComparisonStillRenderer.writePNG(image, to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 18)
    }

    func testFrameExtractorReadsMPVOnlyGeneratedFixtureThroughFallback() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated/chapters-subtitles-long-gop.mkv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Generated media fixtures are unavailable.")
        }

        let image = try await ComparisonStillFrameExtractor.image(from: url, at: 1)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    private func makeImage(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
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
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
