// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudioTypes
import CoreMedia
import CoreVideo
import Metal
import XCTest
import os
@testable import Aagedal_Media_Player

final class CleanfeedTests: XCTestCase {
    private func makeUltraStudioLikeDevice() -> CMIOOutputDevice {
        let lowFPS: [Double] = [23.976, 24.0, 25.0, 29.97, 30.0]
        let allFPS: [Double] = [23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0]
        let rec709P = kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String
        let rec709T = kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String
        let rec2020P = kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String
        let pqT = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
        let hlgT = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String

        let formats: [CMIOOutputFormat] = [
            // Interlaced 1080i (should be deprioritized vs progressive)
            CMIOOutputFormat(
                index: 0, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_32BGRA,
                fieldCount: 2, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                frameRates: [25.0, 29.97]
            ),
            // 720p BGRA 709 (50/59.94/60 like SDI)
            CMIOOutputFormat(
                index: 8, width: 1280, height: 720, pixelFormat: kCVPixelFormatType_32BGRA,
                fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                frameRates: [50.0, 59.94, 60.0]
            ),
            // 1080p BGRA 709
            CMIOOutputFormat(
                index: 1, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_32BGRA,
                fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                frameRates: allFPS
            ),
            // 1080p v210 709
            CMIOOutputFormat(
                index: 2, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_422YpCbCr10,
                fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                frameRates: allFPS
            ),
            // 1080p v210 PQ
            CMIOOutputFormat(
                index: 3, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_422YpCbCr10,
                fieldCount: 1, colorPrimaries: rec2020P, transferFunction: pqT, ycbcrMatrix: rec2020P,
                frameRates: allFPS
            ),
            // 4K UHD BGRA 709 (caps at 30p like UltraStudio 4K Mini)
            CMIOOutputFormat(
                index: 4, width: 3840, height: 2160, pixelFormat: kCVPixelFormatType_32BGRA,
                fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                frameRates: lowFPS
            ),
            // 4K UHD v210 709 (supports 60p)
            CMIOOutputFormat(
                index: 5, width: 3840, height: 2160, pixelFormat: kCVPixelFormatType_422YpCbCr10,
                fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                frameRates: allFPS
            ),
            // 4K UHD v210 PQ (supports 60p)
            CMIOOutputFormat(
                index: 6, width: 3840, height: 2160, pixelFormat: kCVPixelFormatType_422YpCbCr10,
                fieldCount: 1, colorPrimaries: rec2020P, transferFunction: pqT, ycbcrMatrix: rec2020P,
                frameRates: allFPS
            ),
            // 4K UHD v210 HLG (supports 60p)
            CMIOOutputFormat(
                index: 7, width: 3840, height: 2160, pixelFormat: kCVPixelFormatType_422YpCbCr10,
                fieldCount: 1, colorPrimaries: rec2020P, transferFunction: hlgT, ycbcrMatrix: rec2020P,
                frameRates: allFPS
            ),
        ]

        return CMIOOutputDevice(
            deviceID: 45,
            streamID: 47,
            uid: "test-ultrastudio-4k-mini",
            name: "Blackmagic UltraStudio 4K Mini",
            manufacturer: "Blackmagic Design",
            linkedCoreAudioDeviceUID: "test-ultrastudio-audio",
            formats: formats,
            outputBufferQueueSize: 6,
            outputBuffersRequiredForStartup: 3
        )
    }

