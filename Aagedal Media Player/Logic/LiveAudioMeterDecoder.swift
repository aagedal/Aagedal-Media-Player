// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Immutable identity for one source-PCM decode. The stream index is the
/// zero-based audio-stream order used by ffmpeg's `0:a:N` mapping.
nonisolated struct LiveAudioMeterDecodeRequest: Equatable, Sendable {
    let url: URL
    let audioStreamOrderIndex: Int
    let format: LiveAudioMeterFormat
    let startSourceFrame: Int64
    let startSourceTime: TimeInterval

    init(
        url: URL,
        audioStreamOrderIndex: Int,
        format: LiveAudioMeterFormat,
        startSourceFrame: Int64,
        startSourceTime: TimeInterval
    ) throws {
        guard audioStreamOrderIndex >= 0 else {
            throw LiveAudioMeterDecoder.Failure.invalidAudioStreamOrderIndex(audioStreamOrderIndex)
        }
        guard startSourceFrame >= 0, startSourceTime.isFinite, startSourceTime >= 0 else {
            throw LiveAudioMeterDecoder.Failure.invalidStartPosition
        }
        let frameTime = Double(startSourceFrame) / Double(format.sampleRate)
        let halfFrame = 0.5 / Double(format.sampleRate)
        guard abs(frameTime - startSourceTime) <= halfFrame else {
            throw LiveAudioMeterDecoder.Failure.inconsistentStartPosition
        }
        self.url = url
        self.audioStreamOrderIndex = audioStreamOrderIndex
        self.format = format
        self.startSourceFrame = startSourceFrame
        self.startSourceTime = startSourceTime
    }
}

/// Information needed to qualify a live reading as decoded source PCM.
nonisolated struct LiveAudioMeterDecodeProvenance: Equatable, Sendable {
    let request: LiveAudioMeterDecodeRequest
    let decoderVersion: String
    let arguments: [String]
    let sampleFormat: String
    let dynamicRangeCompressionDisabled: Bool
    let codecNormalizationDisabled: Bool
}

nonisolated struct LiveAudioMeterDecodeCompletion: Equatable, Sendable {
    let provenance: LiveAudioMeterDecodeProvenance
    let finalSnapshot: LiveAudioMeterSnapshot?
}

