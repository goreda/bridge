# G-T6 typewriter pacing model (generic, ohal transcribe line)
Deterministic pacing calculator + tests, <2h.

## Interface
```js
planReveal(text, opts) -> number[]   // chars to reveal per tick, len = ticks to finish
// opts: { cps: number (chars/tick base), tickMs: number, pauseAfter: {'.':3, ',':1, '\n':2} (extra ticks), burstMax?: int }
// rules: deterministic for the same inputs; monotonic cumulative reveal; never exceeds text length;
// punctuation pauses ADD ticks without revealing; burstMax caps per-tick reveal (default 4*cps);
// trailing whitespace is revealed with the preceding token, never alone as final tick.
```
## Synthetic fixture
fixtures/texts.json: 6 texts (plain; punctuation-dense; multiline; single char; empty; 10k-char stress) with expected per-tick arrays for opts {cps:2, tickMs:50}.
## Must-pass tests
1-6. Exact expected arrays. 7. Property over 200 random texts: sum of reveals == length; cumulative monotonic; no tick reveals more than burstMax; plan length within ceil(len/cps)+pauseBound.
Run: `node test/gt6-typewriter-pacing.test.mjs`.
## Bounds
Pure arithmetic; no DOM, no timers, no animation frame; the model only - rendering integration is the integrator's.
## Target
Integrator ports into the transcribe line branch (assigned on return).
