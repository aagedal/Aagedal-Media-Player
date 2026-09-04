// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum CompareReviewSidecarError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case sourcePairMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "The comparison notes use unsupported schema version \(version)."
        case .sourcePairMismatch:
            "The comparison notes sidecar belongs to a different source pair."
        }
    }
}

nonisolated enum CompareReviewMutation: Sendable {
    case upsert(CompareReviewNote)
    case delete(UUID)
}

/// Serializes sidecar access and rejects late writes from an older in-memory
/// revision. Source media is never opened for writing.
actor CompareReviewSidecarStore {
    static let shared = CompareReviewSidecarStore()

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
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(CompareReviewDocument.self, from: data)
        guard document.schemaVersion == CompareReviewDocument.currentSchemaVersion else {
            throw CompareReviewSidecarError.unsupportedSchema(document.schemaVersion)
        }
        guard document.belongsTo(primaryURL: primaryURL, secondaryURL: secondaryURL) else {
            throw CompareReviewSidecarError.sourcePairMismatch
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
        latestRevisionByURL[url] = revision

        try write(document, to: url)
    }

    private func write(_ document: CompareReviewDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
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
