#!/usr/bin/env python3
# Independent PCM oracle: integer stereo samples packed directly, no decoder,
# resampler, FFmpeg, network input or floating-point signal generator involved.
import pathlib,struct,wave,hashlib
root=pathlib.Path('fixtures');root.mkdir(exist_ok=True)
raw=b''.join(struct.pack('<hh', ((i*97)%60001)-30000, -(((i*97)%60001)-30000)) for i in range(44100))
(root/'archive-anchor.pcm').write_bytes(raw)
with wave.open(str(root/'anchor44100.wav'),'wb') as output:
    output.setnchannels(2);output.setsampwidth(2);output.setframerate(44100);output.writeframes(raw)
for name in ('anchor44100.wav','archive-anchor.pcm'):
    data=(root/name).read_bytes();print('ARCHIVE_ORACLE',name,len(data),hashlib.sha256(data).hexdigest())
