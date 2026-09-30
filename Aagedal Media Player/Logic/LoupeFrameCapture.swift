// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Combine
import CoreImage

/// A stopped session retains its occupied slot until the worker returns. A rapid
/// close/reopen must not start a second screenshot behind an uncancellable one.
nonisolated struct LoupeCaptureGate {
    private(set) var generation: UInt64 = 0
    private(set) var inFlight: UInt64?
    private(set) var isRunning = false
    private var sequence: UInt64 = 0
    private var inFlightGeneration: UInt64?

    mutating func start() { generation &+= 1; isRunning = true }
    mutating func stop() { generation &+= 1; isRunning = false }
    mutating func begin() -> UInt64? {
        guard isRunning, inFlight == nil else { return nil }
        sequence &+= 1
        inFlight = sequence
        inFlightGeneration = generation
        return sequence
    }
    mutating func complete(_ token: UInt64) -> Bool {
        guard inFlight == token else { return false }
        inFlight = nil
        let canPublish = isRunning && inFlightGeneration == generation
        inFlightGeneration = nil
        return canPublish
    }
}

/// Captures the active decoder only while a loupe is visible. It owns a separate
/// AV output and never starts/stops, borrows, or removes the scope's outputs.
@MainActor
final class LoupeFrameCapture: ObservableObject {
    @Published private(set) var image: CGImage?

    private weak var controller: PlayerController?
    private var timer: Timer?
    private var observation: AnyCancellable?
    private var gate = LoupeCaptureGate()
    private var lastCaptureStartedAt: TimeInterval = -.infinity
    private var source: SourceIdentity?
    private var verifiedAVRasterSource: SourceIdentity?
    private var attachedItem: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?

    private struct SourceIdentity: Equatable {
        let preparationID: Int
        let backend: ObjectIdentifier
        // An item can keep its identity while changing the track feeding its
        // video output. Such a change invalidates both the image and its proof.
        let enabledVideoTracks: [CMPersistentTrackID]
        let videoComposition: ObjectIdentifier?
    }

    /// Dimensions alone do not identify a decoded raster: an old MPV preview
    /// can have the same dimensions as a newly selected AV source. Require the
    /// image to have come from the still-current AV player item.
    func hasVerifiedAVRaster(for controller: PlayerController) -> Bool {
        guard self.controller === controller, image != nil,
              controller.isReady, !controller.useMPV,
              let item = controller.player?.currentItem, item.status == .readyToPlay else { return false }
        let current = avSourceIdentity(controller: controller, item: item)
        return source == current && verifiedAVRasterSource == current
    }

