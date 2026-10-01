# Pinned live audio meter fixtures

`contiguous-dts.mkv` is an entirely generated 36,493-byte, six-channel DTS
fixture in a Matroska container with millisecond timestamps. Each 48 kHz
channel contains a 1 kHz sine wave at 0.1 amplitude for 0.2 seconds. Its SHA-256
is `4b8333804b796a3c323e54c05ef14095bbc23a35d4092cf6093a1357957073a1`.

The decoder regression checks the production FFmpeg decoding path, exact
9,600-frame source interval, six channels, timestamp provenance, and final EOF
snapshot. A missing or changed fixture fails the test. This provides synthetic
timestamp coverage; it does not establish authentic DTS-HD MA, numerical,
native playback, hardware or audible-output acceptance.

The previously inline fixture encoder intermittently crashes with SIGBUS.
Pinning successful output removes that unrelated encoder from this decoder
test without changing decoder settings or assertions. The encoder defect
remains unresolved. See the [generation receipt and diagnosis](../../docs/evidence/dts-fixture-encoder-diagnosis-20261001/README.md)
for the exact generation command, signal source, binary/output hashes, and
bounded repeated trials. Re-encoding Matroska can change container metadata and
thus its whole-file hash; intentionally replace the fixture/hash together.
