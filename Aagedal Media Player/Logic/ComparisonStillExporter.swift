// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ComparisonStillSourceDetails: Equatable, Sendable {
    let filename: String
    let timecode: String
    let technicalLines: [String]

    init(filename: String, timecode: String, technicalLines: [String]) {
        self.filename = filename
        self.timecode = timecode
        self.technicalLines = technicalLines
    }

    @MainActor
    init(item: MediaItem, time: TimeInterval) {
        filename = item.url.lastPathComponent
        let hasSourceTimecode = TimecodeFormatter.effectiveStartTimecode(for: item) != nil
        let mode: TimecodeDisplayMode = hasSourceTimecode ? .source : .relative
        let value = TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: time,
            item: item,
            mode: mode
        )
        timecode = "\(hasSourceTimecode ? "SRC TC" : "REL TC") \(value)"
        technicalLines = Self.technicalLines(for: CompareMediaDescriptor(item: item))
    }

    nonisolated static func technicalLines(for descriptor: CompareMediaDescriptor) -> [String] {
        let codec = cleaned(descriptor.videoCodec)
        let raster: String
        if let width = descriptor.rasterWidth, let height = descriptor.rasterHeight {
            raster = "\(width) × \(height)"
        } else {
            raster = "Unavailable"
        }
        let frameRate = descriptor.frameRate.map { value in
            if abs(value - value.rounded()) < 0.0005 {
                return "\(Int(value.rounded())) fps"
            }
            var label = String(format: "%.3f", value)
            while label.last == "0" { label.removeLast() }
            if label.last == "." { label.removeLast() }
            return "\(label) fps"
        } ?? "Unavailable"

        let transfer = cleaned(descriptor.transferFunction)
        let primaries = cleaned(descriptor.colorPrimaries)
        let range = cleaned(descriptor.colorRange)

        return [
            "Codec: \(codec)    Raster: \(raster)    Frame rate: \(frameRate)",
            "Transfer: \(transfer)    Primaries: \(primaries)    Range: \(range)",
        ]
    }

    nonisolated private static func cleaned(_ value: String?) -> String {
        guard let value else { return "Unavailable" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unavailable" : trimmed
    }
}

nonisolated struct ComparisonStillDetails: Equatable, Sendable {
    let primary: ComparisonStillSourceDetails
    let secondary: ComparisonStillSourceDetails
    let alignmentLabel: String
    let inspectionView: CompareViewMode?

    var inspectionViewAnnotation: String {
        "Inspection view: \(inspectionView?.label ?? "Unrecorded")  •  Export layout: A | B"
    }

    init(
        primary: ComparisonStillSourceDetails,
        secondary: ComparisonStillSourceDetails,
        alignmentLabel: String,
        inspectionView: CompareViewMode? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.alignmentLabel = alignmentLabel
        self.inspectionView = inspectionView
    }
}

nonisolated struct ComparisonStillLayout: Equatable, Sendable {
    static let maximumPanelWidth = 3_840
    static let maximumImageHeight = 2_160
    static let minimumPanelWidth = 640
    static let headerHeight = 150
    static let footerHeight = 250
    static let panelGap = 4

    let panelWidth: Int
    let imageHeight: Int

    var canvasWidth: Int { panelWidth * 2 + Self.panelGap }
    var canvasHeight: Int { Self.headerHeight + imageHeight + Self.footerHeight }

    init(
        primarySize: CGSize,
        secondarySize: CGSize,
        maximumPanelWidth: Int = Self.maximumPanelWidth,
        maximumImageHeight: Int = Self.maximumImageHeight
    ) {
        let widestSource = max(primarySize.width, secondarySize.width)
        let maximumPanelWidth = min(
            max(maximumPanelWidth, Self.minimumPanelWidth),
            Self.maximumPanelWidth
        )
        let resolvedPanelWidth = min(
            max(Int(widestSource.rounded(.up)), Self.minimumPanelWidth),
            maximumPanelWidth
        )
        panelWidth = resolvedPanelWidth

        let fittedHeights = [primarySize, secondarySize].compactMap { size -> CGFloat? in
            guard size.width > 0, size.height > 0 else { return nil }
            return size.height * CGFloat(resolvedPanelWidth) / size.width
        }
        let maximumImageHeight = min(
            max(maximumImageHeight, 360),
            Self.maximumImageHeight
        )
        imageHeight = min(
            max(Int((fittedHeights.max() ?? 360).rounded(.up)), 360),
            maximumImageHeight
        )
    }

    func imageRect(for sourceSize: CGSize, sourceIndex: Int) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .zero }
        let panelX = sourceIndex == 0 ? 0 : panelWidth + Self.panelGap
        let scale = min(
            CGFloat(panelWidth) / sourceSize.width,
            CGFloat(imageHeight) / sourceSize.height
        )
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        return CGRect(
            x: CGFloat(panelX) + (CGFloat(panelWidth) - width) / 2,
            y: CGFloat(Self.footerHeight) + (CGFloat(imageHeight) - height) / 2,
            width: width,
            height: height
        )
    }
}

