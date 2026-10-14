# Agent continuation

For native-pixel loupe / MPVKit work, read
[docs/MPV_NATIVE_RASTER_HANDOFF.md](docs/MPV_NATIVE_RASTER_HANDOFF.md) first.
A checksummed, validated Apple Silicon development bundle is available; restore
it instead of rebuilding MPVKit for app work or rerunning the retained fixtures.
Build and validate this candidate for **arm64 only**. Keep the shipping package
pins and default-off provider gate unless the task explicitly changes them.

The bundle includes local binary targets, native clients, independent fixtures,
source archives and acceptance receipts. Its descriptor is committed at
`docs/mpv-decoder-raster-handoff.json`. The handoff explains the remaining work
and when changing MPVKit source actually requires a new dependency build.

See `CLAUDE.md` for the existing application architecture and build conventions.
