# G-M8 key-namespace guard (generic, ohal middots line)
Pure key classifier + tests, <2h. Decides which storage-key class owns what; generic naming spec, no product source.

## Interface
```js
classifyKey(key, spec) -> { class: 'draft'|'cache'|'protectedPreset'|'protectedWriting'|'foreign', scope: string|null }
// spec: ordered list of { prefix: string, class, scope?: string } - first match wins; no match -> foreign.
// wipeAllowed(key, spec, event) -> boolean
// event: 'syncError'|'authInvalid'|'ordinarySignOut'|'explicitDeviceClear'|'remoteProfileWipe'
// rules: protectedPreset/protectedWriting are NEVER wipe-allowed for any event (incl. explicit clear);
// draft/cache wipe-allowed ONLY on explicitDeviceClear; foreign NEVER wipe-allowed (unknown = keep);
// a key carrying scope 'A' classified under a spec for scope 'B' -> class 'foreign' (cross-scope leak guard).
```
## Synthetic fixture
fixtures/keys.json: 24 keys across all classes incl. look-alike prefixes ('app-draft' vs 'app-drafts'), empty key, NUL byte, unicode, 4 cross-scope cases; expected class + wipeAllowed for all 5 events.
## Must-pass tests
1-8. Exact classification per fixture group. 9-13. wipeAllowed matrix for all 5 events. 14. Property over 500 random keys: protected classes never wipe-allowed; foreign never wipe-allowed.
Run: `node test/gm8-namespace-guard.test.mjs`.
## Bounds
Pure string classification against a supplied spec; no storage, no real key inventory; proves classifier semantics only.
## Target
Integrator ports into the middots line branch (assigned on return).
