# W-gdb-199eb-14: popular-bt4g
Team: 1nstinct. State: APPLIED_SOURCE_RECONCILE. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-14, lane lane/1nstinct/popular-bt4g; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Media/MagnetBrowser.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 60d81bd64f18c8ca371fbee7466f634272ca1575
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Support real BT4G weekly popular rows without inventing hashes or unbounded detail fanout.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Route application already recorded at 3a868a24505a1fbbd9383f7043588a271cb0c4dc. Do not repeat this work; reconcile any remaining gap under this ID.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
1686:                 guard let uri=x["magnet_url"] as? String,uri.hasPrefix("magnet:?"),first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased()==h else {throw fail("eztv:magnet")}
1687:                 let ts=try num(x["date_released_unix"],"eztv:date");if ts>4102444800 {throw fail("eztv:date")}
1688:                 return try row("eztv",text(x["title"],"eztv:title"),h,num(x["size_bytes"],"eztv:size"),Int(num(x["seeds"],"eztv:seeds")),ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:Double(ts))))
1689:             }
1690:         case "bt4g","bt4gRecent":
1691:             guard let xml=payload as? String,xml.count <= 1_000_000,xml.range(of:#"^\s*<rss\s+version="2\.0""#,options:.regularExpression) != nil else {throw fail("bt4g:rss")}
1692:             let items=matches(#"<item>[\s\S]*?</item>"#,xml).map{$0[0]};if items.count>100 {throw fail("bt4g:items")}
1693:             return try items.map { item in
1694:                 let name=try text(field("title",item),"bt4g:title")
1695:                 let uri=field("link",item)
1696:                 guard uri.hasPrefix("magnet:?"),let h=first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased() else {throw fail("bt4g:magnet")}
1697:                 let validHash=try hash(h,"bt4g:hash")
1698:                 let detail=field("guid",item)
1699:                 guard let url=URL(string:detail),url.scheme=="https",url.host=="bt4gprx.com",url.path.range(of:#"^/magnet/[a-zA-Z0-9]+$"#,options:.regularExpression) != nil else {throw fail("bt4g:guid")}
1700:                 guard let desc=first(#"<description><!\[CDATA\[([\s\S]*?)\]\]></description>"#,item) else {throw fail("bt4g:description")}
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
```

Secret scan: clean.
