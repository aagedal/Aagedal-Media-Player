// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Serial, bounded source-PCM measurement core. It is deliberately not connected
/// to playback until decoder provenance and transport ownership are established.
/// Input is interleaved, unmodified PCM in the declared speaker order.
nonisolated struct LiveAudioMeterFormat: Equatable, Sendable {
    enum Layout: Equatable, Sendable {
        case mono, stereo, surround5Point1, surround7Point1, unknown(channels: Int)

        var weights: [Double]? {
            switch self {
            case .mono: [1]
            case .stereo: [1, 1]
            case .surround5Point1: [1, 1, 1, 0, 1.41, 1.41] // FL FR FC LFE SL SR
            case .surround7Point1: [1, 1, 1, 0, 1, 1, 1.41, 1.41] // FL FR FC LFE BL BR SL SR (Annex 3)
            case .unknown: nil
            }
        }

        var channelCount: Int {
            switch self {
            case .unknown(let channels): channels
            case .mono: 1
            case .stereo: 2
            case .surround5Point1: 6
            case .surround7Point1: 8
            }
        }
    }

    let sampleRate: Int
    let layout: Layout
    var channelCount: Int { layout.channelCount }

    init(sampleRate: Int, layout: Layout) throws {
        guard [44_100, 48_000, 96_000].contains(sampleRate),
              (1...8).contains(layout.channelCount) else { throw LiveAudioMeterDSP.Failure.unsupportedFormat }
        self.sampleRate = sampleRate
        self.layout = layout
    }
}

nonisolated struct LiveAudioMeterSnapshot: Equatable, Sendable {
    /// Exclusive source sample position. Filter tail never advances this value.
    let endFrame: Int64
    let segmentStartFrame: Int64
    let samplePeakDBFS: [Double]
    let truePeakDBTP: [Double]
    /// Nil means a complete window is not available, or speaker roles are unknown.
    /// Negative infinity is a valid measurement of silence.
    let momentaryLUFS: Double?
    let shortTermLUFS: Double?
    /// M/S update on the 100-ms grid; odd peak buckets retain that endpoint.
    let loudnessEndFrame: Int64?
    let maximumSamplePeakDBFS: [Double]
    let maximumTruePeakDBTP: [Double]
    let maximumMomentaryLUFS: Double?
    let maximumShortTermLUFS: Double?
    let isFinal: Bool
}

