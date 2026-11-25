// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// CoreMediaIO output/sink device discovery, hot-plug monitoring, and broadcast
// format selection using only Apple's OS-level CoreMediaIO and CoreAudio APIs.

import Combine
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import OSLog

// MARK: - User Preferences

nonisolated enum CleanfeedResolutionMode: String, CaseIterable, Sendable, Identifiable {
    case hd720 = "720p"
    case hd1080 = "1080p"
    case dci2k = "2k"
    case uhd2160 = "2160p"
    case dci4k = "4k"
    case matchUpTo1080 = "match1080"
    case matchUpTo2160 = "match2160"
    case matchSource = "auto"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hd720: "720p HD (1280×720)"
        case .hd1080: "1080p HD (1920×1080)"
        case .dci2k: "2K DCI (2048×1080)"
        case .uhd2160: "2160p UHD (3840×2160)"
        case .dci4k: "4K DCI (4096×2160)"
        case .matchUpTo1080: "Match Source (Max 1080p)"
        case .matchUpTo2160: "Match Source (Max 2160p UHD)"
        case .matchSource: "Match Source (Device Max)"
        }
    }

    /// Strict upper bound on output dimensions to prevent sending unsupported
    /// signals (e.g. 4K) to lower-resolution monitors.
    var maxDimensions: (width: Int, height: Int)? {
        switch self {
        case .hd720: (1280, 720)
        case .hd1080, .matchUpTo1080: (1920, 1080)
        case .dci2k: (2048, 1080)
        case .uhd2160, .matchUpTo2160: (3840, 2160)
        case .dci4k: (4096, 2160)
        case .matchSource: nil
        }
    }

    var fixedDimensions: (width: Int, height: Int)? {
        switch self {
        case .hd720: (1280, 720)
        case .hd1080: (1920, 1080)
        case .dci2k: (2048, 1080)
        case .uhd2160: (3840, 2160)
        case .dci4k: (4096, 2160)
        case .matchUpTo1080, .matchUpTo2160, .matchSource: nil
        }
    }
}

nonisolated enum CleanfeedFrameRateMode: String, CaseIterable, Sendable, Identifiable {
    case matchMax30 = "auto30"
    case matchMax60 = "auto60"
    case fps23_98 = "23.98"
    case fps24 = "24"
    case fps25 = "25"
    case fps29_97 = "29.97"
    case fps30 = "30"
    case fps50 = "50"
    case fps59_94 = "59.94"
    case fps60 = "60"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matchMax30: "Match Source (Max 30 fps)"
        case .matchMax60: "Match Source (Max 60 fps)"
        case .fps23_98: "23.98 fps"
        case .fps24: "24 fps"
        case .fps25: "25 fps"
        case .fps29_97: "29.97 fps"
        case .fps30: "30 fps"
        case .fps50: "50 fps"
        case .fps59_94: "59.94 fps"
        case .fps60: "60 fps"
        }
    }

    var fixedFrameRate: Double? {
        switch self {
        case .matchMax30, .matchMax60: nil
        case .fps23_98: 24_000.0 / 1_001.0
        case .fps24: 24.0
        case .fps25: 25.0
        case .fps29_97: 30_000.0 / 1_001.0
        case .fps30: 30.0
        case .fps50: 50.0
        case .fps59_94: 60_000.0 / 1_001.0
        case .fps60: 60.0
        }
    }

    var maxFrameRate: Double? {
        switch self {
        case .matchMax30: 30.05
        case .matchMax60: 60.05
        default: nil
        }
    }
}

nonisolated enum CleanfeedColorMode: String, CaseIterable, Sendable, Identifiable {
    case sdr709 = "rec709"
    case auto = "auto"
    case hdrPQ = "pq"
    case hdrHLG = "hlg"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sdr709: "SDR (Rec.709)"
        case .auto: "Auto (Match Source SDR / HDR)"
        case .hdrPQ: "HDR10 (PQ)"
        case .hdrHLG: "HLG"
        }
    }
}

nonisolated enum CleanfeedPixelFormatMode: String, CaseIterable, Sendable, Identifiable {
    case auto = "auto"
    case tenBitYUV = "v210"
    case eightBitRGB = "BGRA"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .tenBitYUV: "10-bit 4:2:2 (v210)"
        case .eightBitRGB: "8-bit RGB (BGRA)"
        }
    }
}

