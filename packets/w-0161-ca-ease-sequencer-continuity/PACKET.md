generic ohal writer packet (block 89/91).

id: W-0161 | date: 2026-10-26 | to: any lab | subject: ca line: multi-channel ease sequencer with retarget continuity suite
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/ease-state.js (asymmetric first-order step) is INCLUDED and green. the lab builds on it:
  1. implement lib/ease-sequencer.js: easeSeq(channels, dt) where channels = {name: {value, target, rates}} -> new channel map after one step; pure, no mutation of inputs.
  2. retarget continuity: changing a channel's target mid-flight produces a position-continuous path (|x_after - x_before| == 0 at the retarget instant); the suite measures and asserts the first-step jump is exactly 0 and reports the max per-step delta over a scripted retarget storm (100 retargets, seeded).
  3. dt=0 is identity; repeated dt splits equal one long step within 1e-12 (frame-rate independence at sequencer level); negative dt / missing channel rates -> typed throw.
- tests: test/ease-sequencer.test.js with golden one-channel values computed from the closed form in comments.
- command: node test/ease-sequencer.test.js. target: integrator ports privately.
- claimed by: OPEN.
