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

    func testChangedSingleStreamDescriptionReplacesSameURLWork() async throws {
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { request in
            try await controlled.generate(request)
        }
        let url = URL(fileURLWithPath: "/tmp/enriched-waveform.mov")

        generator.generate(
            url: url, streamIndex: 0, channels: 1,
            channelLayout: "mono", duration: 1
        )
        await controlled.waitForRequestCount(1)

        generator.generate(
            url: url, streamIndex: 0, channels: 2,
            channelLayout: "stereo", duration: 2
        )
        await controlled.waitForRequestCount(2)

        let requests = await controlled.requests
        XCTAssertEqual(requests.map(\.channelCount), [1, 2])
        XCTAssertEqual(requests.map(\.duration), [1, 2])

        await controlled.succeed(at: 1, marker: 20)
        await waitUntilGenerationFinishes(generator)
        XCTAssertEqual(generator.channelImages.map(\.size.width), [20, 21])
        XCTAssertEqual(generator.channelLabels, ["Left", "Right"])

        await controlled.succeed(at: 0, marker: 10)
        await Task.yield()
        XCTAssertEqual(generator.channelImages.map(\.size.width), [20, 21])
        XCTAssertEqual(generator.channelLabels, ["Left", "Right"])
    }

    func testChangedAllMonoStreamSetReplacesSameURLWork() async throws {
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { request in
            try await controlled.generate(request)
        }
        let url = URL(fileURLWithPath: "/tmp/multimono-waveform.mov")

        generator.generateAllMonoStreams(
            url: url, streams: [(index: 0, label: "Boom")], duration: 10
        )
        await controlled.waitForRequestCount(1)

        generator.generateAllMonoStreams(
            url: url,
            streams: [(index: 1, label: "Lav 1"), (index: 2, label: "Lav 2")],
            duration: 20
        )
        await controlled.waitForRequestCount(2)

        let requests = await controlled.requests
        XCTAssertEqual(requests.map(\.streamIndex), [0, 1])
        XCTAssertEqual(requests.map(\.duration), [10, 20])

        await controlled.succeed(at: 1, marker: 30)
        await controlled.waitForRequestCount(3)
        await controlled.succeed(at: 2, marker: 31)
        await waitUntilGenerationFinishes(generator)
        XCTAssertEqual(generator.channelImages.map(\.size.width), [30, 31])
        XCTAssertEqual(generator.channelLabels, ["Lav 1", "Lav 2"])

        await controlled.succeed(at: 0, marker: 10)
        await Task.yield()
        XCTAssertEqual(generator.channelImages.map(\.size.width), [30, 31])
        XCTAssertEqual(generator.channelLabels, ["Lav 1", "Lav 2"])
    }

    func testIdenticalSourceDescriptionKeepsInFlightWork() async {
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { request in
            try await controlled.generate(request)
        }
        let url = URL(fileURLWithPath: "/tmp/deduplicated-waveform.mov")

        for _ in 0..<2 {
            generator.generate(
                url: url, streamIndex: 1, channels: 2,
                channelLayout: "stereo", duration: 30
            )
        }
        await controlled.waitForRequestCount(1)
        await Task.yield()

        let requestCount = await controlled.requests.count
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(generator.isGenerating)
        XCTAssertNil(generator.error)
        generator.cancel()
    }

    func testInvalidDurationFailsBeforeStartingGeneration() async {
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { request in
            try await controlled.generate(request)
        }
        let url = URL(fileURLWithPath: "/tmp/invalid-duration-waveform.mov")

        generator.generate(
            url: url, streamIndex: 0, channels: 1,
            channelLayout: "mono", duration: .nan
        )
        generator.generateAllMonoStreams(
            url: url, streams: [(index: 0, label: "Track 1")], duration: .infinity
        )
        await Task.yield()

        let requests = await controlled.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(generator.error, "Cannot generate the audio waveform: the media duration is unavailable.")
        XCTAssertFalse(generator.isGenerating)
    }

    func testNativeGenerationRejectsNonFiniteDuration() async {
        let request = AudioWaveformGenerationRequest(
            url: URL(fileURLWithPath: "/tmp/invalid-native-waveform.mov"),
            streamIndex: 0, channelCount: 1, duration: .infinity,
            colorHex: "FF2D78", gamma: 1, pixelsPerSecond: 12,
            channelHeight: 240, maxWidth: 24_000
        )

        do {
            _ = try await AudioWaveformGenerator.generateNativeWaveforms(request: request)
            XCTFail("Expected an invalid waveform request")
        } catch let error as AudioWaveformGenerationFailure {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot generate the audio waveform: its source parameters are invalid."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppearanceAndResizeDuringDecodeUseCachedDataWithoutRestarting() async throws {
        let defaults = UserDefaults.standard
        let colorKey = AppSettings.audioWaveformColor.key
        let boostKey = AppSettings.audioWaveformBoost.key
        let oldColor = defaults.object(forKey: colorKey)
        let oldBoost = defaults.object(forKey: boostKey)
        defer {
            defaults.set(oldColor, forKey: colorKey)
            defaults.set(oldBoost, forKey: boostKey)
        }
        defaults.set("FF2D78", forKey: colorKey)
        defaults.set(0.0, forKey: boostKey)
        let controlled = ControlledWaveformGeneration()
        let generator = AudioWaveformGenerator { try await controlled.generate($0) }
        let url = URL(fileURLWithPath: "/tmp/waveform-appearance.mov")
        generator.generate(url: url, streamIndex: 0, channels: 1, channelLayout: "mono", duration: 1)
        await controlled.waitForRequestCount(1)

        defaults.set("4A9EE5", forKey: colorKey)
        defaults.set(70.0, forKey: boostKey)
        generator.setRenderWidth(96)
        generator.rerender()
        generator.generate(url: url, streamIndex: 0, channels: 1, channelLayout: "mono", duration: 1)
        await Task.yield()
        let requestCount = await controlled.requests.count
        XCTAssertEqual(requestCount, 1)
        await controlled.succeed(at: 0, marker: 30)
        await waitUntilGenerationFinishes(generator)
        try await waitForImageWidth(96, generator: generator)
        let bitmap = try bitmapRepresentation(generator.channelImages[0])
        let color = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(color.blueComponent, 229.0 / 255, accuracy: 0.01)
        XCTAssertEqual(color.redComponent, 74.0 / 255, accuracy: 0.01)

        generator.setRenderWidth(120)
        generator.setRenderWidth(48)
        try await waitForImageWidth(48, generator: generator)
        let finalRequestCount = await controlled.requests.count
        XCTAssertEqual(finalRequestCount, 1)
    }

    func testRasterKeepsSilenceTransparentAndDistinctPeakAndMeanLayers() throws {
        let data = WaveformAmplitudeData(
            mins: [0, -1], maxs: [0, 1], averageMins: [0, -0.25], averageMaxs: [0, 0.25]
        )
        let image = try XCTUnwrap(AudioWaveformGenerator.renderWaveformImage(
            data: data, width: 2, height: 20, r: 255, g: 45, b: 120
        ))
        let bitmap = try bitmapRepresentation(image)
        for row in 0..<20 {
            XCTAssertEqual(bitmap.colorAt(x: 0, y: row)?.alphaComponent, 0)
        }
        let peak = try XCTUnwrap(bitmap.colorAt(x: 1, y: 0))
        let body = try XCTUnwrap(bitmap.colorAt(x: 1, y: 10))
        XCTAssertEqual(peak.alphaComponent, 0.55, accuracy: 0.01)
        XCTAssertEqual(body.alphaComponent, 1)
    }

    func testRasterRetainsSingleColumnPeakInNarrowOverview() throws {
        var peaks = [Float](repeating: 0, count: 24_000)
        peaks[12_345] = 1
        let image = try XCTUnwrap(AudioWaveformGenerator.renderWaveformImage(
            data: WaveformAmplitudeData(mins: Array(repeating: 0, count: peaks.count), maxs: peaks),
            width: 100, height: 20, r: 255, g: 45, b: 120
        ))
        let bitmap = try bitmapRepresentation(image)
        XCTAssertEqual(bitmap.colorAt(x: 51, y: 0)?.alphaComponent, 1)
        XCTAssertEqual(bitmap.colorAt(x: 50, y: 0)?.alphaComponent, 0)
    }

    func testRasterRejectsInvalidGeometryAndSanitizesNonFiniteSamples() throws {
        let data = WaveformAmplitudeData(mins: [.nan], maxs: [.infinity])
        XCTAssertNil(AudioWaveformGenerator.renderWaveformImage(
            data: data, width: 5000, height: 20, r: 255, g: 45, b: 120
        ))
        let image = try XCTUnwrap(AudioWaveformGenerator.renderWaveformImage(
            data: data, width: 1, height: 20, r: 255, g: 45, b: 120, gamma: .nan
        ))
        XCTAssertEqual(try bitmapRepresentation(image).colorAt(x: 0, y: 10)?.alphaComponent, 0)
    }

    private func bitmapRepresentation(_ image: NSImage) throws -> NSBitmapImageRep {
        var rect = CGRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cgImage)
    }

    private func waitForImageWidth(_ width: CGFloat, generator: AudioWaveformGenerator) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while generator.channelImages.first?.size.width != width && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(generator.channelImages.first?.size.width, width)
    }

    private func waitUntilGenerationFinishes(_ generator: AudioWaveformGenerator) async {
        while generator.isGenerating {
            await Task.yield()
        }
    }
}

