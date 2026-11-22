# Archive library ingestion/cache harness

Run `bash gor/Tests/Harness/ArchiveLibrary/run.sh`. Python 3 only. Reads current ArchiveLibrary.swift directly, with no historical-source fallback. Synthetic CSV and cache-state inputs only. No Sheets requests, source downloads, actual disk mutations, Swift or AppKit execution. Distinct from TransferResolver Catalogue worker coverage.

Controls: CSV CR/LF/CRLF, quoted commas/quotes/newlines, empty fields and Unicode; instant cache then failure preservation; successful initial callbacks; retry after initial failure; reorder-only refresh suppression; changed refresh schedules persistence. Three source mutations fail. Atomic write and all-source-failure preservation are existing positive source protections.

Counterexamples/characterizations: two changed refreshes can schedule concurrent writes whose completion order leaves older data on disk despite newer memory; queued first-fetch callbacks survive failure and run after a later success (possibly intentional waiting-client semantics); quoted empty EOF row is omitted; unterminated quote is accepted. PASS preserves expected characterizations, not correctness clearance or real disk-race reproduction.

Disk-order handoff: serialize or version cache writes while preserving instant old cache, failed refresh protection and reorder suppression. Do not silently change callback waiting semantics or malformed CSV handling without a separate compatibility review. Swift Character/regex/link parsing, real Sheets/provider/merge, actual write ordering/errors, callback replacement and empty-library semantics remain open. No production patch included.
