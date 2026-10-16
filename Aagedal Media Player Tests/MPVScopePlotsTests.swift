// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import Foundation
import Libmpv
import XCTest
@testable import Aagedal_Media_Player

final class MPVScopePlotsTests: XCTestCase {
    @MainActor
    func testNativePlotsPublishImmediatelyAndSwitchModesWithoutRecomputation() throws {
        let plots = try XCTUnwrap(withNode { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) })
        let worker = ScopeRenderWorker()
        let input = ScopeFrameInput(sdrFrame: nil, hdrFrame: nil, transferFunction: .sdr,
                                   displayAspectRatio: nil, nativePlots: plots)

        for (index, mode) in WaveformMode.allCases.enumerated() {
            worker.submit(primary: input, secondary: nil, source: .primary,
                          differenceGain: 1, mode: mode, resolution: 64)
            XCTAssertEqual(worker.renderSequence, UInt64(index + 1), "Native results must publish within submit")
            XCTAssertTrue(worker.waveformImage === (mode == .luma ? plots.waveform : plots.parade))
            XCTAssertTrue(worker.vectorscopeImage === plots.vectorscope)
        }
        worker.submit(primary: input, secondary: input, source: .difference,
                      differenceGain: 1, mode: .luma, resolution: 64)
        XCTAssertEqual(worker.renderSequence, 2, "Difference scopes require display pixels, never source plots")
        XCTAssertNil(worker.waveformImage)
        XCTAssertNil(worker.vectorscopeImage)
        worker.cancel(clearImages: true)
        XCTAssertNil(worker.waveformImage)
        XCTAssertNil(worker.vectorscopeImage)
    }

    @MainActor
    func testNativeSecondaryPublishesItsHDRScaleBeforeRenderNotification() throws {
        let sdr = try XCTUnwrap(withNode { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) })
        let hdr = MPVScopePlots(waveform: sdr.waveform, parade: sdr.parade, vectorscope: sdr.vectorscope,
                               pts: 1, trackID: 2, transfer: "hlg", primaries: "bt2020", peakNits: 1000)
        let worker = ScopeRenderWorker()
        var notifiedPeak: Float?
        let observer = worker.$renderSequence.dropFirst().sink { _ in
            notifiedPeak = worker.hdrPeakNits
        }
        defer { observer.cancel() }
        worker.submit(
            primary: ScopeFrameInput(sdrFrame: nil, hdrFrame: nil, transferFunction: .sdr,
                                     displayAspectRatio: nil, nativePlots: sdr),
            secondary: ScopeFrameInput(sdrFrame: nil, hdrFrame: nil, transferFunction: .sdr,
                                       displayAspectRatio: nil, nativePlots: hdr),
            source: .secondary, differenceGain: 1, mode: .parade, resolution: 64
        )
        XCTAssertEqual(worker.renderSequence, 1)
        XCTAssertEqual(worker.hdrPeakNits, 1000, "Native metadata is authoritative even before controller metadata arrives")
        XCTAssertEqual(notifiedPeak, 1000)
        XCTAssertTrue(worker.waveformImage === hdr.parade)
    }

    @MainActor
    func testNativePublicationRevokesActiveAndPendingFallbackAndAllowsFallbackAgain() async throws {
        let plots = try XCTUnwrap(withNode { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) })
        let worker = ScopeRenderWorker()
        let fallback = ScopeFrameInput(sdrFrame: plots.waveform, hdrFrame: nil,
                                      transferFunction: .sdr, displayAspectRatio: nil)
        // No suspension here: the main actor cannot publish either fallback
        // completion before the native submission invalidates both generations.
        for _ in 0..<2 {
            worker.submit(primary: fallback, secondary: nil, source: .primary,
                          differenceGain: 1, mode: .luma, resolution: 64)
        }
        worker.submit(primary: ScopeFrameInput(sdrFrame: nil, hdrFrame: nil,
            transferFunction: .sdr, displayAspectRatio: nil, nativePlots: plots),
            secondary: nil, source: .primary, differenceGain: 1, mode: .parade, resolution: 64)
        XCTAssertEqual(worker.renderSequence, 1)
        XCTAssertTrue(worker.waveformImage === plots.parade)

        worker.submit(primary: fallback, secondary: nil, source: .primary,
                      differenceGain: 1, mode: .luma, resolution: 64)
        for _ in 0..<100 where worker.renderSequence == 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(worker.renderSequence, 2, "Cancelled fallback generations must not publish")
        XCTAssertNotNil(worker.waveformImage)
        XCTAssertFalse(worker.waveformImage === plots.parade)
        worker.cancel(clearImages: true)
        await Task.yield()
        XCTAssertNil(worker.waveformImage)
        XCTAssertNil(worker.vectorscopeImage)
        XCTAssertEqual(worker.renderSequence, 2)
    }

    func testAcceptsCompletePlotsAndCopiesNodeOwnedBytes() throws {
        let plots = try XCTUnwrap(withNode { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) })
        XCTAssertEqual(plots.waveform.width, 64)
        XCTAssertEqual(plots.parade.height, 36)
        XCTAssertEqual(plots.vectorscope.width, 36)
        XCTAssertEqual(plots.pts, 1)
        XCTAssertEqual(plots.transfer, "srgb")
        // withNode has freed every native payload. Read all three complete
        // providers now so a retained node pointer cannot pass on dimensions alone.
        for (image, byte) in [(plots.waveform, UInt8(0x31)), (plots.parade, 0x72),
                              (plots.vectorscope, 0xB4)] {
            let data = try XCTUnwrap(image.dataProvider?.data)
            XCTAssertEqual(data as Data, Data(repeating: byte, count: image.width * image.height * 4))
        }
    }

    func testRejectsMalformedMetadataAndPayloadBeforeCopy() {
        let keys = ["protocol", "w", "h", "track-id", "pts", "peak-nits", "primaries", "transfer", "format", "waveform", "parade", "vectorscope"]
        for key in keys {
            XCTAssertNil(withNode(omit: key) { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) }, key)
            XCTAssertNil(withNode(wrongType: key) { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) }, key)
            XCTAssertNil(withNode(duplicate: key) { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) }, key)
        }
        for time in [-1.0, .infinity, .nan] {
            XCTAssertNil(withNode(pts: time) { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) })
        }
        for width in [0, 63, 1441, Int.max] {
            XCTAssertNil(withNode { MPVScopePlots.decode($0, expectedWidth: width, trackID: 1) })
        }
        XCTAssertNil(withNode { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 2) })
        for size in [0, 4, Int.max] {
            XCTAssertNil(withNode(size: size) { MPVScopePlots.decode($0, expectedWidth: 64, trackID: 1) })
        }
    }

    private func withNode<T>(omit: String? = nil, wrongType: String? = nil, duplicate: String? = nil,
                             pts: Double = 1, size: Int? = nil, _ body: (mpv_node) -> T) -> T {
        let names: [String] = (["protocol", "w", "h", "track-id", "pts", "peak-nits", "primaries", "transfer", "format", "waveform", "parade", "vectorscope"].filter { $0 != omit }) + (duplicate.map { [$0] } ?? [])
        var strings: [UnsafeMutablePointer<CChar>] = []
        var arrays: [UnsafeMutablePointer<mpv_byte_array>] = []
        var buffers: [UnsafeMutableRawPointer] = []
        func text(_ s: String) -> UnsafeMutablePointer<CChar> {
            let p = strdup(s)!; strings.append(p); return p
        }
        defer {
            strings.forEach { free($0) }
            arrays.forEach { $0.deinitialize(count: 1); $0.deallocate() }
            buffers.forEach { $0.deallocate() }
        }
        var keys = names.map { Optional(text($0)) }
        var values = names.map { key in
            var n = mpv_node()
            if let value: Int64 = ["protocol": 1, "w": 64, "h": 36, "track-id": 1][key] {
                n.format = MPV_FORMAT_INT64; n.u.int64 = value
            } else if key == "pts" || key == "peak-nits" {
                n.format = MPV_FORMAT_DOUBLE; n.u.double_ = key == "pts" ? pts : 100
            } else if let s = ["primaries": "bt709", "transfer": "srgb", "format": "bgra-premultiplied"][key] {
                n.format = MPV_FORMAT_STRING; n.u.string = text(s)
            } else {
                let count = (key == "vectorscope" ? 36 : 64)*36*4
                let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 8)
                let pattern: UInt8 = ["waveform": 0x31, "parade": 0x72, "vectorscope": 0xB4][key]!
                bytes.initializeMemory(as: UInt8.self, repeating: pattern, count: count); buffers.append(bytes)
                let array = UnsafeMutablePointer<mpv_byte_array>.allocate(capacity: 1)
                array.initialize(to: mpv_byte_array(data: bytes, size: size ?? count)); arrays.append(array)
                n.format = MPV_FORMAT_BYTE_ARRAY; n.u.ba = array
            }
            if key == wrongType { n.format = MPV_FORMAT_NONE }
            return n
        }
        return keys.withUnsafeMutableBufferPointer { keys in
            values.withUnsafeMutableBufferPointer { values in
                var list = mpv_node_list(num: Int32(names.count), values: values.baseAddress, keys: keys.baseAddress)
                return withUnsafeMutablePointer(to: &list) { list in
                    var n = mpv_node(); n.format = MPV_FORMAT_NODE_MAP; n.u.list = list
                    return body(n)
                }
            }
        }
    }
}

