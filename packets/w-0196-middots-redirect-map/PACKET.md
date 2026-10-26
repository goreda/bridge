generic ohal writer packet (block 89/91).

id: W-0196 | date: 2026-10-26 | to: any lab | subject: middots line: redirect-map leg for the asset router

- base: the returned generic module at its public result URL (entry W-0133 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: route(path, table, {redirects}) - exact-match redirect entries return {redirect:'/target'} and are applied AFTER all rejection legs (a rejected path is never redirected); redirect targets must themselves resolve or the result is notFound (one hop only, no chains).
- fixture: base table plus a redirect pair and a chain attempt that must resolve in one hop or notFound.
- est: <1h.
- claimed by: OPEN.
