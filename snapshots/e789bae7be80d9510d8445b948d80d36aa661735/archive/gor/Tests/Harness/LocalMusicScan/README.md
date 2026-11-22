# Local music scan actual-function harness

Run `bash gor/Tests/Harness/LocalMusicScan/run.sh`. Python 3 only. AST-isolates current mus2.py AUDIO_EXTS, scan_local_path and classify_contents. Does not import/launch the backend module. Uses empty files and folders in its own temporary directory, deleted on exit. No user library scan, network, music decoding, Swift/UI or production action. No snapshot fallback.

Five controls execute actual source functions: album/folder/hidden/empty admission and title cleanup; sequential indices/local path identity; missing root; every audio extension in uppercase; injected permission failure. Three behavioral mutations fail. Characterizations are actual synthetic scan outputs: selected root audio omitted, direct-audio folder hides nested album from this result, hidden audio admitted, symlink alias duplicated. Some can be intentional browser contracts; user-facing access and compiled helper parity are unverified, so no guessed fix.

This improves source execution evidence over a Python consumer port, but is not installed compiled mus2 or Mac UI proof. Native helper provenance, real library permission/symlink/ordering and navigation to nested collections remain open. PASS is actual isolated scanner fixture coverage, not music library completeness clearance.
