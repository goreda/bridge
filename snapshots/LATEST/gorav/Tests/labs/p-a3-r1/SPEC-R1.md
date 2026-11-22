# P-A3-R1 Specification: configuration validation and metadata isolation

Packet: P-A3-R1 | lab-a (goreda/bridge INBOX-1NSTINCT.md, commit
d6fe617605a7e0743ebd060e306953b380354c8d): "separate-instance/cross-parse
metadata regression and nonfinite safe-area/PlayRes tests; fail explicitly
rather than claiming finite boxes from unchecked configuration."

This package layers on the unchanged P-A3 package. The original is vendored
byte-identical under `Vendor/P-A3-SubtitleLayout/` and hash-pinned: its
files verify against the corrected delivered `MANIFEST.sha256` with GNU
`sha256sum -c` (see VERIFY-LOG.txt). The only difference from the first
P-A3 delivery is the manifest file itself: the hash values are unchanged,
the separator format was fixed so `sha256sum -c` can read it. All code,
fixtures, docs and hashes of the original are untouched.

## Added public surface (new module SubtitleLayoutStrict)

```swift
public enum SubtitleConfigError: Error, Equatable, Sendable {
    case nonFiniteCellSize(width: Double, height: Double)
    case nonPositiveCellSize(width: Double, height: Double)
    case nonFiniteSafeAreaFraction(Double)
    case outOfRangeSafeAreaFraction(Double)
    case nonFinitePlayRes(rawX: String?, rawY: String?)
    case nonPositivePlayRes(rawX: String?, rawY: String?)
}
public final class StrictSubtitleLayout: SubtitleLayout {
    public init(cellWidth: Double = 10, cellHeight: Double = 20, safeAreaFraction: Double = 0.05) throws
    // parse/active/layout per the P-A3 contract, delegating to the P-A3 engine
}
```

## Fail-explicit rules

- Cell size must be finite and > 0, checked at init.
- Safe-area fraction must be finite and in [0, 0.5), checked at init
  (0.5 leaves an empty safe area; negative or >= 0.5 is rejected).
- ASS PlayResX/PlayResY header lines, when present, must parse to finite
  positive numbers. "nan", "inf", non-numeric text throw
  `nonFinitePlayRes` with the raw header text; zero or negative values
  throw `nonPositivePlayRes`. An absent header remains valid (scale 1).
- SRT parsing does not perform PlayRes validation (no such header exists).

## Base-engine contrast (documented, pinned by test)

The P-A3 engine treats a nonfinite PlayRes as absent and silently falls
back to scale 1; its init does not validate cell/safe-area inputs. That is
exactly the "unchecked configuration" gap P-A3-R1 addresses:
StrictSubtitleLayout throws named errors before any box is produced. The
test `testBaseEngineSilentlyFallsBackOnNonfinitePlayRes` pins the base
behavior so the contrast stays visible.

## Metadata isolation rules (inherited from P-A3, pinned by regression tests)

- Anchor/PlayRes metadata applies only to the exact cue array returned by
  the instance's most recent `parse` call (value equality on `[Cue]`).
- Cue arrays from an earlier parse on the same instance, from another
  instance, or built by hand lay out with documented defaults:
  bottom-center anchor, no PlayRes scaling.
- Known limit (value-type identity): two different parses that produce
  value-identical cue arrays cannot be distinguished, so metadata of the
  latest parse applies to either. This mirrors P-A2-R1's PTS-only limit
  style: equality on values, not object identity. No protocol change was
  made to work around it.

## Fixtures

The six P-A3 fixtures are byte-identical copies (verified, see
VERIFY-LOG.txt). Two generated variants of basic.ass are added:
- `nonfinite-playres.ass`: `PlayResX: nan`
- `nonpositive-playres.ass`: `PlayResX: 0`

Expected values: EXPECTED-R1.md.
