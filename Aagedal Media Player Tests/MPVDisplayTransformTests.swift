// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import CoreGraphics
import XCTest

final class MPVDisplayTransformTests: XCTestCase {
    func testReflectionDetectionIsIndependentOfRotationAndTranslation() {
        for angle in [0.0, Double.pi / 2, Double.pi, 3 * Double.pi / 2] {
            let rotation = CGAffineTransform(rotationAngle: angle)
                .translatedBy(x: 1920, y: 1080)
            XCTAssertFalse(MPVDisplayTransform.isReflected(rotation))
            XCTAssertTrue(MPVDisplayTransform.isReflected(rotation.scaledBy(x: -1, y: 1)))
            XCTAssertTrue(MPVDisplayTransform.isReflected(rotation.scaledBy(x: 1, y: -1)))
            XCTAssertFalse(MPVDisplayTransform.isReflected(rotation.scaledBy(x: -1, y: -1)))
        }
    }

    func testDegenerateAndNonFiniteMatricesCannotEnableCorrection() {
        XCTAssertFalse(MPVDisplayTransform.isReflected(CGAffineTransform(scaleX: 0, y: -1)))
        XCTAssertFalse(MPVDisplayTransform.isReflected(CGAffineTransform(a: .infinity, b: 0, c: 0, d: -1, tx: 0, ty: 0)))
        XCTAssertFalse(MPVDisplayTransform.isReflected(CGAffineTransform(a: .nan, b: 0, c: 0, d: -1, tx: 0, ty: 0)))
    }
}
