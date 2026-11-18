# W-gdb-199f-1nstinct-30 - Panel traversal without call-stack growth
state: OPEN / unclaimed

CLASSIFICATION: Only PanelFocusTraversal is extracted verbatim. Valid deep tree stack exhaustion, not cycle safety. No AppKit focus acceptance.
lab: 1nstinct

Replace recursive PanelFocusTraversal.first with iterative depth-first traversal preserving child order, visibility pruning and first-match semantics. Deep valid hierarchies must not crash the native focus path. Generic signatures stay unchanged. Cycles are not promised: callers still supply a tree. Do not change activation or panel ownership rules.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-1nstinct-30",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorPlatformMac/PanelFocusTraversal.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Replace recursive PanelFocusTraversal.first with iterative depth-first traversal preserving child order, visibility pruning and first-match semantics. Deep valid hierarchies must not crash the native focus path. Generic signatures stay unchanged. Cycles are not promised: callers still supply a tree. Do not change activation or panel ownership rules.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Only PanelFocusTraversal is extracted verbatim. Valid deep tree stack exhaustion, not cycle safety. No AppKit focus acceptance.",
    "callee": "archive/gor/Sources/gor/GorPlatformMac/PanelFocusTraversal.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-30.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199f-1nstinct-30",
    "paths": [
      "archive/gor/Sources/gor/GorPlatformMac/PanelFocusTraversal.swift",
      "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-30.py",
      "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-30.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-30.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorPlatformMac/PanelFocusTraversal.swift",
        "block": "source1",
        "sha256": "3e1a34f112600388f6317285289c98669320dd8b5c3c85e14a7ce114693fd78f",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-30.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-30.json",
        "block": "fixtures2",
        "sha256": "69b8d57cf6d944425ed5449efa8e63359544b68f52cf1cc3d8d3ce2de65caa7a"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "2fa216a02bb81471eb5550586abf41ad16506c0bc2466e05b34392334f99a759",
    "last_5_lines": [
      "0x00007fc039400000\u20130x00007fc039995930 b9f29f81b467904a40bdaaa0b0f84468865569b7 libswiftCore.so /tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/lib/swift/linux/libswiftCore.so",
      "",
      "Backtrace took 0.09s",
      "",
      ""
    ]
  },
  "classification": "Only PanelFocusTraversal is extracted verbatim. Valid deep tree stack exhaustion, not cycle safety. No AppKit focus acceptance."
}
```

```swift id=source1
import Foundation
// Test/background launches may create real windows but must not claim the user's focus.
enum NoActivate {
    static func requested(arguments:[String],environment:[String:String])->Bool {
        arguments.contains("--gor-no-activate") || environment["GOR_NO_ACTIVATE"] == "1"
    }
    static var active:Bool {requested(arguments:ProcessInfo.processInfo.arguments,environment:ProcessInfo.processInfo.environment)}
    private static var startupPending = ProcessInfo.processInfo.arguments.contains("--gor-background-start")
    static var suppressAutomatic:Bool {active || startupPending}
    static func userInteraction() {startupPending=false}
}
// Exact traversal used by native panel focus, independently executable without AppKit.
enum PanelFocusTraversal {
    static func first<Node,Result>(in node:Node,children:(Node)->[Node],visible:(Node)->Bool,accept:(Node)->Result?)->Result? {
        guard visible(node) else{return nil}
        if let found=accept(node){return found}
        for child in children(node) {
            if let found:Result=first(in:child,children:children,visible:visible,accept:accept){return found}
        }
        return nil
    }
}

