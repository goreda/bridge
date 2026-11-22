# Catalogue current-tree survey regression

Run `bash gor/Tests/Harness/Catalogue/run.sh`. Requires Python 3 only. Reads current repository Swift sources directly; no adjacent historical source fallback. Reviewed against pinned commit 9910f354. A missing expected current-source guard or reintroduced regression fails. Source changes still require semantic port review; token presence alone is not native parity.

Old Catalogue survey outputs are historical evidence. Transfer now checks parsed archive host/path, bounded fresh capture and reused capture identity rather than the obsolete substring/semaphore behavior. Catalogue now checks independent file backfill after an empty facet pass rather than asserting the removed early return. Other persistence/refresh/year/key concerns and companion folder-wide semantics remain unresolved source characterizations, not fixed runtime guarantees.

These are Python models plus current Swift source guards, not native Swift URLComponents/CDP/concurrency/disk/network execution. No production source changes. Existing historical ZIPs and hashes must remain unchanged; their metadata is annotated separately.
