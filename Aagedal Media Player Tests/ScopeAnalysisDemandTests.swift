// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ScopeAnalysisDemandTests: XCTestCase {
    func testPausedAVSourceRecapturesConsumedFrameWhenAnalysisResumes() async throws {
        let fixtureRoot = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"].map {
            URL(fileURLWithPath: $0)
        } ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Test Fixtures/Generated")
        let url = fixtureRoot.appending(path: "loupe/landscape.mp4")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Set MEDIA_FIXTURE_DIR to the generated media fixtures")
        }
        let oldResolution = UserDefaults.standard.object(forKey: AppSettings.scopeResolution.key)
        let oldRate = UserDefaults.standard.object(forKey: AppSettings.scopeFrameRate.key)
        UserDefaults.standard.set(64, forKey: AppSettings.scopeResolution.key)
        UserDefaults.standard.set(30.0, forKey: AppSettings.scopeFrameRate.key)
        defer {
            UserDefaults.standard.set(oldResolution, forKey: AppSettings.scopeResolution.key)
            UserDefaults.standard.set(oldRate, forKey: AppSettings.scopeFrameRate.key)
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        let capture = FrameCapture()
        capture.attachAVPlayer(player)
        capture.startCapture()
        defer {
            player.pause()
            capture.stopCapture(rebuildPipeline: false)
            capture.detachAVPlayer()
        }
        let output = try XCTUnwrap(item.outputs.first as? AVPlayerItemVideoOutput)
        player.play()
        for _ in 0..<300 where capture.currentSample == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(capture.currentSample, String(describing: item.error))
        player.pause()
        // Let the existing timer consume the final paused frame before testing
        // demand changes. No playback or seek occurs after this point.
        try await Task.sleep(for: .milliseconds(150))
        let pausedTime = player.currentTime()
        XCTAssertFalse(output.hasNewPixelBuffer(forItemTime: pausedTime))
        let original = try XCTUnwrap(capture.currentSample)
        let originalPixels = try XCTUnwrap(original.sdrFrame?.dataProvider?.data)

        capture.analysisRequested = false
        XCTAssertNil(capture.currentSample)
        capture.analysisRequested = true
        for _ in 0..<300 where capture.currentSample == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let resumed = try XCTUnwrap(capture.currentSample,
            "A consumed paused frame must be copied again even when hasNewPixelBuffer is false")
        XCTAssertGreaterThan(resumed.sequence, original.sequence)
        XCTAssertEqual(resumed.playbackTime, original.playbackTime)
        XCTAssertEqual(resumed.timestampQuality, .exact)
        let resumedPixels = try XCTUnwrap(resumed.sdrFrame?.dataProvider?.data)
        XCTAssertEqual(resumedPixels as Data, originalPixels as Data)
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(player.currentTime(), pausedTime)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(item.outputs.count, 1)
        XCTAssertTrue(item.outputs.first === output)

        let sequence = resumed.sequence
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(capture.currentSample?.sequence, sequence,
                       "The forced paused recapture is one-shot, not continuous repeated analysis")
        print("AV_SCOPE_DEMAND_ACCEPTANCE: paused consumed-frame recapture without seek or pipeline replacement")
    }

    func testSelectionRequestsOnlyTheNeededSources() {
        for source in CompareScopeSource.allCases {
            let single = ScopeAnalysisDemand(source: source, isComparing: false)
            XCTAssertTrue(single.primary)
            XCTAssertFalse(single.secondary)

            let comparison = ScopeAnalysisDemand(source: source, isComparing: true)
            XCTAssertEqual(comparison.primary, source != .secondary)
            XCTAssertEqual(comparison.secondary, source != .primary)
        }
    }

    func testSuspendingAndResumingRevokesOldTicksAndCompletionsWithoutStoppingSession() {
        let capture = FrameCapture()
        capture.startCapture()
        defer { capture.stopCapture() }
        let activeGeneration = capture.captureGeneration.current
        let activeTick = ScopeCaptureTickIdentity(generation: activeGeneration)
        let activeRequest = ScopeCaptureIdentity(generation: activeGeneration, player: nil)

        capture.analysisRequested = false
        let suspendedGeneration = capture.captureGeneration.current
        XCTAssertTrue(capture.isCapturing, "Comparison reload uses this as scope visibility intent")
        XCTAssertFalse(activeTick.matches(generation: suspendedGeneration, isCapturing: capture.isCapturing))
        XCTAssertFalse(activeRequest.matches(generation: suspendedGeneration, player: nil))
        XCTAssertNil(capture.currentSample)
        XCTAssertTrue(capture.recentSamplesSnapshot().isEmpty)

        capture.analysisRequested = false
        XCTAssertEqual(capture.captureGeneration.current, suspendedGeneration, "Unchanged demand must not restart capture")

        capture.analysisRequested = true
        let resumedGeneration = capture.captureGeneration.current
        XCTAssertTrue(capture.isCapturing)
        XCTAssertNotEqual(resumedGeneration, suspendedGeneration)
        XCTAssertFalse(activeRequest.matches(generation: resumedGeneration, player: nil))
        XCTAssertTrue(ScopeCaptureTickIdentity(generation: resumedGeneration)
            .matches(generation: resumedGeneration, isCapturing: capture.isCapturing))
    }

    func testSelectionRetainsAVOutputAndDoesNotRebuildPipeline() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let player = AVPlayer(playerItem: item)
        let capture = FrameCapture()
        var rebuilds = 0
        capture.onAVOutputRemoved = { rebuilds += 1 }
        capture.attachAVPlayer(player)
        capture.startCapture()
        defer {
            capture.stopCapture(rebuildPipeline: false)
            capture.detachAVPlayer()
        }
        let output = try XCTUnwrap(item.outputs.first)
        XCTAssertEqual(item.outputs.count, 1)
        for demand in [false, true, false, true] {
            capture.analysisRequested = demand
            XCTAssertTrue(capture.isCapturing)
            XCTAssertEqual(item.outputs.count, 1)
            XCTAssertTrue(item.outputs.first === output, "Source selection must retain the existing AV output")
        }
        // A deferred output-removal callback must not have been scheduled by
        // selection; normal teardown has its own separate rebuild behavior.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rebuilds, 0)
    }

    func testBackendReplacementPreservesSuspendedAnalysisAndCaptureIntent() {
        let firstItem = AVPlayerItem(asset: AVMutableComposition())
        let firstPlayer = AVPlayer(playerItem: firstItem)
        let capture = FrameCapture()
        capture.analysisRequested = false
        capture.attachAVPlayer(firstPlayer)
        capture.startCapture()
        XCTAssertTrue(capture.isCapturing)
        let obsolete = ScopeCaptureIdentity(generation: capture.captureGeneration.current, player: nil)

        // Match backend teardown/replacement while scopes remain visible.
        let wasCapturing = capture.isCapturing
        capture.stopCapture(rebuildPipeline: false)
        capture.detachAVPlayer()
        let replacementItem = AVPlayerItem(asset: AVMutableComposition())
        let replacement = AVPlayer(playerItem: replacementItem)
        capture.attachAVPlayer(replacement)
        if wasCapturing { capture.startCapture() }
        defer {
            capture.stopCapture(rebuildPipeline: false)
            capture.detachAVPlayer()
        }
        XCTAssertTrue(capture.isCapturing)
        XCTAssertFalse(capture.analysisRequested, "Backend readiness must not resurrect unselected analysis")
        XCTAssertTrue(firstItem.outputs.isEmpty)
        XCTAssertEqual(replacementItem.outputs.count, 1)
        XCTAssertFalse(obsolete.matches(generation: capture.captureGeneration.current, player: nil))

        capture.analysisRequested = true
        XCTAssertTrue(capture.isCapturing)
        XCTAssertTrue(capture.analysisRequested)
        XCTAssertEqual(replacementItem.outputs.count, 1)
    }
}
