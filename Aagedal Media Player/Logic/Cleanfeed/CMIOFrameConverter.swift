// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// GPU-accelerated (Metal) and VideoToolbox frame converter for CoreMediaIO
// cleanfeed output. Converts Metal textures (from MPV's offscreen cleanfeed
// layer) or CVPixelBuffers (from AVPlayer) into IOSurface-backed CVPixelBuffers
// matching the negotiated broadcast format (BGRA, 10-bit v210, or 8-bit 2vuy).

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import Metal
import OSLog
import VideoToolbox

private nonisolated struct CleanfeedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

nonisolated final class CMIOFrameConverter: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "CleanfeedConverter")

    let width: Int
    let height: Int
    let pixelFormat: OSType
    let colorSpace: CleanfeedColorSpace

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var pixelBufferPool: CVPixelBufferPool?
    private var transferSession: VTPixelTransferSession?

    private var bgraPipeline: MTLComputePipelineState?
    private var v210Pipeline: MTLComputePipelineState?
    private var uyvyPipeline: MTLComputePipelineState?
    private var stagingBuffer: MTLBuffer?

    init?(width: Int, height: Int, pixelFormat: OSType, colorSpace: CleanfeedColorSpace) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.colorSpace = colorSpace

        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()

        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 8,
        ]
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: pixelFormat == kCVPixelFormatType_32BGRA,
        ]

        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        guard poolStatus == kCVReturnSuccess, let pool else {
            Self.logger.error("Failed to create CVPixelBufferPool (\(width)x\(height)): \(poolStatus)")
            return nil
        }
        self.pixelBufferPool = pool

        if let device {
            var cache: CVMetalTextureCache?
            if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess {
                self.textureCache = cache
            }
            buildMetalPipelines(device: device)
        }

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &session) == noErr,
           let session {
            VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Letterbox)
            VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries, value: colorSpace.cvColorPrimaries)
            VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: colorSpace.cvTransferFunction)
            VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, value: colorSpace.cvYCbCrMatrix)
            self.transferSession = session
        }
    }

    deinit {
        if let session = transferSession {
            VTPixelTransferSessionInvalidate(session)
        }
    }

    // MARK: - Pool Allocation

    private func allocateDestinationPixelBuffer() -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let pb else { return nil }
        attachColorMetadata(to: pb)
        return pb
    }

    private func attachColorMetadata(to pixelBuffer: CVPixelBuffer) {
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferColorPrimariesKey,
            colorSpace.cvColorPrimaries,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferTransferFunctionKey,
            colorSpace.cvTransferFunction,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            pixelBuffer,
            kCVImageBufferYCbCrMatrixKey,
            colorSpace.cvYCbCrMatrix,
            .shouldPropagate
        )
    }

    // MARK: - Metal Texture Conversion (MPV Cleanfeed Path)

    /// Converts an `MTLTexture` rendered by MPV's offscreen cleanfeed layer into
    /// an IOSurface-backed `CVPixelBuffer` in the negotiated output format.
    ///
    /// Runs asynchronously on our dedicated Metal queue and calls `completion`
    /// once the GPU copy/encode finishes, keeping `retainedToken` alive until
    /// GPU completion so the source drawable cannot be recycled mid-read.
    func convertTexture(
        _ sourceTexture: MTLTexture,
        sourceIsLinearEDR: Bool,
        retainedToken: AnyObject?,
        completion: @escaping @Sendable (CVPixelBuffer?) -> Void
    ) {
        guard let commandQueue, let commandBuffer = commandQueue.makeCommandBuffer(),
              let destination = allocateDestinationPixelBuffer() else {
            completion(nil)
            return
        }

        let transferMode = transferEncodeMode(sourceIsLinearEDR: sourceIsLinearEDR)
        let retainedBox = CleanfeedSendableBox(value: retainedToken)
        let destinationBox = CleanfeedSendableBox(value: destination)

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            guard encodeBGRA(
                from: sourceTexture,
                to: destination,
                transferMode: transferMode,
                commandBuffer: commandBuffer
            ) else {
                completion(nil)
                return
            }
            commandBuffer.addCompletedHandler { _ in
                _ = retainedBox.value
                completion(destinationBox.value)
            }
            commandBuffer.commit()

        case kCVPixelFormatType_422YpCbCr10:
            guard let staging = encodeV210(
                from: sourceTexture,
                to: destination,
                transferMode: transferMode,
                commandBuffer: commandBuffer
            ) else {
                completion(nil)
                return
            }
            let stagingBox = CleanfeedSendableBox(value: staging)
            let targetHeight = height
            let bytesPerRow = CVPixelBufferGetBytesPerRow(destination)
            commandBuffer.addCompletedHandler { _ in
                _ = retainedBox.value
                let dst = destinationBox.value
                CVPixelBufferLockBaseAddress(dst, [])
                if let dstBase = CVPixelBufferGetBaseAddress(dst) {
                    memcpy(dstBase, stagingBox.value.contents(), bytesPerRow * targetHeight)
                }
                CVPixelBufferUnlockBaseAddress(dst, [])
                completion(dst)
            }
            commandBuffer.commit()

        case kCVPixelFormatType_422YpCbCr8:
            guard let staging = encode2vuy(
                from: sourceTexture,
                to: destination,
                transferMode: transferMode,
                commandBuffer: commandBuffer
            ) else {
                completion(nil)
                return
            }
            let stagingBox = CleanfeedSendableBox(value: staging)
            let targetHeight = height
            let bytesPerRow = CVPixelBufferGetBytesPerRow(destination)
            commandBuffer.addCompletedHandler { _ in
                _ = retainedBox.value
                let dst = destinationBox.value
                CVPixelBufferLockBaseAddress(dst, [])
                if let dstBase = CVPixelBufferGetBaseAddress(dst) {
                    memcpy(dstBase, stagingBox.value.contents(), bytesPerRow * targetHeight)
                }
                CVPixelBufferUnlockBaseAddress(dst, [])
                completion(dst)
            }
            commandBuffer.commit()

        default:
            completion(nil)
        }
    }

    // MARK: - CVPixelBuffer Conversion (AVPlayer ProRes RAW Path)

    func convertPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        guard let transferSession, let destination = allocateDestinationPixelBuffer() else { return nil }
        let status = VTPixelTransferSessionTransferImage(transferSession, from: source, to: destination)
        guard status == noErr else { return nil }
        return destination
    }

    // MARK: - Test Patterns & Broadcast Black

    func makeBlackPixelBuffer() -> CVPixelBuffer? {
        guard let pb = allocateDestinationPixelBuffer() else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            // Broadcast black (0, 0, 0, 255)
            let row = base.assumingMemoryBound(to: UInt32.self)
            for x in 0..<width { row[x] = 0xFF000000 }
            for y in 1..<height {
                memcpy(base.advanced(by: y * bpr), base, width * 4)
            }
        case kCVPixelFormatType_422YpCbCr10:
            // 10-bit broadcast black: Y = 64, Cb = 512, Cr = 512
            let groups = (width + 5) / 6
            let words = Self.packV210Group(
                cb0: 512, y0: 64, cr0: 512, y1: 64,
                cb2: 512, y2: 64, cr2: 512, y3: 64,
                cb4: 512, y4: 64, cr4: 512, y5: 64
            )
            let row = base.assumingMemoryBound(to: UInt32.self)
            for g in 0..<groups {
                let offset = g * 4
                row[offset + 0] = words.0
                row[offset + 1] = words.1
                row[offset + 2] = words.2
                row[offset + 3] = words.3
            }
            for y in 1..<height {
                memcpy(base.advanced(by: y * bpr), base, bpr)
            }
        case kCVPixelFormatType_422YpCbCr8:
            // 8-bit 2vuy broadcast black: Cb=128, Y0=16, Cr=128, Y1=16 -> 0x10801080 (little-endian)
            let pairs = width / 2
            let row = base.assumingMemoryBound(to: UInt32.self)
            for p in 0..<pairs { row[p] = 0x10801080 }
            for y in 1..<height {
                memcpy(base.advanced(by: y * bpr), base, bpr)
            }
        default:
            memset(base, 0, bpr * height)
        }
        return pb
    }

    /// Generates animated 75% SMPTE color bars with a moving indicator bar so
    /// the user can visually confirm live frame-locked output on an SDI/HDMI monitor.
    func makeColorBarsPixelBuffer(frameIndex: Int) -> CVPixelBuffer? {
        guard let pb = allocateDestinationPixelBuffer() else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let barWidth = max(width / 8, 1)
        let sweepWidth = max(width / 40, 16)
        let sweepX = (frameIndex * max(width / 60, 8)) % max(width, 1)
        let sweepY0 = (height * 3) / 4
        let sweepY1 = min(height, sweepY0 + max(height / 10, 24))

        // 75% color bars (R, G, B in 0...1)
        let barsRGB: [(Float, Float, Float)] = [
            (0.75, 0.75, 0.75), // White (75%)
            (0.75, 0.75, 0.00), // Yellow
            (0.00, 0.75, 0.75), // Cyan
            (0.00, 0.75, 0.00), // Green
            (0.75, 0.00, 0.75), // Magenta
            (0.75, 0.00, 0.00), // Red
            (0.00, 0.00, 0.75), // Blue
            (0.00, 0.00, 0.00), // Black
        ]

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            let row0 = base.assumingMemoryBound(to: UInt32.self)
            for x in 0..<width {
                let c = barsRGB[min(x / barWidth, 7)]
                let r = UInt32((c.0 * 255).rounded())
                let g = UInt32((c.1 * 255).rounded())
                let b = UInt32((c.2 * 255).rounded())
                row0[x] = 0xFF000000 | (r << 16) | (g << 8) | b
            }
            for y in 1..<height {
                memcpy(base.advanced(by: y * bpr), base, width * 4)
            }
            for y in sweepY0..<sweepY1 {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt32.self)
                for dx in 0..<sweepWidth {
                    row[(sweepX + dx) % width] = 0xFFFFFFFF
                }
            }

        case kCVPixelFormatType_422YpCbCr10:
            let is2020 = colorSpace.isRec2020
            let groups = (width + 5) / 6
            let row0 = base.assumingMemoryBound(to: UInt32.self)
            for g in 0..<groups {
                var ys = [UInt32](repeating: 64, count: 6)
                var cbs = [UInt32](repeating: 512, count: 3)
                var crs = [UInt32](repeating: 512, count: 3)
                for p in 0..<6 {
                    let x = min(g * 6 + p, width - 1)
                    let c = barsRGB[min(x / barWidth, 7)]
                    let ycc = Self.rgbToYCbCr10(r: c.0, g: c.1, b: c.2, isRec2020: is2020)
                    ys[p] = ycc.y
                    if p % 2 == 0 {
                        cbs[p / 2] = ycc.cb
                        crs[p / 2] = ycc.cr
                    }
                }
                let words = Self.packV210Group(
                    cb0: cbs[0], y0: ys[0], cr0: crs[0], y1: ys[1],
                    cb2: cbs[1], y2: ys[2], cr2: crs[1], y3: ys[3],
                    cb4: cbs[2], y4: ys[4], cr4: crs[2], y5: ys[5]
                )
                let off = g * 4
                row0[off + 0] = words.0
                row0[off + 1] = words.1
                row0[off + 2] = words.2
                row0[off + 3] = words.3
            }
            for y in 1..<height {
                memcpy(base.advanced(by: y * bpr), base, bpr)
            }
            // White moving sweep bar in v210 (Y=940, Cb=512, Cr=512)
            let whiteWords = Self.packV210Group(
                cb0: 512, y0: 940, cr0: 512, y1: 940,
                cb2: 512, y2: 940, cr2: 512, y3: 940,
                cb4: 512, y4: 940, cr4: 512, y5: 940
            )
            let sweepGroup0 = (sweepX / 6) % max(groups, 1)
            let sweepGroups = max(sweepWidth / 6, 3)
            for y in sweepY0..<sweepY1 {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt32.self)
                for dg in 0..<sweepGroups {
                    let g = (sweepGroup0 + dg) % groups
                    let off = g * 4
                    row[off + 0] = whiteWords.0
                    row[off + 1] = whiteWords.1
                    row[off + 2] = whiteWords.2
                    row[off + 3] = whiteWords.3
                }
            }

        case kCVPixelFormatType_422YpCbCr8:
            let is2020 = colorSpace.isRec2020
            let pairs = width / 2
            let row0 = base.assumingMemoryBound(to: UInt32.self)
            for p in 0..<pairs {
                let x = min(p * 2, width - 1)
                let c = barsRGB[min(x / barWidth, 7)]
                let ycc = Self.rgbToYCbCr10(r: c.0, g: c.1, b: c.2, isRec2020: is2020)
                let y8 = (ycc.y >> 2) & 0xFF
                let cb8 = (ycc.cb >> 2) & 0xFF
                let cr8 = (ycc.cr >> 2) & 0xFF
                row0[p] = cb8 | (y8 << 8) | (cr8 << 16) | (y8 << 24)
            }
            for y in 1..<height {
                memcpy(base.advanced(by: y * bpr), base, bpr)
            }
            let whitePair: UInt32 = 128 | (235 << 8) | (128 << 16) | (235 << 24)
            let sweepPair0 = (sweepX / 2) % max(pairs, 1)
            let sweepPairs = max(sweepWidth / 2, 8)
            for y in sweepY0..<sweepY1 {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt32.self)
                for dp in 0..<sweepPairs {
                    row[(sweepPair0 + dp) % pairs] = whitePair
                }
            }

        default:
            break
        }
        return pb
    }

    // MARK: - Reference 10-Bit v210 Packing (Tested & Shared Spec)

    /// Packs 6 pixels (3 chroma pairs) into 4 little-endian 32-bit words per the
    /// SMPTE 292M / QuickTime `v210` layout:
    ///   word0 = (Cr0 << 20) | (Y0 << 10) | Cb0
    ///   word1 = (Y2  << 20) | (Cb2 << 10) | Y1
    ///   word2 = (Cb4 << 20) | (Y3 << 10) | Cr2
    ///   word3 = (Y5  << 20) | (Cr4 << 10) | Y4
    static func packV210Group(
        cb0: UInt32, y0: UInt32, cr0: UInt32, y1: UInt32,
        cb2: UInt32, y2: UInt32, cr2: UInt32, y3: UInt32,
        cb4: UInt32, y4: UInt32, cr4: UInt32, y5: UInt32
    ) -> (UInt32, UInt32, UInt32, UInt32) {
        let m: UInt32 = 0x3FF
        let w0 = ((cr0 & m) << 20) | ((y0 & m) << 10) | (cb0 & m)
        let w1 = ((y2 & m) << 20) | ((cb2 & m) << 10) | (y1 & m)
        let w2 = ((cb4 & m) << 20) | ((y3 & m) << 10) | (cr2 & m)
        let w3 = ((y5 & m) << 20) | ((cr4 & m) << 10) | (y4 & m)
        return (w0, w1, w2, w3)
    }

    /// Converts non-linear RGB [0, 1] to 10-bit legal-range YCbCr
    /// (Y in 64...940, Cb/Cr in 64...960) using Rec.709 or Rec.2020 matrix.
    static func rgbToYCbCr10(r: Float, g: Float, b: Float, isRec2020: Bool) -> (y: UInt32, cb: UInt32, cr: UInt32) {
        let rc = min(max(r, 0), 1)
        let gc = min(max(g, 0), 1)
        let bc = min(max(b, 0), 1)
        let kr: Float = isRec2020 ? 0.2627 : 0.2126
        let kb: Float = isRec2020 ? 0.0593 : 0.0722
        let kg: Float = 1.0 - kr - kb

        let yNorm = kr * rc + kg * gc + kb * bc
        let cbNorm = (bc - yNorm) / (2.0 * (1.0 - kb))
        let crNorm = (rc - yNorm) / (2.0 * (1.0 - kr))

        let y = UInt32(min(max((64.0 + 876.0 * yNorm).rounded(), 64), 940))
        let cb = UInt32(min(max((512.0 + 896.0 * cbNorm).rounded(), 64), 960))
        let cr = UInt32(min(max((512.0 + 896.0 * crNorm).rounded(), 64), 960))
        return (y, cb, cr)
    }

    // MARK: - Private Metal Encoding

    private struct ShaderParams {
        var dstWidth: UInt32
        var dstHeight: UInt32
        var dstRowBytes: UInt32
        var isRec2020: UInt32
        var transferMode: UInt32 // 0 = pass-through, 1 = linear->BT.1886, 2 = linear->PQ, 3 = linear->HLG
    }

    private func transferEncodeMode(sourceIsLinearEDR: Bool) -> UInt32 {
        guard sourceIsLinearEDR else { return 0 }
        switch colorSpace {
        case .rec709, .rec2020: return 1
        case .hdrPQ: return 2
        case .hdrHLG: return 3
        }
    }

    private func ensureStagingBuffer(byteLength: Int) -> MTLBuffer? {
        if let existing = stagingBuffer, existing.length >= byteLength {
            return existing
        }
        guard let device else { return nil }
        let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared)
        stagingBuffer = buffer
        return buffer
    }

    private func encodeBGRA(
        from sourceTexture: MTLTexture,
        to destination: CVPixelBuffer,
        transferMode: UInt32,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let textureCache else { return false }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            destination,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let dstTexture = CVMetalTextureGetTexture(cvTexture) else { return false }

        // Zero-shader fast path when dimensions & format match directly.
        if transferMode == 0,
           sourceTexture.width == width,
           sourceTexture.height == height,
           sourceTexture.pixelFormat == .bgra8Unorm,
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: sourceTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: dstTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
            return true
        }

        guard let pipeline = bgraPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        var params = ShaderParams(
            dstWidth: UInt32(width),
            dstHeight: UInt32(height),
            dstRowBytes: UInt32(CVPixelBufferGetBytesPerRow(destination)),
            isRec2020: colorSpace.isRec2020 ? 1 : 0,
            transferMode: transferMode
        )
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(dstTexture, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<ShaderParams>.size, index: 0)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        encoder.endEncoding()
        return true
    }

    private func encodeV210(
        from sourceTexture: MTLTexture,
        to destination: CVPixelBuffer,
        transferMode: UInt32,
        commandBuffer: MTLCommandBuffer
    ) -> MTLBuffer? {
        let rowBytes = CVPixelBufferGetBytesPerRow(destination)
        let totalBytes = rowBytes * height
        guard let pipeline = v210Pipeline,
              let staging = ensureStagingBuffer(byteLength: totalBytes),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        var params = ShaderParams(
            dstWidth: UInt32(width),
            dstHeight: UInt32(height),
            dstRowBytes: UInt32(rowBytes),
            isRec2020: colorSpace.isRec2020 ? 1 : 0,
            transferMode: transferMode
        )
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setBuffer(staging, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<ShaderParams>.size, index: 1)
        let groupsX = (width + 5) / 6
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (groupsX + 15) / 16, height: (height + 15) / 16, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        encoder.endEncoding()
        return staging
    }

    private func encode2vuy(
        from sourceTexture: MTLTexture,
        to destination: CVPixelBuffer,
        transferMode: UInt32,
        commandBuffer: MTLCommandBuffer
    ) -> MTLBuffer? {
        let rowBytes = CVPixelBufferGetBytesPerRow(destination)
        let totalBytes = rowBytes * height
        guard let pipeline = uyvyPipeline,
              let staging = ensureStagingBuffer(byteLength: totalBytes),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        var params = ShaderParams(
            dstWidth: UInt32(width),
            dstHeight: UInt32(height),
            dstRowBytes: UInt32(rowBytes),
            isRec2020: colorSpace.isRec2020 ? 1 : 0,
            transferMode: transferMode
        )
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setBuffer(staging, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<ShaderParams>.size, index: 1)
        let pairsX = width / 2
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (pairsX + 15) / 16, height: (height + 15) / 16, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        encoder.endEncoding()
        return staging
    }

    private func buildMetalPipelines(device: MTLDevice) {
        do {
            let library = try device.makeLibrary(source: Self.metalShaderSource, options: nil)
            if let fn = library.makeFunction(name: "scaleCopyBGRA") {
                bgraPipeline = try device.makeComputePipelineState(function: fn)
            }
            if let fn = library.makeFunction(name: "convertRGBToV210") {
                v210Pipeline = try device.makeComputePipelineState(function: fn)
            }
            if let fn = library.makeFunction(name: "convertRGBTo2vuy") {
                uyvyPipeline = try device.makeComputePipelineState(function: fn)
            }
        } catch {
            Self.logger.error("Failed to compile cleanfeed Metal shaders: \(error.localizedDescription)")
        }
    }

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ShaderParams {
        uint dstWidth;
        uint dstHeight;
        uint dstRowBytes;
        uint isRec2020;
        uint transferMode;
    };

    inline float3 encodeTransfer(float3 rgb, uint mode) {
        if (mode == 0) {
            return clamp(rgb, 0.0f, 1.0f);
        }
        float3 lin = max(rgb, float3(0.0f));
        if (mode == 1) {
            // Linear -> BT.1886 (gamma 2.4)
            return clamp(pow(lin, float3(1.0f / 2.4f)), 0.0f, 1.0f);
        }
        if (mode == 2) {
            // Extended linear (1.0 = 100 nits) -> ST 2084 PQ (1.0 = 10000 nits)
            float3 y = clamp(lin * 0.01f, 0.0f, 1.0f);
            constexpr float m1 = 0.1593017578125f;
            constexpr float m2 = 78.84375f;
            constexpr float c1 = 0.8359375f;
            constexpr float c2 = 18.8515625f;
            constexpr float c3 = 18.6875f;
            float3 ym1 = pow(y, float3(m1));
            return clamp(pow((c1 + c2 * ym1) / (1.0f + c3 * ym1), float3(m2)), 0.0f, 1.0f);
        }
        // mode == 3: HLG OETF
        float3 e = clamp(lin / 12.0f, 0.0f, 1.0f);
        constexpr float a = 0.17883277f;
        constexpr float b = 0.28466892f;
        constexpr float c = 0.55991073f;
        float3 lo = sqrt(3.0f * e);
        float3 hi = a * log(max(12.0f * e - b, float3(1e-6f))) + c;
        return clamp(select(hi, lo, e <= (1.0f / 12.0f)), 0.0f, 1.0f);
    }

    inline float3 sampleLetterbox(texture2d<float, access::sample> src, uint x, uint y, uint dstW, uint dstH, uint transferMode) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float srcW = float(src.get_width());
        float srcH = float(src.get_height());
        float outW = float(dstW);
        float outH = float(dstH);
        float scale = min(outW / max(srcW, 1.0f), outH / max(srcH, 1.0f));
        float fitW = srcW * scale;
        float fitH = srcH * scale;
        float padX = (outW - fitW) * 0.5f;
        float padY = (outH - fitH) * 0.5f;
        float px = float(x) + 0.5f;
        float py = float(y) + 0.5f;
        if (px < padX || px > padX + fitW || py < padY || py > padY + fitH) {
            return float3(0.0f);
        }
        float2 uv = float2((px - padX) / max(fitW, 1.0f), (py - padY) / max(fitH, 1.0f));
        float3 rgb = src.sample(s, uv).rgb;
        return encodeTransfer(rgb, transferMode);
    }

    inline float3 rgbToYCbCrNorm(float3 rgb, uint isRec2020) {
        float kr = isRec2020 ? 0.2627f : 0.2126f;
        float kb = isRec2020 ? 0.0593f : 0.0722f;
        float kg = 1.0f - kr - kb;
        float y = kr * rgb.r + kg * rgb.g + kb * rgb.b;
        float cb = (rgb.b - y) / (2.0f * (1.0f - kb));
        float cr = (rgb.r - y) / (2.0f * (1.0f - kr));
        return float3(y, cb, cr);
    }

    inline uint quantY10(float y) {
        return uint(clamp(round(64.0f + 876.0f * y), 64.0f, 940.0f));
    }

    inline uint quantC10(float c) {
        return uint(clamp(round(512.0f + 896.0f * c), 64.0f, 960.0f));
    }

    kernel void scaleCopyBGRA(
        texture2d<float, access::sample> src [[texture(0)]],
        texture2d<float, access::write> dst [[texture(1)]],
        constant ShaderParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.dstWidth || gid.y >= params.dstHeight) return;
        float3 rgb = sampleLetterbox(src, gid.x, gid.y, params.dstWidth, params.dstHeight, params.transferMode);
        dst.write(float4(rgb, 1.0f), gid);
    }

    kernel void convertRGBToV210(
        texture2d<float, access::sample> src [[texture(0)]],
        device uint *dst [[buffer(0)]],
        constant ShaderParams &params [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint groupsPerRow = (params.dstWidth + 5) / 6;
        if (gid.x >= groupsPerRow || gid.y >= params.dstHeight) return;

        uint baseX = gid.x * 6;
        uint ys[6];
        float cbs[6];
        float crs[6];

        for (uint i = 0; i < 6; i++) {
            uint px = min(baseX + i, params.dstWidth - 1);
            float3 rgb = sampleLetterbox(src, px, gid.y, params.dstWidth, params.dstHeight, params.transferMode);
            float3 ycc = rgbToYCbCrNorm(rgb, params.isRec2020);
            ys[i] = quantY10(ycc.x);
            cbs[i] = ycc.y;
            crs[i] = ycc.z;
        }

        uint cb0 = quantC10(0.5f * (cbs[0] + cbs[1]));
        uint cr0 = quantC10(0.5f * (crs[0] + crs[1]));
        uint cb2 = quantC10(0.5f * (cbs[2] + cbs[3]));
        uint cr2 = quantC10(0.5f * (crs[2] + crs[3]));
        uint cb4 = quantC10(0.5f * (cbs[4] + cbs[5]));
        uint cr4 = quantC10(0.5f * (crs[4] + crs[5]));

        uint rowWords = params.dstRowBytes / 4;
        uint outIdx = gid.y * rowWords + gid.x * 4;
        dst[outIdx + 0] = ((cr0 & 0x3FF) << 20) | ((ys[0] & 0x3FF) << 10) | (cb0 & 0x3FF);
        dst[outIdx + 1] = ((ys[2] & 0x3FF) << 20) | ((cb2 & 0x3FF) << 10) | (ys[1] & 0x3FF);
        dst[outIdx + 2] = ((cb4 & 0x3FF) << 20) | ((ys[3] & 0x3FF) << 10) | (cr2 & 0x3FF);
        dst[outIdx + 3] = ((ys[5] & 0x3FF) << 20) | ((cr4 & 0x3FF) << 10) | (ys[4] & 0x3FF);
    }

    kernel void convertRGBTo2vuy(
        texture2d<float, access::sample> src [[texture(0)]],
        device uint *dst [[buffer(0)]],
        constant ShaderParams &params [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint pairsPerRow = params.dstWidth / 2;
        if (gid.x >= pairsPerRow || gid.y >= params.dstHeight) return;

        uint x0 = gid.x * 2;
        uint x1 = min(x0 + 1, params.dstWidth - 1);
        float3 ycc0 = rgbToYCbCrNorm(sampleLetterbox(src, x0, gid.y, params.dstWidth, params.dstHeight, params.transferMode), params.isRec2020);
        float3 ycc1 = rgbToYCbCrNorm(sampleLetterbox(src, x1, gid.y, params.dstWidth, params.dstHeight, params.transferMode), params.isRec2020);

        uint y0 = uint(clamp(round(16.0f + 219.0f * ycc0.x), 16.0f, 235.0f));
        uint y1 = uint(clamp(round(16.0f + 219.0f * ycc1.x), 16.0f, 235.0f));
        uint cb = uint(clamp(round(128.0f + 224.0f * 0.5f * (ycc0.y + ycc1.y)), 16.0f, 240.0f));
        uint cr = uint(clamp(round(128.0f + 224.0f * 0.5f * (ycc0.z + ycc1.z)), 16.0f, 240.0f));

        uint rowWords = params.dstRowBytes / 4;
        dst[gid.y * rowWords + gid.x] = cb | (y0 << 8) | (cr << 16) | (y1 << 24);
    }
    """
}
