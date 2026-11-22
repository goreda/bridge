import AppKit

/// Overlay gaze borrows head/blink/ambient frames; it never owns camera hardware.
/// Closing, hiding or losing active use clears its callback and timer.
final class GazeCrosshairController {
    private weak var view:NSView?
    private weak var marker:CATextLayer?
    private var status:CATextLayer?
    private var timer:Timer?
    private var model=BinocularGazeCalibration()
    private var point:CGPoint?
    private var lastFrame=0.0
    private var geometry=CGRect.zero
    private func screenGeometry(_ view:NSView)->CGRect {view.window?.convertToScreen(view.convert(view.bounds,to:nil)) ?? view.bounds}
    // ThreeDCornerTuneView.shared is the sole gaze consumer of the single callback slot.
    private var ownsCamera=false
    private(set) var hitFrame=CGRect.zero
    var active:Bool {ownsCamera}

    func bind(view:NSView,marker:CATextLayer) {
        self.view=view;self.marker=marker
        if status?.superlayer !== view.layer {
            status?.removeFromSuperlayer()
            let text=CATextLayer();text.font=PhotonFont.ctFace();text.fontSize=PhotonFont.chromeSize
            text.foregroundColor=NSColor.white.cgColor;text.alignmentMode = .center
            text.contentsScale=view.window?.backingScaleFactor ?? 2
            view.layer?.addSublayer(text);status=text
        }
        render()
    }
    func toggle() {
        if ownsCamera {stop();return}
        guard let view, view.window != nil, !view.isHiddenOrHasHiddenAncestor, NSApp.isActive, HeadTracker.shared.isRequested else { return }
        geometry=screenGeometry(view);point=nil;model.start();ownsCamera=true
        HeadTracker.shared.onGazeUpdate = { [weak self] sample in
            guard let self,self.ownsCamera else{return}
            let now=CACurrentMediaTime();self.lastFrame=now
            self.point=self.model.feed(sample,now:now);self.render()
        }
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else{return}
            guard let view=self.view, view.window != nil, !view.isHiddenOrHasHiddenAncestor, NSApp.isActive, HeadTracker.shared.isRequested else {self.stop();return}
            if CACurrentMediaTime()-self.lastFrame>0.2 {self.point=nil;_=self.model.feed(nil,now:CACurrentMediaTime())}
            self.render()
        }
        render()
    }
    func stop() {
        timer?.invalidate();timer=nil
        if ownsCamera {HeadTracker.shared.onGazeUpdate=nil}
        ownsCamera=false;point=nil;model.stop();render()
    }
    private func render() {
        guard let view,let marker else{return}
        if ownsCamera,screenGeometry(view) != geometry {
            // Screen coordinates learned in another geometry are not reusable.
            geometry=screenGeometry(view);point=nil;model.start()
        }
        let pos:CGPoint,message:String,visible:Bool
        switch model.state {
        case .off:pos=CGPoint(x:0.5,y:0.5);message="";visible=true
        case .calibrating(let i):
            pos=BinocularGazeCalibration.targets[i];visible=true
            message="Look + \(i+1)/5"
        case .tracking:
            pos=point ?? CGPoint(x:0.5,y:0.5);visible=point != nil
            message=visible ? "Gaze":"Hold still"
        case .failed:
            pos=CGPoint(x:0.5,y:0.5);visible=true;message="Retry +"
        }
        let w=PhotonFont.chromeCharW,h=PhotonFont.chromeLineH
        hitFrame=CGRect(x:pos.x*view.bounds.width-w/2,y:pos.y*view.bounds.height-h/2,width:w,height:h)
        CATransaction.begin();CATransaction.setDisableActions(true)
        marker.frame=hitFrame;marker.isHidden = !visible
        let text=ownsCamera && !HeadTracker.shared.isRunning ? "Camera...":message
        status?.string=text
        let statusScale=min(1,max(0,view.bounds.width-8)/max(1,CGFloat(text.count)*PhotonFont.chromeCharW))
        status?.fontSize=PhotonFont.chromeSize*statusScale
        status?.frame=CGRect(x:0,y:max(0,view.bounds.height*0.08),width:view.bounds.width,height:h*statusScale)
        status?.isHidden=message.isEmpty && !ownsCamera
        CATransaction.commit()
    }
}
