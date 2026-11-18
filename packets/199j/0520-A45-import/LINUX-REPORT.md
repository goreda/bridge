# 199j A45 adapted independent replay

Engineering validation only. Input is the privacy-adapted published bundle, not the original archive. No refs changed.

## Privacy neutralization scope

Selected fixed production declarations DZC, DZCWriter, DZCFile and DepthQuant extracted from the adapted full ThreeD.swift exactly match the corresponding declarations in the bundle's inline fixed executable excerpt (boundary whitespace stripped only). Exact declaration hashes and comparisons are in DECLARATION-EQUALITY.json. Both adapted full-file variants were used as the source of verbatim extraction and executed with the supplied runner/config plus independent direct compiler/binary runs.

There is **no full-file before/after token proof; the originals deliberately withheld for privacy**. The parent reports that Ops already checked the b603 production statements against the real repository with string-aware comment stripping. That is Ops' verification, not an independent check performed in this replay. No removed/private lines are repeated here, and no complete full-file source is included in this evidence packet.

## Main results

Swift6.0.3 Linux, explicit -Onone and -O. All legs compile0. Baseline traps-4, fixed exits0 with OK, compiling production mutant bypassing the new UInt64-to-Int offset guard traps-4. Same outcome in both modes. The source patch applies and reproduces adapted fixed bytes exactly after only absolute temporary file headers are normalized to a/ and b/ paths.

Adapted full-source SHA256 baseline9e1bb60fa5f6ca7dea4f8cda8c8e1c0876d73ce8e7fafadd6dfde8f3732ebf8c; fixedcab7c5e123f3deaea297441b8265a09fe2e926ad9071cdf673a7f2d44e439b4c; mutant46c9b5cd03539aca3a294c9fc78a49b772af4269017546ac872a76d3c7d08c87.

The original runner process exits0 on ALL four baseline/fixed legs, even the semantic-4 traps. Parsed compile_exit and semantic_exit, and direct child exit statuses, are the acceptance evidence. See RUNNER-RESULTS.json and raw logs.

## Remaining boundary fix requests, both modes

1. An index offset exactly Int.max passes the new v<=Int.max check, then traps-4 on offset+8 in layout's bounds predicate. Request subtraction-based bounds or checked addition, not only representability of the offset itself.
2. width=UInt32.max, height=UInt32.max trap-4 in the new UInt64(width)*UInt64(height)*2 expression. The first product fits UInt64 but the final multiply by2 does not. Request reporting-overflow checks or prechecked division bounds for every product.
3. startFrame=UInt64.max is admitted by DZCFile with an ordinary small container; pts(0) then traps-4 at conversion to Int. Request validate frame origin and frame-index arithmetic before conversion/addition, including index(atOrAfter:) time conversion.
4. For70000x70000 dimensions, planeBytes returns0 and scanValid accepts an empty decompressed record with CRC0 as one valid frame. This is a semantic sentinel gap, not just a trap: invalid dimensions should fail closed rather than become a valid zero-byte image. The supplied GREEN test only requires scanValid nonnil for this case and does not reject that counted frame.

Ordinary2x2 container remains admitted and an identity decompressor returns four16-bit words. That control is not a real LZFSE decoding proof. One initial extra probe had an invalid duplicate Swift variable declaration and failed compilation; it was corrected before the reported boundary results, and no compile failure is called semantic RED.

## Limits

Main and extra tests compile selected verbatim declarations, fixture support and supplied or independent test mains. Full native ThreeD module, real Compression/LZFSE codec, Metal, native depth pipeline and UI are NOT_RUN. Compression branches are unavailable on Linux, and an explicit identity/empty decompressor is used only in named parser tests. Native48-frame/global-timeline evidence from other tasks is not imported as proof for this parser patch.

Raw argv/logs, extracted production declarations, normalized patch, exact configs, parsed runner results, per-probe mains/results and declaration equality records are included. Full adapted source paths remain private and were not packaged. This is not blanket malformed-container acceptance; the remaining crashes require follow-up fixes.
