// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

/// Owns one offline programme measurement, independently of per-track jobs.
@MainActor
final class ProgrammeLoudnessController: ObservableObject {
    typealias Analyzer = @Sendable (
        URL, ProgrammeLoudnessMapping, [MediaMetadata.AudioStream], Double?, FFmpegService.LoudnessRange?
    ) async throws -> ProgrammeLoudnessResult

    @Published private(set) var mapping: ProgrammeLoudnessMapping?
    @Published private(set) var result: ProgrammeLoudnessResult?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var error: String?

    private var sourceURL: URL?
    private var audioStreams: [MediaMetadata.AudioStream] = []
    private var task: Task<Void, Never>?
    private var generation = OperationGeneration()
    private let analyzer: Analyzer

    init(analyzer: @escaping Analyzer = { url, mapping, streams, duration, range in
        try await FFmpegService.analyzeProgrammeLUFS(
            url: url, mapping: mapping, audioStreams: streams, duration: duration, range: range
        )
    }) {
        self.analyzer = analyzer
    }

    deinit {
        // The analysis holds self weakly, so releasing the owner must also
        // stop its subprocess when there is no inspector callback to cancel it.
        task?.cancel()
    }

    var monoStreamIndices: [Int] {
        audioStreams.indices.filter { audioStreams[$0].channels == 1 }
    }

    var mappingError: String? {
        guard let mapping else { return "Choose at least two mono audio tracks." }
        do {
            try mapping.validate(audioStreams: audioStreams)
            return nil
        } catch { return error.localizedDescription }
    }

    func configure(url: URL, audioStreams: [MediaMetadata.AudioStream]) {
        guard sourceURL != url || self.audioStreams != audioStreams else { return }
        cancel(resetResult: true)
        sourceURL = url
        self.audioStreams = audioStreams
        mapping = monoStreamIndices.count >= 2 ? defaultMapping(for: .stereo) : nil
    }

    func selectLayout(_ layout: ProgrammeLoudnessLayout) {
        guard mapping?.layout != layout else { return }
        cancel(resetResult: true)
        mapping = defaultMapping(for: layout)
    }

    func assignStream(_ streamIndex: Int, toChannel channelIndex: Int) {
        guard let current = mapping,
              current.audioStreamIndices.indices.contains(channelIndex),
              streamIndex == -1 || monoStreamIndices.contains(streamIndex),
              current.audioStreamIndices[channelIndex] != streamIndex else { return }
        cancel(resetResult: true)
        var indices = current.audioStreamIndices
        indices[channelIndex] = streamIndex
        mapping = ProgrammeLoudnessMapping(layout: current.layout, audioStreamIndices: indices)
    }

    private func defaultMapping(for layout: ProgrammeLoudnessLayout) -> ProgrammeLoudnessMapping {
        let available = monoStreamIndices
        return ProgrammeLoudnessMapping(
            layout: layout,
            audioStreamIndices: layout.channelRoles.indices.map { $0 < available.count ? available[$0] : -1 }
        )
    }

    func measure(duration: Double?, range: FFmpegService.LoudnessRange?) {
        guard let sourceURL, let mapping else { return }
        cancel(resetResult: true)
        guard mappingError == nil else { error = mappingError; return }
        let token = generation.current
        let streams = audioStreams
        let analyzer = analyzer
        isAnalyzing = true
        task = Task(priority: .userInitiated) { [weak self] in
            do {
                let result = try await analyzer(sourceURL, mapping, streams, duration, range)
                guard !Task.isCancelled, let self, self.generation.isCurrent(token) else { return }
                self.result = result
                self.isAnalyzing = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.generation.isCurrent(token) else { return }
                if let ffmpegError = error as? FFmpegError, case .processFailed = ffmpegError {
                    self.error = "Programme loudness analysis failed. Check that the assigned tracks are readable, then try again."
                } else {
                    self.error = error.localizedDescription
                }
                self.isAnalyzing = false
                self.task = nil
            }
        }
    }

    func cancel(resetResult: Bool) {
        generation.advance()
        task?.cancel()
        task = nil
        isAnalyzing = false
        error = nil
        if resetResult { result = nil }
    }
}
