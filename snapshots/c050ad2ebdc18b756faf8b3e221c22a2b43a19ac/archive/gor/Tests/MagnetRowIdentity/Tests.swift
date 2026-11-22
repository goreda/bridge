import Foundation
@main struct Tests {
 static func main() {
  var failures=[String](),checks=0
  func check(_ yes:Bool,_ why:String){checks+=1;if !yes {failures.append(why)}}
  func row(_ i:Int,_ seeds:Int)->MagnetResult {
   MagnetResult(title:String(format:"row %03d",i),sizeBytes:1,seeds:seeds,
    magnetUri:"magnet:?xt=urn:btih:"+String(format:"%040d",i),uploadedAt:nil,uploadedLabel:nil,
    infoHash:String(format:"%040d",i),source:"uindex",detailUrl:"https://invalid.test/\(i)",
    claims:["uindex":seeds],verdict:nil)
  }
  for offset in [0.0,235.0,470.0] {
   let panel=MagnetResultsPanel()
   let original=(1...80).map{row($0,1000-$0)}
   panel.show(SearchResponse(results:original,pendingRows:[],providers:[:]))
   let oldRevision=panel.rowRevision
   // Same exact identities, changed ranking. Swap neighboring rows by changing real sort inputs.
   let changed=original.enumerated().map{ index,item in row(index+1,1000-(index ^ 1)) }
   panel.show(SearchResponse(results:changed,pendingRows:[],providers:[:]),keepScroll:true)
   check(panel.rowRevision>oldRevision,"changed order must rebuild row controls at offset \(offset)")
   let h=23.5,viewport=141.0
   let range=MagnetNative.visibleRange(offsetY:offset,viewportHeight:viewport,rowCount:panel.rows.count,rowHeight:h)
   let slots=MagnetNative.slotAssignments(poolSize:MagnetNative.poolSize(viewportHeight:viewport,rowHeight:h),range:range,rowCount:panel.rows.count)
   for (slot,index) in slots {
    check(index==range.lowerBound+slot,"pool recycling maps slot to actual document row")
    // Native stack is flipped. Header is a sibling above NSScrollView, not a data row.
    // Clip offset -> document coordinates. NSButton carries index, not a y/header subtraction.
    let documentY=Double(index)*h+h*0.5
    let viewportY=documentY-offset
    let hitDocumentY=viewportY+offset
    let hitIndex=Int(floor(hitDocumentY/h))
    check(hitIndex==index,"flipped clip offset round trip")
    check(panel.displayed[index]==panel.rows[hitIndex].magnetUri,"clicked displayed row must resolve same magnet, offset \(offset), index \(index)")
   }
   let stableRevision=panel.rowRevision
   panel.show(SearchResponse(results:changed,pendingRows:[],providers:[:]),keepScroll:true)
   check(panel.rowRevision==stableRevision,"unchanged order retains fast path")
   panel.show(SearchResponse(results:changed,pendingRows:[],providers:[:]),keepScroll:false)
   check(panel.rowRevision>stableRevision,"explicit sort/provider refresh still rebuilds")
  }
  if !failures.isEmpty {for f in failures {print("FAIL "+f)};exit(1)}
  print("PASS \(checks) exact-source refresh/order/virtualization checks")
 }
}
