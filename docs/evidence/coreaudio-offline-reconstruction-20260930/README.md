# Offline GPL source/input reconstruction — 2026-09-30

The publication preparer now has a reconstruction mode that materializes the
[retained publication stage](../coreaudio-publication-preparation-20260930/README.md)
on a new host without invoking its build recipe. It requires a SHA-256 for the
publication manifest retained outside the stage, then verifies every published
payload, the exact source Git trees/commit objects, and input receipt bindings
before creating the workspace. It performs no downloads, uploads or app repin.

The driver restores the exact recipe, patched mpv and FFmpeg snapshots into
independent Git repositories, stores their original commit objects, and sets
HEAD to their retained revisions. Missing upstream parents are explicitly marked
as shallow boundaries. It preserves executable file modes, ignores inherited
Git configuration while reconstructing tree identities, and rejects source
archive symlinks or unsafe paths before extracting that archive. The twenty
auxiliary ZIPs are copied unchanged to the recipe's versioned cache paths. The
recipe performs ZIP expansion when a later build is authorized and prepared.

`reconstruction.json` records all reconstructed source/input identities, the
actual driver snapshot identity, a workspace-specific candidate command,
isolated cache/temporary paths, and an environment declaration. The declaration
copies only original receipt facts; absent versions/hashes remain explicitly
unrecorded. The command is data for review and is never executed by this mode.
The workspace also retains `reconstruction-driver.py` as the actual driver
snapshot. Existing output directories and stage/output overlap are rejected.

```bash
python3 scripts/prepare-mpv-coreaudio-publication.py \
  --reconstruct /private/tmp/aagedal-coreaudio-publication-prepared-20260930 \
  --reconstruction-output /tmp/new-coreaudio-reconstruction \
  --expected-publication-sha256 3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c
python3 scripts/test-mpv-coreaudio-publication.py
```

The digest above belongs to the previously retained 2026-09-30 stage; use the
externally retained digest for whichever stage is actually being reconstructed.
The historical stage retains its original preparer. Run the current repository
driver, or its separately reviewed snapshot, to use the new reconstruction mode.

## Validation and limits

[Regression results](regression-tests.log) cover publication mutation rejection,
exact Git revision/tree restoration with unavailable parents, inherited Git
configuration isolation, copied input identities, source extraction safety,
external-digest failures and existing/overlapping output refusal. The actual
retained 46-file stage was reconstructed into a separate local workspace;
[its receipt](reconstruction.json) and [independent identity check](verification.json)
retain the small review artifacts, without duplicating source archives or ZIPs
in this repository.

This closes source/input materialization and reviewable command declaration.
It does **not** prove a fresh dependency build or byte-identical libraries. The
original recipe remains unchanged, including its host-specific Metal compiler
paths and network/tool-installation fallbacks. A fresh host must select and probe
its own Metal toolchain, record recipe path relocation, declare SDK/external
headers and missing tool identities, and control feature autodetection before
compilation. Original build environment facts that were not retained cannot be
invented retrospectively. Public source/input/artifact availability, remote
checksum authentication, ordinary fresh-cache SwiftPM resolution and shipping
app/runtime acceptance remain separate gates.
