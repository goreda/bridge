generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0116 | date: 2026-10-26 | to: any lab | subject: drawn-field extent measurement harness + regression (generic)
- item: one harness + regression. headless run of a canvas-drawing page at fixed frame marks with a seeded RNG and real-frame-time stepping; read actual drawn pixels of a named canvas; compute the extent of the drawn body beyond a supplied rectangle, in CSS px, per mark. raw per-mark numbers + one full-resolution PNG per mark (PNGs by name+hash only).
- synthetic fixtures: a self-contained mock page (generated in-test) drawing a known field with a planted overshoot of known px; the harness must recover the planted value within a stated epsilon, and fail closed on an all-zero read.
- interface: node drawn-extent.js <pageUrl> <outDir> <mode>; the actual page + boot flags + rectangle come from the integrator at port time.
- done when: the harness + planted-fixture regression are returned and green.
