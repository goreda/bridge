# L6 r4 Swift consumer live test (Linux sandbox, NOT a Mac build)

Runs the r4 DVRPUSideData consumer against the REAL GorAVDVRPU C core
(header parse on the received copy) with a fake borrow modeling the
producer contract. No AVFrame, no CFFmpeg stubs.

  gcc -std=c99 -Wall -Wextra -Werror -O2 -c -I../../GorAVDVRPU/include \
    ../../GorAVDVRPU/src/DVRPUAnnexB.c -o dvrpu.o
  /tmp/swift/usr/bin/swiftc -O -I. \
    -Xcc -fmodule-map-file=$PWD/goravdvrpu.modulemap.testonly \
    ../../GorAVDolbyVision/DVRPUSideData.swift main.swift dvrpu.o \
    -o swiftbinding_test
  ./swiftbinding_test ../../fixtures-l6/rpu0.payload

Expected: SWIFTBINDING_PASS 9/9.

kindcheck.c: compiled _Static_assert that AV_FRAME_DATA_DOVI_RPU_BUFFER == 23
against the pinned FFmpeg n8.0.1 @ 894da5ca headers:

  gcc -std=c99 -Wall -Werror -I$FFMPEG_SRC kindcheck.c -o kindcheck && ./kindcheck

Expected: KINDCHECK_PASS AV_FRAME_DATA_DOVI_RPU_BUFFER=23

Run 2026-10-25 (Linux Swift 6.0.3, gcc 11): 9/9 PASS + KINDCHECK_PASS.
Consumer logic + types + C-core parse only; NOT a producer integration
claim (bridge is AUTHORED-UNCOMPILED pending L3 v4).
