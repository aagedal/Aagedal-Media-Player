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
    enum TimestampSource: String, Equatable, Sendable {
        case ffmpegFrameCRC = "ffmpeg-framecrc-v1"
    }

    let request: LiveAudioMeterDecodeRequest
    let decoderVersion: String
    let arguments: [String]
    let sampleFormat: String
    let dynamicRangeCompressionDisabled: Bool
    let codecNormalizationDisabled: Bool
    let timestampSource: TimestampSource
    let timestampTimeBase: String
    let timestampFrameCount: Int64
}

nonisolated struct LiveAudioMeterDecodeCompletion: Equatable, Sendable {
    let provenance: LiveAudioMeterDecodeProvenance
    let finalSnapshot: LiveAudioMeterSnapshot?
}

/// Hard source-frame admission bound shared by the playback owner and decoder
/// worker. Blocking the stdout callback applies pipe backpressure before PCM is
/// queued or processed beyond the current playback budget.
nonisolated final class LiveAudioMeterWorkerGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let sampleRate: Int
    private let maximumAheadFrames: Int64
    private nonisolated(unsafe) var maximumEndFrame: Int64
    private nonisolated(unsafe) var maximaResetRevision: UInt64 = 0
    private nonisolated(unsafe) var isSuspended = false
    private nonisolated(unsafe) var isCancelled = false

    init(request: LiveAudioMeterDecodeRequest) {
        sampleRate = request.format.sampleRate
        maximumAheadFrames = Int64(
            (LiveAudioMeterClockPolicy.maximumDrift * Double(request.format.sampleRate)).rounded(.down)
        )
        maximumEndFrame = request.startSourceFrame
    }

    func update(playbackTime: TimeInterval) {
        guard playbackTime.isFinite, playbackTime >= 0 else { return }
        let frameValue = (playbackTime * Double(sampleRate)).rounded(.down)
        guard frameValue.isFinite, frameValue <= Double(Int64.max - maximumAheadFrames) else { return }
        condition.withLock {
            maximumEndFrame = Int64(frameValue) + maximumAheadFrames
            condition.broadcast()
        }
    }

    func suspend() {
        condition.withLock { isSuspended = true }
    }

    func resume() {
        condition.withLock {
            isSuspended = false
            condition.broadcast()
        }
    }

    func cancel() {
        condition.withLock {
            isCancelled = true
            condition.broadcast()
        }
    }

    /// Orders a numerical-maxima clear relative to worker snapshots without
    /// restarting source-time filters, windows, or peak ballistics.
    @discardableResult
    func clearMaxima() -> UInt64 {
        condition.withLock {
            maximaResetRevision += 1
            return maximaResetRevision
        }
    }

    /// Returns the number of additional bytes that may be admitted without
    /// moving processed plus pending PCM beyond the hard source-frame limit.
    func waitForByteCapacity(
        processedEndFrame: Int64,
        pendingByteCount: Int,
        bytesPerFrame: Int
    ) throws -> Int {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if isCancelled { throw CancellationError() }
            if !isSuspended, maximumEndFrame > processedEndFrame {
                let frameCapacity = maximumEndFrame - processedEndFrame
                let (byteCapacity64, overflow) = frameCapacity.multipliedReportingOverflow(
                    by: Int64(bytesPerFrame)
                )
                let available64 = overflow
                    ? Int64.max
                    : max(0, byteCapacity64 - Int64(pendingByteCount))
                if available64 > 0 {
                    return Int(min(available64, Int64(Int.max)))
                }
            }
            condition.wait()
        }
    }

    var permittedEndFrame: Int64 {
        condition.withLock { maximumEndFrame }
    }

    var currentMaximaResetRevision: UInt64 {
        condition.withLock { maximaResetRevision }
    }
}

