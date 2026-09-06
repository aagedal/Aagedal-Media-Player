// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class TimelineThumbnailLoaderTests: XCTestCase {
    private func item(duration: Double = 10) -> MediaItem {
        MediaItem(url: URL(fileURLWithPath: "/tmp/thumbnail.mov"), name: "Preview", size: 0,
                  durationSeconds: duration)
    }

    func testRequestsQuantizeAndStayBeforeExclusiveMediaEnd() throws {
        let media = item()
        XCTAssertEqual(try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: 2.74)).time, 2.5)
        XCTAssertEqual(try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: -1)).time, 0)
        XCTAssertLessThan(try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: 99)).time, 10)
        XCTAssertNil(TimelineThumbnailLoader.Request(item: media, time: .nan))
        XCTAssertNil(TimelineThumbnailLoader.Request(item: item(duration: .infinity), time: 1))
        var audio = media
        audio.hasVideoStream = false
        XCTAssertNil(TimelineThumbnailLoader.Request(item: audio, time: 1))
    }

    func testBoundedCacheAndMediaReplacement() async throws {
        let loader = TimelineThumbnailLoader(debounce: .zero) { _, _ in
            let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                    bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }
        let media = item(duration: 100)
        for index in 0..<40 {
            loader.request(item: media, time: Double(index))
            for _ in 0..<1_000 where loader.imageTime != Double(index) {
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertEqual(loader.imageTime, Double(index))
        }
        XCTAssertEqual(loader.cachedCount, TimelineThumbnailLoader.cacheLimit)
        loader.request(item: item(duration: 100), time: 1)
        XCTAssertNil(loader.image)
        XCTAssertEqual(loader.cachedCount, 0)
        loader.hide(clearCache: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(loader.image)
        XCTAssertEqual(loader.cachedCount, 0)
    }

    func testFallbackThumbnailPreservesAnamorphicDisplayAspectWithinBounds() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated/rotation-par.mp4")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Generated media fixtures are unavailable.")
        }
        let image = try await ComparisonStillFrameExtractor.ffmpegImage(
            from: url, at: 0.5, maximumSize: CGSize(width: 240, height: 135)
        )
        XCTAssertLessThanOrEqual(image.width, 240)
        XCTAssertLessThanOrEqual(image.height, 135)
        XCTAssertEqual(Double(image.width) / Double(image.height), 9.0 / 16.0, accuracy: 0.02)
    }

    func testLeavingHoverSerializesReplacementAndSuppressesCancelledResult() async throws {
        let recorder = SuspendedExtractor()
        let loader = TimelineThumbnailLoader(debounce: .zero) { _, time in
            await recorder.extract(time: time)
        }
        let media = item()
        loader.request(item: media, time: 1)
        try await waitUntil { recorder.times.count == 1 }
        loader.hide(clearCache: true)
        loader.request(item: media, time: 2)
        // The replacement stays queued while the cancelled decoder deliberately
        // ignores cancellation and continues holding its continuation.
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(recorder.times, [1])
        XCTAssertNil(loader.image)
        recorder.finish()
        try await waitUntil { recorder.times.count == 2 }
        XCTAssertNil(loader.image)
        XCTAssertNil(loader.imageTime)
        XCTAssertEqual(recorder.times, [1, 2])
        XCTAssertEqual(recorder.maximumActive, 1)
        recorder.finish()
        try await waitUntil { loader.imageTime == 2 }
        XCTAssertNotNil(loader.image)
        XCTAssertEqual(loader.cachedCount, 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out waiting for thumbnail worker")
    }

    @MainActor
    private final class SuspendedExtractor {
        var times: [Double] = []
        var maximumActive = 0
        private var active = 0
        private var continuation: CheckedContinuation<CGImage, Never>?

        func extract(time: Double) async -> CGImage {
            times.append(time)
            active += 1
            maximumActive = max(maximumActive, active)
            return await withCheckedContinuation { continuation = $0 }
        }

        func finish() {
            let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                    bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let pending = continuation
            continuation = nil
            active -= 1
            pending?.resume(returning: context.makeImage()!)
        }
    }
}
