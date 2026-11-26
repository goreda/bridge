# W-gdb-199eb-36: popular-status-coverage
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/popular-status-coverage.
Source: archive/gor/Sources/gor/Media/MagnetBrowser.swift, lines 760-787.

## Product change
List every configured provider in empty-query status with specific unavailable reasons.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
760: 
761: /// One place that turns provider outcomes into the panel status line.
762: /// A provider that did not answer is always named with a readable reason, and an empty list
763: /// never reads as a plain "0 results" while a provider is down or still searching.
764: enum MagnetProviderStatusLine {
765:     static let reasonLabels: [String:String] = [
766:         "cloudflare_unresolved": "Cloudflare check not solved",
767:         "rate_limited": "rate limited",
768:         "http_or_network": "network error",
769:         "request_format": "bad request",
770:         "layout_changed": "page layout changed"
771:     ]
772:     static func label(_ provider: String, _ reason: String?) -> String {
773:         guard let reason, !reason.isEmpty else { return provider }
774:         return provider + " (" + (reasonLabels[reason] ?? "unavailable") + ")"
775:     }
776:     static func line(rows: Int, pending: Bool, unavailable: [(String, String?)]) -> String {
777:         let down = unavailable.sorted { $0.0 < $1.0 }.map { label($0.0, $0.1) }
778:         var parts = [rows == 0 && !pending ? (down.isEmpty ? "no results" : "no results from available providers") : "\(rows) rows"]
779:         if pending { parts.append("searching") }
780:         if !down.isEmpty { parts.append("unavailable: " + down.joined(separator: ", ")) }
781:         return parts.joined(separator: " / ")
782:     }
783: }
784: 
785: 
786: // ================================================================
787: //  SearchBarFit - shared growth rule for the single-line search/input bars
```

## Mandatory test
All providers represented pending/ok/unavailable; no plain zero while a provider is pending/down.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
