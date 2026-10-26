generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0113 | date: 2026-10-26 | to: any lab | subject: wasm parity difference reporter (generic)
- item: one test group. a node script that loads TWO wasm binaries with the same export ABI (a state-packing layout with a fixed stride, seeded state init, one step function, one readout - the integrator supplies the actual ABI doc and binaries at port time), feeds identical packed states, and reports per-field f64 differences: count differing, max abs diff, max ULP, first differing cell/field.
- synthetic fixtures: dense and sparse packed states generated in-test from seeds; NO product binaries ship in the packet.
- contract checks (supplied at port time as a JSON of named numeric bounds): each check evaluated and reported PASS/FAIL with raw values; a failing check prints field index + a minimal repro seed. bit-identity is NOT the acceptance - report honest differences.
- test command: node parity-report.js <abi.json> <binA> <binB> <trials> <seed>; the packet's self-test runs it against two tiny mock wasm/JS stubs built in-test.
- done when: the reporter + self-test are returned and green.
