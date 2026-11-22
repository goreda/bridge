import Foundation

///192d D2. Pixel coordinates preserve Euclidean distance under in-plane roll.
/// Calibrated f_px and anatomical IPD affect metric distance only; their ratio
/// cancels for relative zoom. No focal length or physical IPD is guessed.
struct PupilDistanceScale {
    private var referenceSpans:[String:Double]=[:], lastRelative=0.0
    mutating func reset() { referenceSpans=[:];lastRelative=0 }
    mutating func recenter() { reset() }
    var hasPupilReference:Bool {referenceSpans["pupil"] != nil}
    struct Sample {
        let relative: Double
        let millimetres: Double?
        let usedPupils: Bool
    }
    mutating func sample(left:(Double,Double)?,right:(Double,Double)?,yaw:Double,
                         fallbackWidth:Double,focalPixels:Double?=nil,ipdMM:Double?=nil,landmarkKind:String="pupil") -> Sample {
        if landmarkKind != "pupil",hasPupilReference {
            return Sample(relative:lastRelative,millimetres:nil,usedPupils:false)
        }
        let cy=abs(cos(yaw))
        var span:Double?
        if let a=left,let b=right,cy>Double.ulpOfOne.squareRoot() {
            let d=hypot(a.0-b.0,a.1-b.1)/cy
            if d.isFinite && d>0 {span=d}
        }
        if let span {
            // A pupil centre and an eye-outline centre are different sensors.
            // Match each sensor's first reference to the current distance, never
            // reuse a pupil baseline for an outline or mixed anatomical pair.
            if referenceSpans[landmarkKind]==nil {referenceSpans[landmarkKind]=span/(1+lastRelative)}
            lastRelative=span/(referenceSpans[landmarkKind] ?? span)-1
            let mm:Double?
            if let f=focalPixels,let ipd=ipdMM,f>0,ipd>0 {mm=f*ipd/span} else {mm=nil}
            return Sample(relative:lastRelative,millimetres:mm,usedPupils:true)
        }
        // An axis-aligned detector box changes width during roll and pitch.
        // Missing paired landmarks are missing distance evidence: hold, never
        // manufacture approach/retreat from the box. The box still drives x/y.
        _=fallbackWidth
        return Sample(relative:lastRelative,millimetres:nil,usedPupils:false)
    }
}

/// Reuses the shipped blink detector's0.65 open ratio, bilateral and immediate.
/// Missing/closed geometry cannot update pose or teach a distance reference.
struct PoseEyeMeasurementGate {
    private var left:[Double]=[],right:[Double]=[]
    mutating func accept(_ apertures:[Double])->Bool {
        guard apertures.count==2,apertures.allSatisfy({$0.isFinite && $0>0}) else{return false}
        if !left.isEmpty {
            let l=left.sorted()[left.count*3/4],r=right.sorted()[right.count*3/4]
            guard apertures[0]>=0.65*l,apertures[1]>=0.65*r else{return false}
        }
        left.append(apertures[0]);right.append(apertures[1])
        if left.count>121 {left.removeFirst();right.removeFirst()}
        return true
    }
}

///192d D1 continuous backlash followed by one exact critically damped step.
/// Noise bands and fixed taus are explicit measured inputs, never mode switches.
struct PoseBacklashFollow {
    let bands:[Double],taus:[Double]
    private var held:[Double]?,position:[Double]?,velocity:[Double]
    private var previousTime:Double?
    init(bands:[Double],taus:[Double]) {
        precondition(bands.count==taus.count && !bands.isEmpty)
        precondition(bands.allSatisfy{$0.isFinite && $0>=0} && taus.allSatisfy{$0.isFinite && $0>0})
        self.bands=bands;self.taus=taus;velocity=Array(repeating:0,count:bands.count)
    }
    mutating func hold(at t:Double) {if previousTime != nil {previousTime=t};velocity=Array(repeating:0,count:bands.count)}
    mutating func reset() {held=nil;position=nil;previousTime=nil;velocity=Array(repeating:0,count:bands.count)}
    mutating func accept(_ filtered:[Double],at t:Double,heldChannels:Set<Int>=[])->[Double] {
        guard filtered.count==bands.count,filtered.allSatisfy({$0.isFinite}),t.isFinite else {return position ?? Array(repeating:0,count:bands.count)}
        guard var target=held,var x=position,let pt=previousTime else {held=filtered;position=filtered;previousTime=t;return filtered}
        guard t>pt else {return x}
        let dt=t-pt
        for i in x.indices {
            if heldChannels.contains(i) {velocity[i]=0;continue}
            let e=filtered[i]-target[i]
            target[i]+=(e<0 ? -1:1)*max(0,abs(e)-bands[i])
            let omega=1/taus[i],d=x[i]-target[i],c=velocity[i]+omega*d,decay=exp(-omega*dt)
            x[i]=target[i]+(d+c*dt)*decay
            velocity[i]=(velocity[i]-omega*c*dt)*decay
        }
        held=target;position=x;previousTime=t;return x
    }
}

