# G-T5 streaming partial-text assembler (generic, ohal transcribe line)
Pure assembler for interleaved partial transcript segments + tests, <2h.

## Interface
```js
assemble(events) -> { committed, pending }
// events: ordered stream of { seq: int, kind: 'partial'|'final', text: string, rev?: int }
// rules: 'final' at seq N commits the longest stable prefix and discards earlier partials for that range;
// a later 'partial' may revise only uncommitted tail text (rev monotonic per seq; stale rev ignored);
// overlapping duplicate words at a commit boundary are deduped (suffix/prefix overlap >= 1 word);
// out-of-order seq arrival is buffered; gaps never fabricate text;
// committed is append-only across the whole stream (never rewritten, never shrunk).
```
## Synthetic fixture
fixtures/streams.json: 7 streams (clean in-order; revisions; boundary overlap duplicates; out-of-order; gap then fill; empty partials; mixed unicode + whitespace runs) with expected committed/pending.
## Must-pass tests
1-7. One per stream, exact expected output. 8. Property over 300 random streams: committed is append-only; every final's text appears in committed exactly once in order; no fabricated tokens.
Run: `node test/gt5-partial-assembler.test.mjs`.
## Bounds
Pure text model; no audio, no server, no timing; proves assembler semantics only - not any upload or server behavior.
## Target
Integrator ports into the transcribe line branch (assigned on return).
