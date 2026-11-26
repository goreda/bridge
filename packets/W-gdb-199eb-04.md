# W-gdb-199eb-04: crop-consensus
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/crop-consensus.
Source: archive/gor/Sources/gor/Picture/CropDetector.swift, lines 14-41.

## Product change
Fix mixed-aspect sample consensus without removing any observed picture-bearing extent.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Mixed intro/content/outlier vectors fail old consensus and preserve union containment.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
