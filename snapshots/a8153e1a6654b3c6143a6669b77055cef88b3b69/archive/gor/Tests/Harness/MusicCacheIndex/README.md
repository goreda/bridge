# Music cache identity/index actual-function harness

Run `bash gor/Tests/Harness/MusicCacheIndex/run.sh`. Python 3 only, current mus2.py required. AST-isolates index/admission/item helpers with provider/save stubs. Five controls execute original-reference position, reuse/rebuild, sorted empty-cache fetch and index reset. Three behavioral mutations fail. No snapshot fallback, backend module, pickle/user cache/provider/Swift/UI action.

Synthetic state characterizations: equal copy gets -1; duplicate same object keeps last index; indexed bandcamp-only cache skips archive-content check/fetch; changed cache argument does not refresh global identity index. Some are intentional identity/caller contracts. Normal search/cache mutation reachability and compiled helper parity are unverified, so no confirmed installed cache/search defect.

PASS is actual isolated helper coverage, not provider/cache correctness. Verify caller state and helper provenance before changes. No production patch included.
