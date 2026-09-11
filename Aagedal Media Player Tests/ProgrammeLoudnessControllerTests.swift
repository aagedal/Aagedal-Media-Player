// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ProgrammeLoudnessControllerTests: XCTestCase {
    func testDefaultAssignmentsUseMonoAudioOrdinalsAndRejectDuplicates() {
        let controller = ProgrammeLoudnessController()
        var streams = monoStreams(count: 8)
        streams.insert(stream(index: 42, channels: 2), at: 1)
        controller.configure(url: sourceURL, audioStreams: streams)
        XCTAssertEqual(controller.mapping?.audioStreamIndices, [0, 2])
        XCTAssertNil(controller.mappingError)
        controller.assignStream(0, toChannel: 1)
        XCTAssertNotNil(controller.mappingError)
        controller.assignStream(1, toChannel: 1)
        XCTAssertEqual(controller.mapping?.audioStreamIndices, [0, 0], "A stereo stream is not a mono programme channel.")
        controller.selectLayout(.surround5Point1)
        XCTAssertEqual(controller.mapping?.audioStreamIndices, [0, 2, 3, 4, 5, 6])
        XCTAssertNil(controller.mappingError)
        controller.configure(url: sourceURL, audioStreams: monoStreams(count: 2))
        controller.selectLayout(.surround5Point1)
        XCTAssertEqual(controller.mapping?.audioStreamIndices, [0, 1, -1, -1, -1, -1])
        XCTAssertNotNil(controller.mappingError)
    }

    func testCancellationAndRetryRejectLateResultsWithoutClearingCurrentWork() async throws {
        let probe = SuspendedProgrammeAnalysis()
        let controller = makeController(probe)
        controller.configure(url: sourceURL, audioStreams: monoStreams(count: 8))
        controller.measure(duration: 12, range: nil)
        await waitForCalls(1, probe: probe)
        controller.cancel(resetResult: false)
        XCTAssertFalse(controller.isAnalyzing)
        controller.measure(duration: 12, range: nil)
        await waitForCalls(2, probe: probe)
        probe.complete(0, loudness: -12)
        await settle()
        XCTAssertTrue(controller.isAnalyzing)
        XCTAssertNil(controller.result)
        probe.complete(1, loudness: -23)
        await settle()
        XCTAssertFalse(controller.isAnalyzing)
        XCTAssertEqual(controller.result?.loudness.integratedLoudness, -23)
        XCTAssertNil(controller.error)
        controller.cancel(resetResult: false)
        controller.configure(url: sourceURL, audioStreams: monoStreams(count: 8))
        XCTAssertEqual(controller.result?.loudness.integratedLoudness, -23, "Reopening the same inspector retains a completed measurement.")
    }

    func testMappingChangesInvalidateAnalysisAndCompletedMeasurements() async {
        let probe = SuspendedProgrammeAnalysis()
        let controller = makeController(probe)
        controller.configure(url: sourceURL, audioStreams: monoStreams(count: 8))
        controller.measure(duration: 12, range: nil)
        await waitForCalls(1, probe: probe)
        controller.selectLayout(.surround5Point1)
        probe.complete(0, loudness: -23)
        await settle()
        XCTAssertNil(controller.result)
        XCTAssertFalse(controller.isAnalyzing)
        controller.measure(duration: 12, range: nil)
        await waitForCalls(2, probe: probe)
        probe.complete(1, loudness: -20)
        await settle()
        XCTAssertEqual(controller.result?.mapping.layout, .surround5Point1)
        controller.assignStream(7, toChannel: 0)
        XCTAssertNil(controller.result)
        XCTAssertNil(controller.error)
    }

    func testSourceReplacementRejectsLateFailureAndSameURLMetadataChangesResetMapping() async {
        let probe = SuspendedProgrammeAnalysis()
        let controller = makeController(probe)
        controller.configure(url: sourceURL, audioStreams: monoStreams(count: 8))
        controller.selectLayout(.surround5Point1)
        controller.measure(duration: 12, range: nil)
        await waitForCalls(1, probe: probe)
        let replacement = URL(fileURLWithPath: "/tmp/programme-replacement.mov")
        controller.configure(url: replacement, audioStreams: monoStreams(count: 2))
        probe.fail(0)
        await settle()
        XCTAssertEqual(controller.mapping?.layout, .stereo)
        XCTAssertNil(controller.error)
        XCTAssertNil(controller.result)
        controller.configure(url: replacement, audioStreams: [])
        XCTAssertNil(controller.mapping)
    }

    func testRangeChangesCancelAndRetryCarriesExactDurationAndRange() async throws {
        let probe = SuspendedProgrammeAnalysis()
        let controller = makeController(probe)
        let range = try FFmpegService.LoudnessRange(start: 2.125, end: 7.25)
        controller.configure(url: sourceURL, audioStreams: monoStreams(count: 8))
        controller.measure(duration: 12, range: nil)
        await waitForCalls(1, probe: probe)
        // The inspector routes shared scope/trim changes through this reset.
        controller.cancel(resetResult: true)
        controller.measure(duration: 12, range: range)
        await waitForCalls(2, probe: probe)
        XCTAssertEqual(probe.requests[1].url, sourceURL)
        XCTAssertEqual(probe.requests[1].duration, 12)
        XCTAssertEqual(probe.requests[1].range, range)
        probe.fail(0)
        probe.complete(1, loudness: -19)
        await settle()
        XCTAssertEqual(controller.result?.loudness.analysisRange, range)
        XCTAssertNil(controller.error)
    }

    func testFailureIsRetryableAndJSONSeparatesProgrammeFromIndividualTracks() async throws {
        let probe = SuspendedProgrammeAnalysis()
        let controller = makeController(probe)
        let streams = monoStreams(count: 8)
        controller.configure(url: sourceURL, audioStreams: streams)
        controller.measure(duration: 12, range: nil)
        await waitForCalls(1, probe: probe)
        probe.fail(0)
        await settle()
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.isAnalyzing)
        controller.measure(duration: 12, range: nil)
        await waitForCalls(2, probe: probe)
        XCTAssertNil(controller.error)
        probe.complete(1, loudness: -23)
        await settle()
        let metadata = MediaMetadata(
            duration: 12, formatName: nil, containerLongName: nil, sizeBytes: nil,
            bitRate: nil, timecode: nil, comment: nil, encoder: nil, frameCount: nil,
            videoStreams: [], audioStreams: streams, subtitleStreams: [], chapters: []
        )
        let track = FFmpegService.LUFSResult(integratedLoudness: -26, loudnessRange: 0, truePeak: -.infinity)
        let data = try MetadataInspectorView.metadataJSON(
            metadata: metadata, lufsResults: [0: track], programmeLoudness: controller.result
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let programme = try XCTUnwrap(json["programmeLoudness"] as? [String: Any])
        let mapping = try XCTUnwrap(programme["mapping"] as? [String: Any])
        XCTAssertEqual(mapping["audioStreamIndices"] as? [Int], [0, 1])
        XCTAssertEqual(mapping["layout"] as? String, ProgrammeLoudnessLayout.stereo.rawValue)
        let value = try XCTUnwrap(programme["loudness"] as? [String: Any])
        XCTAssertEqual(value["integratedLoudness"] as? Double, -23)
        let exportedTracks = try XCTUnwrap(json["audioStreams"] as? [[String: Any]])
        XCTAssertEqual((exportedTracks[0]["lufs"] as? [String: Any])?["integratedLoudness"] as? Double, -26)
        XCTAssertEqual((exportedTracks[0]["lufs"] as? [String: Any])?["truePeak"] as? String, "-Infinity")
        XCTAssertNil(exportedTracks[1]["lufs"])
    }

    private var sourceURL: URL { URL(fileURLWithPath: "/tmp/programme-source.mov") }

    private func makeController(_ probe: SuspendedProgrammeAnalysis) -> ProgrammeLoudnessController {
        ProgrammeLoudnessController { url, mapping, _, duration, range in
            try await probe.analyze(url: url, mapping: mapping, duration: duration, range: range)
        }
    }

    private func monoStreams(count: Int) -> [MediaMetadata.AudioStream] {
        (0..<count).map { stream(index: $0 + 10, channels: 1) }
    }

    private func stream(index: Int, channels: Int) -> MediaMetadata.AudioStream {
        MediaMetadata.AudioStream(
            index: index, languageCode: nil, title: nil, codec: "pcm_s24le", codecLongName: nil,
            profile: nil, sampleRate: 48_000, channels: channels, channelLayout: channels == 1 ? "mono" : "stereo",
            bitDepth: 24, bitRate: nil, isDefault: false
        )
    }

    private func waitForCalls(_ count: Int, probe: SuspendedProgrammeAnalysis) async {
        for _ in 0..<200 {
            if probe.requests.count >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Programme analysis did not start.")
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private final class SuspendedProgrammeAnalysis {
    struct Request {
        let url: URL
        let mapping: ProgrammeLoudnessMapping
        let duration: Double?
        let range: FFmpegService.LoudnessRange?
    }
    var requests: [Request] = []
    private var continuations: [Int: CheckedContinuation<ProgrammeLoudnessResult, Error>] = [:]

    func analyze(url: URL, mapping: ProgrammeLoudnessMapping, duration: Double?, range: FFmpegService.LoudnessRange?) async throws -> ProgrammeLoudnessResult {
        let index = requests.count
        requests.append(Request(url: url, mapping: mapping, duration: duration, range: range))
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func complete(_ index: Int, loudness: Double) {
        guard let continuation = continuations.removeValue(forKey: index) else { return }
        let request = requests[index]
        continuation.resume(returning: ProgrammeLoudnessResult(
            mapping: request.mapping,
            loudness: FFmpegService.LUFSResult(
                integratedLoudness: loudness, loudnessRange: 0, truePeak: -20, analysisRange: request.range
            )
        ))
    }

    func fail(_ index: Int) {
        continuations.removeValue(forKey: index)?.resume(throwing: FFmpegError.processFailed("Fixture decode failed"))
    }
}