/// Converts arbitrary stdout byte boundaries into bounded, frame-aligned DSP
/// calls. It retains at most one 50-ms input block, never a stream-length PCM
/// buffer or an output history.
nonisolated final class LiveAudioMeterPCMStreamProcessor: @unchecked Sendable {
    typealias SnapshotHandler = @Sendable (LiveAudioMeterSnapshot) -> Void

    private let lock = NSLock()
    private let onSnapshot: SnapshotHandler
    private let workerGate: LiveAudioMeterWorkerGate?
    private let admissionLock = NSLock()
    private let blockFrames: Int
    private let bytesPerFrame: Int
    private nonisolated(unsafe) var meter: LiveAudioMeterDSP
    private nonisolated(unsafe) var pending: [UInt8] = []
    private nonisolated(unsafe) var isFinished = false
    private nonisolated(unsafe) var appliedMaximaResetRevision: UInt64 = 0

    init(
        request: LiveAudioMeterDecodeRequest,
        workerGate: LiveAudioMeterWorkerGate? = nil,
        onSnapshot: @escaping SnapshotHandler
    ) throws {
        meter = try LiveAudioMeterDSP(format: request.format, startFrame: request.startSourceFrame)
        self.workerGate = workerGate
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

    var receivedFrameCount: Int64 {
        lock.withLock {
            meter.nextFrame - meter.segmentStartFrame + Int64(pending.count / bytesPerFrame)
        }
    }

    func consume(_ data: Data) throws {
        guard !data.isEmpty else { return }
        admissionLock.lock()
        defer { admissionLock.unlock() }
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let admission = lock.withLock {
                (processedEndFrame: meter.nextFrame, pendingByteCount: pending.count)
            }
            let gateCapacity = try workerGate?.waitForByteCapacity(
                processedEndFrame: admission.processedEndFrame,
                pendingByteCount: admission.pendingByteCount,
                bytesPerFrame: bytesPerFrame
            ) ?? Int.max
            let snapshots: [LiveAudioMeterSnapshot] = try lock.withLock {
                guard !isFinished else { throw LiveAudioMeterDecoder.Failure.alreadyFinished }
                let available = maximumBufferedByteCount - pending.count
                let count = min(
                    available,
                    gateCapacity,
                    data.distance(from: cursor, to: data.endIndex)
                )
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
        admissionLock.lock()
        defer { admissionLock.unlock() }
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
                applyPendingMaximaReset()
                return try meter.finish().map(stampMaximaResetRevision)
            } catch let error as LiveAudioMeterDSP.Failure {
                throw LiveAudioMeterDecoder.Failure.dsp(error)
            }
        }
        snapshots.forEach(onSnapshot)
        if let final { onSnapshot(final) }
        return final
    }

    private func processPendingBlock() throws -> [LiveAudioMeterSnapshot] {
        applyPendingMaximaReset()
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
                .map(stampMaximaResetRevision)
        } catch let error as LiveAudioMeterDSP.Failure {
            throw LiveAudioMeterDecoder.Failure.dsp(error)
        }
    }

    private func applyPendingMaximaReset() {
        let requestedRevision = workerGate?.currentMaximaResetRevision ?? 0
        guard requestedRevision != appliedMaximaResetRevision else { return }
        meter.clearMaxima()
        appliedMaximaResetRevision = requestedRevision
    }

    private func stampMaximaResetRevision(
        _ snapshot: LiveAudioMeterSnapshot
    ) -> LiveAudioMeterSnapshot {
        snapshot.applyingMaximaResetRevision(appliedMaximaResetRevision)
    }
}

