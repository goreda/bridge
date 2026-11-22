/// KEYPRESS-PARITY slice 2: mpv default key bindings that map onto delivered
/// gorav chrome commands. InputController forwards every key it does not own
/// as ["keypress","<mpv-name>"]; on gorav each one used to hit the router's
/// default loud refusal. This table preserves the mpv-default user-visible
/// behavior for the keys whose gorav equivalent is already delivered, and
/// returns nil for everything else so the router keeps its existing loud
/// typed refusal - route or loud-refuse, never silent.
///
/// Table source: mpv default bindings, excluding keys gor's own
/// Resources/vendor/mpv/input.conf rebinds (photon scripts, sub-scale, grain
/// stock, stats) and keys InputController owns in Swift (arrows, space,
/// shift+digits, photon adjust, fn+shift motion holds). A rebound or
/// Swift-owned key never reaches this table with the mpv-default meaning.
/// Only bindings whose target command is already routed by
/// GorAVPlayerHost.handleChromeCommand are listed.
public enum MPVDefaultKeymap {
    /// Chrome command line for a forwarded mpv key name, or nil when the key
    /// has no delivered gorav equivalent (router must loud-refuse it).
    public static func command(forKey key:String)->String? {
        switch key {
        case "m":return #"{"command":["cycle","mute"]}"#
        case "9","/":return #"{"command":["add","volume",-2]}"#
        case "0","*":return #"{"command":["add","volume",2]}"#
        case "j":return #"{"command":["cycle","sub"]}"#
        case "J":return #"{"command":["cycle","sub","down"]}"#
        case "#":return #"{"command":["cycle","audio"]}"#
        case "v":return #"{"command":["cycle","sub-visibility"]}"#
        case "f":return #"{"command":["cycle","fullscreen"]}"#
        case "T":return #"{"command":["cycle","ontop"]}"#
        case "q":return #"{"command":["quit"]}"#
        case "Q":return #"{"command":["quit-watch-later"]}"#
        case "!":return #"{"command":["add","chapter",-1]}"#
        case "@":return #"{"command":["add","chapter",1]}"#
        default:return nil
        }
    }
}