enum ComparisonStillExportError: Error, LocalizedError {
    case couldNotCreateCanvas
    case couldNotCreateEncoder
    case couldNotWriteImage
    case couldNotDecodeExtractedFrame

    var errorDescription: String? {
        switch self {
        case .couldNotCreateCanvas:
            "Could not create the comparison image canvas."
        case .couldNotCreateEncoder:
            "Could not create the comparison image encoder."
        case .couldNotWriteImage:
            "Could not write the comparison image."
        case .couldNotDecodeExtractedFrame:
            "Could not decode an extracted comparison frame."
        }
    }
}

nonisolated enum ComparisonStillRenderer {
    static func render(
        primaryImage: CGImage,
        secondaryImage: CGImage,
        details: ComparisonStillDetails,
        maximumPanelWidth: Int = ComparisonStillLayout.maximumPanelWidth,
        maximumImageHeight: Int = ComparisonStillLayout.maximumImageHeight
    ) throws -> CGImage {
        let primarySize = CGSize(width: primaryImage.width, height: primaryImage.height)
        let secondarySize = CGSize(width: secondaryImage.width, height: secondaryImage.height)
        let layout = ComparisonStillLayout(
            primarySize: primarySize,
            secondarySize: secondarySize,
            maximumPanelWidth: maximumPanelWidth,
            maximumImageHeight: maximumImageHeight
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ComparisonStillExportError.couldNotCreateCanvas
        }

        let canvas = CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
        context.setFillColor(CGColor(gray: 0.035, alpha: 1))
        context.fill(canvas)

        drawImage(primaryImage, in: layout.imageRect(for: primarySize, sourceIndex: 0), context: context)
        drawImage(secondaryImage, in: layout.imageRect(for: secondarySize, sourceIndex: 1), context: context)

        context.setFillColor(CGColor(gray: 0.18, alpha: 1))
        context.fill(CGRect(
            x: layout.panelWidth,
            y: ComparisonStillLayout.footerHeight,
            width: ComparisonStillLayout.panelGap,
            height: layout.imageHeight
        ))

        drawHeader(details: details, layout: layout, context: context)
        drawFooter(details: details, layout: layout, context: context)

        guard let image = context.makeImage() else {
            throw ComparisonStillExportError.couldNotCreateCanvas
        }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ComparisonStillExportError.couldNotCreateEncoder
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ComparisonStillExportError.couldNotWriteImage
        }
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.86) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ComparisonStillExportError.couldNotCreateEncoder
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1),
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ComparisonStillExportError.couldNotWriteImage
        }
        return output as Data
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private static func drawHeader(
        details: ComparisonStillDetails,
        layout: ComparisonStillLayout,
        context: CGContext
    ) {
        let headerBottom = CGFloat(ComparisonStillLayout.footerHeight + layout.imageHeight)
        drawText(
            "COMPARISON STILL",
            at: CGPoint(x: 32, y: headerBottom + 86),
            fontSize: 34,
            weight: .bold,
            color: CGColor(gray: 0.96, alpha: 1),
            context: context
        )
        drawText(
            "Alignment: \(details.alignmentLabel)  •  Display-space PNG",
            at: CGPoint(x: 32, y: headerBottom + 48),
            fontSize: 24,
            weight: .regular,
            color: CGColor(gray: 0.72, alpha: 1),
            context: context
        )
        drawText(
            details.inspectionViewAnnotation,
            at: CGPoint(x: 32, y: headerBottom + 16),
            fontSize: 20,
            weight: .regular,
            color: CGColor(gray: 0.72, alpha: 1),
            context: context
        )
    }

    private static func drawFooter(
        details: ComparisonStillDetails,
        layout: ComparisonStillLayout,
        context: CGContext
    ) {
        drawSourceFooter(
            label: "A",
            details: details.primary,
            x: 28,
            width: layout.panelWidth - 56,
            context: context
        )
        drawSourceFooter(
            label: "B",
            details: details.secondary,
            x: layout.panelWidth + ComparisonStillLayout.panelGap + 28,
            width: layout.panelWidth - 56,
            context: context
        )
    }

    private static func drawSourceFooter(
        label: String,
        details: ComparisonStillSourceDetails,
        x: Int,
        width: Int,
        context: CGContext
    ) {
        drawText(
            label,
            at: CGPoint(x: x, y: 188),
            fontSize: 34,
            weight: .bold,
            color: label == "A"
                ? CGColor(red: 0.31, green: 0.68, blue: 1, alpha: 1)
                : CGColor(red: 1, green: 0.57, blue: 0.25, alpha: 1),
            context: context
        )
        drawText(
            details.filename,
            at: CGPoint(x: x + 52, y: 190),
            fontSize: 28,
            weight: .semibold,
            color: CGColor(gray: 0.96, alpha: 1),
            maximumWidth: CGFloat(max(0, width - 52)),
            context: context
        )
        drawText(
            details.timecode,
            at: CGPoint(x: x, y: 138),
            fontSize: 24,
            weight: .medium,
            color: CGColor(gray: 0.82, alpha: 1),
            context: context
        )
        for (index, line) in details.technicalLines.prefix(2).enumerated() {
            drawText(
                line,
                at: CGPoint(x: x, y: 88 - index * 38),
                fontSize: 20,
                weight: .regular,
                color: CGColor(gray: 0.68, alpha: 1),
                maximumWidth: CGFloat(width),
                context: context
            )
        }
    }

    private enum FontWeight {
        case regular
        case medium
        case semibold
        case bold

        var fontName: CFString {
            switch self {
            case .regular: "SFProText-Regular" as CFString
            case .medium: "SFProText-Medium" as CFString
            case .semibold: "SFProText-Semibold" as CFString
            case .bold: "SFProText-Bold" as CFString
            }
        }
    }

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        weight: FontWeight,
        color: CGColor,
        maximumWidth: CGFloat? = nil,
        context: CGContext
    ) {
        guard !text.isEmpty else { return }
        let font = CTFontCreateWithName(weight.fontName, fontSize, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        var line = CTLineCreateWithAttributedString(attributed)
        if let maximumWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(
                string: "…",
                attributes: attributed.attributes(at: 0, effectiveRange: nil)
            ))
            line = CTLineCreateTruncatedLine(line, Double(maximumWidth), .end, ellipsis) ?? line
        }
        context.saveGState()
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

