# Avid Media Composer First EDL import diagnostic — 2026-09-29

This is a focused native import observation, not an Avid marker round trip.

- Editor: Avid Media Composer First, bundle version `26.8.0.58987` / build
  `26.8.0`; macOS `27.0.1`.
- Input: unchanged `docs/evidence/resolve-markers-20260919/unique-markers.edl`,
  SHA-256 `0536d12ccd301f0dab0dc2f28d72bd80029cb989f656432ec88ec15a0a902929`.
  This is the app's seven-finding Resolve EDL after the documented same-frame
  omission; it is **not** the Avid marker-text export.
- Project: new disposable `Aagedal 2.0 marker check`, 30i NTSC / 29.97 fps,
  stored under `/private/tmp/aagedal-avid-interchange-20260929`.
- Workflow: **File → Input → Import EDL…**, select the original EDL, confirm
  30 fps and 30i NTSC, select the project's empty bin.
- Observed result: Avid displayed “Creating sequence succeeded” and advised
  decomposing it to avoid video format errors. The bin contained one
  `SOURCE-A.MOV VS SOURCE-B.MOV REVIEW` sequence. Opening it showed a
  `00;00;58;00` start and `10;09;29` duration. The monitor said **MEDIA
  OFFLINE**, consistent with the input's historical source paths no longer
  existing. The original EDL was unchanged.

The sequence-creation dialog does not establish that `|M:` review comments
became Avid markers. Marker records and content were not observed, and no
re-export or source-media link was completed. The importer may have used only
the EDL edit events. This result does not qualify the Resolve EDL as an Avid
marker interchange format or satisfy the Avid acceptance row. Repeat with
current-source fixtures and separately import the app's Avid marker-text file.
