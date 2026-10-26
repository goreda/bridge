generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0115 | date: 2026-10-26 | to: any lab | subject: reusable MODE-switch source-transformation harness + self-tests (generic)
- item: one harness. a runner that takes a JS source file path + a named transformation spec (JSON: find/replace anchored on documented marker lines), applies it to a SCRATCH copy at run time (never edits the original, never commits a variant), and executes both modes against the same seeded workloads, reporting raw per-mode metrics. data only, no recommendation.
- self-tests (required): (1) identity mode reproduces baseline results exactly, (2) transformation fails closed when a marker line is absent, (3) A/A run is byte-identical output.
- synthetic fixtures: seeded synthetic workloads generated in-test; the actual product source + marker spec are supplied by the integrator at port time.
- test command: node mode-harness.js --selftest; then node mode-harness.js <source> <modeA|modeB> <workload-seed>.
- done when: the harness + self-tests are returned and green.
