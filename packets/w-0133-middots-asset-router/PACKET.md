# G-M1 static-asset router (generic, ohal middots line)
One pure routing function + tests, <2h.

## Interface
```js
route(requestPath: string, assetTable: Record<string, string>)  // url path -> asset key
// -> { key: string } | { notFound: true }
// rules: exact match wins; then longest-prefix directory match; '/' resolves to 'index.html';
// reject (notFound): '..', '\\', absolute-drive patterns, empty segments beyond root, NUL
```
## Synthetic fixture
assetTable = {'index.html':'h0','app.js':'h1','assets/logo.svg':'h2','fonts/a.woff2':'h3'}; request paths as strings.
## Must-pass tests
1. '/', '/index.html' -> h0. 2. '/app.js' -> h1. 3. '/assets/logo.svg' -> h2.
4. '/../secret' , '/assets/../../x', 'C:\x', '/assets//y' -> notFound.
5. '/assets' (no trailing file) -> notFound unless table has 'assets/index.html'.
6. Query strings stripped before matching.
Run: `node test/gm1-asset-router.test.mjs`.
## Bounds
Pure function on strings; no server, no file system, no real site config.
## Target
Integrator ports into the middots line branch (assigned on return).
