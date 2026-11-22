import Foundation
import GorAVPlaybackCore

var failures=0
func check(_ name:String,_ cond:Bool){print((cond ? "PASS ":"FAIL ")+name);if !cond {failures+=1}}
func eq(_ name:String,_ got:String?,_ want:String){check(name,got==want)}

// C1 mute
eq("C1 m->cycle mute",MPVDefaultKeymap.command(forKey:"m"),#"{"command":["cycle","mute"]}"#)
// C2 volume digits (mpv default step 2)
eq("C2a 9->add volume -2",MPVDefaultKeymap.command(forKey:"9"),#"{"command":["add","volume",-2]}"#)
eq("C2b 0->add volume +2",MPVDefaultKeymap.command(forKey:"0"),#"{"command":["add","volume",2]}"#)
// C3 volume keypad
eq("C3a /->add volume -2",MPVDefaultKeymap.command(forKey:"/"),#"{"command":["add","volume",-2]}"#)
eq("C3b *->add volume +2",MPVDefaultKeymap.command(forKey:"*"),#"{"command":["add","volume",2]}"#)
// C4 subtitle cycle direction is case-sensitive (mpv: j down-list forward, J backward)
eq("C4a j->cycle sub",MPVDefaultKeymap.command(forKey:"j"),#"{"command":["cycle","sub"]}"#)
eq("C4b J->cycle sub down",MPVDefaultKeymap.command(forKey:"J"),#"{"command":["cycle","sub","down"]}"#)
// C5 audio cycle
eq("C5 #->cycle audio",MPVDefaultKeymap.command(forKey:"#"),#"{"command":["cycle","audio"]}"#)
// C6 subtitle visibility
eq("C6 v->cycle sub-visibility",MPVDefaultKeymap.command(forKey:"v"),#"{"command":["cycle","sub-visibility"]}"#)
// C7 window cycles
eq("C7a f->cycle fullscreen",MPVDefaultKeymap.command(forKey:"f"),#"{"command":["cycle","fullscreen"]}"#)
eq("C7b T->cycle ontop",MPVDefaultKeymap.command(forKey:"T"),#"{"command":["cycle","ontop"]}"#)
// C8 quit pair
eq("C8a q->quit",MPVDefaultKeymap.command(forKey:"q"),#"{"command":["quit"]}"#)
eq("C8b Q->quit-watch-later",MPVDefaultKeymap.command(forKey:"Q"),#"{"command":["quit-watch-later"]}"#)
// C9 chapter step routes to the slice-1 chapter case with exact +/-1 deltas
eq("C9a !->add chapter -1",MPVDefaultKeymap.command(forKey:"!"),#"{"command":["add","chapter",-1]}"#)
eq("C9b @->add chapter +1",MPVDefaultKeymap.command(forKey:"@"),#"{"command":["add","chapter",1]}"#)
// C10 untranslated keys keep the loud-refusal path (nil): photon-bound,
// gor-rebound, speed (no gorav speed command yet), modified and empty keys
for k in ["x","b","g","c","n","1","6","i",",",".","]","[","{","}","BS","ENTER","SPACE","ESC","Shift+m","Meta+Alt+c","Ctrl+F1","", "M","t"] {
    check("C10 '\(k)' untranslated",MPVDefaultKeymap.command(forKey:k)==nil)
}
// C11 every translated line is a JSON object with a string-first command array
for k in ["m","9","0","/","*","j","J","#","v","f","T","q","Q","!","@"] {
    guard let line=MPVDefaultKeymap.command(forKey:k),
          let data=line.data(using:.utf8),
          let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
          let cmd=obj["command"] as? [Any],
          let head=cmd.first as? String else {check("C11 '\(k)' parses",false);continue}
    check("C11 '\(k)' parses to command \(head)",["cycle","add","quit","quit-watch-later"].contains(head))
}
// C12 chapter deltas are nonzero integers
for k in ["!","@"] {
    let line=MPVDefaultKeymap.command(forKey:k)!
    let obj=try! JSONSerialization.jsonObject(with:line.data(using:.utf8)!) as! [String:Any]
    let cmd=obj["command"] as! [Any]
    let d=(cmd[2] as? NSNumber)?.doubleValue ?? 0
    check("C12 '\(k)' chapter delta nonzero integer",d==d.rounded() && d != 0)
}

print(failures==0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures==0 ? 0 : 1)
