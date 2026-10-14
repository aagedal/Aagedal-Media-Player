// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CoreGraphics
import Libmpv
import XCTest
@testable import Aagedal_Media_Player

final class MPVDecoderRasterTests: XCTestCase {
    func testAcceptsOnlyVersionedPresentedDecoderProofAndCopiesPixels() throws {
        let raster = try XCTUnwrap(withNode { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        XCTAssertEqual(raster.pixels.data, Data([0, 0, 255, 0, 0, 255, 0, 0]))
        XCTAssertEqual(raster.pixels.playbackTime, 1.25)
        XCTAssertEqual(raster.pixels.playbackTimeUncertainty, 0)
        XCTAssertEqual(raster.trackID, 1)
        XCTAssertEqual(raster.rotation, 0)
        XCTAssertFalse(raster.mirrored)
        let padded = try XCTUnwrap(withNode(stride: 12, backingByteCount: 12) {
            MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
        })
        XCTAssertEqual(padded.pixels.stride, 12)
        XCTAssertEqual(padded.pixels.data.count, 12)
        XCTAssertEqual(padded.pixels.format, "bgra")
    }

    func testRejectsMissingMistypedDuplicateAndNegativeProofFields() {
        for key in ["protocol", "pixel-preserving", "presented-frame", "track-id", "coded-w", "coded-h", "rotation", "mirrored", "pts"] {
            XCTAssertNil(withNode(omit: key) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, key)
            XCTAssertNil(withNode(wrongType: key) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, key)
            XCTAssertNil(withNode(duplicate: key) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, key)
        }
        for key in ["pixel-preserving", "presented-frame"] {
            XCTAssertNil(withNode(falseFlag: key) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, key)
        }
        XCTAssertNil(withNode(protocolVersion: 3) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
    }

    func testRejectsChangedUnselectedAndUnknownTrack() {
        for tracks: (Int64?, Int64?) in [(1, 2), (nil, 1), (1, nil), (0, 0), (2, 2)] {
            XCTAssertNil(withNode { MPVDecoderRaster.parse($0, trackBefore: tracks.0, trackAfter: tracks.1) })
        }
    }

    func testRejectsResampledRasterUnsupportedRotationAndInvalidFrameTime() {
        XCTAssertNil(withNode(codedWidth: 3) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        XCTAssertNil(withNode(rotation: 45) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        for pts in [-1.0, .infinity, .nan] {
            XCTAssertNil(withNode(pts: pts) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        }
    }

    func testRejectsUnsupportedPixelFormatsAndMalformedBuffersBeforeCopying() {
        for format in ["bgr0", "rgba", "rgba64", "unknown"] {
            XCTAssertNil(withNode(pixelFormat: format) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, format)
        }
        for size in [0, 7, 9, Int.max] {
            XCTAssertNil(withNode(reportedByteCount: size) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, "size \(size)")
        }
        XCTAssertNil(withNode(nullData: true) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        for stride in [-1, 7, Int64.max] {
            XCTAssertNil(withNode(stride: stride) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) }, "stride \(stride)")
        }
    }

    func testRejectsProviderGeometryBeyondBoundedProtocolBeforeCopying() {
        for width in [Int64(4097), Int64.max] {
            XCTAssertNil(withNode(codedWidth: width) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
            XCTAssertNil(withNode(rasterWidth: width) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        }
        // Valid layouts with real backing data would otherwise pass the shared
        // screenshot parser. The provider's protocol bounds must reject them.
        XCTAssertNil(withNode(codedWidth: 4097, stride: 4097 * 4, rasterWidth: 4097,
                              backingByteCount: 4097 * 4) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        XCTAssertNil(withNode(codedWidth: 4096, stride: 4096 * 4, codedHeight: 1025,
                              rasterWidth: 4096, rasterHeight: 1025,
                              backingByteCount: 4096 * 1025 * 4) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        XCTAssertNil(withNode(codedWidth: 4096, codedHeight: 1025) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        XCTAssertNil(withNode(rasterWidth: 4096, rasterHeight: 1025) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
    }

    func testRejectsInconsistentOrientedGeometryBeforeReadingPayload() {
        // A deliberately unreadable pointer proves geometry rejection happens
        // before the shared parser can copy a large provider buffer.
        withNode(rotation: 90) { node in
            let fields = node.u.list!.pointee
            for index in 0..<Int(fields.num) where String(cString: fields.keys![index]!) == "data" {
                let bytes = fields.values![index].u.ba!
                let original = bytes.pointee.data
                bytes.pointee.data = UnsafeMutableRawPointer(bitPattern: 1)
                defer { bytes.pointee.data = original }
                XCTAssertNil(MPVDecoderRaster.parse(node, trackBefore: 1, trackAfter: 1))
            }
        }
    }

    func testDisplayScreenshotCannotBecomeDecoderProof() {
        XCTAssertNil(withNode(omit: "protocol") { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
        var node = mpv_node()
        XCTAssertFalse(MPVPlayer.hasDecoderRasterCommand(node))
        node.format = MPV_FORMAT_NODE_ARRAY
        XCTAssertFalse(MPVPlayer.hasDecoderRasterCommand(node))
    }

    func testCapabilityRequiresExactCommandName() {
        for command in ["aagedal-decoder-raster", "screenshot-raw", "aagedal-decoder-raster-v2"] {
            let name = strdup(command)!
            let key = strdup("name")!
            defer { free(name); free(key) }
            var keys: [UnsafeMutablePointer<CChar>?] = [key]
            var value = mpv_node(); value.format = MPV_FORMAT_STRING; value.u.string = name
            withUnsafeMutablePointer(to: &value) { value in
                keys.withUnsafeMutableBufferPointer { keys in
                    var fields = mpv_node_list(num: 1, values: value, keys: keys.baseAddress)
                    withUnsafeMutablePointer(to: &fields) { fields in
                        var entry = mpv_node(); entry.format = MPV_FORMAT_NODE_MAP; entry.u.list = fields
                        withUnsafeMutablePointer(to: &entry) { entry in
                            var entries = mpv_node_list(num: 1, values: entry, keys: nil)
                            withUnsafeMutablePointer(to: &entries) { entries in
                                var list = mpv_node(); list.format = MPV_FORMAT_NODE_ARRAY; list.u.list = entries
                                XCTAssertEqual(MPVPlayer.hasDecoderRasterCommand(list), command == "aagedal-decoder-raster")
                            }
                        }
                    }
                }
            }
        }
    }

    func testProtocol2RequiresColorAndTransferProofAndRejectsQuantizedHDR() throws {
        for key in ["primaries", "transfer", "source-bit-depth", "hardware-transfer"] {
            for mutation in 0..<3 {
                XCTAssertNil(withNode(omit: mutation == 0 ? key : nil,
                    wrongType: mutation == 1 ? key : nil, duplicate: mutation == 2 ? key : nil,
                    protocolVersion: 2, pixelFormat: "rgba64", stride: 16, backingByteCount: 16,
                    primaries: "bt2020", transfer: "pq", depth: 10, hardware: 1) {
                        MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
                    }, "\(key), mutation \(mutation)")
            }
        }
        for (primaries, transfer, depth, hardware) in [("bt709", "pq", 10, 1), ("bt2020", "srgb", 10, 1),
                                                       ("unknown", "pq", 10, 1), ("bt2020", "pq", 17, 1),
                                                       ("bt2020", "pq", 10, 2)] {
            XCTAssertNil(withNode(protocolVersion: 2, pixelFormat: "rgba64", stride: 16,
                                  backingByteCount: 16, primaries: primaries, transfer: transfer,
                                  depth: Int64(depth), hardware: Int32(hardware)) {
                MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
            })
        }
        XCTAssertNil(withNode(protocolVersion: 2, primaries: "bt2020", transfer: "pq", depth: 10, hardware: 0) {
            MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
        }, "An 8-bit HDR payload must not replace the required RGBA16 encoding")
    }

    func testProtocol2AcceptsBoundedUHDButKeepsLegacyBounds() throws {
        let raster = try XCTUnwrap(withNode(protocolVersion: 2, codedWidth: 3840,
            stride: 3840 * 4, codedHeight: 2160, rasterWidth: 3840, rasterHeight: 2160,
            backingByteCount: 3840 * 2160 * 4, primaries: "bt709", transfer: "srgb", depth: 8, hardware: 1) {
                MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
            })
        XCTAssertEqual(raster.pixels.width, 3840)
        XCTAssertEqual(raster.pixels.height, 2160)
        XCTAssertTrue(raster.hardwareTransferred)
        XCTAssertEqual(raster.colorEncoding, .sRGB)
        XCTAssertNil(withNode(protocolVersion: 2, codedWidth: 3072, stride: 3072 * 4,
            codedHeight: 3072, rasterWidth: 3072, rasterHeight: 3072,
            primaries: "bt709", transfer: "srgb", depth: 8, hardware: 0) {
                MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
            })
        XCTAssertNil(withNode(protocolVersion: 1, codedWidth: 3840, codedHeight: 2160) {
            MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
        })
    }

    func testProtocol2CarriesOrientedHighDepthHDRIntoTaggedCGImage() throws {
        for (transfer, encoding, name) in [("pq", MPVDecoderRaster.ColorEncoding.bt2020PQ, CGColorSpace.itur_2100_PQ),
                                            ("hlg", .bt2020HLG, CGColorSpace.itur_2100_HLG)] {
            let raster = try XCTUnwrap(withNode(protocolVersion: 2, rotation: 90, pixelFormat: "rgba64",
                stride: 8, rasterWidth: 1, rasterHeight: 2, backingByteCount: 16,
                primaries: "bt2020", transfer: transfer, depth: 10, hardware: 1, mirrored: 1) {
                    MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1)
                })
            XCTAssertEqual(raster.colorEncoding, encoding)
            XCTAssertEqual(raster.sourceBitDepth, 10)
            XCTAssertTrue(raster.mirrored)
            let image = try XCTUnwrap(LoupeFrameCapture.image(from: raster))
            XCTAssertEqual(image.bitsPerComponent, 16)
            XCTAssertEqual(image.colorSpace?.name, name)
            XCTAssertEqual(image.width, 1)
            XCTAssertEqual(image.height, 2)
        }
    }

    func testPQColorConversionRetainsHighlightsAboveSDRWhite() throws {
        let words: [UInt16] = [58982, 58982, 58982, 65535, 32768, 32768, 32768, 65535]
        let data = words.withUnsafeBytes { Data($0) }
        let raw = MPVPlayer.RawScreenshot(data: data, width: 2, height: 1, stride: 16,
                                          format: "rgba64", playbackTime: 0, playbackTimeUncertainty: 0)
        let raster = MPVDecoderRaster(pixels: raw, trackID: 1, rotation: 0, mirrored: false,
                                     sourceBitDepth: 10, colorEncoding: .bt2020PQ)
        let image = try XCTUnwrap(LoupeFrameCapture.image(from: raster))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020))
        var values = [Float](repeating: 0, count: 8)
        try values.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 2, height: 1,
                bitsPerComponent: 32, bytesPerRow: 32, space: colorSpace,
                bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue |
                    CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        }
        XCTAssertTrue(values[0].isFinite)
        XCTAssertGreaterThan(values[0], 1, "PQ highlights must survive color conversion into extended linear RGB")
        XCTAssertGreaterThan(values[0], values[4])
    }

    private func withNode<T>(omit: String? = nil, wrongType: String? = nil,
                             duplicate: String? = nil, falseFlag: String? = nil,
                             protocolVersion: Int64 = 1, codedWidth: Int64 = 2,
                             rotation: Int64 = 0, pts: Double = 1.25,
                             pixelFormat: String = "bgra", reportedByteCount: Int? = nil,
                             nullData: Bool = false, stride: Int64 = 8,
                             codedHeight: Int64 = 1, rasterWidth: Int64 = 2,
                             rasterHeight: Int64 = 1, backingByteCount: Int? = nil,
                             primaries: String? = nil, transfer: String? = nil,
                             depth: Int64? = nil, hardware: Int32? = nil, mirrored: Int32 = 0,
                             _ body: (mpv_node) -> T) -> T {
        let bytes = backingByteCount.map { Data(repeating: 0, count: $0) } ?? Data([0, 0, 255, 0, 0, 255, 0, 0])
        let format = strdup(pixelFormat)!
        let primariesText = primaries.flatMap { strdup($0) }
        let transferText = transfer.flatMap { strdup($0) }
        defer { free(format); free(primariesText); free(transferText) }
        return bytes.withUnsafeBytes { buffer in
            var byteArray = mpv_byte_array(data: nullData ? nil : UnsafeMutableRawPointer(mutating: buffer.baseAddress), size: reportedByteCount ?? bytes.count)
            return withUnsafeMutablePointer(to: &byteArray) { array in
                var integers: [String: Int64] = ["w": rasterWidth, "h": rasterHeight, "stride": stride, "protocol": protocolVersion,
                                               "coded-w": codedWidth, "coded-h": codedHeight, "rotation": rotation, "track-id": 1]
                if let depth { integers["source-bit-depth"] = depth }
                var extra: [String] = []
                if primariesText != nil { extra.append("primaries") }
                if transferText != nil { extra.append("transfer") }
                if hardware != nil { extra.append("hardware-transfer") }
                var names = (Array(integers.keys) + ["pixel-preserving", "presented-frame", "mirrored", "pts", "format", "data"] + extra).filter { $0 != omit }
                if let duplicate { names.append(duplicate) }
                var keys = names.map { strdup($0) }
                defer { keys.forEach { free($0) } }
                var values = names.map { name in
                    var node = mpv_node()
                    if let integer = integers[name] {
                        node.format = MPV_FORMAT_INT64; node.u.int64 = integer
                    } else if name == "pts" {
                        node.format = MPV_FORMAT_DOUBLE; node.u.double_ = pts
                    } else if name == "format" {
                        node.format = MPV_FORMAT_STRING; node.u.string = format
                    } else if name == "primaries" || name == "transfer" {
                        node.format = MPV_FORMAT_STRING; node.u.string = name == "primaries" ? primariesText : transferText
                    } else if name == "data" {
                        node.format = MPV_FORMAT_BYTE_ARRAY; node.u.ba = array
                    } else {
                        node.format = MPV_FORMAT_FLAG
                        node.u.flag = name == "mirrored" ? mirrored : (name == "hardware-transfer" ? hardware! : (name == falseFlag ? 0 : 1))
                    }
                    if name == wrongType { node.format = MPV_FORMAT_NONE }
                    return node
                }
                return keys.withUnsafeMutableBufferPointer { keys in
                    values.withUnsafeMutableBufferPointer { values in
                        var list = mpv_node_list(num: Int32(names.count), values: values.baseAddress, keys: keys.baseAddress)
                        return withUnsafeMutablePointer(to: &list) { list in
                            var result = mpv_node(); result.format = MPV_FORMAT_NODE_MAP; result.u.list = list
                            return body(result)
                        }
                    }
                }
            }
        }
    }
}
