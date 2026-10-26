// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Libmpv
import XCTest

final class MPVSurfaceSizeTests: XCTestCase {
    /// In-place resizing depends on the MPVKit layer-resize patch. A repin
    /// without it would silently fall back to stale swapchain sizes.
    func testPinnedLibmpvAcceptsMoltenVKSurfaceSize() throws {
        let context = try XCTUnwrap(mpv_create())
        defer { mpv_terminate_destroy(context) }
        XCTAssertEqual(mpv_set_option_string(context, "vo", "null"), 0)
        XCTAssertEqual(mpv_initialize(context), 0)
        XCTAssertEqual(mpv_set_property_string(context, "moltenvk-surface-size", "1280x720"), 0)
        let value = try XCTUnwrap(mpv_get_property_string(context, "moltenvk-surface-size"))
        defer { mpv_free(value) }
        XCTAssertEqual(String(cString: value), "1280x720")
        XCTAssertLessThan(mpv_set_property_string(context, "moltenvk-surface-size", "wide"), 0)
    }
}
