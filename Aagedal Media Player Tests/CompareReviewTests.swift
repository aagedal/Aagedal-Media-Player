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

    func testMalformedNotePositionsAndRatesAreRejectedWithoutChangingSidecar() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = CompareReviewSidecarStore()
        let document = CompareReviewDocument(
            primaryURL: fixture.primary,
            secondaryURL: fixture.secondary,
            notes: [CompareReviewNote(
                primaryFrame: 42, primaryTime: 1.4,
                secondaryFrame: 42, secondaryTime: 1.4, text: "Keep this review"
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let validJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(document)) as? [String: Any])
        let invalidValues: [(String, NSNumber)] = [
            ("primaryFrame", -1), ("secondaryFrame", -1),
            ("primaryTime", -0.1), ("secondaryTime", -0.1),
            ("primaryRateNumerator", 0), ("secondaryRateNumerator", -1),
            ("primaryRateDenominator", 0), ("secondaryRateDenominator", -1),
            ("primaryFrame", NSNumber(value: Int64.max)),
            ("secondaryFrame", NSNumber(value: Int64.max)),
            ("primaryRateNumerator", NSNumber(value: Int64.max)),
            ("secondaryRateDenominator", NSNumber(value: Int64.max)),
            // Below Int64.max, but unsafe after the decimal-rate export scale.
            ("primaryFrame", NSNumber(value: Int64.max / 1_000_000)),
        ]
        for (field, value) in invalidValues {
            var json = validJSON
            var notes = try XCTUnwrap(json["notes"] as? [[String: Any]])
            notes[0][field] = value
            json["notes"] = notes
            let original = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
            try original.write(to: fixture.sidecar)

            do {
                _ = try await store.load(from: fixture.sidecar, primaryURL: fixture.primary, secondaryURL: fixture.secondary)
                XCTFail("Expected invalid \(field)=\(value) to be rejected")
            } catch let error as CompareReviewSidecarError {
                guard case .invalidNote(1, _) = error else {
                    return XCTFail("Expected an actionable invalid-note error: \(error)")
                }
                XCTAssertTrue(error.localizedDescription.contains("Restore a valid sidecar backup"))
            }
            do {
                _ = try await store.apply(.delete(document.notes[0].id), to: fixture.sidecar, primaryURL: fixture.primary, secondaryURL: fixture.secondary)
                XCTFail("An edit must not overwrite invalid \(field)=\(value)")
            } catch let error as CompareReviewSidecarError {
                guard case .invalidNote = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(try Data(contentsOf: fixture.sidecar), original)
        }
    }

    func testDuplicateNoteIdentifiersAreRejectedWithoutChangingSidecar() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let note = CompareReviewNote(
            primaryFrame: 1, primaryTime: 1.0 / 30,
            secondaryFrame: 1, secondaryTime: 1.0 / 30, text: "Duplicated"
        )
        let document = CompareReviewDocument(
            primaryURL: fixture.primary, secondaryURL: fixture.secondary, notes: [note, note]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let original = try encoder.encode(document)
        try original.write(to: fixture.sidecar)
        let store = CompareReviewSidecarStore()
        do {
            _ = try await store.load(from: fixture.sidecar, primaryURL: fixture.primary, secondaryURL: fixture.secondary)
            XCTFail("Expected duplicate IDs to be rejected")
        } catch let error as CompareReviewSidecarError {
            guard case .invalidNote(2, "duplicate note identifier") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        do {
            _ = try await store.apply(.upsert(note), to: fixture.sidecar, primaryURL: fixture.primary, secondaryURL: fixture.secondary)
            XCTFail("An edit must not overwrite duplicate IDs")
        } catch let error as CompareReviewSidecarError {
            guard case .invalidNote = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.sidecar), original)
    }

    func testLongReviewsAtFractionalRatesRemainValid() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let rates: [(Int64, Int64)] = [(24_000, 1_001), (30_000, 1_001), (60_000, 1_001), (23_987_654, 1_000_000)]
        let notes = rates.map { numerator, denominator in
            CompareReviewNote(
                primaryFrame: 3_000_000_000, primaryTime: 125_000_000,
                secondaryFrame: 3_000_000_000, secondaryTime: 125_000_000,
                primaryRateNumerator: numerator, primaryRateDenominator: denominator,
                secondaryRateNumerator: numerator, secondaryRateDenominator: denominator,
                text: "Preserve stored coordinates and rates",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        }
        let document = CompareReviewDocument(primaryURL: fixture.primary, secondaryURL: fixture.secondary, notes: notes)
        let store = CompareReviewSidecarStore()
        try await store.save(document, to: fixture.sidecar, revision: 1)
        let loaded = try await store.load(from: fixture.sidecar, primaryURL: fixture.primary, secondaryURL: fixture.secondary)
        XCTAssertEqual(loaded, document)
    }

    func testRejectedSavePreservesPreviousDocumentAndDoesNotAdvanceRevision() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let note = CompareReviewNote(
            primaryFrame: 0, primaryTime: 0,
            secondaryFrame: 0, secondaryTime: 0, text: "Original",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        var document = CompareReviewDocument(primaryURL: fixture.primary, secondaryURL: fixture.secondary, notes: [note])
        let store = CompareReviewSidecarStore()
        try await store.save(document, to: fixture.sidecar, revision: 1)
        let original = try Data(contentsOf: fixture.sidecar)
        document.notes.append(note)
        do {
            try await store.save(document, to: fixture.sidecar, revision: 99)
            XCTFail("Invalid save must be rejected")
        } catch let error as CompareReviewSidecarError {
            guard case .invalidNote = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.sidecar), original)
        document.notes = [note]
        document.notes[0].text = "Valid follow-up"
        try await store.save(document, to: fixture.sidecar, revision: 2)
        let loaded = try await store.load(from: fixture.sidecar, primaryURL: fixture.primary, secondaryURL: fixture.secondary)
        XCTAssertEqual(loaded, document)
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
