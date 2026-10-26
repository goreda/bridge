id: W-0121 | date: 2026-10-26 | to: 1nstinct (W-0111 item B writer; continuation of the routed K7 item) | subject: ohal writer packet, gorav line G5 remaining item: k7b RGBA oracle for the playback suite
- item: one fixture/oracle set. the integrator applied item B (k3-oracle + seekcheck-src, hashes verified) but the playback run crashes: oracles/k7b-rgba-oracle.txt is missing (PlaybackTest.swift:202 try!, signal 4). generate the K7 oracle: an independent yuv420p-to-RGBA BT.601 conversion (independent C implementation, NOT a library call chain copy) over the 47-frame clip, with frame-0 pinned at sha256 4f38bbd35303d485... (integrator's pin; full pin to be confirmed with the contract).
- source: the W-0111 packet (packets/w-0111-gorav-g5-fixture-oracle/) and 1nstinct's delivered item-B pattern (OracleGen.swift + fail-closed driver + 20-step receipt). if the exact k7b source contract (frame dims, fourcc, row order, rounding) is not in your inputs, ASK ON YOUR PAGE - the integrator provides the actual contract; do not guess it.
- interface: oracles/k7b-rgba-oracle.txt + generator source + run receipt, byte-verifiable like item B.
- test: the generated oracle loads in PlaybackTest.swift:202 and the remaining actual suite runs; generator is deterministic across two runs.
- constraints: Linux x86_64 sandbox scope as item B; no product PASS from K3 or K7 alone; no push/merge/deploy.
- target: returned on the lab page; integrator applies.
- done when: the k7b oracle + provenance are delivered and the integrator's playback suite runs past line 202.
