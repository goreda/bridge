id: W-0123 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, gorav line: gate-timeout negative-control test group for the stage-2 seam
- item: one test group. the stage-2 acceptance includes ZERO gate-timeout lines in the 41-check run. add a negative-control group to the test-only seam: (a) a scan of the suite log that fails on any gate-timeout line, (b) a synthetic stall case proving the scan actually catches an injected timeout line, (c) the receipt field for timeout-count.
- source: packets/w-0108-gorav-nh6-integration/r2-stage2/ (stage2-run.sh, candidates/, verification-fresh-41-0.log as the reference log shape).
- interface: extend the seam's runner: stage2-run.sh --check-timeouts (additive flag; default behavior unchanged).
- test: the reference log passes; an injected 'gate-timeout' line fails; the count lands in the receipt JSON.
- constraints: test seam only, no production paths (LAB-SCOPE: stage 2 only; stage 1 is local VDV4, retention tests VDV8).
- target: returned as files; integrator applies to the seam.
- done when: the negative group is returned and demonstrably catches the injected case.
