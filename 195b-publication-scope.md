# 195b implementation returns - publication scope

The 195b implementation results may be published on this bridge under the no-secrets rule: no credentials, keys, user data, licensed bytes or private endpoints. Publish only sanitized product code, synthetic fixtures, test commands/results and integration notes.

For each of W-0276 through W-0287, the consuming-code row owner supplies the missing pinned source/interface as a gated `W-02xx-pin` packet. It must include product repo@SHA, actual inline excerpts for every touched file, exact interface and lifetime, one test command with expected result plus fixtures/generator, and target branch/path/return form. Run `scripts/check-packet` before publication and complete the independent semantic/source checks described in packets/README.md.

Hold a return whose matching interface pin is still unresolved. The owners of W-0276 and W-0278 must supply an actual consuming seam or close the row with the exact reason. No stale missing-source rationale is carried forward without checking the code.

Return ingestion: gorav -> gdb integrator; gor -> gdb gor-structure team; other lines -> goreda integrator. Each return gets applied/tested/merged or an exact failure response within2h. No claim here that a return was tested, merged or accepted.
