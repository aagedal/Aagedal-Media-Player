// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum ScreenshotFormat: String, CaseIterable, Sendable {
    case jxl = "jxl"
    case png = "png"
    case jpeg = "jpeg"

    var label: String {
        switch self {
        case .jxl: "JPEG XL"
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .jxl: "jxl"
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

nonisolated enum TrimExportFormat: String, CaseIterable, Sendable {
    case copy = "copy"
    case gif = "gif"
    case animatedAVIF = "animatedAVIF"
    case hardwareH264 = "hardwareH264"
    case hardwareH265 = "hardwareH265"

    var label: String {
        switch self {
        case .copy: "Lossless Copy (Keyframe-Aligned)"
        case .gif: "GIF"
        case .animatedAVIF: "Animated AVIF"
        case .hardwareH264: "Exact H.264 (Hardware)"
        case .hardwareH265: "Exact H.265 (Hardware)"
        }
    }

    var fileExtension: String? {
        switch self {
        case .copy: nil
        case .gif: "gif"
        case .animatedAVIF: "avif"
        case .hardwareH264, .hardwareH265: "mp4"
        }
    }
}

nonisolated enum ExportWidthPreset: Int, CaseIterable, Sendable {
    case original = 0
    case w2160 = 2160
    case w1080 = 1080
    case w720 = 720
    case w480 = 480
    case w320 = 320

    var label: String {
        switch self {
        case .original: "Original"
        case .w2160: "2160"
        case .w1080: "1080"
        case .w720: "720"
        case .w480: "480"
        case .w320: "320"
        }
    }
}

nonisolated struct ScreenshotCommandRequest: Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let time: Double
    let format: ScreenshotFormat
    let bitDepth: Int
    let hasAlpha: Bool
    let isInterlaced: Bool
    let jxlQuality: Double
    let jpegQuality: Double
    let colorMetadata: MediaMetadata.VideoStream?
}

nonisolated enum ScreenshotCommandBuilder {
    static func arguments(for request: ScreenshotCommandRequest) -> [String] {
        let videoFilter = request.isInterlaced
            ? "bwdif=mode=0:parity=-1:deint=all,scale=iw*sar:ih"
            : "scale=iw*sar:ih"

        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(request.time),
            "-i", request.sourceURL.path,
            "-frames:v", "1",
            "-vf", videoFilter,
        ]

        switch request.format {
        case .jxl:
            let pixelFormat: String
            if request.bitDepth > 8 {
                pixelFormat = request.hasAlpha ? "rgba64le" : "rgb48le"
            } else {
                pixelFormat = request.hasAlpha ? "rgba" : "rgb24"
            }
            let quality = normalized(request.jxlQuality, range: 0...100, defaultValue: 90)
            let distance = (100 - quality) / 100 * 15
            arguments += [
                "-pix_fmt", pixelFormat,
                "-c:v", "libjxl",
                "-distance", String(format: "%.2f", distance),
                "-effort", "7",
            ]

        case .png:
            let pixelFormat: String
            if request.bitDepth > 8 {
                pixelFormat = request.hasAlpha ? "rgba64be" : "rgb48be"
            } else {
                pixelFormat = request.hasAlpha ? "rgba" : "rgb24"
            }
            arguments += ["-pix_fmt", pixelFormat, "-c:v", "png"]

        case .jpeg:
            let quality = normalized(request.jpegQuality, range: 0...100, defaultValue: 90)
            let quantizer = 1 + (100 - quality) / 100 * 30
            arguments += [
                "-pix_fmt", "yuvj444p",
                "-c:v", "mjpeg",
                "-q:v", String(format: "%.1f", quantizer),
            ]
        }

        appendColorArguments(from: request.colorMetadata, to: &arguments)
        arguments += ["-n", request.destinationURL.path]
        return arguments
    }

    private static func appendColorArguments(
        from stream: MediaMetadata.VideoStream?,
        to arguments: inout [String]
    ) {
        guard let stream else { return }

        if let value = normalizedColorPrimaries(stream.colorPrimaries) {
            arguments += ["-color_primaries", value]
        }
        if let value = normalizedColorTransfer(stream.colorTransfer) {
            arguments += ["-color_trc", value]
        }
        if let value = normalizedColorSpace(stream.colorSpace) {
            arguments += ["-colorspace", value]
        }
        if let value = normalizedColorRange(stream.colorRange) {
            arguments += ["-color_range", value]
        }
    }

    private static func normalizedColorPrimaries(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: [
            "bt709", "bt470bg", "smpte170m", "smpte240m", "bt2020", "smpte432", "smpte432-1",
        ], mapping: [
            "bt2020-10": "bt2020", "bt2020-12": "bt2020",
        ])
    }

    private static func normalizedColorTransfer(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: [
            "bt709", "smpte2084", "arib-std-b67", "iec61966-2-4", "bt470bg", "smpte170m", "bt2020-10", "bt2020-12",
        ], mapping: [:])
    }

    private static func normalizedColorSpace(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: [
            "bt709", "smpte170m", "smpte240m", "bt2020nc", "bt2020c", "bt2020ncl",
        ], mapping: [
            "bt2020": "bt2020nc", "bt2020-ncl": "bt2020nc", "bt2020-cl": "bt2020c",
        ])
    }

    private static func normalizedColorRange(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: ["tv", "pc"], mapping: [
            "limited": "tv", "full": "pc",
        ])
    }

    private static func normalizedColorValue(
        _ value: String?,
        allowed: Set<String>,
        mapping: [String: String]
    ) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty,
              raw != "unknown",
              raw != "unspecified",
              raw != "na" else {
            return nil
        }
        return mapping[raw] ?? (allowed.contains(raw) ? raw : nil)
    }

    private static func normalized(
        _ value: Double,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

nonisolated struct TrimExportCommandRequest: Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let inPoint: Double
    let outPoint: Double
    let format: TrimExportFormat
    let width: Int
    let gifFrameRate: Double
    let avifQuality: Double
    let avifSpeed: Double
    let h264Quality: Double
    let h265Quality: Double

    var duration: Double { outPoint - inPoint }
}

