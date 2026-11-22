#if canImport(AppKit)
import Foundation
import AppKit
import QuartzCore
import Vision
import XCTest
@testable import gor

/// Pixel witness, not a log assertion. Native NOT_RUN until Ops executes this test.
final class MultipleAudioRefusalPixelTests:XCTestCase {
 @MainActor func testRefusalSurvivesRoutineHUDAndIsActuallyRasterized() async throws {
  _=NSApplication.shared
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:700),styleMask:[.titled],backing:.buffered,defer:false)
  window.isReleasedWhenClosed=false
  defer {window.close()}
  let root=try XCTUnwrap(window.contentView);root.wantsLayer=true;root.layer?.backgroundColor=NSColor.black.cgColor
  let spine=SpineUI(frame:NSRect(x:0,y:0,width:80,height:700));root.addSubview(spine)
  window.makeKeyAndOrderFront(nil);spine.alphaValue=1
  let status=PlayerRouteStatus(requested:.gorav,active:.mpv,fallbackReason:"expected at most one audio stream, found 2")
  let line=try XCTUnwrap(status.refusalHUDLine)
  spine.setEngineRefusalHUD(line)
  spine.showPhotonHUD("sharp\tsharp status")
  spine.clearPhotonHUD()
  spine.showMPVOSD("routine temporary message",force:true)
  // Wait beyond the shared transient's default3s lifetime. No log is used as evidence.
  try await Task.sleep(nanoseconds:3_600_000_000)
  spine.layoutSubtreeIfNeeded();CATransaction.flush()
  let bitmap=try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in:root.bounds))
  let context=try XCTUnwrap(NSGraphicsContext(bitmapImageRep:bitmap))
  try XCTUnwrap(root.layer).render(in:context.cgContext)
  let cg=try XCTUnwrap(bitmap.cgImage)
  let image=NSImage(size:root.bounds.size);image.addRepresentation(bitmap)
  let attachment=XCTAttachment(image:image);attachment.name="retained-multiple-audio-refusal-pixels";attachment.lifetime = .keepAlways
  add(attachment)
  let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
  try VNImageRequestHandler(cgImage:cg).perform([request])
  let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:" ").lowercased()
  XCTAssertTrue(text.contains("gorav to mpv"),"rendered pixels must name the fallback")
  XCTAssertTrue(text.contains("multiple audio tracks"),"rendered pixels must show the actual reason")
  XCTAssertFalse(text.contains("expected_at_most"),"no internal parser token on screen")
  spine.setEngineRefusalHUD(nil)
  spine.layoutSubtreeIfNeeded();CATransaction.flush()
  func layers(_ layer:CALayer)->[CATextLayer] {(layer as? CATextLayer).map{[$0]} ?? (layer.sublayers ?? []).flatMap{layers($0)}}
  XCTAssertFalse(layers(try XCTUnwrap(root.layer)).contains{($0.string as? String)==line && $0.opacity>0})
 }
}
#endif
