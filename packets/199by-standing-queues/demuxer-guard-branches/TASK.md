# in2tinct Q3-Demuxer: missing guard-branch tests only

Standing199by policy-test row, bounded successor test work. Inspect other actual current tests first, add only missing branches. This is a demonstrated hole in the supplied runner, NOT a claim that DemuxerPolicy or its whole suite lacks tests. Do not duplicate whole suites or widen product admission policy.

Existing runner cases using wav with zero video or nil video codec are refused by the earlier container guard. Add direct cases with admitted mp4 container, audio0/other0 and video counts0,2,-1; video1 with nil/unknown codec; muxed mp4 audio1 with nil audio codec; other-stream guard precedence; remote kind with nilURL and exact rejection reason. Guard mutants must compile and then fail the branch tests at runtime; compile failure is not a killed runtime mutant.

Preserve the supplied full current runner and actual AdmissionTable semantics. The current runner has separate decoder/network paths; the new pure branch cases must need no FFmpeg/network. Do not run decoder/network tests under a pure-unit label. Use actual table/SourceDescriptor/module inputs, not reconstructed substitutes; exact missing dependency closure is requested from coordinator and must be named if absent.

Return a test-only delta, exact commands/environment/exits/logs, current source hashes and runtime mutant outcomes, one distinct owned file per return. No product-policy changes, global P-row completion, actual rendering, native or shipping acceptance is asserted. Sources here are baseline inputs, not new output.
