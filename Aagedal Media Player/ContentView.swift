// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Main window: drop zone when no file, player when file is loaded.

import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct ContentView: View {
    @StateObject private var controller = PlayerController()
    @State private var timecodeMode: TimecodeDisplayMode = .preferred
    @State private var isDropTargeted = false

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "ContentView")

    var body: some View {
        Group {
            if let item = controller.mediaItem {
                VStack(spacing: 0) {
                    PlayerView(controller: controller, item: item)

                    ControlsView(
                        controller: controller,
                        item: item,
                        timecodeMode: $timecodeMode
                    )
                }
            } else {
                dropZone
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(Color.black)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onOpenURL { url in
            openFile(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            openFilePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
            if let url = notification.object as? URL {
                openFile(url: url)
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Drop a media file here")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("or use File \u{2192} Open")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            Button("Open File\u{2026}") {
                openFilePanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(20)
        )
    }

    // MARK: - File Opening

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedMediaTypes

        if panel.runModal() == .OK, let url = panel.url {
            openFile(url: url)
        }
    }

    func openFile(url: URL) {
        logger.info("Opening file: \(url.lastPathComponent)")

        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        var item = MediaItem(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            size: fileSize
        )

        // Load metadata asynchronously, then start playback
        Task {
            do {
                let metadata = try await MetadataService.shared.metadata(for: url)
                item.metadata = metadata
                item.durationSeconds = metadata.duration ?? 0
                item.hasVideoStream = !metadata.videoStreams.isEmpty
            } catch {
                logger.warning("Failed to load metadata: \(error.localizedDescription)")
            }

            controller.loadMedia(item)
            NSApp.keyWindow?.title = item.name
        }

        // Add to recent files
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else { return }
            Task { @MainActor in
                self.openFile(url: url)
            }
        }

        return true
    }

    private var supportedMediaTypes: [UTType] {
        [
            .movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video,
            UTType("public.mpeg-4") ?? .movie,
            UTType("com.microsoft.windows-media-wmv") ?? .movie,
            UTType("org.matroska.mkv") ?? .movie,
            UTType("public.mxf") ?? .movie,
            UTType("com.apple.quicktime-movie") ?? .quickTimeMovie,
            UTType("public.mp3") ?? .audio,
            UTType("public.aiff-audio") ?? .audio,
            UTType("org.xiph.flac") ?? .audio,
            UTType("com.microsoft.waveform-audio") ?? .audio,
        ]
    }
}
