# W-gdb-199eb-13: popular-knaben
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-13, lane lane/1nstinct/popular-knaben; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Media/MagnetBrowser.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 60d81bd64f18c8ca371fbee7466f634272ca1575
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Add documented queryless Knaben browse sorted by seeds with validated envelope.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
1280:     // unchanged. uindex.org's front page carries Trending tables, so the
1281:     // popular sources are uindex (WebKit route, same as search) and apibay
1282:     // below. If gdb's package lands with working endpoints for the rest, add
1283:     // them here.
1284:     private func popular() {
1285:         guard Date() >= throttledUntil else { panel.setStatus("wait before searching again"); return }
1286:         throttledUntil = Date().addingTimeInterval(20)
1287:         generation += 1; parseSerial += 1; let token = generation
1288:         refreshRevision &+= 1; reparsePending = false
1289:         panel.invalidateSelection()
1290:         tasks.forEach { $0.cancel() }; tasks.removeAll()
1291:         sessions.forEach { $0.invalidateAndCancel() }; sessions.removeAll()
1292:         query = ""; parsedProviders = [:]; failures = [:]
1293:         pendingProviders = ["uindex", "apibay"]
1294:         lastResponse = nil
1295:         verificationCancellation.cancel(); trackerQueue.cancelAllOperations(); verificationCancellation = Progress(totalUnitCount: 1); verdicts = [:]; scrapedHashes = []
1296:         panel.isHidden = false
1297:         (NSApp.delegate as? AppDelegate)?.controller?.wakeUI()
1298:         panel.setQuery("")
1299:         panel.applySort("seeds", descending: true)
1300:         // apibay precompiled top100 (all-time): plain JSON on the same fetch
1301:         // path as search, same response checks, existing apibay parse arm.
1302:         if let apibayTop = URL(string:"https://apibay.org/precompiled/data_top100_all.json") {
1303:             fetch(apibayTop, provider:"apibay", token:token) { [weak self] in self?.parse() }
1304:         } else { failures["apibay"] = "request_format"; pendingProviders.remove("apibay"); parse() }
1305:         uindexProvider.popular { [weak self] (result: Result<[[String: Any]], MagnetUIndexFailure>) in
1306:             DispatchQueue.main.async {
1307:                 guard let self, self.generation == token else { return }
```

Secret scan: clean.
