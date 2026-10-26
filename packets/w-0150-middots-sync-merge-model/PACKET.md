# G-M5 sync merge/conflict model (generic, ohal middots line)
Pure 3-way merge model + tests, <2h. No product source; generic versioned-record semantics.

## Interface
```js
mergeState({ base, local, remote })  // plain JSON objects, per top-level field
// -> { merged, conflicts, holds }
// field rules: unchanged-vs-base copies through; one side changed -> that side wins;
// both changed equal -> either; both changed different AND base had the field -> conflict {field, local, remote};
// base lacked the field and sides differ (ancestorless) -> hold {field, local, remote} (NOT a silent pick);
// a field one side deleted vs base -> deletion is a change like any other;
// unknown nested keys on the winning side are preserved verbatim (forward compat);
// __proto__/constructor/prototype keys are rejected with a typed error, never written.
```
## Synthetic fixture
Records of the shape {v:1, fields:{font:{size:12}, layout:{lane:'a'}, customX:{...}}}; fixture matrix in fixtures/cases.json: 9 cases covering win/delete/conflict/hold/unknown-preserve/proto-pollution.
## Must-pass tests
1-8. One per fixture case, exact deep-equal on merged/conflicts/holds. 9. Object.prototype unchanged after every case; no key named __proto__ in any output object.
Run: `node test/gm5-merge-model.test.mjs`.
## Bounds
Pure function on JSON values; no storage, no network, no clocks, no product schema; this models semantics only - it is not the acceptance contract of any product change.
## Target
Integrator ports into the middots line branch (assigned on return).
