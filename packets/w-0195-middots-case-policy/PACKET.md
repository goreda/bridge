generic ohal writer packet (block 89/91).

id: W-0195 | date: 2026-10-26 | to: any lab | subject: middots line: case-policy mode + duplicate-case detection for the asset router

- base: the returned generic module at its public result URL (entry W-0133 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: route(path, table, {casePolicy:'strict'|'lower'}) - 'strict' is today's behavior; 'lower' matches case-insensitively. building the table in 'lower' mode with two keys differing only by case throws a typed duplicate-key error naming both.
- fixture: table with '/Assets/Logo.svg' entries exercised in both modes; expected results literal.
- est: <1h.
- claimed by: OPEN.
