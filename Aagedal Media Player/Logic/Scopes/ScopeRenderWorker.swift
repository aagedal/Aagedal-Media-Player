// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Combine
import Dispatch
import OSLog

@MainActor
final class ScopeRenderWorker: ObservableObject {
    @Published private(set) var waveformImage: CGImage?
    @Published private(set) var vectorscopeImage: CGImage?
    @Published private(set) var hdrPeakNits: Float = 10_000

    private nonisolated static let signposter = OSSignposter(
        subsystem: "com.aagedal.MediaPlayer",
        category: "ScopePerformance"
    )

    private struct Request: Sendable {
        let generation: UInt64
        let sdrFrame: CGImage?
        let hdrFrame: HDRFrameData?
        let isHDR: Bool
        let mode: WaveformMode
        let waveformSize: CGSize
        let vectorscopeSize: CGSize
    }

    private struct Result: Sendable {
        let waveformImage: CGImage?
        let vectorscopeImage: CGImage?
        let hdrPeakNits: Float?
    }

    private var gate = LatestFrameGate()
    private var pendingRequest: Request?
    private var computeTask: Task<Void, Never>?
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func submit(
        sdrFrame: CGImage?,
        hdrFrame: HDRFrameData?,
        transferFunction: TransferFunction,
        mode: WaveformMode,
        resolution: Int
    ) {
        let isHDR = transferFunction != .sdr
        let hasRequiredFrame = isHDR ? (sdrFrame != nil || hdrFrame != nil) : sdrFrame != nil
        guard hasRequiredFrame else {
            cancel(clearImages: true)
            return
        }

        let width = CGFloat(resolution > 0 ? resolution : 720)
        let height = round(width * 9.0 / 16.0)
        let submission = gate.submit()
        let request = Request(
            generation: submission.generation,
            sdrFrame: sdrFrame,
            hdrFrame: hdrFrame,
            isHDR: isHDR,
            mode: mode,
            waveformSize: CGSize(width: width, height: height),
            vectorscopeSize: CGSize(width: height, height: height)
        )

        if submission.startImmediately {
            start(request)
        } else {
            pendingRequest = request
            if submission.supersededFrame {
                Self.signposter.emitEvent("Scope frame dropped")
            }
        }
    }

    func cancel(clearImages: Bool) {
        gate.reset()
        pendingRequest = nil
        computeTask?.cancel()
        computeTask = nil

        if clearImages {
            waveformImage = nil
            vectorscopeImage = nil
        }
    }

    private func handleMemoryPressure() {
        let event = memoryPressureSource?.data ?? []
        Self.signposter.emitEvent("Scope memory pressure")
        cancel(clearImages: event.contains(.critical))
    }

    private func start(_ request: Request) {
        let detachedTask = Task.detached(priority: .userInitiated) {
            let interval = Self.signposter.beginInterval("Scope compute")
            let result = Self.compute(request)
            Self.signposter.endInterval("Scope compute", interval)
            return result
        }

        computeTask = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await detachedTask.value
            } onCancel: {
                detachedTask.cancel()
            }

            guard !Task.isCancelled else { return }
            self?.finish(result, generation: request.generation)
        }
    }

    private func finish(_ result: Result, generation: UInt64) {
        guard let completion = gate.complete(generation) else { return }
        computeTask = nil

        if completion.shouldPublish {
            waveformImage = result.waveformImage
            vectorscopeImage = result.vectorscopeImage
            if let peakNits = result.hdrPeakNits {
                hdrPeakNits = peakNits
            }
        } else {
            Self.signposter.emitEvent("Stale scope result discarded")
        }

        guard let nextGeneration = completion.nextGeneration,
              let request = pendingRequest,
              request.generation == nextGeneration else { return }
        pendingRequest = nil
        start(request)
    }

    nonisolated private static func compute(_ request: Request) -> Result {
        guard !Task.isCancelled else {
            return Result(waveformImage: nil, vectorscopeImage: nil, hdrPeakNits: nil)
        }

        if !request.isHDR {
            guard let frame = request.sdrFrame else {
                return Result(waveformImage: nil, vectorscopeImage: nil, hdrPeakNits: nil)
            }

            let waveform: CGImage?
            switch request.mode {
            case .luma:
                waveform = ScopeComputer.computeWaveform(from: frame, outputSize: request.waveformSize)
            case .parade:
                waveform = ScopeComputer.computeParade(from: frame, outputSize: request.waveformSize)
            }

            guard !Task.isCancelled else {
                return Result(waveformImage: nil, vectorscopeImage: nil, hdrPeakNits: nil)
            }
            let vectorscope = ScopeComputer.computeVectorscope(from: frame, outputSize: request.vectorscopeSize)
            return Result(waveformImage: waveform, vectorscopeImage: vectorscope, hdrPeakNits: nil)
        }

        var waveform: CGImage?
        var peakNits: Float?
        if let frame = request.hdrFrame {
            peakNits = frame.contentPeakNits
            switch request.mode {
            case .luma:
                waveform = ScopeComputer.computeHDRWaveform(from: frame, outputSize: request.waveformSize)
            case .parade:
                waveform = ScopeComputer.computeHDRParade(from: frame, outputSize: request.waveformSize)
            }
        }

        guard !Task.isCancelled else {
            return Result(waveformImage: nil, vectorscopeImage: nil, hdrPeakNits: nil)
        }
        let vectorscope = request.sdrFrame.flatMap {
            ScopeComputer.computeVectorscope(from: $0, outputSize: request.vectorscopeSize)
        }
        return Result(waveformImage: waveform, vectorscopeImage: vectorscope, hdrPeakNits: peakNits)
    }
}
