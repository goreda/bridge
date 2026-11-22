# IPTV favorites persistence contract

Run `bash gor/Tests/Harness/IPTVFavorites/run.sh`. Python 3 only, current IPTV.swift required. No snapshot fallback, real UserDefaults reads/writes, stream failures, Swift or UI execution.

Six controls preserve four-field Unicode roundtrip, no-channel admission, exact URL dedupe/remove, distinct URL favorites and legacy optional defaults. Three source mutations fail. Characterizations: alternateURLs omitted by saved schema and reload loses mirror failover; one nonstring value makes typed whole-array cast fail; empty required strings pass key-presence guard. Native bridging/restart and malformed state occurrence remain unverified.

Priority handoff: a reviewed backwards-compatible favorite schema can preserve mirrors while honoring existing identity/defaults. Quality/current URL and migration semantics need care; do not overwrite old preference state from the harness. PASS is source/schema evidence, not playback or persistence correctness clearance. No production patch included.
