// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class OutputCoordinatorTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        directoryURL = nil
    }

    @MainActor
    func testAutomaticOutputChoosesNumericSuffixWithoutOverwriting() throws {
        let existingURL = directoryURL.appendingPathComponent("clip_trimmed.mov")
        try Data("original".utf8).write(to: existingURL)

        let output = OutputCoordinator.automatic(
            directory: directoryURL,
            preferredFilename: "clip_trimmed.mov"
        )
        XCTAssertEqual(output.destinationURL.lastPathComponent, "clip_trimmed 2.mov")
        XCTAssertEqual(output.temporaryURL.pathExtension, "mov")

        try Data("new".utf8).write(to: output.temporaryURL)
        let committedURL = try output.commit()

        XCTAssertEqual(committedURL.lastPathComponent, "clip_trimmed 2.mov")
        XCTAssertEqual(try Data(contentsOf: existingURL), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: committedURL), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.temporaryURL.path))
    }

    @MainActor
    func testCommitHandlesCollisionCreatedAfterPreparation() throws {
        let output = OutputCoordinator.automatic(
            directory: directoryURL,
            preferredFilename: "frame.png"
        )
        try Data("encoded".utf8).write(to: output.temporaryURL)
        try Data("raced".utf8).write(to: output.destinationURL)

        let committedURL = try output.commit()

        XCTAssertEqual(committedURL.lastPathComponent, "frame 2.png")
        XCTAssertEqual(try Data(contentsOf: output.destinationURL), Data("raced".utf8))
        XCTAssertEqual(try Data(contentsOf: committedURL), Data("encoded".utf8))
    }

    @MainActor
    func testUserConfirmedOutputReplacesOnlyAtCommit() throws {
        let destinationURL = directoryURL.appendingPathComponent("chosen.jpg")
        try Data("old".utf8).write(to: destinationURL)
        let output = OutputCoordinator.userConfirmed(destinationURL: destinationURL)
        try Data("new".utf8).write(to: output.temporaryURL)

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("old".utf8))
        let committedURL = try output.commit()

        XCTAssertEqual(committedURL, destinationURL)
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))
    }

    @MainActor
    func testDiscardRemovesPartialOutputWithoutTouchingDestination() throws {
        let output = OutputCoordinator.automatic(
            directory: directoryURL,
            preferredFilename: "frame.jxl"
        )
        try Data("partial".utf8).write(to: output.temporaryURL)

        output.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.temporaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.destinationURL.path))
    }

    @MainActor
    func testCommitRejectsMissingTemporaryOutput() {
        let output = OutputCoordinator.automatic(
            directory: directoryURL,
            preferredFilename: "missing.mp4"
        )

        XCTAssertThrowsError(try output.commit()) { error in
            XCTAssertEqual(error as? OutputCoordinatorError, .temporaryOutputMissing)
        }
    }
}
