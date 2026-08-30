// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum OutputCoordinatorError: Error, LocalizedError, Equatable {
    case temporaryOutputMissing

    var errorDescription: String? {
        switch self {
        case .temporaryOutputMissing:
            return "The encoder did not produce an output file."
        }
    }
}

/// A pending media output that is encoded beside its destination and only
/// moved into place after the encoder has completed successfully.
struct CoordinatedOutput: Sendable {
    enum ExistingFilePolicy: Sendable {
        /// Automatic destinations must never replace a user's existing file.
        case chooseUniqueName
        /// An NSSavePanel selection may replace a file after explicit confirmation.
        case replaceConfirmed
    }

    let destinationURL: URL
    let temporaryURL: URL
    let existingFilePolicy: ExistingFilePolicy

    /// Atomically publishes the completed sibling temporary file.
    /// Returns the actual destination, which may gain a numeric suffix if an
    /// automatic destination appeared while encoding was in progress.
    func commit(fileManager: FileManager = .default) throws -> URL {
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            throw OutputCoordinatorError.temporaryOutputMissing
        }

        switch existingFilePolicy {
        case .replaceConfirmed:
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            return destinationURL

        case .chooseUniqueName:
            var candidate = destinationURL
            var suffix = 2

            while true {
                if fileManager.fileExists(atPath: candidate.path) {
                    candidate = Self.urlByAddingSuffix(suffix, to: destinationURL)
                    suffix += 1
                    continue
                }

                do {
                    // A same-volume move is atomic. FileManager refuses to move
                    // over an existing item, so a concurrent collision is safe.
                    try fileManager.moveItem(at: temporaryURL, to: candidate)
                    return candidate
                } catch {
                    if fileManager.fileExists(atPath: candidate.path) {
                        candidate = Self.urlByAddingSuffix(suffix, to: destinationURL)
                        suffix += 1
                        continue
                    }
                    throw error
                }
            }
        }
    }

    func discard(fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: temporaryURL.path) else { return }
        try? fileManager.removeItem(at: temporaryURL)
    }

    fileprivate static func urlByAddingSuffix(_ suffix: Int, to url: URL) -> URL {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let filename = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(filename)
    }
}

enum OutputCoordinator {
    static func automatic(directory: URL, preferredFilename: String, fileManager: FileManager = .default) -> CoordinatedOutput {
        let preferredURL = directory.appendingPathComponent(preferredFilename)
        var destinationURL = preferredURL
        var suffix = 2

        while fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = CoordinatedOutput.urlByAddingSuffix(suffix, to: preferredURL)
            suffix += 1
        }

        return CoordinatedOutput(
            destinationURL: destinationURL,
            temporaryURL: temporarySibling(for: destinationURL),
            existingFilePolicy: .chooseUniqueName
        )
    }

    static func userConfirmed(destinationURL: URL) -> CoordinatedOutput {
        CoordinatedOutput(
            destinationURL: destinationURL,
            temporaryURL: temporarySibling(for: destinationURL),
            existingFilePolicy: .replaceConfirmed
        )
    }

    private static func temporarySibling(for destinationURL: URL) -> URL {
        let ext = destinationURL.pathExtension
        let stem = destinationURL.deletingPathExtension().lastPathComponent
        let token = UUID().uuidString.lowercased()
        let filename = ext.isEmpty
            ? ".\(stem).\(token).partial"
            : ".\(stem).\(token).partial.\(ext)"
        return destinationURL.deletingLastPathComponent().appendingPathComponent(filename)
    }
}
