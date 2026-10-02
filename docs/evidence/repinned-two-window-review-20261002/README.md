# Repinned native two-window Review — 2026-10-02

The Release app at dependency integration commit `7c95d27` was exercised using
new disposable copies of the retained 24-fps reference/delivery MOVs. Distinct
native `player-AppWindow-1` and `player-AppWindow-2` sessions loaded the exact
same sidecar. The second window's real UI deletion saved successfully.

Window one retained a rejected `-1` endpoint and an unadded note across the
window switch. Its subsequent production Add/save merged the other window's
successful deletion, removed the deleted finding and its correction notice,
and persisted the retained draft. Keyboard Tab/Return then saved a surviving
finding's text, demonstrating that the retired correction no longer blocked
that edit. Before/after sidecars and unchanged media hashes are retained.
The original Allow Multiple Windows setting was off; it was temporarily enabled
and restored to off after the test.

This closes this bounded real two-window deletion/correction/draft/save scenario.
Classification expansion, window switching and deletion used native accessibility
actions. Complete keyboard-only classification, Full Keyboard Access, spoken
VoiceOver, other backends and relink/migration/recovery remain open. The initial
aggregate verifier rejected missing-fixture skips; this native observation does
not make that run accepted. See the exact app identity and action distinctions
in native-observation.json.
