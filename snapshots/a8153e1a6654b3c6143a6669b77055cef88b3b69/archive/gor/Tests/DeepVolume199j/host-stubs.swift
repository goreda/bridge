// Host-only menu surfaces are doubles; menu logic, options, keys and lock-backed state are extracted unchanged.
protocol NSMenuItemValidation {func validateMenuItem(_ row:NSMenuItem)->Bool}
struct ModifierFlags:OptionSet {let rawValue:Int;static let command=Self(rawValue:1),control=Self(rawValue:2),option=Self(rawValue:4)}
enum ItemState {case on,off}
final class NSMenuItem {var title:String,tag=0,submenu:NSMenu?,target:AnyObject?,state=ItemState.off,keyEquivalentModifierMask:ModifierFlags=[];init(title:String,action:Int?,keyEquivalent:String){self.title=title};static func separator()->NSMenuItem{NSMenuItem(title:"-",action:nil,keyEquivalent:"")}}
final class NSMenu {var title:String,items:[NSMenuItem]=[];init(title:String){self.title=title};func addItem(_ i:NSMenuItem){items.append(i)}}
enum NSApp {struct Event {var isARepeat=false};static var currentEvent:Event?=nil}
struct ThreeDExperimentState {var budgetOn=false,convergence=0.0,compression=0.0;var budgetCommand:String{"command"};mutating func useDepthPreset(){};mutating func stepConvergence(_ d:Double){convergence+=d};mutating func stepCompression(_ d:Double){compression+=d}}
enum DepthTemporalEMA {static var flag=false;static func isEnabled()->Bool{flag};static func setEnabled(_ on:Bool){flag=on};static func toggleEnabled(){flag.toggle()}}
enum DepthModelID {case dav2_small_coreml,luma_y_prior;static var flag=Self.luma_y_prior;static func selected()->Self{flag};static func select(_ v:Self){flag=v}}
enum ModelDepthEMA {static var enabled=false;static func setEnabled(_ v:Bool){enabled=v};static func toggle(){enabled.toggle()}}
extension ThreeDSubtitleDepth {static func setExperimental(_ on:Bool){}}
enum SynthMethod:String {case dibr_golden;static var current:(method:Self,note:String){(.dibr_golden,"")}}
enum RenderedShotPlan {enum Codec:String{case hevc,h264}}
