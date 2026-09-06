// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Combine
import CoreGraphics
import Foundation

/// Hover requests are quantized to half seconds and decoded lazily. A single
/// worker coalesces pointer movement; it never launches parallel decoders.
@MainActor
final class TimelineThumbnailLoader: ObservableObject {
    struct Request: Equatable {
        let mediaID: UUID
        let url: URL
        let time: Double

        init?(item: MediaItem, time: Double) {
            guard item.hasVideoStream, item.durationSeconds.isFinite,
                  item.durationSeconds > 0, time.isFinite else { return nil }
            mediaID = item.id
            url = item.url
            self.time = ComparisonStillFrameExtractor.clampedTime(
                (max(0, time) * 2).rounded(.down) / 2, for: item
            )
        }
    }

    @Published private(set) var image: CGImage?
    @Published private(set) var imageTime: Double?
    private(set) var cachedCount = 0
    private var mediaID: UUID?
    private var cache: [Double: CGImage] = [:]
    private var recency: [Double] = []
    private var desired: Request?
    private var worker: Task<Void, Never>?
    static let cacheLimit = 32
    private let debounce: Duration
    private let extract: @Sendable (URL, Double) async throws -> CGImage

    init(
        debounce: Duration = .milliseconds(180),
        extract: @escaping @Sendable (URL, Double) async throws -> CGImage = { url, time in
            try await ComparisonStillFrameExtractor.image(
                from: url, at: time, maximumSize: CGSize(width: 240, height: 135),
                tolerance: CMTime(seconds: 0.25, preferredTimescale: 600)
            )
        }
    ) {
        self.debounce = debounce
        self.extract = extract
    }

    func request(item: MediaItem, time: Double) {
        guard let request = Request(item: item, time: time) else { hide(); return }
        if mediaID != request.mediaID {
            worker?.cancel()
            cache.removeAll()
            recency.removeAll()
            cachedCount = 0
            mediaID = request.mediaID
        }
        guard desired != request else { return }
        desired = request
        image = cache[request.time]
        imageTime = image == nil ? nil : request.time
        if image != nil { touch(request.time) }
        startWorkerIfNeeded()
    }

    func hide(clearCache: Bool = false) {
        desired = nil
        image = nil
        imageTime = nil
        worker?.cancel()
        // Retain the worker until its in-flight decode finishes so reopening
        // the preview cannot overlap it with another decoder.
        if clearCache {
            mediaID = nil
            cache.removeAll()
            recency.removeAll()
            cachedCount = 0
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, let desired, cache[desired.time] == nil else { return }
        worker = Task { [weak self] in
            while let request = self?.desired {
                // Wait for the pointer to settle before touching the file.
                do { try await Task.sleep(for: self?.debounce ?? .zero) }
                catch { break }
                guard let self else { return }
                guard self.desired == request else { continue }
                if self.cache[request.time] != nil { break }
                let result = try? await self.extract(request.url, request.time)
                if Task.isCancelled { break }
                if self.mediaID == request.mediaID, let result {
                    self.cache[request.time] = result
                    self.touch(request.time)
                    while self.recency.count > Self.cacheLimit {
                        self.cache.removeValue(forKey: self.recency.removeFirst())
                    }
                    self.cachedCount = self.cache.count
                }
                if self.desired == request {
                    self.image = result
                    self.imageTime = result == nil ? nil : request.time
                    break
                }
            }
            let wasCancelled = Task.isCancelled
            self?.worker = nil
            if wasCancelled { self?.startWorkerIfNeeded() }
        }
    }

    private func touch(_ time: Double) {
        recency.removeAll { $0 == time }
        recency.append(time)
    }
}
