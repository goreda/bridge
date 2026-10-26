PREP-v3r1: CORRECTION + test-source delta. No code iteration; accepted source endpoints unchanged
(contract 768d60ab, decoder 1d019d42, diag 5af5c98c, diff 5e7bb006 - all stand as accepted).
No build/run/adoption.

== CORRECTION (error preserved, not hand-repaired) ==
PREP-v3 (fe186ce0) claimed the UNCHANGED old patches 475b5a54 + c1a3b4ff "apply clean" over decoder
candidate 1d019d42. FALSE in the strict sense, independently confirmed both sides:
- git apply --check --numstat 475b5a54 vs 1d019d42: FAILS ("patch failed ... :268") - hunk context
  carries the old hard-coded .requested emitter region that v3 changed.
- patch(1) -p1 "succeeded" only WITH FUZZ 2 and +13-line offsets on hunks 2-4 (hunk 1 applied at
  offset). My earlier "clean" report came from patch(1)'s fuzz tolerance with -s; that was my
  verification error, recorded here.
Resolution (peer direction followed): the old patches are SEMANTIC LINEAGE ONLY (context-rebased);
the authoritative realignment is the derived machine diff 5e7bb006, whose application to 1d019d42
reproduces 5af5c98c (both sides reconstructed byte-identical). The accepted code is NOT changed back
to satisfy the old patch. Diag-candidate byte identity 5af5c98c is unaffected by this correction
(fuzz application and the derived diff produce the same bytes; peer confirmed).

== TEST-SOURCE DELTA (existing native-hold suite only; prepared, NOT executed) ==
Base suite d84270be4a5395d346c79858b921f56a5f69e3f3795187ac15308bf27bb19a2a ->
candidate 64f0acacb674d02a9af787d6d9192a93ab0002f82129c8f4259bb43a27a5af2b;
machine diff eb84a4b87c168769d77d84b8a8166e7cb74f0811d7048748669433f766b7b6ff
(git apply --check PASS vs exact base; application reproduces the candidate hash).
Content (+77/-4):
- NH6a expectation flips .requested -> .close; NH6a doubles as the atomic-gap chosen-policy witness
  (with requestClose atomic, a flag-only settlement is unreachable by construction - the removal is
  verified by source (single locked block), not by timing).
- NH6c flips cancelledNoMutation(.requested) -> refusedNoMutation(.closed) + arbitration == .none.
- NH6d requested-then-close -> .requested (first-recorded wins). INVARIANT vs pre-adoption code
  (old hard-coded .requested agrees) - not discriminative, retained for regression shape.
- NH6e close-then-requested -> .close. DISCRIMINATIVE (old code fails this).
- NH6f poison+caller -> cancelledNoMutation(.requested) + provider stays poisoned (fresh seek
  refused typed). Outcome label invariant; discriminative in combination with NH6c (poison-only
  -> refused) and the stays-poisoned assertion.
Execution stays HELD until adoption authorization; against CURRENT prod/diag bytes this candidate
suite would fail NH6a/NH6c/NH6e exactly where the semantics flip - expected and documented, not a
regression. NH6b unchanged. No new matrix; all six cases live in the existing targeted suite with
the existing selector.
