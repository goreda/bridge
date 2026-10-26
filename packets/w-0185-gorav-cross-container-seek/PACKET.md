generic ohal writer packet (block 89/91).

id: W-0185 | date: 2026-10-26 | to: any lab | subject: gorav line: cross-container determinism harness for seekref

- base: the returned generic module at its public result URL (entry W-0122 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: xcont <src.mov> <seed> <count> - remuxes src to .mkv (ffmpeg -c copy), runs the base seek logic on both, asserts the landing_pts SETS match within 1 frame per target (declared tolerance, printed), and reports {"mov_targets":N,"mkv_targets":N,"mismatches":[...],"ok":bool}.
- negative leg: a deliberately re-encoded (not remuxed) variant is allowed to mismatch but must be REPORTED, never silently equalized.
- est: <2h, Python stdlib + ffmpeg CLI.
- claimed by: OPEN.
