// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Darwin

nonisolated enum CompareReviewSidecarError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case sourcePairMismatch
    case invalidNote(Int, String)
    case relinkPreviewChanged
    case relinkDestinationExists
    case relinkSourceUnavailable(String)
    case relinkUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "The comparison notes use unsupported schema version \(version)."
        case .sourcePairMismatch:
            "The comparison notes sidecar belongs to a different source pair."
        case .invalidNote(let number, let reason):
            "Comparison note \(number) is invalid: \(reason). Restore a valid sidecar backup or move this sidecar aside before creating a new review."
        case .relinkPreviewChanged:
            "The selected review changed after preview. Select it again before relinking."
        case .relinkDestinationExists:
            "A review already exists at the destination. Move it aside before relinking; existing reviews are never overwritten."
        case .relinkSourceUnavailable(let path):
            "The replacement source is not a readable regular file: \(path)"
        case .relinkUnavailable:
            "Relinking is unavailable for this review store."
        }
    }
}

nonisolated enum CompareReviewMutation: Sendable {
    case upsert(CompareReviewNote)
    case delete(UUID)
}

nonisolated protocol CompareReviewSidecarStoring: Sendable {
    func previewRelink(from url: URL) async throws -> CompareReviewDocument

    func relink(
        from url: URL,
        to destinationURL: URL,
        primaryURL: URL,
        secondaryURL: URL,
        expectedDocument: CompareReviewDocument
    ) async throws -> CompareReviewDocument

    func load(
        from url: URL,
        primaryURL: URL,
        secondaryURL: URL
    ) async throws -> CompareReviewDocument?

    func apply(
        _ mutation: CompareReviewMutation,
        to url: URL,
        primaryURL: URL,
        secondaryURL: URL
    ) async throws -> CompareReviewDocument
}

nonisolated extension CompareReviewSidecarStoring {
    func previewRelink(from url: URL) async throws -> CompareReviewDocument {
        throw CompareReviewSidecarError.relinkUnavailable
    }

    func relink(
        from url: URL,
        to destinationURL: URL,
        primaryURL: URL,
        secondaryURL: URL,
        expectedDocument: CompareReviewDocument
    ) async throws -> CompareReviewDocument {
        throw CompareReviewSidecarError.relinkUnavailable
    }
}

