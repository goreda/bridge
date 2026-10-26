generic ohal writer packet (block 89/91).

id: W-0194 | date: 2026-10-26 | to: any lab | subject: middots line: extension-negotiation leg for the asset router

- base: the returned generic module at its public result URL (entry W-0133 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: route(path, table, {suffixes:['.js','.html']}) - an exact-miss path without an extension resolves by trying suffixes in the GIVEN order ('/app' -> 'app.js'); when several suffixes match, the first in list order wins (deterministic, documented); '/app' with no suffixed entry stays notFound.
- fixture: base table plus entries exercising order and ambiguity.
- est: <1h.
- claimed by: OPEN.
