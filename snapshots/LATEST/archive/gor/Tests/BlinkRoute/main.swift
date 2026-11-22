// Tests/BlinkRoute/main.swift - regression checks against the extracted production
// blink-control route (see run.sh). Deterministic: explicit timestamps, no camera,
// no wall clock. Same-file concat keeps production `private` members visible.
extension VR180ControllerProbe {
    static func check(_ name: String, _ cond: Bool, _ fails: inout Int) {
        print(cond ? "ok   " : "FAIL ", name)
        if !cond { fails += 1 }
    }
    static func ipcCount(_ ipc: [String], _ needle: String) -> Int { ipc.filter { $0.contains(needle) }.count }

    @discardableResult
    static func runAll(mode: String) -> Int {
        var fails = 0
        let T = HeadTracker.shared
        UserDefaults.standard.set(true, forKey: VR180ControllerProbe.blinkControlDefaultsKey) // explicit opt-in for route tests; production default stays OFF

        if mode == "simpose" {
            // GOR_VR_SIM_POSE=1: the head leg runs a synthetic pose and owns NO camera
            // consumer; its stop path must never release the blink leg's real consumer.
        GeomTrace.resetSpy(); T.resetSpy()
            var ipc: [String] = []
            let p = VR180ControllerProbe(ipcCommand: { ipc.append($0) })
            p.loadedVideoActive = true
            p.playbackActive = true
            p.noteManualEnabled(true)
            check("M1 sim pose: head leg active with no camera consumer of its own", p.headTrackingCameraActive && T.simulatedPoseRunning && T.startCalls == 1, &fails)
            check("M1 sim pose: blink owns the only real consumer", p.blinkCameraActive && T.consumers == 1 && T.isRequested, &fails)
            p.playbackActive = false   // pause intent
            check("M2 pause: sim head leg stays active without releasing a consumer", p.headTrackingCameraActive && T.simulatedPoseRunning && T.stopCalls == 0, &fails)
            check("M2 pause: blink consumer not stolen", p.blinkCameraActive && T.consumers == 1 && T.isRequested, &fails)
            p.playbackActive = true
            p.setHeadTrackingEnabled(false)
            check("M3 head OFF: blink consumer still not stolen", p.blinkCameraActive && T.consumers == 1 && T.isRequested && T.stopCalls == 0, &fails)
            p.setVRModeEnabled(false); p.loadedVideoActive = false; p.setHeadTrackingEnabled(false)
            check("M4 VR exit: every real consumer released exactly once", T.consumers == 0 && !T.isRequested && !p.blinkCameraActive && !T.simulatedPoseRunning && T.stopCalls == 1, &fails)
            return fails
        }

        if mode == "nocam" {
            // Test-owned camera opt-out: blink state and callbacks still install,
            // but no camera consumer is ever started.
            GeomTrace.resetSpy(); T.resetSpy()
            var ipc: [String] = []
            let p = VR180ControllerProbe(ipcCommand: { ipc.append($0) })
            p.loadedVideoActive = true
            p.noteManualEnabled(true)
            check("N1 nocam: blink state still turns on", T.blinkLogEnabled, &fails)
            check("N1 nocam: callbacks still installed", T.onEyeClosure != nil && T.onEyeSeek != nil, &fails)
            check("N1 nocam: no camera consumer started", T.consumers == 0 && !T.isRequested && !p.blinkCameraActive, &fails)
            return fails
        }

        // Default automatic VR entry installs blink without the manual seam.
        GeomTrace.resetSpy(); T.resetSpy()
        let auto = VR180ControllerProbe(ipcCommand: { _ in })
        auto.loadedVideoActive = true
        auto.setVRModeEnabled(true)
        check("D0 fresh auto VR entry defaults blink ON", T.blinkLogEnabled && auto.blinkCameraActive, &fails)
        auto.setVRModeEnabled(false)

        // S0 saved head preference OFF at startup: manual VR ON installs blink as the ONLY consumer.
        VR180ControllerProbe.headTrackingAutoStartAllowed = false
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc0: [String] = []
        let p0 = VR180ControllerProbe(ipcCommand: { ipc0.append($0) })
        p0.loadedVideoActive = true
        p0.playbackActive = true
        p0.noteManualEnabled(true)
        check("S0 head pref OFF: VR on, head tracking stays off", p0.vrModeEnabled && !p0.headTrackingEnabled, &fails)
        check("S0 head pref OFF: no pose consumer or callback", !p0.headTrackingCameraActive && T.onPoseUpdate == nil, &fails)
        check("S0 head pref OFF: blink is the only camera consumer", p0.blinkCameraActive && T.consumers == 1 && T.isRequested, &fails)
        VR180ControllerProbe.headTrackingAutoStartAllowed = true

        // S1 explicit manual VR entry (shift+v / menu toggle) defaults blink ON, one OSD.
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc: [String] = []
        let p = VR180ControllerProbe(ipcCommand: { ipc.append($0) })
        p.loadedVideoActive = true
        p.noteManualEnabled(true)
        check("S1 manual entry enables VR", p.vrModeEnabled && ScreenCaptureEngine.shared.vrModeActive, &fails)
        check("S1 manual entry defaults blink ON", T.blinkLogEnabled, &fails)
        check("S1 exactly one 'blink control on' OSD", ipcCount(ipc, "blink control on") == 1, &fails)
        check("S1 VR enable IPC sent", ipc.contains("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-enabled\",\"true\"]}"), &fails)
        check("S1 closure/seek callbacks installed, command slot clear", T.onEyeClosure != nil && T.onEyeSeek != nil && T.onBlinkControl == nil, &fails)
        check("S1 both camera consumers started (loaded paused file)", p.blinkCameraActive && T.consumers == 2 && T.isRequested, &fails)

        // S2 idempotent manual re-entry: no repeated OSD, no state churn.
        p.noteManualEnabled(true)
        check("S2 repeated manual entry: still exactly one OSD", ipcCount(ipc, "blink control on") == 1, &fails)
        check("S2 repeated manual entry: blink still on", T.blinkLogEnabled, &fails)

        // S3 auto-detect / file re-entry preserves the chosen OFF state.
        let offRet = p.toggleBlinkLog()
        check("S3 manual blink OFF honored", !offRet && !T.blinkLogEnabled, &fails)
        check("S3 blink OFF released its consumer", !p.blinkCameraActive, &fails)
        p.setVRModeEnabled(false)
        ipc.removeAll()
        p.setVRModeEnabled(true)   // automatic re-entry: no manual seam involved
        check("S3 auto re-entry preserves chosen blink OFF", !T.blinkLogEnabled, &fails)
        check("S3 auto re-entry fires no 'blink control on' OSD", ipcCount(ipc, "blink control on") == 0, &fails)
        check("S3 auto re-entry starts no blink consumer", !p.blinkCameraActive, &fails)

        // S3b chosen ON survives VR off and is restored by automatic re-entry (no OSD).
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc3b: [String] = []
        let p3b = VR180ControllerProbe(ipcCommand: { ipc3b.append($0) })
        p3b.loadedVideoActive = true
        p3b.noteManualEnabled(true)
        p3b.setVRModeEnabled(false)
        check("S3b projection off preserves independent blink", T.blinkLogEnabled && T.onEyeClosure != nil && p3b.blinkControlPreferred, &fails)
        ipc3b.removeAll()
        p3b.setVRModeEnabled(true)   // automatic re-entry, no manual seam
        check("S3b auto re-entry restores the chosen ON session", T.blinkLogEnabled && T.onEyeClosure != nil && p3b.blinkCameraActive && T.consumers == 2, &fails)
        check("S3b auto re-entry shows no OSD", ipcCount(ipc3b, "blink control on") == 0, &fails)

        // S3c explicit saved OFF survives manual re-entry and a fresh controller.
        _ = p3b.toggleBlinkLog()     // chosen OFF
        p3b.setVRModeEnabled(false)
        ipc3b.removeAll()
        p3b.noteManualEnabled(true)
        check("S3c manual entry respects saved blink OFF", !T.blinkLogEnabled && !p3b.blinkControlPreferred, &fails)
        check("S3c saved OFF shows no ON OSD", ipcCount(ipc3b, "blink control on") == 0, &fails)
        let fresh = VR180ControllerProbe(ipcCommand: { _ in })
        check("S3c fresh controller retains saved OFF", !fresh.blinkControlPreferred, &fails)
        check("S3c missing cross-eye preference defaults ON", fresh.swapEyes, &fails)
        UserDefaults.standard.set(false, forKey: VR180ControllerProbe.swapEyesDefaultsKey)
        let savedCrossOff = VR180ControllerProbe(ipcCommand: { _ in })
        check("S3c saved cross-eye OFF remains OFF", !savedCrossOff.swapEyes, &fails)

        // S4 pause survival: both consumers read loadedVideoActive, not playbackActive.
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc4: [String] = []
        let p4 = VR180ControllerProbe(ipcCommand: { ipc4.append($0) })
        p4.loadedVideoActive = true
        p4.playbackActive = true
        p4.noteManualEnabled(true)
        check("S4 playing: head + blink consumers both run", p4.blinkCameraActive && p4.headTrackingCameraActive && T.consumers == 2, &fails)
        p4.playbackActive = false   // pause intent
        check("S4 pause keeps the head-motion consumer", p4.headTrackingCameraActive, &fails)
        check("S4 pause keeps both consumers alive", p4.blinkCameraActive && T.consumers == 2 && T.isRequested, &fails)
        p4.playbackActive = true    // resume
        check("S4 resume restores the head-motion consumer", p4.headTrackingCameraActive && T.consumers == 2, &fails)

        p4.playbackActive = false
        ipc4.removeAll()
        T.onPoseUpdate?(HeadPose(yaw:0.2,pitch:0.1))
        check("S4 actual applyHeadPose sends orientation while paused", ipcCount(ipc4,"vr180-look-set-orientation")==1, &fails)
        p4.loadedVideoActive=false
        ipc4.removeAll()
        T.onPoseUpdate?(HeadPose(yaw:0.3))
        check("S4 no loaded video stops pose and blink callbacks", ipc4.isEmpty && T.onPoseUpdate==nil && T.onEyeSeek==nil && T.consumers==0, &fails)
        p4.loadedVideoActive=true
        check("S4 new file rearms blink with a new session", T.blinkLogEnabled && T.onEyeSeek != nil, &fails)

        // S5 head OFF + blink ON keeps the camera; both OFF releases it.
        p4.setHeadTrackingEnabled(false)
        check("S5 head OFF + blink ON keeps camera", p4.blinkCameraActive && T.consumers == 1 && T.isRequested, &fails)
        _ = p4.toggleBlinkLog()
        check("S5 blink OFF + head OFF releases camera", !p4.blinkCameraActive && T.consumers == 0 && !T.isRequested, &fails)

        // S6 exact lids IPC through the actually-installed production callback.
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc6: [String] = []
        let p6 = VR180ControllerProbe(ipcCommand: { ipc6.append($0) })
        p6.loadedVideoActive = true
        p6.noteManualEnabled(true)
        ipc6.removeAll()
        T.onEyeClosure?(0.1, 0.2, false)
        let lidsLit = "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-lids\",\"0.1\",\"0.2\",\"false\"]}"
        check("S6 route format pinned", BlinkCommandRoute.lidsIPC(0.1, 0.2, false) == lidsLit, &fails)
        check("S6 installed closure callback emits exact lids IPC", ipc6 == [lidsLit], &fails)

        // S7 VR exit clears callbacks, zeroes lids, releases the blink consumer, flushes once.
        var softBlink: [Double] = []
        p6.onSoftVideoBlink = { softBlink.append($0) }
        ipc6.removeAll()
        p6.setVRModeEnabled(false)
        check("projection exit preserves independently enabled blink", T.blinkLogEnabled && T.onEyeClosure != nil, &fails)
        p6.loadedVideoActive = false
        p6.setHeadTrackingEnabled(false)
        check("S7 exit clears closure/seek callbacks", T.onEyeClosure == nil && T.onEyeSeek == nil && T.onBlinkIndicator == nil, &fails)
        let clearedLit = "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-lids\",\"0.0\",\"0.0\",\"true\"]}"
        check("S7 lidsClearedIPC constant pinned", BlinkCommandRoute.lidsClearedIPC == clearedLit, &fails)
        check("S7 exit zeroes shader lids via IPC", ipc6.contains(clearedLit), &fails)
        check("S7 exit releases every camera consumer", T.consumers == 0 && !T.isRequested && !p6.blinkCameraActive, &fails)
        check("S7 exit ends the measurement session with one flush", !T.blinkLogEnabled && T.flushCalls.count == 1, &fails)
        check("S7 exit pulses soft video blink", softBlink.isEmpty, &fails)

        // S8 diagnostic-storage failure: control is decoupled from the measurement log.
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc8: [String] = []
        let p8 = VR180ControllerProbe(ipcCommand: { ipc8.append($0) })
        p8.loadedVideoActive = true
        p8.noteManualEnabled(true)
        check("S8 ON registers a diagnostic failure handler", GeomTrace.blinkLogHandler != nil && GeomTrace.beginBlinkLogSessions == ["probe-session"], &fails)
        ipc8.removeAll()
        GeomTrace.blinkLogHandler?("stale-session", "blink measurement stopped: log full (8 MiB), existing samples preserved")
        check("S8 stale session failure: zero effects, no OSD", T.blinkLogEnabled && T.onEyeClosure != nil && T.flushCalls.isEmpty && T.stopIfCurrentCalls.isEmpty && ipc8.isEmpty, &fails)
        GeomTrace.blinkLogHandler?("probe-session", "blink measurement stopped: log full (8 MiB), existing samples preserved")
        check("S8 current failure: session, callbacks, consumer, choice retained", T.blinkLogEnabled && T.onEyeClosure != nil && p8.blinkCameraActive && T.consumers == 2 && p8.blinkControlPreferred, &fails)
        check("S8 current failure: no stop, no flush, no session close", T.stopIfCurrentCalls.isEmpty && T.flushCalls.isEmpty, &fails)
        check("S8 one honest OSD: measurement stopped, control on", ipcCount(ipc8, "log full (8 MiB)") == 1 && ipcCount(ipc8, "blink control stays on") == 1, &fails)
        ipc8.removeAll()
        T.onEyeClosure?(0.2, 0.3, true)   // uncertain fail-open still reaches the shader
        T.onEyeSeek?(60)                  // seek control still dispatches
        check("S8 control live after failure: uncertain lids + seek IPC", ipc8.contains(BlinkCommandRoute.lidsIPC(0.2, 0.3, true)) && ipc8.contains("{\"command\":[\"seek\",60,\"relative\"]}"), &fails)
        p8.setVRModeEnabled(false); p8.loadedVideoActive = false; p8.setHeadTrackingEnabled(false) // unloading video releases consumers
        check("S8 normal VR exit after failure stays safe", !T.blinkLogEnabled && T.onEyeClosure == nil && T.consumers == 0 && T.flushCalls.count == 1 && ipc8.contains(clearedLit), &fails)
        _ = p8   // keep the weak-self target alive through the handler invocations

        // Current map: bilateral double +60, Cmd double -60, nothing else.
        GeomTrace.resetSpy();T.resetSpy()
        var ipc9:[String]=[]
        let p9=VR180ControllerProbe(ipcCommand:{ipc9.append($0)})
        p9.loadedVideoActive=true;p9.noteManualEnabled(true);ipc9=[]
        var gestures=EyeGestureCommands();var t=0.0;let dt=1.0/30
        func feed(_ l:Double,_ r:Double,_ frames:Int)->[Int] {
            var out:[Int]=[]
            for _ in 0..<frames {t+=dt;if let v=gestures.feed(t:t,left:l,right:r,reliable:true){out.append(v)}}
            return out
        }
        _=feed(1,1,20)
        var commands:[Int]=[]
        for _ in 0..<5 {commands+=feed(0.05,0.05,3);commands+=feed(1,1,4)}
        check("S9 five serial blinks make two independent +60 pairs only",commands == [60,60],&fails)
        T.onEyeSeek?(60)
        check("S9 double forward sends +60",ipc9 == ["{\"command\":[\"seek\",60,\"relative\"]}"],&fails)
        NSEvent.modifierFlags=[.command];T.onEyeSeek?(60);NSEvent.modifierFlags=[]
        check("S9 Cmd double sends -60",ipc9.last == "{\"command\":[\"seek\",-60,\"relative\"]}",&fails)
        for pair in [(0.05,1.0),(1.0,0.05),(0.05,0.05)] {
            gestures.reset();t=0;_=feed(1,1,20)
            commands=feed(pair.0,pair.1,120)+feed(1,1,10)
            check("S9 unilateral/bilateral long holds have no command",commands.isEmpty,&fails)
        }
        for gap in [0.08,0.125,0.20,0.25] {
            var slow=EyeGestureCommands();var st=0.0;var result:[Int]=[]
            func sf(_ l:Double,_ r:Double,_ n:Int) {
                for _ in 0..<n {st+=gap;if let v=slow.feed(t:st,left:l,right:r,reliable:true,frameAge:0.02){result.append(v)}}
            }
            sf(1,1,20)
            for _ in 0..<4 {sf(0.05,0.05,1);sf(1,1,1)}
            check("S9 low fps double pairs at \(gap)s",result == [60,60],&fails)
            check("S9 stale frame cannot emit",slow.feed(t:st+gap,left:0.05,right:0.05,reliable:true,frameAge:0.5)==nil,&fails)
        }
        gestures.reset();t=0;_=feed(1,1,20)
        _=feed(0.05,0.05,3);_=feed(1,1,20)
        commands=feed(0.05,0.05,3)+feed(1,1,4)
        check("S9 slower intentional pair within 950ms is accepted",commands == [60],&fails)
        gestures.reset();t=0;_=feed(1,1,20)
        _=feed(0.05,0.05,3);_=gestures.feed(t:t+dt,left:nil,right:nil,reliable:false);t+=dt
        commands=feed(1,1,5)+feed(0.05,0.05,3)+feed(1,1,4)
        // Policy as of cc45c008 (2026-11-08, EyeGestureCommands.robust): up to toleratedMisses (2) fresh unreliable
        // frames between two blinks HOLD the series (comment: "a single dropped landmark frame between two blinks must
        // not erase the series"). The 2026-11-06 expectation here was that any uncertainty cancels. Both are measured.
        check("S9 one dropped frame between blinks keeps the pending double (robust policy)",commands == [60],&fails)
        gestures.reset();t=0;_=feed(1,1,20)
        _=feed(0.05,0.05,3)
        for _ in 0..<(EyeGestureCommands.toleratedMisses+1) {_=gestures.feed(t:t+dt,left:nil,right:nil,reliable:false);t+=dt}
        commands=feed(1,1,5)+feed(0.05,0.05,3)+feed(1,1,4)
        check("S9 more than toleratedMisses consecutive unreliable frames cancel a pending double",commands.isEmpty,&fails)

        // S10 unreliable frames fail open (actual IntentionalEyeClosure): no lid amount, ever.
        var closure = IntentionalEyeClosure()
        var ct = 0.0
        var maxAmount = 0.0
        for _ in 0..<12 { ct += dt; maxAmount = max(maxAmount, closure.feed(t: ct, left: 1.0, right: 1.0, reliable: true)) }
        for _ in 0..<10 { ct += dt; maxAmount = max(maxAmount, closure.feed(t: ct, left: 0.01, right: 0.01, reliable: false)) }
        check("S10 unreliable frames keep lids open", maxAmount == 0 && closure.amount == 0, &fails)

        // S11 VR-off guard: shift+e / menu with VR off explains itself instead of going dead.
        GeomTrace.resetSpy(); T.resetSpy()
        var ipc11: [String] = []
        let p11 = VR180ControllerProbe(ipcCommand: { ipc11.append($0) })
        let guardRet = p11.setBlinkControlEnabled(true)
        check("S11 VR/3D off does not block independent blink opt-in", !ipc11.contains(where: { $0.contains("turn 3d on") }) && T.blinkLogEnabled, &fails)

        // One 3D umbrella: a projection transition must not gate tools off while the master remains ON.
        T.resetSpy(); GeomTrace.resetSpy()
        var ipcUmbrella: [String] = []
        let umbrella = VR180ControllerProbe(ipcCommand: { ipcUmbrella.append($0) })
        umbrella.loadedVideoActive = true
        let umbrellaOn = umbrella.setBlinkControlEnabled(true)
        check("3D ON + projection OFF: blink camera consumer and closure IPC work", umbrellaOn && T.blinkLogEnabled, &fails)
        T.onEyeClosure?(0.8,0.7,false)
        check("3D umbrella sends measured per-eye closures to shader", ipcUmbrella.contains(BlinkCommandRoute.lidsIPC(0.8,0.7,false)), &fails)
        umbrella.setVRModeEnabled(false)
        check("3D OFF leaves independent blink enabled", T.blinkLogEnabled, &fails)
        umbrella.loadedVideoActive = false
        check("unloading video releases blink camera", !T.blinkLogEnabled && !umbrella.blinkCameraActive, &fails)

        // S12 actual BlinkControlDetector: deliberate closure and double blink still classify.
        var det = BlinkControlDetector()
        var dt2 = 0.0
        var events: [BlinkControlDetector.Event] = []
        func dfeed(_ l: Double, _ r: Double, _ frames: Int) {
            for _ in 0..<frames { dt2 += dt; if let e = det.feed(t: dt2, left: l, right: r) { events.append(e) } }
        }
        dfeed(1.0, 1.0, 15)                    // baseline + 0.35 s open arm
        dfeed(1.0, 1.0, 12)
        dfeed(0.05, 0.05, 15)                  // ~0.5 s closure -> deliberate
        dfeed(1.0, 1.0, 3)
        dfeed(0.05, 0.05, 3)                   // quick blink 1
        dfeed(1.0, 1.0, 5)
        dfeed(0.05, 0.05, 3)                   // quick blink 2 -> doubleBlink
        dfeed(1.0, 1.0, 5)
        check("S12 detector: deliberate, blink, then doubleBlink", events == [.deliberate, .blink, .doubleBlink], &fails)

        return fails
    }
}

let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "main"
let failures = VR180ControllerProbe.runAll(mode: arg)
print(failures == 0 ? "ALL OK (\(arg))" : "FAILURES (\(arg)): \(failures)")
exit(failures == 0 ? 0 : 1)
