// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LiveAudioMeterWindowControllerTests: XCTestCase {
    func testShowReusesActivatingChildPanelAndDirectCloseCleansUpOnce() {
        let parent = makeParentWindow()
        var closeCount = 0
        let controller = LiveAudioMeterWindowController(
            primaryController: PlayerController(),
            compareSession: CompareSessionController(),
            windowCoordinator: PlayerWindowCoordinator(),
            parentWindow: parent,
            onClose: { closeCount += 1 }
        )

        controller.show()

        let panel = parent.childWindows?.first as? NSPanel
        XCTAssertNotNil(panel)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(panel?.canBecomeKey == true)
        XCTAssertEqual(parent.childWindows?.count, 1)

        controller.show()
        XCTAssertTrue(parent.childWindows?.first === panel)
        XCTAssertEqual(parent.childWindows?.count, 1)

        panel?.close()

        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(parent.childWindows?.isEmpty == true)
        XCTAssertEqual(closeCount, 1)

        controller.close()
        XCTAssertEqual(closeCount, 1, "Repeated close paths must not repeat owner cleanup")
    }

    func testParentCloseCancelsMeterWorkerAndDetachesPanel() async throws {
        let player = PlayerController()
        player.mediaItem = mediaItem(url: URL(fileURLWithPath: "/tmp/window-meter-source.mov"))
        player.refreshAudioTrackOptions(playerItem: nil)
        await eventually { player.liveAudioMeterSourceRevision > 0 }

        let decoder = WindowMeterDecodeRecorder()
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let comparison = CompareSessionController()
        let session = LiveAudioMeterSession(
            primary: player,
            comparison: comparison,
            defaults: UserDefaults(suiteName: "LiveAudioMeterWindowControllerTests.\(UUID().uuidString)")!,
            coordinator: coordinator
        )
        let parent = makeParentWindow()
        var closeCount = 0
        let controller = LiveAudioMeterWindowController(
            primaryController: player,
            compareSession: comparison,
            windowCoordinator: PlayerWindowCoordinator(),
            parentWindow: parent,
            session: session,
            onClose: { closeCount += 1 }
        )

        controller.show()
        await eventually { await decoder.requestCount == 1 }
        XCTAssertEqual(parent.childWindows?.count, 1)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: parent)

        await eventually { await decoder.cancellationCount == 1 }
        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(parent.childWindows?.isEmpty == true)
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(
            coordinator.status,
            .unavailable(reason: "Live meters are closed.", diagnostic: nil)
        )

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: parent)
        XCTAssertEqual(closeCount, 1)
    }

    private func makeParentWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    private func mediaItem(url: URL) -> MediaItem {
        let stream = MediaMetadata.AudioStream(
            index: 0,
            languageCode: "eng",
            title: "Stereo mix",
            codec: "aac",
            codecLongName: nil,
            profile: nil,
            sampleRate: 48_000,
            channels: 2,
            channelLayout: "stereo",
            bitDepth: nil,
            bitRate: nil,
            isDefault: true
        )
        let metadata = MediaMetadata(
            duration: 60,
            formatName: "mov",
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [stream],
            subtitleStreams: [],
            chapters: []
        )
        return MediaItem(
            url: url,
            name: url.lastPathComponent,
            size: 0,
            durationSeconds: 60,
            hasVideoStream: false,
            metadata: metadata
        )
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition not satisfied before timeout")
    }
}

private actor WindowMeterDecodeRecorder {
    private(set) var requestCount = 0
    private(set) var cancellationCount = 0

    func decode(
        _ request: LiveAudioMeterDecodeRequest,
        _ handle: SubprocessHandle,
        _ workerGate: LiveAudioMeterWorkerGate,
        _ onSnapshot: @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
    ) async throws -> LiveAudioMeterDecodeCompletion {
        _ = request
        _ = handle
        _ = workerGate
        _ = onSnapshot
        requestCount += 1
        do {
            while true { try await Task.sleep(for: .seconds(10)) }
        } catch {
            cancellationCount += 1
            throw error
        }
    }
}
