FFmpeg 8.0.1 @894da5ca7d742e4429ffb2af534fcda0103ef593 - minimal static kit recipe (credential-free).
FETCH (public): git clone https://github.com/FFmpeg/FFmpeg.git && git checkout 894da5ca7d742e4429ffb2af534fcda0103ef593
  (or https://git.ffmpeg.org/ffmpeg.git - same public commit)
CONFIGURE (one line):
./configure --disable-programs --disable-doc --disable-everything --disable-avfilter --disable-avdevice --disable-swscale --disable-swresample --disable-x86asm --disable-asm --disable-debug --disable-zlib --disable-bzlib --disable-lzma --disable-iconv --disable-securetransport --disable-audiotoolbox --disable-videotoolbox --disable-coreimage --disable-appkit --disable-avfoundation --disable-metal --enable-protocol=file --enable-demuxer=mov --enable-decoder=mpeg4 --enable-demuxer=wav --enable-decoder=pcm_s16le --cc=gcc
BUILD: make -j$(nproc)  (produces static .a only; no programs)
EXPECTED ARTIFACT HASHES (Linux x86_64, gcc 11/12/13 - byte drift across gcc versions is possible;
if yours differ, record YOUR hashes in the run log - the pins below are the reference env's):
  libavformat/libavformat.a 4d6bca1b5e6c4b208214581568e9af22c1a09767d1f87872331f29c793072609
  libavcodec/libavcodec.a  28f20b25730b8d2feb0891f1a71ab23f077a6ccaf9ac9328ed5297d52beac4ed
  libavutil/libavutil.a    30d1381e09dbbfe12a85c9528d75decc78162c2682ec4bb11341f8968046df94
NOTE: kit has NO ppm/image2 demuxer+decoder - the -21 first-frame/trace-dump item is OUT OF SCOPE
here (separate local investigation, W-108 stage-2 does not need it).
