# Music queue actual helper harness

Run `bash gor/Tests/Harness/MusicQueue/run.sh`. Python 3 only, current mus2.py required. AST-isolates four queue functions. mpv/cover/provider/emit dependencies are stubs recording synthetic effects, never real playback/network. No snapshot fallback, backend module startup, user queue or production action.

Six controls execute bounds, clear, archive/bandcamp source admission/identity, fetched-track path and now-playing. Three behavioral mutations fail. Injected playback error or malformed URL entry leaves already-mutated queue position; unknown source emits unchanged list. Actual dependency failure contract and normal producer schema need evidence, so these are helper-level failure characterizations, not observed music failures.

Compiled mus2 parity, actual mpv response, persistence/UI and user queue intent remain open. PASS is isolated actual Python function coverage, not installed helper/playback correctness. No production patch included.
