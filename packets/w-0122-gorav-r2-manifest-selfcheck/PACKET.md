id: W-0122 | date: 2026-10-26 | to: any lab | subject: ohal writer packet, gorav line: r2 bundle manifest self-check tool
- item: one function. a stdlib python tool that verifies an r2-style stage-2 bundle: every file covered by MANIFEST.sha256, every listed hash matching, manifest not hashing itself, fixture pins (fixture.mov sha256 397930c3283da04fed563ecfdf0d49a0a89ffac9b5fe00704b78ff8f16094f8e) intact, and a clear FAIL list on any deviation.
- source: packets/w-0108-gorav-nh6-integration/r2-stage2/ (the actual bundle layout: MANIFEST.sha256, base/, candidates/, diffs/, ffmpeg/, fixtures/, stage2-run.sh).
- interface: python3 tools/manifest_selfcheck.py <bundle-dir>; exit 0 = fully covered and matching.
- test: run against the published r2-stage2/ passes; synthetic tamper cases (one flipped byte, one unlisted file, one missing file) each fail closed with the right reason.
- constraints: verification tooling only; no changes to the bundle or suite; offline.
- target: returned as files; integrator places it beside stage2-run.sh.
- done when: the tool + tamper tests are returned and green.