/// Converts arbitrary stdout byte boundaries into bounded, frame-aligned DSP
/// calls. It retains at most one 50-ms input block, never a stream-length PCM
/// buffer or an output history.
nonisolated final class LiveAudioMeterPCMStreamProcessor: @unchecked Sendable {
    typealias SnapshotHandler = @Sendable (LiveAudioMeterSnapshot) -> Void

    private let lock = NSLock()
    private let onSnapshot: SnapshotHandler
    private let blockFrames: Int
    private let bytesPerFrame: Int
    private nonisolated(unsafe) var meter: LiveAudioMeterDSP
    private nonisolated(unsafe) var pending: [UInt8] = []
    private nonisolated(unsafe) var isFinished = false

    init(request: LiveAudioMeterDecodeRequest, onSnapshot: @escaping SnapshotHandler) throws {
        meter = try LiveAudioMeterDSP(format: request.format, startFrame: request.startSourceFrame)
        self.onSnapshot = onSnapshot
        bytesPerFrame = request.format.channelCount * MemoryLayout<Float>.size
        // A peak publication block keeps latency and queued PCM below the DSP's
        // 250-ms hard ceiling while remaining an exact interleaved-frame size.
        blockFrames = min(meter.maximumBlockFrames, request.format.sampleRate / 20)
        pending.reserveCapacity(blockFrames * bytesPerFrame)
    }

    var maximumBufferedByteCount: Int { blockFrames * bytesPerFrame }

    var bufferedByteCount: Int {
        lock.withLock { pending.count }
    }

    func consume(_ data: Data) throws {
        guard !data.isEmpty else { return }
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let snapshots: [LiveAudioMeterSnapshot] = try lock.withLock {
                guard !isFinished else { throw LiveAudioMeterDecoder.Failure.alreadyFinished }
                let available = maximumBufferedByteCount - pending.count
                let count = min(available, data.distance(from: cursor, to: data.endIndex))
                let end = data.index(cursor, offsetBy: count)
                pending.append(contentsOf: data[cursor..<end])
                cursor = end
                if pending.count == maximumBufferedByteCount {
                    return try processPendingBlock()
                }
                return []
            }
            // A 50-ms block produces at most one snapshot, so even a synthetic
            // huge callback cannot accumulate stream-length output here.
            snapshots.forEach(onSnapshot)
        }
    }

    @discardableResult
    func finish() throws -> LiveAudioMeterSnapshot? {
        var snapshots: [LiveAudioMeterSnapshot] = []
        let final: LiveAudioMeterSnapshot? = try lock.withLock {
            guard !isFinished else { throw LiveAudioMeterDecoder.Failure.alreadyFinished }
            isFinished = true
            guard pending.count.isMultiple(of: bytesPerFrame) else {
                throw LiveAudioMeterDecoder.Failure.truncatedPCM(
                    frameByteCount: bytesPerFrame, trailingByteCount: pending.count % bytesPerFrame
                )
            }
            if !pending.isEmpty {
                snapshots += try processPendingBlock()
            }
            do {
                return try meter.finish()
            } catch let error as LiveAudioMeterDSP.Failure {
                throw LiveAudioMeterDecoder.Failure.dsp(error)
            }
        }
        snapshots.forEach(onSnapshot)
        if let final { onSnapshot(final) }
        return final
    }

    private func processPendingBlock() throws -> [LiveAudioMeterSnapshot] {
        let sampleCount = pending.count / MemoryLayout<Float>.size
        var pcm: [Float] = []
        pcm.reserveCapacity(sampleCount)
        var byte = 0
        while byte < pending.count {
            let bits = UInt32(pending[byte])
                | UInt32(pending[byte + 1]) << 8
                | UInt32(pending[byte + 2]) << 16
                | UInt32(pending[byte + 3]) << 24
            pcm.append(Float(bitPattern: bits))
            byte += MemoryLayout<Float>.size
        }
        pending.removeAll(keepingCapacity: true)
        do {
            return try meter.process(pcm, startFrame: meter.nextFrame)
        } catch let error as LiveAudioMeterDSP.Failure {
            throw LiveAudioMeterDecoder.Failure.dsp(error)
        }
    }
}

