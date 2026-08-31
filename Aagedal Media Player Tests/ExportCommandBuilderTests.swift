// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

final class ExportCommandBuilderTests: XCTestCase {
    private let sourceURL = URL(fileURLWithPath: "/tmp/source clip.mov")
    private let destinationURL = URL(fileURLWithPath: "/tmp/output clip.tmp")

    func testBuildsCopyTrimCommand() {
        let arguments = TrimExportCommandBuilder.arguments(for: trimRequest(format: .copy))

        XCTAssertEqual(arguments, [
            "-hide_banner", "-loglevel", "error",
            "-ss", "1.25",
            "-i", "/tmp/source clip.mov",
            "-t", "2.5",
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            "-n", "/tmp/output clip.tmp",
        ])
    }

    func testBuildsScaledGIFCommandAndClampsFrameRate() {
        let arguments = TrimExportCommandBuilder.arguments(for: trimRequest(
            format: .gif,
            width: ExportWidthPreset.w720.rawValue,
            gifFrameRate: 60
        ))

        XCTAssertEqual(value(after: "-vf", in: arguments),
            "fps=30,scale='if(lte(iw,ih),min(720,iw),-2)':'if(lte(iw,ih),-2,min(720,ih))':flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse")
        XCTAssertTrue(arguments.contains("-an"))
    }

    func testGIFFallsBackToCanonicalWidthForInvalidPreference() {
        let arguments = TrimExportCommandBuilder.arguments(for: trimRequest(
            format: .gif,
            width: 123,
            gifFrameRate: 15
        ))

        XCTAssertTrue(value(after: "-vf", in: arguments)?.contains("min(720,iw)") == true)
    }

    func testBuildsAnimatedAVIFCommandAndAllowsZeroQualityAndSpeed() {
        let arguments = TrimExportCommandBuilder.arguments(for: trimRequest(
            format: .animatedAVIF,
            width: ExportWidthPreset.original.rawValue,
            avifQuality: 0,
            avifSpeed: 0
        ))

        XCTAssertEqual(value(after: "-c:v", in: arguments), "libaom-av1")
        XCTAssertEqual(value(after: "-crf", in: arguments), "0")
        XCTAssertEqual(value(after: "-cpu-used", in: arguments), "0")
        XCTAssertFalse(arguments.contains("-vf"))
    }

    func testBuildsHardwareCodecCommands() {
        let h264 = TrimExportCommandBuilder.arguments(for: trimRequest(
            format: .hardwareH264,
            width: ExportWidthPreset.w1080.rawValue,
            h264Quality: 120
        ))
        let h265 = TrimExportCommandBuilder.arguments(for: trimRequest(
            format: .hardwareH265,
            h265Quality: 0
        ))

        XCTAssertEqual(value(after: "-c:v", in: h264), "h264_videotoolbox")
        XCTAssertEqual(value(after: "-q:v", in: h264), "100")
        XCTAssertTrue(value(after: "-vf", in: h264)?.contains("min(1080,iw)") == true)
        XCTAssertEqual(value(after: "-c:v", in: h265), "hevc_videotoolbox")
        XCTAssertEqual(value(after: "-q:v", in: h265), "65")
        XCTAssertFalse(h265.contains("-vf"))
    }

    func testBuildsHighBitDepthInterlacedJXLScreenshotCommand() {
        let arguments = ScreenshotCommandBuilder.arguments(for: screenshotRequest(
            format: .jxl,
            bitDepth: 10,
            hasAlpha: true,
            isInterlaced: true,
            jxlQuality: 80
        ))

        XCTAssertEqual(value(after: "-vf", in: arguments), "bwdif=mode=0:parity=-1:deint=all,scale=iw*sar:ih")
        XCTAssertEqual(value(after: "-pix_fmt", in: arguments), "rgba64le")
        XCTAssertEqual(value(after: "-c:v", in: arguments), "libjxl")
        XCTAssertEqual(value(after: "-distance", in: arguments), "3.00")
        XCTAssertEqual(Array(arguments.suffix(2)), ["-n", "/tmp/output clip.tmp"])
    }

    func testBuildsPNGAndJPEGScreenshotCommands() {
        let png = ScreenshotCommandBuilder.arguments(for: screenshotRequest(
            format: .png,
            bitDepth: 10,
            hasAlpha: false
        ))
        let jpeg = ScreenshotCommandBuilder.arguments(for: screenshotRequest(
            format: .jpeg,
            jpegQuality: 0
        ))

        XCTAssertEqual(value(after: "-pix_fmt", in: png), "rgb48be")
        XCTAssertEqual(value(after: "-c:v", in: png), "png")
        XCTAssertEqual(value(after: "-pix_fmt", in: jpeg), "yuvj444p")
        XCTAssertEqual(value(after: "-q:v", in: jpeg), "31.0")
    }

    func testScreenshotCommandNormalizesSupportedColorMetadata() {
        let stream = MediaMetadata.VideoStream(
            codec: nil,
            codecLongName: nil,
            profile: nil,
            width: nil,
            height: nil,
            displayWidth: nil,
            displayHeight: nil,
            pixelFormat: nil,
            hasAlpha: false,
            pixelAspectRatio: nil,
            displayAspectRatio: nil,
            frameRate: nil,
            bitDepth: nil,
            chromaSubsampling: nil,
            colorPrimaries: " BT2020-10 ",
            colorTransfer: "smpte2084",
            colorSpace: "bt2020-ncl",
            colorRange: "full",
            chromaLocation: nil,
            fieldOrder: nil,
            isInterlaced: nil,
            rotation: nil,
            maxCLL: nil,
            maxFALL: nil,
            masteringMaxLuminance: nil,
            masteringMinLuminance: nil
        )
        let arguments = ScreenshotCommandBuilder.arguments(for: screenshotRequest(
            format: .png,
            colorMetadata: stream
        ))

        XCTAssertEqual(value(after: "-color_primaries", in: arguments), "bt2020")
        XCTAssertEqual(value(after: "-color_trc", in: arguments), "smpte2084")
        XCTAssertEqual(value(after: "-colorspace", in: arguments), "bt2020nc")
        XCTAssertEqual(value(after: "-color_range", in: arguments), "pc")
    }

    private func trimRequest(
        format: TrimExportFormat,
        width: Int = ExportWidthPreset.original.rawValue,
        gifFrameRate: Double = 15,
        avifQuality: Double = 28,
        avifSpeed: Double = 4,
        h264Quality: Double = 65,
        h265Quality: Double = 65
    ) -> TrimExportCommandRequest {
        TrimExportCommandRequest(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            inPoint: 1.25,
            outPoint: 3.75,
            format: format,
            width: width,
            gifFrameRate: gifFrameRate,
            avifQuality: avifQuality,
            avifSpeed: avifSpeed,
            h264Quality: h264Quality,
            h265Quality: h265Quality
        )
    }

    private func screenshotRequest(
        format: ScreenshotFormat,
        bitDepth: Int = 8,
        hasAlpha: Bool = false,
        isInterlaced: Bool = false,
        jxlQuality: Double = 90,
        jpegQuality: Double = 90,
        colorMetadata: MediaMetadata.VideoStream? = nil
    ) -> ScreenshotCommandRequest {
        ScreenshotCommandRequest(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            time: 2.5,
            format: format,
            bitDepth: bitDepth,
            hasAlpha: hasAlpha,
            isInterlaced: isInterlaced,
            jxlQuality: jxlQuality,
            jpegQuality: jpegQuality,
            colorMetadata: colorMetadata
        )
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
