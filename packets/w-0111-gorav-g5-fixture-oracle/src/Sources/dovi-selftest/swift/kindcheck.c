/* kindcheck.c - VERIFIES dvRPUBufferSideDataKind (23) against the pinned
 * FFmpeg n8.0.1 @ 894da5ca headers. Compile-only check, no link/run of
 * FFmpeg code. Output line goes to TESTLOG. */
#include <libavutil/frame.h>
#include <stdio.h>
_Static_assert(AV_FRAME_DATA_DOVI_RPU_BUFFER == 23, "dvRPUBufferSideDataKind mismatch");
int main(void) {
    printf("KINDCHECK_PASS AV_FRAME_DATA_DOVI_RPU_BUFFER=%d\n", (int)AV_FRAME_DATA_DOVI_RPU_BUFFER);
    return 0;
}
