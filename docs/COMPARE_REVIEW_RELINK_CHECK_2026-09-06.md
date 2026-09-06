# Review relinking acceptance check — 2026-09-06

## Automated verification

The Release suite passed all 376 tests without failures or skips. After adding
main-window relink failure alerts, all 36 focused store, controller, and report
tests passed again. Xcode Release static analysis and all 61 release-preflight
checks passed. The suite includes stale preview/write completion, same-path
primary replacement, cancellation, malformed documents, incompatible/equivalent
rates, mixed-rate still caching, and concurrent exclusive publication.

## Native workflow

Used the current locally built Release app on the development Mac and disposable
copies of generated `compare/source-a.mov` and `compare/source-b.mov`. No private
or production media was opened. The old review referenced missing `/old-volume/`
paths and contained one Major / Picture / In Progress finding at A frames 42–47.

- Opened relocated A and B through the normal media file dialogs.
- Opened Review, chose Relink Notes, and selected the old JSON. The Review
  popover closed while the file picker and main-window confirmation remained
  reachable.
- Visually inspected the confirmation: both old/current A/B paths, note count,
  new sidecar path, and non-overwrite explanation were readable.
- Pressed Escape at confirmation. The review stayed empty and a disk check
  found no new sidecar.
- Selected malformed JSON. A visible main-window “Could Not Relink Notes”
  alert explained the parse failure. After dismissal, Review retained the error
  and allowed another attempt.
- Selected the valid original using file-picker keyboard navigation and
  confirmed with Return. Review displayed the imported text, A frames 42–47,
  and Major / Picture / In Progress classification. Relink was then disabled
  because the review was no longer empty.
- Inspected the new JSON: every note field equaled the original, and the new
  identities referred to the loaded A/B files. SHA-256 comparison confirmed
  both media copies were unchanged. The original JSON retained its old paths.
- Closed the disposable player window after the check.

## Limits

This validates the targeted picker/confirmation/error workflow and Return/Escape
activation. It does not certify complete keyboard-only review creation/export,
Full Keyboard Access, VoiceOver, external-volume behavior, or target-editor
round trips. Existing-destination, dangling-symlink, and concurrent-writer
protection are automated tests, not a native overwrite acceptance check.
Relinking maps intended originals without proving content equality or retiming
findings; the portability limits remain in `COMPARE_REVIEW_SIDECAR.md`.
