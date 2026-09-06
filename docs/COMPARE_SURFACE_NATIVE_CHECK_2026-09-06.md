# Native comparison surface transition check — 2026-09-06

The original Release build at `c2c5e81` lost source A's visible MPV picture when
entering Compare Mode. Its timecode continued advancing, and source B remained
visible. Source A's native view was structurally replaced while its MPV context
kept the detached Metal drawable.

The continuation retains a single primary canvas across comparison membership
changes. Inactive comparison uses full-resolution A-only geometry and hides
comparison effects, source badges, and guides.

## Native reproduction and retest

Used macOS 27.0 (26A5425a), the rebuilt Release application, and the generated
24 fps demo files `Source A - reference.mov` and
`Source B - delivery encode.mov`.

1. Open A, pause at `01:00:00:02`, and enlarge the native window from its narrow
   initial size to 1728 points wide.
2. Add B through the native file picker. Both pictures remain visible. A's
   burned-in counter reads frame 2 and its playback position remains unchanged.
3. Replace B with the same generated B file. Both pictures remain visible and
   A remains paused at frame 2.
4. Exit Compare Mode. A fills the single-source picture area and still shows
   frame 2. No reload, playback command, or seek is needed to recover the image.

Native screenshots were inspected at each transition. The first retest was
performed while hosted XCTest execution was active; the resulting test run
had failures and is not counted as a clean integrated validation. The complete
394-test Release suite then passed with zero failures or skips while native
automation stayed idle; final static analysis and all 61 preflight checks also
passed. All four native steps above were repeated successfully after the
XCTest processes finished, confirming entry, replacement, and exit independently.

## Automated regression

`testPrimaryMPVSurfaceSurvivesComparisonEntryReplacementAndExit` hosts the actual
`ContentView` with real MPV decoders. It checks that A's Metal layer and
preparation identity survive paused comparison entry and B replacement/exit
while playback continues. It also checks inactive presentation ignores saved
reduced comparison resolution.

This focused transition check does not replace the all-mode native pointer,
VoiceOver, transformed-media, or oldest-supported-hardware acceptance gates.
