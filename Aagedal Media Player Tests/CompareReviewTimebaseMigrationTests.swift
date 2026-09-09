// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareReviewTimebaseMigrationTests: XCTestCase {
    func testRecognizedHistoricalRatesRetainFramesRangesAndFindingIdentity() throws {
        for (decimal, exact) in [(23_976, 24_000), (29_970, 30_000), (47_952, 48_000),
                                  (59_940, 60_000), (119_880, 120_000)] {
            let f = try ReviewTimebaseMigrationFixture(decimal: decimal, exact: exact)
            defer { f.remove() }
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let migration = try f.proposal(migratedAt: date)
            let before = f.document.notes[0]
            let after = migration.migrated.notes[0]
            XCTAssertEqual(after.id, before.id)
            XCTAssertEqual(after.primaryFrame, 100)
            XCTAssertEqual(after.secondaryFrame, 120)
            XCTAssertEqual(after.primaryEndFrame, 200)
            XCTAssertEqual(after.primaryRateNumerator, Int64(exact))
            XCTAssertEqual(after.primaryRateDenominator, 1_001)
            XCTAssertEqual(after.primaryTime, 100 * 1_001.0 / Double(exact), accuracy: 1e-12)
            XCTAssertEqual(after.secondaryTime, 120 * 1_001.0 / Double(exact), accuracy: 1e-12)
            XCTAssertEqual(after.text, before.text)
            XCTAssertEqual(after.category, .sync)
            XCTAssertEqual(after.severity, .critical)
            XCTAssertEqual(after.status, .inProgress)
            XCTAssertEqual(after.createdAt, before.createdAt)
            XCTAssertEqual(after.updatedAt, date)
            XCTAssertEqual(migration.migrated.primarySource, f.document.primarySource)
            XCTAssertEqual(migration.migrated.secondarySource, f.document.secondarySource)
        }
    }

    func testExactNotesAndUnchangedSecondaryKeepEveryField() throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let exact = CompareReviewNote(primaryFrame: 42, primaryTime: 9,
            secondaryFrame: 50, secondaryTime: 8, primaryRateNumerator: 30_000,
            primaryRateDenominator: 1_001, secondaryRateNumerator: 24, text: "Already exact")
        let historical = CompareReviewNote(primaryFrame: 100, primaryTime: 9,
            secondaryFrame: 150, secondaryTime: 8, primaryRateNumerator: 2_997,
            primaryRateDenominator: 100, secondaryRateNumerator: 24, text: "Reduced decimal")
        var document = f.document
        document.notes = [exact, historical]
        let migration = try CompareReviewTimebaseMigration(document: document,
            primaryURL: f.primary, secondaryURL: f.secondary,
            primaryRate: f.rate, secondaryRate: TimecodeRate(numerator: 24, denominator: 1),
            primaryDuration: 60, secondaryDuration: 60)
        XCTAssertEqual(migration.changedNotes.count, 1)
        XCTAssertEqual(migration.migrated.notes[0], exact)
        XCTAssertEqual(migration.migrated.notes[1].secondaryTime, 8)
        XCTAssertEqual(migration.migrated.notes[1].secondaryRateNumerator, 24)
    }

    func testUnrecognizedRateRejectsEntireProposalAndExactReviewDoesNotMigrate() throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        for numerator in [30, 23_977, 24_000] {
            var document = f.document
            document.notes.append(CompareReviewNote(primaryFrame: 0, primaryTime: 0,
                secondaryFrame: 0, secondaryTime: 0, primaryRateNumerator: Int64(numerator),
                primaryRateDenominator: numerator == 30 ? 1 : 1_000, text: "Unsupported"))
            XCTAssertThrowsError(try f.proposal(document: document)) { error in
                guard case CompareReviewTimebaseMigrationError.unsupportedRate(2, "A") = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        var incompatibleB = f.document
        incompatibleB.notes = [CompareReviewNote(primaryFrame: 0, primaryTime: 0,
            secondaryFrame: 0, secondaryTime: 0, primaryRateNumerator: 29_970,
            primaryRateDenominator: 1_000, secondaryRateNumerator: 24, text: "Wrong B rate")]
        XCTAssertThrowsError(try f.proposal(document: incompatibleB)) { error in
            guard case CompareReviewTimebaseMigrationError.unsupportedRate(1, "B") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let exact = try f.proposal().migrated
        XCTAssertThrowsError(try f.proposal(document: exact)) { error in
            guard case CompareReviewTimebaseMigrationError.noChanges = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSourceRangeAndBEndpointsMustRemainAvailableWithoutClamping() throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        for (durationA, durationB, source) in [(f.rate.seconds(forFrameCount: 100), 60.0, "A"),
            (f.rate.seconds(forFrameCount: 200), 60.0, "A range end"),
            (60.0, f.rate.seconds(forFrameCount: 120), "B")] {
            XCTAssertThrowsError(try f.proposal(durationA: durationA, durationB: durationB)) { error in
                guard case CompareReviewTimebaseMigrationError.unavailableFrame(1, source) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertNoThrow(try f.proposal(durationA: f.rate.seconds(forFrameCount: 201)))
        for duration in [0.0, -Double.infinity, Double.nan] {
            XCTAssertThrowsError(try f.proposal(durationA: duration))
        }
    }

    func testPublishedCopyPreservesOriginalBytesAndCanBeLoadedForSamePair() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let bytes = try Data(contentsOf: f.source)
        let migration = try f.proposal()
        let store = CompareReviewSidecarStore()
        let result = try await store.migrateTimebases(from: f.source, to: f.destination, expectedMigration: migration)
        XCTAssertEqual(result, migration.migrated)
        XCTAssertEqual(try Data(contentsOf: f.source), bytes)
        let loaded = try await store.load(from: f.destination, primaryURL: f.primary, secondaryURL: f.secondary)
        XCTAssertEqual(loaded, migration.migrated)
        XCTAssertEqual(try Data(contentsOf: f.primary), Data("A media".utf8))
        XCTAssertEqual(try Data(contentsOf: f.secondary), Data("B media".utf8))
    }

    func testChangedReviewAndReplacedMediaRejectConfirmation() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let migration = try f.proposal()
        var document = f.document
        document.notes[0].text = "Changed in another window"
        try f.write(document)
        do {
            _ = try await CompareReviewSidecarStore().migrateTimebases(
                from: f.source, to: f.destination, expectedMigration: migration)
            XCTFail("A changed review must not be migrated")
        } catch CompareReviewTimebaseMigrationError.previewChanged {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
        for replacePrimary in [false, true] {
            let replacementFixture = try ReviewTimebaseMigrationFixture()
            defer { replacementFixture.remove() }
            let proposal = try replacementFixture.proposal()
            let source = replacePrimary ? replacementFixture.primary : replacementFixture.secondary
            try Data("Replacement source contents".utf8).write(to: source, options: .atomic)
            do {
                _ = try await CompareReviewSidecarStore().migrateTimebases(
                    from: replacementFixture.source, to: replacementFixture.destination, expectedMigration: proposal)
                XCTFail("A replaced source must invalidate confirmation")
            } catch CompareReviewTimebaseMigrationError.sourceChanged {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: replacementFixture.destination.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }

    func testLegacyPathOnlyIdentityStillDetectsReplacementAfterPreview() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.source)) as? [String: Any])
        json["schemaVersion"] = 1
        json["primarySource"] = ["canonicalPath": f.document.primarySource.canonicalPath]
        json["secondarySource"] = ["canonicalPath": f.document.secondarySource.canonicalPath]
        try JSONSerialization.data(withJSONObject: json).write(to: f.source)
        let store = CompareReviewSidecarStore()
        let original = try await store.previewRelink(from: f.source)
        let proposal = try f.proposal(document: original)
        XCTAssertEqual(proposal.original.schemaVersion, 1)
        XCTAssertEqual(proposal.migrated.schemaVersion, 2)
        XCTAssertNil(proposal.migrated.secondarySource.fileNumber)
        XCTAssertNotNil(proposal.secondarySource.fileNumber)
        try Data("Replacement source contents".utf8).write(to: f.secondary, options: .atomic)
        do {
            _ = try await store.migrateTimebases(from: f.source, to: f.destination, expectedMigration: proposal)
            XCTFail("Path-only legacy identities still require the previewed file")
        } catch CompareReviewTimebaseMigrationError.sourceChanged {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }

    func testExistingDestinationOriginalAndMediaAreNeverOverwritten() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let migration = try f.proposal()
        try Data("existing review".utf8).write(to: f.destination)
        for destination in [f.source, f.destination, f.primary, f.secondary] {
            let bytes = try Data(contentsOf: destination)
            do {
                _ = try await CompareReviewSidecarStore().migrateTimebases(
                    from: f.source, to: destination, expectedMigration: migration)
                XCTFail("Existing files must never be replaced")
            } catch CompareReviewTimebaseMigrationError.destinationExists {}
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
    }

    func testConcurrentMigrationCopiesAndDanglingSymlinkUseExclusivePublication() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let migration = try f.proposal()
        let source = f.source
        let destination = f.destination
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    do {
                        _ = try await CompareReviewSidecarStore().migrateTimebases(
                            from: source, to: destination, expectedMigration: migration)
                        return true
                    } catch { return false }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        XCTAssertEqual(successes, 1)
        let link = f.directory.appendingPathComponent("dangling.json")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing.json")
        do {
            _ = try await CompareReviewSidecarStore().migrateTimebases(
                from: source, to: link, expectedMigration: migration)
            XCTFail("Dangling links must not be replaced")
        } catch CompareReviewTimebaseMigrationError.destinationExists {}
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "missing.json")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).contains { $0.hasSuffix(".partial") })
    }

    func testCanceledMigrationPublishesNothing() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let migration = try f.proposal()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CompareReviewSidecarStore().migrateTimebases(
                from: f.source, to: f.destination, expectedMigration: migration)
        }
        do { _ = try await task.value; XCTFail("Canceled work must not publish") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }

    func testSourceIdentityMismatchDoesNotProduceProposal() throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let reversed = CompareReviewDocument(primaryURL: f.secondary, secondaryURL: f.primary, notes: f.document.notes)
        XCTAssertThrowsError(try f.proposal(document: reversed)) { error in
            guard case CompareReviewTimebaseMigrationError.sourceChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

@MainActor
struct ReviewTimebaseMigrationFixture {
    let directory: URL
    let primary: URL
    let secondary: URL
    let source: URL
    let destination: URL
    let document: CompareReviewDocument
    let rate: TimecodeRate

    init(decimal: Int = 29_970, exact: Int = 30_000) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        primary = directory.appendingPathComponent("A.mov")
        secondary = directory.appendingPathComponent("B.mov")
        try Data("A media".utf8).write(to: primary)
        try Data("B media".utf8).write(to: secondary)
        source = CompareReviewSidecarStore.sidecarURL(primaryURL: primary, secondaryURL: secondary)
        destination = directory.appendingPathComponent("migrated.json")
        rate = TimecodeRate(numerator: exact, denominator: 1_001)
        document = CompareReviewDocument(primaryURL: primary, secondaryURL: secondary, notes: [CompareReviewNote(
            primaryFrame: 100, primaryTime: 9, secondaryFrame: 120, secondaryTime: 8,
            primaryRateNumerator: Int64(decimal), primaryRateDenominator: 1_000,
            secondaryRateNumerator: Int64(decimal), secondaryRateDenominator: 1_000,
            text: "Historical finding\nSecond line", severity: .critical, category: .sync,
            status: .inProgress, primaryEndFrame: 200,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )])
        try write(document)
    }

    func proposal(document: CompareReviewDocument? = nil, durationA: Double = 60, durationB: Double = 60,
                  migratedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> CompareReviewTimebaseMigration {
        try CompareReviewTimebaseMigration(document: document ?? self.document,
            primaryURL: primary, secondaryURL: secondary, primaryRate: rate, secondaryRate: rate,
            primaryDuration: durationA, secondaryDuration: durationB, migratedAt: migratedAt)
    }

    func write(_ document: CompareReviewDocument) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(document).write(to: source)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func item(url: URL) -> MediaItem {
        let stream = MediaMetadata.VideoStream(codec: nil, codecLongName: nil, profile: nil,
            width: 1920, height: 1080, displayWidth: 1920, displayHeight: 1080,
            pixelFormat: nil, hasAlpha: false, pixelAspectRatio: nil, displayAspectRatio: nil,
            frameRate: MediaMetadata.FrameRate(frameRateString: "\(rate.numerator)/\(rate.denominator)"),
            bitDepth: nil, chromaSubsampling: nil, colorPrimaries: nil, colorTransfer: nil,
            colorSpace: nil, colorRange: nil, chromaLocation: nil, fieldOrder: nil, isInterlaced: nil,
            rotation: nil, maxCLL: nil, maxFALL: nil, masteringMaxLuminance: nil, masteringMinLuminance: nil)
        let metadata = MediaMetadata(duration: 60, formatName: "mov", containerLongName: nil,
            sizeBytes: nil, bitRate: nil, timecode: "01:00:00;00", comment: nil, encoder: nil,
            frameCount: nil, videoStreams: [stream], audioStreams: [], subtitleStreams: [], chapters: [])
        return MediaItem(url: url, name: url.lastPathComponent, size: 7, durationSeconds: 60, metadata: metadata)
    }
}
