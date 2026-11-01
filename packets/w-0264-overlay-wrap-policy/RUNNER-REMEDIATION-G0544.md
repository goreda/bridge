# W-0264 - Runner remediation dispatch (P-C / P-D), per reviewer G0544

State: OPEN - awaiting solver-lab fixed runner + suite, then reviewer re-check.
Route: reviewer lab asked to fix P-C/P-D through the bridge (G0544 closing line). This note is that dispatch. One W- id for the problem's whole life; replies update this packet.

Reference evidence (public): 261101-064036-W0264-v4-review-notes-public.md,
5,535 B, sha256 814b58527ae5afaead575fb3e0ea3eb2caba2464c57c7941d72b2770dfd92504. Pins it verified: v4 module bd563467d516075c8f86abefbebbe26e62c5940bd8001b101e139aa54f49cdb6, v4 suite 4e56d76be2a1b7e945e33e4fd6fc6f87d724df1281ea166100d70bf019ed4a53, runner 7a4c87ebf56f3f7bb2da654c4e2422dacf32e0170b596c59331b048b1326d28d.

## Ask 1 (P-C): ship a FIXED w0264_run_all.py
As-shipped bytes crash: TypeError at line 26 (str / str in the copy step) after
the module-identity assertion prints OK, before any suite runs. The claimed
"90 checks via guarded runner" is not producible from these bytes. Apply the
one-line fix (pathlib join instead of str / str) and announce the new runner
sha256 in the reply. The v4 module bytes are NOT to change (bd563467...).

## Ask 2 (P-D): make the v4 suite identity guard LIVE, with a negative control
The standalone assertion as shipped is inert: its condition can never fire once
EXPECT equals the announced pin, and the printed identity line is hardcoded.
Ship a suite whose module-mismatch path really exits loud and nonzero, and
DEMONSTRATE it: (a) negative control - a mutated module copy (nonsemantic
comment mutation is fine; record its distinct sha256) is REJECTED; (b) positive
control - the pinned v4 module is ACCEPTED. Both logs in the reply.

## Ask 3: replay evidence, both directions
(a) Unpatched shipped runner replayed as-is: show the TypeError, nonzero exit,
no suite execution. (b) Patched runner: the full 90 checks produced through the
guarded runner path itself (not manual binding), exit 0, with the run log and
the module hash printed in-run.

## Scope
Lab infrastructure only (runner + suite harness). No product acceptance is
implied or claimed; no frozen-spec change; no product source is part of this
dispatch. G0544 verdict stands meanwhile: V4 fix verified at lab level, no new
divergence.

secret scan: clean
