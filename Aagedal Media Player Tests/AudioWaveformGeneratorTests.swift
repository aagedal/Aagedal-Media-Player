// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import AppKit
import XCTest

@MainActor
final class AudioWaveformGeneratorTests: XCTestCase {
    func testCancelImmediatelyClearsLoadingStateAndKeepsItCleared() async {
        let generator = AudioWaveformGenerator()
        let missingURL = URL(fileURLWithPath: "/nonexistent/waveform-test.mov")

        generator.generate(
            url: missingURL,
            streamIndex: 0,
            channels: 2,
            channelLayout: "stereo",
            duration: 1
        )
        XCTAssertTrue(generator.isGenerating)

        generator.cancel()
        XCTAssertFalse(generator.isGenerating)

        await Task.yield()
        XCTAssertFalse(generator.isGenerating)
    }

    func testReplacementPublishesOnlyTheNewestCompletedWaveform() async throws {
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { request in
            try await controlled.generate(request)
        }
        let firstURL = URL(fileURLWithPath: "/tmp/first-waveform.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/second-waveform.mov")

        generator.generate(
            url: firstURL,
            streamIndex: 0,
            channels: 1,
            channelLayout: "mono",
            duration: 1
        )
        await controlled.waitForRequest(firstURL)

        generator.generate(
            url: secondURL,
            streamIndex: 0,
            channels: 2,
            channelLayout: "stereo",
            duration: 1
        )
        await controlled.waitForRequest(secondURL)

        await controlled.succeed(secondURL, marker: 22, channelCount: 2)
        await waitUntilGenerationFinishes(generator)

        XCTAssertEqual(generator.channelImages.map(\.size.width), [22, 23])
        XCTAssertEqual(generator.channelLabels, ["Left", "Right"])
        XCTAssertNil(generator.error)

        await controlled.succeed(firstURL, marker: 11, channelCount: 1)
        await Task.yield()

        XCTAssertEqual(generator.channelImages.map(\.size.width), [22, 23])
        XCTAssertEqual(generator.channelLabels, ["Left", "Right"])
        XCTAssertNil(generator.error)
    }

    func testStaleFailureCannotReplaceSuccessfulReplacementState() async throws {
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { request in
            try await controlled.generate(request)
        }
        let firstURL = URL(fileURLWithPath: "/tmp/failing-waveform.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/current-waveform.mov")

        generator.generate(
            url: firstURL,
            streamIndex: 0,
            channels: 1,
            channelLayout: "mono",
            duration: 1
        )
        await controlled.waitForRequest(firstURL)
        generator.generate(
            url: secondURL,
            streamIndex: 0,
            channels: 1,
            channelLayout: "mono",
            duration: 1
        )
        await controlled.waitForRequest(secondURL)

        await controlled.succeed(secondURL, marker: 30, channelCount: 1)
        await waitUntilGenerationFinishes(generator)
        await controlled.fail(firstURL)
        await Task.yield()

        XCTAssertEqual(generator.channelImages.first?.size.width, 30)
        XCTAssertEqual(generator.channelLabels, ["Mono"])
        XCTAssertNil(generator.error)
        XCTAssertFalse(generator.isGenerating)
    }

    private func waitUntilGenerationFinishes(_ generator: AudioWaveformGenerator) async {
        while generator.isGenerating {
            await Task.yield()
        }
    }
}

private actor ControlledWaveformGeneration {
    private var continuations: [URL: CheckedContinuation<AudioWaveformGenerationOutput, Error>] = [:]

    func generate(_ request: AudioWaveformGenerationRequest) async throws -> AudioWaveformGenerationOutput {
        try await withCheckedThrowingContinuation { continuation in
            continuations[request.url] = continuation
        }
    }

    func waitForRequest(_ url: URL) async {
        while continuations[url] == nil {
            await Task.yield()
        }
    }

    func succeed(_ url: URL, marker: CGFloat, channelCount: Int) {
        let images = (0..<channelCount).map { channel in
            NSImage(size: NSSize(width: marker + CGFloat(channel), height: 1))
        }
        let amplitudes = (0..<channelCount).map { _ in
            WaveformAmplitudeData(mins: [0], maxs: [1])
        }
        continuations.removeValue(forKey: url)?.resume(returning: AudioWaveformGenerationOutput(
            images: images,
            amplitudes: amplitudes,
            width: 1
        ))
    }

    func fail(_ url: URL) {
        continuations.removeValue(forKey: url)?.resume(throwing: TestFailure())
    }
}

private struct TestFailure: Error {}
