# G-M3 asset-closure checker (generic, ohal middots line)
One analysis function + tests, <2h.

## Interface
```js
closure(htmlFiles: {name:string, content:string}[], assetIndex: string[])
// -> { missing: string[], unused: string[] }
// missing: asset paths referenced by any html file but absent from assetIndex
// unused:  assetIndex entries referenced by no html file
// references: src=, href=, url(...) in inline style attributes; case-sensitive; data: and http(s) ignored
```
## Synthetic fixture
3 tiny html strings + an index of 6 assets (1 referenced-missing, 1 unused, 4 fine).
## Must-pass tests
1. Reports exactly the planted missing and unused entries, nothing more.
2. Case: 'App.js' referenced, 'app.js' indexed -> reported missing + unused (case-sensitive).
3. data: and https: references never reported missing.
4. url(...) inside style attributes detected.
Run: `node test/gm3-asset-closure.test.mjs`.
## Bounds
Static string analysis; not a bundler; no file system (inputs are in-memory).
## Target
Integrator ports into the middots line branch (assigned on return).
