let vids: [(Double,Double)] = [(720,1280),(1080,1920),(1080,1350),(2160,3840),(1920,1080),(3840,2160),(1280,720)]
let avs: [(Double,Double)] = [(2048,1180),(1440,780),(3008,1620)]
var bad = 0
for a in avs { for v in vids {
  let p = GorVideoFit.proposedOpenSize(videoW: v.0, videoH: v.1, screenW: a.0)
  let r = GorVideoFit.fit(video: p, avail: GorFitRect(x:0,y:0,w:a.0,h:a.1))
  let ok = r.w <= a.0 && r.h <= a.1 && r.x >= 0 && r.y >= 0 && r.x + r.w <= a.0 && r.y + r.h <= a.1
  if !ok { bad += 1 }
  print(a, v, "prop", p.w, p.h, "->", r.w, r.h, "@", r.x, r.y, ok ? "OK":"FAIL")
}}
print("FAILS", bad)
