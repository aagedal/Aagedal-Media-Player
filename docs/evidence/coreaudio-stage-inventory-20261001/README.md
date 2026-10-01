# Exact CoreAudio publication-stage inventory — 2026-10-01

The publication verifier now requires exactly the retained files and their
parent directories. Its earlier `rglob`/`is_file` inventory silently excluded
empty directories, FIFOs, directory symlinks and dangling symlinks. The
[before/after mutation record](mutation-verification.json) demonstrates that
the baseline accepted all five extra-entry cases and a symlink replacing the
manifest; the updated verifier rejects each case. Fixtures remain isolated in
temporary directories. The retained publication stage was not mutated.

The verifier walks without following directory symlinks and checks regular file
types before hashing payloads. Preparation verification, offline reconstruction
and the independent reconstruction auditor reject a nonregular `publication.json`
before reading or hashing it. Reconstruction rejects undeclared stage content
before creating its output workspace. The guards cover pipes without blocking
on an open operation.

The focused [publication suite](test-mpv-coreaudio-publication.log) passes 21
tests, and the [reconstruction suite](test-mpv-coreaudio-reconstruction.log)
passes 18. The unchanged [incremental candidate suite](test-mpv-coreaudio-candidate.log)
passes 12 tests and [clean candidate suite](test-mpv-coreaudio-clean-candidate.log)
passes 18; its deliberate GPL-parity rejection is expected.

[Actual publication verification](publication-verification.json) passes for all
46 files in `/private/tmp/aagedal-coreaudio-publication-prepared-20260930`.
[Actual reconstruction verification](reconstruction-verification.json) passes
for `/private/tmp/aagedal-coreaudio-reconstructed-v2-20260930`: 11,089 source
files, twenty auxiliary ZIPs and three exact shallow Git source repositories.
The externally retained publication digest remains
`3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c`.
[Evidence identities](evidence-sha256.json) bind the scripts and verification
records; the original staged preparer and reconstructed driver are unchanged.

This is a local retained-input integrity check. No dependency compilation,
download, upload, package resolution, shipping repin or runtime acceptance ran.
Public reconstruction/environment, authenticated remote assets, publication and
shipping app/hardware gates remain open. These checks do not demonstrate
byte-identical rebuilt libraries or authenticate a replacement evidence chain.
