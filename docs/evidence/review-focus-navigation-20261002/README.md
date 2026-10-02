# Native Review focus continuation — 2026-10-02

A native invalid-range attempt exposed separate row/panel focus ownership:
New Note and Filter commands could still send input to the range correction.
Review now uses one shared field destination, preserves identical invalid
passive validation without recreating correction requests, and suspends row
restoration for explicit New Note/Filter navigation. Unchanged field callbacks
preserve errors and suspension. Explicit action retries restore correction
ownership; ordinary reopening selects a retained live correction. Stable panel
correction reveal selects the destination; mounted-field restoration completes
the handoff after filters recreate lazy rows.

Owner-only draft editing resumption keeps explicit navigation suspension when
editing another finding or the companion field in the selected finding. Its
regression covers both correction fields, owning edits and no-owner behavior.
Eight additional regressions bring the focused optimized Release suite to 54;
all pass with zero failures/skips. No runtime warning is recorded. An existing
weak-variable compiler warning in ProgrammeLoudnessControllerTests is retained.
Candidate/release consumption requires those exact identities and 818 aggregate
tests. The retained intermediate native failure demonstrates why passing draft
policy tests alone did not prove actual keyboard focus.

The native merge observation confirms an externally edited test-sidecar deletion
merges through production Add/save, retires the invalid row/error and permits a
surviving text edit committed by Tab. Pre-merge and saved post-merge sidecars are
retained; the fixture was restored from its backup afterward. This is simulated
external-client deletion, not actual two-window UI acceptance. The earlier parent
focus handoff still failed filtered export and is explicitly retained as such.

The final mounted-field native repeat passes Filter navigation, blocked export
clearing the filter and selecting the rejected range, a valid endpoint typed
without clicking a field and persisted as 25, New Note navigation preserving
invalid input, repeated export correction and ordinary reopening restoration.
See [final observation](native-final-observation.json) and saved sidecar.

Native observations use isolated generated media and a test-only sidecar at
`/private/tmp/aagedal-2-native-structured-review-20261002`. No complete structured
keyboard traversal, spoken VoiceOver, real two-window merge, dependency repin,
hardware or distribution acceptance is inferred. Focused xcresult/build products
remain in temporary storage; durable detailed receipts and compressed logs are
retained here. Canonical implementation evidence is retained separately.

The final owner-only native follow-up keeps focus for companion-text and
different-finding edits while the invalid range/error remain. Explicit Export
selects the invalid range again without discarding either text draft. These are
focus/draft observations, not persistence claims for those unsaved text edits.
See [multi-field observation](native-multi-field-observation.json). The first
canonical attempt at `2478338` was interrupted deliberately (exit130) after this
additional path was identified; it supplies no accepted candidate evidence.
