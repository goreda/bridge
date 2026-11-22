# Music cover preview ownership harness

Run `bash gor/Tests/Harness/MusicCover/run.sh`. Python 3 only, current PPController_Features.swift required. No snapshot fallback, real image/cache/network fetch, Swift/AppKit/rendering or UI execution. This is a nonvisual action-routing/ownership model, not a visual artifact or pixel test.

Five controls cover cache hit/miss, invalid cached-image refusal, completed hide and in-order A/B selection. Three source mutations fail, including stable-key call replacement. SHA-1 implementation itself is not executed or proved. Current stable hash routing is positive source evidence, not missing behavior.

Four bounded characterizations: out-of-order A completion overwrites B; completion after hide sets alpha back to one; completion after music exit still writes captured view; corrupt existing cache skips refetch after image decode failure. Native image/animation/lifetime effects remain unverified. PASS means expected callback actions, not visually correct covers.

Priority handoff: selected-cover/mode/hide ownership token and reviewed cache-decode recovery, preserving stable cache keys and normal hit behavior. Cache errors, sizes/MIME/timeouts/concurrent writes and actual image/alpha/frame pixels need separate native evidence. No production patch included.
