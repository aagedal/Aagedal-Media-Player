// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Libmpv

/// Scalar-only provenance for one native request. No borrowed mpv storage or
/// payload owner can escape through a failed result.
nonisolated enum MPVScopeFailureReason: String, Sendable {
    case screenshotOverride, invalidWidth, playerUnavailable
    case capabilityLookupFailed, capabilityMalformed, commandUnavailable
    case initialTrackLookupFailed, commandFailed, finalTrackLookupFailed, trackChanged
    case invalidMap, invalidProtocol, invalidDimensions, invalidTrack, invalidFormat
    case invalidTimestamp, invalidColor, invalidWaveform, invalidParade, invalidVectorscope
    case imageConstructionFailed
}

nonisolated struct MPVScopeFailure: Error, Equatable, Sendable, CustomStringConvertible {
    let reason: MPVScopeFailureReason
    var status: Int32? = nil
    var expectedTrack: Int64? = nil
    var actualTrack: Int64? = nil

    var description: String {
        "reason=\(reason.rawValue),status=\(status.map(String.init) ?? "none"),expectedTrack=\(expectedTrack.map(String.init) ?? "none"),actualTrack=\(actualTrack.map(String.init) ?? "none")"
    }
}

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

    /// Cache the original scalar reason, including a failed capability probe.
    /// This preserves the existing false-cache behavior until backend reset.
    static func capabilityFailure(status: Int32, node: mpv_node) -> MPVScopeFailure? {
        guard status >= 0 else { return MPVScopeFailure(reason: .capabilityLookupFailed, status: status) }
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list,
              let values = list.pointee.values else { return MPVScopeFailure(reason: .capabilityMalformed) }
        var malformed = false
        for i in 0..<Int(list.pointee.num) {
            guard let fields = fields(values[i]), let name = fields["name"],
                  name.format == MPV_FORMAT_STRING, let string = name.u.string else {
                malformed = true
                continue
            }
            if String(cString: string) == "aagedal-scopes" { return nil }
        }
        return MPVScopeFailure(reason: malformed ? .capabilityMalformed : .commandUnavailable)
    }

    static func decode(_ node: mpv_node, expectedWidth: Int, trackID: Int64) -> Self? {
        try? decodeValidated(node, expectedWidth: expectedWidth, trackID: trackID)
    }

    static func decodeResult(_ node: mpv_node, expectedWidth: Int, trackID: Int64) -> Result<Self, MPVScopeFailure> {
        do { return .success(try decodeValidated(node, expectedWidth: expectedWidth, trackID: trackID)) }
        catch { return .failure(error) }
    }

    private static func decodeValidated(_ node: mpv_node, expectedWidth: Int, trackID: Int64) throws(MPVScopeFailure) -> Self {
        guard let f = fields(node) else { throw MPVScopeFailure(reason: .invalidMap) }
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
        guard integer("protocol") == 1 else { throw MPVScopeFailure(reason: .invalidProtocol) }
        guard expectedWidth >= 64, expectedWidth <= 1440,
              integer("w") == Int64(expectedWidth),
              let height64 = integer("h"), let height = Int(exactly: height64),
              height == Int((Double(expectedWidth)*9/16).rounded()) else {
            throw MPVScopeFailure(reason: .invalidDimensions)
        }
        guard integer("track-id") == trackID else {
            throw MPVScopeFailure(reason: .invalidTrack, expectedTrack: trackID, actualTrack: integer("track-id"))
        }
        guard string("format") == "bgra-premultiplied" else { throw MPVScopeFailure(reason: .invalidFormat) }
        guard let pts = double("pts"), pts >= 0 else { throw MPVScopeFailure(reason: .invalidTimestamp) }
        guard let primaries = string("primaries"), let transfer = string("transfer"),
              let peak = double("peak-nits") else { throw MPVScopeFailure(reason: .invalidColor) }
        let sdrTransfers = ["srgb", "bt1886", "gamma22", "gamma24"]
        guard (primaries == "bt709" && sdrTransfers.contains(transfer) && peak == 100)
                || (primaries == "bt2020" && transfer == "pq" && peak == 10000)
                || (primaries == "bt2020" && transfer == "hlg" && peak == 1000) else { throw MPVScopeFailure(reason: .invalidColor) }
        func image(_ key: String, width: Int, failure: MPVScopeFailureReason) throws(MPVScopeFailure) -> CGImage {
            let count = width*height*4
            guard let n = f[key], n.format == MPV_FORMAT_BYTE_ARRAY, let ba = n.u.ba,
                  ba.pointee.size == count, let bytes = ba.pointee.data else {
                throw MPVScopeFailure(reason: failure)
            }
            guard let provider = CGDataProvider(data: Data(bytes: bytes, count: count) as CFData),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                throw MPVScopeFailure(reason: .imageConstructionFailed)
            }
            guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width*4, space: colorSpace,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                   | CGBitmapInfo.byteOrder32Little.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw MPVScopeFailure(reason: .imageConstructionFailed)
            }
            return image
        }
        let waveform = try image("waveform", width: expectedWidth, failure: .invalidWaveform)
        let parade = try image("parade", width: expectedWidth, failure: .invalidParade)
        let vectorscope = try image("vectorscope", width: height, failure: .invalidVectorscope)
        return Self(waveform: waveform, parade: parade, vectorscope: vectorscope, pts: pts,
                    trackID: trackID, transfer: transfer, primaries: primaries, peakNits: Float(peak))
    }
}
