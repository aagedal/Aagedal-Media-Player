// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ProgrammeLoudnessPerformanceTests: XCTestCase {
    /// Explicit inputs keep long-running decoder workloads out of regression runs.
    func testProductionProgrammeLoudnessProfileWhenRequested() async throws {
        guard let input = ProcessInfo.processInfo.environment["PROGRAMME_LOUDNESS_PROFILE_INPUTS"] else { return }
        let paths = try JSONDecoder().decode([String].self, from: Data(input.utf8))
        XCTAssertFalse(paths.isEmpty)
        for (inputIndex, path) in paths.enumerated() {
            let url = URL(fileURLWithPath: path)
            let metadata = try await MetadataService.shared.metadata(for: url)
            let duration = try XCTUnwrap(metadata.duration)
            XCTAssertTrue(duration.isFinite && duration >= 60)
            guard duration.isFinite && duration >= 60 else { continue }
            let monoIndices = metadata.audioStreams.indices.filter { metadata.audioStreams[$0].channels == 1 }
            XCTAssertGreaterThanOrEqual(monoIndices.count, 8, "Each input must contain at least eight mono tracks")
            guard monoIndices.count >= 8 else { continue }
            var measurements: [[String: Any]] = []
            for layout in ProgrammeLoudnessLayout.allCases {
                let mapping = ProgrammeLoudnessMapping(layout: layout,
                    audioStreamIndices: Array(monoIndices.prefix(layout.channelRoles.count)))
                try mapping.validate(audioStreams: metadata.audioStreams)
                let workloads: [(String, FFmpegService.LoudnessRange?)] = [
                    ("whole", nil),
                    ("early", try .init(start: 0, end: 30)),
                    ("late", try .init(start: duration - 30, end: duration)),
                ]
                for (scope, range) in workloads {
                    let initialResident = try residentBytes()
                    var peakResident = initialResident
                    var peakChildrenResident: UInt64 = 0
                    var outcome: Result<ProgrammeLoudnessResult, Error>?
                    let start = ContinuousClock.now
                    let worker = Task { @MainActor in
                        do {
                            outcome = .success(try await FFmpegService.analyzeProgrammeLUFS(
                                url: url, mapping: mapping, audioStreams: metadata.audioStreams,
                                duration: duration, range: range
                            ))
                        } catch { outcome = .failure(error) }
                    }
                    defer { worker.cancel() }
                    let deadline = start.advanced(by: .seconds(1_800))
                    while outcome == nil, ContinuousClock.now < deadline {
                        peakResident = max(peakResident, try residentBytes())
                        peakChildrenResident = max(peakChildrenResident, try childResidentBytes())
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    guard let outcome else {
                        worker.cancel()
                        await worker.value
                        XCTFail("Loudness profile exceeded 30 minutes for \(scope), layout \(layout.rawValue)")
                        return
                    }
                    let programme = try outcome.get()
                    XCTAssertEqual(programme.mapping, mapping)
                    let result = programme.loudness
                    let elapsed = start.duration(to: .now).components
                    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    XCTAssertEqual(result.analysisRange, range)
                    let selectedDuration = range.map { $0.end - $0.start } ?? duration
                    measurements.append([
                        "layout": layout.rawValue, "audioStreamIndices": mapping.audioStreamIndices,
                        "channelRoles": layout.channelRoles,
                        "scope": scope, "rangeStartSeconds": range?.start ?? 0,
                        "rangeEndSeconds": range?.end ?? duration,
                        "wallSeconds": seconds, "selectedAudioSecondsPerWallSecond": selectedDuration / seconds,
                        "initialResidentBytes": initialResident, "sampledPeakResidentBytes": peakResident,
                        "sampledPeakChildResidentBytes": peakChildrenResident,
                        // Strings preserve valid silence results without JSON infinities.
                        "integratedLUFS": String(result.integratedLoudness),
                        "loudnessRangeLU": String(result.loudnessRange), "truePeakDBTP": String(result.truePeak),
                    ])
                }
            }
            let report: [String: Any] = [
                "inputIndex": inputIndex, "file": url.lastPathComponent, "durationSeconds": duration,
                "audioStreams": metadata.audioStreams.enumerated().map { index, stream -> [String: Any] in
                    ["index": index, "channels": stream.channels ?? 0,
                     "sampleRate": stream.sampleRate ?? 0, "codec": stream.codec ?? "unknown"]
                }, "measurements": measurements,
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let line = "PROGRAMME_LOUDNESS_PROFILE " + String(decoding: data, as: UTF8.self)
            print(line)
            let attachment = XCTAttachment(string: line)
            attachment.name = "Programme loudness profile — \(inputIndex) — \(url.lastPathComponent)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// The isolated host's direct children are the production FFmpeg jobs.
    /// A child may exit between enumeration and inspection; skip that race.
    private func childResidentBytes() throws -> UInt64 {
        var pids = [pid_t](repeating: 0, count: 1_024)
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(getpid()), $0.baseAddress, capacity)
        }
        guard bytes >= 0, bytes < capacity else {
            throw NSError(domain: "LoudnessProfileChildEnumeration", code: Int(bytes))
        }
        var resident: UInt64 = 0
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size {
                resident += info.pti_resident_size
            }
        }
        return resident
    }

    private func residentBytes() throws -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw NSError(domain: NSMachErrorDomain, code: Int(result)) }
        return UInt64(info.resident_size)
    }
}
