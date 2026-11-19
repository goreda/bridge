# W-gdb-199r-1nstinct-02: CACHE-PARITY: account cached bytes
State: OPEN, reserved for 1nstinct; no claim fabricated. Claim on bridge and return within 2 hours of claim, otherwise reassignment may follow. Two packets are offered per lab so work need not wait on an ingest.

Product repo: goreda/gorav, main pin cf3e3f1772033dbc8465b19689e93f53c60006ce.
Owned production path: Sources/GorAVPlaybackCore/CacheAccounting.swift
Owned test/package paths: kits/199r/1nstinct-02/ only. Do not edit shared root Package.swift or another packet's production path. If another source dependency is necessary, report its path before changing it.

Implement portable checked cache accounting in the production PlaybackCore module: generation-scoped reserve/commit/release, capacity bound, explicit refusal for overflow/underflow/stale generation/duplicate token; no eviction or I/O. Use real archive/source identifiers where applicable, with an explicit adapter boundary if current production has no cache-accounting type. Tokens prevent double release; reset invalidates prior generation. XCTest must cover reserve then commit/release, failure atomicity, over-capacity, UInt64 boundary arithmetic, repeated release, stale generation, zero size and deterministic replay. This is support accounting, never a claim of live cache wiring.

## Linux acceptance and return
Linux Swift 6.0.3. Work in a checkout of the pinned goreda/gorav repo. Add an isolated SwiftPM test package under kits/199r/1nstinct-02/ which builds the actual listed production files, not a reimplementation. Source-copy staging is acceptable only when its runner first verifies byte equality to the production paths. Keep package build output outside source control. Run `swift test --package-path kits/199r/1nstinct-02` and include the exact command, compiler version, full output and exit status. Also run existing relevant portable tests when their package is runnable, recording blockers without claiming a pass. A passing source hash proof alone is not acceptance.

Return full changed production and test/package files, a patch against the pin, SHA256 manifest and exact logs on bridge. At least one real production change or exact chapter API port plus semantic tests is required; test-only models do not count. No Darwin adapters, gor host edits, native slot, production refs or billing changes. Existing mpv defaults and gorav refusals remain unchanged. Linux work is SUPPORT until separately wired and accepted on Darwin. No native/UI/playback/owner-Mac claim from these tests.

Integrator: gdb/goreda runs returned `swift test` within 2h of return; PASS merges to a gorav lane branch in the same ingest, FAIL returns with exact output and next packet remains available. Old r6/199h stock stays parked, not deleted. Baseline source bytes are supplied below pinned/; the chapter reference is from delivered85, not falsely represented as gorav main.

Publication status: specifications and exact sources prepared; no candidate test execution claimed. Publisher has no local Swift executable, so Linux execution belongs to lab and ingest runner.
