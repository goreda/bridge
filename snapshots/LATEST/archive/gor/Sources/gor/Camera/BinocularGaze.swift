import Foundation

/// Camera-local binocular pupil displacement. This is NOT a screen gaze point.
/// Only paired pupils inside measured eye outlines can supply a sample.
struct BinocularGazeSample {
    let t:Double,x:Double,y:Double,yaw:Double,pitch:Double,roll:Double,span:Double,cx:Double,cy:Double
    init(t:Double,x:Double,y:Double,yaw:Double,pitch:Double,roll:Double=0,span:Double=1,cx:Double=0,cy:Double=0) {
        self.t=t;self.x=x;self.y=y;self.yaw=yaw;self.pitch=pitch;self.roll=roll
        self.span=span;self.cx=cx;self.cy=cy
    }
    static func measure(t:Double,pupils:[Double],eyes:[Double],widths:[Double],apertures:[Double],yaw:Double,pitch:Double,roll:Double=0)->Self? {
        guard pupils.count==4,eyes.count==4,widths.count==2,apertures.count==2,
              ([t,yaw,pitch,roll]+pupils+eyes+widths+apertures).allSatisfy({$0.isFinite}),
              widths.allSatisfy({$0>2}),apertures.allSatisfy({$0>0.10}) else{return nil}
        let dx=eyes[2]-eyes[0],dy=eyes[3]-eyes[1],span=hypot(dx,dy)
        guard span>2 else{return nil}
        let ax=dx/span,ay=dy/span
        var xs:[Double]=[],ys:[Double]=[]
        for i in 0..<2 {
            let px=pupils[i*2]-eyes[i*2],py=pupils[i*2+1]-eyes[i*2+1]
            let x=(px*ax+py*ay)/widths[i],y=(-px*ay+py*ax)/widths[i]
            guard abs(x)<0.6,abs(y)<0.35 else{return nil}
            xs.append(x);ys.append(y)
        }
        return Self(t:t,x:(xs[0]+xs[1])/2,y:(ys[0]+ys[1])/2,yaw:yaw,pitch:pitch,roll:roll,span:span,cx:(eyes[0]+eyes[2])/2,cy:(eyes[1]+eyes[3])/2)
    }
}

/// Five measured screen targets fit an affine local mapping. It is an estimate,
/// valid for the calibrated window geometry and nearby head orientation only.
/// No eye/head substitution, fixed sensitivity, persisted biometric data or cursor control.
struct BinocularGazeCalibration {
    static let targets:[CGPoint]=[CGPoint(x:0.5,y:0.5),CGPoint(x:0.2,y:0.25),CGPoint(x:0.8,y:0.75),CGPoint(x:0.2,y:0.75),CGPoint(x:0.8,y:0.25)]
    enum State:Equatable {case off,calibrating(Int),tracking,failed}
    private(set) var state:State = .off
    private var rows:[(Double,Double)]=[],batch:[BinocularGazeSample]=[]
    private var entered:Double?,lastT:Double?,anchor:BinocularGazeSample?
    private var cx:[Double]=[],cy:[Double]=[]
    mutating func start(){self=Self();state = .calibrating(0)}
    mutating func stop(){self=Self()}
    mutating func feed(_ sample:BinocularGazeSample?,now:Double)->CGPoint? {
        guard let s=sample,now.isFinite,now-s.t>=0,now-s.t<0.2 else{batch=[];entered=nil;return nil}
        guard lastT==nil || s.t>lastT! else{return nil};lastT=s.t
        if anchor==nil {anchor=s}
        guard let anchor,abs(s.yaw-anchor.yaw)<0.15,abs(s.pitch-anchor.pitch)<0.15,
              abs(s.roll-anchor.roll)<0.15,anchor.span>0,abs(s.span/anchor.span-1)<0.12,
              hypot(s.cx-anchor.cx,s.cy-anchor.cy)/anchor.span<0.25 else{batch=[];entered=nil;return nil}
        switch state {
        case .calibrating(let index):
            if entered==nil {entered=now}
            guard now-(entered ?? now)>0.7 else{return nil} // target acquisition, not training data
            batch.append(s)
            guard batch.count>=12,now-(entered ?? now)>1.2 else{return nil}
            func median(_ a:[Double])->Double {let b=a.sorted();return b[b.count/2]}
            rows.append((median(batch.map{$0.x}),median(batch.map{$0.y})))
            batch=[];entered=nil
            if index+1<Self.targets.count {state = .calibrating(index+1)}
            else {state=fit() ? .tracking:.failed}
            return nil
        case .tracking:
            guard cx.count==3,cy.count==3 else{return nil}
            let x=cx[0]+cx[1]*s.x+cx[2]*s.y,y=cy[0]+cy[1]*s.x+cy[2]*s.y
            guard x.isFinite,y.isFinite,x>=0,x<=1,y>=0,y<=1 else{return nil}
            return CGPoint(x:x,y:y)
        default:return nil
        }
    }
    private mutating func fit()->Bool {
        guard rows.count==Self.targets.count else{return false}
        var a=[[Double]](repeating:[Double](repeating:0,count:5),count:3)
        for (i,row) in rows.enumerated() {
            let v=[1.0,row.0,row.1],p=Self.targets[i]
            for r in 0..<3 {for c in 0..<3 {a[r][c]+=v[r]*v[c]};a[r][3]+=v[r]*Double(p.x);a[r][4]+=v[r]*Double(p.y)}
        }
        for k in 0..<3 {
            let pivot=(k..<3).max(by:{abs(a[$0][k])<abs(a[$1][k])})!
            guard abs(a[pivot][k])>1e-6 else{return false}
            a.swapAt(k,pivot);let d=a[k][k];for c in k..<5 {a[k][c]/=d}
            for r in 0..<3 where r != k {let m=a[r][k];for c in k..<5 {a[r][c]-=m*a[k][c]}}
        }
        cx=a.map{$0[3]};cy=a.map{$0[4]}
        for (i,row) in rows.enumerated() {
            let p=Self.targets[i],x=cx[0]+cx[1]*row.0+cx[2]*row.1,y=cy[0]+cy[1]*row.0+cy[2]*row.1
            guard hypot(x-Double(p.x),y-Double(p.y))<0.12 else{cx=[];cy=[];return false}
        }
        return true
    }
}
