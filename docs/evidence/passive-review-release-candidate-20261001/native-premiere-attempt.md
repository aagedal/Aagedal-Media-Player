# Native Premiere attempt — 2026-10-01

This record describes observed tool/UI outcomes, not accepted interoperability.

The primary agent bound `com.adobe.PremierePro.26`; the call returned after
252.774 seconds despite a supplied 30-second timeout. Subsequent AX/screenshot
observations reached Premiere's Home and New Project screens. A disposable
project was created at
`/private/tmp/aagedal-passive-review-focused-20261001/Aagedal Review Interchange 20261001.prproj`.
Its project UI showed no sequence and zero project items.

Command-I opened the native Import picker. Repeated Command-Shift-G attempts,
direct path-entry attempts and sidebar selection did not reach the intended
`29.97.xml` fixture. Sidebar selections reached different folders than the
requested controls. A fresh app binding did not resolve navigation. The import
was canceled; the returned AX state showed the disposable project again.
No media import, marker inspection or re-export was observed.

A delegated follow-up attempted a new binding. Display-name binding returned
Invalid app. Inventory identified the running app as Adobe Premiere with bundle
ID `com.adobe.PremierePro.26`. Binding that ID produced no AX/screenshot state
and was aborted after 521.3 seconds despite a supplied 30-second timeout.
The sub-agent performed no further input and produced no returned XML.

Native Premiere acceptance remains unverified. These control/navigation failures
are not evidence that the app's Premiere exporter is incompatible. Retain the
existing fixture matrix and complete observed import/marker/source/geometry/
re-export acceptance when native control is available. No existing user project
was opened or modified in these attempts.
