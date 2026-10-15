// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Libmpv

/// Scope images contain diagnostic colors, not source image pixels. All three
/// plots and their source-frame metadata come from one native analysis request.
nonisolated struct MPVScopePlots: Sendable {
    let waveform: CGImage
    let parade: CGImage
    let vectorscope: CGImage
    let pts: Double
    let trackID: Int64
    let transfer: String
    let primaries: String
    let peakNits: Float

    static func fields(_ node: mpv_node) -> [String: mpv_node]? {
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list,
              list.pointee.num > 0, list.pointee.num <= 32,
              let keys = list.pointee.keys, let values = list.pointee.values else { return nil }
        var fields: [String: mpv_node] = [:]
        for i in 0..<Int(list.pointee.num) {
            guard let key = keys[i] else { return nil }
            let name = String(cString: key)
            guard fields[name] == nil else { return nil }
            fields[name] = values[i]
        }
        return fields
    }

    static func decode(_ node: mpv_node, expectedWidth: Int, trackID: Int64) -> Self? {
        guard let f = fields(node) else { return nil }
        func integer(_ key: String) -> Int64? {
            guard let n = f[key], n.format == MPV_FORMAT_INT64 else { return nil }
            return n.u.int64
        }
        func string(_ key: String) -> String? {
            guard let n = f[key], n.format == MPV_FORMAT_STRING, let p = n.u.string else { return nil }
            return String(cString: p)
        }
        func double(_ key: String) -> Double? {
            guard let n = f[key], n.format == MPV_FORMAT_DOUBLE, n.u.double_.isFinite else { return nil }
            return n.u.double_
        }
        guard integer("protocol") == 1, expectedWidth >= 64, expectedWidth <= 1440,
              integer("w") == Int64(expectedWidth),
              let height64 = integer("h"), let height = Int(exactly: height64),
              height == Int((Double(expectedWidth)*9/16).rounded()),
              integer("track-id") == trackID,
              string("format") == "bgra-premultiplied",
              let pts = double("pts"), pts >= 0,
              let primaries = string("primaries"), let transfer = string("transfer"),
              let peak = double("peak-nits") else { return nil }
        let sdrTransfers = ["srgb", "bt1886", "gamma22", "gamma24"]
        guard (primaries == "bt709" && sdrTransfers.contains(transfer) && peak == 100)
                || (primaries == "bt2020" && transfer == "pq" && peak == 10000)
                || (primaries == "bt2020" && transfer == "hlg" && peak == 1000) else { return nil }
        func image(_ key: String, width: Int) -> CGImage? {
            let count = width*height*4
            guard let n = f[key], n.format == MPV_FORMAT_BYTE_ARRAY, let ba = n.u.ba,
                  ba.pointee.size == count, let bytes = ba.pointee.data,
                  let provider = CGDataProvider(data: Data(bytes: bytes, count: count) as CFData),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width*4, space: colorSpace,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                   | CGBitmapInfo.byteOrder32Little.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        guard let waveform = image("waveform", width: expectedWidth),
              let parade = image("parade", width: expectedWidth),
              let vectorscope = image("vectorscope", width: height) else { return nil }
        return Self(waveform: waveform, parade: parade, vectorscope: vectorscope, pts: pts,
                    trackID: trackID, transfer: transfer, primaries: primaries, peakNits: Float(peak))
    }
}
