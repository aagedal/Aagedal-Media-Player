// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

@main
enum ScopeProfiler {
    private static let resolutions = [360, 720, 1080, 1440]
    private static let updateRates = Array(5...30)

    static func main() {
        var measurements: [Measurement] = []

        for resolution in resolutions {
            let height = resolution * 9 / 16
            guard let frame = makeTestFrame(width: resolution, height: height) else {
                fatalError("Could not create the \(resolution)p profiling frame")
            }
            let waveformSize = CGSize(width: resolution, height: height)
            let vectorscopeSize = CGSize(width: height, height: height)

            for mode in Mode.allCases {
                let render = {
                    let waveform: CGImage?
                    switch mode {
                    case .luma:
                        waveform = ScopeComputer.computeWaveform(
                            from: frame,
                            outputSize: waveformSize
                        )
                    case .parade:
                        waveform = ScopeComputer.computeParade(
                            from: frame,
                            outputSize: waveformSize
                        )
                    }
                    let vectorscope = ScopeComputer.computeVectorscope(
                        from: frame,
                        outputSize: vectorscopeSize
                    )
                    return waveform != nil && vectorscope != nil
                }

                guard render() else {
                    fatalError("Scope rendering failed for \(resolution)p \(mode.rawValue)")
                }

                let clock = ContinuousClock()
                var samples: [Double] = []
                for _ in 0..<5 {
                    let start = clock.now
                    guard render() else {
                        fatalError("Scope rendering failed for \(resolution)p \(mode.rawValue)")
                    }
                    samples.append(start.duration(to: clock.now).milliseconds)
                }

                samples.sort()
                measurements.append(
                    Measurement(
                        resolution: resolution,
                        mode: mode,
                        medianMilliseconds: samples[samples.count / 2]
                    )
                )
            }
        }

        printReport(measurements)
    }

    private static func printReport(_ measurements: [Measurement]) {
        print("| Resolution | Mode | Median render | Sustainable rate | 5 fps load | 15 fps load | 30 fps load |")
        print("| ---: | :--- | ---: | ---: | ---: | ---: | ---: |")
        for measurement in measurements {
            let milliseconds = measurement.medianMilliseconds
            let sustainableRate = milliseconds > 0 ? 1_000 / milliseconds : 0
            print(
                String(
                    format: "| %d | %@ | %.1f ms | %.1f fps | %.0f%% | %.0f%% | %.0f%% |",
                    measurement.resolution,
                    measurement.mode.rawValue,
                    milliseconds,
                    sustainableRate,
                    milliseconds * 5 / 10,
                    milliseconds * 15 / 10,
                    milliseconds * 30 / 10
                )
            )
        }

        print("\nFull supported matrix (estimated single-core renderer load):")
        for measurement in measurements {
            let loads = updateRates.map { rate in
                String(format: "%d=%.0f%%", rate, measurement.medianMilliseconds * Double(rate) / 10)
            }.joined(separator: ", ")
            print("\(measurement.resolution)p \(measurement.mode.rawValue): \(loads)")
        }
    }

    private static func makeTestFrame(width: Int, height: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(truncatingIfNeeded: x + y)
                pixels[offset + 1] = UInt8(truncatingIfNeeded: y * 3)
                pixels[offset + 2] = UInt8(truncatingIfNeeded: x * 5)
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension ScopeProfiler {
    enum Mode: String, CaseIterable {
        case luma
        case parade
    }

    struct Measurement {
        let resolution: Int
        let mode: Mode
        let medianMilliseconds: Double
    }
}
