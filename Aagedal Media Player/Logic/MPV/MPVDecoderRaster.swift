// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Libmpv

/// Versioned private provider protocol. This is deliberately separate from
/// screenshot-raw: dimensions and RGB layout never prove source provenance.
nonisolated struct MPVDecoderRaster: Sendable {
    let pixels: MPVPlayer.RawScreenshot
    let trackID: Int64
    let rotation: Int
    let mirrored: Bool

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
        guard integer("protocol") == 1,
              flag("pixel-preserving") == true,
              flag("presented-frame") == true,
              integer("track-id") == trackBefore,
              let width = integer("coded-w"), let height = integer("coded-h"),
              width > 0, height > 0, width <= 4096, height <= 4096,
              width * height <= 4_194_304,
              let rotation = integer("rotation"), [0, 90, 180, 270].contains(rotation),
              let mirrored = flag("mirrored"),
              let pts = fields["pts"], pts.format == MPV_FORMAT_DOUBLE,
              pts.u.double_.isFinite, pts.u.double_ >= 0,
              let format = fields["format"], format.format == MPV_FORMAT_STRING,
              let formatName = format.u.string, String(cString: formatName) == "bgra",
              let rasterWidth = integer("w"), let rasterHeight = integer("h"),
              let stride = integer("stride"),
              rasterWidth > 0, rasterWidth <= 4096,
              rasterHeight > 0, rasterHeight <= 4096,
              rasterWidth * rasterHeight <= 4_194_304,
              stride >= rasterWidth * 4,
              // Bound before the shared screenshot parser copies provider data.
              // Leave room for mpv's row alignment above the 16 MiB pixel limit.
              stride <= (64 * 1024 * 1024) / rasterHeight,
              let data = fields["data"], data.format == MPV_FORMAT_BYTE_ARRAY,
              let bytes = data.u.ba, bytes.pointee.size == stride * rasterHeight,
              let pixels = MPVPlayer.rawScreenshot(from: node, playbackTime: pts.u.double_,
                                                  playbackTimeUncertainty: 0) else { return nil }
        let swapsAxes = rotation == 90 || rotation == 270
        guard Int64(pixels.width) == (swapsAxes ? height : width),
              Int64(pixels.height) == (swapsAxes ? width : height) else { return nil }
        return Self(pixels: pixels, trackID: trackBefore, rotation: Int(rotation), mirrored: mirrored)
    }
}
