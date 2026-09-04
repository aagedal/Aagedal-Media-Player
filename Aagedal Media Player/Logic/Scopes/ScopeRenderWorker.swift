// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Combine
import Dispatch
import Foundation
import OSLog

nonisolated struct ScopeFrameInput: Sendable {
    let sdrFrame: CGImage?
    let hdrFrame: HDRFrameData?
    let transferFunction: TransferFunction
    let displayAspectRatio: CGFloat?
}

/// Matches independently captured A/B scope frames in their aligned media
/// timelines. The larger frame duration permits valid mixed-rate pairs (for
/// example 59.94 against 23.976) without accepting an arbitrarily stale frame.
nonisolated enum ScopeFramePairer {
    static func tolerance(
        primaryFrameRate: Double?,
        secondaryFrameRate: Double?
    ) -> TimeInterval {
        max(
            frameDuration(for: primaryFrameRate),
            frameDuration(for: secondaryFrameRate)
        )
    }

    static func closestSecondary(
        to primary: ScopeFrameSample,
        mapping: CompareTimelineMapping?,
        secondaryDuration: TimeInterval,
        candidates: [ScopeFrameSample],
        tolerance: TimeInterval
    ) -> ScopeFrameSample? {
        guard let primaryTime = primary.playbackTime else { return nil }
        let target = mapping?.secondaryTime(
            forPrimaryTime: primaryTime,
            secondaryDuration: secondaryDuration
        ) ?? primaryTime
        return closest(
            to: target,
            targetUncertainty: primary.timestampUncertainty,
            candidates: candidates,
            tolerance: tolerance
        )
    }

    static func closest(
        to target: TimeInterval,
        targetUncertainty: TimeInterval = 0,
        candidates: [ScopeFrameSample],
        tolerance: TimeInterval
    ) -> ScopeFrameSample? {
        guard target.isFinite,
              targetUncertainty.isFinite,
              targetUncertainty >= 0,
              tolerance.isFinite,
              tolerance >= 0 else { return nil }
        return candidates
            .compactMap { sample -> (sample: ScopeFrameSample, delta: TimeInterval)? in
                guard sample.timestampQuality != .unavailable,
                      sample.timestampUncertainty.isFinite,
                      let time = sample.playbackTime,
                      time.isFinite else { return nil }
                let delta = abs(time - target)
                guard delta + targetUncertainty + sample.timestampUncertainty
                        <= tolerance else { return nil }
                return (sample, delta)
            }
            .min { lhs, rhs in
                if lhs.delta == rhs.delta {
                    if lhs.sample.timestampQuality == rhs.sample.timestampQuality {
                        return lhs.sample.sequence > rhs.sample.sequence
                    }
                    return timestampRank(lhs.sample.timestampQuality)
                        < timestampRank(rhs.sample.timestampQuality)
                }
                return lhs.delta < rhs.delta
            }?
            .sample
    }

    private static func frameDuration(for rate: Double?) -> TimeInterval {
        guard let rate, rate.isFinite, rate >= 1, rate <= 240 else {
            return 1.0 / 30.0
        }
        return 1.0 / rate
    }

    private static func timestampRank(_ quality: ScopeFrameTimestampQuality) -> Int {
        switch quality {
        case .exact: 0
        case .estimated: 1
        case .unavailable: 2
        }
    }
}

