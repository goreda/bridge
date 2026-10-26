# CandidateProxy design assembly policy

This is separate from strict verified .notdef evidence, not a weaker witness.
Source .notdef identity is UNKNOWN. It does not detect unsupported characters.

Explicit main-manifest grammar (four tokens, single occurrence):

```
notdef_proxy legacy-largest-repeat-proxy SELECTED_SHA256 0xSELECTED_CP
```

It is mutually exclusive with `notdef evidence` and `capture_manifest`.
No requested_unsupported or witness records are synthesized. Strict v2 verified
blank/repeated path is unchanged. With no candidate and no verified record the
engine refuses, never silently emits an empty glyph.

The manifest producer automatically scans single-codepoint source tiles once.
Group by exact source-byte SHA256. Consider repeat groups of size >=2 (not the old
>=3 threshold). Select the unique largest group. Ties between different SHA256
values refuse `AmbiguousProxySelection`; never choose first or random. Within one
identical-byte group choose the lowest numeric codepoint. Emit the SHA and CP in
the policy row. Every original glyph row and cmap mapping stays in the manifest,
including every alias in the selected group. The engine verifies this explicit
selection against bounded source-byte reads, then binds it to the stage1 source
pin. Candidate membership is not inferred from glyph shapes or transformed pixels.

After normal glyph processing and spacing solver completion, before assembly,
copy the selected generated outline AND its solver LSB/RSB/advance to gid0. Do not
refit or rescale it. The existing immutable run K governs both copies. Empty rings,
missing generated glyph, missing solver metric or nonfinite metric refuses
CandidateProxyNoInkOrInvalidMetric (or the narrower missing input error). An empty
source is not VerifiedBlank. Post-pass operates afterward with the existing
notdef scope rules; no post-offset overlap guard is added.

Receipt names `CandidateProxy`, `policy=candidate-proxy`, `identity_claim=unverified`,
`source_notdef_identity=UNKNOWN`, `excluded_cp_count=0`, candidate count, selection
rule, selected CP, original source SHA256, generated glyph reference and generated
outline SHA256, plus `advance_basis=source-solver-hmtx`. The generated outline hash
uses stable big-endian binary64 coordinate bits, ring/span counts and span tags.
The final pre-publish gid0 CFF readback gets its own canonical outline SHA receipt;
this is not a font identity proof. Full source cp/name/hash snapshot is bound to
all stage1 pins and its snapshot SHA is receipted. Source paths must canonicalize
under rc.capture_dir; input and remaining aggregate budget cap reads before allocation.

Synthetic unit coverage: repeat2 accepted, distinct-SHA max tie refused, source pin
and selected CP mismatch refused, empty source refused. A synthetic220-alias font
retains220 cmap mappings and has identical gid0/source outline, advance and LSB after
native encode/readback. Strict v2 tests continue unchanged. No real Marq/Paul export
was run; this design choice is not evidence of their original font's gid0 identity.
