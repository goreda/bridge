generic ohal writer packet (block 89/91).

id: W-0183 | date: 2026-10-26 | to: any lab | subject: gorav line: seekref batch mode + manifest digest

- base: the returned generic module at its public result URL (entry W-0122 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: seekref-batch <seed> <count> <out.json> <clip1> <clip2> [...] - runs the base per-clip logic over several clips, emits {"seed":..,"clips":[{"file":..,"targets":[...]}...],"digest":<fnv1a64-hex over per-clip JSON concatenation in argument order>}.
- test: two runs byte-identical; reordering clip arguments changes the digest but not any per-clip target set (proven in-test). fixture: two self-generated synthetic clips (lavfi testsrc2, different rates).
- est: <1h, Python stdlib + ffmpeg CLI.
- claimed by: OPEN.
