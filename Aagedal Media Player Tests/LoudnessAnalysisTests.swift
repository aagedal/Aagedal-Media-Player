// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LoudnessAnalysisTests: XCTestCase {
    // Independently synthesize the specified PCM; FFmpeg is only the meter under test.
    // EBU Tech 3341 (2023), Table 1: https://tech.ebu.ch/docs/tech/tech3341.pdf
    func testEBUAbsoluteStereoCalibrationReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        for sampleRate in [44_100, 48_000, 96_000] {
            for level in [-23.0, -33.0] {
                let url = try writeReferenceTone(
                    segments: [(20, pow(10, level / 20))], sampleRate: sampleRate
                )
                defer { try? FileManager.default.removeItem(at: url) }
                let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
                XCTAssertEqual(result.integratedLoudness, level, accuracy: 0.1, "EBU cases 1 and 2 at \(sampleRate) Hz")
                XCTAssertEqual(result.truePeak, level, accuracy: 0.1)
            }
        }
    }

    func testEBULoudnessRangeReferencesAcrossSampleRates() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // EBU Tech 3342 (2023), Table 1, cases 1–4:
        // https://tech.ebu.ch/docs/tech/tech3342.pdf
        // Each in-phase stereo 1 kHz segment lasts 20 seconds. Case 4's
        // −50 dBFS sections must be gated out; the LRA is 15 LU, not 30 LU.
        // Section 3 states that the algorithm is independent of sample rate.
        let references: [(levels: [Double], expected: Double)] = [
            ([-20, -30], 10), ([-20, -15], 5), ([-40, -20], 20),
            ([-50, -35, -20, -35, -50], 15),
        ]
        for sampleRate in [44_100, 48_000, 96_000] {
            for (index, reference) in references.enumerated() {
                let url = try writeReferenceTone(
                    segments: reference.levels.map { (20, pow(10, $0 / 20)) },
                    sampleRate: sampleRate
                )
                defer { try? FileManager.default.removeItem(at: url) }
                let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
                XCTAssertEqual(
                    result.loudnessRange, reference.expected, accuracy: 1,
                    "EBU Tech 3342 case \(index + 1) at \(sampleRate) Hz"
                )
            }
        }
    }

    func testEBUAbsoluteAndRelativeGatingReference() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // Case 4: both the below-absolute-gate and below-relative-gate sections
        // must be excluded from the integrated result.
        let url = try writeReferenceTone(segments: [
            (10, pow(10, -72.0 / 20)), (10, pow(10, -36.0 / 20)),
            (60, pow(10, -23.0 / 20)),
            (10, pow(10, -36.0 / 20)), (10, pow(10, -72.0 / 20)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        XCTAssertEqual(result.integratedLoudness, -23, accuracy: 0.1, "EBU case 4")
    }

    func testEBUPhaseSensitiveTruePeakReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // Cases 15–19. Case 16 has a sample peak near −9 dBFS but a true peak
        // near −6 dBTP; case 19's unclipped samples reconstruct above full scale.
        let cases: [(divisor: Double, phase: Double, amplitude: Double, expected: Double)] = [
            (4, 0, 0.5, -6), (4, 45, 0.5, -6), (6, 60, 0.5, -6),
            (8, 67.5, 0.5, -6), (4, 45, 1.41, 3),
        ]
        // Frequencies are specified as fractions of fs, rather than fixed Hz.
        for sampleRate in [44_100, 48_000, 96_000] {
            for (index, reference) in cases.enumerated() {
                let url = try writeReferenceTone(
                    segments: [(2, reference.amplitude)], frequency: Double(sampleRate) / reference.divisor,
                    phase: reference.phase * .pi / 180, fadeSeconds: 0.01, sampleRate: sampleRate
                )
                defer { try? FileManager.default.removeItem(at: url) }
                let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
                let context = "EBU case \(index + 15) at \(sampleRate) Hz"
                XCTAssertGreaterThanOrEqual(result.truePeak, reference.expected - 0.4, context)
                XCTAssertLessThanOrEqual(result.truePeak, reference.expected + 0.2, context)
            }
        }
    }

    func testIndependentBandLimitedTransientTruePeakReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // x(t) = A sinc(t / 8)^2 cos(pi t / 2), with t in sample periods.
        // Both factors have magnitude <= 1 and equal 1 at t = 0, so the
        // continuous peak is exactly |A|. Its spectrum ends at 3 fs / 8,
        // below Nyquist. Centering between samples hides roughly 3 dB of peak.
        // Truncation is more than 2,000 envelope widths from the center;
        // the discarded envelope is < 3e-8 of peak at every sample rate.
        for sampleRate in [44_100, 48_000, 96_000] {
            for amplitude in [0.5, -0.5, 1.2, -1.2] {
                let center = Double(sampleRate) / 2 + 0.5
                let samples = (0..<sampleRate).map { frame -> Float in
                    let t = Double(frame) - center
                    let argument = Double.pi * t / 8
                    let sinc = argument == 0 ? 1 : sin(argument) / argument
                    return Float(amplitude * sinc * sinc * cos(.pi * t / 2))
                }
                let samplePeak = Double(samples.map { abs($0) }.max() ?? 0)
                let expected = 20 * log10(abs(amplitude))
                XCTAssertLessThan(samplePeak, 1, "Even above-full-scale references have unclipped PCM")
                XCTAssertLessThan(20 * log10(samplePeak), expected - 3)
                let url = try writeReferenceMonoPCM(samples, sampleRate: sampleRate)
                defer { try? FileManager.default.removeItem(at: url) }
                let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
                let context = "Transient A=\(amplitude) at \(sampleRate) Hz"
                // Regression tolerance matching the existing true-peak references;
                // these analytic pulses are not additional EBU certification cases.
                XCTAssertGreaterThanOrEqual(result.truePeak, expected - 0.4, context)
                XCTAssertLessThanOrEqual(result.truePeak, expected + 0.2, context)
                XCTAssertGreaterThan(result.truePeak, 20 * log10(samplePeak) + 2.5, context)
            }
        }
    }

    private func writeReferenceMonoPCM(_ samples: [Float], sampleRate: Int) throws -> URL {
        let payloadBytes = samples.count * MemoryLayout<Float>.size
        var data = Data(capacity: 44 + payloadBytes)
        func appendInteger<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        appendInteger(UInt32(36 + payloadBytes))
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendInteger(UInt32(16))
        appendInteger(UInt16(3)) // IEEE Float32, mono
        appendInteger(UInt16(1))
        appendInteger(UInt32(sampleRate))
        appendInteger(UInt32(sampleRate * 4))
        appendInteger(UInt16(4))
        appendInteger(UInt16(32))
        data.append(contentsOf: "data".utf8)
        appendInteger(UInt32(payloadBytes))
        for sample in samples { appendInteger(sample.bitPattern) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transient-reference-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    func testIndependentFrontChannelLayoutReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // A −23 dBFS, 1 kHz stereo sine is −23 LUFS (EBU Tech 3341 case 1).
        // ITU-R BS.1770 front channels each have unit energy weight, so an
        // isolated front channel is 10 log10(1/2) LU below that reference.
        let references: [(name: String, mask: UInt32, gains: [Double], weight: Double)] = [
            ("2.1 stereo pair", 0xB, [1, 1, 0], 2),
            ("3.0 left", 0x7, [1, 0, 0], 1),
            ("3.0 right", 0x7, [0, 1, 0], 1),
            ("3.0 center", 0x7, [0, 0, 1], 1),
            ("3.0 all fronts", 0x7, [1, 1, 1], 3),
        ]
        for reference in references {
            let url = try writeReferenceTone(
                segments: [(4, pow(10, -23.0 / 20))],
                channelGains: reference.gains, channelMask: reference.mask
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTAssertEqual(result.integratedLoudness, -23 + 10 * log10(reference.weight / 2),
                           accuracy: 0.1, reference.name)
            XCTAssertEqual(result.truePeak, -23, accuracy: 0.1, reference.name)
        }
    }

    func testIndependentSideSurroundChannelReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // ITU-R BS.2217-2 Table 1 assigns 1.41 energy weight to each side
        // surround. Explicit WAV speaker masks distinguish side from back
        // layouts; energize one channel at a time to catch order mistakes.
        // WAVE order: FL, FR, FC, LFE, SL, SR (mask 0x60F).
        for (channel, weight) in [(0, 1.0), (1, 1.0), (2, 1.0), (4, 1.41), (5, 1.41)] {
            var gains = [Double](repeating: 0, count: 6)
            gains[channel] = 1
            let url = try writeReferenceTone(
                segments: [(4, pow(10, -23.0 / 20))],
                channelGains: gains, channelMask: 0x60F
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTAssertEqual(result.integratedLoudness, -23 + 10 * log10(weight / 2),
                           accuracy: 0.1, "5.1(side) channel \(channel)")
            XCTAssertEqual(result.truePeak, -23, accuracy: 0.1)
        }
    }

    func testIndependentSevenPointOneSurroundReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // ITU-R BS.1770-5 Annex 3, Tables 4–5: rear ±135° speakers have
        // unit energy weight; side ±90° speakers have weight 1.41.
        // https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf
        // WAVE mask 0x63F order: FL, FR, FC, LFE, BL, BR, SL, SR.
        for sampleRate in [44_100, 48_000, 96_000] {
            for (channel, weight) in [(0, 1.0), (1, 1.0), (2, 1.0), (4, 1.0), (5, 1.0), (6, 1.41), (7, 1.41)] {
                var gains = [Double](repeating: 0, count: 8)
                gains[channel] = 1
                let url = try writeReferenceTone(
                    segments: [(4, pow(10, -23.0 / 20))], sampleRate: sampleRate,
                    channelGains: gains, channelMask: 0x63F
                )
                defer { try? FileManager.default.removeItem(at: url) }
                let result = try await FFmpegService.analyzeLUFS(
                    url: url, audioStreamIndex: 0, channels: 8, channelLayout: "7.1"
                )
                XCTAssertEqual(result.integratedLoudness, -23 + 10 * log10(weight / 2),
                               accuracy: 0.1, "7.1 channel \(channel) at \(sampleRate) Hz")
                XCTAssertEqual(result.truePeak, -23, accuracy: 0.1)
                XCTAssertEqual(result.weightingCorrection, .bs1770Conventional7Point1RearChannels)
            }
        }
    }

    func testSevenPointOneMixedChannelsAndSelectedRange() async throws {
        let url = try writeReferenceTone(
            segments: [(4, pow(10, -23.0 / 20)), (4, pow(10, -43.0 / 20))],
            channelGains: [1, 0.5, 0.25, 10, 0.75, 0.4, 0.6, 0.2], channelMask: 0x63F
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let energy = 1 + 0.25 + 0.0625 + 0.5625 + 0.16 + 1.41 * (0.36 + 0.04)
        for (start, level) in [(0.25, -23.0), (4.25, -43.0)] {
            let range = try FFmpegService.LoudnessRange(start: start, end: start + 3.5)
            let result = try await FFmpegService.analyzeLUFS(
                url: url, audioStreamIndex: 0, range: range, channels: 8, channelLayout: "7.1"
            )
            XCTAssertEqual(result.integratedLoudness, level + 10 * log10(energy / 2), accuracy: 0.1)
            XCTAssertEqual(result.truePeak, level + 20, accuracy: 0.1, "LFE remains the unmodified peak")
            XCTAssertEqual(result.analysisRange, range)
        }
    }

    func testSevenPointOneCorrectionSelectsTheRequestedAudioStream() async throws {
        let stereo = try writeReferenceTone(segments: [(3, pow(10, -43.0 / 20))])
        let surround = try writeReferenceTone(
            segments: [(3, pow(10, -23.0 / 20))],
            channelGains: [0, 0, 0, 0, 1, 0, 0, 0], channelMask: 0x63F
        )
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("loudness-streams-\(UUID().uuidString).mov")
        defer {
            for url in [stereo, surround, container] { try? FileManager.default.removeItem(at: url) }
        }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-i", stereo.path, "-i", surround.path,
            "-map", "0:a:0", "-map", "1:a:0", "-c:a", "pcm_f32le", container.path,
        ])
        let metadata = try await MetadataService.shared.metadata(for: container)
        XCTAssertEqual(metadata.audioStreams.count, 2)
        let stream = try XCTUnwrap(metadata.audioStreams.last)
        XCTAssertEqual(stream.channels, 8)
        XCTAssertEqual(stream.channelLayout, "7.1")
        let result = try await FFmpegService.analyzeLUFS(
            url: container, audioStreamIndex: 1, channels: stream.channels, channelLayout: stream.channelLayout
        )
        XCTAssertEqual(result.integratedLoudness, -26, accuracy: 0.1)
        XCTAssertEqual(result.truePeak, -23, accuracy: 0.1)
        XCTAssertEqual(result.weightingCorrection, .bs1770Conventional7Point1RearChannels)
    }

    func testSevenPointOneRearGatingAndLoudnessRange() async throws {
        // Two rear speakers now have exactly the same energy weights as stereo.
        // Relative-gated LRA should retain the 15 LU spread, excluding -50 LUFS.
        let url = try writeReferenceTone(
            segments: [-50.0, -35, -20, -35, -50].map { (20, pow(10, $0 / 20)) },
            channelGains: [0, 0, 0, 0, 1, 1, 0, 0], channelMask: 0x63F
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await FFmpegService.analyzeLUFS(
            url: url, audioStreamIndex: 0, channels: 8, channelLayout: "7.1"
        )
        XCTAssertEqual(result.loudnessRange, 15, accuracy: 1)
        // The -35 sections survive the integrated gate; only -50 is excluded.
        let gatedMean = 10 * log10((pow(10, -2) + 2 * pow(10, -3.5)) / 3)
        XCTAssertEqual(result.integratedLoudness, gatedMean, accuracy: 0.2)
        XCTAssertEqual(result.truePeak, -20, accuracy: 0.1)
    }

    func testSevenPointOneRearIntersamplePeakIsPreserved() async throws {
        for sampleRate in [44_100, 48_000, 96_000] {
            let url = try writeReferenceTone(
                segments: [(2, 0.5)], frequency: Double(sampleRate) / 4,
                phase: .pi / 4, fadeSeconds: 0.01, sampleRate: sampleRate,
                channelGains: [0, 0, 0, 0, 1, 0, 0, 0], channelMask: 0x63F
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let original = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            let corrected = try await FFmpegService.analyzeLUFS(
                url: url, audioStreamIndex: 0, channels: 8, channelLayout: "7.1"
            )
            XCTAssertEqual(corrected.truePeak, original.truePeak, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(corrected.truePeak, -6.4)
            XCTAssertLessThanOrEqual(corrected.truePeak, -5.8)
        }
    }

    func testSevenPointOneAnalysisMappingPreservesEverySample() async throws {
        let url = try writeReferenceTone(
            segments: [(1, 0.5)], channelGains: [1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3],
            channelMask: 0x63F
        )
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("mapped-\(UUID().uuidString).pcm")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: output)
        }
        let arguments = try FFmpegService.loudnessArguments(
            url: url, audioStreamIndex: 0, channels: 8, channelLayout: "7.1"
        )
        let filterIndex = try XCTUnwrap(arguments.firstIndex(of: "-af"))
        // Run the production graph including the meter, then compare its output
        // against the independently written WAV payload (68-byte extended header).
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-i", url.path, "-map", "0:a:0", "-af", arguments[filterIndex + 1],
            "-c:a", "pcm_f32le", "-f", "f32le", output.path,
        ])
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: url).dropFirst(68))
    }

    func testSevenPointOneIncorrectSourceLayoutFailsInsteadOfRemixing() async throws {
        let url = try writeReferenceTone(segments: [(1, 0.5)])
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await FFmpegService.analyzeLUFS(
                url: url, audioStreamIndex: 0, channels: 8, channelLayout: "7.1"
            )
            XCTFail("A stereo source must not be silently expanded into a corrected 7.1 measurement")
        } catch FFmpegError.processFailed { }
    }

    func testSevenPointOneCorrectionRequiresExplicitMatchingLayout() throws {
        let url = URL(fileURLWithPath: "/tmp/test.wav")
        for (channels, layout) in [(nil, nil), (8, nil), (nil, "7.1"), (6, "7.1"), (8, "7.1(wide)"), (8, "octagonal")] as [(Int?, String?)] {
            let arguments = try FFmpegService.loudnessArguments(
                url: url, audioStreamIndex: 0, channels: channels, channelLayout: layout
            )
            XCTAssertFalse(arguments.joined().contains("channelmap"))
        }
    }

    func testLoudnessCorrectionCodableCompatibility() throws {
        let legacy = Data(#"{"integratedLoudness":-23,"loudnessRange":0,"truePeak":-23}"#.utf8)
        var result = try JSONDecoder().decode(FFmpegService.LUFSResult.self, from: legacy)
        XCTAssertNil(result.weightingCorrection)
        result.weightingCorrection = .bs1770Conventional7Point1RearChannels
        let decoded = try JSONDecoder().decode(FFmpegService.LUFSResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.weightingCorrection, result.weightingCorrection)
    }

    func testIndependentLFEExclusionStillIncludesLFETruePeakAcrossLayouts() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // The LFE is 20 dB louder than the calibrated front stereo pair. It
        // must dominate true peak while adding no energy to integrated LUFS.
        let references: [(name: String, mask: UInt32, gains: [Double])] = [
            ("2.1", 0xB, [1, 1, 10]),
            ("5.1(side)", 0x60F, [1, 1, 0, 10, 0, 0]),
            ("7.1", 0x63F, [1, 1, 0, 10, 0, 0, 0, 0]),
        ]
        for reference in references {
            let url = try writeReferenceTone(
                segments: [(4, pow(10, -23.0 / 20))],
                channelGains: reference.gains, channelMask: reference.mask
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0,
                channels: reference.gains.count, channelLayout: reference.name)
            XCTAssertEqual(result.integratedLoudness, -23, accuracy: 0.1, reference.name)
            XCTAssertEqual(result.truePeak, -3, accuracy: 0.1, reference.name)
        }
    }

    /// Little-endian IEEE Float32 WAV, with in-phase channels at explicit gains.
    /// Float PCM preserves the reference levels without integer quantization.
    private func writeReferenceTone(
        segments: [(seconds: Int, amplitude: Double)], frequency: Double = 1_000,
        phase: Double = 0, fadeSeconds: Double = 0, sampleRate: Int = 48_000,
        channelGains: [Double] = [1, 1], channelMask: UInt32? = nil
    ) throws -> URL {
        let frames = segments.reduce(0) { $0 + $1.seconds * sampleRate }
        let blockAlign = channelGains.count * MemoryLayout<Float>.size
        let payloadBytes = frames * blockAlign
        let formatBytes = channelMask == nil ? 16 : 40
        var data = Data(capacity: 28 + formatBytes + payloadBytes)
        func appendInteger<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        appendInteger(UInt32(20 + formatBytes + payloadBytes))
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendInteger(UInt32(formatBytes))
        appendInteger(UInt16(channelMask == nil ? 3 : 0xFFFE)) // IEEE_FLOAT or EXTENSIBLE
        appendInteger(UInt16(channelGains.count))
        appendInteger(UInt32(sampleRate))
        appendInteger(UInt32(sampleRate * blockAlign))
        appendInteger(UInt16(blockAlign))
        appendInteger(UInt16(32))
        if let channelMask {
            // WAVEFORMATEXTENSIBLE: ascending mask bits define channel order.
            // https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ksmedia/ns-ksmedia-waveformatextensible
            precondition(channelMask.nonzeroBitCount == channelGains.count)
            appendInteger(UInt16(22)) // Extension size
            appendInteger(UInt16(32)) // Valid bits per sample
            appendInteger(channelMask)
            // KSDATAFORMAT_SUBTYPE_IEEE_FLOAT: 00000003-0000-0010-8000-00AA00389B71
            appendInteger(UInt32(3))
            appendInteger(UInt16(0))
            appendInteger(UInt16(0x10))
            data.append(contentsOf: [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])
        }
        data.append(contentsOf: "data".utf8)
        appendInteger(UInt32(payloadBytes))
        let fadeFrames = Int(fadeSeconds * Double(sampleRate))
        var frame = 0
        for segment in segments {
            for _ in 0..<(segment.seconds * sampleRate) {
                let envelope = fadeFrames == 0 ? 1 : min(
                    1, Double(min(frame, frames - 1 - frame)) / Double(fadeFrames)
                )
                let sample = segment.amplitude * envelope * sin(
                    2 * .pi * frequency * Double(frame) / Double(sampleRate) + phase
                )
                for gain in channelGains {
                    appendInteger(Float(sample * gain).bitPattern)
                }
                frame += 1
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ebu-reference-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    func testWholeFileKeepsStreamSelectionWithoutTrimming() throws {
        let arguments = try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media with spaces.wav"), audioStreamIndex: 2
        )
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "-map")) + 1], "0:a:2")
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "-af")) + 1], "ebur128=peak=true")
        XCTAssertTrue(arguments.contains("/tmp/media with spaces.wav"))
    }

    func testRangeTrimsSamplesBeforeLoudnessFilter() throws {
        let range = try FFmpegService.LoudnessRange(start: 1.125, end: 4.875)
        let arguments = try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media.wav"), audioStreamIndex: 0, range: range
        )
        let filter = arguments[try XCTUnwrap(arguments.firstIndex(of: "-af")) + 1]
        XCTAssertEqual(filter, "atrim=start=1.125:end=4.875,asetpts=PTS-STARTPTS,ebur128=peak=true")
        let limitIndex = try XCTUnwrap(arguments.firstIndex(of: "-t"))
        XCTAssertEqual(arguments[limitIndex + 1], "4.875")
        XCTAssertLessThan(limitIndex, try XCTUnwrap(arguments.firstIndex(of: "-i")), "Bound demuxing at the input so trailing material is not decoded")
        XCTAssertFalse(arguments.contains("-c"), "Range analysis must decode samples rather than stream-copy keyframes")
    }

    func testInvalidRangesAndStreamAreRejected() throws {
        for (start, end) in [(-1.0, 2.0), (2, 2), (3, 2), (.nan, 2), (0, .infinity), (-.infinity, 2)] {
            XCTAssertThrowsError(try FFmpegService.LoudnessRange(start: start, end: end)) {
                XCTAssertEqual($0 as? FFmpegError, .invalidLoudnessRange)
            }
        }
        XCTAssertThrowsError(try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media.wav"), audioStreamIndex: -1
        )) { XCTAssertEqual($0 as? FFmpegError, .invalidAudioStream) }

        let decoded = try JSONDecoder().decode(
            FFmpegService.LoudnessRange.self, from: Data(#"{"start":4,"end":2}"#.utf8)
        )
        XCTAssertThrowsError(try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media.wav"), audioStreamIndex: 0, range: decoded
        )) { XCTAssertEqual($0 as? FFmpegError, .invalidLoudnessRange) }
    }

    func testSelectedRangeMeasuresOnlyItsSamplesAndExportsBounds() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        // The second three seconds are 20 dB quieter. Non-integer boundaries
        // also exercise sample trimming independently of packet boundaries.
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:sample_rate=48000:duration=6",
            "-af", "volume=if(lt(t\\,3)\\,1\\,0.1):eval=frame", "-y", url.path,
        ])
        let loudRange = try FFmpegService.LoudnessRange(start: 0.25, end: 2.75)
        let quietRange = try FFmpegService.LoudnessRange(start: 3.25, end: 5.75)
        let loud = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: loudRange)
        let quiet = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: quietRange)
        XCTAssertEqual(loud.integratedLoudness - quiet.integratedLoudness, 20, accuracy: 0.2)
        XCTAssertEqual(loud.truePeak - quiet.truePeak, 20, accuracy: 0.2)
        XCTAssertEqual(quiet.analysisRange, quietRange)
        let decoded = try JSONDecoder().decode(FFmpegService.LUFSResult.self, from: JSONEncoder().encode(quiet))
        XCTAssertEqual(decoded.analysisRange, quietRange)

        // Container timestamps need not start at zero. Marker seconds still
        // address time relative to the file, rather than its raw packet PTS.
        let offsetURL = url.deletingPathExtension().appendingPathExtension("mka")
        defer { try? FileManager.default.removeItem(at: offsetURL) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-i", url.path,
            "-c:a", "copy", "-output_ts_offset", "7", "-y", offsetURL.path,
        ])
        let offsetQuiet = try await FFmpegService.analyzeLUFS(url: offsetURL, audioStreamIndex: 0, range: quietRange)
        XCTAssertEqual(offsetQuiet.integratedLoudness, quiet.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(offsetQuiet.truePeak, quiet.truePeak, accuracy: 0.1)

        let delayedURL = url.deletingPathExtension().appendingPathExtension("delayed.mka")
        defer { try? FileManager.default.removeItem(at: delayedURL) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-i", url.path,
            "-itsoffset", "1", "-i", url.path, "-map", "0:a:0", "-map", "1:a:0",
            "-c:a", "copy", "-y", delayedURL.path,
        ])
        // Stream 1's level drops at source second 4, not second 3. Resetting
        // each stream's initial timestamp before trimming would choose quiet audio.
        let delayedRange = try FFmpegService.LoudnessRange(start: 3.25, end: 3.75)
        let delayedLoud = try await FFmpegService.analyzeLUFS(url: delayedURL, audioStreamIndex: 1, range: delayedRange)
        XCTAssertEqual(delayedLoud.integratedLoudness, loud.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(delayedLoud.truePeak, loud.truePeak, accuracy: 0.1)

    }

    func testSilenceCanBeCopiedAsMetadataJSON() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "anullsrc=r=48000:cl=mono", "-t", "1", "-c:a", "alac", "-y", url.path,
        ])
        let range = try FFmpegService.LoudnessRange(start: 0, end: 1)
        let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: range)
        XCTAssertEqual(result.truePeak, -.infinity)
        let metadata = try await MetadataService.shared.metadata(for: url)
        let data = try MetadataInspectorView.metadataJSON(metadata: metadata, lufsResults: [0: result])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let streams = try XCTUnwrap(object["audioStreams"] as? [[String: Any]])
        let lufs = try XCTUnwrap(streams.first?["lufs"] as? [String: Any])
        XCTAssertEqual(lufs["truePeak"] as? String, "-Infinity")
        let bounds = try XCTUnwrap(lufs["analysisRange"] as? [String: Double])
        XCTAssertEqual(bounds["start"], 0)
        XCTAssertEqual(bounds["end"], 1)
    }

    func testMetadataJSONQualifiesOnlyMeasuredSevenPointOneStreams() throws {
        let layouts = ["7.1", "5.1(side)", "7.1"]
        let streams = layouts.enumerated().map { index, layout in
            MediaMetadata.AudioStream(
                index: index + 2, languageCode: nil, title: nil, codec: "pcm_f32le",
                codecLongName: nil, profile: nil, sampleRate: 48_000,
                channels: layout == "7.1" ? 8 : 6, channelLayout: layout,
                bitDepth: 32, bitRate: nil, isDefault: index == 0
            )
        }
        let metadata = MediaMetadata(
            duration: 4, formatName: nil, containerLongName: nil, sizeBytes: nil,
            bitRate: nil, timecode: nil, comment: nil, encoder: nil, frameCount: nil,
            videoStreams: [], audioStreams: streams, subtitleStreams: [], chapters: []
        )
        let measurement = FFmpegService.LUFSResult(
            integratedLoudness: -23, loudnessRange: 0, truePeak: -23
        )
        let data = try MetadataInspectorView.metadataJSON(
            metadata: metadata, lufsResults: [0: measurement, 1: measurement]
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exported = try XCTUnwrap(object["audioStreams"] as? [[String: Any]])
        XCTAssertEqual(exported.count, 3)
        let warning = try XCTUnwrap(exported[0]["lufsWarning"] as? String)
        XCTAssertTrue(warning.contains("7.1"))
        XCTAssertNotNil(exported[0]["lufs"])
        XCTAssertNil(exported[1]["lufsWarning"], "5.1 has no demonstrated rear weighting limitation")
        XCTAssertNotNil(exported[1]["lufs"])
        XCTAssertNil(exported[2]["lufsWarning"], "An unmeasured stream has no result to qualify")
        XCTAssertNil(exported[2]["lufs"])
        var corrected = measurement
        corrected.weightingCorrection = .bs1770Conventional7Point1RearChannels
        let correctedData = try MetadataInspectorView.metadataJSON(metadata: metadata, lufsResults: [0: corrected])
        let correctedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: correctedData) as? [String: Any])
        let correctedStreams = try XCTUnwrap(correctedObject["audioStreams"] as? [[String: Any]])
        XCTAssertNil(correctedStreams[0]["lufsWarning"])
        XCTAssertNotNil(correctedStreams[0]["lufsNote"])
        let correctedLUFS = try XCTUnwrap(correctedStreams[0]["lufs"] as? [String: Any])
        XCTAssertEqual(correctedLUFS["weightingCorrection"] as? String, "bs1770Conventional7Point1RearChannels")
    }

    func testMultichannelStreamWeightingAndIndependentTrackSelection() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("multichannel-loudness-\(UUID().uuidString).mka")
        defer { try? FileManager.default.removeItem(at: url) }
        // All six channels have the same samples. R128 sums three front
        // channels and two surrounds weighted by 1.41, excluding the LFE.
        // The third track is 20 dB quieter to catch accidental stream mixing.
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:sample_rate=48000:duration=3",
            "-filter_complex", "[0:a]asplit=3[mono][surround][quiet];[surround]pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0[six];[quiet]volume=0.1[low]",
            "-map", "[mono]", "-map", "[six]", "-map", "[low]",
            "-c:a", "pcm_s24le", "-y", url.path,
        ])
        let mono = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        let surround = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 1)
        let quiet = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 2)
        XCTAssertEqual(surround.integratedLoudness - mono.integratedLoudness, 10 * log10(3 + 2 * 1.41), accuracy: 0.2)
        XCTAssertEqual(surround.truePeak, mono.truePeak, accuracy: 0.1, "True peak is a channel maximum, not the summed loudness")
        XCTAssertEqual(mono.integratedLoudness - quiet.integratedLoudness, 20, accuracy: 0.2)
        XCTAssertEqual(mono.truePeak - quiet.truePeak, 20, accuracy: 0.2)
        XCTAssertNil(surround.analysisRange)

        let range = try FFmpegService.LoudnessRange(start: 0.25, end: 2.75)
        let selected = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 1, range: range)
        XCTAssertEqual(selected.integratedLoudness, surround.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(selected.truePeak, surround.truePeak, accuracy: 0.1)
        XCTAssertEqual(selected.analysisRange, range)
    }

    func testMalformedAudioAndMissingStreamFailWithoutPublishingMeasurements() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("This is not a WAV file".utf8).write(to: url)
        do {
            _ = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTFail("Malformed audio must fail instead of returning a silence summary")
        } catch FFmpegError.processFailed(let message) {
            XCTAssertFalse(message.isEmpty)
        }

        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=1", "-y", url.path,
        ])
        do {
            _ = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 1)
            XCTFail("A missing stream must not fall back to a different audio track")
        } catch FFmpegError.processFailed(let message) {
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testCancelledAnalysisReturnsCancellationAndSubsequentAnalysisSucceeds() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cancelled-loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=1", "-y", url.path,
        ])
        // Main-actor serialization makes cancellation-before-start deterministic.
        let task = Task { @MainActor in
            try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled analysis must never return a measurement")
        } catch {
            XCTAssertEqual(error as? FFmpegError, .cancelled)
        }
        let retry = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        XCTAssertTrue(retry.integratedLoudness.isFinite)
        XCTAssertTrue(retry.truePeak.isFinite)
    }

    func testEmptySelectionsBeyondEOFAndBeforeDelayedStreamAreRejected() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-loudness-\(UUID().uuidString).mka")
        defer { try? FileManager.default.removeItem(at: url) }
        // The file spans four seconds, but the second stream starts at second
        // two. A valid interval in the media timeline can contain no samples
        // for that stream. The first stream is real digital silence.
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "anullsrc=r=48000:cl=mono:d=4", "-itsoffset", "2", "-f", "lavfi",
            "-i", "sine=frequency=1000:sample_rate=48000:duration=2",
            "-map", "0:a:0", "-map", "1:a:0", "-c:a", "pcm_s24le", "-y", url.path,
        ])
        let beforeAudio = try FFmpegService.LoudnessRange(start: 0.25, end: 1.25)
        let beyondEOF = try FFmpegService.LoudnessRange(start: 8, end: 10)
        for (stream, range) in [(0, beyondEOF), (1, beforeAudio)] {
            do {
                _ = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: stream, range: range)
                XCTFail("An interval without decoded samples must not return FFmpeg's default summary")
            } catch {
                XCTAssertEqual(error as? FFmpegError, .loudnessNoSamples)
            }
        }
        let silence = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: beforeAudio)
        XCTAssertEqual(silence.truePeak, -.infinity, "Actual silence has samples and must remain measurable")
        let audible = try await FFmpegService.analyzeLUFS(
            url: url, audioStreamIndex: 1,
            range: FFmpegService.LoudnessRange(start: 2.25, end: 3.25)
        )
        XCTAssertTrue(audible.truePeak.isFinite)
    }

}
