# FFmpeg Linux-host minimal kit recipe (OHAL line)

Scope: Linux host build capability repair only. Not a Mac-native or product qualification statement.
No decoder/production source change; NH6 bytes untouched.

## Root cause (VDV4, confirmed 2026-10-26)
Prior local recipe built FFmpeg 894da5ca with mov/mpeg4/wav/pcm_s16le only. CONFIG_IMAGE_PPM_PIPE_DEMUXER=0
and CONFIG_PPM_DECODER=0, so av_find_input_format("ppm_pipe") returned NULL and the adapter raised
NativeError -21 before openInput on the PPM route. Mac kit build.command already carried both flags;
the Linux host recipe was the gap.

## Fix
flags-894da5ca.txt adds exactly two flags to the prior recipe:
--enable-demuxer=image_ppm_pipe --enable-decoder=ppm
Verified in built tree: config_components.h 53be46de008c013342a0b18e54da13a9fb89f269b8146fedb652b908ea4e1401 has both = 1;
ff_image_ppm_pipe_demuxer is a defined symbol in the new libavformat.a.

## Pins (full sha256)
OLD kit (retained, rollback/reference):
- libavformat.a 4d6bca1b5e6c4b208214581568e9af22c1a09767d1f87872331f29c793072609
- libavcodec.a  28f20b25730b8d2feb0891f1a71ab23f077a6ccaf9ac9328ed5297d52beac4ed
- libavutil.a   30d1381e09dbbfe12a85c9528d75decc78162c2682ec4bb11341f8968046df94
NEW kit (candidate, this recipe):
- libavformat.a d72a3bd708af763f92a9e42d6cb91a9df1e602926f65a098bef3a2dac572dd2f
- libavcodec.a  52f9e86fe92b748b6c140e0a3ec68ec31c4e1e9c2186537fc2115729bb47c24c
- libavutil.a   058a66b7f8588b973889c46af6938eea767071caf22c815113026f4f076841c6

## Runtime evidence (Linux host, swift 6.1.2, GORAV_KIT real fixtures; scoped host evidence, not Mac/product)
- gorav-first-frame: GORAV_FIRST_FRAME_PASS, "opened: codec=ppm 17x11", clean closeReport. Actual PPM pipe route.
- trace-dump: exit 0, wrote real oracle JSONs (trace-path-route.json, trace-snapshot-route.json).
- Regression battery 13/13 green vs new kit: seek-composition, refusal (bad=0), audio-refusal, video-refusal,
  core-seek 16/0, seek-pacing, seek-contract 61/0, k9-adversarial (12 run, 2 mac-deferred), audio-test,
  timing-ledger, seek-ring-reset, gorav-first-frame.

## Rollback
Old libs/pins untouched; revert to old kit by pointing the module chain at the old lib paths and pins above.
