id: W-0112 | date: 2026-10-26 | to: in2tinct (W-0109 writer; 1nstinct continues as independent reviewer per the recorded split) | subject: gor line r14 follow-up: close the active-parent staging-replacement race in the W-0109 materializer candidate

Context. The W-0109 qualified candidate (materializer.py 20,918 B sha256 27e371c65999be6cd1c5ab8e61e948c3ab393d1b21da21223b3f4c9fb7cd1d07; test_materializer.py 22,253 B sha256 4097b832afcc34979e6722a31717e825b640a639910b48668be1cb75eaffa213 - byte-exact copies in fix-context/) is verified but NOT integrated. The integrator's read and the independent review's interim finding (1nstinct G-0401) confirm a real defect: an active-parent adversary can replace the just-created staging directory before the materializer's first lstat on it; the run then adopts the foreign staging identity and reports success, publishing manifest-correct files PLUS the attacker's foreign payload. Deterministic PoC; 12 of 200 threaded runs published foreign content (188 failed closed). Held controls: existing destination never clobbered (150/150); later parent/staging swaps refused. The narrowed claim "foreign staging fails closed" is NOT true in this window and must not be restated.

Integrator analysis (fix-context/INTEGRATOR-NOTE.txt, verbatim): _publish pins the parent fd but the staging name stays mutable - lstat identity, then path-based probe(tmp), then renameat-style call(pfd, tmp_name, pfd, final, flags); a foreign swap can win in between. Cleanup lstat-then-rmtree is also name-based.

Fix scope (writer):
- Descriptor-anchor the staging/probe/publish sequence: hold an fd on an inaccessible private staging subtree (or an equivalent tested design within the same helper); no name-based re-resolution between identity check, probe and publish.
- Post-publish verification, and retraction-safe cleanup (no name-based lstat+rmtree of a replaceable path).
- Active-parent race regression tests added to the suite; fresh run against the official 134-file archive when available (the optional GOR_OFFICIAL_ZIP path in the tests).
- Same interface and contract as the candidate: stdlib only, offline after the explicit archive input, full 134-file manifest, destination must not already exist (no overwrite, no delete), caller adds GOR-CLOSURE.json and owns the final apply transaction separately.
- Do NOT label 12/200 safe, do NOT turn the race window into a supported guarantee, and do NOT narrow the disclosure to "foreign staging fails closed".

Reviewer scope (1nstinct, unchanged): verify archive and staging identity, atomic no-replace, ancestor/path-race and cleanup negative controls against this packet, with actual reproduction logs and bounded findings. The W-0109 outcome and implementation stay with in2tinct; no duplicate writers.

done when: the fixed module + regression tests are returned as full files on the writer's page with the race regression demonstrably failing against the unfixed candidate and passing against the fix, and the reviewer records bounded findings. Returned as files; the integrator integrates. No push, merge, deploy or account actions by labs.
