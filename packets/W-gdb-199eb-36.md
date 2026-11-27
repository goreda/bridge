# W-gdb-199eb-36: popular-status-coverage
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-36, lane lane/in2tinct/popular-status-coverage; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Media/MagnetBrowser.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 60d81bd64f18c8ca371fbee7466f634272ca1575
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
List every configured provider in empty-query status with specific unavailable reasons.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
