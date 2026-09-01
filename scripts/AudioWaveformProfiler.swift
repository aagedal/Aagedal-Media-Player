// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

@main
enum AudioWaveformProfiler {
    static func main() throws {
        guard CommandLine.arguments.count == 5,
              let duration = Double(CommandLine.arguments[3]),
              let channelCount = Int(CommandLine.arguments[4]) else {
            fatalError("Usage: AudioWaveformProfiler <ffmpeg> <media> <duration-seconds> <channels>")
        }

        let ffmpeg = CommandLine.arguments[1]
        let media = CommandLine.arguments[2]
        let width = max(400, min(24_000, Int(duration * 12)))
        let sampleRate = max(
            100,
            min(48_000, Int(ceil(Double(width) * 100 / max(duration, 0.1))))
        )
        let accumulator = StreamingWaveformAccumulator(
            width: width,
            channelCount: channelCount,
            expectedFrameCount: max(1, Int(ceil(duration * Double(sampleRate))))
        )

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-hide_banner", "-loglevel", "error",
            "-i", media,
            "-vn", "-map", "0:a:0",
            "-ar", "\(sampleRate)",
            "-f", "f32le", "-c:a", "pcm_f32le",
            "pipe:1",
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        let initialResidentBytes = residentBytes()
        let clock = ContinuousClock()
        let start = clock.now
        try process.run()

        while try autoreleasepool(invoking: {
            guard let data = try stdout.fileHandleForReading.read(upToCount: 1024 * 1024),
                  !data.isEmpty else { return false }
            accumulator.consume(data)
            return true
        }) {}
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            fatalError("ffmpeg failed: \(message)")
        }

        let amplitudes = try accumulator.finish()
        let elapsed = start.duration(to: clock.now).seconds
        let residentDelta = max(0, Int64(residentBytes()) - Int64(initialResidentBytes))
        let retainedBytes = accumulator.retainedScalarCount * MemoryLayout<UInt32>.size
        guard amplitudes.count == channelCount else {
            fatalError("Expected \(channelCount) channels, received \(amplitudes.count)")
        }

        let hours = Int(duration / 3_600)
        print(
            String(
                format: "| %d hour%@ | %d | %d | %d Hz | %.2f s | %.2f MiB | %.2f MiB |",
                hours,
                hours == 1 ? "" : "s",
                channelCount,
                width,
                sampleRate,
                elapsed,
                Double(retainedBytes) / 1_048_576,
                Double(residentDelta) / 1_048_576
            )
        )
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