nonisolated enum CleanfeedColorSpace: String, CaseIterable, Sendable, Equatable {
    case rec709 = "rec709"
    case rec2020 = "rec2020"
    case hdrPQ = "pq"
    case hdrHLG = "hlg"

    var label: String {
        switch self {
        case .rec709: "Rec.709"
        case .rec2020: "Rec.2020"
        case .hdrPQ: "HDR10 (PQ)"
        case .hdrHLG: "HLG"
        }
    }

    var isHDR: Bool {
        self == .hdrPQ || self == .hdrHLG
    }

    var isRec2020: Bool {
        self == .rec2020 || self == .hdrPQ || self == .hdrHLG
    }

    /// MPV `target-prim` option for the cleanfeed follower player.
    var mpvTargetPrimaries: String {
        isRec2020 ? "bt.2020" : "bt.709"
    }

    /// MPV `target-trc` option for the cleanfeed follower player.
    var mpvTargetTransfer: String {
        switch self {
        case .rec709, .rec2020: "bt.1886"
        case .hdrPQ: "pq"
        case .hdrHLG: "hlg"
        }
    }

    var cvColorPrimaries: CFString {
        isRec2020 ? kCVImageBufferColorPrimaries_ITU_R_2020 : kCVImageBufferColorPrimaries_ITU_R_709_2
    }

    var cvTransferFunction: CFString {
        switch self {
        case .rec709: kCVImageBufferTransferFunction_ITU_R_709_2
        case .rec2020: kCVImageBufferTransferFunction_ITU_R_2020
        case .hdrPQ: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        case .hdrHLG: kCVImageBufferTransferFunction_ITU_R_2100_HLG
        }
    }

    var cvYCbCrMatrix: CFString {
        isRec2020 ? kCVImageBufferYCbCrMatrix_ITU_R_2020 : kCVImageBufferYCbCrMatrix_ITU_R_709_2
    }
}

// MARK: - Device & Format Models

nonisolated struct CMIOOutputFormat: Sendable, Equatable, Hashable, Identifiable {
    let index: Int
    let width: Int
    let height: Int
    let pixelFormat: OSType
    let fieldCount: Int
    let colorPrimaries: String?
    let transferFunction: String?
    let ycbcrMatrix: String?
    let frameRates: [Double]

    var id: Int { index }
    var isProgressive: Bool { fieldCount <= 1 }
    var isSupportedPixelFormat: Bool {
        pixelFormat == kCVPixelFormatType_32BGRA
            || pixelFormat == kCVPixelFormatType_422YpCbCr10
            || pixelFormat == kCVPixelFormatType_422YpCbCr8
    }

    var is10Bit: Bool {
        pixelFormat == kCVPixelFormatType_422YpCbCr10
    }

    var colorSpace: CleanfeedColorSpace {
        let transfer = transferFunction ?? ""
        let primaries = colorPrimaries ?? ""
        if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            return .hdrPQ
        }
        if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            return .hdrHLG
        }
        if primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) {
            return .rec2020
        }
        return .rec709
    }

    var pixelFormatCode: String {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA: "BGRA"
        case kCVPixelFormatType_422YpCbCr10: "v210"
        case kCVPixelFormatType_422YpCbCr8: "2vuy"
        case kCVPixelFormatType_32ARGB: "ARGB"
        default:
            String(bytes: [
                UInt8((pixelFormat >> 24) & 0xFF),
                UInt8((pixelFormat >> 16) & 0xFF),
                UInt8((pixelFormat >> 8) & 0xFF),
                UInt8(pixelFormat & 0xFF),
            ], encoding: .ascii) ?? String(format: "0x%08X", pixelFormat)
        }
    }

    var resolutionLabel: String {
        "\(width)×\(height)"
    }
}

nonisolated struct CMIOOutputDevice: Sendable, Equatable, Identifiable {
    let deviceID: CMIODeviceID
    let streamID: CMIOStreamID
    let uid: String
    let name: String
    let manufacturer: String
    let linkedCoreAudioDeviceUID: String?
    let formats: [CMIOOutputFormat]
    let outputBufferQueueSize: Int
    let outputBuffersRequiredForStartup: Int

    var id: String { uid }

    var supportedFormats: [CMIOOutputFormat] {
        formats.filter(\.isSupportedPixelFormat)
    }
}

nonisolated struct CMIOOutputSourceDescriptor: Sendable, Equatable {
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let bitDepth: Int?
    let colorPrimaries: String?
    let colorTransfer: String?

    var desiredColorSpace: CleanfeedColorSpace {
        let transfer = (colorTransfer ?? "").lowercased()
        let primaries = (colorPrimaries ?? "").lowercased()
        if transfer.contains("pq") || transfer.contains("2084") || transfer.contains("smpte2084") {
            return .hdrPQ
        }
        if transfer.contains("hlg") || transfer.contains("arib") || transfer.contains("std-b67") {
            return .hdrHLG
        }
        if primaries.contains("2020") {
            return .rec2020
        }
        return .rec709
    }

    var prefers10Bit: Bool {
        desiredColorSpace.isHDR || (bitDepth ?? 8) > 8
    }

    static func from(metadata: MediaMetadata?, fallbackSize: CGSize?) -> CMIOOutputSourceDescriptor {
        let stream = metadata?.videoStreams.first
        let width = stream?.displayWidth ?? stream?.width ?? fallbackSize.map { Int($0.width.rounded()) }
        let height = stream?.displayHeight ?? stream?.height ?? fallbackSize.map { Int($0.height.rounded()) }
        return CMIOOutputSourceDescriptor(
            width: width,
            height: height,
            frameRate: stream?.frameRate?.value,
            bitDepth: stream?.bitDepth,
            colorPrimaries: stream?.colorPrimaries,
            colorTransfer: stream?.colorTransfer
        )
    }
}

