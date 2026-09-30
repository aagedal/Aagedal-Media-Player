# Authentic camera production metadata memory — 2026-09-30

Three unmodified camera recordings pass the actual `MetadataService` Release
profile in separate XCTest hosts, using SwiftMediaMetadata 3.0.1 and the shipping
MPVKit pin. All uncached/cached app-model comparisons pass, and input media,
matching XML sidecars, app/test binaries, metadata source and package identities
match before and after execution.

| Recording | Duration | Source bytes | Lifetime peak increase | Uncached load |
| --- | ---: | ---: | ---: | ---: |
| Sony `rre_8073.MP4` | 258.72 s | 1,879,319,902 | 4.438 MiB | 0.0533 s |
| Sony A1 `20260502_TRA_MOV_0240.MP4` | 111.36 s | 1,569,013,272 | 59.531 MiB | 0.0547 s |
| Sony FX6 `OJ_FX6A0021.MXF` | 139.84 s | 8,643,449,904 | 368.516 MiB | 0.1836 s |

These are individual observations on the current host, with a concurrent
dependency build. They establish producer-authentic metadata-path observations,
not throughput, thermal, multi-hour scaling or base-M1 acceptance. The retained
[raw rows](summary.json) include sample counts and every memory phase.

The FX6 increase is transient: resident memory falls from a sampled 473.19 MiB
during loading to 114.22 MiB after conversion, versus 112.80 MiB initially.
Its lifetime peak is 481.31 MiB. The A1 settles at 144.56 MiB after loading,
versus 112.81 MiB initially. This does not demonstrate a retained full-payload
copy, but the peaks are material to the broader resource gate.

Source inspection shows that the exact 3.0.1 MXF reader visits every KLV key and
BER length and peeks up to 512 value bytes before classifying and skipping
essence. The file is memory-mapped. An independent offset walk reaches the exact
end of this original file after 160,944 complete KLVs; those header/peek ranges
project onto 22,523 host-sized 16 KiB pages (351.92 MiB), before the reader's
separate bounded 16 MiB header scans. This is consistent with the observed peak
and motivates a bounded file-backed MXF reader. It is an inference, not a VM
allocation trace or proof of sole causation. [The diagnostic](mxf-header-page-diagnostic.json)
and [its source](trace-mxf-header-pages.py) preserve the calculation.

No dependency source, parser behavior or production metadata policy was changed.
This observation leaves long-file memory acceptance open and does not reopen or
replace the separately verified top-level MP4 `mdat` copy correction.

The shipping-pin `build-for-testing` came from current development source at
`36ae497`, with concurrent Review-only edits. Metadata/profile sources remained
unchanged. [The environment](environment.json) retains exact identities and
worktree status; no clean-release-source claim is made for this profiling app.
The source build and live meter's copied repaired apps are separate artifacts.
The original derived-data directory was reused for focused Review verification
after profiling identity checks; its current app path does not promise the
historical profiling binary recorded in the environment.

The first temporary manifest used the wrong test-root location and did not run
tests. A corrected sandboxed invocation could not access `testmanagerd`; the
permitted repeat executed all three tests and passed the unchanged artifact
validator. Those infrastructure failures do not supply metadata outcomes.

Complete result bundles remain at
`/tmp/aagedal-authentic-production-metadata-v3-20260930`; retained logs,
attachments, environment, validator output and orchestration source are covered
by [evidence hashes](evidence-sha256.json). The normal reusable profiling command
remains `scripts/profile-production-metadata-memory.sh`.
