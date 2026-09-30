// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ProductionMetadataMemoryPerformanceTests: XCTestCase {
    /// Opt-in, one-input-per-process profiling of the shipping MetadataService path.
    /// The runner starts a fresh XCTest host for every input so lifetime peak RSS
    /// belongs to one uncached metadata load rather than a preceding fixture.
    func testProductionMetadataMemoryProfileWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["METADATA_MEMORY_PROFILE_INPUT"] else {
            throw XCTSkip("Set METADATA_MEMORY_PROFILE_INPUT to run the production metadata-memory profile")
        }
        let inputIndex = try XCTUnwrap(Int(environment["METADATA_MEMORY_PROFILE_INPUT_INDEX"] ?? ""))
        let url = URL(fileURLWithPath: path)
        let inputBytes = try fileSize(url)

        let initial = try memoryObservation()
        var sampledPeak = initial.currentResidentBytes
        var sampleCount = 1
        var outcome: Result<MediaMetadata, Error>?
        let loadStart = ContinuousClock.now
        let worker = Task { @MainActor in
            do {
                outcome = .success(try await MetadataService.shared.metadata(for: url))
            } catch {
                outcome = .failure(error)
            }
        }
        defer { worker.cancel() }

        let deadline = loadStart.advanced(by: .seconds(1_800))
        while outcome == nil, ContinuousClock.now < deadline {
            sampledPeak = max(sampledPeak, try memoryObservation().currentResidentBytes)
            sampleCount += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let completedOutcome = outcome else {
            worker.cancel()
            await worker.value
            XCTFail("Metadata load exceeded 30 minutes")
            return
        }

        var loadedMetadata: MediaMetadata? = try completedOutcome.get()
        outcome = nil
        await worker.value
        let loadWallSeconds = seconds(from: loadStart.duration(to: .now))
        let afterLoad = try memoryObservation()
        sampledPeak = max(sampledPeak, afterLoad.currentResidentBytes)

        let cachedStart = ContinuousClock.now
        var cachedMetadata: MediaMetadata? = try await MetadataService.shared.metadata(for: url)
        let cachedWallSeconds = seconds(from: cachedStart.duration(to: .now))
        let afterCachedRead = try memoryObservation()
        let cacheParity = loadedMetadata == cachedMetadata
        let snapshot = try XCTUnwrap(loadedMetadata).profileSnapshot

        // Drop both caller-owned values. MetadataService intentionally retains its
        // lightweight app model in NSCache; the dependency's source data should
        // already have been released during conversion in loadMetadata(for:).
        loadedMetadata = nil
        cachedMetadata = nil
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        let afterLocalRelease = try memoryObservation()

        let report: [String: Any] = [
            "inputIndex": inputIndex,
            "processIdentifier": Int(getpid()),
            "file": url.lastPathComponent,
            "inputFileBytes": inputBytes,
            "sampleIntervalMilliseconds": 10,
            "sampleCount": sampleCount,
            "loadWallSeconds": loadWallSeconds,
            "cachedReadWallSeconds": cachedWallSeconds,
            "cacheParity": cacheParity,
            "initialResidentBytes": initial.currentResidentBytes,
            "initialLifetimePeakResidentBytes": initial.lifetimePeakResidentBytes,
            "sampledPeakResidentBytes": sampledPeak,
            "afterLoadResidentBytes": afterLoad.currentResidentBytes,
            "afterLoadLifetimePeakResidentBytes": afterLoad.lifetimePeakResidentBytes,
            "afterCachedReadResidentBytes": afterCachedRead.currentResidentBytes,
            "afterCachedReadLifetimePeakResidentBytes": afterCachedRead.lifetimePeakResidentBytes,
            "afterLocalReleaseResidentBytes": afterLocalRelease.currentResidentBytes,
            "afterLocalReleaseLifetimePeakResidentBytes": afterLocalRelease.lifetimePeakResidentBytes,
            "metadata": snapshot,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let line = "PRODUCTION_METADATA_MEMORY_PROFILE " + String(decoding: data, as: UTF8.self)
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "Production metadata memory — \(inputIndex) — \(url.lastPathComponent)"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(cacheParity)
        XCTAssertGreaterThanOrEqual(afterLoad.lifetimePeakResidentBytes, initial.lifetimePeakResidentBytes)
        XCTAssertGreaterThanOrEqual(sampledPeak, initial.currentResidentBytes)
    }

    /// Distinct URLs force real shared-cache misses without duplicating large
    /// media files. Aliasing the parent directory preserves adjacent sidecars.
    func testProductionMetadataRepeatedImportProfileWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["METADATA_MEMORY_PROFILE_INPUT"],
              let countText = environment["METADATA_MEMORY_PROFILE_REIMPORT_COUNT"] else {
            throw XCTSkip("Set METADATA_MEMORY_PROFILE_INPUT and METADATA_MEMORY_PROFILE_REIMPORT_COUNT to profile repeated imports")
        }
        let count = try XCTUnwrap(Int(countText))
        guard (2...1_000).contains(count) else {
            throw NSError(domain: "ProductionMetadataReimportProfileInput", code: 1)
        }
        let inputIndex = try XCTUnwrap(Int(environment["METADATA_MEMORY_PROFILE_INPUT_INDEX"] ?? ""))
        let source = URL(fileURLWithPath: path)
        let inputBytes = try fileSize(source)
        let aliases = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductionMetadataReimport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: aliases, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliases) }

        let initial = try memoryObservation()
        let initialDescriptors = try openDescriptorCount()
        var baseline: MediaMetadata?
        var imports: [[String: Any]] = []
        for index in 0..<count {
            let directory = aliases.appendingPathComponent("import-\(index)", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: source.deletingLastPathComponent())
            let url = directory.appendingPathComponent(source.lastPathComponent)
            let beforeLoad = try memoryObservation()
            var sampledPeak = beforeLoad.currentResidentBytes
            var samples = 1
            var outcome: Result<MediaMetadata, Error>?
            let started = ContinuousClock.now
            let worker = Task { @MainActor in
                do { outcome = .success(try await MetadataService.shared.metadata(for: url)) }
                catch { outcome = .failure(error) }
            }
            defer { worker.cancel() }
            let deadline = started.advanced(by: .seconds(1_800))
            while outcome == nil, ContinuousClock.now < deadline {
                sampledPeak = max(sampledPeak, try memoryObservation().currentResidentBytes)
                samples += 1
                try await Task.sleep(for: .milliseconds(10))
            }
            guard outcome != nil else {
                worker.cancel()
                await worker.value
                XCTFail("Repeated metadata import exceeded 30 minutes")
                return
            }
            var loaded: MediaMetadata? = try outcome?.get()
            outcome = nil
            await worker.value
            let loadSeconds = seconds(from: started.duration(to: .now))
            let afterLoad = try memoryObservation()
            sampledPeak = max(sampledPeak, afterLoad.currentResidentBytes)
            if baseline == nil { baseline = loaded }
            let baselineParity = loaded == baseline
            let cachedStarted = ContinuousClock.now
            var cached: MediaMetadata? = try await MetadataService.shared.metadata(for: url)
            let cachedSeconds = seconds(from: cachedStarted.duration(to: .now))
            let cacheParity = cached == loaded
            loaded = nil
            cached = nil
            await Task.yield()
            try await Task.sleep(for: .milliseconds(100))
            let released = try memoryObservation()
            imports.append([
                "importIndex": index, "sampleCount": samples,
                "loadWallSeconds": loadSeconds, "cachedReadWallSeconds": cachedSeconds,
                "cacheParity": cacheParity, "baselineParity": baselineParity,
                "beforeLoadResidentBytes": beforeLoad.currentResidentBytes,
                "sampledPeakResidentBytes": sampledPeak,
                "afterLoadResidentBytes": afterLoad.currentResidentBytes,
                "afterLoadLifetimePeakResidentBytes": afterLoad.lifetimePeakResidentBytes,
                "afterLocalReleaseResidentBytes": released.currentResidentBytes,
                "afterLocalReleaseLifetimePeakResidentBytes": released.lifetimePeakResidentBytes,
                "afterLocalReleaseOpenDescriptors": try openDescriptorCount(),
            ])
            XCTAssertTrue(cacheParity, "Cached app model changed on import \(index)")
            XCTAssertTrue(baselineParity, "App model changed through a directory alias on import \(index)")
        }

        // Revisit the earliest URL after all later imports. This observes the
        // shared cache's returned model without assuming NSCache never evicts.
        let firstURL = aliases.appendingPathComponent("import-0", isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
        let revisitStarted = ContinuousClock.now
        var revisited: MediaMetadata? = try await MetadataService.shared.metadata(for: firstURL)
        let revisitSeconds = seconds(from: revisitStarted.duration(to: .now))
        let revisitParity = revisited == baseline
        revisited = nil
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        let afterRevisit = try memoryObservation()
        let report: [String: Any] = [
            "inputIndex": inputIndex, "processIdentifier": Int(getpid()),
            "file": source.lastPathComponent, "inputFileBytes": inputBytes,
            "importCount": count, "sampleIntervalMilliseconds": 10,
            "inputStrategy": "distinctDirectorySymlinkURLsPreservingSidecars",
            "initialResidentBytes": initial.currentResidentBytes,
            "initialLifetimePeakResidentBytes": initial.lifetimePeakResidentBytes,
            "initialOpenDescriptors": initialDescriptors,
            "revisitWallSeconds": revisitSeconds, "revisitParity": revisitParity,
            "afterRevisitResidentBytes": afterRevisit.currentResidentBytes,
            "afterRevisitLifetimePeakResidentBytes": afterRevisit.lifetimePeakResidentBytes,
            "afterRevisitOpenDescriptors": try openDescriptorCount(),
            "metadata": try XCTUnwrap(baseline).profileSnapshot, "imports": imports,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let line = "PRODUCTION_METADATA_REIMPORT_PROFILE " + String(decoding: data, as: UTF8.self)
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "Production metadata reimports — \(inputIndex) — \(source.lastPathComponent)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(revisitParity)
    }

    private func openDescriptorCount() throws -> Int {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let required = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        guard required > 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        // Spare capacity tolerates incidental host descriptors opened between
        // the size query and read. A full buffer is never accepted as complete.
        var capacity = Int(required) / stride + 32
        for _ in 0..<3 {
            var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
            let bytes = descriptors.withUnsafeMutableBytes {
                proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
            }
            guard bytes > 0, Int(bytes) % stride == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            if Int(bytes) < capacity * stride { return Int(bytes) / stride }
            capacity *= 2
        }
        throw NSError(domain: "ProductionMetadataDescriptorObservation", code: 1)
    }

    private struct MemoryObservation {
        let currentResidentBytes: UInt64
        let lifetimePeakResidentBytes: UInt64
    }

    private func memoryObservation() throws -> MemoryObservation {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(status))
        }
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return MemoryObservation(
            currentResidentBytes: UInt64(info.resident_size),
            lifetimePeakResidentBytes: UInt64(usage.ru_maxrss)
        )
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw NSError(domain: "ProductionMetadataMemoryProfileInput", code: 1)
        }
        return UInt64(size)
    }

    private func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