/// Produces the same kind of display-referred absolute RGB difference shown by
/// Compare Mode. B is aspect-fitted into A's frame so differing rasters do not
/// get stretched merely to make their pixel grids match.
nonisolated enum ScopeFrameDifference {
    static func makeDisplaySpaceDifference(
        primary: CGImage,
        primaryDisplayAspectRatio: CGFloat?,
        secondary: CGImage,
        secondaryDisplayAspectRatio: CGFloat?,
        gain: Double
    ) -> CGImage? {
        let width = primary.width
        let primaryAspect = sanitizedAspectRatio(
            primaryDisplayAspectRatio,
            fallback: CGFloat(primary.width) / CGFloat(primary.height)
        )
        let secondaryAspect = sanitizedAspectRatio(
            secondaryDisplayAspectRatio,
            fallback: CGFloat(secondary.width) / CGFloat(secondary.height)
        )
        let height = min(4_096, max(1, Int((CGFloat(width) / primaryAspect).rounded())))
        guard width > 0, height > 0 else { return nil }

        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else { return nil }

        guard let primaryPixels = renderedPixels(
            image: primary,
            canvasWidth: width,
            canvasHeight: height,
            displayAspectRatio: primaryAspect,
            byteCount: byteCount
        ), let secondaryPixels = renderedPixels(
            image: secondary,
            canvasWidth: width,
            canvasHeight: height,
            displayAspectRatio: secondaryAspect,
            byteCount: byteCount
        ) else { return nil }

        let gain = CompareSessionController.clampedDifferenceGain(gain)
        var difference = [UInt8](repeating: 0, count: byteCount)
        for offset in stride(from: 0, to: byteCount, by: 4) {
            difference[offset] = amplifiedDifference(primaryPixels[offset], secondaryPixels[offset], gain: gain)
            difference[offset + 1] = amplifiedDifference(primaryPixels[offset + 1], secondaryPixels[offset + 1], gain: gain)
            difference[offset + 2] = amplifiedDifference(primaryPixels[offset + 2], secondaryPixels[offset + 2], gain: gain)
            difference[offset + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(difference) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func renderedPixels(
        image: CGImage,
        canvasWidth: Int,
        canvasHeight: Int,
        displayAspectRatio: CGFloat,
        byteCount: Int
    ) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: byteCount)
        guard let context = CGContext(
            data: &pixels,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: canvasWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .low

        let canvas = CGSize(width: canvasWidth, height: canvasHeight)
        let canvasAspect = canvas.width / canvas.height
        let size: CGSize
        if displayAspectRatio >= canvasAspect {
            size = CGSize(width: canvas.width, height: canvas.width / displayAspectRatio)
        } else {
            size = CGSize(width: canvas.height * displayAspectRatio, height: canvas.height)
        }
        let drawRect = CGRect(
            x: (canvas.width - size.width) / 2,
            y: (canvas.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        context.draw(image, in: drawRect)
        return pixels
    }

    private static func sanitizedAspectRatio(_ value: CGFloat?, fallback: CGFloat) -> CGFloat {
        guard let value, value.isFinite, value >= 0.1, value <= 10 else { return fallback }
        return value
    }

    private static func amplifiedDifference(_ lhs: UInt8, _ rhs: UInt8, gain: Double) -> UInt8 {
        UInt8(min(Double(abs(Int(lhs) - Int(rhs))) * gain, 255))
    }
}

@MainActor
final class ScopeRenderWorker: ObservableObject {
    @Published private(set) var waveformImage: CGImage?
    @Published private(set) var vectorscopeImage: CGImage?
    @Published private(set) var hdrPeakNits: Float = 10_000
    @Published private(set) var renderSequence: UInt64 = 0

    private nonisolated static let signposter = OSSignposter(
        subsystem: "com.aagedal.MediaPlayer",
        category: "ScopePerformance"
    )

    private struct Request: Sendable {
        let generation: UInt64
        let primary: ScopeFrameInput
        let secondary: ScopeFrameInput?
        let source: CompareScopeSource
        let differenceGain: Double
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
        primary: ScopeFrameInput,
        secondary: ScopeFrameInput?,
        source: CompareScopeSource,
        differenceGain: Double,
        mode: WaveformMode,
        resolution: Int
    ) {
        let selected = source == .secondary ? secondary : primary
        let isHDR = source != .difference && selected?.transferFunction != .sdr
        let hasRequiredFrame: Bool
        if source == .difference {
            hasRequiredFrame = primary.sdrFrame != nil && secondary?.sdrFrame != nil
        } else if isHDR {
            hasRequiredFrame = selected?.sdrFrame != nil || selected?.hdrFrame != nil
        } else {
            hasRequiredFrame = selected?.sdrFrame != nil
        }
        guard hasRequiredFrame else {
            cancel(clearImages: true)
            return
        }

        let width = CGFloat(resolution > 0 ? resolution : 720)
        let height = round(width * 9.0 / 16.0)
        let submission = gate.submit()
        let request = Request(
            generation: submission.generation,
            primary: primary,
            secondary: secondary,
            source: source,
            differenceGain: differenceGain,
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

        waveformImage = result.waveformImage
        vectorscopeImage = result.vectorscopeImage
        renderSequence &+= 1
        if let peakNits = result.hdrPeakNits {
            hdrPeakNits = peakNits
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

        let selected = request.source == .secondary ? request.secondary : request.primary
        let sdrFrame: CGImage?
        if request.source == .difference,
           let primary = request.primary.sdrFrame,
           let secondary = request.secondary?.sdrFrame {
            sdrFrame = ScopeFrameDifference.makeDisplaySpaceDifference(
                primary: primary,
                primaryDisplayAspectRatio: request.primary.displayAspectRatio,
                secondary: secondary,
                secondaryDisplayAspectRatio: request.secondary?.displayAspectRatio,
                gain: request.differenceGain
            )
        } else {
            sdrFrame = selected?.sdrFrame
        }

        if !request.isHDR {
            guard let frame = sdrFrame else {
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
        if let frame = selected?.hdrFrame {
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
        let vectorscope = sdrFrame.flatMap {
            ScopeComputer.computeVectorscope(from: $0, outputSize: request.vectorscopeSize)
        }
        return Result(waveformImage: waveform, vectorscopeImage: vectorscope, hdrPeakNits: peakNits)
    }
}
