// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

nonisolated enum CompareSource: Sendable {
    case primary
    case secondary
}

nonisolated struct CompareSurfaceTransform: Equatable, Sendable {
    let scale: CGFloat
    let offset: CGPoint

    static let identity = CompareSurfaceTransform(scale: 1, offset: .zero)
}

/// Resolves comparison layout from post-display aspect ratios. Pixel aspect
/// ratio and rotation are deliberately handled upstream by MetadataService or
/// the playback backend; applying either again here would double-correct B.
nonisolated struct CompareDisplayGeometry: Equatable, Sendable {
    let canvasSize: CGSize
    let primaryAspectRatio: CGFloat
    let secondaryAspectRatio: CGFloat

    init(
        canvasSize: CGSize,
        primaryAspectRatio: CGFloat?,
        secondaryAspectRatio: CGFloat?
    ) {
        self.canvasSize = Self.sanitizedSize(canvasSize)
        self.primaryAspectRatio = Self.sanitizedAspectRatio(primaryAspectRatio)
        self.secondaryAspectRatio = Self.sanitizedAspectRatio(secondaryAspectRatio)
    }

    var canvasRect: CGRect {
        CGRect(origin: .zero, size: canvasSize)
    }

    var primaryReferenceRect: CGRect {
        Self.aspectFitRect(aspectRatio: primaryAspectRatio, in: canvasRect)
    }

    /// Sources with matching post-display aspect ratios share A's visible
    /// picture bounds. If the display aspects genuinely differ, retain each
    /// source's independent fit instead of silently cropping or stretching B.
    var comparisonReferenceRect: CGRect {
        displayAspectsMatch ? primaryReferenceRect : canvasRect
    }

    var displayAspectsMatch: Bool {
        abs(primaryAspectRatio - secondaryAspectRatio) <= 0.001
    }

    func presentationClipRect(for source: CompareSource, mode: CompareViewMode) -> CGRect {
        guard mode == .sideBySide else { return canvasRect }
        switch source {
        case .primary:
            return CGRect(x: 0, y: 0, width: canvasSize.width / 2, height: canvasSize.height)
        case .secondary:
            return CGRect(
                x: canvasSize.width / 2,
                y: 0,
                width: canvasSize.width / 2,
                height: canvasSize.height
            )
        }
    }

    func sideBySideTransform(for source: CompareSource) -> CompareSurfaceTransform {
        let sourceAspectRatio: CGFloat
        let targetRect: CGRect
        switch source {
        case .primary:
            sourceAspectRatio = primaryAspectRatio
            targetRect = CGRect(
                x: 0,
                y: 0,
                width: canvasSize.width / 2,
                height: canvasSize.height
            )
        case .secondary:
            sourceAspectRatio = secondaryAspectRatio
            targetRect = CGRect(
                x: canvasSize.width / 2,
                y: 0,
                width: canvasSize.width / 2,
                height: canvasSize.height
            )
        }

        let sourceRect = Self.aspectFitRect(
            aspectRatio: sourceAspectRatio,
            in: canvasRect
        )
        let fittedTarget = Self.aspectFitRect(
            aspectRatio: sourceAspectRatio,
            in: targetRect
        )
        guard sourceRect.width > 0, sourceRect.height > 0 else { return .identity }

        let scale = min(
            fittedTarget.width / sourceRect.width,
            fittedTarget.height / sourceRect.height
        )
        let offset = CGPoint(
            x: fittedTarget.midX - sourceRect.midX * scale,
            y: fittedTarget.midY - sourceRect.midY * scale
        )
        return CompareSurfaceTransform(scale: scale, offset: offset)
    }

    func secondaryClipRect(for mode: CompareViewMode, wipePosition: Double) -> CGRect {
        let position = CGFloat(CompareSessionController.clampedUnitValue(wipePosition))
        let reference = comparisonReferenceRect
        switch mode {
        case .verticalWipe:
            return CGRect(
                x: reference.minX,
                y: reference.minY,
                width: reference.width * position,
                height: reference.height
            )
        case .horizontalWipe:
            return CGRect(
                x: reference.minX,
                y: reference.minY,
                width: reference.width,
                height: reference.height * position
            )
        case .overlay, .difference:
            return reference
        case .sideBySide, .primary, .secondary:
            return canvasRect
        }
    }

    static func aspectFitRect(aspectRatio: CGFloat, in container: CGRect) -> CGRect {
        guard aspectRatio.isFinite, aspectRatio > 0,
              container.width.isFinite, container.height.isFinite,
              container.width > 0, container.height > 0 else { return .zero }

        let containerAspectRatio = container.width / container.height
        let size: CGSize
        if aspectRatio > containerAspectRatio {
            size = CGSize(width: container.width, height: container.width / aspectRatio)
        } else {
            size = CGSize(width: container.height * aspectRatio, height: container.height)
        }
        return CGRect(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func sanitizedAspectRatio(_ value: CGFloat?) -> CGFloat {
        guard let value, value.isFinite, value > 0 else { return 16.0 / 9.0 }
        return value
    }

    private static func sanitizedSize(_ value: CGSize) -> CGSize {
        CGSize(
            width: value.width.isFinite ? max(0, value.width) : 0,
            height: value.height.isFinite ? max(0, value.height) : 0
        )
    }
}
