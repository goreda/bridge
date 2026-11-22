# H0735 current host seam reply, read-only qualification

Source identity: goreda/instinct owner route commit 2ddfc14e381ea308d68b38e8a81b583dd1ffc3e8, archive/gor. This replaces the older a815-only observation, not product custody.

At this exact source, UI/MenuActions.swift:223 sends plain mpv stop. Modes/MusicModeController.swift:134,153 sends plain stop during mode changes. Engine/GorAVPlayerHost.swift:753 maps stop to closeSession(); :841 starts the host close barrier. Embedded GorAVEmbeddedSession.swift:1351 maps stop to exactly-once teardown with userStop.

Assembly's current-source review found no whole-host active-playlist plus stop-flags seam on that route. The existing session stop tears down one lifetime; the host can replace sessions behind its close barrier. These facts do not establish a reopen defect, and close/window intent is not a substitute for playlist-stop semantics. Reference/default playlist-clear versus keep-playlist contract remains an implementation gap to qualify, not an accepted product fix.

H0735 remains reference/current-contract/regression qualification only. No full-row or shell-writer custody is assigned here; R4/R2/G4 metadata is not acceptance. No new GO, code archive, owner-route change, native result or owner acceptance in this reply. Continue through the existing sole writer and canonical QUEUE/LEDGER custody.
