// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareReviewTimelineTests: XCTestCase {
    func testFrameIndexSnapsAtFractionalFrameRate() {
        let rate = 24_000.0 / 1_001.0
        let frameTime = 100.0 / rate

        XCTAssertEqual(
            CompareReviewTimeline.frameIndex(
                for: frameTime + (0.49 / rate),
                duration: 60,
                frameRate: rate
            ),
            100
        )
        XCTAssertEqual(
            CompareReviewTimeline.frameIndex(
                for: frameTime + (0.51 / rate),
                duration: 60,
                frameRate: rate
            ),
            101
        )
    }

    func testDurationClampsToLastPlayableFrame() {
        XCTAssertEqual(
            CompareReviewTimeline.frameIndex(for: 10, duration: 10, frameRate: 24),
            239
        )
        XCTAssertEqual(
            CompareReviewTimeline.frameIndex(for: -.infinity, duration: 10, frameRate: 24),
            0
        )
    }

    func testFrameRoundTripDoesNotDriftAt2997() {
        let rate = 30_000.0 / 1_001.0
        let originalFrame: Int64 = 107_892
        let time = CompareReviewTimeline.time(
            forFrame: originalFrame,
            duration: 7_200,
            frameRate: rate
        )

        XCTAssertEqual(
            CompareReviewTimeline.frameIndex(
                for: time,
                duration: 7_200,
                frameRate: rate
            ),
            originalFrame
        )
    }
}

final class CompareReviewSidecarStoreTests: XCTestCase {
    func testPairSpecificSidecarURLIsAdjacentToPrimary() {
        let primary = URL(fileURLWithPath: "/Volumes/QC/Master.mov")
        let first = URL(fileURLWithPath: "/Volumes/QC/Encode.mov")
        let second = URL(fileURLWithPath: "/Volumes/Other/Encode.mov")

        let firstURL = CompareReviewSidecarStore.sidecarURL(
            primaryURL: primary,
            secondaryURL: first
        )
        let secondURL = CompareReviewSidecarStore.sidecarURL(
            primaryURL: primary,
            secondaryURL: second
        )

        XCTAssertEqual(firstURL.deletingLastPathComponent(), primary.deletingLastPathComponent())
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertTrue(firstURL.lastPathComponent.hasSuffix(".aagedal-compare.json"))
    }

    func testSaveAndLoadRoundTripsUnicodeNote() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = CompareReviewSidecarStore()
        let note = CompareReviewNote(
            primaryFrame: 42,
            primaryTime: 1.75,
            secondaryFrame: 48,
            secondaryTime: 2,
            text: "Hudtone – sjekk blåkanal\nSecond line",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        let document = CompareReviewDocument(
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary,
            notes: [note]
        )

        try await store.save(document, to: fixture.sidecar, revision: 1)
        let loaded = try await store.load(
            from: fixture.sidecar,
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary
        )

        XCTAssertEqual(loaded, document)
    }

    func testMissingSidecarLoadsAsNil() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = CompareReviewSidecarStore()

        let loaded = try await store.load(
            from: fixture.sidecar,
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary
        )

        XCTAssertNil(loaded)
    }

    func testSidecarSourceOrderIsValidated() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = CompareReviewSidecarStore()
        let document = CompareReviewDocument(
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary,
            notes: []
        )
        try await store.save(document, to: fixture.sidecar, revision: 1)

        do {
            _ = try await store.load(
                from: fixture.sidecar,
                primaryURL: fixture.secondary,
                secondaryURL: fixture.primary
            )
            XCTFail("Expected source-pair mismatch")
        } catch let error as CompareReviewSidecarError {
            XCTAssertEqual(error.localizedDescription, CompareReviewSidecarError.sourcePairMismatch.localizedDescription)
        }
    }

    func testSavingSidecarDoesNotModifyMedia() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let primaryBytes = Data("primary media".utf8)
        let secondaryBytes = Data("secondary media".utf8)
        try primaryBytes.write(to: fixture.primary)
        try secondaryBytes.write(to: fixture.secondary)

        let store = CompareReviewSidecarStore()
        let document = CompareReviewDocument(
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary,
            notes: []
        )
        try await store.save(document, to: fixture.sidecar, revision: 1)

        XCTAssertEqual(try Data(contentsOf: fixture.primary), primaryBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.secondary), secondaryBytes)
    }

    func testMutationsMergeNotesFromConcurrentReviewWindows() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("primary".utf8).write(to: fixture.primary)
        try Data("secondary".utf8).write(to: fixture.secondary)
        let store = CompareReviewSidecarStore()
        let first = CompareReviewNote(
            primaryFrame: 1,
            primaryTime: 1.0 / 30,
            secondaryFrame: 1,
            secondaryTime: 1.0 / 30,
            text: "First window"
        )
        let second = CompareReviewNote(
            primaryFrame: 2,
            primaryTime: 2.0 / 30,
            secondaryFrame: 2,
            secondaryTime: 2.0 / 30,
            text: "Second window"
        )

        async let firstResult = store.apply(
            .upsert(first),
            to: fixture.sidecar,
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary
        )
        async let secondResult = store.apply(
            .upsert(second),
            to: fixture.sidecar,
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary
        )
        _ = try await (firstResult, secondResult)

        let loaded = try await store.load(
            from: fixture.sidecar,
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary
        )
        XCTAssertEqual(loaded?.notes.map(\.text), ["First window", "Second window"])
    }

    func testReplacingMediaAtSamePathRejectsOldReview() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("primary version one".utf8).write(to: fixture.primary)
        try Data("secondary version one".utf8).write(to: fixture.secondary)
        let store = CompareReviewSidecarStore()
        let document = CompareReviewDocument(
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary,
            notes: []
        )
        try await store.save(document, to: fixture.sidecar, revision: 1)

        try Data("secondary replacement with a different size".utf8).write(
            to: fixture.secondary,
            options: .atomic
        )

        do {
            _ = try await store.load(
                from: fixture.sidecar,
                primaryURL: fixture.primary,
                secondaryURL: fixture.secondary
            )
            XCTFail("Expected replacement media to fail source-pair validation")
        } catch let error as CompareReviewSidecarError {
            XCTAssertEqual(
                error.localizedDescription,
                CompareReviewSidecarError.sourcePairMismatch.localizedDescription
            )
        }
    }

    func testSidecarPreservesSubsecondTimestamps() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = CompareReviewSidecarStore()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.123)
        let document = CompareReviewDocument(
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary,
            notes: [CompareReviewNote(
                primaryFrame: 0,
                primaryTime: 0,
                secondaryFrame: 0,
                secondaryTime: 0,
                text: "Precise",
                createdAt: timestamp,
                updatedAt: timestamp
            )]
        )
        try await store.save(document, to: fixture.sidecar, revision: 1)

        let loaded = try await store.load(
            from: fixture.sidecar,
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary
        )

        XCTAssertEqual(
            try XCTUnwrap(loaded?.notes.first?.createdAt).timeIntervalSince1970,
            timestamp.timeIntervalSince1970,
            accuracy: 0.000_1
        )
    }

    private func makeFixture() throws -> (
        directory: URL,
        primary: URL,
        secondary: URL,
        sidecar: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let primary = directory.appendingPathComponent("Master.mov")
        let secondary = directory.appendingPathComponent("Encode.mov")
        return (
            directory,
            primary,
            secondary,
            CompareReviewSidecarStore.sidecarURL(
                primaryURL: primary,
                secondaryURL: secondary
            )
        )
    }
}
