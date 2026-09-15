# Future MCP ideas (evaluation only)

No MCP server is currently planned for Aagedal Media Player. Revisit only if a
real agent workflow needs access to the player's *live inspection session*.
Generic media inspection and conversion already overlap with Aagedal Media
Converter's MCP tools and do not justify a second server here.

Potential player-specific workflow: an agent reads the active A/B pair,
alignment and frame-addressed Comparison Review findings, then prepares a QC
summary or exports evidence for a selected finding. A minimal read-only surface
could expose:

- The active comparison's source identities, alignment mode/offset and playhead.
- Structured review findings, including frame positions, rational rates,
  severity, category, status and stable IDs.
- Existing annotated-still or report export for an explicitly selected finding
  and approved destination.

Writing or classifying findings should be a separate, later decision. Any such
tool would need to preserve the review store's identity validation, ordered
saves, error recovery and stale-session checks, and make agent-originated edits
clear to the user. Do not treat display-space difference or loupe captures as
objective, frame-locked quality measurements. Programme loudness with explicit
speaker mapping is another possible automation capability, but a shared
measurement service may be a better home than a player-specific MCP server.

Validation before implementation: identify a concrete consumer and task that
cannot be handled adequately by the Converter's MCP tools or the player's
existing JSON sidecar, CSV/PDF reports and editor-marker exports. If that use
case does not emerge, leave this idea unimplemented.