nonisolated struct CMIOOutputFormatSelection: Sendable, Equatable {
    let format: CMIOOutputFormat
    let frameRate: Double
    let colorSpace: CleanfeedColorSpace

    var summaryLabel: String {
        let scan = format.isProgressive ? "p" : "i"
        let fpsText: String
        if abs(frameRate - frameRate.rounded()) < 0.01 {
            fpsText = String(Int(frameRate.rounded()))
        } else {
            fpsText = String(format: "%.2f", frameRate)
        }
        return "\(format.width)×\(format.height)\(scan)\(fpsText) • \(format.pixelFormatCode) • \(colorSpace.label)"
    }
}

// MARK: - Device Capabilities & Format Selection Logic

nonisolated struct CMIOOutputCapabilities: Sendable, Equatable {
    let resolutionModes: [CleanfeedResolutionMode]
    let frameRateModes: [CleanfeedFrameRateMode]
    let colorModes: [CleanfeedColorMode]
    let pixelFormatModes: [CleanfeedPixelFormatMode]

    let effectiveResolutionMode: CleanfeedResolutionMode
    let effectiveFrameRateMode: CleanfeedFrameRateMode
    let effectiveColorMode: CleanfeedColorMode
    let effectivePixelFormatMode: CleanfeedPixelFormatMode

    static func evaluate(
        device: CMIOOutputDevice?,
        preferredResolution: CleanfeedResolutionMode,
        preferredFrameRate: CleanfeedFrameRateMode,
        preferredColor: CleanfeedColorMode,
        preferredPixelFormat: CleanfeedPixelFormatMode
    ) -> CMIOOutputCapabilities {
        guard let device else {
            // Without a connected device, present conservative HD/SDR choices
            // (preserving any previously saved preference so the picker stays valid).
            var resolutions: [CleanfeedResolutionMode] = [.hd720, .hd1080, .matchUpTo1080]
            if !resolutions.contains(preferredResolution) { resolutions.append(preferredResolution) }
            var rates: [CleanfeedFrameRateMode] = [.matchMax30, .matchMax60, .fps23_98, .fps24, .fps25, .fps29_97, .fps30, .fps50, .fps59_94, .fps60]
            if !rates.contains(preferredFrameRate) { rates.append(preferredFrameRate) }
            var colors: [CleanfeedColorMode] = [.sdr709, .auto]
            if !colors.contains(preferredColor) { colors.append(preferredColor) }
            return CMIOOutputCapabilities(
                resolutionModes: resolutions,
                frameRateModes: rates,
                colorModes: colors,
                pixelFormatModes: CleanfeedPixelFormatMode.allCases,
                effectiveResolutionMode: preferredResolution,
                effectiveFrameRateMode: preferredFrameRate,
                effectiveColorMode: preferredColor,
                effectivePixelFormatMode: preferredPixelFormat
            )
        }

        let allCandidates = device.supportedFormats.filter { !$0.frameRates.isEmpty }
        let progressive = allCandidates.filter(\.isProgressive)
        let scanPool = progressive.isEmpty ? allCandidates : progressive

        // 1. Supported resolutions on this hardware.
        let resolutionModes = availableResolutionModes(in: scanPool)
        let effectiveResolution: CleanfeedResolutionMode
        if resolutionModes.contains(preferredResolution) {
            effectiveResolution = preferredResolution
        } else if resolutionModes.contains(.hd1080) {
            effectiveResolution = .hd1080
        } else if resolutionModes.contains(.matchUpTo1080) {
            effectiveResolution = .matchUpTo1080
        } else {
            effectiveResolution = resolutionModes.first ?? .hd1080
        }

        // 2. Narrow pool to formats reachable under effectiveResolution.
        let resPool = formatsMatchingResolution(in: scanPool, mode: effectiveResolution)

        // 3. Supported frame rates for those formats.
        let frameRateModes = availableFrameRateModes(in: resPool)
        let effectiveFrameRate: CleanfeedFrameRateMode
        if frameRateModes.contains(preferredFrameRate) {
            effectiveFrameRate = preferredFrameRate
        } else if frameRateModes.contains(.matchMax30) {
            effectiveFrameRate = .matchMax30
        } else if frameRateModes.contains(.matchMax60) {
            effectiveFrameRate = .matchMax60
        } else {
            effectiveFrameRate = frameRateModes.first ?? .matchMax30
        }

        // 4. Supported color spaces for those formats.
        let colorModes = availableColorModes(in: resPool)
        let effectiveColor: CleanfeedColorMode
        if colorModes.contains(preferredColor) {
            effectiveColor = preferredColor
        } else if colorModes.contains(.sdr709) {
            effectiveColor = .sdr709
        } else {
            effectiveColor = colorModes.first ?? .sdr709
        }

        // 5. Supported pixel formats for the chosen resolution + frame rate.
        let ratePool = formatsMatchingFrameRate(in: resPool, mode: effectiveFrameRate)
        let pixelFormatModes = availablePixelFormatModes(in: ratePool)
        let effectivePixelFormat: CleanfeedPixelFormatMode
        if pixelFormatModes.contains(preferredPixelFormat) {
            effectivePixelFormat = preferredPixelFormat
        } else if pixelFormatModes.contains(.auto) {
            effectivePixelFormat = .auto
        } else {
            effectivePixelFormat = pixelFormatModes.first ?? .auto
        }

        return CMIOOutputCapabilities(
            resolutionModes: resolutionModes,
            frameRateModes: frameRateModes,
            colorModes: colorModes,
            pixelFormatModes: pixelFormatModes,
            effectiveResolutionMode: effectiveResolution,
            effectiveFrameRateMode: effectiveFrameRate,
            effectiveColorMode: effectiveColor,
            effectivePixelFormatMode: effectivePixelFormat
        )
    }

    private static func availableResolutionModes(in pool: [CMIOOutputFormat]) -> [CleanfeedResolutionMode] {
        guard !pool.isEmpty else { return [.hd1080] }
        let dims = Set(pool.map { "\($0.width)x\($0.height)" })
        let hdDims = Set(pool.filter { $0.width <= 1920 && $0.height <= 1080 }.map { "\($0.width)x\($0.height)" })
        let hasAbove1080 = pool.contains { $0.width > 1920 || $0.height > 1080 }
        let hasAboveUHD = pool.contains { $0.width > 3840 || $0.height > 2160 }
        let hasUHD = dims.contains("3840x2160")

        var modes: [CleanfeedResolutionMode] = []
        for fixed: CleanfeedResolutionMode in [.hd720, .hd1080, .dci2k, .uhd2160, .dci4k] {
            if let f = fixed.fixedDimensions, dims.contains("\(f.width)x\(f.height)") {
                modes.append(fixed)
            }
        }
        if !hdDims.isEmpty && (hdDims.count > 1 || hasAbove1080) {
            modes.append(.matchUpTo1080)
        }
        if hasUHD || (hasAbove1080 && !hasAboveUHD) {
            modes.append(.matchUpTo2160)
        }
        if hasAboveUHD || modes.isEmpty {
            modes.append(.matchSource)
        }
        return modes
    }

    private static func formatsMatchingResolution(
        in pool: [CMIOOutputFormat],
        mode: CleanfeedResolutionMode
    ) -> [CMIOOutputFormat] {
        if let fixed = mode.fixedDimensions {
            let exact = pool.filter { $0.width == fixed.width && $0.height == fixed.height }
            if !exact.isEmpty { return exact }
        }
        if let maxDims = mode.maxDimensions {
            let capped = pool.filter { $0.width <= maxDims.width && $0.height <= maxDims.height }
            if !capped.isEmpty { return capped }
        }
        return pool
    }

    private static func availableFrameRateModes(in pool: [CMIOOutputFormat]) -> [CleanfeedFrameRateMode] {
        let allRates = pool.flatMap(\.frameRates)
        guard !allRates.isEmpty else { return [.matchMax30] }

        let hasAtOrBelow30 = allRates.contains { $0 <= 30.05 }
        let hasAbove30 = allRates.contains { $0 > 30.05 }

        var modes: [CleanfeedFrameRateMode] = []
        if hasAtOrBelow30 {
            modes.append(.matchMax30)
        }
        if hasAbove30 {
            modes.append(.matchMax60)
        }
        for fixed: CleanfeedFrameRateMode in [.fps23_98, .fps24, .fps25, .fps29_97, .fps30, .fps50, .fps59_94, .fps60] {
            if let target = fixed.fixedFrameRate,
               allRates.contains(where: { abs($0 - target) < 0.05 }) {
                modes.append(fixed)
            }
        }
        return modes.isEmpty ? [.matchMax30] : modes
    }

    private static func availableColorModes(in pool: [CMIOOutputFormat]) -> [CleanfeedColorMode] {
        let spaces = Set(pool.map(\.colorSpace))
        let hasSDR = spaces.contains(.rec709) || spaces.contains(.rec2020)
        let hasPQ = spaces.contains(.hdrPQ)
        let hasHLG = spaces.contains(.hdrHLG)

        var modes: [CleanfeedColorMode] = []
        if hasSDR || (!hasPQ && !hasHLG) {
            modes.append(.sdr709)
        }
        if hasPQ || hasHLG {
            modes.append(.auto)
        }
        if hasPQ {
            modes.append(.hdrPQ)
        }
        if hasHLG {
            modes.append(.hdrHLG)
        }
        return modes.isEmpty ? [.sdr709] : modes
    }

    private static func formatsMatchingFrameRate(
        in pool: [CMIOOutputFormat],
        mode: CleanfeedFrameRateMode
    ) -> [CMIOOutputFormat] {
        if let fixed = mode.fixedFrameRate {
            let matching = pool.filter { fmt in
                fmt.frameRates.contains(where: { abs($0 - fixed) < 0.05 })
            }
            if !matching.isEmpty { return matching }
        }
        if let cap = mode.maxFrameRate {
            let matching = pool.filter { fmt in
                fmt.frameRates.contains(where: { $0 <= cap })
            }
            if !matching.isEmpty { return matching }
        }
        return pool
    }

    private static func availablePixelFormatModes(in pool: [CMIOOutputFormat]) -> [CleanfeedPixelFormatMode] {
        let hasV210 = pool.contains { $0.pixelFormat == kCVPixelFormatType_422YpCbCr10 }
        let hasBGRA = pool.contains { $0.pixelFormat == kCVPixelFormatType_32BGRA }

        var modes: [CleanfeedPixelFormatMode] = []
        if (hasV210 && hasBGRA) || (!hasV210 && !hasBGRA) {
            modes.append(.auto)
        }
        if hasV210 {
            modes.append(.tenBitYUV)
        }
        if hasBGRA {
            modes.append(.eightBitRGB)
        }
        return modes.isEmpty ? [.auto] : modes
    }
}

