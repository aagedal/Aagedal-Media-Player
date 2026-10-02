// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
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
        XCTAssertNil(withNode(protocolVersion: 2) { MPVDecoderRaster.parse($0, trackBefore: 1, trackAfter: 1) })
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

    private func withNode<T>(omit: String? = nil, wrongType: String? = nil,
                             duplicate: String? = nil, falseFlag: String? = nil,
                             protocolVersion: Int64 = 1, codedWidth: Int64 = 2,
                             rotation: Int64 = 0, pts: Double = 1.25,
                             _ body: (mpv_node) -> T) -> T {
        let bytes = Data([0, 0, 255, 0, 0, 255, 0, 0])
        let format = strdup("bgr0")!
        defer { free(format) }
        return bytes.withUnsafeBytes { buffer in
            var byteArray = mpv_byte_array(data: UnsafeMutableRawPointer(mutating: buffer.baseAddress), size: bytes.count)
            return withUnsafeMutablePointer(to: &byteArray) { array in
                let integers: [String: Int64] = ["w": 2, "h": 1, "stride": 8, "protocol": protocolVersion,
                                               "coded-w": codedWidth, "coded-h": 1, "rotation": rotation, "track-id": 1]
                var names = (Array(integers.keys) + ["pixel-preserving", "presented-frame", "mirrored", "pts", "format", "data"]).filter { $0 != omit }
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
                    } else if name == "data" {
                        node.format = MPV_FORMAT_BYTE_ARRAY; node.u.ba = array
                    } else {
                        node.format = MPV_FORMAT_FLAG; node.u.flag = name == "mirrored" || name == falseFlag ? 0 : 1
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