nonisolated struct LiveAudioMeterDSP: Sendable {
    enum Failure: Error, Equatable {
        case unsupportedFormat, invalidPosition, oversizedBlock, incompleteFrame, nonFinitePCM
        case discontinuity(expected: Int64, actual: Int64)
        case invalidated, alreadyEnded
    }

    static let algorithm = "bs1770-5-k-weighting-annex2-fir4-v1"
    static let reconstructionDelayFrames = 5.875
    static let reconstructionTailFrames = 11
    let format: LiveAudioMeterFormat
    let segmentStartFrame: Int64
    private(set) var nextFrame: Int64
    private(set) var failure: Failure?
    private(set) var isEnded = false
    /// Maximum accepted input block. The caller must bound its own decoder queue.
    var maximumBlockFrames: Int { format.sampleRate / 4 }

    private var channels: [Channel]
    private var bucketSamplePeaks: [Double]
    private var bucketTruePeaks: [Double]
    private var maximumSamplePeaks: [Double]
    private var maximumTruePeaks: [Double]
    private var bucketFrames = 0
    private var bucketEnergy = 0.0
    private var energies = [Double](repeating: 0, count: 60)
    private var energyIndex = 0
    private var energyCount = 0
    private var completedBuckets: Int64 = 0
    private var momentary: Double?
    private var shortTerm: Double?
    private var loudnessEndFrame: Int64?
    private var maximumMomentary: Double?
    private var maximumShortTerm: Double?
    private var lastPublishedSamplePeaks: [Double]
    private var lastPublishedTruePeaks: [Double]

    init(format: LiveAudioMeterFormat, startFrame: Int64 = 0) throws {
        guard startFrame >= 0 else { throw Failure.invalidPosition }
        self.format = format
        segmentStartFrame = startFrame
        nextFrame = startFrame
        channels = (0..<format.channelCount).map { _ in Channel(sampleRate: format.sampleRate) }
        bucketSamplePeaks = .init(repeating: 0, count: format.channelCount)
        bucketTruePeaks = bucketSamplePeaks
        maximumSamplePeaks = bucketSamplePeaks
        maximumTruePeaks = bucketSamplePeaks
        lastPublishedSamplePeaks = bucketSamplePeaks
        lastPublishedTruePeaks = bucketSamplePeaks
    }

    /// Only fixed filter state and sixty 50-ms energy sums are retained; no
    /// per-sample history grows with file duration. At most five snapshots return.
    /// Any rejected block invalidates this segment, rather than hiding a gap.
    mutating func process(_ pcm: [Float], startFrame: Int64) throws -> [LiveAudioMeterSnapshot] {
        guard failure == nil else { throw Failure.invalidated }
        guard !isEnded else { throw Failure.alreadyEnded }
        guard startFrame == nextFrame else {
            throw invalidate(.discontinuity(expected: nextFrame, actual: startFrame))
        }
        guard pcm.count % format.channelCount == 0 else { throw invalidate(.incompleteFrame) }
        let frames = pcm.count / format.channelCount
        guard frames <= maximumBlockFrames else { throw invalidate(.oversizedBlock) }
        guard nextFrame <= Int64.max - Int64(frames) else { throw invalidate(.invalidPosition) }
        // Validate the complete block before changing filter or publication state.
        guard pcm.allSatisfy({ $0.isFinite }) else { throw invalidate(.nonFinitePCM) }
        var snapshots: [LiveAudioMeterSnapshot] = []
        snapshots.reserveCapacity(5)
        let weights = format.layout.weights
        let bucketSize = format.sampleRate / 20
        for frame in 0..<frames {
            for channel in channels.indices {
                let sample = Double(pcm[frame * format.channelCount + channel])
                let measured = channels[channel].process(sample)
                recordPeaks(channel: channel, sample: abs(sample), reconstructed: measured.peak)
                if let weights {
                    bucketEnergy += measured.energy * weights[channel]
                }
            }
            bucketFrames += 1
            nextFrame += 1
            if bucketFrames == bucketSize {
                energies[energyIndex] = bucketEnergy / Double(bucketSize)
                energyIndex = (energyIndex + 1) % energies.count
                energyCount = min(energyCount + 1, energies.count)
                completedBuckets += 1
                if completedBuckets.isMultiple(of: 2), weights != nil {
                    if energyCount >= 8 {
                        momentary = loudness(windowBuckets: 8)
                        loudnessEndFrame = nextFrame
                    }
                    if energyCount >= 60 { shortTerm = loudness(windowBuckets: 60) }
                    if let momentary { maximumMomentary = max(maximumMomentary ?? -.infinity, momentary) }
                    if let shortTerm { maximumShortTerm = max(maximumShortTerm ?? -.infinity, shortTerm) }
                }
                snapshots.append(snapshot(isFinal: false))
                lastPublishedSamplePeaks = bucketSamplePeaks
                lastPublishedTruePeaks = bucketTruePeaks
                clearBucket()
            }
        }
        return snapshots
    }

    /// Drain only the reconstruction FIR, retaining the true source endpoint.
    /// No artificial silence enters the loudness windows or sample-peak reading.
    /// At an exact publication boundary this revises the last bucket at the same
    /// endpoint; consumers must not advance display time or restart its hold.
    mutating func finish() throws -> LiveAudioMeterSnapshot? {
        guard failure == nil else { throw Failure.invalidated }
        guard !isEnded else { throw Failure.alreadyEnded }
        isEnded = true
        guard nextFrame > segmentStartFrame else { return nil }
        if bucketFrames == 0 {
            bucketSamplePeaks = lastPublishedSamplePeaks
            bucketTruePeaks = lastPublishedTruePeaks
        }
        for _ in 0..<Self.reconstructionTailFrames {
            for channel in channels.indices {
                let peak = channels[channel].reconstruct(0)
                recordPeaks(channel: channel, sample: 0, reconstructed: peak)
            }
        }
        return snapshot(isFinal: true)
    }

    /// Clear numerical maxima without clearing filters, windows or the current
    /// publication bucket. Old bucket peaks cannot repopulate cleared maxima.
    mutating func clearMaxima() {
        maximumSamplePeaks = .init(repeating: 0, count: format.channelCount)
        maximumTruePeaks = maximumSamplePeaks
        maximumMomentary = nil
        maximumShortTerm = nil
    }

    private mutating func invalidate(_ error: Failure) -> Failure {
        failure = error
        return error
    }

    private mutating func recordPeaks(channel: Int, sample: Double, reconstructed: Double) {
        bucketSamplePeaks[channel] = max(bucketSamplePeaks[channel], sample)
        bucketTruePeaks[channel] = max(bucketTruePeaks[channel], reconstructed)
        maximumSamplePeaks[channel] = max(maximumSamplePeaks[channel], sample)
        maximumTruePeaks[channel] = max(maximumTruePeaks[channel], reconstructed)
    }

    private mutating func clearBucket() {
        bucketFrames = 0
        bucketEnergy = 0
        for channel in channels.indices {
            bucketSamplePeaks[channel] = 0
            bucketTruePeaks[channel] = 0
        }
    }

    private func loudness(windowBuckets: Int) -> Double {
        var power = 0.0
        for offset in 1...windowBuckets {
            power += energies[(energyIndex + energies.count - offset) % energies.count]
        }
        return power > 0 ? -0.691 + 10 * log10(power / Double(windowBuckets)) : -.infinity
    }

    private func snapshot(isFinal: Bool) -> LiveAudioMeterSnapshot {
        LiveAudioMeterSnapshot(endFrame: nextFrame, segmentStartFrame: segmentStartFrame,
            samplePeakDBFS: bucketSamplePeaks.map(Self.decibels),
            truePeakDBTP: bucketTruePeaks.map(Self.decibels), momentaryLUFS: momentary,
            shortTermLUFS: shortTerm, loudnessEndFrame: loudnessEndFrame, maximumSamplePeakDBFS: maximumSamplePeaks.map(Self.decibels),
            maximumTruePeakDBTP: maximumTruePeaks.map(Self.decibels),
            maximumMomentaryLUFS: maximumMomentary, maximumShortTermLUFS: maximumShortTerm,
            isFinal: isFinal)
    }

    private static func decibels(_ amplitude: Double) -> Double {
        amplitude > 0 ? 20 * log10(amplitude) : -.infinity
    }

    private struct Biquad: Sendable {
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1 = 0.0, z2 = 0.0
        mutating func process(_ input: Double) -> Double {
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            return output
        }
    }

    private struct Channel: Sendable {
        var shelf: Biquad
        var highPass: Biquad
        var history = [Double](repeating: 0, count: 12)
        var cursor = 0
        // ITU-R BS.1770-5 Annex 2, four columns, newest sample first.
        // Exact coefficient units are 1/8192; continuous 12-frame history.
        static let phases: [[Double]] = [
            [14, 90, -161, 272, -487, 1125, 7964, -838, 390, -218, 122, -68],
            [-239, 240, -424, 730, -1364, 3810, 6388, -1641, 832, -477, 271, -155],
            [-155, 271, -477, 832, -1641, 6388, 3810, -1364, 730, -424, 240, -239],
            [-68, 122, -218, 390, -838, 7964, 1125, -487, 272, -161, 90, 14]
        ].map { $0.map { $0 / 8192 } }

        init(sampleRate: Int) {
            // Bilinear form of the BS.1770 K-weighting stages. Parameterization
            // is documented by libebur128's ebur128_init_filter; at 48 kHz this
            // reproduces the published Annex 1 coefficients.
            let k = tan(.pi * 1681.974450955533 / Double(sampleRate))
            let q = 0.7071752369554196
            let vh = pow(10, 3.999843853973347 / 20)
            let vb = pow(vh, 0.4996667741545416)
            let a0 = 1 + k / q + k * k
            shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0,
                b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q + k * k) / a0,
                a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
            let h = tan(.pi * 38.13547087602444 / Double(sampleRate))
            let hq = 0.5003270373238773
            let h0 = 1 + h / hq + h * h
            highPass = Biquad(b0: 1, b1: -2, b2: 1,
                a1: 2 * (h * h - 1) / h0, a2: (1 - h / hq + h * h) / h0)
        }

        mutating func process(_ sample: Double) -> (energy: Double, peak: Double) {
            let filtered = highPass.process(shelf.process(sample))
            return (filtered * filtered, reconstruct(sample))
        }

        mutating func reconstruct(_ sample: Double) -> Double {
            history[cursor] = sample
            var peak = 0.0
            for phase in Self.phases {
                var value = 0.0
                for tap in 0..<12 {
                    value += phase[tap] * history[(cursor + 12 - tap) % 12]
                }
                peak = max(peak, abs(value))
            }
            cursor = (cursor + 1) % 12
            return peak
        }
    }
}
