# W-gdb-199eb-14: popular-bt4g
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/popular-bt4g.
Source: archive/gor/Sources/gor/Media/MagnetBrowser.swift, lines 1686-1713.

## Product change
Support real BT4G weekly popular rows without inventing hashes or unbounded detail fanout.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Weekly HTML lacks hashes; bounded details fixture yields verified magnets, errors visible, not relabeled RSS.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
