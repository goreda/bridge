# W-0261 integrated repair (c8d3e29) - per-changed-site notes (A3 form)

Integrated change: commit c8d3e29e4ad6bc393031aa63c06d181006790a09 on the rebuild
line (parent 63a413082e71ec7d3b15be1756048a2e751e253f). Touches exactly three files,
all packet-public unit files: Sources/race-witness-tests/RaceArms2.swift,
Sources/race-witness-tests/main.swift, Tests/AudioPacingTests/AudioPacingTests.swift.
Zero assertion, message, or interleaving changes; Package.swift untouched.

## Carrier definitions (added)

- RWCell<T> (RaceArms2.swift, shared with main.swift, same target):
  `final class RWCell<T>: @unchecked Sendable { var v: T; init(_ v: T) }`.
  Doc comment in code: "one-shot/typed result carrier synchronized by the EXISTING
  DispatchSemaphore discipline (write -> signal -> wait -> read). Replaces
  captured-var mutation inside Task bodies - no locking added to any witness path,
  every assertion and the timing structure unchanged."
- WaitsBox (AudioPacingTests.swift): `private final class WaitsBox: @unchecked
  Sendable { private var items: [Double]; add(_:); snapshot() }`.
  Doc comment in code: "serial-callback wait recorder; the pump's onWait fires on
  its executor, the test reads after await pump.run() - identical happens-before
  to the captured var it replaces; the expected sequence assert is unchanged."

## Common pattern (all 21 semaphore hand-off sites)

What shared state: a single produced result (PumpStats / Bool ACK / [SourceEvent] /
SeekBarrierOutcome) formerly a captured `var` mutated inside an escaping Task.
Isolation chosen: EXTERNAL ordering, no locking inside the carrier - one writer
(the producer Task), write completes before the existing done-semaphore signals,
the arm thread reads only after the matching .wait(). The semaphore's
release/acquire edge orders every write/read pair; no access path exists outside
this chain (each cell is a function-local let, single Task writer, reads only
post-wait; verified per site).
Why detection semantics are preserved: the concurrent producer, the holds/parks/
handshakes, and the completion signal are untouched (semaphore and Task lines are
context, not hunks); the asserted value remains the producer's own result read at
the same program point; every assertion text and the witness output shape are
byte-identical to baseline.

## RaceArms2.swift - 18 sites (baseline error-extract lines)

:231 statsA (RW31/A), :235 ackA (RW31/A), :270 statsB (RW31/B),
:369 ackA (RW32/A), :377 statsA (RW32/A), :397 ackB (RW32/B), :404 statsB (RW32/B),
:420 ackC (RW32/C), :432 ackD1 + :434 ackD2 (RW32/D - two separate cells, one per
overlapping reset Task), :453 statsE (RW32/E), :457 ackE (RW32/E),
:527 pulled (RW34/A - 7x append inside the Task, then signal), :542 barrier (RW34/A),
:551 pulledB (RW34/B - 3x append inside the Task, then signal), :568 statsC (RW34/C),
:603 statsA (RW35/A), :625 statsB (RW35/B).
Each: captured var -> RWCell; write in the same Task before the same semaphore;
read after the same wait. Frozen asserted outcomes per site are unchanged (see
H-0495 section-6 table).

## main.swift - 6 sites

- RW20 :597/:603 t (live clock) and :606 bad (bad clock): `let t = RWCell(1000.0)`,
  clocks `{ t.v }` (LIVE read per clock call - not a snapshot); `bad.v = true`
  precedes the l3 append that must observe it; `t.v += 1` follows all ledger use.
  Shared state: the clock value formerly captured by @Sendable closures.
  Isolation: THREAD CONFINEMENT - TimingLedger invokes clock() only synchronously
  (init, and append while holding its own NSLock); TimingLedger has no internal
  Task/queue/thread; the ledgers are arm-locals. Every access to t.v/bad.v is on
  the arm thread in program order. No concurrency exists in the actual call graph.
  Detection preserved: same clock values at the same call points; the 606
  non-finite-stamp witness keeps its live-cell shape (the snapshot shape is the
  one the lab mirror proved turns that check red; the integrated form is live).
- RW25 :748 statsBox, :763 statsBox2, :786 statsBox3: common semaphore hand-off
  pattern above (write in Task before signal; read after wait; force-unwrap at
  the same program point as baseline).

## AudioPacingTests.swift - 1 site

- test09_stalledCounterWaitsNotSubstitutes: captured `var waits: [Double]` ->
  WaitsBox; onWait records via add(); the test reads snapshot() after
  `await pump.run()` returns. Shared state: the recorded wait sequence. Isolation:
  serial pump executor callback + read only after run() completes (the same
  ordering the captured var relied on). Detection preserved: the asserted expected
  sequence [1.0, 1.0, 0.5] and its load-bearing ordering are unchanged; per-test
  XCTAssert count unchanged (121 total, non-decreasing everywhere).

## Bounds

Analytical conclusion limited to the examined call graph, not an empirical
race-freedom proof: no TSan or equivalent run exists on either byte line.
Mac/Darwin native unrun. Lab candidate uses a different carrier (NSLock-guarded
RWResultBox); this note describes the INTEGRATED bytes only.
