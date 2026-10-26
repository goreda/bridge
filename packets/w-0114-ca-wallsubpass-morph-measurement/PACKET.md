generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0114 | date: 2026-10-26 | to: any lab | subject: A/B pass-effect measurement harness (generic)
- item: one harness. given a state-transition function F supplied at port time (integrator provides the actual function + a skip flag), measure what one optional post-pass changes per call: per-entity numeric field deltas (mean/max abs) and count of entities affected, pass-on vs pass-skipped, across synthetic dense and sparse states.
- synthetic fixtures: seeded synthetic entity states (position/velocity/shape fields) generated in-test.
- interface: measure(effectFn, states, {passOn}) -> per-state delta table printed as raw values; no acceptance thresholds, metrics only; NO code changes to the supplied function.
- test command: node ab-pass-effect.js --selftest runs the harness against a mock F with a known planted effect and asserts the measured deltas recover it.
- done when: the harness + self-test are returned and green.
