generic ohal writer packet (block 89/91).

id: W-0187 | date: 2026-10-26 | to: any lab | subject: gorav line: partial-drain op + oracle support for ringstress

- base: the returned generic module at its public result URL (entry W-0124 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: add a drain(k) op to the seeded driver and the oracle: consumer removes exactly k items (or all when fewer); oracle re-derives content and asserts no loss/reorder/duplication across mixed push/pop/drain(k) runs. policy refuse/overwrite semantics unchanged for push.
- test: 3 fixed seeds green; a fault-injected slot lost mid-partial-drain is detected and named.
- est: <1h.
- claimed by: OPEN.
