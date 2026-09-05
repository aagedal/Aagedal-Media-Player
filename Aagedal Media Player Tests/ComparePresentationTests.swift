// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ComparePresentationTests: XCTestCase {
    func testFrameResolutionDefaultsToFull() {
        let session = CompareSessionController()

        XCTAssertEqual(session.frameResolution, .full)
    }

    func testFrameResolutionProvidesExpectedRenderScaleAndSurfaceSize() {
        let canvasSize = CGSize(width: 1_920, height: 1_080)

        XCTAssertEqual(CompareFrameResolution.full.renderScale, 1)
        XCTAssertEqual(
            CompareFrameResolution.full.surfaceSize(for: canvasSize),
            canvasSize
        )
        XCTAssertEqual(CompareFrameResolution.reduced.renderScale, 0.5)
        XCTAssertEqual(
            CompareFrameResolution.reduced.surfaceSize(for: canvasSize),
            CGSize(width: 960, height: 540)
        )
    }

    func testSettingFrameResolutionWhileInactiveChangesTheSelection() {
        let primary = PlayerController()
        let session = CompareSessionController()
        let preparationID = primary.preparationID

        session.setFrameResolution(.reduced, primary: primary)

        XCTAssertEqual(session.frameResolution, .reduced)
        XCTAssertEqual(primary.preparationID, preparationID)
    }

    func testStoppingSessionRestoresFullFrameResolution() {
        let primary = PlayerController()
        let session = CompareSessionController()
        session.setFrameResolution(.reduced, primary: primary)

        session.stop()

        XCTAssertEqual(session.frameResolution, .full)
    }

    func testWipePositionClampsToUnitInterval() {
        let session = CompareSessionController()

        session.setWipePosition(-0.25)
        XCTAssertEqual(session.wipePosition, 0)

        session.setWipePosition(1.25)
        XCTAssertEqual(session.wipePosition, 1)

        session.setWipePosition(.infinity)
        XCTAssertEqual(session.wipePosition, 0.5)
    }

    func testMovingWipeUsesClampedPosition() {
        let session = CompareSessionController()

        session.moveWipe(by: 0.2)
        XCTAssertEqual(session.wipePosition, 0.7, accuracy: 0.000_001)

        session.moveWipe(by: 1)
        XCTAssertEqual(session.wipePosition, 1)
    }

    func testOverlayBlendUsesTheSameClampedRange() {
        let session = CompareSessionController()

        session.setOverlayBlend(-1)
        XCTAssertEqual(session.overlayBlend, 0)

        session.setOverlayBlend(2)
        XCTAssertEqual(session.overlayBlend, 1)
    }

    func testDifferenceGainClampsToSupportedRange() {
        let session = CompareSessionController()

        session.setDifferenceGain(0)
        XCTAssertEqual(session.differenceGain, 1)

        session.setDifferenceGain(8.5)
        XCTAssertEqual(session.differenceGain, 8.5)

        session.setDifferenceGain(20)
        XCTAssertEqual(session.differenceGain, 16)

        session.setDifferenceGain(.nan)
        XCTAssertEqual(session.differenceGain, 1)
    }

    func testDifferenceBrightnessCompensatesForContrastLift() {
        XCTAssertEqual(
            CompareSessionController.differenceBrightness(forGain: 1),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CompareSessionController.differenceBrightness(forGain: 2),
            0.25,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CompareSessionController.differenceBrightness(forGain: 4),
            0.375,
            accuracy: 0.000_001
        )
    }

    func testABToggleEntersPrimaryAndAlternatesSources() {
        let session = CompareSessionController()

        session.viewMode = .verticalWipe
        session.togglePrimarySecondary()
        XCTAssertEqual(session.viewMode, .primary)

        session.togglePrimarySecondary()
        XCTAssertEqual(session.viewMode, .secondary)
    }

    func testScopeSourceIsIndependentAndResetsWithSession() {
        let session = CompareSessionController()

        XCTAssertEqual(session.scopeSource, .primary)
        session.viewMode = .overlay
        session.scopeSource = .difference
        XCTAssertEqual(session.viewMode, .overlay)
        XCTAssertEqual(session.scopeSource, .difference)

        session.stop()
        XCTAssertEqual(session.scopeSource, .primary)
    }

    func testComparisonGuidesResetWithSession() {
        let session = CompareSessionController()

        session.safeAreaGuide = .actionAndTitle
        session.aspectRatioGuide = .twoThirtyNine

        session.stop()

        XCTAssertEqual(session.safeAreaGuide, .none)
        XCTAssertEqual(session.aspectRatioGuide, .none)
    }

    func testSafeAreaGuidePresetsExposeExpectedFrames() {
        XCTAssertFalse(CompareSafeAreaGuide.none.showsActionSafe)
        XCTAssertFalse(CompareSafeAreaGuide.none.showsTitleSafe)
        XCTAssertTrue(CompareSafeAreaGuide.action.showsActionSafe)
        XCTAssertFalse(CompareSafeAreaGuide.action.showsTitleSafe)
        XCTAssertFalse(CompareSafeAreaGuide.title.showsActionSafe)
        XCTAssertTrue(CompareSafeAreaGuide.title.showsTitleSafe)
        XCTAssertTrue(CompareSafeAreaGuide.actionAndTitle.showsActionSafe)
        XCTAssertTrue(CompareSafeAreaGuide.actionAndTitle.showsTitleSafe)
    }

    func testSafeAreaRectsUseNinetyAndEightyPercentOfGuideFrame() {
        let reference = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

        XCTAssertEqual(
            CompareDisplayGeometry.safeAreaRect(fraction: 0.9, in: reference),
            CGRect(x: 96, y: 54, width: 1_728, height: 972)
        )
        XCTAssertEqual(
            CompareDisplayGeometry.safeAreaRect(fraction: 0.8, in: reference),
            CGRect(x: 192, y: 108, width: 1_536, height: 864)
        )
    }

    func testAspectGuideIsInscribedWithinVisiblePicture() {
        let reference = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

        XCTAssertEqual(
            CompareDisplayGeometry.aspectGuideRect(
                aspectRatio: CompareAspectRatioGuide.fourByThree.aspectRatio,
                in: reference
            ),
            CGRect(x: 240, y: 0, width: 1_440, height: 1_080)
        )
        XCTAssertEqual(
            CompareDisplayGeometry.aspectGuideRect(aspectRatio: nil, in: reference),
            reference
        )
    }

    func testAudioSourceRoutesExactlyOneControllerAndStopRestoresSafety() {
        let primary = PlayerController()
        let secondary = PlayerController()
        let session = CompareSessionController(secondaryController: secondary)

        XCTAssertEqual(session.audioSource, .primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)

        session.selectAudioSource(.secondary, primary: primary)
        XCTAssertEqual(session.audioSource, .secondary)
        XCTAssertTrue(primary.isAudioSuppressed)
        XCTAssertFalse(secondary.isAudioSuppressed)

        session.selectAudioSource(.primary, primary: primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)

        session.selectAudioSource(.secondary, primary: primary)
        session.stop()
        XCTAssertEqual(session.audioSource, .primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    func testAudioSourceSelectionDoesNotChangeUserMutePreference() {
        let primary = PlayerController()
        let secondary = PlayerController()
        let session = CompareSessionController(secondaryController: secondary)
        let primaryMutePreference = primary.isMuted
        let secondaryMutePreference = secondary.isMuted

        session.selectAudioSource(.secondary, primary: primary)
        session.selectAudioSource(.primary, primary: primary)

        XCTAssertEqual(primary.isMuted, primaryMutePreference)
        XCTAssertEqual(secondary.isMuted, secondaryMutePreference)
    }

    func testReplacingSecondaryReturnsAudioMonitoringToPrimary() {
        let primary = PlayerController()
        let secondary = PlayerController()
        let session = CompareSessionController(secondaryController: secondary)

        session.selectAudioSource(.secondary, primary: primary)
        session.loadSecondary(
            URL(fileURLWithPath: "/tmp/replacement-compare-source.mov"),
            alignedWith: primary
        )

        XCTAssertEqual(session.audioSource, .primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
        session.stop()
    }

    func testOnlyWipeModesReportWipeControls() {
        XCTAssertTrue(CompareViewMode.verticalWipe.isWipe)
        XCTAssertTrue(CompareViewMode.horizontalWipe.isWipe)
        XCTAssertFalse(CompareViewMode.overlay.isWipe)
        XCTAssertFalse(CompareViewMode.difference.isWipe)
        XCTAssertFalse(CompareViewMode.sideBySide.isWipe)
    }

    func testEquivalentDisplayAspectsShareTheSameComparisonRect() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 1_920.0 / 1_080.0,
            // For example, 1440x1080 coded pixels after a 4:3 PAR is applied.
            secondaryAspectRatio: 1_920.0 / 1_080.0
        )

        XCTAssertEqual(geometry.primaryReferenceRect.minY, 60, accuracy: 0.000_001)
        XCTAssertEqual(geometry.primaryReferenceRect.width, 1_920, accuracy: 0.000_001)
        XCTAssertEqual(geometry.primaryReferenceRect.height, 1_080, accuracy: 0.000_001)
        XCTAssertEqual(
            CompareDisplayGeometry.aspectFitRect(
                aspectRatio: geometry.secondaryAspectRatio,
                in: geometry.canvasRect
            ),
            geometry.primaryReferenceRect
        )
    }

    func testRotatedAndPhysicallyPortraitSourcesShareDisplayGeometry() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_600, height: 900),
            // Both inputs are post-display ratios: one can originate from a
            // rotated 1920x1080 stream and the other from a 1080x1920 raster.
            primaryAspectRatio: 9.0 / 16.0,
            secondaryAspectRatio: 1_080.0 / 1_920.0
        )

        let secondaryRect = CompareDisplayGeometry.aspectFitRect(
            aspectRatio: geometry.secondaryAspectRatio,
            in: geometry.canvasRect
        )
        XCTAssertEqual(secondaryRect, geometry.primaryReferenceRect)
        XCTAssertEqual(geometry.primaryReferenceRect.width, 506.25, accuracy: 0.000_001)
        XCTAssertEqual(geometry.primaryReferenceRect.height, 900, accuracy: 0.000_001)
    }

    func testSideBySideFitsPortraitSourcesToFullPaneHeight() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_600, height: 900),
            primaryAspectRatio: 9.0 / 16.0,
            secondaryAspectRatio: 9.0 / 16.0
        )

        let primary = geometry.sideBySideTransform(for: .primary)
        let secondary = geometry.sideBySideTransform(for: .secondary)

        XCTAssertEqual(primary.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(primary.offset.x, -400, accuracy: 0.000_001)
        XCTAssertEqual(primary.offset.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(secondary.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(secondary.offset.x, 400, accuracy: 0.000_001)
        XCTAssertEqual(secondary.offset.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            geometry.presentationClipRect(for: .primary, mode: .sideBySide),
            CGRect(x: 0, y: 0, width: 800, height: 900)
        )
        XCTAssertEqual(
            geometry.presentationClipRect(for: .secondary, mode: .sideBySide),
            CGRect(x: 800, y: 0, width: 800, height: 900)
        )
    }

    func testSideBySideGuidesRepeatInsideEachSourcePane() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 16.0 / 9.0,
            secondaryAspectRatio: 4.0 / 3.0
        )

        XCTAssertEqual(
            geometry.guideReferenceRects(for: .sideBySide),
            [
                CGRect(x: 0, y: 330, width: 960, height: 540),
                CGRect(x: 960, y: 240, width: 960, height: 720)
            ]
        )
    }

    func testSideBySideTransformedPicturesMatchTheirGuidesAcrossAspectAndResolutionMatrix() {
        let canvas = CGSize(width: 1_919, height: 1_079)
        let aspects: [CGFloat] = [9.0 / 16.0, 1, 4.0 / 3.0, 16.0 / 9.0, 2.39]
        for primaryAspect in aspects {
            for secondaryAspect in aspects {
                let full = CompareDisplayGeometry(
                    canvasSize: canvas,
                    primaryAspectRatio: primaryAspect,
                    secondaryAspectRatio: secondaryAspect
                )
                for resolution in [CompareFrameResolution.full, .reduced] {
                    let geometry = CompareDisplayGeometry(
                        canvasSize: resolution.surfaceSize(for: canvas),
                        primaryAspectRatio: primaryAspect,
                        secondaryAspectRatio: secondaryAspect
                    )
                    let guides = full.guideReferenceRects(for: .sideBySide)
                    for (index, source) in [CompareSource.primary, .secondary].enumerated() {
                        let picture = source == .primary
                            ? geometry.primaryReferenceRect : geometry.secondaryReferenceRect
                        let transform = geometry.sideBySideTransform(for: source)
                        let visible = CGRect(
                            x: (picture.minX * transform.scale + transform.offset.x) / resolution.renderScale,
                            y: (picture.minY * transform.scale + transform.offset.y) / resolution.renderScale,
                            width: picture.width * transform.scale / resolution.renderScale,
                            height: picture.height * transform.scale / resolution.renderScale
                        )
                        XCTAssertEqual(visible.minX, guides[index].minX, accuracy: 0.000_001)
                        XCTAssertEqual(visible.minY, guides[index].minY, accuracy: 0.000_001)
                        XCTAssertEqual(visible.width, guides[index].width, accuracy: 0.000_001)
                        XCTAssertEqual(visible.height, guides[index].height, accuracy: 0.000_001)
                        let pane = full.presentationClipRect(for: source, mode: .sideBySide)
                        XCTAssertGreaterThanOrEqual(visible.minX, pane.minX - 0.000_001)
                        XCTAssertLessThanOrEqual(visible.maxX, pane.maxX + 0.000_001)
                        XCTAssertGreaterThanOrEqual(visible.minY, pane.minY - 0.000_001)
                        XCTAssertLessThanOrEqual(visible.maxY, pane.maxY + 0.000_001)
                    }
                }
            }
        }
    }

    func testCompositedGuidesUseOneSharedComparisonFrame() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 16.0 / 9.0,
            secondaryAspectRatio: 4.0 / 3.0
        )

        XCTAssertEqual(geometry.guideReferenceRects(for: .overlay), [geometry.canvasRect])
        XCTAssertEqual(geometry.guideReferenceRects(for: .difference), [geometry.canvasRect])
        XCTAssertEqual(geometry.guideReferenceRects(for: .verticalWipe), [geometry.canvasRect])
        XCTAssertEqual(geometry.guideReferenceRects(for: .horizontalWipe), [geometry.canvasRect])
        XCTAssertEqual(
            geometry.guideReferenceRects(for: .primary),
            [geometry.primaryReferenceRect]
        )
        XCTAssertEqual(
            geometry.guideReferenceRects(for: .secondary),
            [geometry.secondaryReferenceRect]
        )
    }

    func testWipeClipUsesPrimaryVisiblePictureBounds() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 16.0 / 9.0,
            secondaryAspectRatio: 16.0 / 9.0
        )

        XCTAssertEqual(
            geometry.secondaryClipRect(for: .verticalWipe, wipePosition: 0.5),
            CGRect(x: 0, y: 60, width: 960, height: 1_080)
        )
        XCTAssertEqual(
            geometry.secondaryClipRect(for: .horizontalWipe, wipePosition: 0.5),
            CGRect(x: 0, y: 60, width: 1_920, height: 540)
        )
    }

    func testDifferingDisplayAspectsRetainIndependentFullFrameFits() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 16.0 / 9.0,
            secondaryAspectRatio: 4.0 / 3.0
        )

        XCTAssertFalse(geometry.displayAspectsMatch)
        XCTAssertEqual(geometry.comparisonReferenceRect, geometry.canvasRect)
        XCTAssertEqual(
            geometry.secondaryClipRect(for: .verticalWipe, wipePosition: 1),
            geometry.canvasRect
        )
        XCTAssertEqual(
            geometry.secondaryClipRect(for: .difference, wipePosition: 0.5),
            geometry.canvasRect
        )
    }

    func testInvalidGeometryFallsBackWithoutProducingNonFiniteValues() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: CGFloat.infinity, height: CGFloat.nan),
            primaryAspectRatio: CGFloat.nan,
            secondaryAspectRatio: -CGFloat.infinity
        )

        XCTAssertEqual(geometry.canvasSize, CGSize.zero)
        XCTAssertEqual(geometry.primaryAspectRatio, 16.0 / 9.0)
        XCTAssertEqual(geometry.secondaryAspectRatio, 16.0 / 9.0)
        XCTAssertEqual(geometry.primaryReferenceRect, CGRect.zero)
        XCTAssertEqual(
            CompareDisplayGeometry.safeAreaRect(
                fraction: .nan,
                in: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            .zero
        )
    }
}
