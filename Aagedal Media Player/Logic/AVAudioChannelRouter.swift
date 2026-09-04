// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import AudioToolbox
import MediaToolbox

private nonisolated final class AVAudioChannelTapStorage: @unchecked Sendable {
    let routing: AudioChannelRouting
    var processingFormat = AudioStreamBasicDescription()

    init(routing: AudioChannelRouting) {
        self.routing = routing
    }
}

private nonisolated func audioChannelTapStorage(
    _ tap: MTAudioProcessingTap
) -> AVAudioChannelTapStorage? {
    let storage = MTAudioProcessingTapGetStorage(tap)
    return Unmanaged<AVAudioChannelTapStorage>.fromOpaque(storage).takeUnretainedValue()
}

private nonisolated func audioChannelTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private nonisolated func audioChannelTapFinalize(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<AVAudioChannelTapStorage>.fromOpaque(storage).release()
}

private nonisolated func audioChannelTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    audioChannelTapStorage(tap)?.processingFormat = processingFormat.pointee
}

private nonisolated func audioChannelTapUnprepare(_ tap: MTAudioProcessingTap) {}

private nonisolated func audioChannelTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    var timeRange = CMTimeRange.invalid
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        &timeRange,
        numberFramesOut
    )
    guard status == noErr,
          numberFramesOut.pointee > 0,
          let storage = audioChannelTapStorage(tap) else { return }

    applyAudioChannelRouting(
        in: bufferListInOut,
        frameCount: Int(numberFramesOut.pointee),
        routing: storage.routing,
        processingFormat: storage.processingFormat
    )
}

nonisolated func applyAudioChannelRouting(
    in audioBufferList: UnsafeMutablePointer<AudioBufferList>,
    frameCount: Int,
    routing: AudioChannelRouting,
    processingFormat: AudioStreamBasicDescription
) {
    guard frameCount > 0, !routing.isBypassed else { return }
    guard processingFormat.mFormatID == kAudioFormatLinearPCM,
          processingFormat.mFormatFlags & (kAudioFormatFlagIsFloat | kAudioFormatFlagIsSignedInteger) != 0,
          Int(processingFormat.mChannelsPerFrame) == routing.channelCount else { return }

    let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
    var channelBase = 0

    for buffer in buffers {
        guard let data = buffer.mData else {
            channelBase += Int(buffer.mNumberChannels)
            continue
        }

        let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
        let byteCount = Int(buffer.mDataByteSize)
        guard byteCount > 0 else {
            channelBase += channelsInBuffer
            continue
        }

        if channelsInBuffer == 1 {
            if !routing.isAudible(channelBase) {
                memset(data, 0, byteCount)
            }
        } else {
            let bytesPerFrame = byteCount / frameCount
            let bytesPerSample = bytesPerFrame / channelsInBuffer
            guard bytesPerFrame > 0, bytesPerSample > 0 else {
                channelBase += channelsInBuffer
                continue
            }

            for localChannel in 0..<channelsInBuffer
            where !routing.isAudible(channelBase + localChannel) {
                for frame in 0..<frameCount {
                    memset(
                        data.advanced(by: frame * bytesPerFrame + localChannel * bytesPerSample),
                        0,
                        bytesPerSample
                    )
                }
            }
        }
        channelBase += channelsInBuffer
    }
}

@MainActor
enum AVAudioChannelRouter {
    static func apply(_ routing: AudioChannelRouting, to playerItem: AVPlayerItem?) {
        guard let playerItem else { return }
        guard !routing.isBypassed else {
            playerItem.audioMix = nil
            return
        }

        let audioTracks = playerItem.tracks.compactMap(\.assetTrack).filter {
            $0.mediaType == .audio
        }
        guard !audioTracks.isEmpty else {
            playerItem.audioMix = nil
            return
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = audioTracks.compactMap { track in
            guard let tap = makeTap(for: routing) else { return nil }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            return parameters
        }
        playerItem.audioMix = mix.inputParameters.isEmpty ? nil : mix
    }

    private static func makeTap(for routing: AudioChannelRouting) -> MTAudioProcessingTap? {
        let storage = Unmanaged.passRetained(AVAudioChannelTapStorage(routing: routing))
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: storage.toOpaque(),
            init: audioChannelTapInit,
            finalize: audioChannelTapFinalize,
            prepare: audioChannelTapPrepare,
            unprepare: audioChannelTapUnprepare,
            process: audioChannelTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard status == noErr, let tap else {
            storage.release()
            return nil
        }
        return tap
    }
}
