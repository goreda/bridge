# native87 C gate

This is an explicit diagnostic mode of the real gor executable. It opens the
production GorAVPlayerHost NSWindow and uses its actual UI pause, seek and close
methods, then awaits their production tasks. Normal launch is unchanged.

Scope: the gate uses an isolated NSApplication delegate, not normal AppDelegate
startup. It does not start mpv, event taps, camera helpers, installed preferences
or change the default engine. Even when every check is green the receipt is
PARTIAL for normal-AppDelegate lifecycle and display venue. No install or owner
acceptance follows from it.

## Entrypoints

After the ordinary native gor build, ops runs:

```
python3 Tests/NativeGate/run-c.py \
  --gor /absolute/path/to/built/gor \
  --fixture /absolute/path/to/local-av-fixture.mp4 \
  --venue 'ops-observed runner/display description' \
  --output /new/directory/native87-C
```

The underlying product invocation is:

```
gor --gorav-native-gate /absolute/path/to/local-av-fixture.mp4
```

Use a local audio/video fixture with duration greater than 20 seconds, audible
(non-silence) samples, and a valid seek landing at 8 seconds. A short/silent/video-
only fixture is not a valid pause/audio witness. No URL download is performed.

Outputs: `C-runtime.raw.log`, `receipt.json`, and on failure `failure-tail.log`
(last 200 lines). A prior output directory is never overwritten. Exit nonzero
on crash, timeout, a missing required PASS line, or any FAIL line. Raw logs must
be retained alongside the receipt. Run Stage A before this runtime stage.

## Timeout contract

- Whole child process: hard 120 seconds, kills its process group on timeout.
- Initial first-frame anchor: 20 seconds.
- Pause-state acknowledgement: 2 seconds.
- Pause hold: at least 12 seconds, sampled every 100 ms.
- Resume/landing: 10 seconds.
- Clean close: strictly less than 300 ms, measured around awaited teardown.
- The initial 250 ms pause-edge settling interval is excluded from the hold.

These are operational gate bounds, not claims about historical venue bounds.
Engine pin is 2112af0d (Packages/gorav/source-lock.json): a parked seek skips
the frame0 render-order gate (vacuous while quiesced; no 10s stall, no
firstFrameTimeoutMuted), so the parked-seek leg is expected well under the old
10s engine wait. A parked seek is still awaited before resume, deliberately
exposing a timeout rather than bypassing it by issuing concurrent resume. An
in-flight command hang is caught by the process cap and is FAIL, not PASS or
silent scope reduction.

## Stage B executable build (ops, macOS)

A green engine-library compile is not evidence for the b-gate executable.
Build the explicit product and keep the full log as its own artifact:

```
python3 tools/build-with-gorav-provider.py \
  --package-path Packages/gorav -c debug --product b-gate-tests \
  > <output>/b-gate-tests.build.log 2>&1
```

Run from `archive/gor` so the b-gate build shares the gor build's locked,
deployment-target-pinned provider cache. Record the swift-driver version and
the effective flag set (package tools-version/language mode, `-Xcc`/`-Xlinker`
provider flags) in the run receipt. macOS legs only; the executable exits 77
elsewhere. No B PASS is implied by a C check.

## Evidence and remaining work

Per-check JSON lines report actual anchor, time-pos, EOF observations, seek trace,
audio landing admissions, host error/terminal events and awaited teardown time.
C4 reads the engine's observation store; it does not synthesize missing metadata.
Width/height/video-params/dwidth/dheight/fps/drop fields remain KNOWN-OPEN here.

The live RT silence/non-silence/callback/presentation API is wired at engine
2112af0d: C3.real-audio-and-presentation-pause asserts the actual pause
contract from EmbeddedSnapshot counters (presentedFrames and
audioNonSilenceFrames frozen while audioIntentionalSilenceFrames and
audioCallbacks advance), C3.resume-live-counters asserts post-resume growth,
C3.parked-seek-committed requires both seekTrace and seekCommittedCount
witnesses, and C3.close-from-paused reads the typed EmbeddedCloseReport
(reason, measured closeMs, cleanShutdown, pre-close counters). Every counter
is a required witness: a nil field FAILs its check outright, never passes as
a fabricated zero. B1-B3 flagged-E1 entrypoint is the engine lane's
b-gate-tests target (vendored at Packages/gorav/Sources/b-gate-tests, macOS
legs only, exit 77 elsewhere), run separately by ops. No B PASS is implied by
a C check.

Linux validation: Swift parse only (not Darwin typecheck), fail-closed receipt
contract test (`python3 Tests/NativeGate/test_contract.py`). Actual NSWindow,
Metal surface and AudioUnit runtime checks require the native venue. No visual
or scanout inspection was performed during Linux preparation.
