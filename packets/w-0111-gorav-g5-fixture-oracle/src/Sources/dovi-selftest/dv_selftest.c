/* dv_selftest.c - L6 self-test driver (offline, no FFmpeg needed). r2:
 * typed extract status; standard FNV-1a receipts.
 * Usage: dv_selftest <input.hevc> <expected-rpu.bin>
 * 1) scans input for valid type-62 RPU NALs, prints per-RPU receipts
 *    (index, payloadBytes, fnv1a64) to stdout;
 * 2) extracts dovi_tool-compatible RPU stream and byte-compares
 *    against <expected-rpu.bin> (reference extractor output);
 * 3) exit 0 only when status OK and bytes are identical;
 *    stops at first failure with one clean line (75d style). */
#include "DVRPUAnnexB.h"
#include <stdio.h>
#include <stdlib.h>

static uint8_t *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return 0; }
    uint8_t *b = malloc((size_t)n ? (size_t)n : 1);
    if (!b || (n && fread(b, 1, (size_t)n, f) != (size_t)n)) { fclose(f); free(b); return 0; }
    fclose(f); *len = (size_t)n; return b;
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: dv_selftest <in.hevc> <expected-rpu.bin>\n"); return 2; }
    size_t hvLen = 0, exLen = 0;
    uint8_t *hv = slurp(argv[1], &hvLen);
    if (!hv) { printf("FAIL stage=read_input file=%s\n", argv[1]); return 1; }
    uint8_t *ex = slurp(argv[2], &exLen);
    if (!ex) { printf("FAIL stage=read_expected file=%s\n", argv[2]); free(hv); return 1; }

    uint64_t cap = hvLen + 4096;
    uint8_t *out = malloc(cap);
    uint64_t wrote = 0, required = 0; uint32_t n = 0;
    GorAVDVExtractStatus st = gorav_dv_extract_rpu_stream(hv, hvLen, out, cap, &wrote, &required, &n, 0);
    if (st != GORAV_DV_EXTRACT_OK) { printf("FAIL stage=extract status=%d rpucount=%u\n", (int)st, n); return 1; }

    GorAVDVRPURef *refs = malloc(sizeof(GorAVDVRPURef) * n);
    GorAVDVRPUList list = { refs, n, 0, 0, 0, 0 };
    gorav_dv_scan_annexb(hv, hvLen, &list);
    if (list.count != n || list.totalFound != n) {
        printf("FAIL stage=scan_consistency extract=%u scan=%u total=%u\n", n, list.count, list.totalFound);
        return 1;
    }
    for (uint32_t i = 0; i < n; i++)
        printf("rpu[%u] payloadBytes=%u fnv1a64=%016llx\n", i, refs[i].payloadBytes,
               (unsigned long long)refs[i].fnv1a64);

    if (wrote != exLen) {
        printf("FAIL stage=length ours=%llu ref=%llu\n", (unsigned long long)wrote, (unsigned long long)exLen);
        return 1;
    }
    for (uint64_t i = 0; i < wrote; i++) {
        if (out[i] != ex[i]) {
            printf("FAIL stage=bytes at=%llu ours=%02x ref=%02x\n", (unsigned long long)i, out[i], ex[i]);
            return 1;
        }
    }
    printf("SELFTEST_PASS rpucount=%u bytes=%llu rejectedHeader=%u\n",
           n, (unsigned long long)wrote, list.rejectedHeader);
    free(refs); free(out); free(ex); free(hv);
    return 0;
}