nonisolated enum TrimExportCommandBuilder {
    static func arguments(for request: TrimExportCommandRequest) -> [String] {
        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(request.inPoint),
            "-i", request.sourceURL.path,
            "-t", String(request.duration),
        ]

        arguments += formatArguments(for: request)
        arguments += ["-n", request.destinationURL.path]
        return arguments
    }

    private static func formatArguments(for request: TrimExportCommandRequest) -> [String] {
        switch request.format {
        case .copy:
            return ["-c", "copy", "-avoid_negative_ts", "make_zero"]

        case .gif:
            let fps = Int(normalized(request.gifFrameRate, range: 5...30, defaultValue: 15))
            let components = [
                "fps=\(fps)",
                scaleFilter(width: request.width, defaultWidth: AppSettings.gifWidth.defaultValue),
            ].compactMap { $0 }
            let prefix = components.joined(separator: ",")
            return ["-vf", "\(prefix),split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", "-an"]

        case .animatedAVIF:
            let crf = Int(normalized(request.avifQuality, range: 0...63, defaultValue: 28))
            let speed = Int(normalized(request.avifSpeed, range: 0...8, defaultValue: 4))
            var arguments = [
                "-c:v", "libaom-av1",
                "-crf", String(crf),
                "-cpu-used", String(speed),
                "-b:v", "0",
                "-an",
            ]
            if let scale = scaleFilter(width: request.width, defaultWidth: AppSettings.avifWidth.defaultValue) {
                arguments += ["-vf", scale]
            }
            return arguments

        case .hardwareH264:
            let quality = Int(normalized(request.h264Quality, range: 1...100, defaultValue: 65))
            var arguments = ["-c:v", "h264_videotoolbox", "-q:v", String(quality), "-c:a", "aac"]
            if let scale = scaleFilter(width: request.width, defaultWidth: AppSettings.h264Width.defaultValue) {
                arguments += ["-vf", scale]
            }
            return arguments

        case .hardwareH265:
            let quality = Int(normalized(request.h265Quality, range: 1...100, defaultValue: 65))
            var arguments = ["-c:v", "hevc_videotoolbox", "-q:v", String(quality), "-c:a", "aac"]
            if let scale = scaleFilter(width: request.width, defaultWidth: AppSettings.h265Width.defaultValue) {
                arguments += ["-vf", scale]
            }
            return arguments
        }
    }

    private static func scaleFilter(width: Int, defaultWidth: Int) -> String? {
        let preset = ExportWidthPreset(rawValue: width)
            ?? ExportWidthPreset(rawValue: defaultWidth)
            ?? .original
        guard preset != .original else { return nil }
        return "scale='if(lte(iw,ih),min(\(preset.rawValue),iw),-2)':'if(lte(iw,ih),-2,min(\(preset.rawValue),ih))':flags=lanczos"
    }

    private static func normalized(
        _ value: Double,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) -> Double {
        guard value.isFinite else { return defaultValue }
        if value == 0, range.lowerBound > 0 { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
