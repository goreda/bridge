#!/usr/bin/env python3
"""Compile actual helper and verbatim session methods with explicit boundary fakes.
Linux checks algorithm/API control flow, never FFmpeg/seek/Metal integration.
Exit 77 is NOT_RUN. Run from repository root with python3 Tests/GorAVFacade/chapter-real-source-test.py.
"""
from pathlib import Path
import os,shutil,subprocess,tempfile,sys
R=Path(__file__).resolve().parents[2]
sw=os.environ.get('SWIFTC','swiftc')
if not shutil.which(sw): print('NOT_RUN: swiftc unavailable');sys.exit(77)
session=R/'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift'
s=session.read_text();start=s.index('    // BEGIN chapter-navigation API');end=s.index('    // END chapter-navigation API',start)
methods=s[start:end]
prefix='''import Foundation
public struct ActiveMediaInventoryIdentity: Equatable { var revision: Int }
struct MediaInventory { var chapters: [ChapterNavigationEntry] }
public struct ActiveMediaInventorySnapshot { var identity: ActiveMediaInventoryIdentity; var inventory: MediaInventory }
enum EmbeddedRefusal: Error { case seekUnavailable(String) }
final class FakeDecoder {
 var receipt: ActiveMediaInventorySnapshot?
 func activeMediaInventory(session: Int) -> ActiveMediaInventorySnapshot? { receipt }
}
struct FakeTracker {
 var position: Double? = 15
 mutating func read(clockNow: Double, durationSeconds: Double?) -> Double? { position }
}
@MainActor final class SessionBoundary {
 var tornDown=false, fenced=false, preparedOperation=false
 var preparedShot: Int? = nil
 var plane=PlayerControlPlane()
 var decoder: FakeDecoder? = FakeDecoder()
 var session: Int? = 1
 var tracker=FakeTracker()
 var durationSeconds: Double? = 100
 var seekCounter: UInt64 = 0
 var seeks=[Double]()
 var outcome=0
 func trackerClockNow() -> Double { 1 }
 init() { _=plane.apply(.beginLoad);_=plane.apply(.loadReady);_=plane.apply(.play) }
 func seek(toSeconds seconds: Double) async throws {
  seeks.append(seconds);seekCounter &+= 1
  switch outcome {
  case 1: throw EmbeddedRefusal.seekUnavailable("boundary refused")
  case 2: _=plane.apply(.beginSeek);_=plane.apply(.seekRequiresClose)
  case 3: tornDown=true
  case 4: decoder=FakeDecoder()
  case 5: seekCounter &+= 1
  default: break
  }
 }
'''
suffix='''
}
func require(_ value: Bool, _ message: String) { precondition(value, message) }
func refused(_ body: () throws -> Void) { do {try body();preconditionFailure("expected refusal")} catch {} }
@main struct Tests {
 @MainActor static func main() async throws {
  let entries=[ChapterNavigationEntry(index:0,startSeconds:0,endSeconds:10),ChapterNavigationEntry(index:1,startSeconds:10,endSeconds:20),ChapterNavigationEntry(index:2,startSeconds:20,endSeconds:30)]
  func target(_ p:Double?,_ d:ChapterDirection) throws -> Int { try ChapterNavigation.target(entries:entries,position:p,direction:d).index }
  require(try target(15,.next)==2,"next");require(try target(15,.previous)==0,"previous")
  require(try target(10,.next)==2,"exact boundary next");require(try target(10,.previous)==0,"exact boundary previous")
  refused {_ = try target(0,.previous)};refused {_ = try target(25,.next)}
  refused {_ = try target(nil,.next)};refused {_ = try target(.nan,.next)};refused {_ = try target(-1,.next)}
  for bad in [[ChapterNavigationEntry](),[entries[1],entries[0]],[entries[0],entries[0]],[ChapterNavigationEntry(index:-1,startSeconds:0,endSeconds:1)],[ChapterNavigationEntry(index:0,startSeconds:2,endSeconds:1)],[ChapterNavigationEntry(index:0,startSeconds:.infinity,endSeconds:.infinity)],[ChapterNavigationEntry(index:0,startSeconds:Double.greatestFiniteMagnitude,endSeconds:Double.greatestFiniteMagnitude)]] {
   refused {_ = try ChapterNavigation.target(entries:bad,position:1,direction:.next)}
  }
  let shifted=[ChapterNavigationEntry(index:4,startSeconds:5,endSeconds:9)]
  require(try ChapterNavigation.target(entries:shifted,position:0,direction:.next).index==4,"before first")
  refused {_ = try ChapterNavigation.target(entries:shifted,position:0,direction:.previous)}
  let identity=ActiveMediaInventoryIdentity(revision:1)
  func make() -> SessionBoundary {
   let s=SessionBoundary();s.decoder!.receipt=ActiveMediaInventorySnapshot(identity:identity,inventory:MediaInventory(chapters:entries));return s
  }
  let s=make();let result=try await s.navigateChapter(.next,expected:identity)
  require(result==20 && s.seeks == [20],"real method dispatches exact target")
  let paused=make();_=paused.plane.apply(.pause)
  _ = try await paused.navigateChapter(.previous,expected:identity)
  require(paused.seeks == [0] && paused.plane.state == .paused,"paused preserved by boundary")
  for kind in 0..<7 {
   let t=make()
   if kind==0 {t.fenced=true};if kind==1 {t.tornDown=true};if kind==2 {t.preparedOperation=true};if kind==3 {t.preparedShot=1};if kind==4 {t.decoder!.receipt=nil};if kind==5 {t.session=nil}
   var didRefuse=false
   do {_ = try await t.navigateChapter(.next,expected:kind==6 ? ActiveMediaInventoryIdentity(revision:2) : identity)}catch{didRefuse=true}
   require(didRefuse && t.seeks.isEmpty,"pre-seek fence")
  }
  for outcome in 1...5 {
   let t=make();t.outcome=outcome;var didRefuse=false
   do {_ = try await t.navigateChapter(.next,expected:identity)}catch{didRefuse=true}
   require(didRefuse,"post-seek failure must not succeed")
  }
  print("PASS actual ChapterNavigation.swift + verbatim session chapter methods; decoder/seek boundaries FAKE; native integration NOT_RUN")
 }
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'SessionTests.swift').write_text(prefix+methods+suffix)
 cmd=[sw,'-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library',str(R/'Packages/gorav/Sources/GorAVPlaybackCore/ChapterNavigation.swift'),str(R/'Packages/gorav/Sources/GorAVPlaybackCore/PlayerControlPlane.swift'),str(p/'SessionTests.swift'),'-o',str(p/'tests')]
 print('Compiling actual production helper, actual control plane and extracted session chapter methods',flush=True)
 subprocess.run(cmd,check=True);subprocess.run([str(p/'tests')],check=True)
