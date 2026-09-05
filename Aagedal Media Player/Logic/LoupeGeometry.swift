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

/// Coordinates use a top-left origin throughout, matching SwiftUI's picture
/// and lens layout. Picture bounds must exclude letterbox and pillarbox bars.
nonisolated enum LoupeGeometry {
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
