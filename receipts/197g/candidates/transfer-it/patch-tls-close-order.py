#!/usr/bin/env python3
import pathlib,sys
p=pathlib.Path(sys.argv[1])/'Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift';s=p.read_text()
# FFmpeg URLProtocol contexts may retain copies of AVIOInterruptCB; changing
# AVFormatContext alone cannot retire their opaque pointer. Keep slot alive
# until avformat_close_input has returned. Fence is cleared before teardown.
old='''                self.teardownInterruptLocked()
                self.activeSid'''
assert old in s;s=s.replace(old,'''                self.interruptSlot.clear()
                self.activeSid''')
old='''                if let fc = self.fmt { var f: UnsafeMutablePointer<AVFormatContext>? = fc; avformat_close_input(&f); self.fmt = nil }
'''
assert old in s;s=s.replace(old,old+'''                self.teardownInterruptLocked()
''')
old='''            self.teardownInterruptLocked()
            if let pkt=self.packet'''
assert old in s;s=s.replace(old,'''            self.interruptSlot.clear()
            if let pkt=self.packet''')
old='''            if let fc=self.fmt { var f:UnsafeMutablePointer<AVFormatContext>?=fc; avformat_close_input(&f) }
'''
assert old in s;s=s.replace(old,old+'''            self.teardownInterruptLocked()
''')
start=s.index('                // 195b-54: close retires')
end=s.index('                if let ctx',start)
s=s[:start]+'''                // Fence new requests now, but keep callback storage alive until
                // provider teardown completes. Nested protocol contexts may
                // hold copies of AVIOInterruptCB, including TLS shutdown.
'''+s[end:]
p.write_text(s)
