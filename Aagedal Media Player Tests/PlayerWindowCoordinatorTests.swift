// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerWindowCoordinatorTests: XCTestCase {
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
