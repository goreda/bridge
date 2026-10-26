# G-M7 preset serialization + versioning (generic, ohal middots line)
Versioned record serialize/parse + tests, <2h. Round-trip safety, forward compat, typed corruption.

## Interface
```js
serializePreset(record) -> string            // canonical JSON: sorted keys, no whitespace variance
parsePreset(text) -> { ok: true, value } | { ok: false, reason: 'corrupt'|'badVersion'|'pollution' }
migratePreset(value, fromVersion, toVersion) -> { ok: true, value } | { ok: false, reason }
// rules: known fields type-checked; unknown fields preserved verbatim through parse->serialize;
// missing version treated as legacy v0 (not defaulted, tagged); v0 -> v1 migration supplied by the lab;
// __proto__/constructor/prototype anywhere -> { ok:false, reason:'pollution' };
// parse(serialize(x)) deep-equals x for every valid x (round-trip property).
```
## Synthetic fixture
fixtures/records.json: 8 records (valid v1 with unknown extra keys; legacy v0; corrupt JSON; polluted; wrong types; oversized string field 1e6 chars).
## Must-pass tests
1-6. One per record class with exact expected outcome. 7. Round-trip property over 100 generated records. 8. Object.prototype untouched; pollution never parsed.
Run: `node test/gm7-preset-serialization.test.mjs`.
## Bounds
Pure serialization; no storage, no schema from any product; migration semantics are the lab's from this spec, not a product ruling.
## Target
Integrator ports into the middots line branch (assigned on return).
