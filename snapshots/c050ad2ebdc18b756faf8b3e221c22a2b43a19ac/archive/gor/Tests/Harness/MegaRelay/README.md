# MEGA relay framing and lifecycle harness

Run `bash gor/Tests/Harness/MegaRelay/run.sh`. Requires Python 3 only. Reads current MegaStreamManager.swift, AppDelegate.swift and vendored mega_relay.mjs directly. No stored-source fallback, subprocess launch, MEGA request, socket, download or playback. Reviewed at the commit in manifest.json.

Priority: unlike the existing caption/CDP/camera lifecycle cells, this relay dispatches readiness/error work without current-process identity. A ready callback already queued on main can outlive stop or replacement, changing the selected media or title. Independent per-read UTF-8 decoding also discards a line when a multibyte scalar splits between reads. These are source-grounded model counterexamples, not observed Mac incidents.

Controls: 496 ASCII ready-line chunk partitions, combined/blank/CRLF/tail framing, independent stdout/stderr and current readiness. Five known-red characterizations cover queued readiness after stop/replacement, stale errors, duplicate ready and split UTF-8. Three source mutations are rejected. PASS means controls and expected counterexamples were reproduced, not that correctness or native timing passed. Introducing an identity/terminal guard requires updating the port, not erasing the known-red without replacement assertions.

Fix handoff: bind relay callbacks to the owning process or generation at delivery time; invalidate before teardown; enforce one terminal ready transition; keep incomplete UTF-8 bytes between reads. Preserve current stdout/stderr separation, line framing, one valid ready callback and off-main reaping. Re-test queued A after B starts and split scalar boundaries. This describes a candidate direction, not a production patch or native proof.

Open: actual FileHandle/main queue ordering, Foundation UTF-8 behavior, process failure/EOF cleanup, newline-free buffer limit, port reuse, producer integration, real MEGA and playback. No Swift compiler was available in this run. No visual output created. No production files changed; this package contains only harness paths.