/// Serializes sidecar access and rejects late writes from an older in-memory
/// revision. Source media is never opened for writing.
actor CompareReviewSidecarStore: CompareReviewSidecarStoring {
    static let shared = CompareReviewSidecarStore()

    // TimecodeRate.init(frameRate:) represents non-broadcast fractional rates
    // with this denominator before reducing the fraction. Reserve that export
    // precision even if a sidecar claims its marker was captured at an integer rate.
    private static let decimalRateTimebase: Int64 = 1_000_000
    private static let sourceTimecodeDaySeconds: Int64 = 86_400

    private var latestRevisionByURL: [URL: UInt64] = [:]

    nonisolated static func sidecarURL(primaryURL: URL, secondaryURL: URL) -> URL {
        let primaryName = shortened(primaryURL.deletingPathExtension().lastPathComponent)
        let secondaryName = shortened(secondaryURL.deletingPathExtension().lastPathComponent)
        let secondaryIdentity = secondaryURL.standardizedFileURL.resolvingSymlinksInPath().path
        let suffix = String(stableHash(secondaryIdentity), radix: 16, uppercase: false)
        let filename = "\(primaryName) vs \(secondaryName)-\(suffix).aagedal-compare.json"
        return primaryURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    func load(
        from url: URL,
        primaryURL: URL,
        secondaryURL: URL
    ) throws -> CompareReviewDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let document = try readDocument(from: url)
        guard document.belongsTo(primaryURL: primaryURL, secondaryURL: secondaryURL) else {
            throw CompareReviewSidecarError.sourcePairMismatch
        }
        return document
    }

    /// Reads the old review without attaching it to any currently loaded media.
    /// Missing original media is expected when a review has been moved.
    func previewRelink(from url: URL) async throws -> CompareReviewDocument {
        try readDocument(from: url)
    }

    private func readDocument(from url: URL) throws -> CompareReviewDocument {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(CompareReviewDocument.self, from: data)
        guard (1...CompareReviewDocument.currentSchemaVersion).contains(document.schemaVersion) else {
            throw CompareReviewSidecarError.unsupportedSchema(document.schemaVersion)
        }
        try Self.validate(document)
        return document
    }

    /// Explicitly maps old A/B to new A/B, preserving every note coordinate and
    /// classification. Publication uses an exclusive rename of a completed
    /// sibling file so competing stores cannot overwrite an existing review.
    func relink(
        from url: URL,
        to destinationURL: URL,
        primaryURL: URL,
        secondaryURL: URL,
        expectedDocument: CompareReviewDocument
    ) async throws -> CompareReviewDocument {
        try Task.checkCancellation()
        let original = try readDocument(from: url)
        guard original == expectedDocument else {
            throw CompareReviewSidecarError.relinkPreviewChanged
        }
        let fileManager = FileManager.default
        for source in [primaryURL, secondaryURL] {
            let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
            let attributes = try? fileManager.attributesOfItem(atPath: canonical.path)
            guard source.isFileURL,
                  attributes?[.type] as? FileAttributeType == .typeRegular,
                  fileManager.isReadableFile(atPath: canonical.path) else {
                throw CompareReviewSidecarError.relinkSourceUnavailable(source.path)
            }
        }
        guard url.standardizedFileURL.resolvingSymlinksInPath() != destinationURL.standardizedFileURL.resolvingSymlinksInPath(),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            throw CompareReviewSidecarError.relinkDestinationExists
        }
        let document = CompareReviewDocument(
            primaryURL: primaryURL, secondaryURL: secondaryURL, notes: original.notes
        )
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).aagedal-compare.partial")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try write(document, to: temporaryURL)
        try Task.checkCancellation()
        // RENAME_EXCL refuses every existing directory entry, including a
        // dangling symlink, without a check-then-rename overwrite race. Unlike
        // hard links, same-volume renames also work on external exFAT volumes.
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let temporaryPath, let destinationPath else {
                    errno = EINVAL
                    return Int32(-1)
                }
                return renamex_np(temporaryPath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let failure = errno
            if failure == EEXIST {
                throw CompareReviewSidecarError.relinkDestinationExists
            }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        return document
    }

    /// Applies one UUID-addressed edit to the latest on-disk document. A
    /// process-wide store serializes windows that review the same source pair,
    /// avoiding full-document last-writer-wins replacement.
    func apply(
        _ mutation: CompareReviewMutation,
        to url: URL,
        primaryURL: URL,
        secondaryURL: URL
    ) throws -> CompareReviewDocument {
        var document = try load(
            from: url,
            primaryURL: primaryURL,
            secondaryURL: secondaryURL
        ) ?? CompareReviewDocument(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            notes: []
        )

        switch mutation {
        case .upsert(let note):
            if let index = document.notes.firstIndex(where: { $0.id == note.id }) {
                document.notes[index] = note
            } else {
                document.notes.append(note)
            }
        case .delete(let id):
            document.notes.removeAll { $0.id == id }
        }
        document.notes.sort {
            if $0.primaryFrame != $1.primaryFrame {
                return $0.primaryFrame < $1.primaryFrame
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        document.schemaVersion = CompareReviewDocument.currentSchemaVersion
        try write(document, to: url)
        return document
    }

    func save(
        _ document: CompareReviewDocument,
        to url: URL,
        revision: UInt64
    ) throws {
        let latestRevision = latestRevisionByURL[url] ?? 0
        guard revision >= latestRevision else { return }
        try write(document, to: url)
        latestRevisionByURL[url] = revision
    }

    private func write(_ document: CompareReviewDocument, to url: URL) throws {
        guard (1...CompareReviewDocument.currentSchemaVersion).contains(document.schemaVersion) else {
            throw CompareReviewSidecarError.unsupportedSchema(document.schemaVersion)
        }
        try Self.validate(document)
        var document = document
        document.schemaVersion = CompareReviewDocument.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    private static func validate(_ document: CompareReviewDocument) throws {
        var ids = Set<UUID>()
        for (index, note) in document.notes.enumerated() {
            let number = index + 1
            guard ids.insert(note.id).inserted else {
                throw CompareReviewSidecarError.invalidNote(number, "duplicate note identifier")
            }
            if let endFrame = note.primaryEndFrame, endFrame < note.primaryFrame {
                throw CompareReviewSidecarError.invalidNote(number, "source A range ends before its start")
            }
            for (source, frame, time, numerator, denominator) in [
                ("A", note.primaryFrame, note.primaryTime, note.primaryRateNumerator, note.primaryRateDenominator),
                ("A range end", note.primaryEndFrame ?? note.primaryFrame, note.primaryTime, note.primaryRateNumerator, note.primaryRateDenominator),
                ("B", note.secondaryFrame, note.secondaryTime, note.secondaryRateNumerator, note.secondaryRateDenominator),
            ] {
                guard frame >= 0, time.isFinite, time >= 0 else {
                    throw CompareReviewSidecarError.invalidNote(number, "source \(source) has a negative or non-finite position")
                }
                guard numerator > 0, denominator > 0 else {
                    throw CompareReviewSidecarError.invalidNote(number, "source \(source) has a nonpositive frame rate")
                }
                // Reports add a source timecode (less than 24 hours) and a
                // one-frame marker duration, then form an Int64 rational time.
                // Reserve the decimal-rate fallback timebase too, rather than
                // trusting a forged integer rate to make a huge frame safe.
                let nominalRate = max(1, (Double(numerator) / Double(denominator)).rounded())
                guard nominalRate < Double(Int64.max / sourceTimecodeDaySeconds) else {
                    throw CompareReviewSidecarError.invalidNote(number, "source \(source) frame rate exceeds the supported timecode range")
                }
                let sourceTimecodeFrames = Int64(nominalRate) * sourceTimecodeDaySeconds
                let (endFrame, frameOverflow) = frame.addingReportingOverflow(sourceTimecodeFrames)
                let (exclusiveEnd, endOverflow) = endFrame.addingReportingOverflow(1)
                let (_, timeOverflow) = exclusiveEnd.multipliedReportingOverflow(by: max(decimalRateTimebase, denominator))
                guard !frameOverflow, !endOverflow, !timeOverflow else {
                    throw CompareReviewSidecarError.invalidNote(number, "source \(source) position exceeds the supported frame range")
                }
            }
        }
    }

    nonisolated private static func shortened(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = cleaned.isEmpty ? "Untitled" : cleaned
        return String(fallback.prefix(60))
    }

    /// Deterministic FNV-1a keeps pair sidecars distinct without depending on
    /// Swift's intentionally randomized Hasher.
    nonisolated private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
