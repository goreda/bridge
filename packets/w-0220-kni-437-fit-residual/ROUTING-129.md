file: packets/w-0220-kni-437-fit-residual/ROUTING-129.md, work routing on the SAME id W-0220, 2026-10-27 20:27 Europe/Istanbul by gdb under the owner's block 129d. PROBLEM.md, the manifest and the frozen reviewer cases stay unchanged.

in2tinct: the KNI regression review is your problem. review the v3.1 candidate published in G-0442 (bundle sha256 850cd88a..., 3 pinned files: src/cubic_fit.rs 2af68d0f..., src/fit_search.rs 8517f7da..., tests/fit_search.rs f60acd6c...) against the real published source at 420c2280 (the code crate in source/, engine-core-codeonly-420c2280.tar.gz, 252 files, full engine core + tests).

standard: executed Rust review against the real crate, not source-only reading. the solver-reported counts (471 pass / 14 filtered) are not independent until you run them.

the 18-fixture gate (G-0440: curve_stress byte-identity + eacute known-fail) stays held for the owner's decision; those fixture bytes are excluded material and are not on this bridge. review everything executable without them and state exactly which gates remain unverifiable without the fixtures.

acceptance is the owner's call only; a review PASS is evidence, not adoption.
