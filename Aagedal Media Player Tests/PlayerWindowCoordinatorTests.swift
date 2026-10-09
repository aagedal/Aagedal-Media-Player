// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerWindowCoordinatorTests: XCTestCase {
    func testOpeningIndicatorHandsOffToPlaybackPreparation() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mkv")
        let coordinator = PlayerWindowCoordinator()
        let controller = PlayerController()
        let loaded = expectation(description: "Media handed to playback controller")
        let observation = controller.$mediaItem.compactMap { $0 }.prefix(1).sink { item in
            XCTAssertEqual(item.url, url)
            loaded.fulfill()
        }
        defer {
            observation.cancel()
            coordinator.tearDown()
            controller.teardown()
        }

        coordinator.openFile(url, controller: controller,
            onTimecodeModeChange: { _ in }, onMetadataLoaded: {})
        XCTAssertEqual(coordinator.openingURL, url)
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertNil(coordinator.openingURL)
        XCTAssertNotEqual(controller.playbackPhase, .idle)
    }

    func testOpeningIndicatorSurvivesSupersededSlowFileAndClearsOnTeardown() async {
        let first = URL(fileURLWithPath: "/network/first.mkv")
        let second = URL(fileURLWithPath: "/network/second.mkv")
        let firstStarted = expectation(description: "First file read started")
        let secondStarted = expectation(description: "Second file read started")
        let reads = SuspendedMediaItemReads()
        let coordinator = PlayerWindowCoordinator(mediaItemLoader: { url in
            await reads.load(url) {
                (url == first ? firstStarted : secondStarted).fulfill()
            }
        })
        let controller = PlayerController()

        coordinator.openFile(first, controller: controller,
            onTimecodeModeChange: { _ in }, onMetadataLoaded: {})
        XCTAssertEqual(coordinator.openingURL, first)
        XCTAssertNil(controller.mediaItem)
        await fulfillment(of: [firstStarted], timeout: 1)

        coordinator.openFile(second, controller: controller,
            onTimecodeModeChange: { _ in }, onMetadataLoaded: {})
        XCTAssertEqual(coordinator.openingURL, second)
        await fulfillment(of: [secondStarted], timeout: 1)
        await reads.finish(first)
        // Let the cancelled request resume on the main actor.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(coordinator.openingURL, second)
        XCTAssertNil(controller.mediaItem)

        coordinator.tearDown()
        XCTAssertNil(coordinator.openingURL)
        await reads.finish(second)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(coordinator.openingURL)
        XCTAssertNil(controller.mediaItem)
    }

    func testWindowConfiguratorDefersAndCoalescesRepeatedAvailability() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 711, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let coordinator = WindowConfigurator.Coordinator()
        let view = WindowConfigurator.ConfiguratorNSView()
        view.coordinator = coordinator
        let delivered = expectation(description: "Window availability delivered")
        let duplicate = expectation(description: "Window availability not delivered twice")
        duplicate.isInverted = true
        var deliveredWindow: NSWindow?
        var deliveryCount = 0
        view.onWindowAvailable = { availableWindow in
            deliveryCount += 1
            deliveredWindow = availableWindow
            if deliveryCount == 1 {
                delivered.fulfill()
            } else {
                duplicate.fulfill()
            }
        }

        window.contentView = view
        coordinator.scheduleWindowAvailability(window, from: view)
        coordinator.scheduleWindowAvailability(window, from: view)

        XCTAssertNil(deliveredWindow, "Representable updates must not publish window state synchronously")
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertTrue(deliveredWindow === window)
        coordinator.scheduleWindowAvailability(window, from: view)
        await fulfillment(of: [duplicate], timeout: 0.05)
        XCTAssertEqual(deliveryCount, 1)
    }

    func testWindowConfiguratorDeliversAReplacementWindow() async {
        let firstWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 711, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let replacementWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 711, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let coordinator = WindowConfigurator.Coordinator()
        let view = WindowConfigurator.ConfiguratorNSView()
        view.coordinator = coordinator
        let firstDelivered = expectation(description: "First window delivered")
        let replacementDelivered = expectation(description: "Replacement window delivered")
        var deliveredWindows: [NSWindow] = []
        view.onWindowAvailable = { window in
            deliveredWindows.append(window)
            if window === firstWindow {
                firstDelivered.fulfill()
            } else if window === replacementWindow {
                replacementDelivered.fulfill()
            }
        }

        firstWindow.contentView = view
        await fulfillment(of: [firstDelivered], timeout: 1)
        replacementWindow.contentView = view
        coordinator.scheduleWindowAvailability(replacementWindow, from: view)
        await fulfillment(of: [replacementDelivered], timeout: 1)

        XCTAssertEqual(deliveredWindows.count, 2)
        XCTAssertTrue(deliveredWindows.first.map { $0 === firstWindow } ?? false)
        XCTAssertTrue(deliveredWindows.last.map { $0 === replacementWindow } ?? false)
    }

    func testMakeMediaItemUsesFilenameAndFileSize() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Opening Shot.mov")
        let bytes = Data(repeating: 0x2A, count: 37)
        try bytes.write(to: url)

        let item = PlayerWindowCoordinator.makeMediaItem(for: url)

        XCTAssertEqual(item.url, url)
        XCTAssertEqual(item.name, "Opening Shot")
        XCTAssertEqual(item.size, 37)
    }

    func testDroppedURLResultsPreservesProviderOrder() {
        let first = URL(fileURLWithPath: "/tmp/first.mov")
        let second = URL(fileURLWithPath: "/tmp/second.mov")
        let third = URL(fileURLWithPath: "/tmp/third.mov")
        let results = DroppedURLResults(count: 3)

        XCTAssertNil(results.record(third, at: 2))
        XCTAssertNil(results.record(first, at: 0))
        XCTAssertEqual(results.record(second, at: 1), [first, second, third])
    }

    func testDroppedURLResultsOmitsFailedProviders() {
        let url = URL(fileURLWithPath: "/tmp/valid.mov")
        let results = DroppedURLResults(count: 2)

        XCTAssertNil(results.record(nil, at: 0))
        XCTAssertEqual(results.record(url, at: 1), [url])
    }

    func testDroppedURLResultsCancellationRejectsPendingCompletion() {
        let first = URL(fileURLWithPath: "/tmp/first.mov")
        let second = URL(fileURLWithPath: "/tmp/second.mov")
        let results = DroppedURLResults(count: 2)

        XCTAssertNil(results.record(first, at: 0))
        results.cancel()

        XCTAssertNil(results.record(second, at: 1))
    }

    func testSiblingMediaFilesFiltersHiddenDirectoriesAndUnsupportedFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = ["Clip 2.mov", "Clip 10.MP4", "Soundtrack.flac"]
        for name in expected + ["notes.txt", ".hidden.mp3"] {
            XCTAssertTrue(FileManager.default.createFile(
                atPath: directory.appendingPathComponent(name).path,
                contents: Data()
            ))
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Nested.mov"),
            withIntermediateDirectories: false
        )

        let files = PlayerWindowCoordinator.siblingMediaFiles(
            containing: directory.appendingPathComponent("Clip 2.mov")
        )

        XCTAssertEqual(files.map(\.lastPathComponent), expected)
    }

    func testFolderNavigationReportsBoundariesAndAdjacentURLs() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["01.mov", "02.mov", "03.mov"].map {
            directory.appendingPathComponent($0)
        }
        for url in urls {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        }

        let coordinator = PlayerWindowCoordinator()
        coordinator.applyFolderNavigation(currentURL: urls[1], siblingURLs: urls)

        XCTAssertTrue(coordinator.canOpenPreviousFile)
        XCTAssertTrue(coordinator.canOpenNextFile)
        XCTAssertEqual(
            coordinator.previousMediaURL()?.resolvingSymlinksInPath(),
            urls[0].resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            coordinator.nextMediaURL()?.resolvingSymlinksInPath(),
            urls[2].resolvingSymlinksInPath()
        )
        coordinator.tearDown()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private actor SuspendedMediaItemReads {
    private var continuations: [URL: CheckedContinuation<MediaItem, Never>] = [:]

    func load(_ url: URL, onStarted: @Sendable () -> Void) async -> MediaItem {
        await withCheckedContinuation { continuation in
            continuations[url] = continuation
            onStarted()
        }
    }

    func finish(_ url: URL) {
        continuations.removeValue(forKey: url)?.resume(returning: MediaItem(
            url: url, name: url.deletingPathExtension().lastPathComponent, size: 0
        ))
    }
}
