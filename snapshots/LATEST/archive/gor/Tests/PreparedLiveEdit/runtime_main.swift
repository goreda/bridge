import Foundation
@main struct Harness {
 static func main() {
  let generation=RenderRevision()
  precondition(generation.update("A",now:0));let oldToken=generation.token
  precondition(!generation.ready(now:0.49) && generation.ready(now:0.5))
  precondition(!generation.update("A",now:0.2))
  generation.update("B",now:1);generation.update("A",now:2)
  precondition(!generation.isCurrent(oldToken),"ABA revived cancelled job")
  var committed=0
  precondition(!generation.commit(oldToken) {committed+=1})
  precondition(generation.commit(generation.token) {committed+=1} && committed==1)
  let fileA=RenderRevision.fileName(shot:3,key:"A"),fileB=RenderRevision.fileName(shot:3,key:"B")
  precondition(fileA != fileB && fileA.contains("559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd"))
  generation.invalidate();precondition(!generation.ready(now:10))
  print("PASS production token debounce,ABA,stale publication and SHA256 filename")
  let mode=ProcessInfo.processInfo.environment["TEST_MODE"] ?? "full_sbs"
  let output=ThreeDOutput(rawValue:mode)!
  SourceFormatChoice.mode=mode
  let fm=FileManager.default,root=DepthCachePaths.root,entry=root.appendingPathComponent("fixture")
  try! fm.createDirectory(at:entry,withIntermediateDirectories:true)
  func json(_ x:Any,_ url:URL) {try! JSONSerialization.data(withJSONObject:x).write(to:url,options:.atomic)}
  json(["cache_key":"fixture"],root.appendingPathComponent("current-film.json"))
  json(["shots":[[0,239],[240,479],[480,719]]],entry.appendingPathComponent("cuts.json"))
  json(["fps":24,"shots":(0..<3).map {["start_pts":Double($0*10),"end_pts":Double($0*10+10),"hfov_deg":52.0]}],entry.appendingPathComponent("fov_track.json"))
  for n in 0..<3 {
   try! Data([1,2,3]).write(to:entry.appendingPathComponent(String(format:"depth_shot_%05d.dzc",n)))
   try! Data([4]).write(to:entry.appendingPathComponent(String(format:"source_shot_%05d.mp4",n)))
   json(["depth_width":320,"depth_height":180,"source_width":320,"source_height":180],entry.appendingPathComponent(String(format:"depth_shot_%05d.json",n)))
  }
  var pos=1.0,commands:[String]=[]
  let film=root.appendingPathComponent("original.mp4"),id=FilmID(rawValue:"fixture")
  let coordinator=ThreeDRenderCoordinator(send:{commands.append($0)},mpvExecutable:{URL(fileURLWithPath:ProcessInfo.processInfo.environment["TEST_PLAYER"]!)},playhead:{pos},film:{film})
  func prefs(_ strength:Double,_ conv:Double=1.5) {
   json(["mode":mode,"depth_scale":strength,"convergence_m":conv],root.appendingPathComponent("render-prefs.json"))
   coordinator.preferencesDidChange()
  }
  func spin(_ seconds:Double) {let until=Date().addingTimeInterval(seconds);while Date()<until {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}}
  func loads()->[[Any]] {commands.compactMap {s in
   guard let row=(try? JSONSerialization.jsonObject(with:Data(s.utf8))) as? [String:Any],let cmd=row["command"] as? [Any],cmd.first as? String == "loadfile" else {return nil};return cmd
  }}
  MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.open(id,ThreeDEvidence()));ThreeDStore.shared.dispatch(.setOutput(output))}
  coordinator.applyStoreOutput(output,filmID:id);prefs(1);coordinator.start();spin(1.7)
  precondition(loads().count==1,commands.description)
  let old=URL(fileURLWithPath:loads()[0][1] as! String);let oldBytes=try! Data(contentsOf:old)
  let depth0=entry.appendingPathComponent("depth_shot_00000.dzc")
  try! fm.removeItem(at:depth0);spin(0.35)
  precondition(loads().count==1,"depth re-prepare dropped the last-good encoded picture")
  try! Data([1,2,3]).write(to:depth0)
  prefs(1.5);spin(0.15);prefs(1.75);spin(0.15);prefs(2.0);spin(1.4)
  precondition(loads().count==1,"parameter edits reloaded the media mid-shot")
  precondition(try! Data(contentsOf:old)==oldBytes,"last good overwritten")
  precondition(!loads().contains {($0[1] as? String)==film.path},"backTo2D during edit")
  print("PASS real coordinator rapid edits preserve playing bytes, no mid-shot load or2D flash")
  prefs(2.0,2.0);spin(1.0)
  precondition(loads().count==1,"convergence edit reloaded mid-shot")
  for walkingPTS in [2.5,4.0,5.5,7.0,8.5,9.9] {
   pos=walkingPTS;spin(0.3)
   precondition(loads().count==1,"replacement loaded inside the existing shot")
  }
  pos=10.05;spin(0.4)
  precondition(loads().count==2,"replacement did not swap at cut")
  let next=URL(fileURLWithPath:loads()[1][1] as! String)
  precondition((try! String(contentsOf:next)).contains("0.126"),"not newest strength")
  precondition((try! String(contentsOf:next)).contains("conv=2.0"),"not newest convergence")
  precondition((loads()[1][4] as! String).contains("rebase-start-time=no,audio-file="))
  print("PASS real coordinator next shot loads latest strength+convergence and film-time audio options")
  // One busy generation, followed by two immediate edits including ABA.
  RenderShotWriter.delay=0.8;prefs(1.25);spin(0.85);prefs(1.0);prefs(1.25);spin(1.7)
  precondition(RenderShotWriter.cancelledCount>0,"busy old generation was not cancelled")
  precondition(!loads().contains {($0[1] as? String)==film.path})
  print("PASS real coordinator generation cancellation including ABA; no stale2D publish")
  coordinator.applyStoreOutput(.off,filmID:id);SourceFormatChoice.mode="off";spin(0.3)
  precondition(loads().last?[1] as? String == film.path,"Off failed to recover original")
  print("PASS actual Off returns original mode=\(mode); GPU/VT/player boundaries mocked, not Mac proof")
 }
}
