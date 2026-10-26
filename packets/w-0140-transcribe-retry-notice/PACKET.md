# G-T4 retry-notice state machine (generic, ohal transcribe line)
One framework-free UI state machine + DOM-stub tests, <2h. Independent of G-T1 (transport) - this is presentation state only.

## Interface
```js
createRetryNotice({ onAction })
// states: 'hidden' | 'showing' | 'busy' | 'terminal'
// -> {
//   show(reason): void            // hidden -> showing; showing -> showing (no duplicate)
//   action(): void                // showing -> busy, calls onAction once
//   resolve(): void               // busy -> hidden
//   failTerminal(reason): void    // any -> terminal
//   clear(): void                 // terminal -> hidden
//   render(el): void              // el is a DOM-stub element (fixture)
// }
```
## Synthetic fixture
Minimal DOM stub: element = {children:[], attrs:{}, addEventListener(){}, remove(){}}; factory counts created elements.
## Must-pass tests
1. show() x3 renders exactly ONE action element (no duplicates).
2. action() during 'busy' is a no-op; onAction called once.
3. failTerminal during 'busy' -> terminal; action element removed/disabled; late resolve() is a no-op.
4. clear() from terminal returns to hidden with zero children.
5. role='alert' attribute set while visible.
Run: `node test/gt4-retry-notice.test.mjs`.
## Bounds
DOM stub only - real browser rendering is a separate verification step owned by the integrator. No transport logic.
## Target
Integrator ports into the transcribe line branch (assigned on return).
