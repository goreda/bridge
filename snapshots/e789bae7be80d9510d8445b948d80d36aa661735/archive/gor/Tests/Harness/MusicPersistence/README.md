# Music JSON persistence actual-function harness

Run `bash gor/Tests/Harness/MusicPersistence/run.sh`. Python 3 only, current mus2.py required. AST-isolates four playlist/local-library JSON load/save functions; never imports/starts backend. Only own temporary files are read/written and deleted. No user preferences, pickle cache, provider, compiled helper or UI execution. No snapshot fallback.

Six controls execute missing/malformed defaults and Unicode roundtrip for both files. Three behavioral mutations fail. Actual injected write-error test truncates prior temporary valid file before save completes: old content lost, save raises and loader returns empty. Synthetic wrong JSON root returned without schema validation. Not an observed disk incident or installed mus2 proof.

Priority handoff: verify compiled helper provenance, then atomic replace/backup and visible save/load failure handling while preserving old schema/defaults. Real disk concurrency/migration remain open. PASS is isolated Python persistence/fault coverage, not user-data durability clearance. No production edit included.
