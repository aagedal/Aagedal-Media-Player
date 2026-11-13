// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

/// Track dispositions and editions as mpv 0.42 reports them, through the
/// bundled libmpv and generated files.
@MainActor
final class MPVEditionAndTrackRoleTests: XCTestCase {
    private var retainedSurfaces: [NSView] = []
    private var windows: [NSWindow] = []
    private var temporaryFiles: [URL] = []

    override func tearDown() async throws {
        retainedSurfaces.removeAll()
        windows.forEach { $0.close() }
        windows.removeAll()
        temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryFiles.removeAll()
        try await super.tearDown()
    }

    func testAudioTrackNamesShowRoleFlags() async throws {
        let url = try await generate("roles.mkv", [
            "-f", "lavfi", "-i", "color=c=black:s=160x90:r=25:d=2",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-map", "0", "-map", "1", "-map", "1", "-map", "1", "-map", "1", "-map", "1",
            "-c:v", "ffv1", "-c:a", "pcm_s16le",
            "-disposition:a:0", "original",
            "-disposition:a:1", "comment",
            "-metadata:s:a:2", "title=Director's Commentary", "-disposition:a:2", "comment",
            "-disposition:a:3", "visual_impaired",
        ])
        let player = MPVPlayer()
        defer { player.destroy() }
        player.isMuted = true
        attachSurface(to: player)
        player.load(url: url, autostart: false)
        let loaded = await waitUntil { player.isFileLoaded && player.audioTrackNames.count == 5 }
        let names = player.audioTrackNames
        guard loaded else {
            return XCTFail("Loaded \(player.isFileLoaded), error \(player.error ?? "none"), tracks \(names)")
        }
        XCTAssertTrue(names[0].hasSuffix(" \u{2022} Original"), names[0])
        XCTAssertTrue(names[1].hasSuffix(" \u{2022} Commentary"), names[1])
        XCTAssertFalse(names[2].hasSuffix(" \u{2022} Commentary"), "The title already says so: \(names[2])")
        XCTAssertTrue(names[3].hasSuffix(" \u{2022} Audio Description"), names[3])
        XCTAssertTrue(names[4].hasSuffix(" kHz"), "An unflagged track gains no role: \(names[4])")
    }

    func testTransportStreamProgramsSwitchTracksInPlace() async throws {
        let url = try await makeProgramsFile()
        let controller = try await makePlayingController(url: url)
        defer { controller.teardown() }

        let listed = await waitUntil { controller.editionOptions.count == 2 && controller.currentEditionID != nil }
        XCTAssertTrue(listed, "Editions: \(controller.editionOptions)")
        XCTAssertTrue(controller.editionOptions[0].title.contains("Alpha"), controller.editionOptions[0].title)
        XCTAssertTrue(controller.editionOptions[1].title.contains("Beta"), controller.editionOptions[1].title)
        let first = try XCTUnwrap(controller.currentEditionID)
        let target = try XCTUnwrap(controller.editionOptions.first { $0.id != first })
        let firstLanguage = target.title.contains("Beta") ? "ENG" : "NOR"
        let targetLanguage = firstLanguage == "ENG" ? "NOR" : "ENG"
        let initialTracks = await waitUntil {
            controller.audioTrackOptions.count == 1
                && controller.audioTrackOptions[0].title.contains(firstLanguage)
        }
        XCTAssertTrue(initialTracks, "Only the current program's audio is listed: \(controller.audioTrackOptions)")

        controller.selectEdition(id: target.id)
        let switched = await waitUntil {
            controller.currentEditionID == target.id
                && controller.audioTrackOptions.count == 1
                && controller.audioTrackOptions[0].title.contains(targetLanguage)
        }
        XCTAssertTrue(switched, "Tracks after switching: \(controller.audioTrackOptions)")
        XCTAssertTrue(controller.isPlaying, "A program switch keeps playing")
    }

    func testMatroskaEditionReloadRebuildsChaptersAndKeepsPlaying() async throws {
        let url = try await makeEditionsFile()
        let controller = try await makePlayingController(url: url)
        defer { controller.teardown() }

        let listed = await waitUntil {
            controller.editionOptions.count == 2 && controller.chapterOptions.count == 2
        }
        XCTAssertTrue(listed, "Editions \(controller.editionOptions), chapters \(controller.chapterOptions)")
        controller.selectEdition(id: 1)
        let switched = await waitUntil {
            controller.currentEditionID == 1 && controller.chapterOptions.map(\.title) == ["Alternate"]
        }
        XCTAssertTrue(switched, "Chapters after the reload: \(controller.chapterOptions)")
        XCTAssertEqual(controller.editionOptions.count, 2)
        let playing = await waitUntil {
            controller.isPlaying && (controller.mpvPlayer?.timePos ?? 0) > 0.2
        }
        XCTAssertTrue(playing, "The reload resumes playing and the controller reports it")
    }

