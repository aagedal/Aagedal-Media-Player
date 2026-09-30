# Repeatable CoreAudio reconstruction audit — 2026-09-30

The new `scripts/verify-mpv-coreaudio-reconstruction.py` audits an existing
offline workspace against an externally pinned publication stage. It verifies
the entire stage first, then checks all three source Git HEAD/tree identities,
actual source working-file bytes and executable modes, all twenty cached input
ZIPs, and the reconstruction receipt's driver, source/input, command, working
directory, cache and environment declarations. It performs no compilation,
downloads, uploads or dependency repin.

[Actual verification](verification.json) passed against
`/private/tmp/aagedal-coreaudio-publication-prepared-20260930` and
`/private/tmp/aagedal-coreaudio-reconstructed-v2-20260930`: 11,089 retained source
files, three shallow source repositories and twenty auxiliary ZIPs. The original
publication manifest SHA-256 remains
`3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c`.
The workspace retains its original driver; the new auditor is recorded separately
in [evidence identities](evidence-sha256.json). The large stage/workspace payloads
remain local.

The publication verifier also now binds each declared upstream source revision
to the retained build receipt and each origin URL to its expected project. The
[before/after reproduction](provenance-regression.json) shows the original
verifier accepting replacement mpv upstream provenance in a synthetic fixture,
and the fixed verifier rejecting it. This repairs provenance validation within
the retained chain; the manifest remains a checksum inventory, without a
signature or remote authentication.

The [seventeen publication regressions](publication-regressions.log) and
[ten reconstruction regressions](reconstruction-regressions.log) pass. They cover
upstream provenance replacement, source edits hidden by Git `assume-unchanged`,
executable changes hidden by `core.filemode=false`, changed commits and input
ZIPs, receipt mutations, stage/digest failures, inherited Git directory isolation,
source symlink replacement and CLI exit status. Tests use temporary fixtures and
isolated Git configuration. Both suites are included in the normal script gate.

```bash
python3 scripts/verify-mpv-coreaudio-reconstruction.py \
  /private/tmp/aagedal-coreaudio-publication-prepared-20260930 \
  /private/tmp/aagedal-coreaudio-reconstructed-v2-20260930 \
  --expected-publication-sha256 3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c
```

This checks the declared retained files, rather than certifying the absence of
all extra files or proving a hermetic build environment. It does not run the
declared build command or demonstrate byte-identical libraries. Portable Metal
selection, missing original tool/SDK/header identities, controlled autodetection,
public payload availability, authenticated downloads, fresh SwiftPM resolution,
shipping repin and native/hardware acceptance remain open as described in the
[original offline reconstruction](../coreaudio-offline-reconstruction-20260930/README.md).
