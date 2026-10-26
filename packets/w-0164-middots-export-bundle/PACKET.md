# G-M9 local export bundle builder + verifier (generic, ohal middots line)
Deterministic export format + verifier + tests, <2h. The generic read-only export tool shape (91d); no user data, synthetic entries only.

## Interface
```js
buildBundle(entries) -> string
// entries: Array<{ key: string, value: string }> -> deterministic text bundle:
// header 'BUNDLEv1\n', then entries sorted by key, each: key, byteLength, sha256hex, base64 value, one line per field.
verifyBundle(text) -> { ok: true, entries: [{key, value}], warnings: [] } | { ok: false, reason }
// rules: byte-identical output for the same entry SET regardless of input order;
// verifier re-checks every length+hash; tamper, truncation, bad base64, duplicate key -> typed failure;
// keys/values may contain unicode and newlines (value always base64; key percent-encoded if it contains control chars);
// no entry is dropped, reordered, or normalized (lossless round-trip).
```
## Synthetic fixture
fixtures/entries.json: 5 entry sets (single; 50 mixed; unicode+emoji+newlines; empty value; 1MB value) with expected bundle digests.
## Must-pass tests
1-5. Exact digest per set. 6-9. verify rejects: flipped byte, truncated bundle, bad base64, duplicate key - each typed. 10. Round-trip property over 100 random sets: verify(build(x)) deep-equals sorted x.
Run: `node test/gm9-export-bundle.test.mjs`.
## Bounds
Pure format module; no storage, no file writing, no real browser data; the format and verifier only - wiring to any browser is the integrator's.
## Target
Integrator ports into the middots line branch (assigned on return).
