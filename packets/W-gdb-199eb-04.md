# W-gdb-199eb-04: crop-consensus
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-04, lane lane/1nstinct/crop-consensus; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Picture/CropDetector.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 98c8d0558be0aa017dc6ee48a60c39ac3976fea3
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Fix mixed-aspect sample consensus without removing any observed picture-bearing extent.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
14: // window spring is allowed to chase the crop endpoint.
15: struct CropMotionClock {
16:     let started:Double
17:     let duration:Double
18:     func phase(_ now:Double)->Double {
19:         guard now.isFinite,started.isFinite,duration.isFinite,duration>0 else{return 1}
20:         let t=max(0,min(1,(now-started)/duration))
21:         return t*t*(3-2*t)
22:     }
23:     static func mix(_ a:CGRect,_ b:CGRect,_ phase:Double)->CGRect {
24:         let t=CGFloat(max(0,min(1,phase)))
25:         if t==1{return b};if t==0{return a}
26:         return CGRect(x:a.minX+(b.minX-a.minX)*t,y:a.minY+(b.minY-a.minY)*t,
27:                       width:a.width+(b.width-a.width)*t,height:a.height+(b.height-a.height)*t)
28:     }
29: }
30: 
31: final class CropDetector {
32:     private let sourceScanner = SourcePixelCropScanner()
33:     var stereoSBS = false
34:     var viewportOnly = false
35:     var sourcePixelWidth:Int { sourceScanner.decodedWidth }
36:     var sourcePixelHeight:Int { sourceScanner.decodedHeight }
37:     var perEyeAspect:Double? {sourceScanner.perEyeAspect}
38:     var stereoTopBottom = false
39:     private let mpvPath: String
40:     /// Typed probe source, injected by the composition root; the Picture
41:     /// layer never names the backend command owner that mints these.
```

Secret scan: clean.
