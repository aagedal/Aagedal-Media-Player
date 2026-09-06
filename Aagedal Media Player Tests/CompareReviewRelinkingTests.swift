// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareReviewRelinkingTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let source: URL
        let primary: URL
        let secondary: URL
        let destination: URL
        let document: CompareReviewDocument
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primary = directory.appendingPathComponent("New A.mov")
        let secondary = directory.appendingPathComponent("New B.mov")
        try Data("A media".utf8).write(to: primary)
        try Data("B media".utf8).write(to: secondary)
        let document = CompareReviewDocument(
            primaryURL: directory.appendingPathComponent("Missing A.mov"),
            secondaryURL: directory.appendingPathComponent("Missing B.mov"),
            notes: [CompareReviewNote(
                primaryFrame: 42, primaryTime: 42 * 1_001.0 / 30_000,
                secondaryFrame: 100, secondaryTime: 100.0 / 24,
                primaryRateNumerator: 30_000, primaryRateDenominator: 1_001,
                secondaryRateNumerator: 24, text: "Keep every field\nSecond line",
                severity: .critical, category: .sync, status: .inProgress,
                primaryEndFrame: 84,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000.123),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_001.456)
            )]
        )
        let source = directory.appendingPathComponent("old-review.json")
        try encode(document).write(to: source)
        return Fixture(directory: directory, source: source, primary: primary, secondary: secondary,
                       destination: CompareReviewSidecarStore.sidecarURL(primaryURL: primary, secondaryURL: secondary),
                       document: document)
    }

    private func encode(_ document: CompareReviewDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(document)
    }

    func testRelinkMissingOriginalMediaPreservesNotesAndOriginalBytes() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let originalBytes = try Data(contentsOf: f.source)
        let store = CompareReviewSidecarStore()
        let preview = try await store.previewRelink(from: f.source)
        XCTAssertEqual(preview, f.document)
        let result = try await store.relink(from: f.source, to: f.destination, primaryURL: f.primary,
                                           secondaryURL: f.secondary, expectedDocument: preview)
        XCTAssertEqual(result.notes, preview.notes)
        XCTAssertTrue(result.belongsTo(primaryURL: f.primary, secondaryURL: f.secondary))
        XCTAssertFalse(result.belongsTo(primaryURL: f.secondary, secondaryURL: f.primary))
        let loaded = try await store.load(from: f.destination, primaryURL: f.primary, secondaryURL: f.secondary)
        XCTAssertEqual(loaded, result)
        XCTAssertEqual(try Data(contentsOf: f.source), originalBytes)
        XCTAssertEqual(try Data(contentsOf: f.primary), Data("A media".utf8))
        XCTAssertEqual(try Data(contentsOf: f.secondary), Data("B media".utf8))
    }

    func testChangedPreviewIsRejectedWithoutCreatingDestination() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let store = CompareReviewSidecarStore()
        let preview = try await store.previewRelink(from: f.source)
        var changed = preview
        changed.notes[0].text = "Another window edited this"
        let changedBytes = try encode(changed)
        try changedBytes.write(to: f.source)
        do {
            _ = try await store.relink(from: f.source, to: f.destination, primaryURL: f.primary,
                                       secondaryURL: f.secondary, expectedDocument: preview)
            XCTFail("A stale preview must not be imported")
        } catch CompareReviewSidecarError.relinkPreviewChanged {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
        XCTAssertEqual(try Data(contentsOf: f.source), changedBytes)
    }

    func testExistingDestinationAndOriginalCannotBeOverwritten() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let store = CompareReviewSidecarStore()
        let preview = try await store.previewRelink(from: f.source)
        try Data("existing review".utf8).write(to: f.destination)
        for destination in [f.destination, f.source, f.primary, f.secondary] {
            let bytes = try Data(contentsOf: destination)
            do {
                _ = try await store.relink(from: f.source, to: destination, primaryURL: f.primary,
                                           secondaryURL: f.secondary, expectedDocument: preview)
                XCTFail("Existing data must not be replaced")
            } catch CompareReviewSidecarError.relinkDestinationExists {}
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
    }

    func testMissingOrDirectoryReplacementMediaIsRejected() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let store = CompareReviewSidecarStore()
        let preview = try await store.previewRelink(from: f.source)
        for invalidSource in [f.directory, f.directory.appendingPathComponent("missing.mov")] {
            do {
                _ = try await store.relink(from: f.source, to: f.destination, primaryURL: invalidSource,
                                           secondaryURL: f.secondary, expectedDocument: preview)
                XCTFail("Replacement media must be a readable regular file")
            } catch CompareReviewSidecarError.relinkSourceUnavailable {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
        }
    }

    func testPreviewRejectsUnsupportedSchemaAndInvalidNotes() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let store = CompareReviewSidecarStore()
        var invalid = f.document
        invalid.schemaVersion = CompareReviewDocument.currentSchemaVersion + 1
        try encode(invalid).write(to: f.source)
        do {
            _ = try await store.previewRelink(from: f.source)
            XCTFail("Unsupported schema must be rejected")
        } catch CompareReviewSidecarError.unsupportedSchema {}
        invalid = f.document
        invalid.notes[0].primaryEndFrame = 0
        try encode(invalid).write(to: f.source)
        do {
            _ = try await store.previewRelink(from: f.source)
            XCTFail("Invalid notes must be rejected")
        } catch CompareReviewSidecarError.invalidNote {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }

    func testConcurrentStoresPublishExactlyOneReview() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let preview = try await CompareReviewSidecarStore().previewRelink(from: f.source)
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do {
                        _ = try await CompareReviewSidecarStore().relink(
                            from: f.source, to: f.destination, primaryURL: f.primary,
                            secondaryURL: f.secondary, expectedDocument: preview
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        XCTAssertEqual(successes, 1)
        let loaded = try await CompareReviewSidecarStore().load(
            from: f.destination, primaryURL: f.primary, secondaryURL: f.secondary
        )
        XCTAssertEqual(loaded?.notes, preview.notes)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.directory.path)
        XCTAssertFalse(leftovers.contains { $0.hasSuffix(".partial") })
    }

    func testDanglingDestinationSymlinkIsNotReplaced() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let store = CompareReviewSidecarStore()
        let preview = try await store.previewRelink(from: f.source)
        let missingPath = f.directory.appendingPathComponent("missing.json").path
        try FileManager.default.createSymbolicLink(atPath: f.destination.path, withDestinationPath: missingPath)
        do {
            _ = try await store.relink(from: f.source, to: f.destination, primaryURL: f.primary,
                                       secondaryURL: f.secondary, expectedDocument: preview)
            XCTFail("A dangling symlink must not be replaced")
        } catch CompareReviewSidecarError.relinkDestinationExists {}
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: f.destination.path), missingPath)
    }

    func testCanceledRelinkDoesNotCreateDestination() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let store = CompareReviewSidecarStore()
        let preview = try await store.previewRelink(from: f.source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.relink(from: f.source, to: f.destination, primaryURL: f.primary,
                                          secondaryURL: f.secondary, expectedDocument: preview)
        }
        do {
            _ = try await task.value
            XCTFail("Canceled work must not publish a review")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }
}