/// Startup noise estimate from33 filtered samples (same25% variance uncertainty
/// sample budget as the former estimator). Detrend each channel before measuring
/// its robust MAD envelope, so a slow coherent lean is not learned as noise.
/// Provisional online calibration, not a labeled owner still-head segment.
struct PoseNoiseCalibration {
    private var samples:[[Double]]=[]
    private(set) var bands:[Double]?
    mutating func interrupt() {if bands==nil {samples=[]}}
    mutating func observe(_ x:[Double]) {
        guard bands==nil,x.count==6,x.allSatisfy({$0.isFinite}) else{return}
        samples.append(x);guard samples.count==33 else{return}
        func median(_ a:[Double])->Double {let b=a.sorted();return b[b.count/2]}
        bands=(0..<6).map {j in
            let ys=samples.map{$0[j]},mid=16.0
            let mean=ys.reduce(0,+)/33
            let slope=ys.enumerated().reduce(0.0){$0+(Double($1.offset)-mid)*($1.element-mean)}/2992
            let residual=ys.enumerated().map{$0.element-mean-slope*(Double($0.offset)-mid)}
            let m=median(residual)
            return 3*median(residual.map{abs($0-m)})/0.6744897501960817
        }
    }
}

/// Dimensionless anatomy consistency, not motion rejection. The shipped33sample
/// statistical budget and3MAD envelope learn ratios that uniform scaling cannot change.
private struct PoseDistanceRatioCalibration {
    private var samples:[[Double]]=[]
    private var centres:[Double]?,bands:[Double]?
    var calibrated:Bool {centres != nil}
    mutating func accept(pupils:[Double],eyeGeometry:[Double],eyeWidths:[Double],yaw:Double,pitch:Double)->Bool {
        guard pupils.count==4,eyeGeometry.count==4,eyeWidths.count==2,
              (pupils+eyeGeometry+eyeWidths).allSatisfy({$0.isFinite}),eyeWidths.allSatisfy({$0>0}) else {return false}
        let width=(eyeWidths[0]+eyeWidths[1])/2
        let ratios=[hypot(pupils[2]-pupils[0],pupils[3]-pupils[1])/width,
                    hypot(eyeGeometry[2]-eyeGeometry[0],eyeGeometry[3]-eyeGeometry[1])/width]
        guard ratios.allSatisfy({$0.isFinite && $0>0}) else{return false}
        // Orthographic projection of a rigid face plane has singular values1
        // and |normal.z|. A ratio of two planar lengths can change only within
        // [ratio*s,ratio/s]. Roll and uniform real distance scaling cancel.
        let foreshortening=abs(cos(yaw)*cos(pitch))
        guard foreshortening.isFinite,foreshortening>Double.ulpOfOne.squareRoot() else{return false}
        let bounds: [Double] = ratios.flatMap { ratio -> [Double] in
            [ratio * foreshortening, ratio / foreshortening]
        }
        if let centres, let bands {
            return (0..<2).allSatisfy { j -> Bool in
                let lowerIndex: Int = j * 2
                let upperIndex: Int = lowerIndex + 1
                let lowerLimit: Double = centres[lowerIndex] - bands[lowerIndex]
                let upperLimit: Double = centres[upperIndex] + bands[upperIndex]
                let reachesLower: Bool = bounds[upperIndex] >= lowerLimit
                return reachesLower && bounds[lowerIndex] <= upperLimit
            }
        }
        samples.append(bounds)
        if samples.count==33 {
            func median(_ xs:[Double])->Double {xs.sorted()[xs.count/2]}
            centres=(0..<4).map{j in median(samples.map{$0[j]})}
            bands=(0..<4).map{j in let c=centres![j];return max(3*median(samples.map{abs($0[j]-c)})/0.6744897501960817,abs(c)*Double.ulpOfOne.squareRoot())}
        }
        return true
    }
}

/// Pupil and outline-centre routes retain independent anatomy calibrations,
/// just as PupilDistanceScale retains independent references for these sensors.
struct PoseDistanceConsistency {
    private var pupil=PoseDistanceRatioCalibration(),eye=PoseDistanceRatioCalibration()
    var calibrated:Bool {pupil.calibrated || eye.calibrated}
    func ready(for kind:String)->Bool {kind=="pupil" ? pupil.calibrated:(kind=="eye" && eye.calibrated)}
    mutating func accept(pupils:[Double],eyeGeometry:[Double],eyeWidths:[Double],yaw:Double,pitch:Double,landmarkKind:String="pupil")->Bool {
        if landmarkKind=="pupil" {return pupil.accept(pupils:pupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch)}
        if landmarkKind=="eye" {return eye.accept(pupils:pupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch)}
        return false
    }
}