private actor ControlledWaveformGeneration {
    private(set) var requests: [AudioWaveformGenerationRequest] = []
    private var continuations: [CheckedContinuation<AudioWaveformGenerationOutput, Error>?] = []

    func generate(_ request: AudioWaveformGenerationRequest) async throws -> AudioWaveformGenerationOutput {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(request)
            continuations.append(continuation)
        }
    }

    func waitForRequest(_ url: URL) async {
        while !requests.contains(where: { $0.url == url }) {
            await Task.yield()
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func succeed(_ url: URL, marker: CGFloat, channelCount: Int) {
        guard let index = requests.indices.first(where: {
            requests[$0].url == url && continuations[$0] != nil
        }) else { return }
        succeed(at: index, marker: marker, channelCount: channelCount)
    }

    func succeed(at index: Int, marker: CGFloat, channelCount: Int? = nil) {
        guard requests.indices.contains(index) else { return }
        let count = channelCount ?? requests[index].channelCount
        let images = (0..<count).map { channel in
            NSImage(size: NSSize(width: marker + CGFloat(channel), height: 1))
        }
        let amplitudes = (0..<count).map { _ in
            WaveformAmplitudeData(mins: [0], maxs: [1])
        }
        continuations[index]?.resume(returning: AudioWaveformGenerationOutput(
            images: images,
            amplitudes: amplitudes,
            width: 1
        ))
        continuations[index] = nil
    }

    func fail(_ url: URL) {
        guard let index = requests.indices.first(where: {
            requests[$0].url == url && continuations[$0] != nil
        }) else { return }
        continuations[index]?.resume(throwing: TestFailure())
        continuations[index] = nil
    }
}

private struct TestFailure: Error {}
