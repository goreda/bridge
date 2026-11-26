# W-gdb-199eb-13: popular-knaben
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/popular-knaben.
Source: archive/gor/Sources/gor/Media/MagnetBrowser.swift, lines 1280-1307.

## Product change
Add documented queryless Knaben browse sorted by seeds with validated envelope.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Live or recorded valid 100-row envelope; malformed row isolation and generation cancellation.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
