// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ITUProgrammeLoudnessTests: XCTestCase {
    /// The official programme audio remains outside the repository. Set the
    /// directory explicitly to run these independent, whole-file references.
    func testOfficialProgrammeReferencesWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ITU_LOUDNESS_REFERENCE_DIRECTORY"] else { return }
        XCTAssertFalse(directory.isEmpty, "Specify the directory containing all three official WAV files")
        guard !directory.isEmpty else { return }
        // ITU-R BS.2217-2, programme rows on printed pages 4–5: -23 ±0.1 LKFS.
        // https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BS.2217-2-2016-PDF-E.pdf
        // Archive downloads: https://www.itu.int/oth/R1102000001/en
        // These hashes identify the downloaded originals, not synthetic copies.
        let references: [(file: String, channels: Int, sha256: String)] = [
            ("1770-2 Conf Mono Voice+Music-23LKFS.wav", 1,
             "f8b318474b158c9f2ee842f0cfadf58ffcf504ffe8daa172220190d12dd0785b"),
            ("1770-2 Conf Stereo VinL+R-23LKFS.wav", 2,
             "3ff26c997d838aff36b4319f9e0a673c0b51fe26722ecb0153887b66f38c296f"),
            ("1770-2 Conf 6ch VinCntr-23LKFS.wav", 6,
             "ef2a0baef7f50db39eddfb1ba6f2a5445646050d113f81c6365cddca7f0448a0"),
        ]
        for reference in references {
            let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(reference.file)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, reference.sha256, "Reference bytes changed: \(reference.file)")
            guard digest == reference.sha256 else { continue }

            let metadata = try await MetadataService.shared.metadata(for: url)
            XCTAssertEqual(metadata.audioStreams.count, 1, reference.file)
            let stream = try XCTUnwrap(metadata.audioStreams.first)
            XCTAssertEqual(stream.channels, reference.channels, reference.file)
            XCTAssertEqual(stream.sampleRate, 48_000, reference.file)
            let result = try await FFmpegService.analyzeLUFS(
                url: url, audioStreamIndex: 0,
                channels: stream.channels, channelLayout: stream.channelLayout
            )
            let report: [String: Any] = [
                "file": reference.file, "sha256": digest,
                "channels": stream.channels ?? 0, "sampleRate": stream.sampleRate ?? 0,
                "channelLayout": stream.channelLayout ?? "unspecified",
                "expectedIntegratedLUFS": -23.0, "toleranceLU": 0.1,
                "integratedLUFS": String(result.integratedLoudness),
                // BS.2217-2 gives no LRA/true-peak targets for these programmes.
                "unreferencedObservations": [
                    "loudnessRangeLU": String(result.loudnessRange),
                    "truePeakDBTP": String(result.truePeak),
                ],
            ]
            let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let line = "ITU_PROGRAMME_LOUDNESS " + String(decoding: reportData, as: UTF8.self)
            print(line)
            let attachment = XCTAttachment(string: line)
            attachment.name = "ITU programme loudness — \(reference.channels) channels"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertNil(result.analysisRange)
            XCTAssertEqual(result.integratedLoudness, -23.0, accuracy: 0.1, reference.file)
        }
    }
}