    func testLiveLoupeOpensAndFollowsTheChosenProgram() async throws {
        let controller = try await makePlayingController(url: try await makeProgramsFile())
        defer { controller.teardown() }
        let listed = await waitUntil { controller.editionOptions.count == 2 && controller.currentEditionID != nil }
        XCTAssertTrue(listed, "Editions: \(controller.editionOptions)")
        let first = try XCTUnwrap(controller.currentEditionID)
        let target = try XCTUnwrap(controller.editionOptions.first { $0.id != first })
        controller.selectEdition(id: target.id)
        let switched = await waitUntil { controller.currentEditionID == target.id }
        XCTAssertTrue(switched)

        let session = startLiveLoupe(controller: controller)
        defer { session.stop() }
        let opened = await waitUntil { session.player?.currentEditionID == target.id && session.isReady(for: controller) }
        XCTAssertTrue(opened, "Loupe edition \(String(describing: session.player?.currentEditionID)), "
            + "error \(session.error ?? "none")")

        let opening = session.player
        controller.selectEdition(id: first)
        let followed = await waitUntil { session.player?.currentEditionID == first && session.isReady(for: controller) }
        XCTAssertTrue(followed, "Loupe edition \(String(describing: session.player?.currentEditionID))")
        XCTAssertFalse(session.player === opening, "The loupe reopens on the new program")
    }

    func testLiveLoupeFollowsAMatroskaEditionReload() async throws {
        let controller = try await makePlayingController(url: try await makeEditionsFile())
        defer { controller.teardown() }
        let listed = await waitUntil { controller.editionOptions.count == 2 && controller.currentEditionID == 0 }
        XCTAssertTrue(listed, "Editions: \(controller.editionOptions)")
        let session = startLiveLoupe(controller: controller)
        defer { session.stop() }
        let opened = await waitUntil { session.player?.currentEditionID == 0 && session.isReady(for: controller) }
        XCTAssertTrue(opened, session.error ?? "The loupe did not open")

        controller.selectEdition(id: 1)
        let followed = await waitUntil {
            controller.currentEditionID == 1 && session.player?.currentEditionID == 1 && session.isReady(for: controller)
        }
        XCTAssertTrue(followed, "Loupe edition \(String(describing: session.player?.currentEditionID)), "
            + "error \(session.error ?? "none")")
    }

    // MARK: - Helpers

    private func makeProgramsFile() async throws -> URL {
        try await generate("programs.ts", [
            "-f", "lavfi", "-i", "testsrc2=s=320x180:r=25:d=6",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=6",
            "-f", "lavfi", "-i", "smptebars=s=320x180:r=25:d=6",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=6",
            "-map", "0", "-map", "1", "-map", "2", "-map", "3",
            "-c:v", "mpeg2video", "-c:a", "mp2",
            "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=nor",
            "-program", "title=Alpha:program_num=1:st=0:st=1",
            "-program", "title=Beta:program_num=2:st=2:st=3",
        ])
    }

    private func makeEditionsFile() async throws -> URL {
        let metadata = try temporaryURL("chapters.ffmetadata")
        try """
        ;FFMETADATA1
        [CHAPTER]
        TIMEBASE=1/1000
        START=0
        END=3000
        title=Opening
        [CHAPTER]
        TIMEBASE=1/1000
        START=3000
        END=6000
        title=Closing

        """.write(to: metadata, atomically: true, encoding: .utf8)
        let url = try await generate("editions.mkv", [
            "-f", "lavfi", "-i", "testsrc2=s=320x180:r=25:d=6",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=6",
            "-f", "ffmetadata", "-i", metadata.path,
            "-map", "0", "-map", "1", "-map_metadata", "2", "-map_chapters", "2",
            "-c:v", "ffv1", "-c:a", "pcm_s16le", "-write_crc32", "0",
        ])
        try addSingleChapterEdition(titled: "Alternate", to: url)
        return url
    }

    private func startLiveLoupe(controller: PlayerController) -> LiveLoupeSession {
        let session = LiveLoupeSession()
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 160, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        let surface = LiveLoupeVideoSurface.SurfaceView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        surface.session = session
        window.contentView = surface
        window.orderFront(nil)
        session.attachSurface(surface.metalLayer)
        session.start(controller: controller)
        return session
    }

