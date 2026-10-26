# G-M2 cache-token linker (generic, ohal middots line)
One HTML rewrite function + tests, <2h. Generator-side; NOT the schema validator (separate owned item).

## Interface
```js
retoken(html: string, tokenMap: Record<string, string>)  // asset path -> token
// -> html string with src/href="PATH" rewritten to src/href="PATH?v=TOKEN"
// ONLY paths present in tokenMap; idempotent (already-tokened URLs untouched);
// external URLs (http(s)://, protocol-relative), data:, mailto:, #anchors untouched
```
## Synthetic fixture
Small inline HTML string with 6 references: local js, local css, local svg, external https, data: image, anchor link. tokenMap covers the three locals.
## Must-pass tests
1. The 3 locals gain ?v=<token>. 2. External/data/anchor unchanged byte-for-byte.
3. Running retoken twice yields identical output (idempotent).
4. A path NOT in tokenMap stays untouched. 5. Single- and double-quoted attributes both handled.
Run: `node test/gm2-cache-token-linker.test.mjs`.
## Bounds
String-level rewrite on well-formed attributes; not a full HTML parser; no network.
## Target
Integrator ports into the middots line branch (assigned on return).
