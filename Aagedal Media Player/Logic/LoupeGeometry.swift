// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

nonisolated enum LoupeMagnification: String, CaseIterable, Identifiable, Sendable {
    case twoTimes
    case fourTimes
    case eightTimes
    case nativePixels

    var id: Self { self }

    var label: String {
        switch self {
        case .twoTimes: "2×"
        case .fourTimes: "4×"
        case .eightTimes: "8×"
        case .nativePixels: "Native pixels"
        }
    }

    var factor: CGFloat? {
        switch self {
        case .twoTimes: 2
        case .fourTimes: 4
        case .eightTimes: 8
        case .nativePixels: nil
        }
    }
}

/// Runtime evidence used before presenting a capture as one source pixel per
/// physical display pixel. MPV screenshots pass through display processing;
/// even a matching raster size cannot establish pixel provenance. Only an
/// AVFoundation decoded raster can currently qualify.
nonisolated struct LoupeNativePixelSource: Equatable, Sendable {
    let name: String
    let backend: PlaybackBackend?
    let codedWidth: Int?
    let codedHeight: Int?
    let rotation: Int?
    let capturedWidth: Int?
    let capturedHeight: Int?
}

nonisolated enum LoupeNativePixelAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        self == .available
    }

    var explanation: String {
        switch self {
        case .available:
            "Verified AVFoundation raster: one captured source pixel per physical display pixel."
        case .unavailable(let reason):
            reason
        }
    }

    static func evaluate(
        primary: LoupeNativePixelSource,
        secondary: LoupeNativePixelSource? = nil
    ) -> Self {
        for source in [primary, secondary].compactMap({ $0 }) {
            guard let backend = source.backend else {
                return .unavailable("1:1 source pixels are waiting for the \(source.name) playback backend.")
            }
            guard backend == .avFoundation else {
                return .unavailable("1:1 source pixels require a verified decoded raster; \(source.name) uses mpv display-processed capture.")
            }
            guard let codedWidth = source.codedWidth,
                  let codedHeight = source.codedHeight,
                  codedWidth > 0, codedHeight > 0,
                  let capturedWidth = source.capturedWidth,
                  let capturedHeight = source.capturedHeight,
                  capturedWidth > 0, capturedHeight > 0 else {
                return .unavailable("1:1 source pixels are waiting for a verifiable \(source.name) decoded raster.")
            }

            let normalizedRotation = ((source.rotation ?? 0) % 360 + 360) % 360
            guard [0, 90, 180, 270].contains(normalizedRotation) else {
                return .unavailable(
                    "1:1 source pixels are unavailable because \(source.name) has an unsupported "
                        + "\(normalizedRotation)-degree display transform."
                )
            }
            let expectedWidth = normalizedRotation == 90 || normalizedRotation == 270
                ? codedHeight : codedWidth
            let expectedHeight = normalizedRotation == 90 || normalizedRotation == 270
                ? codedWidth : codedHeight
            guard capturedWidth == expectedWidth, capturedHeight == expectedHeight else {
                return .unavailable(
                    "1:1 source pixels are unavailable because \(source.name) captured "
                        + "\(capturedWidth) × \(capturedHeight), not the expected oriented raster "
                        + "\(expectedWidth) × \(expectedHeight)."
                )
            }
        }
        return .available
    }
}

/// Coordinates use a top-left origin throughout, matching SwiftUI's picture
/// and lens layout. Picture bounds must exclude letterbox and pillarbox bars.
nonisolated enum LoupeGeometry {
    /// Keep the floating lenses within the current canvas even when a pinned
    /// pointer still contains coordinates from a larger window. If the canvas
    /// cannot fit an axis, center that axis so overflow is shared on both sides.
    static func overlayCenter(canvasSize: CGSize, overlaySize: CGSize, pointer: CGPoint?) -> CGPoint {
        guard validSize(canvasSize), validSize(overlaySize) else { return .zero }
        let pointer = pointer ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let pointerX = pointer.x.isFinite ? pointer.x : canvasSize.width / 2
        let pointerY = pointer.y.isFinite ? pointer.y : canvasSize.height / 2
        let below = pointerY + overlaySize.height / 2 + 24
        let preferredY = below + overlaySize.height / 2 <= canvasSize.height - 8
            ? below : pointerY - overlaySize.height / 2 - 24

        return clampedOverlayCenter(
            CGPoint(x: pointerX, y: preferredY),
            canvasSize: canvasSize, overlaySize: overlaySize
        )
    }

    static func clampedOverlayCenter(
        _ preferred: CGPoint, canvasSize: CGSize, overlaySize: CGSize
    ) -> CGPoint {
        guard validSize(canvasSize), validSize(overlaySize) else { return .zero }

        func boundedCenter(_ value: CGFloat, extent: CGFloat, canvas: CGFloat) -> CGFloat {
            guard extent <= canvas else { return canvas / 2 }
            let margin = min(8, (canvas - extent) / 2)
            let finiteValue = value.isFinite ? value : canvas / 2
            return min(max(finiteValue, extent / 2 + margin), canvas - extent / 2 - margin)
        }

        return CGPoint(
            x: boundedCenter(preferred.x, extent: overlaySize.width, canvas: canvasSize.width),
            y: boundedCenter(preferred.y, extent: overlaySize.height, canvas: canvasSize.height)
        )
    }

    static func normalizedPoint(location: CGPoint, in picture: CGRect) -> CGPoint? {
        guard validSize(picture.size),
              picture.origin.x.isFinite, picture.origin.y.isFinite,
              picture.maxX.isFinite, picture.maxY.isFinite,
              location.x.isFinite, location.y.isFinite,
              location.x >= picture.minX, location.x <= picture.maxX,
              location.y >= picture.minY, location.y <= picture.maxY else { return nil }

        return CGPoint(
            x: (location.x - picture.minX) / picture.width,
            y: (location.y - picture.minY) / picture.height
        )
    }

    /// The entire image's frame in lens-local points. The inspected point
    /// stays at the lens center even at an image edge; the lens background
    /// supplies black outside the image instead of shifting the inspected point.
    /// Fixed magnification scales the fitted picture. Native pixels maps each
    /// captured source pixel to one physical display pixel, including on Retina.
    static func imagePlacement(
        imageSize: CGSize,
        pictureSize: CGSize,
        normalizedPoint: CGPoint,
        lensSize: CGSize,
        magnification: LoupeMagnification,
        displayScale: CGFloat
    ) -> CGRect {
        guard validSize(imageSize), validSize(pictureSize), validSize(lensSize) else { return .zero }

        let size: CGSize
        if let factor = magnification.factor {
            size = CGSize(width: pictureSize.width * factor, height: pictureSize.height * factor)
        } else {
            let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
            size = CGSize(width: imageSize.width / scale, height: imageSize.height / scale)
        }
        guard validSize(size) else { return .zero }

        return CGRect(
            x: lensSize.width / 2 - unitValue(normalizedPoint.x) * size.width,
            y: lensSize.height / 2 - unitValue(normalizedPoint.y) * size.height,
            width: size.width,
            height: size.height
        )
    }

    private static func unitValue(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
