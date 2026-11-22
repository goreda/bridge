import Foundation
var failures=0
func check(_ name:String,_ ok:Bool) {print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
func dispatch(_ state:ThreeDState,_ action:ThreeDAction)->ThreeDState {ThreeDReducer.reduce(state,action).0}
check("192s fresh cross-eye default ON",ThreeDState().effects[.crossEye] == .bool(true))
var inherited = ThreeDState();inherited.effects[.crossEye] = .bool(false)
let legacyData=try! JSONEncoder().encode(inherited)
inherited=try! JSONDecoder().decode(ThreeDState.self,from:legacyData)
inherited.restoreViewingDefault()
check("192s legacy inherited false recovers approved ON",inherited.effects[.crossEye] == .bool(true) && inherited.crossEyeExplicitChoice == nil)
var chosen=dispatch(inherited,.setEffect(.crossEye,.bool(false)))
chosen=try! JSONDecoder().decode(ThreeDState.self,from:JSONEncoder().encode(chosen))
chosen.restoreViewingDefault()
check("192s explicit OFF persists and survives default recovery",chosen.crossEyeExplicitChoice == false && chosen.effects[.crossEye] == .bool(false))
chosen=dispatch(chosen,.setEffect(.crossEye,.bool(true)));chosen.restoreViewingDefault()
check("192s explicit ON persists",chosen.crossEyeExplicitChoice == true && chosen.effects[.crossEye] == .bool(true))
var entry=dispatch(ThreeDState(),.open(FilmID(rawValue:"default-vr"),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
check("192s native VR entry blink defaults ON",entry.effects[.blink] == .bool(true))
entry=dispatch(entry,.setEffect(.blink,.bool(false)))
entry=try! JSONDecoder().decode(ThreeDState.self,from:JSONEncoder().encode(entry))
entry=dispatch(entry,.setOutput(.off));entry=dispatch(entry,.setOutput(.vr180))
check("192s explicit blink OFF survives re-entry/relaunch",entry.blinkExplicitChoice == false && entry.effects[.blink] == .bool(false))
var convert=dispatch(ThreeDState(),.open(FilmID(rawValue:"default-convert"),ThreeDEvidence()))
check("192s plain2D does not auto-start blink",convert.effects[.blink] == .bool(false))
convert=dispatch(convert,.setOutput(.sbs))
check("192s converted VR entry blink defaults ON",convert.effects[.blink] == .bool(true))
MainActor.assumeIsolated {
 let suite="gor192s-"+UUID().uuidString;let prefs=UserDefaults(suiteName:suite)!
 defer {prefs.removePersistentDomain(forName:suite)}
 var old=ThreeDState();old.effects[.crossEye] = .bool(false)
 prefs.set(try! JSONEncoder().encode(old),forKey:ThreeDStore.defaultsKey)
 let first=ThreeDStore(defaults:prefs)
 check("192s real store loads inherited OFF as ON",first.snapshot.effects[.crossEye] == .bool(true))
 first.dispatch(.setEffect(.crossEye,.bool(false)))
 let second=ThreeDStore(defaults:prefs)
 check("192s real stored explicit OFF survives next process load",second.snapshot.effects[.crossEye] == .bool(false) && second.snapshot.crossEyeExplicitChoice == false)
}
let plain=FilmID(rawValue:"plain-source")
let native=FilmID(rawValue:"native-source")
var s=dispatch(ThreeDState(),.open(plain,ThreeDEvidence(suggestion:"looks like SBS?")))
check("plain film always opens 2D/off; geometry is not authority",s.current.source.format == .flat2D && s.current.output == .off)
s=dispatch(s,.setOutput(.sbs))
var plan=ThreeDPresentationPlan.make(state:s)
check("191o T1 fresh 2D 3D On is flat SBS pack3",plan.engine == .flat(.sbs) && plan.output == .sbs && plan.pack == 3 && plan.vrEnabled)
var stored=s;var storedFilm=stored.current;storedFilm.output = .off;storedFilm.lastOutput = .vr180;stored.films[plain.rawValue]=storedFilm
stored=dispatch(stored,.toggle3D)
plan=ThreeDPresentationPlan.make(state:stored)
check("191o T2 stored non-VR lastOutput vr180 restores SBS",stored.current.output == .sbs && plan.engine == .flat(.sbs) && plan.pack == 3)
for _ in 0..<120 {s=dispatch(s,.open(plain,ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))}
check("explicit SBS survives late probe,120 polls and metadata",s.current.output == .sbs && s.current.userTouched)
for _ in 0..<3 {
 s=dispatch(s,.generated(plain,ThreeDSource(.sbsFull),.sbs))
 check("generated shot inherits parent, no generated entry",s.currentFilm == plain && s.films.count == 1 && s.current.output == .sbs)
 s=dispatch(s,.open(plain,ThreeDEvidence()))
 check("late source poll retains generated presentation",s.renderedSource == ThreeDSource(.sbsFull))
 s=dispatch(s,.original)
}
s=dispatch(s,.setOutput(.vr180));s=dispatch(s,.generated(plain,ThreeDSource(.vr180SBS),.vr180))
check("generated VR180 presentation is measurable before the owner SBS action",s.renderedSource == ThreeDSource(.vr180SBS) && s.presentationSource.format == .vr180SBS)
s=dispatch(s,.setOutput(.sbs))
check("explicit SBS after generated VR180 replaces the presentation immediately",s.current.output == .sbs && s.presentationSource.format == .flat2D)
s=dispatch(s,.setOutput(.vr180));s=dispatch(s,.toggle3D)
var inSession=ThreeDState()
inSession=dispatch(inSession,.open(plain,ThreeDEvidence()))
inSession=dispatch(inSession,.setOutput(.sbs))
let originalPlan=ThreeDPresentationPlan.make(state:inSession)
inSession=dispatch(inSession,.generated(plain,ThreeDSource(.sbsFull),.sbs))
let generatedPlan=ThreeDPresentationPlan.make(state:inSession)
inSession=dispatch(inSession,.original)
let returnedPlan=ThreeDPresentationPlan.make(state:inSession)
check("in-session generated route returns to the original plan without an output action",generatedPlan.luaKind == "flat-sbs" && returnedPlan == originalPlan)
s=dispatch(s,.open(plain,ThreeDEvidence(filenameTag:ThreeDSource(.vr180SBS))))
check("Off survives close/reopen and filename tag",s.current.output == .off)
let before=s.current
s=dispatch(s,.setEffect(.head,.bool(true)));s=dispatch(s,.setEffect(.blink,.bool(true)))
check("effects independent while Off",s.current == before && s.effects[.head] == .bool(true))
s=dispatch(s,.open(native,ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
check("native metadata retains native VR presentation",s.current.source.format == .vr180SBS && s.current.output == .vr180)
s=dispatch(s,.toggle3D)
check("native Off does not rewrite SOURCE",s.current.output == .off && s.current.source.format == .vr180SBS)
s=dispatch(s,.open(native,ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
check("native Off restores exactly",s.current.output == .off)
s=dispatch(s,.open(FilmID(rawValue:"tag-native"),ThreeDEvidence(filenameTag:ThreeDSource(.vr180TB))))
check("explicit filename restores191b native behavior",s.current.output == .vr180 && s.current.source.format == .vr180TB)
let tagSBS=FilmID(rawValue:"196u-tag-flat-sbs")
s=dispatch(s,.open(tagSBS,ThreeDEvidence(filenameTag:ThreeDSource(.sbsFull))))
plan=ThreeDPresentationPlan.make(state:s)
check("196u native SBS filename tag auto-opens flat SBS pack3",s.current.output == .sbs && s.current.lastOutput == .sbs && plan.engine == .flat(.sbs) && plan.pack == 3 && plan.vrEnabled)
s=dispatch(s,.toggle3D)
check("196u toggle on the auto-SBS film goes Off",s.current.output == .off)
s=dispatch(s,.toggle3D)
check("196u toggle back restores SBS from auto lastOutput",s.current.output == .sbs)
s=dispatch(s,.setOutput(.off))
s=dispatch(s,.open(tagSBS,ThreeDEvidence(filenameTag:ThreeDSource(.sbsFull))))
check("196u owner Off beats the SBS tag on every later open",s.current.output == .off)
s=dispatch(s,.open(tagSBS,ThreeDEvidence(metadata:ThreeDSource(.sbsFull))))
check("196u owner Off beats SBS metadata too",s.current.output == .off)
let tagTB=FilmID(rawValue:"196u-tag-flat-tb")
s=dispatch(s,.open(tagTB,ThreeDEvidence(metadata:ThreeDSource(.tbFull))))
check("196u native TB metadata auto-opens over-under",s.current.output == .tb && s.current.lastOutput == .tb)
let tagHalf=FilmID(rawValue:"196u-tag-half-sbs")
s=dispatch(s,.open(tagHalf,ThreeDEvidence(filenameTag:ThreeDSource(.sbsHalf))))
check("196u half-SBS tag auto-opens half-SBS output",s.current.output == .halfSBS)
let plainSuggest=FilmID(rawValue:"196u-plain-suggest")
s=dispatch(s,.open(plainSuggest,ThreeDEvidence(suggestion:"looks like SBS?")))
check("196u suggestion alone still never enables output",s.current.output == .off && s.current.source.format == .flat2D)
var twoD=FilmID(rawValue:"191o-two-d")
var vr=dispatch(ThreeDState(),.open(twoD,ThreeDEvidence()))
vr=dispatch(vr,.setOutput(.vr180))
vr=dispatch(vr,.generated(twoD,ThreeDSource(.vr180SBS),.vr180))
plan=ThreeDPresentationPlan.make(state:vr)
check("191o T3 generated VR180 on 2D stays twoDVR180 without VR180 Lua",plan.engine == .twoDVR180 && plan.luaKind == "flat-2d3d" && plan.luaAspect == 0 && plan.pack == 3 && plan.output == .vr180)
check("191o flat VR180 never teaches lastOutput",vr.current.output == .vr180 && vr.current.lastOutput == .sbs)
vr=dispatch(vr,.setOutput(.sbs))
plan=ThreeDPresentationPlan.make(state:vr)
check("191o T4 View SBS replaces generated shot",vr.renderedSource == nil && plan.engine == .flat(.sbs) && plan.luaKind == "flat-2d3d" && plan.pack == 3)
vr=dispatch(vr,.setOutput(.off))
plan=ThreeDPresentationPlan.make(state:vr)
check("191o T5 Off clears generated presentation and VR",vr.renderedSource == nil && plan.engine == .flat(.off) && plan.pack == 0 && !plan.vrEnabled)
var nativePlanState=dispatch(ThreeDState(),.open(native,ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
plan=ThreeDPresentationPlan.make(state:nativePlanState)
check("191o T6/T9 native VR180 SBS is native pack0",plan.engine == .nativeVR180 && plan.output == .vr180 && plan.pack == 0)
nativePlanState=dispatch(nativePlanState,.setOutput(.off))
plan=ThreeDPresentationPlan.make(state:nativePlanState)
check("191o native Off disables shader",plan.engine == .flat(.off) && plan.output == .off && plan.pack == 0 && !plan.vrEnabled)
nativePlanState=dispatch(ThreeDState(),.open(native,ThreeDEvidence(metadata:ThreeDSource(.vr180TB))))
plan=ThreeDPresentationPlan.make(state:nativePlanState)
check("191o T6/T9 native VR180 TB is native pack0",plan.engine == .nativeVR180 && plan.output == .vr180 && plan.pack == 0)
let nativeOff=dispatch(nativePlanState,.setOutput(.off))
let nativeOffPlan=ThreeDPresentationPlan.make(state:nativeOff)
check("191o native Off disables shader",nativeOffPlan.output == .off && !nativeOffPlan.vrEnabled)
var flatLearn=dispatch(ThreeDState(),.open(twoD,ThreeDEvidence()))
flatLearn=dispatch(flatLearn,.setOutput(.vr180))
check("191o flat VR180 never teaches lastOutput",flatLearn.current.lastOutput != .vr180)
let storeSuite="191o-store-"+UUID().uuidString
let storeDefaults=UserDefaults(suiteName:storeSuite)!
MainActor.assumeIsolated {
 let store=ThreeDStore(defaults:storeDefaults)
 store.dispatch(.open(twoD,ThreeDEvidence()))
 var firstOutputs:[ThreeDOutput]=[],secondOutputs:[ThreeDOutput]=[],nested=false,armed=false
 store.subscribe(ownerID:"first") { state,_ in
  firstOutputs.append(state.current.output)
  if armed && !nested {nested=true;store.dispatch(.setOutput(.sbs))}
 }
 store.subscribe(ownerID:"second") { state,_ in secondOutputs.append(state.current.output) }
 armed=true
 store.dispatch(.setOutput(.vr180))
 check("191o T8 nested dispatch drains to the same final snapshot",firstOutputs.last == .sbs && secondOutputs.last == .sbs && store.snapshot.current.output == .sbs)
}
let replaySuite="191v-replay-"+UUID().uuidString
let replayDefaults=UserDefaults(suiteName:replaySuite)!
MainActor.assumeIsolated {
 let store=ThreeDStore(defaults:replayDefaults)
 var presented=0
 store.subscribe(ownerID:"replay") { _,effects in if effects.contains(.showInfo) {presented += 1} }
 store.dispatch(.open(twoD,ThreeDEvidence()))
 store.dispatch(.setOutput(.sbs));store.dispatch(.setOutput(.vr180));store.dispatch(.setOutput(.sbs));store.dispatch(.setOutput(.off));store.dispatch(.setOutput(.sbs));store.dispatch(.setOutput(.sbs))
 check("in-session replay presents changed outputs, repeated selection does not reset",presented == 5 && store.snapshot.current.output == .sbs)
}
replayDefaults.removePersistentDomain(forName:replaySuite)
storeDefaults.removePersistentDomain(forName:storeSuite)
for source in ThreeDSource.Format.allCases {for output in ThreeDOutput.allCases {
 var m=dispatch(ThreeDState(),.open(plain,ThreeDEvidence()))
 m=dispatch(m,.setSource(ThreeDSource(source,swap:true)));m=dispatch(m,.setOutput(output))
 check("matrix \(source.rawValue)/\(output.rawValue)",m.current.source == ThreeDSource(source,swap:true) && m.current.output == output)
}}
var stale=ThreeDState();var old=FilmThreeD();old.output = .vr180;stale.films[plain.rawValue]=old
stale=dispatch(stale,.open(plain,ThreeDEvidence()))
check("unproven stale VR180 entry ignored",stale.current.output == .off)
var persistedLock=ThreeDState();var touched=FilmThreeD();touched.output = .vr180;touched.lastOutput = .sbs;touched.userTouched = true;persistedLock.films[plain.rawValue]=touched
persistedLock=dispatch(persistedLock,.open(plain,ThreeDEvidence()))
plan=ThreeDPresentationPlan.make(state:persistedLock)
check("owner regression: persisted flat VR180 output reopens as SBS, not a VR180 lock",persistedLock.current.output == .sbs && plan.engine == .flat(.sbs) && plan.pack == 3)
var openingProjection:String?
openingProjection=ThreeDProjectionMemory.resolve(current:openingProjection,evidence:"vr180",probe:nil)
check("native opening projection survives later flat SBS params",ThreeDProjectionMemory.resolve(current:openingProjection,evidence:"flat-sbs",probe:nil) == "vr180")
check("confirmed native probe beats generic flat SBS evidence",ThreeDProjectionMemory.resolve(current:nil,evidence:"flat-sbs",probe:"vr180") == "vr180")
check("unavailable probe does not invent native from flat SBS",ThreeDProjectionMemory.resolve(current:nil,evidence:"flat-sbs",probe:nil) == "flat-sbs")
check("unsupported spherical probe is not flat SBS",ThreeDProjectionMemory.resolve(current:nil,evidence:"flat-sbs",probe:"unsupported") == "unsupported")
for native in ["vr180","vr180-tb","vr360-mono","vr360-tb","unsupported"] {
    for flat in ["flat-sbs","flat-tb"] {
        check("native probe beats generic evidence \(native) \(flat)",ThreeDProjectionMemory.resolve(current:nil,evidence:flat,probe:native) == native)
        check("confirmed verdict survives pending probe \(native) \(flat)",ThreeDProjectionMemory.resolve(current:native,evidence:flat,probe:nil) == native)
    }
}
check("new unsupported verdict supersedes retained native",ThreeDProjectionMemory.resolve(current:"vr180",evidence:"flat-sbs",probe:"unsupported") == "unsupported")
check("new spherical verdict supersedes retained opening",ThreeDProjectionMemory.resolve(current:"vr180",evidence:"flat-sbs",probe:"vr360-mono") == "vr360-mono")
for i in 0..<2005 {stale=dispatch(stale,.open(FilmID(rawValue:"film\(i)"),ThreeDEvidence()))}
check("film history capped2000; oldest evicted",stale.films.count == 2000 && stale.order.count == 2000 && stale.films["film0"] == nil)
let roundtrip=try! JSONDecoder().decode(ThreeDState.self,from:JSONEncoder().encode(s))
check("Codable snapshot roundtrip",roundtrip == s)
func identity(_ volume:String,_ inode:String,_ name:String,_ size:Int64)->ThreeDFilmIdentity {.init(volume:volume,fileID:inode,infohash:nil,fileIndex:nil,basename:name,finalSize:size,normalizedURL:nil)}
let first=identity("vol1","inode1","film.mkv",10_000_000)
let firstID=ThreeDFilmIdentity.resolve(first,records:[:],freshID:"unused")
let records=[firstID.rawValue:first]
check("D1 growth10MBto4GB retainsID",ThreeDFilmIdentity.resolve(identity("vol1","inode1","film.mkv",4_000_000_000),records:records,freshID:"new")==firstID)
check("D1 rename samevolume retainsID",ThreeDFilmIdentity.resolve(identity("vol1","inode1","renamed.mkv",10_000_000),records:records,freshID:"new")==firstID)
check("D1 unique copy basename+size matches",ThreeDFilmIdentity.resolve(identity("vol2","inode5","film.mkv",10_000_000),records:records,freshID:"new")==firstID)
var ambiguous=records;ambiguous["other"]=identity("vol3","inode6","film.mkv",10_000_000)
check("D1 two same-name films cannot collide",ThreeDFilmIdentity.resolve(identity("vol4","inode7","film.mkv",10_000_000),records:ambiguous,freshID:"new") != firstID)
check("D1 different files remain distinct",ThreeDFilmIdentity.resolve(identity("vol2","inode1","other.mkv",10_000_000),records:records,freshID:"new") != firstID)
let torrentA=ThreeDFilmIdentity(volume:nil,fileID:nil,infohash:"ABCDEF",fileIndex:3,basename:"magnet.mkv",finalSize:4_000_000_000,normalizedURL:nil)
let torrentID=ThreeDFilmIdentity.resolve(torrentA,records:[:],freshID:"new")
check("D1 known torrent uses infohash+fileindex",torrentID.rawValue=="torrent|abcdef|3")
var copyRecord=identity("vol2","inode5","film.mkv",10_000_000);copyRecord.aliases=[first.primary!]
check("D1 copy alias preserves originalvolume/inode",ThreeDFilmIdentity.resolve(first,records:[firstID.rawValue:copyRecord],freshID:"new")==firstID)
check("D1 basename wrongsize cannot match",ThreeDFilmIdentity.resolve(identity("vol9","inode9","film.mkv",12),records:records,freshID:"new") != firstID)
var currentView=dispatch(ThreeDState(),.open(plain,ThreeDEvidence()))
currentView=dispatch(currentView,.setOutput(.vr180))
currentView=dispatch(currentView,.open(plain,ThreeDEvidence()))
check("191t ARCH-Q same-film poll preserves explicit flat VR180 view",currentView.current.output == .vr180 && currentView.current.lastOutput == .sbs && currentView.current.source.format == .flat2D)
var freshView=currentView;freshView.currentFilm=nil
freshView=dispatch(freshView,.open(plain,ThreeDEvidence()))
check("191v ARCH-Q fresh launch matches explicit flat VR180 choice",freshView.current.output == .vr180 && freshView.current.lastOutput == .sbs)
// 191t T2-T4: old evidence records are not manual source choices.
let legacyID=FilmID(rawValue:"191t-legacy")
var legacy=ThreeDState();var legacyFilm=FilmThreeD()
legacyFilm.source=ThreeDSource(.vr180SBS);legacyFilm.output = .sbs;legacyFilm.explicitOutput = .sbs;legacyFilm.userTouched=true
legacy.films[legacyID.rawValue]=legacyFilm
legacy=dispatch(legacy,.open(legacyID,ThreeDEvidence()))
let legacyPlan=ThreeDPresentationPlan.make(state:legacy)
check("191t T2 inferred old VR180 record repairs on open without data reset",legacy.current.source.format == .flat2D && legacy.current.output == .sbs && legacyPlan.engine == .flat(.sbs) && legacyPlan.luaKind == "flat-2d3d")
for evidence in [ThreeDEvidence(),ThreeDEvidence(metadata:ThreeDSource(.vr180SBS)),ThreeDEvidence(filenameTag:ThreeDSource(.sbsFull))] {
 var late=dispatch(ThreeDState(),.open(legacyID,ThreeDEvidence()))
 late=dispatch(late,.setOutput(.sbs))
 late=dispatch(late,.open(legacyID,evidence))
 var restored=try! JSONDecoder().decode(ThreeDState.self,from:JSONEncoder().encode(late));restored.currentFilm=nil
 restored=dispatch(restored,.open(legacyID,evidence))
 check("191t T3 first-open and snapshot-relaunch agree \(late.current.source.format)",restored == late)
}
var manual=dispatch(ThreeDState(),.open(legacyID,ThreeDEvidence(metadata:ThreeDSource(.vr180SBS))))
check("191t T4 metadata-native opens native VR180",ThreeDPresentationPlan.make(state:manual).engine == .nativeVR180 && manual.current.output == .vr180 && manual.current.userSource != true)
manual=dispatch(manual,.setSource(ThreeDSource(.vr180SBS)))
manual=dispatch(manual,.open(legacyID,ThreeDEvidence()))
check("191t T4 manual native source survives absent metadata",manual.current.userSource == true && manual.current.source.format == .vr180SBS && manual.current.output == .vr180)
manual=dispatch(manual,.cycleSource)
check("191t cycleSource records a user source choice",manual.current.userSource == true)
for source in [ThreeDSource.Format.flat2D,.sbsFull,.vr180SBS,.vr180TB] {
 for output in ThreeDOutput.allCases {
  var test=dispatch(ThreeDState(),.open(legacyID,ThreeDEvidence(metadata:ThreeDSource(source))))
  test=dispatch(test,.setOutput(output));test=dispatch(test,.setOutput(.off))
  let off=ThreeDPresentationPlan.make(state:test)
  check("191t T6 Off overrides \(source)/\(output)",off.output == .off && off.engine == .flat(.off) && off.pack == 0 && !off.vrEnabled)
  if !ThreeDSource(source).nativeVR {
   test=dispatch(test,.toggle3D)
   check("191t T6 flat toggle restores non-VR output",test.current.output != .vr180 && test.current.output != .off)
  }
 }
}
for action in [ThreeDAction.setSource(ThreeDSource(.flat2D)),.setOutput(.sbs),.toggle3D,.cycleSource] {
 let (_,effects)=ThreeDReducer.reduce(legacy,action)
 if case let .setOutput(output)=action,legacy.current.output == output,legacy.current.explicitOutput == output {check("191t F3 repeated output preserves presentation",effects.isEmpty)} else {check("191t F3 changed source/output choice requests reapply",effects.contains(.reapply))}
}
//192u: actual spherical SOURCE is independent of remembered output and prepared shots.
for fmt in [ThreeDSource.Format.vr180SBS,.vr180TB] {
 var n=dispatch(ThreeDState(),.open(native,ThreeDEvidence(metadata:ThreeDSource(fmt))))
 n=dispatch(n,.setOutput(.sbs));var p=ThreeDPresentationPlan.make(state:n)
 check("192u outputSBS never reclassifies native \(fmt)",p.engine == .flat(.sbs) && p.filmSource.format == fmt && p.luaKind == (fmt == .vr180SBS ? "flat-sbs":"flat-tb") && p.pack == 3 && p.output == .sbs)
 n.renderedSource=ThreeDSource(.flat2D);n.renderedOutput = .vr180
 p=ThreeDPresentationPlan.make(state:n)
 check("192u stale rendered flat source never overrides native \(fmt)",p.luaKind == (fmt == .vr180SBS ? "flat-sbs":"flat-tb") && p.pack == 3)
 n=dispatch(n,.setOutput(.off));p=ThreeDPresentationPlan.make(state:n)
 check("192u explicitOff retains raw for native \(fmt)",!p.vrEnabled && p.output == .off && p.pack == 0)
}
//193h owner's selected OUTPUT is the single engine table for every source.
for format:ThreeDSource.Format in [.flat2D,.sbsFull,.vr180SBS,.vr180TB] {
 for output in ThreeDOutput.allCases {
  var matrix=ThreeDState();let id=FilmID(rawValue:"193h-matrix")
  matrix.currentFilm=id;var film=FilmThreeD();film.source=ThreeDSource(format);film.output=output;matrix.films[id.rawValue]=film
  let p=ThreeDPresentationPlan.make(state:matrix),native=[ThreeDSource.Format.vr180SBS,.vr180TB].contains(format)
  let expected:ThreeDEngine = output == .off ? .flat(.off):(output == .vr180 ? (native ? .nativeVR180:.twoDVR180):.flat(output))
  check("193h source/output \(format)/\(output)",p.engine==expected && p.output==output)
  let kind=(native && output != .vr180) ? (format == .vr180SBS ? "flat-sbs":"flat-tb"):ThreeDSource(format).projection
  check("193h luaKind \(format)/\(output)",p.luaKind==kind)
 }
}


var staleNative=FilmThreeD();staleNative.source=ThreeDSource(.vr180SBS);staleNative.userSource=true;staleNative.userTouched=true
check("193i oldnativechoicewithoutpositiveevidencecleared",ThreeDReducer.opening(saved:staleNative,evidence:ThreeDEvidence()).source.format == .flat2D)
check("193i livenativechoicepreserved",ThreeDReducer.opening(saved:staleNative,evidence:ThreeDEvidence(),liveSourceChoice:true).source.format == .vr180SBS)
var cycle=dispatch(ThreeDState(),.open(plain,ThreeDEvidence()))
for _ in 0..<30 {cycle=dispatch(cycle,.cycleSource);check("193i cyclecannotinventnative",![.vr180SBS,.vr180TB].contains(cycle.current.source.format))}
let stream1=ThreeDFilmIdentity(volume:nil,fileID:nil,infohash:nil,fileIndex:nil,basename:"a",finalSize:nil,normalizedURL:"https://example.test/shared")
check("193i URLalonecannotidentifyfilm",stream1.primary == nil)
var stream2=stream1;stream2.finalSize=100;var stream3=stream1;stream3.finalSize=200
check("193i reusedURLdifferentsizesdistinct",stream2.primary != stream3.primary)


// Owner12:05: independent parameter edits must not trigger coordinator reapply.
var live=ThreeDReducer.reduce(ThreeDState(),.open(FilmID(rawValue:"live-params"),ThreeDEvidence())).0
live=ThreeDReducer.reduce(live,.setOutput(.sbs)).0
for key in ThreeDEffectKey.allCases {
 let before=live
 let (updated,effects)=ThreeDReducer.reduce(live,.setEffect(key,key == .surround ? .text("black"):.number(1.2)))
 check("live parameter no route/media reapply \(key)",!effects.contains(.reapply) && updated.current == before.current && updated.renderedSource == before.renderedSource)
 live=updated
}
check("explicit same-output does not reset crop/media",ThreeDReducer.reduce(live,.setOutput(.sbs)).1.isEmpty)

// Same-output shortcut is not a fresh presentation command: keep crop/pose/prepared media intact.
let repeatID=FilmID(rawValue:"repeat-sbs")
let repeatOpen=ThreeDReducer.reduce(ThreeDState(),.open(repeatID,ThreeDEvidence())).0
let repeatSBS=ThreeDReducer.reduce(repeatOpen,.setOutput(.sbs)).0
let (repeatUnchanged,repeatEffects)=ThreeDReducer.reduce(repeatSBS,.setOutput(.sbs))
precondition(repeatUnchanged == repeatSBS && repeatEffects.isEmpty,"same-output reset presentation/crop")
let (_,differentEffects)=ThreeDReducer.reduce(repeatSBS,.setOutput(.tb))
precondition(differentEffects.contains(.reapply),"changed output lost explicit presentation")
print("PASS repeated same-output is a state/effect no-op; changed output still reapplies")

print("ThreeDState reducer failures=\(failures)")
exit(failures == 0 ? 0:1)

