// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftMediaMetadata
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MetadataServiceTests: XCTestCase {
    func testCacheReusesUnchangedFileAndRefreshesInPlaceChanges() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let reader = Reader()
        let service = MetadataService(loader: { try await reader.read($0) })
        let first = try await service.metadata(for: url)
        let cached = try await service.metadata(for: url)
        XCTAssertEqual(first.duration, 1)
        XCTAssertEqual(cached, first)
        try Data([1, 2]).write(to: url)
        let changed = try await service.metadata(for: url)
        XCTAssertEqual(changed.duration, 2)
        let calls = await reader.calls
        XCTAssertEqual(calls, 2)
    }

    func testAtomicReplacementWithSameSizeAndModificationDateRefreshesCache() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let reader = Reader()
        let service = MetadataService(loader: { try await reader.read($0) })
        _ = try await service.metadata(for: url)
        try Data([2]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let changed = try await service.metadata(for: url)
        XCTAssertEqual(changed.duration, 2)
    }

    func testDeletedFileDoesNotReturnCachedMetadata() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = Reader()
        let service = MetadataService(loader: { try await reader.read($0) })
        _ = try await service.metadata(for: url)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await service.metadata(for: url)
            XCTFail("Deleted media must not return cached metadata")
        } catch { }
    }

    func testOlderReadCannotOverwriteReplacementCache() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let reader = Reader(holdFirst: true)
        let service = MetadataService(loader: { try await reader.read($0) })
        let old = Task { try await service.metadata(for: url) }
        await reader.waitForFirstRead()
        try Data([2, 2]).write(to: url, options: .atomic)
        let replacement = try await service.metadata(for: url)
        await reader.releaseFirstRead()
        _ = try await old.value
        let cached = try await service.metadata(for: url)
        XCTAssertEqual(replacement.duration, 2)
        XCTAssertEqual(cached, replacement)
        let calls = await reader.calls
        XCTAssertEqual(calls, 2)
    }

    func testFileChangedDuringReadIsNotCached() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let reader = Reader(holdFirst: true)
        let service = MetadataService(loader: { try await reader.read($0) })
        let old = Task { try await service.metadata(for: url) }
        await reader.waitForFirstRead()
        try Data([2, 2]).write(to: url)
        await reader.releaseFirstRead()
        _ = try await old.value
        let refreshed = try await service.metadata(for: url)
        XCTAssertEqual(refreshed.duration, 2)
    }

    func testConcurrentRequestsShareOneRead() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let reader = Reader()
        let service = MetadataService(loader: { try await reader.read($0) })
        try await withThrowingTaskGroup(of: MediaMetadata.self) { group in
            for _ in 0..<20 { group.addTask { try await service.metadata(for: url) } }
            for try await result in group { XCTAssertEqual(result.duration, 1) }
        }
        let calls = await reader.calls
        XCTAssertEqual(calls, 1)
    }

    func testMapperRejectsNonfiniteAndOverflowingFrameCountsAndDisplayWidths() {
        for duration in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -1] {
            var video = VideoMetadata(format: .mp4)
            video.duration = duration
            var stream = VideoStream(index: 0)
            stream.avgFrameRate = 30
            video.videoStreams = [stream]
            XCTAssertNil(MetadataMapper.makeMediaMetadata(from: video).frameCount)
        }
        var video = VideoMetadata(format: .mp4)
        video.duration = 2
        var stream = VideoStream(index: 0)
        stream.avgFrameRate = 29.97
        video.videoStreams = [stream]
        XCTAssertEqual(MetadataMapper.makeMediaMetadata(from: video).frameCount, 60)
        stream.width = Int.max
        stream.height = 1080
        stream.pixelAspectRatio = (Int.max, 1)
        stream.avgFrameRate = .infinity
        video.videoStreams = [stream]
        let mapped = MetadataMapper.makeMediaMetadata(from: video)
        XCTAssertNil(mapped.frameCount)
        XCTAssertNil(mapped.primaryVideoStream?.displayWidth)
        XCTAssertNil(mapped.primaryVideoStream?.frameRate)
    }
}

private actor Reader {
    private(set) var calls = 0
    private let holdFirst: Bool
    private var firstRead: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(holdFirst: Bool = false) { self.holdFirst = holdFirst }

    func read(_ url: URL) async throws -> MediaMetadata {
        _ = try Data(contentsOf: url)
        calls += 1
        let index = calls
        if holdFirst && index == 1 {
            await withCheckedContinuation { continuation in
                firstRead = continuation
                for waiter in startWaiters { waiter.resume() }
                startWaiters.removeAll()
            }
        }
        var video = VideoMetadata(format: .mp4)
        video.duration = Double(index)
        return MetadataMapper.makeMediaMetadata(from: video)
    }

    func waitForFirstRead() async {
        if firstRead != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseFirstRead() {
        firstRead?.resume()
        firstRead = nil
    }
}
