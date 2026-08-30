// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum TrimExportValidationError: Error, LocalizedError, Equatable {
    case missingContainerExtension
    case containerChangeRequiresReencoding(source: String, destination: String)
    case noCopyableStreams

    nonisolated var errorDescription: String? {
        switch self {
        case .missingContainerExtension:
            return "Lossless copy requires a source and destination file extension. Choose an exact re-encode format instead."
        case .containerChangeRequiresReencoding(let source, let destination):
            return "Lossless copy cannot change the container from .\(source) to .\(destination) because the existing codecs may not be compatible. Keep the .\(source) extension or choose an exact re-encode format."
        case .noCopyableStreams:
            return "The source contains no audio, video, or subtitle streams that can be copied."
        }
    }
}

/// Preflight checks for lossless trim exports.
///
/// Stream copy deliberately preserves the source container. Allowing a new container
/// would require a codec-by-codec muxer matrix and can otherwise fail only after ffmpeg
/// has started. Equivalent filename extensions are grouped into the same container.
enum TrimExportValidator {
    nonisolated static func validateStreamCopy(
        sourceURL: URL,
        destinationURL: URL,
        metadata: MediaMetadata?
    ) throws {
        let sourceExtension = normalizedExtension(sourceURL.pathExtension)
        let destinationExtension = normalizedExtension(destinationURL.pathExtension)

        guard !sourceExtension.isEmpty, !destinationExtension.isEmpty else {
            throw TrimExportValidationError.missingContainerExtension
        }

        guard containerFamily(for: sourceExtension) == containerFamily(for: destinationExtension) else {
            throw TrimExportValidationError.containerChangeRequiresReencoding(
                source: sourceExtension,
                destination: destinationExtension
            )
        }

        if let metadata,
           metadata.videoStreams.isEmpty,
           metadata.audioStreams.isEmpty,
           metadata.subtitleStreams.isEmpty {
            throw TrimExportValidationError.noCopyableStreams
        }
    }

    nonisolated private static func normalizedExtension(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func containerFamily(for fileExtension: String) -> String {
        switch fileExtension {
        case "mp4", "m4v", "m4a":
            return "mp4"
        case "mkv", "mka", "mks":
            return "matroska"
        case "tif", "tiff":
            return "tiff"
        case "jpg", "jpeg":
            return "jpeg"
        case "wav", "wave":
            return "wave"
        default:
            return fileExtension
        }
    }
}