/// Couples raw PCM on stdout to FFmpeg framecrc records on stderr. No PCM
/// reaches the meter until its exact packet size, PTS/DTS, and Adler-32 have
/// been verified. During active streaming both unmatched sides are bounded to
/// 250 ms; a temporarily faster output therefore applies pipe backpressure
/// instead of accumulating with playback duration. Process termination releases
/// waits so the OS-bounded final pipe tail can be reconciled or rejected.
nonisolated final class LiveAudioMeterTimestampedStreamProcessor: @unchecked Sendable {
    struct Summary: Equatable, Sendable {
        let packetCount: Int64
        let frameCount: Int64
    }

    private struct Record: Equatable, Sendable {
        let pts: Int64
        let frameCount: Int64
        let byteCount: Int
        let checksum: UInt32
    }

    private let condition = NSCondition()
    private let admissionLock = NSLock()
    private let downstream: LiveAudioMeterPCMStreamProcessor
    private let expectedSampleRate: Int
    private let bytesPerFrame: Int
    private let maximumTimestampJitterFrames: Int64
    let maximumUnmatchedByteCount: Int
    private nonisolated(unsafe) var records: [Record] = []
    private nonisolated(unsafe) var pendingPCM = Data()
    private nonisolated(unsafe) var unmatchedTimingByteCount = 0
    private nonisolated(unsafe) var packetCount: Int64 = 0
    private nonisolated(unsafe) var expectedPTS: Int64 = 0
    private nonisolated(unsafe) var hasTimeBase = false
    private nonisolated(unsafe) var hasSampleRate = false
    private nonisolated(unsafe) var terminationStarted = false
    private nonisolated(unsafe) var timingEnded = false
    private nonisolated(unsafe) var failure: LiveAudioMeterDecoder.Failure?

    init(
        request: LiveAudioMeterDecodeRequest,
        workerGate: LiveAudioMeterWorkerGate? = nil,
        onSnapshot: @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
    ) throws {
        downstream = try LiveAudioMeterPCMStreamProcessor(
            request: request, workerGate: workerGate, onSnapshot: onSnapshot
        )
        expectedSampleRate = request.format.sampleRate
        bytesPerFrame = request.format.channelCount * MemoryLayout<Float>.size
        // Extracted streams can retain a coarse container time base even after
        // FFmpeg expresses the decoded packets in 1/sampleRate units. Independent
        // packet rounding can then move a timestamp by a few source frames (for
        // example 128 followed by 120) although the checksummed PCM is complete.
        // One millisecond covers that quantization without concealing an audible
        // discontinuity.
        maximumTimestampJitterFrames = Int64(max(1, request.format.sampleRate / 1_000))
        maximumUnmatchedByteCount = request.format.sampleRate / 4 * bytesPerFrame
        pendingPCM.reserveCapacity(maximumUnmatchedByteCount)
    }

    func consumeTimingLine(_ line: String) -> LiveAudioMeterDecoder.Failure? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#tb 0:") {
            let actual = trimmed.dropFirst("#tb 0:".count)
                .trimmingCharacters(in: .whitespaces)
            return condition.withLock {
                guard failure == nil else { return nil }
                guard actual == "1/\(expectedSampleRate)" else {
                    return failLocked(.timestampTimeBaseMismatch(
                        expected: "1/\(expectedSampleRate)", actual: actual
                    ))
                }
                hasTimeBase = true
                return nil
            }
        }
        if trimmed.hasPrefix("#sample_rate 0:") {
            let actual = Int(trimmed.dropFirst("#sample_rate 0:".count)
                .trimmingCharacters(in: .whitespaces))
            return condition.withLock {
                guard failure == nil else { return nil }
                guard actual == expectedSampleRate else {
                    return failLocked(.timestampSampleRateMismatch(
                        expected: expectedSampleRate, actual: Int64(actual ?? -1)
                    ))
                }
                hasSampleRate = true
                return nil
            }
        }
        guard let first = trimmed.first, first.isNumber else { return nil }
        guard let record = Self.parseRecord(trimmed, bytesPerFrame: bytesPerFrame) else {
            return condition.withLock { failLocked(.malformedFrameTimestamp) }
        }

        condition.lock()
        defer { condition.unlock() }
        guard failure == nil else { return nil }
        guard hasTimeBase, hasSampleRate else {
            return failLocked(.missingFrameTimestampHeader)
        }
        let minimumPTS = expectedPTS - maximumTimestampJitterFrames
        let (maximumPTS, maximumPTSOverflow) = expectedPTS.addingReportingOverflow(
            maximumTimestampJitterFrames
        )
        guard record.pts >= minimumPTS,
              maximumPTSOverflow || record.pts <= maximumPTS else {
            return failLocked(.timestampDiscontinuity(
                expectedFrame: expectedPTS, actualFrame: record.pts
            ))
        }
        let (nextExpectedPTS, nextPTSOverflow) = expectedPTS.addingReportingOverflow(
            record.frameCount
        )
        guard !nextPTSOverflow else {
            return failLocked(.malformedFrameTimestamp)
        }
        guard record.byteCount <= maximumUnmatchedByteCount else {
            return failLocked(.timestampPacketTooLarge(
                byteCount: record.byteCount, maximum: maximumUnmatchedByteCount
            ))
        }
        while failure == nil, !terminationStarted,
              unmatchedTimingByteCount + record.byteCount > maximumUnmatchedByteCount {
            condition.wait()
        }
        guard failure == nil else { return nil }
        records.append(record)
        unmatchedTimingByteCount += record.byteCount
        packetCount += 1
        // Use the verified PCM frame count as the logical source position. The
        // packet timestamp remains an independent continuity check, but bounded
        // container rounding must not drop or duplicate decoded samples.
        expectedPTS = nextExpectedPTS
        condition.broadcast()
        return nil
    }

    func consumePCM(_ data: Data) throws {
        admissionLock.lock()
        defer { admissionLock.unlock() }
        var cursor = data.startIndex

        while true {
            condition.lock()
            if let failure {
                condition.unlock()
                throw failure
            }
            if let record = records.first {
                let needed = record.byteCount - pendingPCM.count
                if needed > 0, cursor < data.endIndex {
                    let count = min(needed, data.distance(from: cursor, to: data.endIndex))
                    let end = data.index(cursor, offsetBy: count)
                    pendingPCM.append(data[cursor..<end])
                    cursor = end
                }
                if pendingPCM.count >= record.byteCount {
                    let packet = Data(pendingPCM.prefix(record.byteCount))
                    pendingPCM.removeFirst(record.byteCount)
                    records.removeFirst()
                    unmatchedTimingByteCount -= record.byteCount
                    condition.broadcast()
                    condition.unlock()
                    let checksum = Self.adler32(packet)
                    guard checksum == record.checksum else {
                        let discovered = LiveAudioMeterDecoder.Failure.timestampChecksumMismatch(
                            expected: record.checksum, actual: checksum
                        )
                        recordFailure(discovered)
                        throw discovered
                    }
                    try downstream.consume(packet)
                    continue
                }
            } else if cursor < data.endIndex {
                let available = maximumUnmatchedByteCount - pendingPCM.count
                if available > 0 {
                    let count = min(available, data.distance(from: cursor, to: data.endIndex))
                    let end = data.index(cursor, offsetBy: count)
                    pendingPCM.append(data[cursor..<end])
                    cursor = end
                } else if timingEnded {
                    let discovered = failLocked(.missingFrameTimestamps)
                    condition.unlock()
                    throw discovered
                } else {
                    condition.wait()
                    condition.unlock()
                    continue
                }
            }
            condition.unlock()
            if cursor == data.endIndex { return }
        }
    }

    func prepareForProcessTermination() {
        condition.withLock {
            terminationStarted = true
            condition.broadcast()
        }
    }

    func finishTiming() {
        condition.withLock {
            timingEnded = true
            condition.broadcast()
        }
    }

    func cancel() {
        recordFailure(.cancelled)
    }

    func finish() throws -> (LiveAudioMeterSnapshot?, Summary) {
        try consumePCM(Data())
        let summary: Summary = try condition.withLock {
            if let failure { throw failure }
            guard timingEnded else { throw LiveAudioMeterDecoder.Failure.missingFrameTimestamps }
            guard hasTimeBase, hasSampleRate else {
                throw LiveAudioMeterDecoder.Failure.missingFrameTimestampHeader
            }
            guard records.isEmpty, pendingPCM.isEmpty else {
                throw LiveAudioMeterDecoder.Failure.timestampStreamIncomplete(
                    pcmBytes: pendingPCM.count, timingBytes: unmatchedTimingByteCount
                )
            }
            return Summary(packetCount: packetCount, frameCount: expectedPTS)
        }
        guard downstream.receivedFrameCount == summary.frameCount else {
            throw LiveAudioMeterDecoder.Failure.timestampFrameCountMismatch(
                expected: summary.frameCount, actual: downstream.receivedFrameCount
            )
        }
        return (try downstream.finish(), summary)
    }

    private func recordFailure(_ discovered: LiveAudioMeterDecoder.Failure) {
        condition.withLock { _ = failLocked(discovered) }
    }

    @discardableResult
    private func failLocked(
        _ discovered: LiveAudioMeterDecoder.Failure
    ) -> LiveAudioMeterDecoder.Failure {
        if failure == nil { failure = discovered }
        condition.broadcast()
        return failure ?? discovered
    }

    private static func parseRecord(_ line: String, bytesPerFrame: Int) -> Record? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard fields.count == 6,
              Int(fields[0]) == 0,
              let dts = Int64(fields[1]),
              let pts = Int64(fields[2]),
              let frameCount = Int64(fields[3]), frameCount > 0,
              let byteCount = Int(fields[4]), byteCount > 0,
              dts == pts,
              frameCount <= Int64.max / Int64(bytesPerFrame),
              byteCount == Int(frameCount) * bytesPerFrame,
              fields[5].hasPrefix("0x"),
              let checksum = UInt32(fields[5].dropFirst(2), radix: 16) else { return nil }
        return Record(
            pts: pts, frameCount: frameCount, byteCount: byteCount, checksum: checksum
        )
    }

    private static func adler32(_ data: Data) -> UInt32 {
        let modulus: UInt32 = 65_521
        var a: UInt32 = 0
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % modulus
            b = (b + a) % modulus
        }
        return (b << 16) | a
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
        case missingFrameTimestamps
        case missingFrameTimestampHeader
        case malformedFrameTimestamp
        case timestampDiscontinuity(expectedFrame: Int64, actualFrame: Int64)
        case timestampTimeBaseMismatch(expected: String, actual: String)
        case timestampSampleRateMismatch(expected: Int, actual: Int64)
        case timestampPacketTooLarge(byteCount: Int, maximum: Int)
        case timestampChecksumMismatch(expected: UInt32, actual: UInt32)
        case timestampStreamIncomplete(pcmBytes: Int, timingBytes: Int)
        case timestampFrameCountMismatch(expected: Int64, actual: Int64)

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
            case .missingFrameTimestamps:
                "The decoder produced PCM without authoritative frame timestamps."
            case .missingFrameTimestampHeader:
                "The decoder timestamp stream did not declare its required time base and sample rate."
            case .malformedFrameTimestamp:
                "The decoder produced a malformed audio-frame timestamp."
            case .timestampDiscontinuity(let expected, let actual):
                "The decoder audio timestamp expected frame \(expected) but received \(actual)."
            case .timestampTimeBaseMismatch(let expected, let actual):
                "The decoder timestamp time base changed from \(expected) to \(actual)."
            case .timestampSampleRateMismatch(let expected, let actual):
                "The decoder timestamp rate changed from \(expected) Hz to \(actual) Hz."
            case .timestampPacketTooLarge(let byteCount, let maximum):
                "A decoder timestamp packet used \(byteCount) bytes, exceeding the \(maximum)-byte admission bound."
            case .timestampChecksumMismatch(let expected, let actual):
                String(
                    format: "Decoded PCM checksum 0x%08x did not match timestamp packet 0x%08x.",
                    actual, expected
                )
            case .timestampStreamIncomplete(let pcmBytes, let timingBytes):
                "The decoder ended with \(pcmBytes) unmatched PCM byte(s) and \(timingBytes) unmatched timestamp byte(s)."
            case .timestampFrameCountMismatch(let expected, let actual):
                "The decoder timestamp stream described \(expected) frame(s), but PCM contained \(actual)."
            }
        }
    }

    nonisolated static func arguments(
        for request: LiveAudioMeterDecodeRequest,
        inputAudioArguments: [String] = []
    ) -> [String] {
        let source = request.url.isFileURL ? request.url.path : request.url.absoluteString
        // Keep long-source seeking bounded while preserving codec delay and
        // edit-list accuracy at the requested sample boundary. Input seeking
        // gets close; output seeking trims at most one decoded second exactly.
        let decoderPrerollFrames = min(request.startSourceFrame, Int64(request.format.sampleRate))
        let decoderPreroll = Double(decoderPrerollFrames) / Double(request.format.sampleRate)
        let inputSeekFrames = request.startSourceFrame - decoderPrerollFrames
        let inputSeekTime = Double(inputSeekFrames) / Double(request.format.sampleRate)
        var arguments = [
            "-hide_banner", "-nostdin", "-nostats", "-loglevel", "error",
            "-ss", sourceTimeArgument(inputSeekTime), "-accurate_seek",
            // Keep decoded source time aligned with forward 1x playback. Capping
            // catch-up at the requested rate prevents a temporarily stalled
            // reader from racing ahead after it resumes.
            "-readrate", "1", "-readrate_catchup", "1",
        ]
        if decoderPreroll > 0 {
            // Burst only the bounded preroll so readings begin without adding
            // a seek-dependent delay; decoded output remains paced at 1x.
            arguments += ["-readrate_initial_burst", sourceTimeArgument(decoderPreroll)]
        }
        // Native AC-3 DRC and xHE-AAC target normalization are explicitly
        // disabled. Other decoders report these private options as unused.
        arguments += ["-drc_scale", "0", "-target_level", "0"]
        arguments += inputAudioArguments + ["-i", source]
        let timestampFilter = [
            "asettb=expr=1/sr",
            "atrim=start_pts=\(decoderPrerollFrames)",
            "asetpts=PTS-\(decoderPrerollFrames)",
        ]
        arguments += [
            "-map", "0:a:\(request.audioStreamOrderIndex)",
            "-vn", "-sn", "-dn", "-map_metadata", "-1",
            "-af", timestampFilter.joined(separator: ","),
            "-c:a", "pcm_f32le", "-f", "tee",
            "[f=f32le]pipe:1|[f=framecrc]pipe:2",
        ]
        return arguments
    }

    static func decode(
        _ request: LiveAudioMeterDecodeRequest,
        handle: SubprocessHandle = SubprocessHandle(),
        workerGate: LiveAudioMeterWorkerGate? = nil,
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
        let processor = try LiveAudioMeterTimestampedStreamProcessor(
            request: request, workerGate: workerGate, onSnapshot: onSnapshot
        )
        let pipelineFailure = PipelineFailure()

        do {
            try await withTaskCancellationHandler {
                try await FFmpegService.runStreamingOutput(
                    arguments: decoderArguments,
                    handle: handle,
                    onStandardErrorLine: { line in
                        guard let failure = processor.consumeTimingLine(line) else { return }
                        pipelineFailure.record(failure)
                        processor.cancel()
                        handle.cancel()
                    },
                    onProcessTermination: { processor.prepareForProcessTermination() },
                    onStandardErrorEnd: { processor.finishTiming() }
                ) { data in
                    do {
                        try processor.consumePCM(data)
                    } catch {
                        pipelineFailure.record(error)
                        processor.cancel()
                        handle.cancel()
                    }
                }
            } onCancel: {
                workerGate?.cancel()
                processor.cancel()
                handle.cancel()
            }
            try Task.checkCancellation()
        } catch {
            if let failure = pipelineFailure.failure { throw failure }
            throw map(error)
        }
        if let failure = pipelineFailure.failure { throw failure }
        let (finalSnapshot, timestampSummary) = try processor.finish()
        return LiveAudioMeterDecodeCompletion(
            provenance: LiveAudioMeterDecodeProvenance(
                request: request,
                decoderVersion: decoderVersion,
                arguments: decoderArguments,
                sampleFormat: "f32le",
                dynamicRangeCompressionDisabled: true,
                codecNormalizationDisabled: true,
                timestampSource: .ffmpegFrameCRC,
                timestampTimeBase: "1/\(request.format.sampleRate)",
                timestampFrameCount: timestampSummary.frameCount
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