    private func makePlayingController(url: URL) async throws -> PlayerController {
        let controller = PlayerController(proResRAWDetector: { _, _ in false })
        controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: url))
        let constructed = await waitUntil { controller.useMPV && controller.mpvPlayer != nil }
        XCTAssertTrue(constructed)
        let mpv = try XCTUnwrap(controller.mpvPlayer)
        mpv.isMuted = true
        attachSurface(to: mpv)
        let ready = await waitUntil { controller.isReady }
        XCTAssertTrue(ready)
        controller.play()
        let playing = await waitUntil { controller.isPlaying }
        XCTAssertTrue(playing)
        return controller
    }

    private func attachSurface(to player: MPVPlayer) {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let layer = MPVMetalLayer()
        layer.frame = view.bounds
        layer.drawableSize = view.bounds.size
        view.layer = layer
        view.wantsLayer = true
        retainedSurfaces.append(view)
        player.attachDrawable(layer)
    }

    private func temporaryURL(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        temporaryFiles.append(url)
        return url
    }

    private func generate(_ name: String, _ arguments: [String]) async throws -> URL {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = try temporaryURL(name)
        try await FFmpegService.run(arguments: ["-hide_banner", "-nostdin", "-loglevel", "error", "-y"]
            + arguments + [url.path])
        return url
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return predicate()
    }

    /// FFmpeg writes one Matroska edition (here without CRC-32 elements, which
    /// would no longer match). Takes the bytes for a second,
    /// single-chapter edition from the Void after the SeekHead, so clusters
    /// and cues keep their offsets; only Info, Tracks and Chapters move.
    private func addSingleChapterEdition(titled title: String, to url: URL) throws {
        var bytes = [UInt8](try Data(contentsOf: url))
        func vint(_ offset: Int, keepMarker: Bool = false) -> (value: Int, length: Int) {
            let first = Int(bytes[offset])
            let length = first.leadingZeroBitCount - (Int.bitWidth - 8) + 1
            var value = keepMarker ? first : first & ((0x80 >> (length - 1)) - 1)
            for index in 1..<length { value = value << 8 | Int(bytes[offset + index]) }
            return (value, length)
        }
        func element(at offset: Int) -> (id: Int, payload: Int, end: Int) {
            let id = vint(offset, keepMarker: true)
            let size = vint(offset + id.length)
            let payload = offset + id.length + size.length
            return (id.value, payload, payload + size.value)
        }
        func encode(_ id: [UInt8], _ payload: [UInt8]) -> [UInt8] {
            let count = payload.count
            precondition(count < 0x3FFF)
            let size: [UInt8] = count < 0x7F
                ? [0x80 | UInt8(count)]
                : [0x40 | UInt8(count >> 8), UInt8(count & 0xFF)]
            return id + size + payload
        }
        func uint(_ id: [UInt8], _ value: UInt64) -> [UInt8] {
            encode(id, withUnsafeBytes(of: value.bigEndian, Array.init))
        }

        let segment = element(at: element(at: 0).end)
        XCTAssertEqual(segment.id, 0x1853_8067)
        var children: [Int: (start: Int, payload: Int, end: Int)] = [:]
        var offset = segment.payload
        while offset < bytes.count {
            let child = element(at: offset)
            if child.id == 0x1F43_B675 { break }
            if children[child.id] == nil { children[child.id] = (offset, child.payload, child.end) }
            offset = child.end
        }
        let seekHead = try XCTUnwrap(children[0x114D_9B74])
        let void = try XCTUnwrap(children[0xEC])
        let chapters = try XCTUnwrap(children[0x1043_A770])
        XCTAssertLessThan(void.start, chapters.start)

        let display = encode([0x80], encode([0x85], Array(title.utf8)))
        let atom = encode([0xB6], uint([0x73, 0xC4], 0x5EC0_4D00) + uint([0x91], 0) + display)
        let edition = encode([0x45, 0xB9], uint([0x45, 0xBC], 0x5EC0_4D01) + atom)
        let newChapters = encode([0x10, 0x43, 0xA7, 0x70], Array(bytes[chapters.payload..<chapters.end]) + edition)
        let growth = newChapters.count - (chapters.end - chapters.start)
        let voidPayload = void.end - void.start - growth - 2
        XCTAssertGreaterThanOrEqual(voidPayload, 0, "FFmpeg's Void has room for the edition")
        let newVoid = encode([0xEC], [UInt8](repeating: 0, count: voidPayload))

        // SeekHead positions are relative to the Segment payload. Rewrite in
        // place the ones for elements that moved back by `growth` bytes.
        var seek = seekHead.payload
        while seek < seekHead.end {
            let entry = element(at: seek)
            var field = entry.payload
            while field < entry.end {
                let child = element(at: field)
                if child.id == 0x53AC {
                    var position = 0
                    for index in child.payload..<child.end { position = position << 8 | Int(bytes[index]) }
                    let absolute = segment.payload + position
                    if absolute >= void.end, absolute <= chapters.start {
                        var moved = position - growth
                        for index in (child.payload..<child.end).reversed() {
                            bytes[index] = UInt8(moved & 0xFF)
                            moved >>= 8
                        }
                    }
                }
                field = child.end
            }
            seek = entry.end
        }

        let result = Array(bytes[..<void.start]) + newVoid + Array(bytes[void.end..<chapters.start])
            + newChapters + Array(bytes[chapters.end...])
        XCTAssertEqual(result.count, bytes.count)
        try Data(result).write(to: url)
    }
}
