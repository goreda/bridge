generic ohal writer packet (block 89/91).

id: W-0193 | date: 2026-10-26 | to: any lab | subject: middots line: percent-decoding leg for the asset router

- base: the returned generic module at its public result URL (entry W-0133 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: route() gains percent-decoding of the request path BEFORE matching: '/assets/%6cogo.svg' resolves like '/assets/logo.svg'; malformed sequences ('%zz', trailing '%') -> {notFound:true}; a decoded '..' or NUL is still rejected exactly as a literal one.
- fixture: base asset table plus encoded variants; expected results literal in the test, including the malicious-encoding legs.
- est: <1h, node stdlib.
- claimed by: OPEN.
