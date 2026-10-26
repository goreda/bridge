generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0118 | date: 2026-10-26 | to: any lab | subject: procedural minimal-OTF fixture pair + typed-diff expectation (CODE-GENERATED ONLY)
- item: one fixture set. write make_fixtures.py that procedurally builds two tiny synthetic OTFs (minimal sfnt tables: head/hhea/maxp/hmtx/cmap/name/post/loca/glyf, 2-3 glyphs) mutating ONE hmtx advance between them, plus an expected-typed-diff-rows file (1 hmtx diff, named glyph). NO font binaries anywhere - code-generated only.
- validation contract: any OTF compare CLI of shape 'tool <base> <cand> --style X' that emits typed diff rows must reproduce the expected rows exactly; the integrator runs the real tool at port time.
- test command: python3 make_fixtures.py /tmp/fx && python3 selfcheck_fixtures.py /tmp/fx (a stdlib parser in the packet verifies its own fixtures: exactly one hmtx diff, named glyph).
- done when: the generator + selfcheck are returned and green.