/// Launches one bundled ffmpeg source decoder and streams its f32le output
/// directly through `LiveAudioMeterDSP`.
nonisolated enum LiveAudioMeterDecoder {
    enum Failure: Error, Equatable, LocalizedError {
        case invalidAudioStreamOrderIndex(Int)
        case invalidStartPosition
        case inconsistentStartPosition
        case truncatedPCM(frameByteCount: Int, trailingByteCount: Int)
        case dsp(LiveAudioMeterDSP.Failure)
        case decoderUnavailable
        case decoderFailed(String)
        case cancelled
        case alreadyFinished

        var errorDescription: String? {
            switch self {
            case .invalidAudioStreamOrderIndex:
                "Choose a valid zero-based source audio stream for live metering."
            case .invalidStartPosition:
                "The live meter start frame and source time must be finite and non-negative."
            case .inconsistentStartPosition:
                "The live meter start frame does not match its source time and sample rate."
            case .truncatedPCM(let frameBytes, let trailingBytes):
                "The decoder ended with \(trailingBytes) trailing PCM byte(s); each source frame requires \(frameBytes) bytes."
            case .dsp(let failure):
                "Live meter DSP rejected decoded source PCM: \(String(describing: failure))."
            case .decoderUnavailable:
                "The bundled ffmpeg decoder is unavailable. Reinstall the application and retry."
            case .decoderFailed(let message):
                "The source audio stream could not be decoded for live metering: \(message)"
            case .cancelled:
                "Live source-audio metering was cancelled."
            case .alreadyFinished:
                "The live source-PCM stream has already ended. Start a new meter segment to retry."
            }
        }
    }

    nonisolated static func arguments(
        for request: LiveAudioMeterDecodeRequest,
        inputAudioArguments: [String] = []
    ) -> [String] {
        let source = request.url.isFileURL ? request.url.path : request.url.absoluteString
        return [
            "-hide_banner", "-nostdin", "-loglevel", "error",
            "-ss", sourceTimeArgument(request.startSourceTime),
            // Keep decoded source time aligned with forward 1x playback. Capping
            // catch-up at the requested rate prevents a temporarily stalled
            // reader from racing ahead after it resumes.
            "-readrate", "1", "-readrate_catchup", "1",
            // Native AC-3 DRC and xHE-AAC target normalization are explicitly
            // disabled. Other decoders report these private options as unused.
            "-drc_scale", "0", "-target_level", "0",
        ] + inputAudioArguments + [
            "-i", source,
            "-map", "0:a:\(request.audioStreamOrderIndex)",
            "-vn", "-sn", "-dn", "-map_metadata", "-1",
            "-c:a", "pcm_f32le", "-f", "f32le", "pipe:1",
        ]
    }

    static func decode(
        _ request: LiveAudioMeterDecodeRequest,
        handle: SubprocessHandle = SubprocessHandle(),
        onSnapshot: @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
    ) async throws -> LiveAudioMeterDecodeCompletion {
        guard let path = FFmpegService.ffmpegPath else { throw Failure.decoderUnavailable }
        let executableURL = URL(fileURLWithPath: path)
        let decoderVersion = try await version(executableURL: executableURL)
        let inputArguments: [String]
        do {
            inputArguments = try RIFXAudioDecoding.ffmpegInputArguments(for: request.url)
        } catch {
            throw Failure.decoderFailed(error.localizedDescription)
        }
        let decoderArguments = arguments(for: request, inputAudioArguments: inputArguments)
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request, onSnapshot: onSnapshot)
        let pipelineFailure = PipelineFailure()

        do {
            try await FFmpegService.runStreamingOutput(arguments: decoderArguments, handle: handle) { data in
                do {
                    try processor.consume(data)
                } catch {
                    pipelineFailure.record(error)
                    handle.cancel()
                }
            }
            try Task.checkCancellation()
        } catch {
            if let failure = pipelineFailure.failure { throw failure }
            throw map(error)
        }
        if let failure = pipelineFailure.failure { throw failure }
        let finalSnapshot = try processor.finish()
        return LiveAudioMeterDecodeCompletion(
            provenance: LiveAudioMeterDecodeProvenance(
                request: request,
                decoderVersion: decoderVersion,
                arguments: decoderArguments,
                sampleFormat: "f32le",
                dynamicRangeCompressionDisabled: true,
                codecNormalizationDisabled: true
            ),
            finalSnapshot: finalSnapshot
        )
    }

    private static func version(executableURL: URL) async throws -> String {
        do {
            let result = try await SubprocessService.run(
                executableURL: executableURL,
                arguments: ["-version"],
                outputLimit: 4 * 1_024
            )
            guard result.terminationStatus == 0 else {
                throw Failure.decoderFailed("ffmpeg version query failed with status \(result.terminationStatus).")
            }
            let firstLine = String(decoding: result.standardOutput, as: UTF8.self)
                .split(whereSeparator: \.isNewline).first.map(String.init)
            guard let firstLine, !firstLine.isEmpty else {
                throw Failure.decoderFailed("ffmpeg did not report its decoder version.")
            }
            return firstLine
        } catch is CancellationError {
            throw Failure.cancelled
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.decoderFailed(error.localizedDescription)
        }
    }

    private static func map(_ error: Error) -> Failure {
        if error is CancellationError { return .cancelled }
        if let failure = error as? Failure { return failure }
        if let ffmpeg = error as? FFmpegError {
            switch ffmpeg {
            case .cancelled: return .cancelled
            case .ffmpegMissing: return .decoderUnavailable
            default: return .decoderFailed(ffmpeg.localizedDescription)
            }
        }
        return .decoderFailed(error.localizedDescription)
    }

    private nonisolated static func sourceTimeArgument(_ time: TimeInterval) -> String {
        String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), time)
    }

    private final class PipelineFailure: @unchecked Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var stored: Error?

        var failure: Error? { lock.withLock { stored } }

        func record(_ error: Error) {
            lock.withLock {
                if stored == nil { stored = error }
            }
        }
    }
}
