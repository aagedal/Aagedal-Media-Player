// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreGraphics
import Darwin
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class TimelineThumbnailLoaderTests: XCTestCase {
    /// Opt-in production-decoder profile. The script provides explicit files;
    /// ordinary regression runs do not depend on long-form profiling media.
    func testProductionThumbnailProfileWhenRequested() async throws {
        guard let input = ProcessInfo.processInfo.environment["TIMELINE_PROFILE_INPUTS"] else { return }
        let paths = try JSONDecoder().decode([String].self, from: Data(input.utf8))
        XCTAssertFalse(paths.isEmpty)
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            XCTAssertTrue(duration.isFinite && duration >= 40, "Profile inputs must be at least 40 seconds")
            guard duration.isFinite && duration >= 40 else { continue }
            let media = MediaItem(url: url, name: url.lastPathComponent, size: 0,
                                  durationSeconds: duration)
            let loader = TimelineThumbnailLoader()
            defer { loader.hide(clearCache: true) }
            var latencies: [Double] = []
            let initialResident = try residentBytes()
            var peakResident = initialResident
            var maximumImageBytes = 0
            // A coprime permutation forces distributed cold seeks rather than
            // benefitting from sequential decoder read-ahead.
            for index in 0..<40 {
                // Offset inside each interval so the 1/8/24-hour fixtures do
                // not accidentally request only their ten-second keyframes.
                let time = duration * (Double((index * 17) % 40) + 0.413) / 40
                let requested = try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: time))
                let start = ContinuousClock.now
                loader.request(item: media, time: time)
                let deadline = start.advanced(by: .seconds(30))
                while loader.imageTime != requested.time, ContinuousClock.now < deadline {
                    peakResident = max(peakResident, try residentBytes())
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertEqual(loader.imageTime, requested.time, "No preview for \(url.lastPathComponent) at \(time)")
                let image = try XCTUnwrap(loader.image)
                XCTAssertLessThanOrEqual(image.width, 240)
                XCTAssertLessThanOrEqual(image.height, 135)
                maximumImageBytes = max(maximumImageBytes, image.bytesPerRow * image.height)
                XCTAssertLessThanOrEqual(loader.cachedCount, TimelineThumbnailLoader.cacheLimit)
                let elapsed = start.duration(to: .now).components
                latencies.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            }
            XCTAssertEqual(loader.cachedCount, TimelineThumbnailLoader.cacheLimit)
            // The last requested image is cached: reopening must be immediate.
            let lastTime = try XCTUnwrap(loader.imageTime)
            loader.hide()
            loader.request(item: media, time: lastTime)
            XCTAssertNotNil(loader.image)
            XCTAssertEqual(loader.imageTime, lastTime)
            latencies.sort()
            let report: [String: Any] = [
                "file": url.lastPathComponent, "durationSeconds": duration,
                "samples": latencies.count, "cachedImages": loader.cachedCount,
                "medianSeconds": (latencies[19] + latencies[20]) / 2,
                "p95Seconds": latencies[37], "maximumSeconds": latencies[39],
                "initialResidentBytes": initialResident, "sampledPeakResidentBytes": peakResident,
                "cachePixelBytesUpperBound": maximumImageBytes * TimelineThumbnailLoader.cacheLimit,
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let line = "TIMELINE_PROFILE " + String(decoding: data, as: UTF8.self)
            print(line)
            let attachment = XCTAttachment(string: line)
            attachment.name = "Timeline thumbnail profile — \(url.lastPathComponent)"
            attachment.lifetime = .keepAlways
            add(attachment)
            loader.hide(clearCache: true)
            XCTAssertEqual(loader.cachedCount, 0)
            XCTAssertNil(loader.image)
        }
    }

    private func residentBytes() throws -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw NSError(domain: NSMachErrorDomain, code: Int(result)) }
        return UInt64(info.resident_size)
    }

    private func item(duration: Double = 10) -> MediaItem {
        MediaItem(url: URL(fileURLWithPath: "/tmp/thumbnail.mov"), name: "Preview", size: 0,
                  durationSeconds: duration)
    }

    func testRequestsQuantizeAndStayBeforeExclusiveMediaEnd() throws {
        let media = item()
        XCTAssertEqual(try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: 2.74)).time, 2.5)
        XCTAssertEqual(try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: -1)).time, 0)
        XCTAssertLessThan(try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: 99)).time, 10)
        XCTAssertEqual(
            try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: .greatestFiniteMagnitude)).time,
            try XCTUnwrap(TimelineThumbnailLoader.Request(item: media, time: 99)).time
        )
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

    func testURLReplacementWithSameMediaIDInvalidatesCacheAndSerializesDecode() async throws {
        let recorder = SuspendedExtractor()
        let loader = TimelineThumbnailLoader(debounce: .zero) { _, time in
            await recorder.extract(time: time)
        }
        var media = item()
        loader.request(item: media, time: 1)
        try await waitUntil { recorder.times.count == 1 }
        recorder.finish()
        try await waitUntil { loader.imageTime == 1 }
        XCTAssertEqual(loader.cachedCount, 1)

        loader.request(item: media, time: 2)
        try await waitUntil { recorder.times.count == 2 }
        media.url = URL(fileURLWithPath: "/tmp/replacement.mov")
        loader.request(item: media, time: 1)
        XCTAssertNil(loader.image, "A cached frame from the previous URL must not be shown")
        XCTAssertEqual(loader.cachedCount, 0)
        XCTAssertEqual(recorder.times, [1, 2])
        recorder.finish()
        try await waitUntil { recorder.times.count == 3 }
        XCTAssertNil(loader.image)
        XCTAssertEqual(loader.cachedCount, 0, "The old URL's in-flight result must be discarded")
        XCTAssertEqual(recorder.maximumActive, 1)
        recorder.finish()
        try await waitUntil { loader.imageTime == 1 }
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
