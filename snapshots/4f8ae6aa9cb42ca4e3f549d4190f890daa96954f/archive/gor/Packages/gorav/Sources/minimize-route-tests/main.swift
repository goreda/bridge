import Foundation
import GorAVPlaybackCore
var failures=0
func check(_ name:String,_ cond:Bool){print((cond ? "PASS ":"FAIL ")+name);if !cond {failures+=1}}
func eq(_ name:String,_ got:MinimizeRoute?,_ want:MinimizeRoute?){check(name,got==want)}

// C1 gorav with a player window miniaturizes the window itself
eq("C1 gorav+window -> goravHostWindow",MinimizeRoutePlanner.route(engineIsGorav:true,hasMpvAXWindow:false,hasPlayerWindow:true),.goravHostWindow)
// C2 gorav without any window is a genuine no-op (nothing to minimize)
eq("C2 gorav no window -> nil",MinimizeRoutePlanner.route(engineIsGorav:true,hasMpvAXWindow:false,hasPlayerWindow:false),nil)
// C3 mpv with AX window and player window keeps the legacy chain
eq("C3 mpv+ax+window -> mpvWindowChain",MinimizeRoutePlanner.route(engineIsGorav:false,hasMpvAXWindow:true,hasPlayerWindow:true),.mpvWindowChain)
// C4 mpv without AX window keeps the legacy silent guard (unchanged behavior)
eq("C4 mpv no ax -> nil",MinimizeRoutePlanner.route(engineIsGorav:false,hasMpvAXWindow:false,hasPlayerWindow:true),nil)
eq("C4b mpv ax but no window -> nil",MinimizeRoutePlanner.route(engineIsGorav:false,hasMpvAXWindow:true,hasPlayerWindow:false),nil)
// C5 gorav never touches the mpv chain, even if a stale AX window existed
eq("C5 gorav ignores ax",MinimizeRoutePlanner.route(engineIsGorav:true,hasMpvAXWindow:true,hasPlayerWindow:true),.goravHostWindow)
// C6 pure and deterministic
check("C6 deterministic",MinimizeRoutePlanner.route(engineIsGorav:true,hasMpvAXWindow:false,hasPlayerWindow:true)==MinimizeRoutePlanner.route(engineIsGorav:true,hasMpvAXWindow:false,hasPlayerWindow:true))

print(failures==0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures==0 ? 0 : 1)
