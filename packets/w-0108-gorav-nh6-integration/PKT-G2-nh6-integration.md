PKT-G2 (block 86, gorav integrator line): NH6 receipt-taxonomy candidate integration onto ohal/gorav.
Scope: written-work landing prep within the existing review done-when. NO semantic adoption beyond
the reviewed candidate; NO main merge/deploy; G3 fault-retention ruling NOT touched.

BASE: ohal/gorav @b3a2c4d (trunk c5f06bd + S5 r1, fresh GREEN: comp suite ALL_CHECKS_PASS,
log 831580d5, this packet's sibling evidence).
STAGE 1 (prod candidate compile - closes peer open limit "standalone prod compile"):
- Sources/GorAVNativeProbeKit/GorAVSeekContract.swift  <- contract candidate 768d60ab98d5bcc236a38b7e92cd85d2be2dade495f6a4dee25271a6bbda8db1
- Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift <- prod decoder candidate 1d019d42871feee9085dff0b72a4a3134e787239dd61d5495c8b4154e816194e
- Verify sha256 at both paths; fresh swiftc module chain compile (commands pattern:
  build-commands.txt (in this packet dir)); existing Linux suites build+run green on the candidate tree.
- Label: source-accepted candidate + compile evidence. NOT production acceptance, NOT native proof.
STAGE 2 (test-only seam, clearly separated):
- native-hold-tests/ suite v2 9563d4e019ac71db8becda9308230ac73be02784acae5a4670d1d4604e2c8fc8
  at Sources/native-hold-tests/main.swift (new test target dir, package wiring optional for Linux
  direct-swiftc runs) + diag overlay 5af5c98ce92d3ebdc1220be606efaff185247cf6db2c3794d5edfddb5f35675c
  applied ONLY in the test build tree (never replacing the module source in a product build).
- Test: explicit selector NH6 (cases a-f), external deadline, zero gate-timeout lines required;
  expected 41/0 per receipt abe72f7e2e47ce84fb5648e8f8b9f6a9e6648e2a762cd8b3660798d5a8f269ed.
CARRIED LIMITS (must appear in PR body): resumePolicy public but unasserted; NH6c catch-all vs
NH6f typed .closed; atomic gap-absence source-only; six held pre-entry vs NH6b recovery seek;
one partially-bound writer Linux diagnostic; Mac/RT open.
SOURCE ARTIFACTS: this packet dir (contract-candidate.swift, decoder-candidate.swift,
diag-candidate.swift, suite-candidate-v2.swift, diffs 391eadea/91958ea5/5e7bb006/46228fb2,
PREP-v3r1-CORRECTION.md 4b8b4428).
DONE-WHEN: stage-1 compile green + existing suites green; stage-2 NH6 41/0 zero gate-timeout;
PR body carries the carried-limits list verbatim.
