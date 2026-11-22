# IPTV ingestion and request-identity harness

Run `bash gor/Tests/Harness/IPTVIngestion/run.sh`. Python 3 only. Reads current gor/Sources/gor/IPTV.swift directly. No snapshot fallback, playlist requests, sockets, external provider, playback or production changes. Synthetic inputs are embedded in the test. Source hash and final live-main reread are recorded in manifest.json.

Controls: LF/CRLF/CR line endings, attribute name/country/ID and fallback country parsing, empty lines and URL whitespace, quality-suffix grouping with ordered alternate URLs, unrelated ID-less channels, missing names/local-file rejection and normal-country generation/screen suppression including same-country ABA. Three source mutations fail.

Known-red characterizations: a directive/comment between EXTINF and URL drops the channel; malformed http-prefixed strings enter the list; uppercase HTTPS is skipped; last-comma fallback truncates a name containing a comma; an old random-country request can remain eligible after stop/restart because both callbacks only test isRandomMode. These preserve current source behavior, not observed provider/AppKit incidents or externally certified M3U compliance conclusions. Dictionary output order is deliberately not asserted because Swift's map order is unspecified.

Priority handoff: random fetch ownership should be scoped to the random session/request, preserving normal country generation guards. Parser changes need explicit accepted-scheme and directive/name semantics plus regressions for valid existing inputs. No candidate production patch is included.

PASS means controls and counterexamples reproduced, not IPTV correctness clearance. Native Foundation/regex/String/Dictionary parity, URLSession ordering, request cancellation/retry bounds, HTTP errors/charset/provider behavior, EPG, favorites persistence, quality switching and UI pixels remain open. This is gor playlist ingestion, not gorav/WT engine coverage.
