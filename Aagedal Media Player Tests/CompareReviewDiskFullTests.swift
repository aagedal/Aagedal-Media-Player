// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import Darwin
@testable import Aagedal_Media_Player

/// Opt-in integration coverage. Run through scripts/test-compare-review-disk-full.sh.
/// Ordinary test runs skip this test; no user/host volume is ever filled.
final class CompareReviewDiskFullTests: XCTestCase {
    func testRealVolumeExhaustionPreservesSidecarAndAllowsRetry() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["AAGEDAL_DISK_FULL_MOUNT"],
              let token = environment["AAGEDAL_DISK_FULL_TOKEN"],
              let expectedFilesystem = environment["AAGEDAL_DISK_FULL_FILESYSTEM"] else {
            throw XCTSkip("Requires the disposable disk-image harness")
        }
        // Foundation's resolvingSymlinksInPath rewrites /private/tmp to /tmp
        // on macOS. POSIX realpath preserves the actual mount spelling used by
        // statfs and still rejects symlinked/aliased input paths.
        guard let canonicalBuffer = realpath(path, nil) else {
            return XCTFail("Cannot resolve disk-full fixture: \(path), errno=\(errno)")
        }
        let canonicalPath = String(cString: canonicalBuffer)
        free(canonicalBuffer)
        let mount = URL(fileURLWithPath: canonicalPath)
        let parent = mount.deletingLastPathComponent()
        guard canonicalPath == path,
              mount.lastPathComponent == "mount",
              parent.deletingLastPathComponent().path == "/private/tmp",
              parent.lastPathComponent.hasPrefix("aagedal-disk-full."),
              UUID(uuidString: token) != nil,
              try String(contentsOf: mount.appendingPathComponent(".aagedal-disk-full-token"), encoding: .utf8) == token
        else { return XCTFail("Refusing an unrecognized disk-full fixture: input=\(path), canonical=\(canonicalPath), parent=\(parent.path), validToken=\(UUID(uuidString: token) != nil)") }
        var filesystem = statfs()
        guard statfs(path, &filesystem) == 0 else { throw POSIXError(.EIO) }
        let mountName = withUnsafePointer(to: &filesystem.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let filesystemName = withUnsafePointer(to: &filesystem.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
        let deviceName = withUnsafePointer(to: &filesystem.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        // APFS needs a larger minimum container than the HFS+ fixture. Both
        // allowlists remain fixed; caller-supplied sizes cannot relax the bounds.
        let maximumBytes: UInt64
        switch expectedFilesystem {
        case "hfs": maximumBytes = 40 * 1024 * 1024
        case "apfs": maximumBytes = 136 * 1024 * 1024
        default: return XCTFail("Unrecognized fixture filesystem")
        }
        let capacity = UInt64(filesystem.f_blocks) * UInt64(filesystem.f_bsize)
        guard mountName == path, filesystemName == expectedFilesystem, deviceName.hasPrefix("/dev/disk"),
              capacity >= 8 * 1024 * 1024, capacity <= maximumBytes
        else { return XCTFail("Refusing to fill a filesystem other than the bounded test image: mount=\(mountName), expected=\(path), type=\(filesystemName), device=\(deviceName), capacity=\(capacity)") }

        func logFreeSpace(_ phase: String) {
            var state = statfs()
            if statfs(path, &state) == 0 {
                print("Disk-full phase: \(phase); free=\(state.f_bfree), available=\(state.f_bavail), blockSize=\(state.f_bsize)")
            }
        }
        logFreeSpace("validated empty image")
        let fileManager = FileManager.default
        let directory = mount.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: directory) }
        let primary = directory.appendingPathComponent("A.mov")
        let secondary = directory.appendingPathComponent("B.mov")
        let media = Data("Source media must remain untouched".utf8)
        try media.write(to: primary)
        try media.write(to: secondary)
        let sidecar = CompareReviewSidecarStore.sidecarURL(primaryURL: primary, secondaryURL: secondary)
        let note = CompareReviewNote(primaryFrame: 0, primaryTime: 0,
            secondaryFrame: 0, secondaryTime: 0, text: "Original",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001))
        var document = CompareReviewDocument(primaryURL: primary, secondaryURL: secondary, notes: [note])
        let store = CompareReviewSidecarStore()
        try await store.save(document, to: sidecar, revision: 1)
        let original = try Data(contentsOf: sidecar)
        // Exclusive publication has a different temporary-file/rename path
        // from ordinary edits. Keep its reviewed source unchanged throughout
        // exhaustion and retry, and require enough data to defeat metadata reserves.
        let publicationSource = directory.appendingPathComponent("historical.json")
        let relinkDestination = directory.appendingPathComponent("relinked.json")
        let migrationDestination = directory.appendingPathComponent("migrated.json")
        let historicalNote = CompareReviewNote(primaryFrame: 0, primaryTime: 0,
            secondaryFrame: 0, secondaryTime: 0,
            primaryRateNumerator: 29_970, primaryRateDenominator: 1_000,
            secondaryRateNumerator: 29_970, secondaryRateDenominator: 1_000,
            text: String(repeating: "Historical finding ", count: 16_384),
            createdAt: note.createdAt, updatedAt: note.updatedAt)
        let historical = CompareReviewDocument(primaryURL: primary, secondaryURL: secondary,
            notes: [historicalNote])
        try await store.save(historical, to: publicationSource, revision: 1)
        let publicationBytes = try Data(contentsOf: publicationSource)
        let reviewed = try await store.previewRelink(from: publicationSource)
        let exactRate = TimecodeRate(numerator: 30_000, denominator: 1_001)
        let migration = try CompareReviewTimebaseMigration(document: reviewed,
            primaryURL: primary, secondaryURL: secondary,
            primaryRate: exactRate, secondaryRate: exactRate,
            primaryDuration: 60, secondaryDuration: 60,
            migratedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let originalEntries = try fileManager.contentsOfDirectory(atPath: directory.path).sorted()
        let filler = directory.appendingPathComponent("filler")
        let descriptor = open(filler.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var reachedENOSPC = false
        // Fixed upper bound even if the mount validation were ever to regress.
        // Small blocks consume the final allocation units without sparse writes.
        let block = [UInt8](repeating: 0x61, count: 4096)
        for _ in 0..<Int(maximumBytes / UInt64(block.count)) {
            let count = block.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!, $0.count) }
            if count < 0 {
                let failure = errno
                close(descriptor)
                guard failure == ENOSPC else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
                reachedENOSPC = true
                break
            }
        }
        if !reachedENOSPC { close(descriptor) }
        logFreeSpace("filler reached exhaustion")
        guard reachedENOSPC else { return XCTFail("Bounded filler did not reach ENOSPC") }
        // Ensure replacement requires new allocation even if metadata reserves
        // leave a handful of blocks available to Foundation's atomic writer.
        document.notes[0].text = String(repeating: "Recovered edit ", count: 16_384)
        do {
            try await store.save(document, to: sidecar, revision: 99)
            XCTFail("Full test volume must reject production atomic replacement")
        } catch {
            let failure = error as NSError
            XCTAssertTrue(
                (failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.Code.fileWriteOutOfSpace.rawValue) ||
                (failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC)),
                "Expected ENOSPC/out-of-space, received \(failure)"
            )
        }
        XCTAssertEqual(try Data(contentsOf: sidecar), original)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path).sorted(),
            (originalEntries + ["filler"]).sorted())
        do {
            _ = try await store.apply(.delete(note.id), to: sidecar,
                primaryURL: primary, secondaryURL: secondary)
            XCTFail("Full test volume must reject atomic deletion")
        } catch {
            let failure = error as NSError
            XCTAssertTrue(
                (failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.Code.fileWriteOutOfSpace.rawValue) ||
                (failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC)),
                "Expected ENOSPC/out-of-space, received \(failure)"
            )
        }
        XCTAssertEqual(try Data(contentsOf: sidecar), original)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path).sorted(),
            (originalEntries + ["filler"]).sorted())
        for migrate in [false, true] {
            do {
                if migrate {
                    _ = try await store.migrateTimebases(from: publicationSource,
                        to: migrationDestination, expectedMigration: migration)
                } else {
                    _ = try await store.relink(from: publicationSource, to: relinkDestination,
                        primaryURL: secondary, secondaryURL: primary, expectedDocument: reviewed)
                }
                XCTFail("Full test volume must reject exclusive \(migrate ? "migration" : "relink") publication")
            } catch {
                let failure = error as NSError
                XCTAssertTrue(
                    (failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.Code.fileWriteOutOfSpace.rawValue) ||
                    (failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC)),
                    "Expected ENOSPC/out-of-space, received \(failure)"
                )
            }
            XCTAssertEqual(try Data(contentsOf: publicationSource), publicationBytes)
            XCTAssertEqual(try Data(contentsOf: sidecar), original)
            XCTAssertEqual(try Data(contentsOf: primary), media)
            XCTAssertEqual(try Data(contentsOf: secondary), media)
            XCTAssertFalse(fileManager.fileExists(atPath: relinkDestination.path))
            XCTAssertFalse(fileManager.fileExists(atPath: migrationDestination.path))
            XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path).sorted(),
                (originalEntries + ["filler"]).sorted(), "Failed publication must remove every partial file")
        }
        logFreeSpace("before releasing filler")
        // Explicitly release and synchronize the filler allocation before
        // retrying. Filesystems can defer reclamation when a large file is unlinked.
        let releaseDescriptor = open(filler.path, O_WRONLY | O_NOFOLLOW)
        guard releaseDescriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let truncateResult = ftruncate(releaseDescriptor, 0)
        let truncateError = errno
        let synchronizeResult = fsync(releaseDescriptor)
        let synchronizeError = errno
        close(releaseDescriptor)
        guard truncateResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: truncateError) ?? .EIO) }
        guard synchronizeResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: synchronizeError) ?? .EIO) }
        try fileManager.removeItem(at: filler)
        logFreeSpace("after removing filler")
        var recoveredSpace = statfs()
        for _ in 0..<20 {
            guard statfs(path, &recoveredSpace) == 0 else { throw POSIXError(.EIO) }
            if UInt64(recoveredSpace.f_bavail) * UInt64(recoveredSpace.f_bsize) >= 1024 * 1024 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard UInt64(recoveredSpace.f_bavail) * UInt64(recoveredSpace.f_bsize) >= 1024 * 1024 else {
            return XCTFail("Owned filler allocation was not reclaimed within one second")
        }
        // Failed revision 99 must not suppress the valid revision 2 retry.
        print("Disk-full phase: retry save")
        try await store.save(document, to: sidecar, revision: 2)
        let recovered = try await store.load(from: sidecar, primaryURL: primary, secondaryURL: secondary)
        XCTAssertEqual(recovered, document)
        let deleted = try await store.apply(.delete(note.id), to: sidecar,
            primaryURL: primary, secondaryURL: secondary)
        XCTAssertTrue(deleted.notes.isEmpty)
        let persistedDeletion = try await store.load(from: sidecar,
            primaryURL: primary, secondaryURL: secondary)
        XCTAssertEqual(persistedDeletion, deleted)
        XCTAssertEqual(try Data(contentsOf: primary), media)
        XCTAssertEqual(try Data(contentsOf: secondary), media)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path).sorted(), originalEntries)
        // Retry the exact reviewed proposals and destinations after releasing
        // space. Failed publication must not leave a destination collision.
        let relinked = try await store.relink(from: publicationSource, to: relinkDestination,
            primaryURL: secondary, secondaryURL: primary, expectedDocument: reviewed)
        let reopenedRelink = try await store.load(from: relinkDestination,
            primaryURL: secondary, secondaryURL: primary)
        XCTAssertEqual(reopenedRelink, relinked)
        XCTAssertEqual(relinked.notes, reviewed.notes)
        let migrated = try await store.migrateTimebases(from: publicationSource,
            to: migrationDestination, expectedMigration: migration)
        let reopenedMigration = try await store.load(from: migrationDestination,
            primaryURL: primary, secondaryURL: secondary)
        XCTAssertEqual(migrated, migration.migrated)
        XCTAssertEqual(reopenedMigration, migration.migrated)
        XCTAssertEqual(try Data(contentsOf: publicationSource), publicationBytes)
        XCTAssertEqual(try Data(contentsOf: primary), media)
        XCTAssertEqual(try Data(contentsOf: secondary), media)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path).sorted(),
            (originalEntries + [relinkDestination.lastPathComponent, migrationDestination.lastPathComponent]).sorted())
        // The harness also requires xcodebuild success, so failed assertions
        // cannot produce a successful run merely by reaching this proof write.
        print("Disk-full phase: completion proof")
        try Data(token.utf8).write(to: mount.appendingPathComponent(".aagedal-disk-full-verified"), options: .atomic)
    }
}
