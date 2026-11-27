# W-gdb-199eb-15: popular-nyaa
Team: 1nstinct. State: APPLIED_SOURCE_RECONCILE. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-15, lane lane/1nstinct/popular-nyaa; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Media/MagnetBrowser.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 60d81bd64f18c8ca371fbee7466f634272ca1575
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Find and validate actual popular ordering; RSS sort parameters may be ignored.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Route application already recorded at f6b43ed53933a5ea7106f537eb5100b59c4d0e64. Do not repeat this work; reconcile any remaining gap under this ID.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
1701:                 let pieces=desc.replacingOccurrences(of:#"(?i)<br\s*/?>"#,with:"\u{0001}",options:.regularExpression).components(separatedBy:"\u{0001}").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
1702:                 guard pieces.count==4,pieces[3].lowercased()==validHash else {throw fail("bt4g:description")}
1703:                 return try row("bt4g",name,validHash,size(pieces[1],"bt4g:size"),nil,date(field("pubDate",item),"bt4g:date"),detail,uri:uri)
1704:             }
1705:         case "nyaa":
1706:             guard let xml=payload as? String,xml.count<=1_000_000,xml.contains("<rss") else {throw fail("nyaa:rss")}
1707:             let items=matches(#"<item>[\s\S]*?</item>"#,xml).map{$0[0]};if items.count>100 {throw fail("nyaa:items")}
1708:             return try items.map {item in
1709:                 let name=try text(field("title",item),"nyaa:title")
1710:                 let h=try hash(field("nyaa:infoHash",item),"nyaa:hash")
1711:                 let link=field("link",item)
1712:                 guard link.range(of:#"^https://nyaa\.si/(view|download)/[0-9]+(?:\.torrent)?$"#,options:.regularExpression) != nil else {throw fail("nyaa:link")}
1713:                 return try row("nyaa",name,h,size(field("nyaa:size",item),binary:true,"nyaa:size"),Int(num(field("nyaa:seeders",item),"nyaa:seeds")),date(field("pubDate",item),"nyaa:date"))
1714:             }
1715:         case "uindex":
1716:             // Collector output: magnet-anchored rows from a real WebKit page.
1717:             // Live layout (verified 2026-10-17 on the real results DOM):
1718:             // td.sr-col-name holds the magnet anchor plus the details.php title
1719:             // anchor; td.sr-col-size / td.sr-col-seeders / td.sr-col-uploaded
1720:             // carry claims. Every field falls back to row-text / dn= so a
1721:             // layout change degrades instead of breaking. Malformed rows drop
1722:             // and count, never fail the provider. seeds/size stay claims -
1723:             // the verdict verifies truth.
1724:             return try array(payload,2000,"uindex:rows").compactMap { x -> MagnetResult? in
1725:               do {
1726:                 // text() caps at 300 chars; real uindex magnets carry 8 trackers
1727:                 // and run 400-700 chars (measured on the live DOM 2026-10-17), so
1728:                 // the magnet gets its own extraction with a 4096 abuse cap.
```

Secret scan: clean.
