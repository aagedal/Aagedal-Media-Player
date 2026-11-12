// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreFoundation
import Foundation

/// Consumes MPVKit's `amc-meter-history-v1` transport: up to 128 sequenced
/// records of the probe filter's output frames, each with its media interval
/// and that frame's metadata. Validation follows Aagedal Media Converter's
/// consumer. Readings aggregate every frame the clock has reached, so polling
/// gaps lose nothing while the ring keeps up. Lost, rejected or discontinuous
/// frames set `needsFilterRestart` instead of publishing incomplete maxima.
/// The clock is never qualified against physical output latency here.
nonisolated struct MPVNativeAudioMeterHistory: Sendable {
    private struct Frame: Sendable {
        let sequence: UInt64
        let raw: Data
        let start: Double
        let end: Double
        let rate: Double
        let sampleRate: UInt64
        let samples: UInt64
        let speed: Double
        let layout: String
        let measurement: MPVNativeAudioMeter.FrameMeasurement
        var history: Double = 0
    }

    private struct Snapshot: Sendable {
        let instance: UInt64
        let epoch: UInt64
        let last: UInt64
        let evicted: UInt64
        let rejected: UInt64
        let resetReason: String
        let frames: [Frame]
    }

    let channels: Int
    let sampleRate: Int
    private(set) var needsFilterRestart = false
    private(set) var restarts = 0
    /// Why history was last discarded, for diagnostics.
    private(set) var lastFailure: String?
    var bufferedFrameCount: Int { queue.count }
    private var instance: UInt64?
    private var epoch: UInt64 = 0
    private var lastSequence: UInt64 = 0
    private var evicted: UInt64 = 0
    private var rejected: UInt64 = 0
    // Only the current snapshot is cached. Ring reads repeat most records, so
    // their exact bytes permit reusing already validated frames.
    private var parsedFrames: [UInt64: Frame] = [:]
    private var queue: [Frame] = []
    private var previous: Frame?
    private var continuousMeasuredDuration = 0.0
    private var lastClock: Double?
    private var maximumSamplePeaks: [Double]
    private var measuredSamples: Int64 = 0

    init(channels: Int, sampleRate: Int) {
        self.channels = channels
        self.sampleRate = sampleRate
        maximumSamplePeaks = Array(repeating: -.infinity, count: channels)
    }

    /// After the caller reinstalled the filter: a new instance, new maxima.
    mutating func restart() {
        var fresh = Self(channels: channels, sampleRate: sampleRate)
        fresh.restarts = restarts + 1
        fresh.lastFailure = lastFailure
        self = fresh
    }

    mutating func ingest(json: String) {
        guard let snapshot = Self.decode(json, channels: channels, sampleRate: sampleRate,
            cachedInstance: instance, cachedEpoch: epoch, cachedFrames: parsedFrames) else {
            return invalidate("Invalid meter history")
        }
        let fresh = instance != snapshot.instance
        if let instance, snapshot.instance < instance { return invalidate("Retired filter instance") }
        if !fresh {
            guard snapshot.epoch >= epoch, snapshot.last >= lastSequence,
                  snapshot.evicted >= evicted, snapshot.rejected >= rejected else {
                return invalidate("Backward meter history counters")
            }
            if snapshot.epoch == epoch {
                for frame in snapshot.frames where frame.sequence <= lastSequence {
                    // decode already checked byte identity against this cache.
                    guard parsedFrames[frame.sequence] != nil else {
                        return invalidate("Changed or unrecognized repeated frame")
                    }
                }
            }
        }

        // free_graph recreates the filters and clears retained records while
        // the sequence counter stays monotonic. A first snapshot from that new
        // graph establishes a baseline; later loss still needs a new instance.
        let graphResetBaseline = fresh && snapshot.epoch > 0
            && snapshot.resetReason == "graph-reset" && snapshot.evicted == 0 && snapshot.rejected == 0
        if fresh {
            // mpv recreates user filters when the af chain changes (for example
            // channel routing). The new instance restarts ebur128 and maxima.
            if instance != nil {
                queue.removeAll()
                previous = nil
                continuousMeasuredDuration = 0
                maximumSamplePeaks = Array(repeating: -.infinity, count: channels)
                measuredSamples = 0
            }
            lastSequence = graphResetBaseline ? (snapshot.frames.first.map { $0.sequence - 1 } ?? snapshot.last) : 0
            if (snapshot.epoch != 0 && !graphResetBaseline) || snapshot.rejected != 0 {
                return invalidate("Filter history began after a discontinuity")
            }
        } else if snapshot.epoch != epoch || snapshot.rejected != rejected {
            return invalidate("Filter history discontinuity")
        }
        if snapshot.last > 0 && !(graphResetBaseline && snapshot.frames.isEmpty)
            && (snapshot.frames.isEmpty || snapshot.frames.last?.sequence != snapshot.last) {
            return invalidate("Missing trailing meter records")
        }
        instance = snapshot.instance
        epoch = snapshot.epoch
        evicted = snapshot.evicted
        rejected = snapshot.rejected

        for var frame in snapshot.frames where fresh || frame.sequence > lastSequence {
            let expected = lastSequence.addingReportingOverflow(1)
            if expected.overflow || frame.sequence != expected.partialValue {
                return invalidate("Missing received meter records")
            }
            if let previous {
                let tolerance = 0.5 / min(previous.rate, frame.rate) + 0.000002
                if previous.layout != frame.layout || previous.speed != frame.speed
                    || abs(frame.start - previous.end) > tolerance {
                    return invalidate("Discontinuous measured audio")
                }
            }
            // ebur128 windows count nominal decoded samples. Media spans can be
            // scaled by playback speed and must not warm loudness early.
            continuousMeasuredDuration += Double(frame.samples) / Double(frame.sampleRate)
            frame.history = continuousMeasuredDuration
            queue.append(frame)
            previous = frame
            lastSequence = frame.sequence
        }
        // The envelope includes rejected sequences, even when no frame was retained.
        lastSequence = snapshot.last
        parsedFrames = Dictionary(uniqueKeysWithValues: snapshot.frames.map { ($0.sequence, $0) })
        if queue.count > 256 || (queue.last.map { last in queue.first.map { last.end - $0.start > 30 } ?? false } ?? false) {
            invalidate("Unconsumed meter history exceeds bounds")
        }
    }

    /// Frames become eligible at their measured interval's end, never at
    /// receipt. A reading covers every frame that became eligible since the
    /// previous one; nil when none did or the newest is stale.
    mutating func reading(at clock: Double) -> MPVNativeAudioMeter.Reading? {
        guard clock.isFinite, !needsFilterRestart else { return nil }
        if let lastClock, clock < lastClock - 0.000002 {
            invalidate("Presentation clock rewound")
            return nil
        }
        lastClock = clock
        // Serialized frame times carry float rounding (0.2 + 0.1 > 0.3).
        let count = queue.prefix { $0.end <= clock + 0.000002 }.count
        guard count > 0 else { return nil }
        let due = queue[..<count]
        queue.removeFirst(count)
        var peaks = Array(repeating: -Double.infinity, count: channels)
        var energy = Array(repeating: 0.0, count: channels)
        var samples: UInt64 = 0
        for frame in due {
            for channel in 0..<channels {
                peaks[channel] = max(peaks[channel], frame.measurement.samplePeaks[channel])
                // astats RMS is per frame (reset=1); weight its power by length.
                energy[channel] += pow(10, frame.measurement.rms[channel] / 10) * Double(frame.samples)
            }
            samples += frame.samples
        }
        for channel in 0..<channels {
            maximumSamplePeaks[channel] = max(maximumSamplePeaks[channel], peaks[channel])
        }
        measuredSamples += Int64(samples)
        guard let newest = due.last else { return nil }
        let freshness = max(0.2, min(1, 2 * (newest.end - newest.start)))
        guard clock - newest.end <= freshness else { return nil }
        let rms = energy.map { $0 > 0 ? 10 * log10($0 / Double(samples)) : -Double.infinity }
        return .init(samplePeaks: peaks, rms: rms, maximumSamplePeaks: maximumSamplePeaks,
                     truePeaks: newest.measurement.truePeaks,
                     momentary: newest.history >= 0.4 - 0.000002 ? newest.measurement.momentary : nil,
                     shortTerm: newest.history >= 3 - 0.000002 ? newest.measurement.shortTerm : nil,
                     filterFrames: measuredSamples, measuredUntil: newest.end,
                     frameCount: count, historyRestarts: restarts)
    }

    private mutating func invalidate(_ reason: String) {
        queue.removeAll()
        previous = nil
        continuousMeasuredDuration = 0
        needsFilterRestart = true
        lastFailure = reason
    }

    private static func integer(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
        return UInt64(number.stringValue)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func decode(_ json: String, channels: Int, sampleRate: Int, cachedInstance: UInt64?,
        cachedEpoch: UInt64, cachedFrames: [UInt64: Frame]) -> Snapshot? {
        guard json.utf8.count <= 3 * 1024 * 1024,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(object["schema-version"]) == 1,
              let instance = integer(object["instance"]), instance > 0,
              let epoch = integer(object["epoch"]),
              let last = integer(object["last-sequence"]),
              let evicted = integer(object["evicted"]), let rejected = integer(object["rejected"]),
              integer(object["capacity"]) == 128,
              let reason = object["reset-reason"] as? String, reason.utf8.count <= 1024,
              let records = object["frames"] as? [[String: Any]], records.count <= 128,
              evicted <= last, rejected <= last - evicted else { return nil }
        var frames: [Frame] = []
        frames.reserveCapacity(records.count)
        let canReuse = instance == cachedInstance && epoch == cachedEpoch
        for record in records {
            guard let sequence = integer(record["sequence"]), sequence > 0, sequence <= last,
                  frames.last.map({ sequence > $0.sequence }) ?? true,
                  let raw = record["frame"] as? String, raw.utf8.count <= 16 * 1024,
                  let bytes = raw.data(using: .utf8) else { return nil }
            if canReuse, let cached = cachedFrames[sequence] {
                guard cached.raw == bytes else { return nil }
                frames.append(cached)
                continue
            }
            guard let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let valid = value["valid-time"] as? NSNumber,
                  CFGetTypeID(valid) == CFBooleanGetTypeID(), valid.boolValue,
                  let start = number(value["start"]), let end = number(value["end"]), end > start,
                  let rate = number(value["effective-rate"]), rate > 0,
                  let speed = number(value["speed"]), speed > 0,
                  (rate * speed).isFinite, (rate + speed).isFinite,
                  let frameRate = integer(value["sample-rate"]), frameRate == UInt64(sampleRate),
                  let samples = integer(value["samples"]), samples > 0, samples <= UInt64(Int32.max),
                  let layout = value["layout"] as? String, !layout.isEmpty, layout.utf8.count <= 1024,
                  let metadata = value["metadata"] as? [String: String], metadata.count <= 512,
                  end - start <= 30,
                  abs((end - start) - Double(samples) / rate) <= 0.5 / rate + 0.000002,
                  // Both factors are serialized to six decimals by MPV. Their
                  // rounding errors matter especially for very small speeds.
                  abs(rate * speed - Double(frameRate)) <= (rate + speed) * 0.0000005 + 0.000002,
                  let measurement = MPVNativeAudioMeter.decodeFrame(metadata, channels: channels)
            else { return nil }
            frames.append(Frame(sequence: sequence, raw: bytes, start: start, end: end, rate: rate,
                sampleRate: frameRate, samples: samples, speed: speed, layout: layout,
                measurement: measurement))
        }
        return Snapshot(instance: instance, epoch: epoch, last: last, evicted: evicted, rejected: rejected,
            resetReason: reason, frames: frames)
    }
}
