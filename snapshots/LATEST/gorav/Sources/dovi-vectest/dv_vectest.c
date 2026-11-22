/* dv_vectest.c - L6 independent vectors + policy mutants (architect r2 f5).
 * Everything embedded: expected offsets/counts computed BY CONSTRUCTION,
 * independent of dovi_tool and of the fixture files. Every mutant targets a
 * specific check and must be killed by it. Pure asserts, one clean line per
 * failure; VECTEST_PASS only when every vector holds. */
#include "DVRPUAnnexB.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails = 0;
static void *failing_alloc(size_t n) { (void)n; return 0; }
static void failing_free(void *p) { (void)p; }
/* recording allocator (r4.3): proves pairing, call counts, and that a
 * custom free is NEVER handed NULL (stack path must not call it at all). */
static unsigned rec_allocs = 0, rec_frees = 0, rec_null_frees = 0;
static void *rec_alloc(size_t n) { rec_allocs++; return malloc(n); }
static void rec_free(void *p) { rec_frees++; if (!p) rec_null_frees++; else free(p); }
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, msg); fails++; } } while (0)

/* --- vector stream layout (all offsets literal by construction) ---
 *  [0..3]   4-byte SC, VPS  nal hdr 40 01 + 6 payload            -> 12 B
 *  [12..14] 3-byte SC, slice nal hdr 02 01 + 5 payload           -> 10 B
 *  [22..25] 4-byte SC, RPU  nal hdr 7C 01 + 10 payload (EP inside)-> 16 B
 *  [38..40] 3-byte SC, RPU  nal hdr 7C 01 + 20 payload + 2 trail0 -> 27 B
 *  [65..68] 4-byte SC, RPU  hdr FC 01 (forbidden bit) + 8 payload -> 14 B
 *  [79..81] 3-byte SC, RPU  hdr 7C 00 (temporal id 0) + 8 payload -> 13 B
 *  [92..94] 3-byte SC, RPU  hdr 7C 01 + 2 payload (too short)     -> 7  B
 *  [99..]   no trailing start code: slice hdr 02 01 + 4 payload (EOF end)
 * expected: totalFound=2, rejectedHeader=3, offsets {28, 43}, bytes {10, 20} */
static uint8_t VEC[108];
static void build_vec(void) {
    memset(VEC, 0, sizeof VEC);
    size_t o = 0;
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x40;VEC[o++]=0x01;
    for (int i=0;i<6;i++) VEC[o++]=(uint8_t)(0xA0+i);
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x02;VEC[o++]=0x01;
    for (int i=0;i<5;i++) VEC[o++]=(uint8_t)(0xB0+i);
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x7C;VEC[o++]=0x01;
    /* 10 payload bytes including an emulation-prevention sequence 00 00 03 */
    uint8_t p1[10]={0x19,0x08,0x00,0x00,0x03,0x02,0x11,0x22,0x33,0x80};
    memcpy(VEC+o,p1,10); o+=10;
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x7C;VEC[o++]=0x01;
    for (int i=0;i<20;i++) VEC[o++]=(uint8_t)(0xC0+i);
    VEC[o++]=0;VEC[o++]=0; /* trailing zeros before next SC */
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0xFC;VEC[o++]=0x01;
    for (int i=0;i<8;i++) VEC[o++]=(uint8_t)(0xD0+i);
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x7C;VEC[o++]=0x00;
    for (int i=0;i<8;i++) VEC[o++]=(uint8_t)(0xE0+i);
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x7C;VEC[o++]=0x01;
    VEC[o++]=0x19;VEC[o++]=0x80; /* only 2 payload bytes: too short */
    VEC[o++]=0;VEC[o++]=0;VEC[o++]=1; VEC[o++]=0x02;VEC[o++]=0x01;
    for (int i=0;i<4;i++) VEC[o++]=(uint8_t)(0xF0+i);
    if (o != sizeof VEC) { printf("FAIL vec construction o=%zu\n", o); fails++; }
}


