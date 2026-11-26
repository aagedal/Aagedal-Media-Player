// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Low-level CoreMediaIO sink stream driver. Manages exclusive device control,
// format negotiation, frame-cadence pacing, preroll, SMPTE timecode attachment,
// and clean hardware teardown without any proprietary vendor SDK.

import CoreAudioTypes
import CoreMedia
@preconcurrency import CoreMediaIO
@preconcurrency import CoreMediaIO.CMIOSampleBuffer
import CoreVideo
import Foundation
import OSLog
import os

nonisolated enum CMIOCleanfeedSinkError: Error, LocalizedError, Sendable {
    case formatUnavailable
    case deviceControlDenied(OSStatus)
    case formatSelectionFailed(OSStatus)
    case frameRateSelectionFailed(OSStatus)
    case bufferQueueUnavailable(OSStatus)
    case streamStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .formatUnavailable:
            "The selected video format is no longer advertised by the output device."
        case .deviceControlDenied(let status):
            "Could not claim exclusive control of the output device (status \(status)). Another app such as DaVinci Resolve may be using it."
        case .formatSelectionFailed(let status):
            "The output device rejected the selected video format (status \(status))."
        case .frameRateSelectionFailed(let status):
            "The output device rejected the selected frame rate (status \(status))."
        case .bufferQueueUnavailable(let status):
            "Could not open the CoreMediaIO output buffer queue (status \(status))."
        case .streamStartFailed(let status):
            "Could not start the output video stream (status \(status)). Check that no other app is holding the device."
        }
    }
}

nonisolated struct CMIOCleanfeedStats: Sendable, Equatable {
    var framesSent: UInt64 = 0
    var framesScheduled: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var underrunCount: UInt32 = 0
}

nonisolated struct CMIOCleanfeedStartResult: Sendable, Equatable {
    let generation: UInt64
    let negotiatedFrameRate: Double
}

