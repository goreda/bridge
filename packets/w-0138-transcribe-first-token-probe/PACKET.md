# G-T2 streaming first-token latency probe (generic, ohal transcribe line)
One measurement harness, <2h. Distinct from all persistence/retry work: this MEASURES, it does not change behavior.

## Interface
```js
measureFirstVisible({ clock, stages, chunker })
// clock: {now():ms, sleep(ms):Promise} controllable fake clock (provided in fixture)
// stages: async function* yielding {t:ms, event:'uploaded'|'engine-done'|'polled', seq?} - fake pipeline
// chunker: (totalSeconds, partSeconds) => number[] of part boundaries
// returns { firstPartCutMs, firstTextVisibleMs, perPartMs:number[] }
```
## Synthetic fixture
Fake clock with scripted advance; fake engine stages (upload 300ms, engine 1500ms, poll 2000ms as defaults); chunker inputs 5s/3s/2s part sizes.
## Must-pass tests
1. With default stages and 5s parts: firstTextVisibleMs == 5000+300+1500+2000 (+/- 0, fake clock is exact).
2. 2s parts reduce firstTextVisibleMs by exactly 3000ms vs 5s parts.
3. Per-part cut times are monotonic non-decreasing.
4. Harness never calls real timers (assert no Date.now/setTimeout use outside injected clock).
Run: `node test/gt2-first-token-probe.test.mjs`.
## Bounds
SIMULATION ONLY: numbers are not real-device latency; the harness exists so a real pipeline can be plugged in later. No UI, no network.
## Target
Integrator ports into the transcribe line branch (assigned on return).
