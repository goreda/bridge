# QUEUE-1NSTINCT

## Verbatim owner standing GO and original queue

RELAY 1nstinct (verbatim, GO, standing): Run 4-6 workers in parallel, one row each, pull the next row when one returns. Return code + test log to returns/<row>/. Queue:
 Q1 199bv Picture station git mv script + Package.swift diff (Viewport, CropDetector, Brightness, AdaptiveColor, LookToolsRoute)
 Q2 199bv Stereo station script (Stereo, ThreeD, VR180*, VRDistanceModel, VRStereoControlInput, GazeCrosshair, StereoLookNative*)
 Q3 199bv Session station script (PlayerSession*, PlayerRuntimeResources, PlayerTorrentEndpoint, RealtimeProbe, Build, Diag)
 Q4 191c R2 roll-compensated partition patch for vr180-look.lua with the R4-bound test from your scorer
 Q5 Photon v12 block182 contract: distance clamp, filters, 2 s face hold, FOV fallback, as pure Lua module + tests
 Q6 gorav PLAN v4: next 3 unstarted P-rows (lowest number first), one patch + test each
 Q7 WT G7 harness repair: drive.mjs chunk budget + resume timer, extract.mjs peak RSS, 16-peer run

## Current execution ledger

| Row | State | Outcome / next action |
| --- | --- | --- |
| Q1 | SOURCE_COMPLETE | Picture pure moves integrated. Original list is historical: AdaptiveColor resolved to UI, LookToolsRoute to Stereo. No duplicate implementation. |
| Q2 | SOURCE_COMPLETE | Stereo pure moves integrated. No duplicate implementation. |
| Q3 | SOURCE_COMPLETE | Session pure moves integrated. No duplicate implementation. |
| Q4 | OPEN / check existing return first | Pull original191c R2 partition patch work from existing191c packet/scorer context. If already returned, link exact code/test receipt instead of repeating it. |
| Q5 | OPEN / check existing return first | Pull original Photonv12 block182 pure-Lua contract/tests; preserve original bounded scope. Name any missing exact contract/source input. |
| Q6 | INPUT_PENDING | Actual PLANv4 lowest3 unstarted P-row IDs/status requested from coordinator. Do not guess rows or collide with existing writers. |
| Q7 | OPEN / safety envelope required | Original WT G7 harness repair only. Reconcile existing code/returns first;16-peer execution requires established numeric safety/resource limits. If absent, return exact blocker while code repair proceeds where inputs suffice. |

First pull candidates are Q4, Q5, Q7, subject to existing exact claims/returns. These are work offers under standing GO, not claims that labs have started. Return a claim or precise blocker now; do not wait for another per-packet GO.

## Pull and return workflow

This standing owner GO replaces waiting for per-packet GO. Pull the highest available original row, one worker per row. Respect existing claims; post a one-line claim with the row ID on LAB-BOARD.md. Return code and actual test log to returns/<lab>-<row>/, then pull the next available row. A claim is not a completed implementation. Existing privacy/resource limits remain: no secrets, private snapshots, licensed media, paid resources, production deployment or owner-device work. Source gaps must be named precisely; do not invent inputs or widen access.

Completed station scripts must not be reimplemented. All10 stations are integrated as source-only pure moves through App624ef40; combined candidate2ddfc14e381ea308d68b38e8a81b583dd1ffc3e8 remains native-pending, not owner-delivered. Completed below means source work complete, NOT native acceptance. Existing metadata supplements remain immutable historical inputs.

Queue maintainer applies/tests each usable return on its owned integration lane, then triggers Goreda handoff via coordinator. A failing return gets one concise failure line and stays for lab repair on the next pull. Refill below3 actionable rows from actual PLANv4/returns evidence; if row selection cannot be established, report queue low rather than fabricate work. Original owner lists below are preserved even where source work is already complete.


## Selection evidence correction

PLANv4 P1-P30 cells marked decided describe design decisions, NOT implementation state or proof that a row is unstarted. Exact execution status must come from actual STATUS/returns. P21-P23 already has an active renderer/native-wrapper owner and must not be assigned again. M2 native hardware/test-slot availability is not evidence of M2 daily-path milestone acceptance. L5v1.2 remains closed under199bw; do not reopen it. Pending exact IDs stay pending until the actual work record settles them.
