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

/// Drives a single CoreMediaIO output/sink stream (`kCMIOStreamPropertyDirection == 0`)
/// at a steady broadcast frame cadence.
nonisolated final class CMIOCleanfeedSink: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "CleanfeedSink")

    private struct FrameSlot: @unchecked Sendable {
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

    /// Starts streaming to `device` using `selection`. Call `submitFrame(_:smpteTime:)`
    /// whenever a new converted `CVPixelBuffer` is ready; until the first video frame
    /// arrives (and whenever playback is paused), the sink repeats the latest frame
    /// (or broadcast black) to keep the SDI/HDMI output continuously locked.
    func start(
        device: CMIOOutputDevice,
        selection: CMIOOutputFormatSelection,
        initialFrame: CVPixelBuffer?
    ) throws {
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

        // Configure output frame rate.
        var rateAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFrameRate),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var fps = Float64(selection.frameRate)
        let rateStatus = CMIOObjectSetPropertyData(
            device.streamID,
            &rateAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &fps
        )
        guard rateStatus == noErr else {
            releaseDeviceControl(deviceID: device.deviceID)
            throw CMIOCleanfeedSinkError.frameRateSelectionFailed(rateStatus)
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

        // Acquire the CMIO sink buffer queue.
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

        // Start hardware output stream.
        let startStatus = CMIODeviceStartStream(device.deviceID, device.streamID)
        guard startStatus == noErr else {
            unregisterCallbacks(streamID: device.streamID)
            releaseDeviceControl(deviceID: device.deviceID)
            throw CMIOCleanfeedSinkError.streamStartFailed(startStatus)
        }

        let rate = TimecodeRate(frameRate: selection.frameRate)
        let duration = CMTime(value: rate.denominator, timescale: CMTimeScale(rate.numerator))
        let capacity = Int(CMSimpleQueueGetCapacity(queue))
        let startupPreroll = max(device.outputBuffersRequiredForStartup, 3)

        pumpQueue.sync {
            self.activeDevice = device
            self.activeSelection = selection
            self.bufferQueue = queue
            self.streamFormatDescription = liveFormatDescription
            self.fallbackBlackBuffer = initialFrame
            self.frameDuration = duration
            self.sequenceNumber = 0
            self.targetQueueDepth = min(max(capacity - 1, 2), max(startupPreroll + 1, 4))
            self.isRunning = true

            let initialSlot = FrameSlot(pixelBuffer: initialFrame, smpteTime: nil)
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

            let intervalNs = max(Int64((1_000_000_000.0 / max(selection.frameRate, 1.0)).rounded()), 1_000_000)
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
        }

        Self.logger.info("Started cleanfeed sink on \(device.name): \(selection.summaryLabel)")
    }

    func submitFrame(_ pixelBuffer: CVPixelBuffer, smpteTime: SMPTETime? = nil) {
        let slot = FrameSlot(pixelBuffer: pixelBuffer, smpteTime: smpteTime)
        latestFrameLock.withLock {
            $0 = slot
        }
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
        pumpQueue.sync {
            guard self.isRunning || self.activeDevice != nil else { return }
            self.isRunning = false
            self.pumpTimer?.cancel()
            self.pumpTimer = nil
            deviceToStop = self.activeDevice
            self.activeDevice = nil
            self.activeSelection = nil
            self.bufferQueue = nil
            self.streamFormatDescription = nil
            self.fallbackBlackBuffer = nil
            self.latestFrameLock.withLock {
                $0.pixelBuffer = nil
                $0.smpteTime = nil
            }
        }

        if let device = deviceToStop {
            _ = CMIODeviceStopStream(device.deviceID, device.streamID)
            unregisterCallbacks(streamID: device.streamID)
            releaseDeviceControl(deviceID: device.deviceID)
            Self.logger.info("Stopped cleanfeed sink on \(device.name)")
        } else if let ctx = callbackContext {
            callbackContext = nil
            Unmanaged<CMIOCleanfeedSink>.fromOpaque(ctx).release()
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
