import Foundation
var failures=0
func check(_ ok:Bool,_ label:String){ print((ok ? "PASS ":"FAIL ")+label); if !ok { failures += 1 } }
let a=MediaInventory.stableStreamID(kind:.audio,index:1,codec:"aac|en",language:"fr",title:"x")
let b=MediaInventory.stableStreamID(kind:.audio,index:1,codec:"aac",language:"en|fr",title:"x")
check(a != b,"delimiter tuples remain distinct")
let n=MediaInventory.stableStreamID(kind:.audio,index:1,codec:"aac",language:nil,title:"x")
let e=MediaInventory.stableStreamID(kind:.audio,index:1,codec:"aac",language:"",title:"x")
check(n != e,"nil and empty language remain distinct")
check(a == MediaInventory.stableStreamID(kind:.audio,index:1,codec:"aac|en",language:"fr",title:"x"),"same tuple deterministic")
exit(failures == 0 ? 0:1)
