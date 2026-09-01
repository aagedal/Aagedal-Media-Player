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
}
