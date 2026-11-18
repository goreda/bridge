# W-gdb-198z-1nstinct-01-fix executable RED starter

A01 runnable starter compiles verbatim TrackKind and stableStreamID declarations extracted from the complete exact imported file. No function rewrite or provider stub is used. This isolates the identity defect and is NOT a whole-module/provider build. ProviderModuleRegression.swift is supplied for a provider-equipped writer to link against the real GorAVFFmpegAdapter module; that path is NOT_RUN here.

Run `python3 run.py` from this folder, or use the archive-root argv in binding.json. Set SWIFTC if needed. Set PRODUCT_ROOT to test the same runner against a writer checkout; otherwise the bundled exact-source pin is used. No automatic fetch occurs. Missing compiler is exit77 NOT_RUN. Expected imported baseline exit1, not acceptance PASS. The full provider package build required by the original fix packet is NOT_RUN.
