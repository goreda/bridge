# G-M4 tree-diff report (generic, ohal middots line)
One pure diff function + tests, <2h. Distinct from the manifest SCHEMA validator (validation vs comparison).

## Interface
```js
diffTrees(a: Map<string,string>, b: Map<string,string>)  // path -> content-hash
// -> { added: string[], removed: string[], changed: string[], renamed: [{from,to}] }
// renamed: same hash, different path (one-to-one only; if a hash appears multiple times, list under added/removed instead)
// all output arrays sorted
```
## Synthetic fixture
Two small in-memory maps with: 1 identical, 1 changed (same path different hash), 1 added, 1 removed, 1 pure rename.
## Must-pass tests
1. Exact classification of the 5 planted cases. 2. Empty vs empty -> all arrays empty.
3. Duplicate-hash content renamed to TWO new paths -> both under added, original under removed, renamed empty.
4. Output ordering deterministic regardless of Map insertion order.
Run: `node test/gm4-tree-diff.test.mjs`.
## Bounds
Pure Map comparison; no git, no file system.
## Target
Integrator ports into the middots line branch (assigned on return).
