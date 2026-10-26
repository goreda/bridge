generic ohal writer packet (block 89/91).

id: W-0186 | date: 2026-10-26 | to: any lab | subject: gorav line: exhaustive small-capacity op-sequence sweep for ringstress

- base: the returned generic module at its public result URL (entry W-0124 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: ringsweep --cap-max 3 --len-max 8 - DETERMINISTICALLY enumerates every op sequence (push/pop/drain) for capacities 1..3 up to length 8 and runs each through the base ring + oracle; reports {checked:<n>, failures:0}.
- property: enumeration count equals sum over caps and lengths of 3^len (asserted); any oracle mismatch names the exact sequence. no randomness anywhere.
- est: <1h.
- claimed by: OPEN.