    func start(controller: PlayerController) {
        if self.controller === controller, gate.isRunning {
            refreshSource()
            return
        }
        stop()
        self.controller = controller
        gate.start()
        // Published changes are announced before mutation; defer the read until
        // the mutation has landed, then reject obsolete images immediately.
        observation = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSource() }
        }
        refreshSource()
        let generation = gate.generation
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.gate.generation == generation else { return }
                self.capture()
            }
        }
        // Keep previews refreshing while AppKit tracks scrubbing or slider drags.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        capture()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observation = nil
        gate.stop()
        detachOutput()
        source = nil
        verifiedAVRasterSource = nil
        controller = nil
        image = nil
    }

    private func currentSource() -> SourceIdentity? {
        guard let controller, controller.isReady else { return nil }
        if controller.useMPV, let mpv = controller.mpvPlayer {
            return SourceIdentity(preparationID: controller.preparationID, backend: ObjectIdentifier(mpv),
                                  enabledVideoTracks: [], videoComposition: nil)
        }
        if let item = controller.player?.currentItem, item.status == .readyToPlay {
            return avSourceIdentity(controller: controller, item: item)
        }
        return nil
    }

    private func avSourceIdentity(controller: PlayerController, item: AVPlayerItem) -> SourceIdentity {
        SourceIdentity(
            preparationID: controller.preparationID, backend: ObjectIdentifier(item),
            enabledVideoTracks: Self.enabledVideoTracks(in: item).map(\.trackID),
            videoComposition: item.videoComposition.map(ObjectIdentifier.init)
        )
    }

    private static func enabledVideoTracks(in item: AVPlayerItem) -> [AVAssetTrack] {
        item.tracks.compactMap { itemTrack in
            guard itemTrack.isEnabled, let track = itemTrack.assetTrack,
                  track.mediaType == .video else { return nil }
            return track
        }
    }

    /// The asset's first video track need not be the one supplying the output.
    /// A video composition applies its own display geometry. Multiple enabled
    /// tracks cannot supply an unambiguous source transform. AVCompositionTrack
    /// still supplies preview geometry here, but the worker rejects its proof.
    static func sourceVideoTrack(in item: AVPlayerItem) -> AVAssetTrack? {
        guard item.videoComposition == nil else { return nil }
        let tracks = enabledVideoTracks(in: item)
        return tracks.count == 1 ? tracks[0] : nil
    }

    private func refreshSource() {
        guard gate.isRunning else { return }
        let latest = currentSource()
        guard latest != source else { return }
        detachOutput()
        image = nil
        verifiedAVRasterSource = nil
        source = latest
        if latest != nil, let controller, !controller.useMPV,
           let item = controller.player?.currentItem {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            item.add(output)
            attachedItem = item
            self.output = output
        }
    }

    private func detachOutput() {
        if let attachedItem, let output { attachedItem.remove(output) }
        attachedItem = nil
        output = nil
    }

    private func capture() {
        refreshSource()
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureStartedAt >= 0.1,
              let controller, let source, let token = gate.begin() else { return }
        lastCaptureStartedAt = now
        let request: Request
        let isAVRaster: Bool
        if controller.useMPV, let mpv = controller.mpvPlayer {
            request = .mpv(mpv)
            isAVRaster = false
        } else if let item = attachedItem, let output, let player = controller.player {
            // Acquire the frame while its playback timestamp is current. At
            // production resolutions, a worker hop and metadata awaits can let
            // that frame age out of the output before it is copied.
            guard let buffer = output.copyPixelBuffer(
                forItemTime: player.currentTime(), itemTimeForDisplay: nil
            ) else {
                _ = gate.complete(token)
                return
            }
            let track = Self.sourceVideoTrack(in: item)
            // Composition tracks can concatenate different coded formats and
            // display matrices. Their nominal format is insufficient evidence
            // about the segment that produced this buffer.
            let canVerify = !(item.asset is AVComposition) && !(track is AVCompositionTrack)
            request = .av(track, buffer, canVerify: canVerify)
            isAVRaster = true
        } else {
            _ = gate.complete(token)
            return
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                await Self.makeImage(request)
            }.value
            guard let self else { return }
            let canPublish = self.gate.complete(token)
            guard canPublish, self.source == source, self.currentSource() == source else { return }
            if let result {
                self.verifiedAVRasterSource = isAVRaster && result.preservesSourcePixels ? source : nil
                self.image = result.image
            }
        }
    }

    // The main actor acquires the AV buffer at the current playback timestamp.
    // The worker retains that immutable snapshot and its selected track until conversion
    // completes; all output attachment and removal remain on MainActor.
    private nonisolated enum Request: @unchecked Sendable {
        case mpv(MPVPlayer)
        case av(AVAssetTrack?, CVPixelBuffer, canVerify: Bool)
    }

    private nonisolated struct CapturedImage {
        let image: CGImage
        let preservesSourcePixels: Bool
    }

    private nonisolated static let context = CIContext(options: [.cacheIntermediates: false])

    private nonisolated static func makeImage(_ request: Request) async -> CapturedImage? {
        switch request {
        case .mpv(let mpv):
            guard let raw = mpv.screenshotRaw() else { return nil }
            guard let image = image(from: raw) else { return nil }
            return CapturedImage(image: image, preservesSourcePixels: false)
        case .av(let track, let buffer, let canVerify):
            // A composition has already applied its own geometry to the output;
            // do not apply an unrelated first-track matrix a second time.
            let transform: CGAffineTransform
            let format: CMFormatDescription?
            if let track {
                guard let preferred = try? await track.load(.preferredTransform) else { return nil }
                transform = preferred
                let formats = try? await track.load(.formatDescriptions)
                // Several coded descriptions can represent changing raster
                // formats. Output does not identify which description supplied
                // this frame, so keep native-pixel verification conservative.
                format = formats?.count == 1 ? formats?.first : nil
            } else {
                transform = .identity
                format = nil
            }
            // Preferred transform supplies container rotation/mirroring. Keep
            // the full oriented raster; the UI applies display aspect (PAR).
            let decoded = CIImage(cvPixelBuffer: buffer)
            let oriented = decoded.transformed(by: coreImageTransform(transform))
            guard let image = context.createCGImage(oriented, from: oriented.extent) else { return nil }
            // The negotiated output can differ from the track's coded raster.
            // Check the buffer before any display transform, independently of
            // cached UI metadata and the final image's oriented dimensions.
            let fullBufferExtent = CGRect(x: 0, y: 0,
                                          width: CVPixelBufferGetWidth(buffer),
                                          height: CVPixelBufferGetHeight(buffer))
            let preservesSourcePixels = canVerify && decoded.extent == fullBufferExtent
                && isSourceRaster(buffer, format: format, transform: transform)
            return CapturedImage(image: image, preservesSourcePixels: preservesSourcePixels)
        }
    }

    /// AV output negotiation and metadata can disagree. The active track's
    /// video format description, rather than a matching final image size,
    /// establishes whether the acquired buffer retains its coded raster.
    nonisolated static func isSourceRaster(
        _ buffer: CVPixelBuffer,
        format: CMFormatDescription?,
        transform: CGAffineTransform
    ) -> Bool {
        guard let format, CMFormatDescriptionGetMediaType(format) == kCMMediaType_Video,
              isPixelPreserving(transform) else { return false }
        let coded = CMVideoFormatDescriptionGetDimensions(format)
        return coded.width > 0 && coded.height > 0
            && CVPixelBufferGetWidth(buffer) == Int(coded.width)
            && CVPixelBufferGetHeight(buffer) == Int(coded.height)
    }

    /// Dimensions can still match after a scale or shear that resamples every
    /// pixel. Native-pixel mode requires a whole-pixel rotation/reflection and
    /// whole-pixel translation in the AV track's display matrix.
    nonisolated static func isPixelPreserving(_ transform: CGAffineTransform) -> Bool {
        let coefficients = [transform.a, transform.b, transform.c, transform.d]
        guard coefficients.allSatisfy(\.isFinite),
              transform.tx.isFinite, transform.ty.isFinite else { return false }
        let rows = (abs(transform.a) == 1 && transform.b == 0
                    && transform.c == 0 && abs(transform.d) == 1)
            || (transform.a == 0 && abs(transform.b) == 1
                && abs(transform.c) == 1 && transform.d == 0)
        return rows && transform.tx == transform.tx.rounded()
            && transform.ty == transform.ty.rounded()
    }

    /// AV track transforms use a top-left origin; Core Image uses bottom-left.
    /// Conjugate by a vertical flip. The output is rendered over its own extent,
    /// so no extra translation to the positive quadrant is necessary.
    nonisolated static func coreImageTransform(_ transform: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: transform.a, b: -transform.b,
                          c: -transform.c, d: transform.d,
                          tx: transform.tx, ty: -transform.ty)
    }

    /// MPV's video screenshot already passes through its display conversion
    /// (including pixel aspect and GPU rotation). Do not rotate it a second time.
    nonisolated static func image(from raw: MPVPlayer.RawScreenshot) -> CGImage? {
        let bits: Int
        let info: CGBitmapInfo
        switch raw.format {
        case "bgr0":
            bits = 8
            info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        case "bgra":
            bits = 8
            info = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        case "rgba":
            bits = 8
            info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        case "rgba64":
            bits = 16
            info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        default: return nil
        }
        let bytesPerPixel = bits / 8 * 4
        guard raw.width > 0, raw.height > 0,
              raw.width <= Int.max / bytesPerPixel,
              raw.stride >= raw.width * bytesPerPixel,
              raw.height <= Int.max / raw.stride,
              raw.data.count >= raw.height * raw.stride,
              let provider = CGDataProvider(data: raw.data as CFData) else { return nil }
        return CGImage(width: raw.width, height: raw.height,
                       bitsPerComponent: bits, bitsPerPixel: bits * 4,
                       bytesPerRow: raw.stride, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
