PKT-G5 (lab packet; owner: lab pickup QMX via bridge; integrator-qualified expectations)
BASE: ohal/gorav @f937ee76 (PR1 head; tree identical for these suites to b3a2c4d).
TASK: close the 6 fixture-gapped suites. The integrator sweep (2026-10-26, Linux, direct
gcc/swiftc per build-g1.sh) established the matrix below; the 6 RED suites fail ONLY on missing
kit content, not code. Supply or generate the missing files, re-run, pin logs.
MISSING KIT CONTENT (none reachable in repo fixtures/, card720 payload, or s5 kits):
- oracles/k3-oracle.txt  -> blocks seek-test, coexist-test, isolation-test, trace-dump
  (suites read $GORAV_KIT/oracles/k3-oracle.txt via try!; SIGILL = swift fatalError on missing file)
- fixtures/seekcheck-src.mp4 -> blocks real-seek-tests ($GORAV_KIT/fixtures/seekcheck-src.mp4)
- gorav-first-frame: REFUSE openSnapshot providerFailed(code: -21) - investigate what snapshot
  input it expects; not a plain missing-file path.
KNOWN-GOOD KIT for the rest: GORAV_KIT=/tmp/instinct-repo/projects/gorav/card720/v6/source/payload
(has fixtures/fixture-k3.mp4 + fixture-k4.wav). Repo fixtures/ has the 3 mov files;
GORAV_CANONICAL/GORAV_OFFSET100 point there.
CONVENTIONS: seek-ring-reset-tests compiles WITHOUT -parse-as-library (top-level code).
audio-seek-tests/audio-baseline-tests are DESIGN-SKIP unless GORAV_AUDIO_SEEK_FILE /
GORAV_AUDIO_BASELINE_FILE+GORAV_AUDIO_EXPECTED_BYTES are provided (NOT_RUN is correct behavior).
INTEGRATOR MATRIX (base b3a2c4d, exit 0 all): seek-composition ALL_CHECKS_PASS; refusal-tests bad=0;
audio-refusal bad=0 (kit); video-refusal bad=0 (kit); core-seek 16/0; seek-pacing; seek-contract 61/0;
k9-adversarial PASS (12 run, 2 mac-deferred); audio-test K9_RING_CONCURRENCY_PASS (kit);
seek-ring-reset ALL_CHECKS_PASS; timing-ledger 114/0.
DONE-WHEN: 6 suites exit 0 with real (not fabricated) kit content; if an oracle/src file must be
GENERATED, the generator + provenance accompany the log; logs + object hashes pinned;
claims labeled Linux-sandbox.