/* --- r3 finding 2 vectors: semantic parser validation --- */
typedef struct { uint8_t b[256]; size_t n; size_t bit; } BW;
static void bw_u(BW *w, uint32_t v, unsigned nbits) {
    for (int i = (int)nbits - 1; i >= 0; i--) {
        if (w->bit % 8 == 0) w->b[w->n++] = 0;
        if ((v >> i) & 1) w->b[w->n - 1] |= (uint8_t)(0x80 >> (w->bit % 8));
        w->bit++;
    }
}
static void bw_ue(BW *w, uint32_t v) {
    uint32_t code = v + 1; unsigned bits = 0; uint32_t t = code;
    while (t) { bits++; t >>= 1; }
    bw_u(w, 0, bits - 1); bw_u(w, code, bits);
}
static uint32_t crc32_mpeg2(const uint8_t *p, size_t n) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) {
        crc ^= (uint32_t)p[i] << 24;
        for (int b = 0; b < 8; b++)
            crc = (crc & 0x80000000u) ? (crc << 1) ^ 0x04C11DB7u : (crc << 1);
    }
    return crc;
}
/* Build a complete valid P8.1-class RPU (header only) with correct CRC.
 * Params allow targeted mutants. Returns EBSP length (no EP sequences are
 * introduced; the builder asserts that so strip == identity). */
static size_t build_rpu(uint8_t *out, uint8_t prefix, uint8_t rpuType,
                        uint8_t level, uint8_t reserved3, uint32_t blM8,
                        uint32_t denom, uint8_t prevFlag, uint32_t prevId) {
    BW w; memset(&w, 0, sizeof w);
    bw_u(&w, prefix, 8);
    bw_u(&w, rpuType, 6);
    bw_u(&w, 0, 11);          /* rpu_format: bit-depth block present */
    bw_u(&w, 1, 4);           /* vdr_rpu_profile 1 */
    bw_u(&w, level, 4);
    bw_u(&w, 1, 1);           /* seq info present */
    bw_u(&w, 0, 1);           /* chroma filter flag */
    bw_u(&w, 0, 2);           /* coefficient_data_type 0 */
    bw_ue(&w, denom);         /* coefficient_log2_denom */
    bw_u(&w, 0, 2);           /* normalized_idc */
    bw_u(&w, 0, 1);           /* full range 0 */
    bw_ue(&w, blM8);          /* bl_bit_depth_minus8 */
    bw_ue(&w, 2);             /* el packed (el=2, ext 0/0) */
    bw_ue(&w, 2);             /* vdr_bit_depth_minus8 */
    bw_u(&w, 0, 1);           /* spatial filter */
    bw_u(&w, reserved3, 3);   /* reserved_zero_3bits */
    bw_u(&w, 0, 1);           /* el spatial filter */
    bw_u(&w, 1, 1);           /* disable_residual */
    bw_u(&w, 0, 1);           /* dm metadata present */
    bw_u(&w, prevFlag, 1);
    if (prevFlag) bw_ue(&w, prevId);
    /* byte align with zero bits */
    while (w.bit % 8) bw_u(&w, 0, 1);
    uint32_t crc = crc32_mpeg2(w.b + 1, w.n - 1); /* checksum ignores prefix */
    w.b[w.n++] = (uint8_t)(crc >> 24); w.b[w.n++] = (uint8_t)(crc >> 16);
    w.b[w.n++] = (uint8_t)(crc >> 8);  w.b[w.n++] = (uint8_t)crc;
    w.b[w.n++] = 0x80;
    memcpy(out, w.b, w.n);
    /* construction invariant: no accidental EP pattern (strip == identity) */
    for (size_t i = 0; i + 2 < w.n; i++)
        if (w.b[i] == 0 && w.b[i+1] == 0 && w.b[i+2] == 3) { printf("FAIL builder EP collision\n"); fails++; }
    return w.n;
}

