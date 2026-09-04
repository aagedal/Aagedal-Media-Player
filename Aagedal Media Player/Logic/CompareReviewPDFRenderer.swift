// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreText
import Foundation
import ImageIO

nonisolated enum CompareReviewPDFError: Error, LocalizedError {
    case couldNotCreateDocument
    case couldNotFinalizeDocument

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDocument:
            "Could not create the PDF review document."
        case .couldNotFinalizeDocument:
            "Could not finalize the PDF review document."
        }
    }
}

/// Produces a compact, printable report without depending on WebKit or a
/// print panel. Core Text wrapping keeps note text selectable in the PDF and
/// splits large reports across as many pages as necessary.
nonisolated enum CompareReviewPDFRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let margin: CGFloat = 40
    private static let rowGap: CGFloat = 4
    private static let noteLineHeight: CGFloat = 14
    private static let minimumRowHeight: CGFloat = 80

    static func render(
        snapshot: CompareReviewReportSnapshot,
        annotatedStills: [Int: Data] = [:]
    ) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw CompareReviewPDFError.couldNotCreateDocument
        }

        var mediaBox = pageRect
        let metadata = [
            kCGPDFContextTitle: "Comparison Review: \(snapshot.primaryFilename) vs \(snapshot.secondaryFilename)",
            kCGPDFContextCreator: "Aagedal Media Player",
        ] as CFDictionary
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            metadata
        ) else {
            throw CompareReviewPDFError.couldNotCreateDocument
        }

        let titleFont = font(size: 18, weight: .bold)
        let headingFont = font(size: 9, weight: .semibold)
        let metadataFont = font(size: 8, weight: .regular)
        let metadataBoldFont = font(size: 11, weight: .bold)
        let noteFont = font(size: 10, weight: .regular)
        let dark = CGColor(gray: 0.12, alpha: 1)
        let secondary = CGColor(gray: 0.42, alpha: 1)
        let rule = CGColor(gray: 0.82, alpha: 1)
        let rowFill = CGColor(gray: 0.96, alpha: 1)
        let contentWidth = pageRect.width - 2 * margin
        let metadataWidth: CGFloat = 148
        let columnGap: CGFloat = 14
        let noteX = margin + metadataWidth + columnGap
        let noteWidth = contentWidth - metadataWidth - columnGap
        let dateFormatter = reportDateFormatter()

        var pageNumber = 0
        var cursor: CGFloat = 0

        func beginPage() {
            pageNumber += 1
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(pageRect)

            drawText(
                "COMPARISON REVIEW",
                x: margin,
                top: 30,
                maximumWidth: 340,
                font: titleFont,
                color: dark,
                context: context
            )
            drawText(
                "Page \(pageNumber)",
                x: pageRect.width - margin - 70,
                top: 34,
                maximumWidth: 70,
                font: headingFont,
                color: secondary,
                alignment: .right,
                context: context
            )
            drawText(
                "A  \(snapshot.primaryFilename)",
                x: margin,
                top: 61,
                maximumWidth: contentWidth,
                font: headingFont,
                color: dark,
                context: context
            )
            drawText(
                "B  \(snapshot.secondaryFilename)",
                x: margin,
                top: 76,
                maximumWidth: contentWidth,
                font: headingFont,
                color: dark,
                context: context
            )
            drawText(
                "Alignment: \(snapshot.alignmentLabel)   -   \(snapshot.rows.count) notes",
                x: margin,
                top: 93,
                maximumWidth: contentWidth,
                font: metadataFont,
                color: secondary,
                context: context
            )

            drawRule(top: 112, color: rule, context: context)
            drawText(
                "MARKER / TIMECODE",
                x: margin + 6,
                top: 121,
                maximumWidth: metadataWidth - 6,
                font: headingFont,
                color: secondary,
                context: context
            )
            drawText(
                "NOTE",
                x: noteX,
                top: 121,
                maximumWidth: noteWidth,
                font: headingFont,
                color: secondary,
                context: context
            )
            cursor = 143
        }

        func endPage() {
            context.endPDFPage()
        }

        beginPage()

        for row in snapshot.rows {
            let noteLines = wrappedLines(
                row.note,
                width: noteWidth - 12,
                font: noteFont,
                color: dark
            )
            var lineIndex = 0
            var isContinuation = false
            let stillImage: CGImage? = annotatedStills[row.markerNumber].flatMap { data in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    return nil
                }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }

            repeat {
                let stillSize = isContinuation
                    ? .zero
                    : fittedStillSize(stillImage, maximumWidth: contentWidth - 12)
                let stillHeight = stillSize.height
                let stillSpace = stillHeight > 0 ? stillHeight + 12 : 0
                let available = pageRect.height - margin - cursor
                if available < minimumRowHeight + stillSpace {
                    endPage()
                    beginPage()
                }

                let pageAvailable = pageRect.height - margin - cursor
                let maximumLines = max(
                    1,
                    Int(floor((pageAvailable - 20 - stillSpace) / noteLineHeight))
                )
                let lineCount = min(maximumLines, noteLines.count - lineIndex)
                let textHeight = max(
                    minimumRowHeight,
                    20 + CGFloat(lineCount) * noteLineHeight
                )
                let rowHeight = textHeight + stillSpace
                let rowRect = rectFromTop(
                    x: margin,
                    top: cursor,
                    width: contentWidth,
                    height: rowHeight
                )
                context.setFillColor(rowFill)
                context.fill(rowRect)
                context.setStrokeColor(rule)
                context.setLineWidth(0.5)
                context.stroke(rowRect)

                drawText(
                    isContinuation ? "#\(row.markerNumber) (continued)" : "#\(row.markerNumber)",
                    x: margin + 7,
                    top: cursor + 7,
                    maximumWidth: metadataWidth - 12,
                    font: metadataBoldFont,
                    color: dark,
                    context: context
                )
                drawText(
                    "A  \(displayTimecode(source: row.primarySourceTimecode, relative: row.primaryRelativeTimecode))  -  F\(row.primaryFrame)",
                    x: margin + 7,
                    top: cursor + 24,
                    maximumWidth: metadataWidth - 12,
                    font: metadataFont,
                    color: dark,
                    context: context
                )
                drawText(
                    "B  \(displayTimecode(source: row.secondarySourceTimecode, relative: row.secondaryRelativeTimecode))  -  F\(row.secondaryFrame)",
                    x: margin + 7,
                    top: cursor + 37,
                    maximumWidth: metadataWidth - 12,
                    font: metadataFont,
                    color: dark,
                    context: context
                )
                drawText(
                    "Created \(dateFormatter.string(from: row.createdAt))",
                    x: margin + 7,
                    top: cursor + 50,
                    maximumWidth: metadataWidth - 12,
                    font: metadataFont,
                    color: secondary,
                    context: context
                )
                drawText(
                    "Updated \(dateFormatter.string(from: row.updatedAt))",
                    x: margin + 7,
                    top: cursor + 62,
                    maximumWidth: metadataWidth - 12,
                    font: metadataFont,
                    color: secondary,
                    context: context
                )

                for offset in 0..<lineCount {
                    drawLine(
                        noteLines[lineIndex + offset],
                        x: noteX + 6,
                        top: cursor + 9 + CGFloat(offset) * noteLineHeight,
                        font: noteFont,
                        context: context
                    )
                }

                if let stillImage, stillHeight > 0 {
                    let stillRect = rectFromTop(
                        x: margin + (contentWidth - stillSize.width) / 2,
                        top: cursor + textHeight + 6,
                        width: stillSize.width,
                        height: stillHeight
                    )
                    context.saveGState()
                    context.interpolationQuality = .high
                    context.draw(stillImage, in: stillRect)
                    context.restoreGState()
                }

                lineIndex += lineCount
                cursor += rowHeight + rowGap
                isContinuation = lineIndex < noteLines.count
                if isContinuation {
                    endPage()
                    beginPage()
                }
            } while lineIndex < noteLines.count
        }

        endPage()
        context.closePDF()

        guard output.length > 0 else {
            throw CompareReviewPDFError.couldNotFinalizeDocument
        }
        return output as Data
    }

    private enum FontWeight {
        case regular
        case semibold
        case bold
    }

    private enum TextAlignment {
        case left
        case right
    }

    private static func font(size: CGFloat, weight: FontWeight) -> CTFont {
        let name: CFString = switch weight {
        case .regular: "Helvetica" as CFString
        case .semibold: "Helvetica-Bold" as CFString
        case .bold: "Helvetica-Bold" as CFString
        }
        return CTFontCreateWithName(name, size, nil)
    }

    private static func displayTimecode(source: String?, relative: String) -> String {
        source ?? relative
    }

    private static func fittedStillSize(
        _ image: CGImage?,
        maximumWidth: CGFloat
    ) -> CGSize {
        guard let image, image.width > 0, image.height > 0 else { return .zero }
        let scale = min(
            maximumWidth / CGFloat(image.width),
            270 / CGFloat(image.height)
        )
        return CGSize(
            width: CGFloat(image.width) * scale,
            height: CGFloat(image.height) * scale
        )
    }

    private static func reportDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter
    }

    private static func wrappedLines(
        _ text: String,
        width: CGFloat,
        font: CTFont,
        color: CGColor
    ) -> [CTLine] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let attributes = textAttributes(font: font, color: color)
        var lines: [CTLine] = []

        for paragraph in paragraphs {
            let attributed = NSAttributedString(string: String(paragraph), attributes: attributes)
            guard attributed.length > 0 else {
                lines.append(CTLineCreateWithAttributedString(
                    NSAttributedString(string: " ", attributes: attributes)
                ))
                continue
            }

            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var location = 0
            while location < attributed.length {
                let suggested = CTTypesetterSuggestLineBreak(
                    typesetter,
                    location,
                    Double(width)
                )
                let length = max(1, suggested)
                lines.append(CTTypesetterCreateLine(
                    typesetter,
                    CFRange(location: location, length: min(length, attributed.length - location))
                ))
                location += length
            }
        }

        return lines.isEmpty
            ? [CTLineCreateWithAttributedString(NSAttributedString(string: " ", attributes: attributes))]
            : lines
    }

    private static func textAttributes(font: CTFont, color: CGColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
    }

    private static func drawText(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        maximumWidth: CGFloat,
        font: CTFont,
        color: CGColor,
        alignment: TextAlignment = .left,
        context: CGContext
    ) {
        let attributed = NSAttributedString(
            string: text,
            attributes: textAttributes(font: font, color: color)
        )
        var line = CTLineCreateWithAttributedString(attributed)
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(
            string: "…",
            attributes: textAttributes(font: font, color: color)
        ))
        line = CTLineCreateTruncatedLine(
            line,
            Double(maximumWidth),
            .end,
            ellipsis
        ) ?? line

        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let drawX = alignment == .right ? x + maximumWidth - lineWidth : x
        drawLine(line, x: drawX, top: top, font: font, context: context)
    }

    private static func drawLine(
        _ line: CTLine,
        x: CGFloat,
        top: CGFloat,
        font: CTFont,
        context: CGContext
    ) {
        context.saveGState()
        context.textPosition = CGPoint(
            x: x,
            y: pageRect.height - top - CTFontGetAscent(font)
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawRule(top: CGFloat, color: CGColor, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(0.75)
        let y = pageRect.height - top
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        context.strokePath()
        context.restoreGState()
    }

    private static func rectFromTop(
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(x: x, y: pageRect.height - top - height, width: width, height: height)
    }
}
