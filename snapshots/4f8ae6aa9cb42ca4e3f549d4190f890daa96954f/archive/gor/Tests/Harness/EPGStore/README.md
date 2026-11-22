# EPG store cache and fallback harness

Run `bash gor/Tests/Harness/EPGStore/run.sh`. Python 3 only, current IPTV.swift required. Seven controls cover waiters, positive/negative TTL boundaries, country isolation and network fallback. Three source mutations fail. No snapshot fallback, feed request, XML/native/UI or production action.

Source/model characterizations: nonempty HTTP200 primary is parsed without trying fallback if guide comes back empty; empty parse is neither positive nor negative cached, so next request repeats; fuzzy prefix lookup uses first Dictionary match without exact channel identity assurance. No actual provider response or wrong guide observed. Policy, normalized identity, stale-cache preservation and failure TTL intent need evidence before changes.

PASS is state-port consistency, not provider/guide/native correctness. Distinct from EPGParsing XML admission; no production patch or external availability claim.
