// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class TrimExportValidatorTests: XCTestCase {
    func testAcceptsPreservedContainer() throws {
        try TrimExportValidator.validateStreamCopy(
            sourceURL: URL(fileURLWithPath: "/tmp/source.mov"),
            destinationURL: URL(fileURLWithPath: "/tmp/source_trimmed.mov"),
            metadata: nil
        )
    }

    func testAcceptsEquivalentContainerExtensions() throws {
        try TrimExportValidator.validateStreamCopy(
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            destinationURL: URL(fileURLWithPath: "/tmp/source_trimmed.m4v"),
            metadata: nil
        )
    }

    func testRejectsContainerChangeBeforeExport() {
        XCTAssertThrowsError(
            try TrimExportValidator.validateStreamCopy(
                sourceURL: URL(fileURLWithPath: "/tmp/source.mkv"),
                destinationURL: URL(fileURLWithPath: "/tmp/source_trimmed.mp4"),
                metadata: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? TrimExportValidationError,
                .containerChangeRequiresReencoding(source: "mkv", destination: "mp4")
            )
        }
    }

    func testRejectsMissingContainerExtension() {
        XCTAssertThrowsError(
            try TrimExportValidator.validateStreamCopy(
                sourceURL: URL(fileURLWithPath: "/tmp/source"),
                destinationURL: URL(fileURLWithPath: "/tmp/source_trimmed"),
                metadata: nil
            )
        ) { error in
            XCTAssertEqual(error as? TrimExportValidationError, .missingContainerExtension)
        }
    }

    func testRejectsMetadataWithoutCopyableStreams() {
        let metadata = MediaMetadata(
            duration: 1,
            formatName: "mov",
            containerLongName: "QuickTime / MOV",
            sizeBytes: 1,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [],
            subtitleStreams: [],
            chapters: []
        )

        XCTAssertThrowsError(
            try TrimExportValidator.validateStreamCopy(
                sourceURL: URL(fileURLWithPath: "/tmp/source.mov"),
                destinationURL: URL(fileURLWithPath: "/tmp/source_trimmed.mov"),
                metadata: metadata
            )
        ) { error in
            XCTAssertEqual(error as? TrimExportValidationError, .noCopyableStreams)
        }
    }
}