nonisolated enum CMIOOutputFormatSelector {
    /// Picks the best supported broadcast format and frame rate for a CoreMediaIO
    /// sink device given source video properties and user display limits.
    static func select(
        device: CMIOOutputDevice,
        source: CMIOOutputSourceDescriptor?,
        resolutionMode: CleanfeedResolutionMode = .hd1080,
        frameRateMode: CleanfeedFrameRateMode = .matchMax30,
        colorMode: CleanfeedColorMode = .sdr709,
        pixelFormatMode: CleanfeedPixelFormatMode = .auto
    ) -> CMIOOutputFormatSelection? {
        let candidates = device.supportedFormats.filter { !$0.frameRates.isEmpty }
        guard !candidates.isEmpty else { return nil }

        let progressive = candidates.filter(\.isProgressive)
        let scanPool = progressive.isEmpty ? candidates : progressive

        // Strictly cap resolution so an HD monitor never receives a 4K signal.
        let resolutionPool: [CMIOOutputFormat]
        if let maxDims = resolutionMode.maxDimensions {
            let capped = scanPool.filter { $0.width <= maxDims.width && $0.height <= maxDims.height }
            resolutionPool = capped.isEmpty ? scanPool : capped
        } else {
            resolutionPool = scanPool
        }

        let desiredWidth: Int
        let desiredHeight: Int
        if let fixed = resolutionMode.fixedDimensions {
            desiredWidth = fixed.width
            desiredHeight = fixed.height
        } else {
            let sw = source?.width ?? 1920
            let sh = source?.height ?? 1080
            let rawWidth: Int
            let rawHeight: Int
            if sw > 2048 || sh > 1080 {
                rawWidth = sw >= 4000 ? 4096 : 3840
                rawHeight = 2160
            } else if sw >= 2000 && sh <= 1080 {
                rawWidth = 2048
                rawHeight = 1080
            } else if sw <= 1280 && sh <= 720 {
                rawWidth = 1280
                rawHeight = 720
            } else {
                rawWidth = 1920
                rawHeight = 1080
            }
            if let maxDims = resolutionMode.maxDimensions,
               rawWidth > maxDims.width || rawHeight > maxDims.height {
                desiredWidth = maxDims.width
                desiredHeight = maxDims.height
            } else {
                desiredWidth = rawWidth
                desiredHeight = rawHeight
            }
        }

        let desiredFPS: Double
        if let fixedFPS = frameRateMode.fixedFrameRate {
            desiredFPS = fixedFPS
        } else {
            let sourceFPS = (source?.frameRate).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 25.0
            if let cap = frameRateMode.maxFrameRate, sourceFPS > cap {
                // Cleanly halve 50 -> 25, 59.94 -> 29.97, 60 -> 30 when capped at 30 fps.
                let halved = sourceFPS / 2.0
                desiredFPS = halved <= cap ? halved : min(sourceFPS, 30.0)
            } else {
                desiredFPS = sourceFPS
            }
        }

        let desiredColor: CleanfeedColorSpace = switch colorMode {
        case .sdr709: .rec709
        case .auto: source?.desiredColorSpace ?? .rec709
        case .hdrPQ: .hdrPQ
        case .hdrHLG: .hdrHLG
        }

        let prefers10Bit: Bool = switch pixelFormatMode {
        case .tenBitYUV: true
        case .eightBitRGB: false
        case .auto: desiredColor.isHDR || (source?.prefers10Bit ?? false)
        }

        // Score every (format, fps) pair deterministically.
        var bestSelection: CMIOOutputFormatSelection?
        var bestScore = Int.min

        for format in resolutionPool {
            let resScore = resolutionScore(
                width: format.width,
                height: format.height,
                desiredWidth: desiredWidth,
                desiredHeight: desiredHeight,
                exactSourceWidth: resolutionMode.fixedDimensions == nil ? source?.width : nil,
                exactSourceHeight: resolutionMode.fixedDimensions == nil ? source?.height : nil
            )
            let colorScore = colorSpaceScore(actual: format.colorSpace, desired: desiredColor)
            let pixScore = pixelFormatScore(
                pixelFormat: format.pixelFormat,
                mode: pixelFormatMode,
                prefers10Bit: prefers10Bit
            )

            let allowedRates: [Double]
            if let cap = frameRateMode.maxFrameRate {
                let cappedRates = format.frameRates.filter { $0 <= cap }
                allowedRates = cappedRates.isEmpty ? format.frameRates : cappedRates
            } else {
                allowedRates = format.frameRates
            }

            for fps in allowedRates {
                let fpsScore = frameRateScore(actual: fps, desired: desiredFPS)
                let total = resScore + fpsScore + colorScore + pixScore
                if total > bestScore {
                    bestScore = total
                    bestSelection = CMIOOutputFormatSelection(
                        format: format,
                        frameRate: fps,
                        colorSpace: format.colorSpace
                    )
                }
            }
        }

        return bestSelection
    }

    private static func resolutionScore(
        width: Int,
        height: Int,
        desiredWidth: Int,
        desiredHeight: Int,
        exactSourceWidth: Int?,
        exactSourceHeight: Int?
    ) -> Int {
        if width == desiredWidth && height == desiredHeight {
            return 100_000
        }
        if let sw = exactSourceWidth, let sh = exactSourceHeight, width == sw && height == sh {
            return 95_000
        }
        // Prefer standard 16:9 HD/UHD over DCI/SD when falling back.
        let standardBonus = (width == 1920 && height == 1080) || (width == 3840 && height == 2160) ? 5_000 : 0
        let coversTarget = width >= desiredWidth && height >= desiredHeight
        let dist = abs(width - desiredWidth) + abs(height - desiredHeight)
        if coversTarget {
            return 70_000 + standardBonus - min(dist, 20_000)
        }
        return 40_000 + standardBonus - min(dist, 30_000)
    }

    private static func frameRateScore(actual: Double, desired: Double) -> Int {
        let diff = abs(actual - desired)
        if diff < 0.05 { return 50_000 }
        if diff < 0.15 { return 48_000 }
        // Exact 2x multiple (e.g. 25 -> 50, 29.97 -> 59.94, 30 -> 60)
        if abs(actual - desired * 2.0) < 0.15 { return 38_000 }
        // Exact 1/2 divisor (e.g. 120 -> 60, 100 -> 50)
        if abs(actual * 2.0 - desired) < 0.15 { return 36_000 }
        // 23.976 <-> 24.000
        if abs(actual - desired) < 1.1 { return 30_000 }
        if actual >= desired {
            return 20_000 - min(Int((actual - desired) * 100), 15_000)
        }
        return 10_000 - min(Int((desired - actual) * 100), 9_000)
    }

    private static func colorSpaceScore(actual: CleanfeedColorSpace, desired: CleanfeedColorSpace) -> Int {
        if actual == desired { return 20_000 }
        if desired.isHDR {
            // Keep HDR family together before falling back to SDR.
            if actual.isHDR { return 12_000 }
            if actual == .rec2020 { return 6_000 }
            return 2_000
        }
        if desired == .rec2020 {
            return actual == .rec709 ? 10_000 : 2_000
        }
        // Desired Rec.709: never accidentally output HDR signaling for SDR content.
        return actual == .rec2020 ? 4_000 : 0
    }

    private static func pixelFormatScore(
        pixelFormat: OSType,
        mode: CleanfeedPixelFormatMode,
        prefers10Bit: Bool
    ) -> Int {
        switch mode {
        case .tenBitYUV:
            switch pixelFormat {
            case kCVPixelFormatType_422YpCbCr10: return 15_000
            case kCVPixelFormatType_32BGRA: return 6_000
            case kCVPixelFormatType_422YpCbCr8: return 4_000
            default: return 0
            }
        case .eightBitRGB:
            switch pixelFormat {
            case kCVPixelFormatType_32BGRA: return 15_000
            case kCVPixelFormatType_422YpCbCr10: return 6_000
            case kCVPixelFormatType_422YpCbCr8: return 4_000
            default: return 0
            }
        case .auto:
            if prefers10Bit {
                switch pixelFormat {
                case kCVPixelFormatType_422YpCbCr10: return 12_000
                case kCVPixelFormatType_32BGRA: return 7_000
                case kCVPixelFormatType_422YpCbCr8: return 4_000
                default: return 0
                }
            } else {
                // For 8-bit SDR, prefer BGRA when available at the chosen fps
                // (zero chroma subsampling, direct GPU blit), and naturally
                // fall back to v210 when fps > 30 at 4K where BGRA isn't offered.
                switch pixelFormat {
                case kCVPixelFormatType_32BGRA: return 8_000
                case kCVPixelFormatType_422YpCbCr10: return 6_500
                case kCVPixelFormatType_422YpCbCr8: return 5_000
                default: return 0
                }
            }
        }
    }
}

