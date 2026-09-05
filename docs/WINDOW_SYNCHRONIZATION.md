# Window synchronization and Compare Mode

**Playback > Sync Transport Commands Across Windows** shares playback and
navigation commands between player windows. The same preference is available
in Settings > General when multiple windows are enabled. A **Transport Sync**
indicator appears in the player toolbar when the preference is enabled and at
least two live player windows have opened files. Hover over it for the scope
of synchronization. The menu toggle can disable it without opening Settings.

Each ordinary window has its own playback clock. Shared play, pause and
navigation commands do not continuously frame-lock the windows. Option-modified
navigation shortcuts remain local to the current window. The preference also
shares monitoring mute and volume commands.

**Playback > Align Windows to Current Timecode Once** (Shift–Command–S) seeks
other windows to the active window's current time once. It uses source timecode
when both sender and receiver have source timecode, otherwise relative time.
It works whether transport synchronization is enabled or disabled. Alignment
does not establish a shared playback clock or keep correcting drift.

For two-file inspection, use **Compare Mode** from the primary file's toolbar
and open the other file as its comparison source. This gives the pair a shared
timeline, explicit alignment and overlap state, and coordinated comparison
playback. A compare session still participates as one window in transport
commands shared with any other open windows; disable transport sync to inspect
the pair independently.

## Why reopen the file inside Compare Mode?

There is no “Compare these windows” transfer command yet. Ordinary windows own
their player controllers, native render surfaces, asynchronous file loading,
observers, and teardown independently. CompareSessionController owns a separate
secondary controller and its lifetime, audio suppression and alignment. Moving
an existing controller from another window would also require transferring its
render surface and ownership, detaching its command handlers, and preventing
the original window from tearing it down. That transfer is not implemented.

Reopening the same file as the comparison source creates a secondary player
owned by the compare session. It does not modify the file. Close the spare
ordinary window or turn off transport sync if it is no longer needed; this
also avoids decoding the same source in an extra window.

## Verification

1. Open two files in ordinary windows and enable transport sync. Confirm that
   both show the indicator and a playback command reaches both.
2. Disable the preference from Playback. Confirm that both indicators disappear
   and playback commands affect only the active window.
3. With sync disabled, use the one-time alignment command. Confirm the other
   window seeks to source timecode (or relative time without timecode).
4. Enable sync and close one window. Confirm the remaining window's indicator
   disappears. Open a second file in another window and confirm it returns.
5. Open the second file inside Compare Mode. Confirm its A/B alignment controls
   operate independently of the ordinary-window one-time alignment command.
