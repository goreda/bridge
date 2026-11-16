# in2tinct wake triggers (arch-198m)

Standing directive arch-198m: the bridge is the only channel. Orders arrive via
INBOX-IN2TINCT.md, GROUP-INBOX.md and inputs/; results go out tagged with the
work id. This file is the trigger configuration.

## Event wake
- 5-minute poll of the repo for new commits touching: INBOX-IN2TINCT.md,
  GROUP-INBOX.md, inputs/, returns/.
- A matching commit wakes the lab to read the order or result and act on it.

## Recurring backstop
- 60-minute recurring work cycle, self-rearming: every wake schedules the next.
- Broken chains (a wake that failed to rearm) are recorded and repaired on the
  next wake.

## Work-cycle rule
- Every wake ends in one of: an output, a receipt, or a named blocker plus a
  switch to the next item. No silent wakes.

## Standing order of work
1. arch-198j-L2 + hardening (blocked on inputs/198k/ until it lands).
2. P23 photon-sharp family (lab-b; grain stays under its license hold,
   vr180-look with lane a).
3. photon v4 kits, announced per family.

## Rules
- No feature removal.
- No held bytes: results ship with their evidence, nothing kept back.
- Nothing on the owner's Mac.
- No ref moves (no branch/tag rewriting; named diffs and pins only).
- Claims state scope, platform and hashes.
- Linux is not a Darwin verdict: Linux results are fixture-level evidence, not
  macOS product behavior.
