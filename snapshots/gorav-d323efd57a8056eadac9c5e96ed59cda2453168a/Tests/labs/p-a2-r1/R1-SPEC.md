# P-A2-R1: enqueue-generation adapter regression

Separate tagged package built on P-A2. Original source, protocol, tests, fixtures,
README and evidence are byte-for-byte unchanged. BASE-SHA256SUMS is the original
manifest renamed; GNU sha256sum -c checks its original payload. New files add an
adapter, five adapter tests, this spec, a verifier and R1Evidence. No private
source, accounts, devices, media, fonts or third-party code are used.

## Contract

EnqueueGenerationAdapter owns its AudioMasterClock. enqueue(videoPTS:) captures
clock.generation in an immutable EnqueuedVideoFrame. Clients retain that value
alongside decoded bytes. decide(frame:hostTime:) passes the stored generation,
never the current generation. Seek and reset invalidate old generations. The
packet's AudioMasterScheduler protocol and existing implementation are unchanged.
The adapter also conforms to it for compatibility.

PTS-only limits remain: protocol decide(videoPTS:hostTime:) cannot distinguish an
unseen old frame from a fresh frame with identical PTS. The compatibility method
does not claim otherwise. Use the frame-token method or flush all old queues at
seek. Retain tokens from the same adapter instance; cross-instance mixing is not
supported. Serial calls, finite valid timeline inputs, and no UInt64 generation
reuse while old frames survive are required. No physical playback claim is made.

## Tests

Five added named XCTest cases prove:

- An unseen old frame and fresh frame have identical PTS and different generation;
  old drops, new presents, and repeated old decisions cannot relabel it.
- A waiting frame drops after seek while a fresh identical-PTS frame presents.
- Reset invalidates a queued token.
- The original protocol remains usable and its identity ambiguity is explicit.
- A full 600001-tick simulation drives the adapter through the saved five-seek
  fixture, 10 ms audio updates with [-2,0,2,0] ms jitter, and 40 ms video cadence.
  Frames are actually enqueued ahead of decision and retained while waiting.

At each seek the suite retains the pending video token, a distinct future probe,
and an unseen token whose PTS equals the seek target. Every retained stale token
is tested at the seek time and at an otherwise-present clock time. Ninety stale
checks pass across five seeks. Immediate-before, immediate-after and +1 ms seek
samples, generation values and every presented-frame offset are recorded.
The fresh frame presentation probe at each seek is not counted twice in the
cadence sample count.

## Measured result

13 XCTest tests (8 unchanged + 5 new), zero failures on Swift 6.0.3 Linux x86_64.
The adapter run presents 15000 frames, zero timing drops, maximum absolute offset
0.0010000000000616183 seconds. Six segment drifts, measured from first/last samples:
0, 0.0009999999999763531, 0.0009999999999195097, 0,
0.0009999999999763531, 0.0009999999999195097 seconds.
All five seeks land exactly on their target. Complete samples and measured
summary are in R1Evidence. A second run produces a byte-identical adapter trace.
The initial compile log records corrected Swift decimal-literal syntax, not a
remaining behavioral failure. The final test log is authoritative for this run.

## Reproduce and verify

```sh
export LC_ALL=C
mkdir -p R1Evidence
R1_EVIDENCE_DIR="$PWD/R1Evidence" swift test -j 1
python3 tools/verify_r1.py
python3 tools/verify_evidence.py
sha256sum -c BASE-SHA256SUMS
sha256sum -c SHA256SUMS
python3 tools/scan.py
```

No downloads are needed once Swift is available. The archive excludes toolchain
and build cache. SHA256SUMS covers all payload files except itself; the archive
SHA-256 delivered separately covers the manifest too. Re-running tests overwrites
the R1 trace only if R1_EVIDENCE_DIR is set; saving a new log changes its digest.

secret scan: clean

Bounded pattern scan plus source/fixture inspection found no credentials or user
data. This does not assert detection of every possible secret encoding.
No remaining packet implementation blocker. Adoption still requires routing
queued frames through the token API, not treating PTS-only calls as identity-safe.
