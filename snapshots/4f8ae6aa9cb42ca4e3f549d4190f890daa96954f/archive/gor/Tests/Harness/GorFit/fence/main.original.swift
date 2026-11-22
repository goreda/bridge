// Glue replica v5: AppDelegate note/evaluate/write skeleton running the REAL GorClampFence.
func R(_ x:Double,_ y:Double,_ w:Double,_ h:Double)->GorFitRect{GorFitRect(x:x,y:y,w:w,h:h)}
let avail=R(0,0,2048,1180)
func inB(_ f:GorFitRect)->Bool{f.x>=-0.5&&f.y>=-0.5&&f.x+f.w<=2048.5&&f.y+f.h<=1180.5}
func clamp(_ f:GorFitRect)->GorFitRect{var r=f;r.w=min(r.w,2048);r.h=min(r.h,1180);r.x=min(max(r.x,0),2048-r.w);r.y=min(max(r.y,0),1180-r.h);return r}
struct G{
  var fence=GorClampFence(); var last=R(0,0,0,0); var scheduled=false; var writes=0; var seqs:[Int]=[]
  mutating func receipt(_ t:Double,_ f:GorFitRect){ last=f
    if fence.isUp { if fence.classify(receipt:f,now:t) == .own {return} }
    scheduled=true }
  mutating func ack(_ t:Double,ok:Bool=true){ if ok{fence.ack(seq:fence.seq,now:t)}else{fence.abort();scheduled=true} }
  mutating func evaluate(_ t:Double){ fence.expire(now:t); guard scheduled else{return}
    if fence.isUp {return}            // transient block -> real code retries every 0.5s; sim re-calls evaluate
    scheduled=false; if inB(last){return}
    let c=clamp(last); guard fence.canWrite(expected:c) else{return}
    _=fence.write(now:t,before:last,expected:c); writes+=1 } }
var fails=0
func chk(_ n:String,_ ok:Bool,_ i:String){ if !ok{fails+=1}; print(ok ?"PASS":"FAIL",n,i) }
let bad=R(300,-88,819,1456)
// G1 resize/clamp/receipt/resize
var g=G(); g.receipt(10,bad); g.evaluate(10.4); g.ack(10.45); let e1=clamp(bad); g.receipt(10.6,e1); g.receipt(11.0,R(1900,0,600,1000)); g.evaluate(11.4)
chk("G1 two user resizes -> two writes",g.writes==2,"writes=\(g.writes)")
// G2 animation frames of own write
g=G(); g.receipt(10,bad); g.evaluate(10.4); let b2=g.fence; let e2=clamp(bad)
for k in 1...3{let a=Double(k)/4; g.receipt(10.4+0.04*Double(k),R(bad.x+(e2.x-bad.x)*a,bad.y+(e2.y-bad.y)*a,bad.w+(e2.w-bad.w)*a,bad.h+(e2.h-bad.h)*a)); g.evaluate(10.42+0.04*Double(k))}
g.ack(10.55); g.receipt(10.6,e2); g.evaluate(10.8); _=b2
chk("G2 own animation frames -> no extra write",g.writes==1,"writes=\(g.writes)")
// G3 landing receipt BEFORE ack (out of order)
g=G(); g.receipt(10,bad); g.evaluate(10.4); g.receipt(10.45,e2); g.ack(10.5); g.evaluate(10.8)
chk("G3 receipt before ack -> no extra write",g.writes==1,"writes=\(g.writes)")
// G4 rapid user drags right after landing (inside the old 0.60s window), each out of bounds
g=G(); g.receipt(10,bad); g.evaluate(10.4); g.ack(10.45); g.receipt(10.5,e2)
g.receipt(10.6,R(1800,10,600,1000)); g.evaluate(10.65); g.ack(10.7); g.receipt(10.72,clamp(R(1800,10,600,1000)))
g.receipt(10.8,R(1850,20,650,1000)); g.evaluate(10.85)
chk("G4 drags 0.1s after landing are USER events and get clamped",g.writes==3 && !inB(R(1850,20,650,1000)),"writes=\(g.writes)")
// G5 static desktop: write, NO ack and NO receipt ever; later user resize must still be clamped (TCv3-F1)
g=G(); g.receipt(10,bad); g.evaluate(10.4); g.receipt(12.5,R(1900,0,600,1000)); g.evaluate(12.9)
chk("G5 no ack/receipt: fence expires, later user resize clamped",g.writes==2,"writes=\(g.writes)")
// G6 mpv error reply: write refused -> abort + re-evaluate (not lost)
g=G(); g.receipt(10,bad); g.evaluate(10.4); g.ack(10.45,ok:false); g.evaluate(10.9)
chk("G6 refused write is retried, not lost",g.writes==2,"writes=\(g.writes)")
// G7 persistently refused: OS keeps returning a different out-of-bounds frame that is NOT on the path (off-request) 
g=G(); g.receipt(10,bad); var t=10.4; g.evaluate(t); 
for _ in 0..<12 { t+=0.1; g.ack(t); t+=0.05; g.receipt(t,R(300,-40,880,1240)); t+=0.05; g.evaluate(t) }
chk("G7 refused/off-request receipts: loop bounded by identical-target rule",g.writes<=8,"writes=\(g.writes)")
// G7b identical target refused 3x then stop
g=G(); g.receipt(10,bad); t=10.4; g.evaluate(t)
for _ in 0..<12 { t+=0.1; g.ack(t); t+=0.05; g.receipt(t,bad); t+=0.05; g.evaluate(t) }   // OS keeps snapping back to the same bad frame
chk("G7b same target refused 3x -> stops chasing",g.writes==3,"writes=\(g.writes)")
// G7c ...but a DIFFERENT user move afterwards is clamped again
g.receipt(t+0.5,R(1700,5,700,1000)); g.evaluate(t+1.0)
chk("G7c new user move after a refused target is clamped",g.writes==4,"writes=\(g.writes)")
print("FAILS",fails)
