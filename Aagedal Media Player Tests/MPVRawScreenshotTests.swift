// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Libmpv
import XCTest
@testable import Aagedal_Media_Player

final class MPVRawScreenshotTests: XCTestCase {
    func testCopiesValidatedRasterBeforeMPVNodeIsFreed() throws {
        let expected = Data([0, 0, 255, 0, 0, 255, 0, 0, 99, 99, 99, 99])
        let raw = try XCTUnwrap(withScreenshotNode(bytes: expected) { parse($0) })
        XCTAssertEqual(raw.width, 2)
        XCTAssertEqual(raw.height, 1)
        XCTAssertEqual(raw.stride, 8)
        XCTAssertEqual(raw.format, "bgr0")
        XCTAssertEqual(raw.data, expected.prefix(8), "Copy only the validated raster, excluding trailing bytes")
        XCTAssertEqual(raw.playbackTime, 1.25)
        XCTAssertEqual(raw.playbackTimeUncertainty, 0.01)
    }

    func testRequiresEveryScreenshotField() {
        for key in ["w", "h", "stride", "format", "data"] {
            XCTAssertNil(withScreenshotNode(omit: key) { parse($0) }, "Missing \(key)")
        }
    }

    func testRejectsIncorrectUnionTagsBeforeReadingPayload() {
        for key in ["w", "h", "stride", "format", "data"] {
            XCTAssertNil(withScreenshotNode(wrongType: key) { parse($0) }, "Wrong node type for \(key)")
        }
    }

    func testRejectsDuplicateRequiredFields() {
        for key in ["w", "h", "stride", "format", "data"] {
            XCTAssertNil(withScreenshotNode(duplicate: key) { parse($0) }, "Duplicate \(key)")
        }
    }

    func testRejectsMissingNodeMapStorage() {
        var result = mpv_node()
        XCTAssertNil(parse(result))
        result.format = MPV_FORMAT_NODE_MAP
        XCTAssertNil(parse(result))
        var list = mpv_node_list()
        withUnsafeMutablePointer(to: &list) { pointer in
            result.u.list = pointer
            XCTAssertNil(parse(result))
            pointer.pointee.num = 5
            XCTAssertNil(parse(result))
        }
    }

    func testRejectsTruncatedOrNullByteArray() {
        XCTAssertNil(withScreenshotNode(bytes: Data(repeating: 0, count: 7)) { parse($0) })
        XCTAssertNil(withScreenshotNode(nullBytes: true) { parse($0) })
    }

    func testValidatesSupportedLayoutsIncludingHighBitDepthAndPadding() {
        for format in ["bgr0", "bgra", "rgba", "rgba64"] {
            let stride = format == "rgba64" ? 24 : 12
            let bytes = Data(repeating: 0, count: stride * 2)
            let raw = withScreenshotNode(bytes: bytes, height: 2, stride: Int64(stride), format: format) { parse($0) }
            XCTAssertEqual(raw?.data.count, stride * 2)
            XCTAssertNotNil(raw.flatMap(LoupeFrameCapture.image(from:)), format)
        }
    }

    func testRejectsUnknownFormatAndOverflowingDimensionsWithoutCopying() {
        XCTAssertNil(withScreenshotNode(format: "unknown") { parse($0) })
        for invalid in [Int64.zero, -1, Int64.max] {
            XCTAssertNil(withScreenshotNode(width: invalid) { parse($0) })
            XCTAssertNil(withScreenshotNode(height: invalid) { parse($0) })
            XCTAssertNil(withScreenshotNode(stride: invalid) { parse($0) })
        }
        XCTAssertNil(withScreenshotNode(stride: 4) { parse($0) })
        XCTAssertNil(withScreenshotNode(stride: 8, format: "rgba64") { parse($0) })
    }

    private func parse(_ result: mpv_node) -> MPVPlayer.RawScreenshot? {
        MPVPlayer.rawScreenshot(from: result, playbackTime: 1.25, playbackTimeUncertainty: 0.01)
    }

    /// These synthetic nodes use real valid storage with intentionally wrong
    /// tags. Production must reject the tag before dereferencing that union.
    private func withScreenshotNode<T>(
        bytes: Data = Data(repeating: 0, count: 8),
        width: Int64 = 2,
        height: Int64 = 1,
        stride: Int64 = 8,
        format: String = "bgr0",
        omit: String? = nil,
        wrongType: String? = nil,
        duplicate: String? = nil,
        nullBytes: Bool = false,
        _ body: (mpv_node) -> T
    ) -> T {
        let formatString = strdup(format)!
        defer { free(formatString) }
        return bytes.withUnsafeBytes { data in
            var byteArray = mpv_byte_array()
            byteArray.size = data.count
            byteArray.data = nullBytes ? nil : UnsafeMutableRawPointer(mutating: data.baseAddress)
            return withUnsafeMutablePointer(to: &byteArray) { byteArrayPointer in
                var names = ["w", "h", "stride", "format", "data"].filter { $0 != omit }
                if let duplicate { names.append(duplicate) }
                var keys = names.map { strdup($0) }
                defer { keys.forEach { free($0) } }
                var values = names.map { name in
                    var node = mpv_node()
                    switch name {
                    case "w", "h", "stride":
                        node.format = MPV_FORMAT_INT64
                        node.u.int64 = name == "w" ? width : name == "h" ? height : stride
                    case "format":
                        node.format = MPV_FORMAT_STRING
                        node.u.string = formatString
                    default:
                        node.format = MPV_FORMAT_BYTE_ARRAY
                        node.u.ba = byteArrayPointer
                    }
                    if name == wrongType { node.format = MPV_FORMAT_NONE }
                    return node
                }
                return keys.withUnsafeMutableBufferPointer { keyBuffer in
                    values.withUnsafeMutableBufferPointer { valueBuffer in
                        var list = mpv_node_list()
                        list.num = Int32(valueBuffer.count)
                        list.keys = keyBuffer.baseAddress
                        list.values = valueBuffer.baseAddress
                        return withUnsafeMutablePointer(to: &list) { listPointer in
                            var result = mpv_node()
                            result.format = MPV_FORMAT_NODE_MAP
                            result.u.list = listPointer
                            return body(result)
                        }
                    }
                }
            }
        }
    }
}
