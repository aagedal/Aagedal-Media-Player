# Live playback loupe enabled by default

The loupe now defaults to the silent secondary MPV viewer during forward
playback. The “Live video during playback” control switches back to captured
previews. Pause uses the main player's captured frame; reverse and AVFoundation
retain captured previews. The live-loupe environment flag is no longer needed.
Shipping pins and the native provider's default-off gate are unchanged.

The [28-test run](tests-summary.json) passes without skips or failures, with no
live-loupe environment flag. The actual overlay test starts from default state,
checks screenshot suppression during live playback, verifies the primary native
raster on pause and after a paused seek, resumes live playback, and disables live
mode to check captured previews. Crop, geometry, resizing, source replacement,
transport and teardown tests pass. Existing mixed MPV/AV screenshot-and-scope
profiles now explicitly select captured previews, preserving their fresh-pixel
acceptance criteria. Their initial run correctly detected that live mode had
stopped screenshots; the final run passes with the fallback selected.

The locally signed arm64 app is in
`build/default-live-loupe-candidate-20261014/Aagedal Media Player.app`.
Open it directly for default live video. The adjacent native-raster launcher
opts into the existing candidate provider for paused inspection. MPVKit was
reused without rebuilding. [The receipt](candidate-receipt.json) binds source
and executable hashes; compressed build and test logs are retained here.
Previous [UHD playback qualification](../mpv-live-loupe-prototype-20261014/README.md)
remains the performance evidence; this change does not alter the viewer engine
or claim additional frame-lock, long-duration or HDR-display qualification.
