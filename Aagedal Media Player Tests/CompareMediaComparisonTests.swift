// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareMediaComparisonTests: XCTestCase {
    func testReportsEveryKnownTechnicalMismatch() {
        let primary = descriptor(
            videoCodec: "h264",
            rasterWidth: 1920,
            rasterHeight: 1080,
            duration: 60,
            frameRate: 24,
            transferFunction: "bt709",
            colorPrimaries: "bt709",
            colorRange: "tv",
            audioLayout: "stereo"
        )
        let secondary = descriptor(
            videoCodec: "hevc",
            rasterWidth: 3840,
            rasterHeight: 2160,
            duration: 61,
            frameRate: 25,
            transferFunction: "smpte2084",
            colorPrimaries: "bt2020",
            colorRange: "pc",
            audioLayout: "5.1"
        )

        let mismatches = CompareMediaComparison.mismatches(
            primary: primary,
            secondary: secondary
        )

        XCTAssertEqual(mismatches.map(\.kind), [
            .videoCodec,
            .raster,
            .frameRate,
            .transferFunction,
            .colorPrimaries,
            .colorRange,
            .audioLayout,
            .duration
        ])
        XCTAssertEqual(mismatches[0].primaryValue, "H.264")
        XCTAssertEqual(mismatches[0].secondaryValue, "HEVC")
        XCTAssertEqual(mismatches[1].primaryValue, "1920 × 1080")
        XCTAssertEqual(mismatches[1].secondaryValue, "3840 × 2160")
        XCTAssertEqual(mismatches[2].primaryValue, "24 fps")
        XCTAssertEqual(mismatches[2].secondaryValue, "25 fps")
    }

    func testEquivalentAliasesDoNotWarn() {
        let primary = descriptor(
            videoCodec: "H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10",
            rasterWidth: 1920,
            rasterHeight: 1080,
            duration: 10,
            frameRate: 30_000.0 / 1_001.0,
            transferFunction: "smpte2084",
            colorPrimaries: "bt2020-10",
            colorRange: "pc",
            audioLayout: "2 channels"
        )
        let secondary = descriptor(
            videoCodec: "avc1",
            rasterWidth: 1920,
            rasterHeight: 1080,
            duration: 10.000_5,
            frameRate: 29.970_03,
            transferFunction: "PQ",
            colorPrimaries: "BT.2020",
            colorRange: "full",
            audioLayout: "Stereo"
        )

        XCTAssertTrue(CompareMediaComparison.mismatches(
            primary: primary,
            secondary: secondary
        ).isEmpty)
    }

    func testValuesMissingFromBothSourcesDoNotCreateWarnings() {
        let primary = descriptor(
            duration: nil,
            frameRate: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            colorRange: nil
        )
        let secondary = descriptor(
            duration: nil,
            frameRate: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            colorRange: nil
        )

        XCTAssertTrue(CompareMediaComparison.mismatches(
            primary: primary,
            secondary: secondary
        ).isEmpty)
    }

    func testOneSidedMissingValuesAreReportedAsUnavailable() {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(),
            secondary: descriptor(
                videoCodec: "hevc",
                rasterWidth: 3840,
                rasterHeight: 2160,
                duration: 30,
                frameRate: 30,
                transferFunction: "hlg",
                colorPrimaries: "bt2020",
                colorRange: "limited",
                audioLayout: "5.1"
            )
        )

        XCTAssertEqual(mismatches.map(\.kind), CompareMismatchKind.allCases)
        XCTAssertTrue(mismatches.allSatisfy { $0.primaryValue == "Unavailable" })
    }

    func testUnknownSentinelsAreTreatedAsMissingTags() {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(
                transferFunction: " unknown ",
                colorPrimaries: "N/A",
                colorRange: "unspecified"
            ),
            secondary: descriptor(
                transferFunction: "bt709",
                colorPrimaries: "bt709",
                colorRange: "tv"
            )
        )

        XCTAssertEqual(mismatches.map(\.kind), [
            .transferFunction,
            .colorPrimaries,
            .colorRange
        ])
        XCTAssertTrue(mismatches.allSatisfy { $0.primaryValue == "Unavailable" })
    }

    func testDurationToleranceIgnoresRoundingButReportsFrameDifference() {
        let withinTolerance = CompareMediaComparison.mismatches(
            primary: descriptor(duration: 10, frameRate: 25),
            secondary: descriptor(duration: 10.009, frameRate: 25)
        )
        let beyondTolerance = CompareMediaComparison.mismatches(
            primary: descriptor(duration: 10, frameRate: 25),
            secondary: descriptor(duration: 10.04, frameRate: 25)
        )

        XCTAssertTrue(withinTolerance.isEmpty)
        XCTAssertEqual(beyondTolerance.map(\.kind), [.duration])
    }

    func testDurationLabelsRemainReadablePastOneHour() throws {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(duration: 3_661.25),
            secondary: descriptor(duration: 3_662.5)
        )

        let mismatch = try XCTUnwrap(mismatches.first)
        XCTAssertEqual(mismatch.kind, .duration)
        XCTAssertEqual(mismatch.primaryValue, "1:01:01.250")
        XCTAssertEqual(mismatch.secondaryValue, "1:01:02.500")
    }

    func testDescriptorSummarizesEveryAudioStreamWithChannelFallbacks() {
        let item = mediaItem(audioStreams: [
            audioStream(channels: 2, channelLayout: nil),
            audioStream(channels: 6, channelLayout: "5.1(side)")
        ])

        let descriptor = CompareMediaDescriptor(item: item)

        XCTAssertEqual(descriptor.audioLayout, "Stereo + 5.1(side)")
    }

    func testDescriptorDistinguishesNoAudioFromUnavailableMetadata() {
        let noAudio = CompareMediaDescriptor(item: mediaItem(audioStreams: []))
        let unavailable = CompareMediaDescriptor(item: MediaItem(
            url: URL(fileURLWithPath: "/tmp/unavailable.mov"),
            name: "unavailable.mov",
            size: 0
        ))

        XCTAssertEqual(noAudio.audioLayout, "No audio")
        XCTAssertNil(unavailable.audioLayout)
    }

    func testDescriptorExtractsRasterAndPrefersCanonicalCodecWithLongNameFallback() {
        let canonical = CompareMediaDescriptor(item: mediaItem(videoStreams: [
            videoStream(
                codec: "h264",
                codecLongName: "H.264 / AVC / MPEG-4 AVC",
                width: 1920,
                height: 1080
            )
        ]))
        let fallback = CompareMediaDescriptor(item: mediaItem(videoStreams: [
            videoStream(
                codec: nil,
                codecLongName: "Apple ProRes",
                width: 0,
                height: -1
            )
        ]))

        XCTAssertEqual(canonical.videoCodec, "h264")
        XCTAssertEqual(canonical.rasterWidth, 1920)
        XCTAssertEqual(canonical.rasterHeight, 1080)
        XCTAssertEqual(fallback.videoCodec, "Apple ProRes")
        XCTAssertNil(fallback.rasterWidth)
        XCTAssertNil(fallback.rasterHeight)
    }

    func testAudioLayoutMismatchPreservesMeaningfulDisplayPunctuation() throws {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(audioLayout: "5.1(side)"),
            secondary: descriptor(audioLayout: "Stereo")
        )

        let mismatch = try XCTUnwrap(mismatches.first)
        XCTAssertEqual(mismatch.kind, .audioLayout)
        XCTAssertEqual(mismatch.primaryValue, "5.1(side)")
        XCTAssertEqual(mismatch.secondaryValue, "Stereo")
    }

    private func descriptor(
        videoCodec: String? = nil,
        rasterWidth: Int? = nil,
        rasterHeight: Int? = nil,
        duration: TimeInterval? = nil,
        frameRate: Double? = nil,
        transferFunction: String? = nil,
        colorPrimaries: String? = nil,
        colorRange: String? = nil,
        audioLayout: String? = nil
    ) -> CompareMediaDescriptor {
        CompareMediaDescriptor(
            videoCodec: videoCodec,
            rasterWidth: rasterWidth,
            rasterHeight: rasterHeight,
            duration: duration,
            frameRate: frameRate,
            transferFunction: transferFunction,
            colorPrimaries: colorPrimaries,
            colorRange: colorRange,
            audioLayout: audioLayout
        )
    }

    private func mediaItem(
        videoStreams: [MediaMetadata.VideoStream] = [],
        audioStreams: [MediaMetadata.AudioStream] = []
    ) -> MediaItem {
        let metadata = MediaMetadata(
            duration: nil,
            formatName: nil,
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: videoStreams,
            audioStreams: audioStreams,
            subtitleStreams: [],
            chapters: []
        )
        return MediaItem(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            name: "test.mov",
            size: 0,
            metadata: metadata
        )
    }

    private func audioStream(
        channels: Int?,
        channelLayout: String?
    ) -> MediaMetadata.AudioStream {
        MediaMetadata.AudioStream(
            index: nil,
            languageCode: nil,
            title: nil,
            codec: nil,
            codecLongName: nil,
            profile: nil,
            sampleRate: nil,
            channels: channels,
            channelLayout: channelLayout,
            bitDepth: nil,
            bitRate: nil,
            isDefault: false
        )
    }

    private func videoStream(
        codec: String?,
        codecLongName: String?,
        width: Int?,
        height: Int?
    ) -> MediaMetadata.VideoStream {
        MediaMetadata.VideoStream(
            codec: codec,
            codecLongName: codecLongName,
            profile: nil,
            width: width,
            height: height,
            displayWidth: nil,
            displayHeight: nil,
            pixelFormat: nil,
            hasAlpha: false,
            pixelAspectRatio: nil,
            displayAspectRatio: nil,
            frameRate: nil,
            bitDepth: nil,
            chromaSubsampling: nil,
            colorPrimaries: nil,
            colorTransfer: nil,
            colorSpace: nil,
            colorRange: nil,
            chromaLocation: nil,
            fieldOrder: nil,
            isInterlaced: nil,
            rotation: nil,
            maxCLL: nil,
            maxFALL: nil,
            masteringMaxLuminance: nil,
            masteringMinLuminance: nil
        )
    }
}
