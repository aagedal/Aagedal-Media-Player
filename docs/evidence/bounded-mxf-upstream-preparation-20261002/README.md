# Bounded MXF normal upstream package preparation — 2026-10-02

A fresh isolated checkout at SwiftMediaMetadata 3.0.1 revision
`8662054299a3e13c49c65f74c564360559d1bf7f` now builds and tests the portable
bounded-MXF correction with the normal upstream manifest, CLI, Benchmark and
lockfile preserved. The workspace is
`/private/tmp/aagedal-bounded-mxf-upstream-preparation-20261002/SwiftMediaMetadata`.
Only the six portable patch source/test files differ from HEAD. The retained
earlier bounded-MXF candidate and the app's package caches/pins were not modified.

[Preparation and test receipt](preparation.json) records exact commands,
environment, base/patch source identities, unchanged before/after source hashes,
actual built CLI identity and dependency resolution. A valid existing SwiftPM
Git cache for ArgumentParser was cloned without hardlinks or object sharing to
this workspace's independent cache. Its declared GitHub origin, 1.7.1 tag and
pinned revision `626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b` match the unchanged
upstream lockfile. Git object-integrity checks pass; the actual resolved checkout
is clean at that revision. SwiftPM fetched from that local cache with
`--force-resolved-versions --skip-update`. This is offline content/commit
integrity checking, without new remote download or authentication.

- [Normal complete upstream test log](library-tests.log.gz): **1,674 library
  tests, 21 explicit opt-in skips, zero failures**. All normal package targets,
  including ArgumentParser and `swift-exif`, compile. The default CLI target
  also runs 50 tests with 28 black-box opt-in skips and zero failures.
- [Opted-in CLI target log](cli-tests.log.gz): **50 tests, zero skips, zero
  failures**, including the black-box CLI cases. The test harness's existing
  `SWIFT_EXIF_CLI_BINARY` override points to the executable built in the isolated
  scratch directory; no harness or executable source was substituted.
- The package manifest, lockfile, Benchmark and six correction files remain
  byte-identical before/after testing. The source receipt and compressed logs
  are bound by [evidence hashes](evidence-sha256.json).

The initial missing temporary-directory attempt and initial CLI binary-location
failure remain in [setup log](initial-missing-temp-directory.log.gz) and
[lookup log](initial-cli-binary-location-failure.log.gz). The latter failed
because upstream defaults search the package's `.build` directory while this
run uses a separate scratch directory. Creating the declared temporary directory
and supplying the documented binary override corrected those invocation issues.
Neither required a package, CLI, test or correction-source edit.

These are local Debug SwiftPM tests with isolated Clang/Swift/package caches;
debug information was disabled to avoid the previously blocked `dsymutil`
helper. No Release archive, fresh authentic-media observation, upstream commit,
tag, publication or shipping app repin ran. The 21 library opt-in skips and
existing external-volume, multi-hour, Linux, supported-macOS/base-M1 and
shipping-integration acceptance gates remain open. A final release revision
still requires version/release preparation and checks on its exact final tree.
