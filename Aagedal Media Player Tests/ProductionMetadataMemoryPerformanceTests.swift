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
        guard let path = environment["METADATA_MEMORY_PROFILE_INPUT"] else { return }
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