@MainActor
final class MPVNativeScopeIntegrationTests: XCTestCase {
    func testSuspendedNativeAnalysisSurvivesBackendReplacementAndResumesFresh() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MPV_SCOPE_TEST_FIXTURES"] else {
            throw XCTSkip("Set MPV_SCOPE_TEST_FIXTURES for the arm64 native scope candidate")
        }
        let oldResolution = UserDefaults.standard.object(forKey: AppSettings.scopeResolution.key)
        let oldRate = UserDefaults.standard.object(forKey: AppSettings.scopeFrameRate.key)
        UserDefaults.standard.set(64, forKey: AppSettings.scopeResolution.key)
        UserDefaults.standard.set(30.0, forKey: AppSettings.scopeFrameRate.key)
        defer {
            UserDefaults.standard.set(oldResolution, forKey: AppSettings.scopeResolution.key)
            UserDefaults.standard.set(oldRate, forKey: AppSettings.scopeFrameRate.key)
        }

        let players = [MPVPlayer(), MPVPlayer()]
        let views = players.map { player in
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
            let layer = MPVMetalLayer()
            layer.frame = view.bounds
            layer.drawableSize = view.bounds.size
            view.layer = layer
            view.wantsLayer = true
            XCTAssertFalse(player.attachDrawable(layer))
            return view
        }
        let capture = FrameCapture()
        var disabledPublications = 0
        let observer = capture.$currentSample.sink { sample in
            if sample != nil, !capture.analysisRequested { disabledPublications += 1 }
        }
        defer {
            observer.cancel()
            capture.stopCapture()
            capture.detachMPV()
            players.forEach { $0.destroy() }
            withExtendedLifetime(views) {}
        }

        capture.attachMPV(players[0])
        players[0].load(url: URL(fileURLWithPath: directory).appendingPathComponent("sdr.mkv"))
        capture.startCapture()
        for _ in 0..<300 where capture.currentSample?.nativePlots == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let first = try XCTUnwrap(capture.currentSample)
        XCTAssertEqual(try XCTUnwrap(first.nativePlots).transfer, "srgb")

        capture.analysisRequested = false
        XCTAssertTrue(capture.isCapturing)
        XCTAssertNil(capture.currentSample)
        XCTAssertTrue(capture.recentSamplesSnapshot().isEmpty)
        // Several 30 Hz timer ticks must leave capture idle after revocation.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(capture.currentSample)
        XCTAssertEqual(disabledPublications, 0)

        // Preserve the same running intent across the production backend
        // teardown/attachment sequence, without re-enabling analysis.
        let wasCapturing = capture.isCapturing
        capture.stopCapture(rebuildPipeline: false)
        capture.detachMPV()
        players[0].destroy()
        capture.attachMPV(players[1])
        players[1].load(url: URL(fileURLWithPath: directory).appendingPathComponent("pq.mkv"))
        if wasCapturing { capture.startCapture() }
        for _ in 0..<300 where !players[1].isFileLoaded {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(players[1].isFileLoaded)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertFalse(capture.analysisRequested)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(capture.currentSample)
        XCTAssertEqual(disabledPublications, 0)

        capture.analysisRequested = true
        for _ in 0..<300 where capture.currentSample?.nativePlots == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let replacement = try XCTUnwrap(capture.currentSample)
        XCTAssertGreaterThan(replacement.sequence, first.sequence)
        XCTAssertEqual(try XCTUnwrap(replacement.nativePlots).transfer, "pq",
                       "Re-enabled analysis must come from the replacement source")
        XCTAssertEqual(replacement.timestampQuality, .exact)
        XCTAssertNil(replacement.sdrFrame)
        XCTAssertNil(replacement.hdrFrame)
        XCTAssertEqual(disabledPublications, 0)
        print("MPV_SCOPE_DEMAND_ACCEPTANCE: native suspension, backend replacement and fresh resume")
    }

    func testUHDLiveScopeThroughputAgainstScreenshotBackend() async throws {
        guard let path = ProcessInfo.processInfo.environment["MPV_SCOPE_PLAYBACK_FIXTURE"] else {
            throw XCTSkip("Set MPV_SCOPE_PLAYBACK_FIXTURE to the UHD 60 fps HLG fixture")
        }
        let oldResolution = UserDefaults.standard.object(forKey: AppSettings.scopeResolution.key)
        let oldRate = UserDefaults.standard.object(forKey: AppSettings.scopeFrameRate.key)
        UserDefaults.standard.set(720, forKey: AppSettings.scopeResolution.key)
        UserDefaults.standard.set(30.0, forKey: AppSettings.scopeFrameRate.key)
        defer {
            UserDefaults.standard.set(oldResolution, forKey: AppSettings.scopeResolution.key)
            UserDefaults.standard.set(oldRate, forKey: AppSettings.scopeFrameRate.key)
        }
        var rates: [Double] = []
        for native in [false, true] {
            let mpv = MPVPlayer()
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
            let layer = MPVMetalLayer(); layer.frame = view.bounds; layer.drawableSize = view.bounds.size
            view.layer = layer; view.wantsLayer = true
            XCTAssertFalse(mpv.attachDrawable(layer), "Initial attachment does not require a drawable replacement")
            mpv.setLooping(true)
            let capture = FrameCapture()
            capture.transferFunction = .hlg; capture.contentPeakNits = 1000
            capture.requiresDisplayFrame = !native
            capture.attachMPV(mpv)
            let worker = ScopeRenderWorker()
            var rendered = 0, captured = 0, wrongBackend = 0
            var times = Set<Double>()
            var measuring = false
            let sampleObserver = capture.$currentSample.sink { sample in
                guard let sample else { return }
                if measuring {
                    captured += 1
                    if (sample.nativePlots != nil) != native { wrongBackend += 1 }
                    if let time = sample.playbackTime { times.insert(time) }
                }
                worker.submit(primary: ScopeFrameInput(sdrFrame: sample.sdrFrame,
                    hdrFrame: sample.hdrFrame, transferFunction: .hlg, displayAspectRatio: 16/9,
                    nativePlots: sample.nativePlots), secondary: nil, source: .primary,
                    differenceGain: 1, mode: .luma, resolution: 720)
            }
            let renderObserver = worker.$renderSequence.sink { sequence in
                if measuring && sequence > 0 { rendered += 1 }
            }
            mpv.load(url: URL(fileURLWithPath: path), autostart: true)
            capture.startCapture()
            for _ in 0..<300 where capture.currentSample == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNotNil(capture.currentSample)
            try await Task.sleep(for: .milliseconds(500))
            measuring = true
            let start = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(3))
            measuring = false
            let seconds = ProcessInfo.processInfo.systemUptime-start
            rates.append(Double(rendered)/seconds)
            XCTAssertEqual(wrongBackend, 0)
            XCTAssertGreaterThan(Double(times.count), Double(captured)*0.8)
            print("MPV_SCOPE_THROUGHPUT: native=\(native) rendered=\(rendered) captured=\(captured) distinctPTS=\(times.count) seconds=\(seconds)")
            sampleObserver.cancel(); renderObserver.cancel()
            capture.stopCapture(); capture.detachMPV(); worker.cancel(clearImages: true); mpv.destroy()
            withExtendedLifetime(view) {}
        }
        XCTAssertGreaterThan(rates[1], 20)
        XCTAssertGreaterThanOrEqual(rates[1], rates[0]*0.9)
        print("MPV_SCOPE_PLAYBACK_ACCEPTANCE: screenshotFPS=\(rates[0]) nativeFPS=\(rates[1])")
    }

    func testNativeCaptureRendersAllModesAndRetainsDisplayDifferenceFallback() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MPV_SCOPE_TEST_FIXTURES"] else {
            throw XCTSkip("Set MPV_SCOPE_TEST_FIXTURES for the arm64 native scope candidate")
        }
        let oldResolution = UserDefaults.standard.object(forKey: AppSettings.scopeResolution.key)
        UserDefaults.standard.set(64, forKey: AppSettings.scopeResolution.key)
        defer { UserDefaults.standard.set(oldResolution, forKey: AppSettings.scopeResolution.key) }
        for name in ["sdr", "pq", "hlg"] {
            let mpv = MPVPlayer()
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
            let layer = MPVMetalLayer(); layer.frame = view.bounds; layer.drawableSize = view.bounds.size
            view.layer = layer; view.wantsLayer = true
            XCTAssertFalse(mpv.attachDrawable(layer), "Initial attachment does not require a drawable replacement")
            let capture = FrameCapture()
            capture.attachMPV(mpv)
            mpv.load(url: URL(fileURLWithPath: directory).appendingPathComponent(name+".mkv"))
            capture.startCapture()
            defer { capture.stopCapture(); capture.detachMPV(); mpv.destroy() }
            for _ in 0..<300 where capture.currentSample?.nativePlots == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            let sample = try XCTUnwrap(capture.currentSample)
            let plots = try XCTUnwrap(sample.nativePlots, "Candidate must use native analysis for \(name)")
            XCTAssertEqual(plots.transfer, name == "sdr" ? "srgb" : name)
            XCTAssertNil(sample.sdrFrame)
            XCTAssertNil(sample.hdrFrame)
            XCTAssertEqual(sample.timestampQuality, .exact)
            let worker = ScopeRenderWorker()
            for mode in WaveformMode.allCases {
                let sequence = worker.renderSequence
                worker.submit(primary: ScopeFrameInput(sdrFrame: nil, hdrFrame: nil,
                    transferFunction: name == "sdr" ? .sdr : name == "pq" ? .pq : .hlg,
                    displayAspectRatio: 1, nativePlots: plots), secondary: nil, source: .primary,
                    differenceGain: 1, mode: mode, resolution: 64)
                for _ in 0..<100 where worker.renderSequence == sequence {
                    try await Task.sleep(for: .milliseconds(5))
                }
                XCTAssertTrue(worker.waveformImage === (mode == .luma ? plots.waveform : plots.parade))
                XCTAssertTrue(worker.vectorscopeImage === plots.vectorscope)
            }
            worker.cancel(clearImages: true)
            capture.requiresDisplayFrame = true
            XCTAssertNil(capture.currentSample)
            for _ in 0..<300 where capture.currentFrame == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNotNil(capture.currentFrame, "Display-space difference still gets captured RGB")
            XCTAssertNil(capture.currentSample?.nativePlots)
            capture.requiresDisplayFrame = false
            for _ in 0..<300 where capture.currentSample?.nativePlots == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNotNil(capture.currentSample?.nativePlots)
            capture.stopCapture()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(capture.currentSample, "Stopping rejects an in-flight native completion")
            withExtendedLifetime(view) {}
        }
        print("MPV_NATIVE_SCOPE_APP_ACCEPTANCE: SDR/PQ/HLG, waveform/parade/vector, fallback and stop")
    }
}
