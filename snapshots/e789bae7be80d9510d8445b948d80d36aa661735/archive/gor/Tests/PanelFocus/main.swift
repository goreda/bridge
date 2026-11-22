import Foundation
final class Node {var children:[Node]=[];var visible=true;var editable=false;var enabled=true;init(_ c:[Node]=[]){children=c}}
let field=Node();field.editable=true
let original=Node([Node(),field]),stereoHost=Node([original,Node()])
func find(_ n:Node)->Node? {PanelFocusTraversal.first(in:n,children:{$0.children},visible:{$0.visible},accept:{$0.editable && $0.enabled ? $0:nil})}
precondition(find(stereoHost) === field)
original.visible=false;precondition(find(stereoHost)==nil);original.visible=true
field.enabled=false;precondition(find(stereoHost)==nil);field.enabled=true
precondition(find(original) === field)
print("PASS production recursive resolver mono/stereo nested/hidden/disabled controls; native AppKit switch/IME/Esc UNRUN")
