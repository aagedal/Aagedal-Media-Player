// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class LiveAudioMeterPlaybackSourceTests: XCTestCase {
    func testBuildsExactRequestFromAudioOrderAndRoundedSourceFrame() throws {
        let source = try makeSource(
            order: 2, sampleRate: 48_000, channels: 2, layout: "stereo", duration: 10
        )

        let request = try source.request(at: 1.0 / 3.0)

        XCTAssertEqual(request.audioStreamOrderIndex, 2)
        XCTAssertEqual(request.startSourceFrame, 16_000)
        XCTAssertEqual(request.startSourceTime, 1.0 / 3.0, accuracy: 1.0 / 48_000)
        XCTAssertEqual(source.containerStreamIndex, 7)
        XCTAssertEqual(source.channelLabels, ["Left", "Right"])
        XCTAssertEqual(source.sourceOption, .init(id: "B", label: "Source B", detail: "Mix"))
    }

    func testClampsStartToSourceBoundsWithoutCreatingInconsistentIdentity() throws {
        let source = try makeSource(
            sampleRate: 44_100, channels: 1, layout: nil, duration: 2
        )

        XCTAssertEqual(try source.request(at: -3).startSourceFrame, 0)
        let end = try source.request(at: 20)
        XCTAssertEqual(end.startSourceFrame, 88_200)
        XCTAssertEqual(end.startSourceTime, 2)
        XCTAssertThrowsError(try source.request(at: .nan)) { error in
            XCTAssertEqual(error as? LiveAudioMeterPlaybackSource.Failure, .invalidPlaybackTime)
        }
    }

    func testMapsOnlyExplicitSupportedSurroundSpeakerOrders() throws {
        XCTAssertEqual(
            try makeSource(sampleRate: 48_000, channels: 6, layout: "5.1(side)").format.layout,
            .surround5Point1
        )
        XCTAssertEqual(
            try makeSource(sampleRate: 96_000, channels: 8, layout: "7.1").format.layout,
            .surround7Point1
        )
        XCTAssertEqual(
            try makeSource(sampleRate: 48_000, channels: 6, layout: "5.1").format.layout,
            .unknown(channels: 6),
            "Back-surround 5.1 must not be measured with side-surround weights"
        )
        XCTAssertEqual(
            try makeSource(sampleRate: 48_000, channels: 8, layout: nil).format.layout,
            .unknown(channels: 8)
        )
    }

    func testRejectsMissingAndUnsupportedTrackFormat() throws {
        XCTAssertThrowsError(try makeSource(sampleRate: nil, channels: 2, layout: "stereo")) { error in
            XCTAssertEqual(error as? LiveAudioMeterPlaybackSource.Failure, .missingSampleRate)
        }
        XCTAssertThrowsError(try makeSource(sampleRate: 48_000, channels: nil, layout: nil)) { error in
            XCTAssertEqual(error as? LiveAudioMeterPlaybackSource.Failure, .missingChannelCount)
        }
        XCTAssertThrowsError(try makeSource(sampleRate: 88_200, channels: 2, layout: "stereo")) { error in
            XCTAssertEqual(error as? LiveAudioMeterPlaybackSource.Failure, .unsupportedSampleRate(88_200))
        }
        XCTAssertThrowsError(try makeSource(sampleRate: 48_000, channels: 12, layout: "7.1.4")) { error in
            XCTAssertEqual(error as? LiveAudioMeterPlaybackSource.Failure, .unsupportedChannelCount(12))
        }
    }

    private func makeSource(
        order: Int = 0,
        sampleRate: Int?,
        channels: Int?,
        layout: String?,
        duration: TimeInterval = 60
    ) throws -> LiveAudioMeterPlaybackSource {
        try LiveAudioMeterPlaybackSource(
            id: "B",
            label: "Source B",
            url: URL(fileURLWithPath: "/tmp/source.mov"),
            audioStreamOrderIndex: order,
            stream: MediaMetadata.AudioStream(
                index: 7,
                languageCode: "eng",
                title: "Mix",
                codec: "pcm_s24le",
                codecLongName: nil,
                profile: nil,
                sampleRate: sampleRate,
                channels: channels,
                channelLayout: layout,
                bitDepth: 24,
                bitRate: nil,
                isDefault: true
            ),
            trackLabel: "Mix",
            duration: duration
        )
    }
}