private extension MediaMetadata {
    var profileSnapshot: [String: Any] {
        [
            "durationSeconds": duration.map { $0 as Any } ?? NSNull(),
            "formatName": formatName.map { $0 as Any } ?? NSNull(),
            "sizeBytes": sizeBytes.map { $0 as Any } ?? NSNull(),
            "bitRate": bitRate.map { $0 as Any } ?? NSNull(),
            "videoStreamCount": videoStreams.count,
            "audioStreamCount": audioStreams.count,
            "subtitleStreamCount": subtitleStreams.count,
            "chapterCount": chapters.count,
            "videoStreams": videoStreams.map { stream in
                [
                    "codec": stream.codec.map { $0 as Any } ?? NSNull(),
                    "width": stream.width.map { $0 as Any } ?? NSNull(),
                    "height": stream.height.map { $0 as Any } ?? NSNull(),
                    "frameRateNumerator": stream.frameRate.map(\.numerator) as Any? ?? NSNull(),
                    "frameRateDenominator": stream.frameRate.map(\.denominator) as Any? ?? NSNull(),
                ]
            },
            "audioStreams": audioStreams.map { stream in
                [
                    "codec": stream.codec.map { $0 as Any } ?? NSNull(),
                    "sampleRate": stream.sampleRate.map { $0 as Any } ?? NSNull(),
                    "channels": stream.channels.map { $0 as Any } ?? NSNull(),
                    "bitDepth": stream.bitDepth.map { $0 as Any } ?? NSNull(),
                    "channelLayout": stream.channelLayout.map { $0 as Any } ?? NSNull(),
                ]
            },
        ]
    }
}
