# Dependency publication — 2026-10-02

SwiftMediaMetadata 3.0.2 is public at immutable revision
`9e8e912deb8d941da66a4b76854a90e3e9f01e3f`. Its normal GitHub release workflow
passes complete final-tree preflight. A fresh download passes the published
archive checksum, reports CLI 3.0.2 and successfully resolves Oslo using the
bundled geocoding resource. Original library/CLI source corrections are retained
from `8297324bb00ad1358b4070575c1ea59e698d3f2f`.

MPVKit's macOS GPL dependency prerelease is public at immutable revision
`1d44b9a0aa9e8faa5b8bf222173f6cc2930ed233` and tag
`aagedal-2.0.0-coreaudio-20260930`. It includes all eight exact qualified framework
ZIPs, the historical publication manifest and the complete 46-file source/input
stage archive. The tagged package also retains the portable driver and fresh
rebuild receipt.

The new standalone driver runs without network using macOS sandbox-exec,
requires explicitly preinstalled tools, relocates Metal paths, declares host
pkg-config directories and binds SDK/header symlink closures. The initial
fresh attempt failed because the explicit pkg-config list omitted Homebrew's
Apple SDK zlib shim; it remains at
`/private/tmp/aagedal-coreaudio-portable-build-20261002`. The corrected attempt
uses the explicitly declared shim directory and passes at
`/private/tmp/aagedal-coreaudio-portable-build-v2-20261002`: both binary
architectures, fresh CoreAudio objects, GPL/Metal/Samba and every boolean
configuration header digest match the qualified build. Declared tools and input
trees are rehashed after compilation. Five driver regressions pass, including
same-size changes behind header symlinks and actual network denial.

Published payloads remain the exact qualified September 30 binaries;
recompilation is not claimed byte-identical. The missing original environment
identities remain historical gaps. Dependency slices do not establish downstream
runtime or platform acceptance.

All 29 binary-target URLs and twenty build-input URLs now pass fresh HTTPS
byte/hash verification with retained redirect identities. Fresh ordinary Xcode
resolution from a new package directory succeeds with the exact app pins and
Sparkle unchanged; the package-cache gate confirms all three clean checkout
identities.

The initial published stage archive retains macOS AppleDouble metadata and
fails strict inventory validation when extracted by Python. It is retained as
superseded. A new metadata-free `coreaudio-publication-stage-portable.tar.gz`
asset and `release-assets-portable.json` are public, without replacing any prior
asset. The new archive passes local Python extraction and complete stage
verification; its fresh remote re-download now passes the external archive hash/size and complete
strict stage verification after Python extraction. Its SHA-256 is
`726d1b7bffcc4d7cfaf73a489140870c2bacda2fd55cb5454d4deabec1e08ade`.

The first app verifier at `7c95d27` executes 764 passing tests with zero failures
or runtime warnings, but rejects 54 skips because this new worktree lacked its
ignored generated fixture tree. This is rejected evidence. The current fixture
generator has now populated the normal ignored path; a fresh canonical retry
is required. Native app work uses that repinned Release product, without claiming
its incomplete aggregate run is accepted. Native/editor/accessibility, runtime/device/soak,
source-pixel and distribution/beta gates are not closed by publication.