/// Key-window ownership between gor's single player window and its floating input panels.
/// Invariant: while at least one input panel is open, the panel owns the key window and no
/// automatic gor path (app-activation recovery, mpv-activation recovery, overlay click focus
/// claim, un-minimize) may re-key the player window. The panel re-claims key only through its
/// own open/click path (GORInputPanel). AppKit-free so the rule runs in the Linux harness
/// (Tests/Harness/PanelFocus); the AppKit binding lives in PanelFocus.swift.
/// Main-thread only, like the windows it describes.
final class PanelKeyOwnership {
    static let shared = PanelKeyOwnership()
    /// Tokens of the currently open input panels, in registration order.
    private(set) var openPanels:[ObjectIdentifier] = []
    /// Idempotent: a panel registers on every ordering-in/key claim.
    func register(_ token:ObjectIdentifier) {
        if !openPanels.contains(token) { openPanels.append(token) }
    }
    /// Idempotent: close, order-out and deinit all unregister.
    func unregister(_ token:ObjectIdentifier) {
        openPanels.removeAll { $0 == token }
    }
    var panelOwnsKey:Bool { !openPanels.isEmpty }
    /// The single decision point every automatic player-window re-key must consult.
    func mayKeyPlayerWindow() -> Bool { !NoActivate.suppressAutomatic && !panelOwnsKey }
}

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')) else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorPlatformMac/PanelFocusTraversal.swift",
  "markers": [
    "enum PanelFocusTraversal {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet result:Int?=PanelFocusTraversal.first(in:0,children:{$0<50000 ? [$0+1]:[]},visible:{_ in true},accept:{$0==50000 ? $0:nil})\ncheck(result == 50000,\"deep hierarchy traverses without stack overflow\")\nlet first:Int?=PanelFocusTraversal.first(in:0,children:{$0==0 ? [1,2]:[]},visible:{_ in true},accept:{$0>0 ? $0:nil})\ncheck(first == 1,\"first child order retained\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=-11

*** Signal 11: Backtracing from 0x7fc039850730... done ***

*** Program crashed: Bad pointer dereference at 0x00007ffc6854aff0 ***

Thread 0 "test" crashed:

    0      0x00007fc039850730 getCache(swift::TargetTypeContextDescriptor<swift::InProcess> const&) + 464 in libswiftCore.so
    1 [ra] 0x00007fc039850ea9 _swift_getGenericMetadata(swift::MetadataRequest, void const* const*, swift::TargetTypeContextDescriptor<swift::InProcess> const*) + 40 in libswiftCore.so
    2 [ra] 0x00007fc0396c9493 __swift_instantiateCanonicalPrespecializedGenericMetadata + 34 in libswiftCore.so
    3 [ra] 0x000055ed717b8406 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 261 in test
    4 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
    5 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
    6 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
    7 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
    8 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
    9 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   10 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   11 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   12 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   13 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   14 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   15 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   16 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   17 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   18 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   19 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   20 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   21 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   22 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   23 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   24 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   25 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   26 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   27 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   28 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   29 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   30 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   31 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   32 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   33 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   34 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   35 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   36 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   37 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   38 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   39 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   40 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   41 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   42 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   43 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   44 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   45 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
   46 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
  ...
18053 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18054 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18055 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18056 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18057 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18058 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18059 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18060 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18061 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18062 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18063 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18064 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18065 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18066 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18067 [ra] 0x000055ed717b86e9 static PanelFocusTraversal.first<A, B>(in:children:visible:accept:) + 1000 in test
18068 [ra] 0x000055ed717b8d74 main + 99 in test


Registers:

rax 0x0000000000080012  524306
rdx 0x0000000000000000  0
rcx 0x00000000000800f2  524530
rbx 0x00007fc0399e34c0  00 c7 0c 00 0c bd fd ff 01 00 01 00 01 00 02 00  ·Ç···½ýÿ········
rsi 0x00007fc0399e34c4  0c bd fd ff 01 00 01 00 01 00 02 00 80 00 00 00  ·½ýÿ············
rdi 0x00007ffc6854b1d8  90 d0 99 39 c0 7f 00 00 00 00 00 00 00 00 00 00  ·Ð·9À···········
rbp 0x00007ffc6854b080  c0 b1 54 68 fc 7f 00 00 a9 0e 85 39 c0 7f 00 00  À±Thü···©··9À···
rsp 0x00007ffc6854afd0  140722058866640
 r8 0x00007fc0399e34a4  f2 00 08 00 60 95 fd ff 14 bd fd ff b0 fa cf ff  ò···`·ýÿ·½ýÿ°úÏÿ
 r9 0x00007fc039aafc40  ff ff ff ff 00 00 00 00 00 00 00 00 00 00 00 00  ÿÿÿÿ············
r10 0x00007fc03999d090  00 02 00 00 00 00 00 00 f4 26 9e 39 c0 7f 00 00  ········ô&·9À···
r11 0x00007fc03999d090  00 02 00 00 00 00 00 00 f4 26 9e 39 c0 7f 00 00  ········ô&·9À···
r12 0x00007ffc68d49e18  30 ac d4 68 fc 7f 00 00 00 00 00 00 00 00 00 00  0¬Ôhü···········
r13 0x00007fc0399e34a4  f2 00 08 00 60 95 fd ff 14 bd fd ff b0 fa cf ff  ò···`·ýÿ·½ýÿ°úÏÿ
r14 0x000055ed717bacb0  00 00 00 00 00 00 00 00 38 9a 9a 39 c0 7f 00 00  ········8··9À···
r15 0x00007fc039aafbc0  00 00 00 00 19 00 00 00 c0 de 07 a4 ed 55 00 00  ········ÀÞ·¤íU··
rip 0x00007fc039850730  4c 89 bd 70 ff ff ff 48 89 bd 78 ff ff ff 41 8b  L·½pÿÿÿH·½xÿÿÿA·

rflags 0x0000000000010202  

cs 0x0033  fs 0x0000  gs 0x0000


Images (18 omitted):

0x000055ed717b7000–0x000055ed717b9410 <no build ID>                            test            /tmp/tmpubrwnygi/test
0x00007fc039400000–0x00007fc039995930 b9f29f81b467904a40bdaaa0b0f84468865569b7 libswiftCore.so /tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/lib/swift/linux/libswiftCore.so

Backtrace took 0.09s



```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. Single production path plus own test, no adoption or runtime closure.
