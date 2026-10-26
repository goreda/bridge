/* dv_fuzz.c - bounded fuzz over the L6 core (architect r2 f5).
 * Deterministic PRNG; three modes over the real fixture bytes:
 *  1) uniform random buffers (0..2048 B)
 *  2) dv81.hevc with k random single-byte mutations
 *  3) dv81.hevc truncated to random length
 * Every input runs scan + extract + header-parse over extracted RPUs.
 * Any sanitizer abort or invariant break fails the run. */
#include "DVRPUAnnexB.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t rs = 0x243F6A8885A308D3ULL;
static uint64_t rnd(void){ rs^=rs<<13; rs^=rs>>7; rs^=rs<<17; return rs; }

static uint8_t *slurp(const char *p, size_t *n){ FILE*f=fopen(p,"rb"); if(!f)return 0;
    fseek(f,0,SEEK_END); long l=ftell(f); fseek(f,0,SEEK_SET);
    uint8_t*b=malloc(l); if(fread(b,1,l,f)!=(size_t)l){fclose(f);free(b);return 0;} fclose(f); *n=l; return b; }

static void exercise(const uint8_t *b, size_t n) {
    GorAVDVRPURef refs[512]; GorAVDVRPUList l = { refs, 512, 0, 0, 0, 0 };
    gorav_dv_scan_annexb(b, n, &l);
    if (l.count > l.totalFound || l.totalFound > 512*64) { printf("FAIL invariant\n"); exit(1); }
    uint64_t cap = n + 4096;
    uint8_t *dst = malloc(cap);
    uint64_t wrote=0, required=0; uint32_t cnt=0;
    GorAVDVExtractStatus st = gorav_dv_extract_rpu_stream(b, n, dst, cap, &wrote, &required, &cnt, 0);
    if (st==GORAV_DV_EXTRACT_OK && (cnt==0 || wrote != required)) { printf("FAIL extract invariant\n"); exit(1); }
    if (st==GORAV_DV_EXTRACT_OK) {
        /* parse every extracted RPU header: must never crash; any rc allowed */
        size_t i=0; uint32_t parsed=0;
        while (i+4 < wrote && parsed<cnt) {
            size_t sc = (dst[i]==0&&dst[i+1]==0&&dst[i+2]==0&&dst[i+3]==1)?4:3;
            size_t start=i+sc, j=start;
            while (j+3<=wrote && !(dst[j]==0&&dst[j+1]==0&&(dst[j+2]==1||(j+4<=wrote&&dst[j+2]==0&&dst[j+3]==1)))) j++;
            size_t end=j; while (end>start && dst[end-1]==0) end--;
            GorAVDVRPUHeader h; (void)gorav_dv_parse_rpu_header(dst+start, end-start, &h);
            parsed++; i=j;
        }
    }
    free(dst);
}

int main(int argc, char **argv) {
    (void)argc;
    size_t baseLen=0; uint8_t *base = slurp(argv[1], &baseLen);
    if (!base) { printf("FAIL read fixture\n"); return 1; }
    uint8_t *work = malloc(baseLen ? baseLen : 1);
    int iters = 3000;
    for (int it=0; it<iters; it++) {
        int mode = it % 3;
        if (mode==0) {
            size_t n = rnd()%2048;
            for (size_t i=0;i<n;i++) work[i]=(uint8_t)rnd();
            exercise(work, n);
        } else if (mode==1) {
            memcpy(work, base, baseLen);
            int k = 1 + (int)(rnd()%8);
            for (int j=0;j<k;j++) work[rnd()%baseLen] ^= (uint8_t)(1u<<(rnd()%8));
            exercise(work, baseLen);
        } else {
            size_t n = rnd()%(baseLen+1);
            exercise(base, n);
        }
    }
    printf("FUZZ_PASS iterations=%d modes=3\n", iters);
    free(work); free(base);
    return 0;
}
