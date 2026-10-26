generic ohal writer packet (block 89/91).

id: W-0188 | date: 2026-10-26 | to: any lab | subject: gorav line: tick-budget blocking policy for ringstress

- base: the returned generic module at its public result URL (entry W-0124 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: --policy block --ticks T - push on a full ring waits (advances a simulated tick clock) until space or budget exhaustion, then returns a typed TIMEOUT result; the oracle models the tick clock and asserts no wait exceeds T and no push is lost silently.
- test: seeded mix where timeouts are forced (consumer stalled for >T ticks): TIMEOUT count matches the oracle exactly; refusal paths stay typed.
- est: <2h.
- claimed by: OPEN.