/// Drives a single CoreMediaIO output/sink stream (`kCMIOStreamPropertyDirection == 0`)
/// at a steady broadcast frame cadence.
nonisolated final class CMIOCleanfeedSink: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "CleanfeedSink")

    private struct FrameSlot: @unchecked Sendable {
        var generation: UInt64 = 0
        var expectedWidth: Int = 0
        var expectedHeight: Int = 0
        var expectedPixelFormat: OSType = 0
        var pixelBuffer: CVPixelBuffer?
        var smpteTime: SMPTETime?
    }

    private struct MetricsState {
        var framesSent: UInt64 = 0
        var framesScheduled: UInt64 = 0
        var droppedFrames: UInt64 = 0
    }

    private let pumpQueue = DispatchQueue(label: "com.aagedal.MediaPlayer.cleanfeed.sink", qos: .userInteractive)
    private let latestFrameLock = OSAllocatedUnfairLock(initialState: FrameSlot())
    private let metricsLock = OSAllocatedUnfairLock(initialState: MetricsState())

    private var activeDevice: CMIOOutputDevice?
    private var activeSelection: CMIOOutputFormatSelection?
    private var negotiatedFrameRate: Double = 25.0
    private var streamGeneration: UInt64 = 0
    private var bufferQueue: CMSimpleQueue?
    private var streamFormatDescription: CMFormatDescription?
    private var fallbackBlackBuffer: CVPixelBuffer?
    private var frameDuration: CMTime = CMTime(value: 1, timescale: 25)
    private var sequenceNumber: UInt64 = 0
    private var pumpTimer: DispatchSourceTimer?
    private var targetQueueDepth: Int = 4
    private var isRunning = false
    private var callbackContext: UnsafeMutableRawPointer?

    var onStatsUpdated: (@Sendable (CMIOCleanfeedStats) -> Void)?

    deinit {
        stop()
    }

    /// Starts streaming to `device` using `selection`. Call `submitFrame(_:smpteTime:generation:)`
    /// whenever a new converted `CVPixelBuffer` is ready; until the first video frame
    /// arrives (and whenever playback is paused), the sink repeats the latest frame
    /// (or broadcast black) to keep the SDI/HDMI output continuously locked.
    @discardableResult
    func start(
        device: CMIOOutputDevice,
        selection: CMIOOutputFormatSelection,
        initialFrame: CVPixelBuffer?
    ) throws -> CMIOCleanfeedStartResult {
        stop()

        guard let liveFormatDescription = CMIOOutputDeviceDiscovery.copyFormatDescription(
            streamID: device.streamID,
            at: selection.format.index
        ) else {
            throw CMIOCleanfeedSinkError.formatUnavailable
        }

        // Claim exclusive device control (modern replacement for DeviceMaster).
        var pid = getpid()
        var controlAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceControl),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let controlStatus = CMIOObjectSetPropertyData(
            device.deviceID,
            &controlAddress,
            0,
            nil,
            UInt32(MemoryLayout<pid_t>.size),
            &pid
        )
        if controlStatus != noErr {
            throw CMIOCleanfeedSinkError.deviceControlDenied(controlStatus)
        }

        // Configure output format description.
        var formatAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescription),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var formatRef: CMFormatDescription = liveFormatDescription
        let formatStatus = withUnsafePointer(to: &formatRef) { ptr in
            CMIOObjectSetPropertyData(
                device.streamID,
                &formatAddress,
                0,
                nil,
                UInt32(MemoryLayout<CMFormatDescription>.size),
                ptr
            )
        }
        guard formatStatus == noErr else {
            releaseDeviceControl(deviceID: device.deviceID)
            throw CMIOCleanfeedSinkError.formatSelectionFailed(formatStatus)
        }

        // Configure output frame rate (and minimum frame rate in safe order so
        // drivers that enforce minRate <= maxRate accept both down-steps and up-steps).
        let rateStatus = configureStreamFrameRate(streamID: device.streamID, targetFPS: selection.frameRate)
        guard rateStatus == noErr else {
            releaseDeviceControl(deviceID: device.deviceID)
            throw CMIOCleanfeedSinkError.frameRateSelectionFailed(rateStatus)
        }

        // Read back the device's actual active frame rate. Some CMIO extensions
        // (such as BlackmagicCameraExtension 16.5) accept FrameRate writes with
        // noErr yet keep a hardware-locked rate (e.g. 29.97 at 1080p/2160p or
        // 50 at 720p). Pacing the sink to the actual active rate prevents queue
        // underruns and reports the true signal rate in the UI.
        let actualFPS: Double
        if let reported = readStreamFrameRate(streamID: device.streamID),
           reported.isFinite, reported > 0,
           abs(reported - selection.frameRate) >= 0.05 {
            Self.logger.warning(
                "Output device \(device.name) kept frame rate \(reported, format: .fixed(precision: 3)) fps instead of requested \(selection.frameRate, format: .fixed(precision: 3)) fps"
            )
            actualFPS = reported
        } else {
            actualFPS = selection.frameRate
        }

        // Retain self for C callbacks until stop() unregisters them.
        let ctx = Unmanaged.passRetained(self).toOpaque()
        callbackContext = ctx

        // Register scheduled output callback for hardware presentation metrics.
        var schedProc = CMIOStreamScheduledOutputNotificationProcAndRefCon(
            scheduledOutputNotificationProc: Self.scheduledOutputCallback,
            scheduledOutputNotificationRefCon: ctx
        )
        var schedAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyScheduledOutputNotificationProc),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        _ = CMIOObjectSetPropertyData(
            device.streamID,
            &schedAddress,
            0,
            nil,
            UInt32(MemoryLayout<CMIOStreamScheduledOutputNotificationProcAndRefCon>.size),
            &schedProc
        )

        // Acquire the CMIO sink buffer queue and drain any leftover buffers from
        // a previous resolution/format before starting the stream.
        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let queueStatus = CMIOStreamCopyBufferQueue(
            device.streamID,
            Self.queueAlteredCallback,
            ctx,
            &unmanagedQueue
        )
        guard queueStatus == noErr, let queue = unmanagedQueue?.takeRetainedValue() else {
            unregisterCallbacks(streamID: device.streamID)
            releaseDeviceControl(deviceID: device.deviceID)
            throw CMIOCleanfeedSinkError.bufferQueueUnavailable(queueStatus)
        }
        Self.drainQueue(queue)

        // Start hardware output stream.
        let startStatus = CMIODeviceStartStream(device.deviceID, device.streamID)
        guard startStatus == noErr else {
            unregisterCallbacks(streamID: device.streamID)
            releaseDeviceControl(deviceID: device.deviceID)
            throw CMIOCleanfeedSinkError.streamStartFailed(startStatus)
        }

        let rate = TimecodeRate(frameRate: actualFPS)
        let duration = CMTime(value: rate.denominator, timescale: CMTimeScale(rate.numerator))
        let capacity = Int(CMSimpleQueueGetCapacity(queue))
        let startupPreroll = max(device.outputBuffersRequiredForStartup, 3)

        let startedGeneration: UInt64 = pumpQueue.sync {
            self.streamGeneration &+= 1
            let gen = self.streamGeneration
            self.activeDevice = device
            self.activeSelection = selection
            self.negotiatedFrameRate = actualFPS
            self.bufferQueue = queue
            self.streamFormatDescription = liveFormatDescription
            let validatedInitial = initialFrame.flatMap {
                Self.pixelBufferMatches(
                    $0,
                    width: selection.format.width,
                    height: selection.format.height,
                    pixelFormat: selection.format.pixelFormat
                ) ? $0 : nil
            }
            self.fallbackBlackBuffer = validatedInitial
            self.frameDuration = duration
            self.sequenceNumber = 0
            self.targetQueueDepth = min(max(capacity - 1, 2), max(startupPreroll + 1, 4))
            self.isRunning = true

            let initialSlot = FrameSlot(
                generation: gen,
                expectedWidth: selection.format.width,
                expectedHeight: selection.format.height,
                expectedPixelFormat: selection.format.pixelFormat,
                pixelBuffer: validatedInitial,
                smpteTime: nil
            )
            self.latestFrameLock.withLock {
                $0 = initialSlot
            }
            self.metricsLock.withLock {
                $0 = MetricsState()
            }

            // Enqueue startup preroll frames immediately so the device locks cleanly.
            for _ in 0..<min(startupPreroll + 1, max(capacity, 1)) {
                self.enqueueNextFrameLocked()
            }

            let intervalNs = max(Int64((1_000_000_000.0 / max(actualFPS, 1.0)).rounded()), 1_000_000)
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: self.pumpQueue)
            timer.schedule(
                deadline: .now() + .nanoseconds(Int(intervalNs)),
                repeating: .nanoseconds(Int(intervalNs)),
                leeway: .microseconds(500)
            )
            timer.setEventHandler { [weak self] in
                self?.pumpTickLocked()
            }
            self.pumpTimer = timer
            timer.resume()
            return gen
        }

        Self.logger.info("Started cleanfeed sink on \(device.name): \(selection.summaryLabel(actualFrameRate: actualFPS))")
        return CMIOCleanfeedStartResult(generation: startedGeneration, negotiatedFrameRate: actualFPS)
    }

    private struct PixelBufferBox: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    /// Submits the latest converted frame to the active stream. Rejects buffers
    /// from an old stream generation or whose dimensions/pixel format do not
    /// match the negotiated stream format (preventing stale Metal completions
    /// from injecting previous-resolution frames after a live resolution switch).
    @discardableResult
    func submitFrame(
        _ pixelBuffer: CVPixelBuffer,
        smpteTime: SMPTETime? = nil,
        generation expectedGeneration: UInt64? = nil
    ) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let box = PixelBufferBox(value: pixelBuffer)
        return latestFrameLock.withLock { slot in
            if let expectedGeneration, expectedGeneration != slot.generation {
                return false
            }
            guard slot.expectedWidth > 0,
                  slot.expectedHeight > 0,
                  width == slot.expectedWidth,
                  height == slot.expectedHeight,
                  pixelFormat == slot.expectedPixelFormat else {
                return false
            }
            slot.pixelBuffer = box.value
            slot.smpteTime = smpteTime
            return true
        }
    }

    /// Exposed for deterministic unit testing of pixel-buffer format matching.
    nonisolated static func pixelBufferMatches(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        pixelFormat: OSType
    ) -> Bool {
        CVPixelBufferGetWidth(pixelBuffer) == width
            && CVPixelBufferGetHeight(pixelBuffer) == height
            && CVPixelBufferGetPixelFormatType(pixelBuffer) == pixelFormat
    }

    func currentStats() -> CMIOCleanfeedStats {
        let m = metricsLock.withLock { $0 }
        let underruns: UInt32
        if let streamID = activeDevice?.streamID {
            underruns = CMIOOutputDeviceDiscovery.readUInt32Property(
                streamID,
                selector: kCMIOStreamPropertyOutputBufferUnderrunCount
            ) ?? 0
        } else {
            underruns = 0
        }
        return CMIOCleanfeedStats(
            framesSent: m.framesSent,
            framesScheduled: m.framesScheduled,
            droppedFrames: m.droppedFrames,
            underrunCount: underruns
        )
    }

    func stop() {
        var deviceToStop: CMIOOutputDevice?
        var queueToDrain: CMSimpleQueue?
        pumpQueue.sync {
            guard self.isRunning || self.activeDevice != nil else { return }
            self.isRunning = false
            self.streamGeneration &+= 1
            let nextGen = self.streamGeneration
            self.pumpTimer?.cancel()
            self.pumpTimer = nil
            deviceToStop = self.activeDevice
            queueToDrain = self.bufferQueue
            self.activeDevice = nil
            self.activeSelection = nil
            self.bufferQueue = nil
            self.streamFormatDescription = nil
            self.fallbackBlackBuffer = nil
            self.latestFrameLock.withLock {
                $0 = FrameSlot(generation: nextGen)
            }
        }

        if let device = deviceToStop {
            _ = CMIODeviceStopStream(device.deviceID, device.streamID)
            if let queueToDrain {
                // Drain all queued CMSampleBuffers from the previous format so
                // restarting at a different resolution starts with a clean queue.
                Self.drainQueue(queueToDrain)
            }
            unregisterCallbacks(streamID: device.streamID)
            releaseDeviceControl(deviceID: device.deviceID)
            Self.logger.info("Stopped cleanfeed sink on \(device.name)")
        } else if let ctx = callbackContext {
            callbackContext = nil
            Unmanaged<CMIOCleanfeedSink>.fromOpaque(ctx).release()
        }
    }

    private func configureStreamFrameRate(streamID: CMIOStreamID, targetFPS: Double) -> OSStatus {
        var rateAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFrameRate),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var minRateAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyMinimumFrameRate),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let hasMinRate = CMIOObjectHasProperty(streamID, &minRateAddress)
        var minSettable: DarwinBoolean = false
        if hasMinRate {
            _ = CMIOObjectIsPropertySettable(streamID, &minRateAddress, &minSettable)
        }

        let currentFPS = readStreamFrameRate(streamID: streamID)
        var fps = Float64(targetFPS)

        if minSettable.boolValue, let currentFPS, targetFPS < currentFPS {
            _ = CMIOObjectSetPropertyData(streamID, &minRateAddress, 0, nil, UInt32(MemoryLayout<Float64>.size), &fps)
        }
        let rateStatus = CMIOObjectSetPropertyData(
            streamID,
            &rateAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &fps
        )
        if rateStatus == noErr, minSettable.boolValue {
            _ = CMIOObjectSetPropertyData(streamID, &minRateAddress, 0, nil, UInt32(MemoryLayout<Float64>.size), &fps)
        }
        return rateStatus
    }

    private func readStreamFrameRate(streamID: CMIOStreamID) -> Double? {
        var rateAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFrameRate),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(streamID, &rateAddress) else { return nil }
        var fps: Float64 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            streamID,
            &rateAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &used,
            &fps
        )
        return status == noErr && fps.isFinite && fps > 0 ? fps : nil
    }

    private static func drainQueue(_ queue: CMSimpleQueue) {
        while let raw = CMSimpleQueueDequeue(queue) {
            Unmanaged<CMSampleBuffer>.fromOpaque(raw).release()
        }
    }

    // MARK: - Pump Loop (pumpQueue)

    private func pumpTickLocked() {
        guard isRunning, let queue = bufferQueue else { return }
        let currentCount = Int(CMSimpleQueueGetCount(queue))
        let capacity = Int(CMSimpleQueueGetCapacity(queue))
        if currentCount >= capacity {
            metricsLock.withLock { $0.droppedFrames += 1 }
            return
        }

        // Keep the sink fed up to targetQueueDepth without bursting too far ahead.
        let needed = max(1, targetQueueDepth - currentCount)
        let framesToPush = min(needed, capacity - currentCount, 2)
        for _ in 0..<framesToPush {
            enqueueNextFrameLocked()
        }

        if sequenceNumber % 15 == 0, let callback = onStatsUpdated {
            let stats = currentStats()
            callback(stats)
        }
    }

    private func enqueueNextFrameLocked() {
        guard isRunning, let queue = bufferQueue else { return }
        let slot = latestFrameLock.withLock { $0 }
        guard let pixelBuffer = slot.pixelBuffer ?? fallbackBlackBuffer else { return }

        var frameFormatDescription: CMVideoFormatDescription?
        let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &frameFormatDescription
        )
        guard fmtStatus == noErr, let frameFormatDescription else { return }

        // Stream-relative 0-based PTS matches BlackmagicCameraExtension's
        // scheduled playback timeline (using host uptime causes hardware to wait).
        let pts = CMTime(
            value: Int64(sequenceNumber) * frameDuration.value,
            timescale: frameDuration.timescale
        )
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var unmanagedSample: Unmanaged<CMSampleBuffer>?
        let createStatus = CMIOSampleBufferCreateForImageBuffer(
            kCFAllocatorDefault,
            pixelBuffer,
            frameFormatDescription,
            &timing,
            sequenceNumber,
            UInt32(kCMIOSampleBufferNoDiscontinuities),
            &unmanagedSample
        )
        guard createStatus == noErr, let unmanagedSample else {
            metricsLock.withLock { $0.droppedFrames += 1 }
            return
        }

        if var smpte = slot.smpteTime {
            let sample = unmanagedSample.takeUnretainedValue()
            let data = withUnsafeBytes(of: &smpte) { bytes in
                CFDataCreate(kCFAllocatorDefault, bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
            }
            if let data,
               let smpteKey = kCMIOSampleBufferAttachmentKey_SMPTETime?.takeUnretainedValue() {
                CMSetAttachment(
                    sample,
                    key: smpteKey,
                    value: data,
                    attachmentMode: kCMAttachmentMode_ShouldPropagate
                )
            }
        }

        // CMSimpleQueue takes ownership of the retained CMSampleBuffer reference.
        let enqueueStatus = CMSimpleQueueEnqueue(queue, element: unmanagedSample.toOpaque())
        if enqueueStatus == noErr {
            sequenceNumber += 1
            metricsLock.withLock { $0.framesSent += 1 }
        } else {
            unmanagedSample.release()
            metricsLock.withLock { $0.droppedFrames += 1 }
        }
    }

    // MARK: - C Callbacks & Teardown Helpers

    private static let queueAlteredCallback: CMIODeviceStreamQueueAlteredProc = { _, _, _ in
        // Queue consumption is tracked via CMSimpleQueueGetCount on pumpQueue.
    }

    private static let scheduledOutputCallback: CMIOStreamScheduledOutputNotificationProc = { _, _, refCon in
        guard let refCon else { return }
        let sink = Unmanaged<CMIOCleanfeedSink>.fromOpaque(refCon).takeUnretainedValue()
        sink.metricsLock.withLock { $0.framesScheduled += 1 }
    }

    private func unregisterCallbacks(streamID: CMIOStreamID) {
        var schedProc = CMIOStreamScheduledOutputNotificationProcAndRefCon(
            scheduledOutputNotificationProc: nil,
            scheduledOutputNotificationRefCon: nil
        )
        var schedAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyScheduledOutputNotificationProc),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        _ = CMIOObjectSetPropertyData(
            streamID,
            &schedAddress,
            0,
            nil,
            UInt32(MemoryLayout<CMIOStreamScheduledOutputNotificationProcAndRefCon>.size),
            &schedProc
        )

        var unusedQueue: Unmanaged<CMSimpleQueue>?
        _ = CMIOStreamCopyBufferQueue(streamID, nil, nil, &unusedQueue)
        unusedQueue?.release()

        if let ctx = callbackContext {
            callbackContext = nil
            Unmanaged<CMIOCleanfeedSink>.fromOpaque(ctx).release()
        }
    }

    private func releaseDeviceControl(deviceID: CMIODeviceID) {
        var releasePID: pid_t = -1
        var controlAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceControl),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        _ = CMIOObjectSetPropertyData(
            deviceID,
            &controlAddress,
            0,
            nil,
            UInt32(MemoryLayout<pid_t>.size),
            &releasePID
        )
    }
}
