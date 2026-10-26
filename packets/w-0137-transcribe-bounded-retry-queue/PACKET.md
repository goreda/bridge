# G-T1 bounded retry queue (generic, ohal transcribe line)
One component, <2h. Write the module + tests; integrator ports it into the product branch.

## Interface (ESM, no deps)
```js
createRetryQueue({ send, maxAttempts = 5, baseDelayMs = 100, honorRetryAfter = true })
// send: async (part: {seq:number, body:Uint8Array}) => {ok:true} | throws | {status:number, headers?:{get(h)=>string|null}}
// returns {
//   enqueue(part): void            // parts must be sent in ascending seq order
//   onAck(cb): void  onFail(cb): void   // cb(seq) / cb(seq, terminalStatus)
//   close(): Promise<{stored:number[], failed:number[]}>
// }
```
## Synthetic fixture (provided below, reuse or extend)
Fake server scripting per-seq outcomes: ok / status(429|503 with Retry-After header) / throw TypeError('network') / 'lost' (stores, ack lost). Deterministic, in-memory.
## Must-pass tests (node test file, node:assert)
1. 15 parts, seq 3 and 7 return 429 twice then ok: close() resolves stored=[0..14], attempts on any seq <= maxAttempts, Retry-After value honored (no send before delay).
2. seq 0 returns 503 every time: close() resolves failed=[0], stored=rest; no unbounded loop.
3. 'lost' on seq 5: resend is idempotent (same bytes), no duplicate-ack crash; stored includes 5 once.
4. enqueue during close: coalesced, no part dropped.
Run: `node test/gt1-retry-queue.test.mjs` (no deps).
## Bounds
Synthetic only: passing does NOT prove any real server behavior; integrator wires to the real client and re-measures. No persistence, no UI, no job-id/cap logic.
## Target
Integrator ports into the transcribe line branch (assigned on return).
