import Foundation

/// Structural invalidity is independent of lighting or a confidence threshold.
/// Semantic conditions (dark room, hand, glare) require measured frame evidence.
enum PoseMeasurementValidity {
    /// Rectangle pose has measured angles/box but makes no pupil, gaze or eyelid claim.
    static func rectangleReason(faceCount:Int,angles:[Double],box:CGRect)->Int {
        guard faceCount==1 else {return 1}
        guard angles.count==3 else {return 2}
        guard angles.allSatisfy({$0.isFinite}),box.minX.isFinite,box.minY.isFinite,
              box.width.isFinite,box.height.isFinite,box.width>0,box.height>0 else {return 3}
        return 0
    }
    //0 valid structure;1 missing/ambiguous face;2 absent landmarks/pose;3 nonfinite.
    static func reason(faceCount:Int,landmarkFaceCount:Int,angles:[Double],box:CGRect,
                       pupils:[Double],landmarkConfidence:Double)->Int {
        guard faceCount==1,landmarkFaceCount==1 else{return 1}
        guard angles.count==3,pupils.count==4 else{return 2}
        guard angles.allSatisfy({$0.isFinite}),pupils.allSatisfy({$0.isFinite}),
              landmarkConfidence.isFinite,landmarkConfidence>0,
              box.minX.isFinite,box.minY.isFinite,box.width.isFinite,box.height.isFinite,
              box.width>0,box.height>0 else{return 3}
        return 0
    }
}