    func testDefaultSelectionSafelyCaps4K60HDRTo1080p30SDR() {
        let device = makeUltraStudioLikeDevice()
        let source = CMIOOutputSourceDescriptor(
            width: 3840, height: 2160, frameRate: 59.94, bitDepth: 10,
            colorPrimaries: "bt2020", colorTransfer: "smpte2084"
        )
        let selection = CMIOOutputFormatSelector.select(device: device, source: source)
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.format.width, 1920)
        XCTAssertEqual(selection?.format.height, 1080)
        XCTAssertEqual(selection?.frameRate ?? 0, 29.97, accuracy: 0.02)
        XCTAssertEqual(selection?.colorSpace, .rec709)
    }

    func testSelectorMatches1080p25SDRAsProgressiveBGRA() {
        let device = makeUltraStudioLikeDevice()
        let source = CMIOOutputSourceDescriptor(
            width: 1920, height: 1080, frameRate: 25.0, bitDepth: 8,
            colorPrimaries: "bt709", colorTransfer: "bt709"
        )
        let selection = CMIOOutputFormatSelector.select(device: device, source: source)
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.format.width, 1920)
        XCTAssertEqual(selection?.format.height, 1080)
        XCTAssertTrue(selection?.format.isProgressive == true)
        XCTAssertEqual(selection?.format.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(selection?.colorSpace, .rec709)
        XCTAssertEqual(selection?.frameRate ?? 0, 25.0, accuracy: 0.01)
    }

    func testSelectorPicksV210For4K60WhereBGRACapsAt30() {
        let device = makeUltraStudioLikeDevice()
        let source = CMIOOutputSourceDescriptor(
            width: 3840, height: 2160, frameRate: 59.94, bitDepth: 8,
            colorPrimaries: "bt709", colorTransfer: "bt709"
        )
        let selection = CMIOOutputFormatSelector.select(
            device: device,
            source: source,
            resolutionMode: .matchUpTo2160,
            frameRateMode: .matchMax60,
            colorMode: .auto
        )
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.format.width, 3840)
        XCTAssertEqual(selection?.format.height, 2160)
        XCTAssertEqual(selection?.format.pixelFormat, kCVPixelFormatType_422YpCbCr10)
        XCTAssertEqual(selection?.frameRate ?? 0, 59.94, accuracy: 0.02)
        XCTAssertEqual(selection?.colorSpace, .rec709)
    }

    func testSelectorPicks10BitPQForHDR10SourceWhenAutoColorEnabled() {
        let device = makeUltraStudioLikeDevice()
        let source = CMIOOutputSourceDescriptor(
            width: 3840, height: 2160, frameRate: 23.976, bitDepth: 10,
            colorPrimaries: "bt2020", colorTransfer: "smpte2084"
        )
        let selection = CMIOOutputFormatSelector.select(
            device: device,
            source: source,
            resolutionMode: .matchUpTo2160,
            frameRateMode: .matchMax30,
            colorMode: .auto
        )
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.format.pixelFormat, kCVPixelFormatType_422YpCbCr10)
        XCTAssertEqual(selection?.colorSpace, .hdrPQ)
        XCTAssertEqual(selection?.frameRate ?? 0, 23.976, accuracy: 0.02)
    }

    func testSelectorRespectsFixedResolutionAndFrameRateOverrides() {
        let device = makeUltraStudioLikeDevice()
        let source = CMIOOutputSourceDescriptor(
            width: 3840, height: 2160, frameRate: 59.94, bitDepth: 10,
            colorPrimaries: "bt709", colorTransfer: "bt709"
        )
        let selection = CMIOOutputFormatSelector.select(
            device: device,
            source: source,
            resolutionMode: .hd1080,
            frameRateMode: .fps25,
            colorMode: .sdr709,
            pixelFormatMode: .tenBitYUV
        )
        XCTAssertEqual(selection?.format.width, 1920)
        XCTAssertEqual(selection?.format.height, 1080)
        XCTAssertEqual(selection?.frameRate ?? 0, 25.0, accuracy: 0.01)
        XCTAssertEqual(selection?.format.pixelFormat, kCVPixelFormatType_422YpCbCr10)

        let cap720 = CMIOOutputFormatSelector.select(
            device: device,
            source: source,
            resolutionMode: .hd720,
            frameRateMode: .fps50
        )
        XCTAssertEqual(cap720?.format.width, 1280)
        XCTAssertEqual(cap720?.format.height, 720)
        XCTAssertEqual(cap720?.frameRate ?? 0, 50.0, accuracy: 0.01)
    }

    func testMatchUpTo1080Allows720pAndCaps4K() {
        let device = makeUltraStudioLikeDevice()
        let source720 = CMIOOutputSourceDescriptor(
            width: 1280, height: 720, frameRate: 50.0, bitDepth: 8,
            colorPrimaries: "bt709", colorTransfer: "bt709"
        )
        let sel720 = CMIOOutputFormatSelector.select(
            device: device,
            source: source720,
            resolutionMode: .matchUpTo1080,
            frameRateMode: .matchMax60
        )
        XCTAssertEqual(sel720?.format.width, 1280)
        XCTAssertEqual(sel720?.format.height, 720)
        XCTAssertEqual(sel720?.frameRate ?? 0, 50.0, accuracy: 0.01)

        let source4K = CMIOOutputSourceDescriptor(
            width: 3840, height: 2160, frameRate: 25.0, bitDepth: 8,
            colorPrimaries: "bt709", colorTransfer: "bt709"
        )
        let selCapped = CMIOOutputFormatSelector.select(
            device: device,
            source: source4K,
            resolutionMode: .matchUpTo1080,
            frameRateMode: .matchMax60
        )
        XCTAssertEqual(selCapped?.format.width, 1920)
        XCTAssertEqual(selCapped?.format.height, 1080)
        XCTAssertEqual(selCapped?.frameRate ?? 0, 25.0, accuracy: 0.01)
    }

    func testCapabilitiesHide4KAndHDROnHDOnlySDROutputDevice() {
        let rec709P = kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String
        let rec709T = kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String
        let hdOnlyDevice = CMIOOutputDevice(
            deviceID: 50,
            streamID: 51,
            uid: "test-ultrastudio-monitor-3g",
            name: "Blackmagic UltraStudio Monitor 3G",
            manufacturer: "Blackmagic Design",
            linkedCoreAudioDeviceUID: "test-3g-audio",
            formats: [
                CMIOOutputFormat(
                    index: 0, width: 1280, height: 720, pixelFormat: kCVPixelFormatType_32BGRA,
                    fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                    frameRates: [50.0, 59.94, 60.0]
                ),
                CMIOOutputFormat(
                    index: 1, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_32BGRA,
                    fieldCount: 1, colorPrimaries: rec709P, transferFunction: rec709T, ycbcrMatrix: rec709P,
                    frameRates: [23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0]
                ),
            ],
            outputBufferQueueSize: 6,
            outputBuffersRequiredForStartup: 3
        )

        // Even if user previously saved 2160p UHD + HDR PQ on a 4K box, the HD-only box
        // never offers 4K/2K/HDR and clamps effective selection to 1080p SDR BGRA.
        let caps = CMIOOutputCapabilities.evaluate(
            device: hdOnlyDevice,
            preferredResolution: .uhd2160,
            preferredFrameRate: .matchMax30,
            preferredColor: .hdrPQ,
            preferredPixelFormat: .tenBitYUV
        )
        XCTAssertEqual(caps.resolutionModes, [.hd720, .hd1080, .matchUpTo1080])
        XCTAssertFalse(caps.resolutionModes.contains(.uhd2160))
        XCTAssertFalse(caps.resolutionModes.contains(.dci4k))
        XCTAssertFalse(caps.resolutionModes.contains(.matchUpTo2160))
        XCTAssertEqual(caps.effectiveResolutionMode, .hd1080)
        XCTAssertEqual(caps.colorModes, [.sdr709])
        XCTAssertEqual(caps.effectiveColorMode, .sdr709)
        XCTAssertEqual(caps.pixelFormatModes, [.eightBitRGB])
        XCTAssertEqual(caps.effectivePixelFormatMode, .eightBitRGB)

        // At 720p on this SDI box, only 50/59.94/60 rates exist — no 24/25/30 fps offered.
        let caps720 = CMIOOutputCapabilities.evaluate(
            device: hdOnlyDevice,
            preferredResolution: .hd720,
            preferredFrameRate: .fps25,
            preferredColor: .sdr709,
            preferredPixelFormat: .auto
        )
        XCTAssertEqual(caps720.frameRateModes, [.matchMax60, .fps50, .fps59_94, .fps60])
        XCTAssertEqual(caps720.effectiveFrameRateMode, .matchMax60)
    }

    func testCapabilitiesNarrow4K60PixelFormatToV210OnUltraStudio4KMini() {
        let device = makeUltraStudioLikeDevice()
        let caps = CMIOOutputCapabilities.evaluate(
            device: device,
            preferredResolution: .uhd2160,
            preferredFrameRate: .fps59_94,
            preferredColor: .auto,
            preferredPixelFormat: .eightBitRGB
        )
        XCTAssertEqual(caps.pixelFormatModes, [.tenBitYUV])
        XCTAssertEqual(caps.effectivePixelFormatMode, .tenBitYUV)
        XCTAssertTrue(caps.colorModes.contains(.hdrPQ))
        XCTAssertTrue(caps.colorModes.contains(.hdrHLG))
        // UHD 2160 only advertises progressive formats, so Interlaced is hidden there.
        XCTAssertEqual(caps.scanModes, [.progressive])
    }

    func testScanModeSupports1080i50AndAutoMatchesInterlacedSource() {
        let device = makeUltraStudioLikeDevice()

        // 1080 offers both progressive and interlaced on UltraStudio.
        let caps1080 = CMIOOutputCapabilities.evaluate(
            device: device,
            preferredResolution: .hd1080,
            preferredScan: .interlaced,
            preferredFrameRate: .fps25,
            preferredColor: .sdr709,
            preferredPixelFormat: .auto
        )
        XCTAssertEqual(caps1080.scanModes, [.progressive, .interlaced, .auto])
        XCTAssertEqual(caps1080.effectiveScanMode, .interlaced)
        XCTAssertEqual(caps1080.frameRateModes, [.matchMax30, .fps25, .fps29_97])

        // Explicit Interlaced selects 1080i50 (25 fps frame rate, 50 fields/sec broadcast label).
        let source25p = CMIOOutputSourceDescriptor(
            width: 1920, height: 1080, frameRate: 25.0, bitDepth: 8,
            colorPrimaries: "bt709", colorTransfer: "bt709", isInterlaced: false
        )
        let interlacedSel = CMIOOutputFormatSelector.select(
            device: device,
            source: source25p,
            resolutionMode: .hd1080,
            scanMode: .interlaced,
            frameRateMode: .fps25
        )
        XCTAssertEqual(interlacedSel?.format.isProgressive, false)
        XCTAssertEqual(interlacedSel?.frameRate ?? 0, 25.0, accuracy: 0.01)
        XCTAssertEqual(interlacedSel?.summaryLabel, "1920×1080i50 • BGRA • Rec.709")

        // Auto scan matches an interlaced source to 1080i and a progressive source to 1080p.
        let source25i = CMIOOutputSourceDescriptor(
            width: 1920, height: 1080, frameRate: 25.0, bitDepth: 8,
            colorPrimaries: "bt709", colorTransfer: "bt709", isInterlaced: true
        )
        let autoInterlaced = CMIOOutputFormatSelector.select(
            device: device,
            source: source25i,
            resolutionMode: .hd1080,
            scanMode: .auto,
            frameRateMode: .matchMax30
        )
        XCTAssertEqual(autoInterlaced?.format.isProgressive, false)

        let autoProgressive = CMIOOutputFormatSelector.select(
            device: device,
            source: source25p,
            resolutionMode: .hd1080,
            scanMode: .auto,
            frameRateMode: .matchMax30
        )
        XCTAssertEqual(autoProgressive?.format.isProgressive, true)
    }

    func testV210PackingAndBroadcastLegalRange() {
        let black = CMIOFrameConverter.rgbToYCbCr10(r: 0, g: 0, b: 0, isRec2020: false)
        XCTAssertEqual(black.y, 64)
        XCTAssertEqual(black.cb, 512)
        XCTAssertEqual(black.cr, 512)

        let white = CMIOFrameConverter.rgbToYCbCr10(r: 1, g: 1, b: 1, isRec2020: false)
        XCTAssertEqual(white.y, 940)
        XCTAssertEqual(white.cb, 512)
        XCTAssertEqual(white.cr, 512)

        let packed = CMIOFrameConverter.packV210Group(
            cb0: 0x101, y0: 0x202, cr0: 0x303, y1: 0x040,
            cb2: 0x200, y2: 0x3AC, cr2: 0x1FF, y3: 0x155,
            cb4: 0x2AA, y4: 0x080, cr4: 0x320, y5: 0x250
        )
        XCTAssertEqual(packed.0 & 0x3FF, 0x101)
        XCTAssertEqual((packed.0 >> 10) & 0x3FF, 0x202)
        XCTAssertEqual((packed.0 >> 20) & 0x3FF, 0x303)
        XCTAssertEqual(packed.1 & 0x3FF, 0x040)
        XCTAssertEqual((packed.1 >> 10) & 0x3FF, 0x200)
        XCTAssertEqual((packed.1 >> 20) & 0x3FF, 0x3AC)
        XCTAssertEqual(packed.2 & 0x3FF, 0x1FF)
        XCTAssertEqual((packed.2 >> 10) & 0x3FF, 0x155)
        XCTAssertEqual((packed.2 >> 20) & 0x3FF, 0x2AA)
        XCTAssertEqual(packed.3 & 0x3FF, 0x080)
        XCTAssertEqual((packed.3 >> 10) & 0x3FF, 0x320)
        XCTAssertEqual((packed.3 >> 20) & 0x3FF, 0x250)
    }

    func testConverterGeneratesValidBGRAAndV210TestFrames() {
        for format in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_422YpCbCr10, kCVPixelFormatType_422YpCbCr8] {
            let converter = CMIOFrameConverter(width: 1920, height: 1080, pixelFormat: format, colorSpace: .rec709)
            XCTAssertNotNil(converter)
            let black = converter?.makeBlackPixelBuffer()
            let bars = converter?.makeColorBarsPixelBuffer(frameIndex: 5)
            XCTAssertNotNil(black)
            XCTAssertNotNil(bars)
            XCTAssertEqual(CVPixelBufferGetWidth(bars!), 1920)
            XCTAssertEqual(CVPixelBufferGetHeight(bars!), 1080)
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(bars!), format)
        }
    }

    func testSMPTETimeCalculationWithSourceOffset() {
        let tc = CleanfeedSMPTETime.make(
            playbackSeconds: 2.0,
            sourceStartTimecode: "01:00:00:00",
            sourceFrameRate: 25.0,
            outputFrameRate: 25.0
        )
        XCTAssertNotNil(tc)
        XCTAssertEqual(tc?.mHours, 1)
        XCTAssertEqual(tc?.mMinutes, 0)
        XCTAssertEqual(tc?.mSeconds, 2)
        XCTAssertEqual(tc?.mFrames, 0)
        XCTAssertEqual(tc?.mType, .type25)

        let dropTC = CleanfeedSMPTETime.make(
            playbackSeconds: 0.0,
            sourceStartTimecode: "01:00:00;00",
            sourceFrameRate: 29.97,
            outputFrameRate: 29.97
        )
        XCTAssertEqual(dropTC?.mType, .type2997Drop)
    }

    func testMetalGPUConversionToBGRAAndV210() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let width = 48
        let height = 16
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let sourceTexture = try XCTUnwrap(device.makeTexture(descriptor: desc))
        // Fill with solid white (BGRA = 0xFFFFFFFF)
        var pixels = [UInt32](repeating: 0xFFFFFFFF, count: width * height)
        sourceTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: width * 4
        )

        // 1. BGRA fast-path GPU blit
        let bgraConverter = try XCTUnwrap(CMIOFrameConverter(
            width: width, height: height, pixelFormat: kCVPixelFormatType_32BGRA, colorSpace: .rec709
        ))
        let bgraExp = expectation(description: "BGRA GPU convert")
        let bgraResult = OSAllocatedUnfairLock<UInt32>(initialState: 0)
        bgraConverter.convertTexture(sourceTexture, sourceIsLinearEDR: false, retainedToken: nil) { pb in
            if let pb {
                CVPixelBufferLockBaseAddress(pb, .readOnly)
                if let base = CVPixelBufferGetBaseAddress(pb) {
                    let pixel = base.assumingMemoryBound(to: UInt32.self)[0]
                    bgraResult.withLock { $0 = pixel }
                }
                CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            }
            bgraExp.fulfill()
        }
        wait(for: [bgraExp], timeout: 5.0)
        XCTAssertEqual(bgraResult.withLock { $0 }, 0xFFFFFFFF)

        // 2. 10-bit v210 GPU compute shader (white -> Y=940, Cb=512, Cr=512)
        let v210Converter = try XCTUnwrap(CMIOFrameConverter(
            width: width, height: height, pixelFormat: kCVPixelFormatType_422YpCbCr10, colorSpace: .rec709
        ))
        let v210Exp = expectation(description: "v210 GPU convert")
        let v210Result = OSAllocatedUnfairLock<(UInt32, UInt32)>(initialState: (0, 0))
        v210Converter.convertTexture(sourceTexture, sourceIsLinearEDR: false, retainedToken: nil) { pb in
            if let pb {
                CVPixelBufferLockBaseAddress(pb, .readOnly)
                if let base = CVPixelBufferGetBaseAddress(pb) {
                    let words = base.assumingMemoryBound(to: UInt32.self)
                    let w0 = words[0]
                    let w1 = words[1]
                    v210Result.withLock { $0 = (w0, w1) }
                }
                CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            }
            v210Exp.fulfill()
        }
        wait(for: [v210Exp], timeout: 5.0)
        let expected = CMIOFrameConverter.packV210Group(
            cb0: 512, y0: 940, cr0: 512, y1: 940,
            cb2: 512, y2: 940, cr2: 512, y3: 940,
            cb4: 512, y4: 940, cr4: 512, y5: 940
        )
        let actualV210 = v210Result.withLock { $0 }
        XCTAssertEqual(actualV210.0, expected.0)
        XCTAssertEqual(actualV210.1, expected.1)
    }

    func testSummaryLabelReportsDeviceLockedFrameRateMismatch() {
        let device = makeUltraStudioLikeDevice()
        let source2398 = CMIOOutputSourceDescriptor(
            width: 3840, height: 2160, frameRate: 24_000.0 / 1_001.0, bitDepth: 10,
            colorPrimaries: "bt2020", colorTransfer: "smpte2084"
        )
        let selection = CMIOOutputFormatSelector.select(
            device: device,
            source: source2398,
            resolutionMode: .uhd2160,
            frameRateMode: .matchMax30,
            colorMode: .sdr709
        )
        XCTAssertNotNil(selection)
        XCTAssertEqual(
            selection?.summaryLabel(actualFrameRate: 24_000.0 / 1_001.0),
            "3840×2160p23.98 • v210 • Rec.709"
        )
        XCTAssertEqual(
            selection?.summaryLabel(actualFrameRate: 30_000.0 / 1_001.0),
            "3840×2160p29.97 • v210 • Rec.709 (device locked; requested 23.98)"
        )
    }

    func testSinkPixelBufferFormatMatchingRejectsStaleResolutionBuffers() throws {
        let conv1080 = try XCTUnwrap(CMIOFrameConverter(
            width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_32BGRA, colorSpace: .rec709
        ))
        let pb1080 = try XCTUnwrap(conv1080.makeBlackPixelBuffer())
        XCTAssertTrue(CMIOCleanfeedSink.pixelBufferMatches(
            pb1080, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_32BGRA
        ))
        XCTAssertFalse(CMIOCleanfeedSink.pixelBufferMatches(
            pb1080, width: 3840, height: 2160, pixelFormat: kCVPixelFormatType_32BGRA
        ))
        XCTAssertFalse(CMIOCleanfeedSink.pixelBufferMatches(
            pb1080, width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_422YpCbCr10
        ))

        // Unstarted sink must reject frames instead of caching mismatched buffers.
        let sink = CMIOCleanfeedSink()
        XCTAssertFalse(sink.submitFrame(pb1080, smpteTime: nil, generation: 1))
    }
}
