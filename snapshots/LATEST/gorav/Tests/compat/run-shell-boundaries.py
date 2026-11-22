#!/usr/bin/env python3
"""Compile the actual Mac-shell boundary expressions against real receipt data.
Linux proof of these extracted contracts only, not an AppKit/CoreAudio build.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--swiftc', default='swiftc')
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
spsc = (root/'Sources/GorAVPlaybackCore/SPSC.swift').read_text()
start = spsc.index('public struct PCMRingReceipt:')
end = spsc.index('\n}', start) + 2
receipt = spsc[start:end]
sink = (root/'Sources/GorAVMacShell/AudioUnitSink.swift').read_text()
start = sink.index('            let residualFrames = receipt.pushedFrames')
end = sink.index('\n            let out =', start)
residual = sink[start:end]
shell = (root/'Sources/GorAVMacShell/ShellFrameSource.swift').read_text()
assert 'endState = .decodeFailed; return .failed(Int32(clamping: code))' in shell
conversion = shell[shell.index('return .failed(Int32(clamping: code))'):].split('\n', 1)[0]
# Real four-byte contract from the source, not an unrelated expected value.
assert 'public static let bytesPerFrame = 4' in spsc
swift = 'import Foundation\n' + receipt + '''
enum SPSCPCMRing { static let bytesPerFrame = 4 }
enum Event { case failed(Int32) }
func mapped(_ code: Int) -> Event { ''' + conversion + ''' }
func remaining(_ receipt: PCMRingReceipt) -> Int {
''' + residual + '''
return residual
}
func snapshot(_ pushed: UInt64, _ consumed: UInt64) -> PCMRingReceipt {
 PCMRingReceipt(generation: 1, requestedBytes: 0, admittedBytes: 0,
 droppedBytes: 0, partialTailDrops: 0, pushedFrames: pushed, droppedFrames: 0,
 consumedFrames: consumed, underrunFrames: 0, pushCount: 0, maxPushFrames: 0,
 maxAvailAfterPushFrames: 0, droppedAnything: false)
}
func check(_ ok: Bool, _ label: String) {
 if !ok { print("FAIL " + label); exit(1) }
}
check(remaining(snapshot(10,10)) == 0, "drained")
check(remaining(snapshot(23,7)) == 64, "held residual")
check(remaining(snapshot(7,23)) == 0, "malformed counters no underflow")
check(remaining(snapshot(UInt64.max,0)) == Int(UInt32.max)*4, "large clamp")
for (code,want) in [(Int(Int32.min),Int32.min),(Int(Int32.max),Int32.max),
                   (-22,Int32(-22)),(Int.min,Int32.min),(Int.max,Int32.max)] {
 guard case .failed(let got) = mapped(code) else { fatalError("lost failure path") }
 check(got == want, "nontrapping failure mapping")
}
print("SHELL_BOUNDARIES_PASS residual4 failure5; extracted contracts only")
'''
with tempfile.TemporaryDirectory(prefix='gorav-shell-boundaries-') as d:
    d = Path(d)
    (d/'main.swift').write_text(swift)
    subprocess.run([a.swiftc, '-swift-version', '6', '-strict-concurrency=complete',
                    '-warnings-as-errors', str(d/'main.swift'), '-o', str(d/'proof')], check=True)
    subprocess.run([str(d/'proof')], check=True)
