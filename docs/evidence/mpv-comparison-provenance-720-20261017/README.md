# 720/15 sustained scope provenance continuation

This run resumes the explicit serial-repeat step in the
[retained 720/15 rejection](../mpv-comparison-scope-provenance-soak-20261016/README.md).
It uses current merged app/test sources with the verified arm64 native-raster
baseline and scope delta. MPVKit is not rebuilt. Shipping pins and the native
provider's default-off gate remain unchanged.

## Rejected complete run

The fresh arm64 Release build, local deep/strict signature verification, **69
focused hosted tests** (zero failures/skips) and **14 runner regressions** pass.
The three-cycle sustained run **fails** the unchanged cycle-end memory gate.
Physical footprints were **643,877,912**, **959,368,288** and **968,838,384 bytes**:
maximum growth **309.91 MiB** above warmup (limit 256 MiB). Both later cycles
exceeded the limit. The runner exits unsuccessfully even though XCTest prints
all three end-of-workload markers. No sustained acceptance is claimed.

All **396 loupe windows**, **198 scope windows**, **54 sampled difference
publications** and **six fresh resumes** completed. Every one of the **54
selection groups** measured at least **11.79 seconds**. The sampled difference
checks each cover **291,600 pixels** and complete occupied-bin sets. Minimum
loupe cadence was **48.31 presentations/sec**, maximum drift **83.3 ms**, and
**11,878/11,880 clock samples** were usable; every window meets its 29/30 gate.
Native A/B endpoint, pixel/bin, input-progress and idle screenshot-worker
assertions reported no failure. These completed checks do not override the
memory rejection.

[Statistics](stats.json), [failed summary](soak-summary.json),
[measurements](measurements.txt), compressed action/stdout/build logs and executed
configurations retain the result. [The candidate receipt](candidate-receipt.json)
marks `accepted: false` and pins matching current/prepared Swift file sets and
hashes, arm64 executables, fixtures, manifests, descriptors and validation tools.
`execution-inputs.json` pins executables/manifests before the sustained run;
retention verifies they remain unchanged and match executed configuration paths.
The source patch is empty: no production or XCTest Swift source was changed.
Local app/results remain under `/private/tmp/aagedal-provenance-720-20261017`.

## Memory diagnosis and next work

Read-only lifecycle review found no concrete accumulating retain cycle. Pair
cleanup removes the host, stops captures/comparison tasks and tears down both
sources/followers; scope publication history is bounded. This is inspection,
not proof of complete object retirement. No production/provider change or gate
relaxation is justified from footprint samples alone.

After the cycle-two rejection, `vmmap -summary` sampled the running process in
cycle three. [That diagnostic](cycle3-vmmap-summary.txt.gz) contains malloc,
purgeable and graphics allocation categories, but is an in-playback snapshot
without matching cycle-end baselines. It cannot establish a leak or its cause.
The diagnostic can perturb cadence; cycle-three timing, including the overall
minimum above, is retained with that limitation. The earlier cycle-two memory
failure predates it.

Next collect matched per-cycle teardown memory categories and weak retirement
probes for hosts/controllers/scope workers/loupe sessions before selecting any
fix. Repeat in a coordinated host window after diagnosis, preserving both this
rejection and the earlier loaded native-fallback rejection. A separate pass
cannot establish the cause of either failure. The original serial/quiet-host
acceptance remains open because unrelated jobs were present here and this run
failed memory.

## Host context

The initial host check found no competing Media Player workload. Other-project
Photo Agent and Media Converter builds/tests appeared during focused validation.
After a bounded wait, the sustained test started without another Media Player
benchmark, while those unrelated jobs remained active. The retained
`host-processes.txt` records that context. This is not an idle-host claim and
does not reproduce the earlier concurrent Media Player benchmark.

## Reproduce

The retained `prepare.py` verifies both inventories and the complete overlaid
package before preparing current sources. Its absolute paths identify this local
run. Build arm64 Release for testing with testability enabled using the
[native raster handoff](../../MPV_NATIVE_RASTER_HANDOFF.md), then run:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance \
  --scope-resolution 720 --scope-fps 15 --soak-seconds 10 --soak-cycles 3
```

`run-focused.py` runs the existing native/loupe/scope correctness selection plus
the process-local settings regression. `retain.py NEW_RUN_ROOT` requires passing
zero-skip focused and sustained results, exact settings receipts, complete
measurement identities and all 54 selection-duration groups before writing the
receipt. Accepted retention requires successful XCTest; `--rejected`
retains a failed complete workload explicitly with `accepted: false`. The native
A/B endpoint, difference-pixel/bin, presentation, clock, idle screenshot-worker
and cycle-end memory gates remain unchanged.

## Limits

A separate serial success does not explain the earlier loaded native fallback
or qualify arbitrary concurrent workloads. Process snapshots sample host state;
they do not reserve the GPU or prove an idle OS throughout the run. Difference
correctness is sampled once per measured difference window and after each pair's
capture restart, not on every publication. Exact provenance refers to submitted
captures; screenshot timestamps remain estimated. Occupied-bin checks do not
qualify full plot colors/intensities. Metal counters count loupe presentations,
not unique frames or composite-canvas cadence. Cycle-end physical footprints are
not peak/GPU memory measurements or a total-memory ceiling. Generated UHD60
looped media, the 960×540 canvas, these settings and this host bound the result.
Producer-authentic long media, other hosts, dependency sanitizer coverage, frame
lock and physical HDR calibration remain open.
