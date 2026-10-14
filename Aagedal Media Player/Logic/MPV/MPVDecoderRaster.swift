// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CoreGraphics
import Libmpv

/// Versioned private provider protocol. This is deliberately separate from
/// screenshot-raw: dimensions and RGB layout never prove source provenance.
nonisolated struct MPVDecoderRaster: Sendable {
    let pixels: MPVPlayer.RawScreenshot
    let trackID: Int64
    let rotation: Int
    let mirrored: Bool
    var hardwareTransferred = false
    var sourceBitDepth = 8
    var colorEncoding: ColorEncoding?

    enum ColorEncoding: Sendable, Equatable {
        case sRGB, bt709Gamma22, bt709Gamma24, bt2020PQ, bt2020HLG

        init?(primaries: String, transfer: String) {
            switch (primaries, transfer) {
            case ("bt709", "srgb"): self = .sRGB
            case ("bt709", "gamma22"): self = .bt709Gamma22
            case ("bt709", "bt1886"), ("bt709", "gamma24"): self = .bt709Gamma24
            case ("bt2020", "pq"): self = .bt2020PQ
            case ("bt2020", "hlg"): self = .bt2020HLG
            default: return nil
            }
        }

        var isHDR: Bool {
            switch self {
            case .bt2020PQ, .bt2020HLG: true
            default: false
            }
        }

        var colorSpace: CGColorSpace? {
            switch self {
            case .sRGB: return CGColorSpace(name: CGColorSpace.sRGB)
            case .bt2020PQ: return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
            case .bt2020HLG: return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
            case .bt709Gamma22, .bt709Gamma24:
                let white: [CGFloat] = [0.95047, 1, 1.08883]
                let gamma: [CGFloat] = Array(repeating: self == .bt709Gamma22 ? 2.2 : 2.4, count: 3)
                let matrix: [CGFloat] = [0.4124564, 0.2126729, 0.0193339,
                                         0.3575761, 0.7151522, 0.1191920,
                                         0.1804375, 0.0721750, 0.9503041]
                return white.withUnsafeBufferPointer { white in
                    gamma.withUnsafeBufferPointer { gamma in
                        matrix.withUnsafeBufferPointer { matrix in
                            CGColorSpace(calibratedRGBWhitePoint: white.baseAddress!, blackPoint: nil,
                                         gamma: gamma.baseAddress!, matrix: matrix.baseAddress!)
                        }
                    }
                }
            }
        }
    }

    /// The provider must bind this raster to the currently presented frame,
    /// before all video filters, PAR scaling, crop, and display conversion.
    /// Both track reads bracket the command while holding MPVPlayer's queue.
    static func parse(_ node: mpv_node, trackBefore: Int64?, trackAfter: Int64?) -> Self? {
        guard let trackBefore, trackBefore > 0, trackBefore == trackAfter,
              node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list,
              list.pointee.num > 0, let keys = list.pointee.keys,
              let values = list.pointee.values else { return nil }
        var fields: [String: mpv_node] = [:]
        for index in 0..<Int(list.pointee.num) {
            guard let key = keys[index] else { return nil }
            let name = String(cString: key)
            guard fields.updateValue(values[index], forKey: name) == nil else { return nil }
        }
        func integer(_ key: String) -> Int64? {
            guard let value = fields[key], value.format == MPV_FORMAT_INT64 else { return nil }
            return value.u.int64
        }
        func flag(_ key: String) -> Bool? {
            guard let value = fields[key], value.format == MPV_FORMAT_FLAG,
                  value.u.flag == 0 || value.u.flag == 1 else { return nil }
            return value.u.flag == 1
        }
        func string(_ key: String) -> String? {
            guard let value = fields[key], value.format == MPV_FORMAT_STRING,
                  let text = value.u.string else { return nil }
            return String(cString: text)
        }
        guard let version = integer("protocol"), version == 1 || version == 2 else { return nil }
        let encoding: ColorEncoding?
        let hardware: Bool
        let depth: Int64
        if version == 2 {
            guard let primaries = string("primaries"), let transfer = string("transfer"),
                  let color = ColorEncoding(primaries: primaries, transfer: transfer),
                  let transferred = flag("hardware-transfer"),
                  let bitDepth = integer("source-bit-depth"), (8...16).contains(bitDepth) else { return nil }
            encoding = color
            hardware = transferred
            depth = bitDepth
        } else {
            encoding = nil
            hardware = false
            depth = 8
        }
        let highDepth = depth > 8 || encoding?.isHDR == true
        let pixelLimit: Int64 = version == 2 ? 8_847_360 : 4_194_304
        let byteLimit: Int64 = (version == 2 ? 72 : 64) * 1024 * 1024
        let bytesPerPixel: Int64 = highDepth ? 8 : 4
        guard
              flag("pixel-preserving") == true,
              flag("presented-frame") == true,
              integer("track-id") == trackBefore,
              let width = integer("coded-w"), let height = integer("coded-h"),
              width > 0, height > 0, width <= 4096, height <= 4096,
              width * height <= pixelLimit,
              let rotation = integer("rotation"), [0, 90, 180, 270].contains(rotation),
              let mirrored = flag("mirrored"),
              let pts = fields["pts"], pts.format == MPV_FORMAT_DOUBLE,
              pts.u.double_.isFinite, pts.u.double_ >= 0,
              string("format") == (highDepth ? "rgba64" : "bgra"),
              let rasterWidth = integer("w"), let rasterHeight = integer("h"),
              let stride = integer("stride"),
              rasterWidth > 0, rasterWidth <= 4096,
              rasterHeight > 0, rasterHeight <= 4096,
              rasterWidth * rasterHeight <= pixelLimit,
              // Reject inconsistent orientation before copying a potentially 72 MiB payload.
              rasterWidth == ((rotation == 90 || rotation == 270) ? height : width),
              rasterHeight == ((rotation == 90 || rotation == 270) ? width : height),
              stride >= rasterWidth * bytesPerPixel,
              // Bound before the shared screenshot parser copies provider data.
              // Protocol 2 allows a DCI UHD RGBA16 raster and aligned rows.
              stride <= byteLimit / rasterHeight,
              let data = fields["data"], data.format == MPV_FORMAT_BYTE_ARRAY,
              let bytes = data.u.ba, bytes.pointee.size == stride * rasterHeight,
              let pixels = MPVPlayer.rawScreenshot(from: node, playbackTime: pts.u.double_,
                                                  playbackTimeUncertainty: 0) else { return nil }
        return Self(pixels: pixels, trackID: trackBefore, rotation: Int(rotation), mirrored: mirrored,
                    hardwareTransferred: hardware, sourceBitDepth: Int(depth), colorEncoding: encoding)
    }
}
