import Foundation
var failures=0
func check(_ ok:Bool,_ label:String){ print((ok ? "PASS ":"FAIL ")+label); if !ok { failures += 1 } }
let track=SubtitleTrack.Track(format:"srt",cues:[SubtitleCue(index:1,startSeconds:0,endSeconds:10,lines:["same content"])],styles:[],unsupportedOverrides:[],skippedStyles:[],playResX:nil,playResY:nil)
var c=SubtitleController()
c.selectPrimary(track)
let oldID=c.contentID(slot:.primary)!
c.selectPrimary(track) // distinct source selection with identical content
let before=c.presentationReadback(slot:.primary)
let stale=SubtitleController.PresentationSettings(fontScale:3,verticalPosition:0.2,delay:2,visible:false)
let result=c.applyPresentation(stale,slot:.primary,forContentID:oldID)
if case .failure(.staleSource)=result { check(true,"prior source request refused") } else { check(false,"content-only API does not fence source replacement") }
check(c.presentationReadback(slot:.primary)==before,"stale request changes nothing")
exit(failures == 0 ? 0:1)