nonisolated enum ComparisonStillFrameExtractor {
    static func clampedTime(_ time: TimeInterval, for item: MediaItem) -> TimeInterval {
        let finiteTime = time.isFinite ? max(0, time) : 0
        let duration = item.durationSeconds
        guard duration.isFinite, duration > 0 else { return finiteTime }

        let frameRate = item.metadata?.videoStreams.first?.frameRate?.value
            .flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 30
        // A duration is the exclusive end of the timeline. Asking an image
        // generator for that exact timestamp commonly returns no frame.
        let lastFrameTime = max(0, duration - 1 / frameRate)
        return min(finiteTime, lastFrameTime)
    }

    static func image(
        from url: URL, at time: TimeInterval, maximumSize: CGSize = .zero,
        tolerance: CMTime = .zero
    ) async throws -> CGImage {
        do {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = maximumSize
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 60_000)
            let cancellation = ImageGenerationCancellation(generator)
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await generator.image(at: requestedTime)
            } onCancel: {
                cancellation.cancel()
            }
            try Task.checkCancellation()
            return result.image
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            // AVFoundation covers ProRes RAW and other platform codecs. The
            // bundled ffmpeg fallback covers formats that only the MPV backend
            // can play, keeping comparison export independent of the active
            // playback backend.
            return try await ffmpegImage(from: url, at: time, maximumSize: maximumSize)
        }
    }

    // AVAssetImageGenerator supports cancelling generation from another queue.
    private final class ImageGenerationCancellation: @unchecked Sendable {
        private let generator: AVAssetImageGenerator
        init(_ generator: AVAssetImageGenerator) { self.generator = generator }
        func cancel() { generator.cancelAllCGImageGeneration() }
    }

    static func ffmpegImage(from url: URL, at time: TimeInterval, maximumSize: CGSize) async throws -> CGImage {
        let scale = maximumSize.width > 0 && maximumSize.height > 0
            ? "scale=w='max(1,min(\(Int(maximumSize.width)),\(Int(maximumSize.height))*dar))':h='max(1,min(\(Int(maximumSize.height)),\(Int(maximumSize.width))/dar))',setsar=1"
            : "scale=iw*sar:ih,setsar=1"
        let sink = LockedDataSink()
        try await FFmpegService.runStreamingOutput(
            arguments: [
                "-hide_banner", "-loglevel", "error",
                "-ss", String(max(0, time)),
                "-i", url.path,
                "-frames:v", "1",
                "-vf", scale,
                "-c:v", "png",
                "-f", "image2pipe",
                "pipe:1",
            ],
            onStandardOutputData: { data in
                sink.append(data)
            }
        )
        let data = sink.snapshot()
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ComparisonStillExportError.couldNotDecodeExtractedFrame
        }
        return image
    }

    private final class LockedDataSink: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}
