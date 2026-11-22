"""Portable production LiveCaptionDiagnostics test at its admitted-sink boundary.

The complete production class, including its unused-by-injection default append
method, is compiled without rewriting it. Its only project collaborator is
DiagSessionSink.append(Data) -> Bool. A recording implementation of that exact
boundary also exercises the real default initializer and asynchronous append.
This is NOT a test of native sink admission, tagging, caps, disk IO or drain.
"""
from pathlib import Path
import importlib.util
import os
import re
import subprocess
import tempfile

r=Path(__file__).resolve().parents[2]
_spec=importlib.util.spec_from_file_location('live_caption_diagnostic_sections',r/'Tests/Structure/section_source.py')
_sections=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_sections)
s=_sections.symbol_text(r,'LiveCaptionDiagnostics',kind='class')+'\n'
sink_source=_sections.symbol_text(r,'DiagSessionSink',kind='enum')
assert re.search(r'(?m)^    static func append\(_ data: Data\) -> Bool \{',sink_source),'review changed admitted-sink append contract'


# Fail closed if this class acquires another project type. This is a bounded
# source contract, not a general Swift dependency resolver. Foundation/Dispatch
# supply Data, Date, UUID, NSRecursiveLock, DispatchQueue and the string APIs.
project_types=set()
for path in _sections.swift_files(r):
    for line in path.read_text().splitlines():
        match=_sections._DECL.match(line)
        if match and match.group('kind')!='extension':
            project_types.add(match.group('name'))
project_refs=set(re.findall(r'\b[A-Za-z_][A-Za-z0-9_]*\b',s)) & project_types
assert project_refs=={'LiveCaptionDiagnostics','DiagSessionSink'},('review changed LiveCaptionDiagnostics project closure',sorted(project_refs))

boundary='''
// Explicit recording collaborator, NOT the production session sink. No native
// context, allocator, filesystem, StagedRunPaths or fallback log is involved.
// The production class sees the real sink's exact append(Data) -> Bool surface.
enum DiagSessionSink {
    private static let lock=NSLock()
    private static let available=DispatchSemaphore(value:0)
    nonisolated(unsafe) private static var records:[Data]=[]
    @discardableResult
    static func append(_ data:Data)->Bool {
        lock.lock();records.append(data);lock.unlock()
        available.signal()
        return true
    }
    static func waitForRows(_ count:Int)->[Data] {
        for _ in 0..<count {
            precondition(available.wait(timeout:.now()+5) == .success,"default diagnostic sink delivery timed out")
        }
        lock.lock();defer{lock.unlock()}
        return records
    }
}
'''
test='''
var rows:[String]=[]
let d=LiveCaptionDiagnostics(sink:{rows.append($0)})
d.begin(model:"small",threads:4,window:6,step:1,language:"tr",vad:true)
let timing="[dbg] whisper_full returned 0 (window.size()=96000, took 1234ms, wf_ms_ema=1200ms, current_step=1380ms, tick=2, wall=5.2s)"
let input="[dbg] raw text=PRIVATE TRANSCRIPT\\n"+timing+"\\nwhisper_init_state: Core ML model loaded\\nsystem_info: COREML = 1 | METAL = 0 | NEON = 1\\nggml_metal_init: using device Private GPU Name\\n[dbg] whisper_full returned PRIVATE\\n"
let privatePaths="load_model: /PRIVATE/TRANSCRIPT.txt\\n"+"ggml_metal_init: loaded /PRIVATE/Backend.metallib\\n"
let bytes=Array((input+privatePaths).utf8)
for byte in bytes {d.ingest(Data([byte]))}
precondition(rows.contains{$0.contains(timing)})
precondition(rows.contains{$0.contains("language=tr") && $0.contains("threads=4")})
precondition(rows.contains{$0.contains("coreml-loaded")})
precondition(rows.contains{$0.contains("metal-init-observed")})
precondition(!rows.joined().contains("PRIVATE") && !rows.joined().contains("Private GPU"))
print("PASS production session diagnostics: fragmented stderr, exact timing, fixed backend labels, transcript/path exclusion")

// The production default method is compiled AND executed, not merely hidden
// behind the custom sink. Compare all forwarded bytes after its documented
// timestamp/newline framing and fresh session identity are accounted for.
let routed=LiveCaptionDiagnostics()
routed.begin(model:"small",threads:4,window:6,step:1,language:"tr",vad:true)
for byte in bytes {routed.ingest(Data([byte]))}
let forwarded=DiagSessionSink.waitForRows(rows.count)
precondition(forwarded.count==rows.count)
let actual=forwarded.map {data->String in
    guard let text=String(data:data,encoding:.utf8),text.hasSuffix("\\n"),
          let space=text.firstIndex(of:" "),let timestamp=Double(text[..<space]) else {
        preconditionFailure("invalid production default append framing")
    }
    precondition(timestamp.isFinite && timestamp>0)
    return String(text[text.index(after:space)...].dropLast())
}
let expected=rows.map{$0.replacingOccurrences(of:d.session,with:routed.session)}
precondition(actual==expected,"default sink changed sanitized diagnostic rows")
precondition(!actual.joined().contains("PRIVATE") && !actual.joined().contains("Private GPU"))
print("PASS real default async append: complete recording boundary, exact ordered Data rows, timestamp/newline framing and privacy parity; native sink lifecycle NOT_TESTED")
'''
with tempfile.TemporaryDirectory() as d:
    p=Path(d);(p/'main.swift').write_text('import Foundation\n'+boundary+s+test)
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',d+'/test'],check=True)
    subprocess.run([d+'/test'],check=True)
controller=_sections.section_text_exact(r,'LiveCaptionController.swift')
assert '"--threads", String(threads)' in controller and '"-l", preferredLanguage ?? "auto"' in controller
assert 'diagnostics.ingest(data)' in controller
print('PASS actual launch bindings: threads explicit default4, existing selected language unchanged, stderr diagnostic ingestion')
