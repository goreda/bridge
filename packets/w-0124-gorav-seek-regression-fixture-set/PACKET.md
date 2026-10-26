generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0124 | date: 2026-10-26 | to: any lab | subject: synthetic seek-regression video fixture generator (generic)
- item: one fixture set. a generator producing small synthetic video files exercising two seek classes: backward keyframe seeks and an end-of-media boundary; plus a manifest mapping case -> expected class. all bytes generated in-test; deterministic (two runs byte-identical).
- synthetic fixtures: pure synthetic encodes (documented codec parameters in the generator; public ffmpeg toolchain).
- test command: python3 gen_seek_fixtures.py <out-dir> && python3 selfcheck_fixtures.py <out-dir> (opens every generated file with the pinned ffmpeg recipe, verifies frame counts + keyframe layout).
- done when: the generator + manifest + determinism proof are returned.