// MARK: - CoreMediaIO Discovery

nonisolated enum CMIOOutputDeviceDiscovery {
    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "Cleanfeed")

    static func discoverOutputDevices() -> [CMIOOutputDevice] {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        var dataUsed: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var deviceIDs = [CMIODeviceID](repeating: 0, count: deviceCount)
        let getStatus = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            dataSize,
            &dataUsed,
            &deviceIDs
        )
        guard getStatus == noErr else { return [] }

        var outputDevices: [CMIOOutputDevice] = []
        for deviceID in deviceIDs {
            guard let sinkStreamID = findOutputSinkStream(for: deviceID) else { continue }
            let name = copyStringProperty(deviceID, selector: kCMIOObjectPropertyName) ?? "Video Output \(deviceID)"
            let manufacturer = copyStringProperty(deviceID, selector: kCMIOObjectPropertyManufacturer) ?? ""
            let uid = copyStringProperty(deviceID, selector: kCMIODevicePropertyDeviceUID) ?? "cmio-\(deviceID)"
            let linkedAudio = copyStringProperty(deviceID, selector: kCMIODevicePropertyLinkedCoreAudioDeviceUID)
            let formats = readFormats(for: sinkStreamID)
            let queueSize = readUInt32Property(sinkStreamID, selector: kCMIOStreamPropertyOutputBufferQueueSize)
                .map(Int.init) ?? 6
            let startupBuffers = readUInt32Property(sinkStreamID, selector: kCMIOStreamPropertyOutputBuffersRequiredForStartup)
                .map(Int.init) ?? 3

            outputDevices.append(CMIOOutputDevice(
                deviceID: deviceID,
                streamID: sinkStreamID,
                uid: uid,
                name: name,
                manufacturer: manufacturer,
                linkedCoreAudioDeviceUID: linkedAudio?.isEmpty == false ? linkedAudio : nil,
                formats: formats,
                outputBufferQueueSize: max(queueSize, 3),
                outputBuffersRequiredForStartup: max(startupBuffers, 1)
            ))
        }

        return outputDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolves the live `CMFormatDescription` object owned by the CMIO stream at
    /// `formatIndex`, suitable for passing directly to `kCMIOStreamPropertyFormatDescription`.
    static func copyFormatDescription(streamID: CMIOStreamID, at index: Int) -> CMFormatDescription? {
        guard let cfArray = copyFormatDescriptionsArray(for: streamID) else { return nil }
        let count = CFArrayGetCount(cfArray)
        guard index >= 0, index < count,
              let raw = CFArrayGetValueAtIndex(cfArray, index) else { return nil }
        return unsafeBitCast(raw, to: CMFormatDescription.self)
    }

    private static func findOutputSinkStream(for deviceID: CMIODeviceID) -> CMIOStreamID? {
        var streamsAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &size) == noErr,
              size > 0 else { return nil }

        let count = Int(size) / MemoryLayout<CMIOStreamID>.size
        var streams = [CMIOStreamID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, size, &used, &streams) == noErr else {
            return nil
        }

        for streamID in streams {
            // kCMIOStreamPropertyDirection: 0 = output/sink, 1 = input/source.
            if let dir = readUInt32Property(streamID, selector: kCMIOStreamPropertyDirection), dir == 0 {
                return streamID
            }
        }
        return nil
    }

    private static func copyFormatDescriptionsArray(for streamID: CMIOStreamID) -> CFArray? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescriptions),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(streamID, &address) else { return nil }
        var unmanagedArray: Unmanaged<CFArray>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &unmanagedArray) { ptr in
            CMIOObjectGetPropertyData(
                streamID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Unmanaged<CFArray>?>.size),
                &used,
                ptr
            )
        }
        guard status == noErr else { return nil }
        return unmanagedArray?.takeRetainedValue()
    }

    private static func readFormats(for streamID: CMIOStreamID) -> [CMIOOutputFormat] {
        guard let cfArray = copyFormatDescriptionsArray(for: streamID) else { return [] }
        let count = CFArrayGetCount(cfArray)
        var result: [CMIOOutputFormat] = []
        result.reserveCapacity(count)

        for idx in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(cfArray, idx) else { continue }
            let fd = unsafeBitCast(raw, to: CMFormatDescription.self)
            let subtype = CMFormatDescriptionGetMediaSubType(fd)
            let dims = CMVideoFormatDescriptionGetDimensions(fd)
            guard dims.width > 0, dims.height > 0 else { continue }

            let extensions = CMFormatDescriptionGetExtensions(fd) as? [CFString: Any]
            let primaries = extensions?[kCMFormatDescriptionExtension_ColorPrimaries] as? String
            let transfer = extensions?[kCMFormatDescriptionExtension_TransferFunction] as? String
            let matrix = extensions?[kCMFormatDescriptionExtension_YCbCrMatrix] as? String
            let fieldCount = (extensions?[kCMFormatDescriptionExtension_FieldCount] as? NSNumber)?.intValue ?? 1
            let frameRates = readFrameRates(for: streamID, formatDescription: fd)

            result.append(CMIOOutputFormat(
                index: idx,
                width: Int(dims.width),
                height: Int(dims.height),
                pixelFormat: subtype,
                fieldCount: fieldCount,
                colorPrimaries: primaries,
                transferFunction: transfer,
                ycbcrMatrix: matrix,
                frameRates: frameRates
            ))
        }
        return result
    }

    private static func readFrameRates(for streamID: CMIOStreamID, formatDescription: CMFormatDescription) -> [Double] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFrameRates),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var qualifier: CMFormatDescription = formatDescription
        var size: UInt32 = 0
        var used: UInt32 = 0
        let sizeStatus = withUnsafePointer(to: &qualifier) { qPtr in
            CMIOObjectGetPropertyDataSize(
                streamID,
                &address,
                UInt32(MemoryLayout<CMFormatDescription>.size),
                qPtr,
                &size
            )
        }
        guard sizeStatus == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<Float64>.size
        var rates = [Float64](repeating: 0, count: count)
        let getStatus = withUnsafePointer(to: &qualifier) { qPtr in
            CMIOObjectGetPropertyData(
                streamID,
                &address,
                UInt32(MemoryLayout<CMFormatDescription>.size),
                qPtr,
                size,
                &used,
                &rates
            )
        }
        guard getStatus == noErr else { return [] }
        return rates.filter { $0.isFinite && $0 > 0 }.sorted()
    }

    static func copyStringProperty(_ objectID: CMIOObjectID, selector: Int) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(objectID, &address) else { return nil }
        var unmanagedString: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &unmanagedString) { ptr in
            CMIOObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Unmanaged<CFString>?>.size),
                &used,
                ptr
            )
        }
        guard status == noErr else { return nil }
        return unmanagedString?.takeRetainedValue() as String?
    }

    static func readUInt32Property(_ objectID: CMIOObjectID, selector: Int) -> UInt32? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(objectID, &address) else { return nil }
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &used,
            &value
        )
        return status == noErr ? value : nil
    }
}

// MARK: - Live Hot-Plug Monitor

@MainActor
final class CMIOOutputDeviceMonitor: ObservableObject {
    @Published private(set) var devices: [CMIOOutputDevice] = []

    private let listenerQueue = DispatchQueue(label: "com.aagedal.MediaPlayer.cmio.monitor")
    private nonisolated(unsafe) var listenerBlock: CMIOObjectPropertyListenerBlock?
    private var isMonitoring = false

    init() {
        refresh()
        startMonitoring()
    }

    deinit {
        if let block = listenerBlock {
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            CMIOObjectRemovePropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                listenerQueue,
                block
            )
        }
    }

    func refresh() {
        let discovered = CMIOOutputDeviceDiscovery.discoverOutputDevices()
        if discovered != devices {
            devices = discovered
        }
    }

    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        listenerBlock = block
        CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            listenerQueue,
            block
        )
    }
}
