// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import ImageIO
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ComparisonStillExporterTests: XCTestCase {
    func testInspectionViewAnnotationNamesTheCapturedModeAndFixedExportLayout() {
        let source = ComparisonStillSourceDetails(filename: "a.mov", timecode: "", technicalLines: [])
        let modes: [(CompareViewMode, String)] = [
            (.sideBySide, "A | B"), (.primary, "A"), (.secondary, "B"),
            (.verticalWipe, "Vertical Wipe"), (.horizontalWipe, "Horizontal Wipe"),
            (.overlay, "Overlay"), (.difference, "Display Difference")
        ]
        for (mode, label) in modes {
            let details = ComparisonStillDetails(
                primary: source, secondary: source, alignmentLabel: "Relative start",
                inspectionView: mode
            )
            XCTAssertEqual(details.inspectionView, mode)
            XCTAssertEqual(details.inspectionViewAnnotation,
                           "Inspection view: \(label)  •  Export layout: A | B")
        }

        // Note reports have no recorded inspection mode. Do not infer the live
        // session's mode or label their fixed export layout as a captured mode.
        let unrecorded = ComparisonStillDetails(primary: source, secondary: source, alignmentLabel: "")
        XCTAssertNil(unrecorded.inspectionView)
        XCTAssertEqual(unrecorded.inspectionViewAnnotation,
                       "Inspection view: Unrecorded  •  Export layout: A | B")
    }

    func testCapturedInspectionViewChangesRenderedHeaderOnly() throws {
        let image = try makeImage(width: 16, height: 9, red: 1, green: 0, blue: 0)
        let source = ComparisonStillSourceDetails(filename: "a.mov", timecode: "", technicalLines: [])
        func render(_ mode: CompareViewMode?) throws -> CGImage {
            try ComparisonStillRenderer.render(
                primaryImage: image, secondaryImage: image,
                details: ComparisonStillDetails(
                    primary: source, secondary: source, alignmentLabel: "Relative start",
                    inspectionView: mode
                )
            )
        }
        let baseline = try render(nil)
        let imageAndFooter = CGRect(
            x: 0, y: ComparisonStillLayout.headerHeight,
            width: baseline.width, height: baseline.height - ComparisonStillLayout.headerHeight
        )
        let baselineBody = try XCTUnwrap(baseline.cropping(to: imageAndFooter))
        let baselineBodyData = try renderedBytes(baselineBody)
        for mode in [CompareViewMode.verticalWipe, .difference] {
            let rendered = try render(mode)
            XCTAssertEqual(rendered.width, baseline.width)
            XCTAssertEqual(rendered.height, baseline.height)
            XCTAssertNotEqual(try XCTUnwrap(rendered.dataProvider?.data) as Data,
                              try XCTUnwrap(baseline.dataProvider?.data) as Data)
            let body = try XCTUnwrap(rendered.cropping(to: imageAndFooter))
            XCTAssertEqual(try renderedBytes(body), baselineBodyData)
        }
    }

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
        XCTAssertEqual(try pixel(in: decoded, x: 16, y: 9), try pixel(in: image, x: 16, y: 9))
    }

    func testRenderedPixelsPreserveSourceCornersAndAspectFitBars() throws {
        // Asymmetric corners catch mirrored or vertically inverted exports,
        // while the different rasters exercise both letterbox and pillarbox.
        let primary = try makeCornerImage(width: 160, height: 90)
        let secondary = try makeCornerImage(width: 90, height: 160, secondaryPalette: true)
        let sourceDetails = ComparisonStillSourceDetails(
            filename: "corners.mov", timecode: "REL TC 00:00:00:00", technicalLines: []
        )
        let rendered = try ComparisonStillRenderer.render(
            primaryImage: primary,
            secondaryImage: secondary,
            details: ComparisonStillDetails(
                primary: sourceDetails, secondary: sourceDetails, alignmentLabel: "Relative"
            ),
            maximumPanelWidth: 640,
            maximumImageHeight: 640
        )

        // Expected picture bounds are independent of ComparisonStillLayout:
        // A is 640×360 centered in a 640-high panel; B is 360×640.
        let pictures = [
            CGRect(x: 0, y: 390, width: 640, height: 360),
            CGRect(x: 784, y: 250, width: 360, height: 640)
        ]
        for (index, picture) in pictures.enumerated() {
            let samples: [(CGFloat, CGFloat, [UInt8])] = index == 0
                ? [(0.25, 0.25, [255, 0, 0, 255]),
                   (0.75, 0.25, [0, 255, 0, 255]),
                   (0.25, 0.75, [0, 0, 255, 255]),
                   (0.75, 0.75, [255, 255, 0, 255])]
                : [(0.25, 0.25, [0, 255, 255, 255]),
                   (0.75, 0.25, [255, 0, 255, 255]),
                   (0.25, 0.75, [255, 255, 255, 255]),
                   (0.75, 0.75, [0, 0, 0, 255])]
            for (x, y, expected) in samples {
                XCTAssertEqual(
                    try pixel(in: rendered,
                              x: Int(picture.minX + picture.width * x),
                              y: Int(picture.minY + picture.height * y)),
                    expected
                )
            }
        }

        let bars = try [
            pixel(in: rendered, x: 320, y: 300),
            pixel(in: rendered, x: 320, y: 850),
            pixel(in: rendered, x: 700, y: 570),
            pixel(in: rendered, x: 1_200, y: 570)
        ]
        for bar in bars {
            XCTAssertEqual(bar, bars[0])
            XCTAssertEqual(bar[0], bar[1])
            XCTAssertEqual(bar[1], bar[2])
            XCTAssertLessThan(bar[0], 64)
            XCTAssertEqual(bar[3], 255)
        }
        let divider = try pixel(in: rendered, x: 642, y: 570)
        XCTAssertGreaterThan(divider[0], bars[0][0])
        XCTAssertEqual(divider[0], divider[1])
        XCTAssertEqual(divider[1], divider[2])
    }

    func testRendererAcceptsEmptyOptionalAnnotations() throws {
        let image = try makeImage(width: 16, height: 9, red: 1, green: 0, blue: 0)
        let empty = ComparisonStillSourceDetails(
            filename: "", timecode: "", technicalLines: ["", ""]
        )
        let rendered = try ComparisonStillRenderer.render(
            primaryImage: image, secondaryImage: image,
            details: ComparisonStillDetails(primary: empty, secondary: empty, alignmentLabel: "")
        )
        XCTAssertEqual(rendered.width, 1_284)
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

    private func makeCornerImage(width: Int, height: Int, secondaryPalette: Bool = false) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let colors: [(CGFloat, CGFloat, CGFloat)] = secondaryPalette
            ? [(0, 1, 1), (1, 0, 1), (1, 1, 1), (0, 0, 0)]
            : [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0)]
        for (index, color) in colors.enumerated() {
            context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
            context.fill(CGRect(
                x: index % 2 * width / 2, y: index / 2 * height / 2,
                width: width / 2, height: height / 2
            ))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func renderedBytes(_ image: CGImage) throws -> Data {
        // A cropped CGImage may retain its original provider. Redraw it so the
        // comparison contains only the visible crop, excluding header storage.
        let bytesPerRow = image.width * 4
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: bytesPerRow * image.height)
    }

    /// Sample in the same bottom-left drawing coordinates used by the exporter.
    private func pixel(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: 4))
    }
}
