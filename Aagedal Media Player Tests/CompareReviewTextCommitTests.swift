// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareReviewTextCommitTests: XCTestCase {
    func testAcceptedEditUsesTrimmedText() {
        var updatedText: String?
        let result = CompareReviewTextCommitResult.attempt(
            draft: "  Corrected finding\n", savedText: "Original finding", canEdit: true
        ) { text in
            updatedText = text
            return true
        }

        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(updatedText, "Corrected finding")
    }

    func testRejectedAndUnavailableEditsRemainUnaccepted() {
        let draft = "Corrected finding"
        var updateCalls = 0
        let rejected = CompareReviewTextCommitResult.attempt(
            draft: draft, savedText: "Original finding", canEdit: true
        ) { _ in
            updateCalls += 1
            return false
        }
        let unavailable = CompareReviewTextCommitResult.attempt(
            draft: draft, savedText: "Original finding", canEdit: false
        ) { _ in
            updateCalls += 1
            return true
        }

        XCTAssertEqual(rejected, .rejected)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(updateCalls, 1)
    }

    func testEmptyAndUnchangedEditsDoNotMutateNote() {
        var updateCalls = 0
        for (draft, expected) in [
            (" \n ", CompareReviewTextCommitResult.empty),
            ("  Original finding  ", .accepted)
        ] {
            let result = CompareReviewTextCommitResult.attempt(
                draft: draft, savedText: "Original finding", canEdit: true
            ) { _ in
                updateCalls += 1
                return true
            }
            XCTAssertEqual(result, expected)
        }
        XCTAssertEqual(updateCalls, 0)
    }
}
