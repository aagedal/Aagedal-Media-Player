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

Fresh verification of all 29 binary-target URLs and twenty build-input URLs,
remote stage re-download, fresh repinned app resolution and canonical app
acceptance are in progress. Native/editor/accessibility, runtime/device/soak,
source-pixel and distribution/beta gates are not closed by publication.