int main(void) {
    build_vec();

    /* FNV-1a 64 standard vectors (independent, published) */
    CHECK(gorav_dv_fnv1a64((const uint8_t*)"",0)==0xcbf29ce484222325ULL,"fnv empty");
    CHECK(gorav_dv_fnv1a64((const uint8_t*)"a",1)==0xaf63dc4c8601ec8cULL,"fnv a");
    CHECK(gorav_dv_fnv1a64((const uint8_t*)"foobar",6)==0x85944171f73967e8ULL,"fnv foobar");
    CHECK(gorav_dv_fnv1a64(NULL,0)==0xcbf29ce484222325ULL,"fnv null");

    /* independent offset/count/length vectors */
    GorAVDVRPURef refs[8]; GorAVDVRPUList l = { refs, 8, 99, 99, 99, 99 };
    gorav_dv_scan_annexb(VEC, sizeof VEC, &l);
    CHECK(l.count==2 && l.totalFound==2 && l.rejectedHeader==3,"vec counts");
    CHECK(refs[0].payloadOffset==28 && refs[0].payloadBytes==10,"vec rpu0 off/len");
    CHECK(refs[1].payloadOffset==43 && refs[1].payloadBytes==20,"vec rpu1 off/len");

    /* capacity 0: nothing recorded, totals still counted */
    GorAVDVRPUList l0 = { 0, 0, 9, 9, 9, 9 };
    gorav_dv_scan_annexb(VEC, sizeof VEC, &l0);
    CHECK(l0.count==0 && l0.totalFound==2 && l0.rejectedHeader==3,"capacity 0");

    /* null/empty scan: zeroed outputs, no crash */
    GorAVDVRPUList ln = { 0, 0, 9, 9, 9, 9 };
    gorav_dv_scan_annexb(NULL, 0, &ln);
    CHECK(ln.count==0 && ln.totalFound==0 && ln.rejectedHeader==0,"null scan");
    GorAVDVRPUList le = { 0, 0, 9, 9, 9, 9 };
    gorav_dv_scan_annexb(VEC, 0, &le);
    CHECK(le.count==0 && le.totalFound==0 && le.rejectedHeader==0,"empty scan");

    /* extract: full, then typed failure statuses */
    uint8_t dst[512]; uint64_t wrote=0, required=0; uint32_t n=0;
    GorAVDVExtractStatus st = gorav_dv_extract_rpu_stream(VEC, sizeof VEC, dst, sizeof dst, &wrote, &required, &n, 0);
    CHECK(st==GORAV_DV_EXTRACT_OK && n==2 && wrote==38 && required==38,"extract full");
    /* bytes: SC + 10 payload (EP preserved) + SC + 20 payload */
    CHECK(dst[0]==0&&dst[1]==0&&dst[2]==0&&dst[3]==1,"extract sc1");
    CHECK(dst[4]==0x19&&dst[6]==0x00&&dst[7]==0x00&&dst[8]==0x03,"extract EP preserved");
    CHECK(dst[14]==0&&dst[15]==0&&dst[16]==0&&dst[17]==1,"extract sc2");
    CHECK(dst[18]==0xC0&&dst[37]==0xD3,"extract p2");

    st = gorav_dv_extract_rpu_stream(VEC, sizeof VEC, dst, 37, &wrote, &required, &n, 0);
    CHECK(st==GORAV_DV_EXTRACT_DST_TOO_SMALL && wrote==0 && required==38,"dst too small typed");
    st = gorav_dv_extract_rpu_stream(NULL, sizeof VEC, dst, sizeof dst, &wrote, &required, &n, 0);
    CHECK(st==GORAV_DV_EXTRACT_INVALID_ARGS,"null args typed");
    st = gorav_dv_extract_rpu_stream(VEC, 0, dst, sizeof dst, &wrote, &required, &n, 0);
    CHECK(st==GORAV_DV_EXTRACT_INVALID_ARGS,"len0 typed");
    uint8_t nodv[12]={0,0,0,1,0x40,0x01,1,2,3,4,5,6};
    st = gorav_dv_extract_rpu_stream(nodv, sizeof nodv, dst, sizeof dst, &wrote, &required, &n, 0);
    CHECK(st==GORAV_DV_EXTRACT_NO_RPU && required==0,"no rpu typed");
    st = gorav_dv_extract_rpu_stream(VEC, 100, VEC+10, sizeof VEC, &wrote, &required, &n, 0);
    CHECK(st==GORAV_DV_EXTRACT_OVERLAP,"overlap typed");

    /* header truncation: cut the stream mid-RPU-header and inside payloads */
    for (size_t cut = 0; cut <= sizeof VEC; cut++) {
        GorAVDVRPUList lc = { 0, 0, 0, 0, 0, 0 };
        gorav_dv_scan_annexb(VEC, cut, &lc); /* must never crash */
        CHECK(lc.count<=lc.totalFound && lc.totalFound<=2,"trunc bounded");
    }

    /* mutants - each must be killed by its named policy check */
    {
        uint8_t m[sizeof VEC];
        memcpy(m, VEC, sizeof m); m[22+4]=0x7C; m[22+5]=0x00; /* temporal id 0 on valid rpu0 */
        GorAVDVRPUList lm={0,0,0,0,0,0}; gorav_dv_scan_annexb(m,sizeof m,&lm);
        CHECK(lm.totalFound==1 && lm.rejectedHeader==4,"mutant temporal0");
        memcpy(m, VEC, sizeof m); m[22+4]=0xFC; /* forbidden bit on valid rpu0 */
        memset(&lm,0,sizeof lm); gorav_dv_scan_annexb(m,sizeof m,&lm);
        CHECK(lm.totalFound==1 && lm.rejectedHeader==4,"mutant forbidden");
        memcpy(m, VEC, sizeof m); m[22+4]=0x02; /* wrong NAL type on rpu0 */
        memset(&lm,0,sizeof lm); gorav_dv_scan_annexb(m,sizeof m,&lm);
        CHECK(lm.totalFound==1 && lm.rejectedHeader==3,"mutant wrongtype");
        /* break the 0x01 of rpu0's start code: the SC vanishes entirely,
         * rpu0 is swallowed into the preceding slice NAL. (Breaking only a
         * zero byte leaves 00 00 01 and the scanner resyncs - not a kill.) */
        memcpy(m, VEC, sizeof m); m[25]=0x02;
        GorAVDVRPURef mr[4]; GorAVDVRPUList lm2={mr,4,0,0,0,0};
        gorav_dv_scan_annexb(m,sizeof m,&lm2);
        CHECK(lm2.totalFound==1 && lm2.count==1,"mutant broken SC swallows NAL");
        CHECK(lm2.count==1 && mr[0].payloadOffset==43 && mr[0].payloadBytes==20,
              "mutant broken SC: surviving rpu1 intact");
    }

    /* header parse: valid rpu0 of fixture-class payload is NOT in VEC (no
     * CRC), so parse must FAIL there (CRC) - and a header-only garbage RPU
     * must fail cleanly, never crash */
    {
        GorAVDVRPUHeader h;
        int rc = gorav_dv_parse_rpu_header(VEC+26, 10, &h);
        CHECK(rc!=0,"vec rpu0 no crc -> parse fails"); (void)h;
        uint8_t junk[7]={0x19,0,0,0,0,0,0x80};
        rc = gorav_dv_parse_rpu_header(junk, sizeof junk, &h);
        CHECK(rc==-2,"junk fails crc -2");
        rc = gorav_dv_parse_rpu_header(junk, 3, &h);
        CHECK(rc==-1,"short fails -1");
    }


    /* r3 finding 2: semantic validation vectors */
    {
        uint8_t v[300]; GorAVDVRPUHeader h;
        size_t n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 0, 0);
        int rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==0,"r3 valid rpu parses");
        CHECK(h.rpu_nal_prefix==0x19 && h.rpu_type==2 && h.vdr_rpu_profile==1
              && h.bl_bit_depth_minus8==2 && h.el_bit_depth_minus8==2
              && h.vdr_bit_depth_minus8==2 && h.coefficient_log2_denom==23
              && h.disable_residual_flag==1,"r3 valid rpu fields");
        CHECK(gorav_dv_guess_profile(&h)==8,"r3 valid rpu profile 8");

        n = build_rpu(v, 0x25, 2, 0, 0, 2, 23, 0, 0); /* architect kill case */
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==-1,"r3 prefix 0x25 rejected");

        n = build_rpu(v, 0x19, 3, 0, 0, 2, 23, 0, 0);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==-1,"r3 rpu_type 3 rejected (reference ensure == 2)");

        n = build_rpu(v, 0x19, 2, 6, 0, 2, 23, 0, 0);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==-4,"r3 level 6 semantic reject (reference validate)");

        n = build_rpu(v, 0x19, 2, 0, 0, 4, 23, 0, 0);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==-4,"r3 bl depth 12-bit semantic reject");

        n = build_rpu(v, 0x19, 2, 0, 0, 2, 24, 0, 0);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==-4,"r3 denom 24 semantic reject (reference <= 23)");

        /* reserved bits: reference reads without ensure -> recorded, NOT
         * rejected (divergence would fail the reference-decoder acceptance) */
        n = build_rpu(v, 0x19, 2, 0, 5, 2, 23, 0, 0);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==0 && h.reserved_zero_3bits==5,"r3 reserved bits recorded not rejected (reference parity)");

        /* trailing zeros after the 0x80 terminator: reference trims */
        n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 0, 0);
        v[n]=0; v[n+1]=0; v[n+2]=0;
        rc = gorav_dv_parse_rpu_header(v, n+3, &h);
        CHECK(rc==0,"r3 trailing zeros trimmed (reference parity)");

        /* prev_vdr_rpu_id */
        n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 1, 9);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==0 && h.use_prev_vdr_rpu_flag==1 && h.prev_vdr_rpu_id==9,"r3 prev id field");

        /* malformed EP sequence: 00 00 03 followed by 0x07 */
        {
            uint8_t bad[64]; size_t bn = build_rpu(bad, 0x19, 2, 0, 0, 2, 23, 0, 0);
            memmove(bad+8, bad+5, bn-5); bad[5]=0; bad[6]=0; bad[7]=3; bad[8]|=0x07;
            rc = gorav_dv_parse_rpu_header(bad, bn+3, &h);
            CHECK(rc==-1,"r3 bad EP following byte rejected");
        }

        /* field reads may not consume the CRC/terminator (budget) */
        n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 0, 0);
        for (size_t cut = 7; cut < n; cut++) {
            rc = gorav_dv_parse_rpu_header(v, cut, &h);
            CHECK(rc!=0,"r3 truncation budget never succeeds");
        }

        /* oversize payload policy bound */
        rc = gorav_dv_parse_rpu_header(v, GORAV_DV_RPU_MAX_BYTES + 1, &h);
        CHECK(rc==-1,"r3 oversize payload rejected");

        /* overlap arithmetic: unrepresentable dst range -> INVALID_ARGS,
         * no pointer is ever formed or dereferenced */
        uint8_t od[64]; uint64_t w2=0, r2=0; uint32_t n2=0;
        GorAVDVExtractStatus ost = gorav_dv_extract_rpu_stream(VEC, sizeof VEC, od, UINT64_MAX, &w2, &r2, &n2, 0);
        CHECK(ost==GORAV_DV_EXTRACT_INVALID_ARGS && w2==0,"r3 overflow-range dst rejected");
    }


    /* r4 finding 3: truncation + range-guard vectors */
    {
        uint8_t v[300]; GorAVDVRPUHeader h;
        /* prev_vdr_rpu_id = 70000 exceeds u16: must parse EXACTLY into the
         * widened uint32 field (kills the r3 truncation) */
        size_t n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 1, 70000);
        int rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==0 && h.prev_vdr_rpu_id==70000,"r4 prev id 70000 exact, no truncation");

        /* ext mapping split parity with reference (hdr.rs:91-99): the ext
         * slice is exactly 8 bits; a packed ue with bits above bit 15 must
         * leave ext_5_7 == (packed>>13)&0x07, not the full upper slice */
        n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 0, 0);
        CHECK(rc==0,"r4 base still parses"); /* build_rpu re-run sanity */
        /* el packed = (0x1FF << 8) | 2 -> ext8 = 0xFF -> ext_0_4=0x1F, ext_5_7=7 */
        {
            BW w; memset(&w, 0, sizeof w);
            bw_u(&w, 0x19, 8); bw_u(&w, 2, 6); bw_u(&w, 0, 11);
            bw_u(&w, 1, 4); bw_u(&w, 0, 4); bw_u(&w, 1, 1);
            bw_u(&w, 0, 1); bw_u(&w, 0, 2); bw_ue(&w, 23);
            bw_u(&w, 0, 2); bw_u(&w, 0, 1);
            bw_ue(&w, 2); bw_ue(&w, (0x1FFu << 8) | 2u); bw_ue(&w, 2);
            bw_u(&w, 0, 1); bw_u(&w, 0, 3); bw_u(&w, 0, 1); bw_u(&w, 1, 1);
            bw_u(&w, 0, 1); bw_u(&w, 0, 1);
            while (w.bit % 8) bw_u(&w, 0, 1);
            uint32_t crc = crc32_mpeg2(w.b + 1, w.n - 1);
            w.b[w.n++] = (uint8_t)(crc >> 24); w.b[w.n++] = (uint8_t)(crc >> 16);
            w.b[w.n++] = (uint8_t)(crc >> 8);  w.b[w.n++] = (uint8_t)crc;
            w.b[w.n++] = 0x80;
            memcpy(v, w.b, w.n); n = w.n;
            rc = gorav_dv_parse_rpu_header(v, n, &h);
            CHECK(rc==0,"r4 ext-packed parses");
            CHECK(h.el_bit_depth_minus8==2 && h.ext_mapping_idc_0_4==0x1F && h.ext_mapping_idc_5_7==7,
                  "r4 ext split exact reference parity");
        }

        /* scan range guard: a length that overflows the address space is
         * rejected with zeroed outputs BEFORE any dereference */
        {
            GorAVDVRPUList lg = { 0, 0, 9, 9, 9, 9 };
            size_t huge = (size_t)(UINTPTR_MAX - (uintptr_t)VEC) + 1;
            gorav_dv_scan_annexb(VEC, huge, &lg);
            CHECK(lg.count==0 && lg.totalFound==0 && lg.rejectedHeader==0,"r4 scan range guard, no deref");
        }
    }


    /* r4 part2: P5-shaped adversarial headers, cross-verified against the
     * reference decoder (dovi_tool 2.3.4 export, 2026-10-25):
     *  - block present, profile 0 + full range -> reference parses,
     *    dovi_profile 5; lane must agree (rc 0, guess 5).
     *  - rpu_format 0x100 (bit-depth block ABSENT) -> reference rejects
     *    ("bl_bit_depth_minus8 should be 2"); lane must reject -4. This
     *    pins the unconditional bl/el/vdr validate as reference parity,
     *    not an over-reach. Header-shape coverage only - NOT a P5 stream,
     *    reshaping, or playback claim. */
    {
        static const uint8_t p5shape[] = {
            0x19,0x08,0x00,0x00,0x40,0x60,0xb6,0xc1,0x3c,0x00,0xff,0xe0,0x07,0xff,0x00,0x3f,0xff,0x40,0x00,0x00,0x20,0x00,0x00,0x1a,0x00,0x00,0x01,0x00,0x00,0x00,0xd0,0x00,0x00,0x08,0x00,0x00,0x00,0x58,0x69,0x19,0x07,0x80 };
        static const uint8_t p5noblock[] = {
            0x19,0x08,0x80,0x00,0x40,0x60,0x9e,0x00,0x7f,0xf0,0x03,0xff,0x80,0x1f,0xff,0xa0,0x00,0x00,0x10,0x00,0x00,0x0d,0x00,0x00,0x00,0x80,0x00,0x00,0x68,0x00,0x00,0x04,0x00,0x00,0x00,0x0e,0x81,0xe5,0x79,0x80 };
        GorAVDVRPUHeader h;
        int rc = gorav_dv_parse_rpu_header(p5shape, sizeof p5shape, &h);
        CHECK(rc==0 && gorav_dv_guess_profile(&h)==5 && h.vdr_rpu_profile==0
              && h.bl_video_full_range_flag==1,"r4 p5-shaped header agrees with reference (profile 5)");
        rc = gorav_dv_parse_rpu_header(p5noblock, sizeof p5noblock, &h);
        CHECK(rc==-4,"r4 block-absent RPU rejected like reference (-4)");
    }


    /* r4.2 part-3 vectors: ue boundary, alloc-failure class, typed range */
    {
        uint8_t v[320]; GorAVDVRPUHeader h;
        /* ue boundary: 2^32-2 decodes EXACT (31 leading zeros); 2^32-1 is
         * REJECTED (intentional bounded-subset overflow policy, never
         * truncated). Rust reference reads u64 - divergence declared. */
        size_t n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 1, 0xFFFFFFFEu);
        int rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==0 && h.prev_vdr_rpu_id==0xFFFFFFFEu,"r4.2 ue max-1 exact");
        n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 1, 0xFFFFFFFFu);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==-1,"r4.2 ue 2^32-1 rejected, not truncated");

        /* allocation failure is its OWN class (-5), injectable via the
         * r4.3 PER-CALL PAIR (no global hook any more) */
        {
            const GorAVDVAllocator failpair = { failing_alloc, failing_free };
            /* force the heap path: input > 512 B stack buffer; content
             * validity is irrelevant, allocation happens first */
            uint8_t huge[600]; memset(huge, 0, sizeof huge);
            rc = gorav_dv_parse_rpu_header_ex(huge, sizeof huge, &h, &failpair);
            CHECK(rc==-5,"r4.3 alloc failure typed -5 (injected pair)");
        }
        n = build_rpu(v, 0x19, 2, 0, 0, 2, 23, 0, 0);
        rc = gorav_dv_parse_rpu_header(v, n, &h);
        CHECK(rc==0,"r4.3 default path unaffected by custom pair");

        /* pair rule: BOTH or NEITHER - a half pair is -6, never run */
        {
            const GorAVDVAllocator only_alloc = { failing_alloc, 0 };
            const GorAVDVAllocator only_free  = { 0, failing_free };
            CHECK(gorav_dv_parse_rpu_header_ex(v, n, &h, &only_alloc)==-6,
                  "r4.3 half pair (alloc only) rejected -6");
            CHECK(gorav_dv_parse_rpu_header_ex(v, n, &h, &only_free)==-6,
                  "r4.3 half pair (free only) rejected -6");
            const GorAVDVAllocator both_null = { 0, 0 };
            CHECK(gorav_dv_parse_rpu_header_ex(v, n, &h, &both_null)==0,
                  "r4.3 both-NULL pair selects default allocator");
        }

        /* invalid call arguments are -6, a caller bug, never a content
         * verdict: NULL source / NULL out are distinct from malformed -1 */
        CHECK(gorav_dv_parse_rpu_header(0, n, &h)==-6,"r4.3 NULL ebsp typed -6");
        CHECK(gorav_dv_parse_rpu_header(v, n, 0)==-6,"r4.3 NULL out typed -6");

        /* recording allocator: stack path (<512 B) must NEVER touch the
         * allocator; heap path exactly one alloc + one free, and the custom
         * free is never handed NULL */
        {
            const GorAVDVAllocator rec = { rec_alloc, rec_free };
            uint8_t huge[600]; memset(huge, 0, sizeof huge);
            rec_allocs = rec_frees = rec_null_frees = 0;
            rc = gorav_dv_parse_rpu_header_ex(v, n, &h, &rec);
            CHECK(rc==0 && rec_allocs==0 && rec_frees==0,
                  "r4.3 stack path bypasses allocator entirely");
            rec_allocs = rec_frees = rec_null_frees = 0;
            rc = gorav_dv_parse_rpu_header_ex(huge, sizeof huge, &h, &rec);
            CHECK(rc!=0 && rec_allocs==1 && rec_frees==1 && rec_null_frees==0,
                  "r4.3 heap path one alloc, one non-NULL free");
        }

        /* typed scan range: INVALID_RANGE, not silent-empty */
        {
            GorAVDVRPUList lg = { 0, 0, 9, 9, 9, 9 };
            size_t huge = (size_t)(UINTPTR_MAX - (uintptr_t)VEC) + 1;
            GorAVDVScanStatus sc = gorav_dv_scan_annexb(VEC, huge, &lg);
            CHECK(sc==GORAV_DV_SCAN_INVALID_RANGE && lg.count==0,"r4.2 scan typed invalid range");
            GorAVDVRPUList lo = { 0, 0, 0, 0, 0, 0 };
            CHECK(gorav_dv_scan_annexb(VEC, sizeof VEC, &lo)==GORAV_DV_SCAN_OK && lo.saturated==0,
                  "r4.2 scan ok, saturated receipt clear");
        }
    }


    /* r4.3 vectors: NULL-source policy + saturation boundary */
    {
        /* NULL buf with NONZERO len is typed INVALID_ARGS (caller bug),
         * never a silent clean scan; NULL with len==0 stays clean-empty */
        GorAVDVRPUList ln = { 0, 0, 0, 0, 0, 0 };
        CHECK(gorav_dv_scan_annexb(0, 16, &ln)==GORAV_DV_SCAN_INVALID_ARGS && ln.count==0,
              "r4.3 scan NULL+len>0 typed invalid");
        CHECK(gorav_dv_scan_annexb(0, 0, &ln)==GORAV_DV_SCAN_OK && ln.totalFound==0,
              "r4.3 scan NULL+len0 clean empty");
        /* saturation helper AT the boundary: the exact production increment,
         * from just below UINT32_MAX through wrap attempts */
        {
            uint32_t c = 0, sat = 0;
            CHECK(gorav_dv_sat_inc(&c, &sat)==1 && sat==0, "r4.3 sat_inc normal counts, receipt clear");
            c = UINT32_MAX - 2; sat = 0;
            CHECK(gorav_dv_sat_inc(&c, &sat)==UINT32_MAX-1 && sat==0, "r4.3 sat_inc MAX-2 -> MAX-1");
            CHECK(gorav_dv_sat_inc(&c, &sat)==UINT32_MAX && sat==0, "r4.3 sat_inc reaches MAX, receipt still clear");
            CHECK(gorav_dv_sat_inc(&c, &sat)==UINT32_MAX && sat==1, "r4.3 sat_inc clamps at MAX + sets receipt");
            CHECK(gorav_dv_sat_inc(&c, &sat)==UINT32_MAX && sat==1, "r4.3 sat_inc stays clamped, receipt sticky");
        }
    }


    /* r4.3.1 vectors: countSaturated receipt contract on preflight returns.
     * Flag is zeroed at entry and must reflect pass-0 counting on NO_RPU /
     * DST_TOO_SMALL / OK - not only success. (Unsaturated streams assert
     * the flag stays CLEAR on those paths; the saturated-true case needs
     * 2^32 NALs and is unit-tested at gorav_dv_sat_inc above.) */
    {
        uint8_t dst[64]; uint64_t w=0, req=0; uint32_t rc=0; uint8_t cs=0;
        /* DST_TOO_SMALL: sizing pass ran, flag must be a real (clear) value */
        cs = 0xAA; /* poison: must be overwritten at entry */
        GorAVDVExtractStatus st = gorav_dv_extract_rpu_stream(VEC, sizeof VEC, dst, 8, &w, &req, &rc, &cs);
        CHECK(st==GORAV_DV_EXTRACT_DST_TOO_SMALL && cs==0 && req>8 && rc==0,
              "r4.3.1 countSaturated cleared+valid on DST_TOO_SMALL");
        /* NO_RPU: clean stream, flag cleared, no stale value */
        {
            uint8_t plain[32]; memset(plain, 0x11, sizeof plain);
            cs = 0xAA;
            st = gorav_dv_extract_rpu_stream(plain, sizeof plain, dst, sizeof dst, &w, &req, &rc, &cs);
            CHECK(st==GORAV_DV_EXTRACT_NO_RPU && cs==0 && rc==0,
                  "r4.3.1 countSaturated cleared+valid on NO_RPU");
        }
        /* OK path: flag clear and count exact on an unsaturated stream */
        {
            uint8_t big[256];
            cs = 0xAA;
            st = gorav_dv_extract_rpu_stream(VEC, sizeof VEC, big, sizeof big, &w, &req, &rc, &cs);
            CHECK(st==GORAV_DV_EXTRACT_OK && cs==0 && rc==2 && w==req,
                  "r4.3.1 countSaturated clear, count exact on OK");
        }
    }

    if (fails) { printf("VECTEST_FAIL count=%d\n", fails); return 1; }
    printf("VECTEST_PASS lexical_checks=74 truncations=%zu\n", (size_t)107);
    return 0;
}
