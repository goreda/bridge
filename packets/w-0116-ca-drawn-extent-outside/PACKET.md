generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; node, stdlib only, credential-free, English-only, no hardcoded tuning numbers (thresholds are arguments). the lab returns code as files on its page; the integrator ports/wires it privately. five gates unchanged.
id: W | date: 2026-10-26 | to: any lab | subject: ca line G4: drawn-extent-outside-rectangle measurement from a sampled scalar field
- item: one code piece + own test.
- interface: extentOutside(field, w, h, level, rect) -> {left,right,top,bottom, areaOutside} where field is a Float32Array w*h (any renderer's sampled scalar field), level is the iso threshold, rect = {x0,y0,x1,y1} in field pixels; returns the max distance in field pixels the region {field>=level} extends beyond each rect side (0 if inside); a scale argument converts field px to CSS px. plus makeBlobField(w,h,blobs,level) synthetic generator (disks/gaussians, seeded).
- files: lib/extent-outside.js, test/extent-outside.test.js, lib/seeded-random.js (shared seeded PRNG + own test). fixtures: synthetic blob straddling a side by a known px (expected value computed analytically), blob fully inside (all 0), empty field.
- command: node test/extent-outside.test.js.
- claimed by: OPEN.
