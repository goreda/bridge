/* DVRPUAnnexB.c - see header for contract. Pure C99, no dependencies. */
#include "DVRPUAnnexB.h"
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

uint64_t gorav_dv_fnv1a64(const uint8_t *p, size_t n) {
    uint64_t h = 14695981039346656037ULL; /* 0xcbf29ce484222325 */
    if (!p) return h;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 1099511628211ULL; }
    return h;
}

static size_t next_start_code(const uint8_t *b, size_t from, size_t len, size_t *scLen) {
    if (from >= len) return (size_t)-1;
    for (size_t i = from; i + 3 <= len; i++) {
        if (b[i] == 0 && b[i + 1] == 0) {
            if (b[i + 2] == 1) { *scLen = 3; return i; }
            if (i + 4 <= len && b[i + 2] == 0 && b[i + 3] == 1) { *scLen = 4; return i; }
        }
    }
    return (size_t)-1;
}

/* One NAL framing-validity check; shared by scan and extract so both apply
 * the exact same policy. Returns payload length when valid, 0 otherwise;
 * *isRpu distinguishes "not a type-62 NAL" from "rejected type-62". */
static size_t nal_rpu_payload(const uint8_t *buf, size_t hdr, size_t end, int *isRpu) {
    *isRpu = 0;
    if (hdr + 2 > end) return 0;
    if (((buf[hdr] >> 1) & 0x3F) != GORAV_DV_HEVC_NAL_RPU) return 0;
    *isRpu = 1;
    if (buf[hdr] & 0x80) return 0;            /* forbidden_zero_bit set   */
    if ((buf[hdr + 1] & 0x07) == 0) return 0; /* temporal_id_plus1 == 0   */
    while (end > hdr + 2 && buf[end - 1] == 0) end--;
    if (end - (hdr + 2) < GORAV_DV_RPU_MIN_BYTES) return 0;
    if (end - (hdr + 2) > UINT32_MAX) return 0; /* unrepresentable in the API: policy reject */
    return end - (hdr + 2);
}

GorAVDVScanStatus gorav_dv_scan_annexb(const uint8_t *buf, size_t len, GorAVDVRPUList *out) {
    if (!out) return GORAV_DV_SCAN_INVALID_ARGS;
    out->count = 0; out->totalFound = 0; out->rejectedHeader = 0; out->saturated = 0;
    /* r4.3: NULL buf with a NONZERO len is a caller bug (typed), never a
     * silent clean scan; len==0 stays a clean empty scan either way. */
    if (!buf) return len == 0 ? GORAV_DV_SCAN_OK : GORAV_DV_SCAN_INVALID_ARGS;
    if (len == 0) return GORAV_DV_SCAN_OK;
    /* Range guard (r4.2 TYPED): a [buf, buf+len) range that does not fit
     * the address space is unrepresentable; report INVALID_RANGE, read
     * nothing. Representability only - not an ownership proof. */
    if (len > (size_t)(UINTPTR_MAX - (uintptr_t)buf)) return GORAV_DV_SCAN_INVALID_RANGE;
    size_t scLen = 0;
    size_t pos = next_start_code(buf, 0, len, &scLen);
    while (pos != (size_t)-1) {
        size_t hdr = pos + scLen;
        if (hdr + 2 > len) break;
        size_t nextScLen = 0;
        size_t next = next_start_code(buf, hdr + 2, len, &nextScLen);
        size_t rawEnd = (next == (size_t)-1) ? len : next;
        int isRpu = 0;
        size_t payload = nal_rpu_payload(buf, hdr, rawEnd, &isRpu);
        if (isRpu && payload == 0) {
            gorav_dv_sat_inc(&out->rejectedHeader, &out->saturated);
        }
        if (payload > 0) {
            gorav_dv_sat_inc(&out->totalFound, &out->saturated); /* receipt: counts then a lower bound */
            if (out->items && out->count < out->capacity) {
                GorAVDVRPURef *r = &out->items[out->count++];
                r->payloadOffset = (uint64_t)(hdr + 2);
                r->payloadBytes = (uint32_t)payload;
                r->fnv1a64 = gorav_dv_fnv1a64(buf + hdr + 2, payload);
            }
        }
        if (next == (size_t)-1) break;
        pos = next; scLen = nextScLen; /* carry: next NAL's own start-code length */
    }
    return GORAV_DV_SCAN_OK;
}

GorAVDVExtractStatus gorav_dv_extract_rpu_stream(const uint8_t *buf, size_t len,
                                                 uint8_t *dst, uint64_t dstCap,
                                                 uint64_t *written, uint64_t *required,
                                                 uint32_t *rpuCount,
                                                 uint8_t *countSaturated) {
    if (written) *written = 0;
    if (required) *required = 0;
    if (rpuCount) *rpuCount = 0;
    if (countSaturated) *countSaturated = 0;
    if (!buf || !dst || !written || len == 0) return GORAV_DV_EXTRACT_INVALID_ARGS;
    /* Overflow-safe range overlap (r3): never form buf+len or dst+dstCap
     * when the addition could wrap; reject unrepresentable ranges. */
    {
        uintptr_t b = (uintptr_t)buf, d = (uintptr_t)dst;
        if (len > (size_t)(UINTPTR_MAX - b)) return GORAV_DV_EXTRACT_INVALID_ARGS;
        if (dstCap > (uint64_t)(UINTPTR_MAX - d)) return GORAV_DV_EXTRACT_INVALID_ARGS;
        if (d < b + len && b < d + (uintptr_t)dstCap) return GORAV_DV_EXTRACT_OVERLAP;
    }
    uint64_t need = 0; uint32_t n = 0; uint32_t satLocal = 0;
    for (int pass = 0; pass < 2; pass++) {
        uint64_t w = 0;
        size_t scLen = 0; size_t pos = next_start_code(buf, 0, len, &scLen);
        while (pos != (size_t)-1) {
            size_t hdr = pos + scLen; if (hdr + 2 > len) break;
            size_t nsl = 0; size_t next = next_start_code(buf, hdr + 2, len, &nsl);
            size_t rawEnd = (next == (size_t)-1) ? len : next;
            int isRpu = 0;
            size_t payload = nal_rpu_payload(buf, hdr, rawEnd, &isRpu);
            if (payload > 0) {
                if (pass == 0) {
                    if (need > UINT64_MAX - 4 - (uint64_t)payload) {
                        /* preflight error AFTER counting began: the receipt
                         * reflects counting so far (r4.3.1 contract). */
                        if (countSaturated && satLocal) *countSaturated = 1;
                        return GORAV_DV_EXTRACT_INVALID_ARGS;
                    }
                    need += 4 + (uint64_t)payload;
                    gorav_dv_sat_inc(&n, &satLocal); /* receipt: count then a lower bound */
                }
                else {
                    dst[w++] = 0; dst[w++] = 0; dst[w++] = 0; dst[w++] = 1;
                    memcpy(dst + w, buf + hdr + 2, payload); w += payload;
                }
            }
            if (next == (size_t)-1) break;
            pos = next; scLen = nsl; /* carry: next NAL's own start-code length */
        }
        if (pass == 0) {
            /* r4.3.1 receipt contract: once pass 0 has run, countSaturated
             * reflects pass-0 counting on EVERY return from here on
             * (NO_RPU / DST_TOO_SMALL / OK) - not only on success. */
            if (countSaturated && satLocal) *countSaturated = 1;
            if (required) *required = need;
            if (n == 0) return GORAV_DV_EXTRACT_NO_RPU;
            if (need > dstCap) return GORAV_DV_EXTRACT_DST_TOO_SMALL;
        } else {
            *written = w;
            if (rpuCount) *rpuCount = n;
            return GORAV_DV_EXTRACT_OK;
        }
    }
    return GORAV_DV_EXTRACT_INVALID_ARGS; /* unreachable */
}

/* ---- RPU header parse ---- */

typedef struct { const uint8_t *p; size_t n; size_t bit; int err; } GorAVBitRd;

static uint32_t br_u(GorAVBitRd *r, unsigned nbits) {
    uint32_t v = 0;
    for (unsigned i = 0; i < nbits; i++) {
        size_t byte = r->bit >> 3;
        if (byte >= r->n) { r->err = 1; return 0; }
        v = (v << 1) | ((r->p[byte] >> (7 - (r->bit & 7))) & 1);
        r->bit++;
    }
    return v;
}

static uint32_t br_ue(GorAVBitRd *r) {
    unsigned zeros = 0;
    while (!r->err && br_u(r, 1) == 0) { if (++zeros > 31) { r->err = 1; return 0; } }
    if (r->err) return 0;
    if (zeros == 0) return 0;
    return ((1u << zeros) - 1u) + br_u(r, zeros);
}

/* r4.3: parse body takes the allocator as a PER-CALL PAIR (resolved by the
 * public entry points) - no globals, nothing to race, no cross-call family
 * mixing. GORAV_DV_PARSE_DONE frees ONLY a non-NULL heap buffer: a custom
 * free is never handed NULL, and the <512 B stack path never touches the
 * allocator at all. */
static int parse_impl(const uint8_t *ebsp, size_t len, GorAVDVRPUHeader *out,
                      GorAVDVAllocFn allocFn, GorAVDVFreeFn freeFn) {
    if (len < GORAV_DV_RPU_MIN_BYTES || len > GORAV_DV_RPU_MAX_BYTES) return -1;
    /* EBSP -> RBSP: drop the 0x03 in 00 00 03 sequences */
    uint8_t stackbuf[512];
    uint8_t *rbsp = stackbuf;
    uint8_t *heap = 0;
#define GORAV_DV_PARSE_DONE(code) do { if (heap) freeFn(heap); return (code); } while (0)
    if (len > sizeof stackbuf) {
        heap = allocFn(len);
        if (!heap) return -5; /* resource failure, distinct from malformed */
        rbsp = heap;
    }
    size_t rn = 0;
    for (size_t i = 0; i < len; i++) {
        if (i + 2 < len && ebsp[i] == 0 && ebsp[i+1] == 0 && ebsp[i+2] == 3) {
            /* emulation prevention: 00 00 03 must be followed by 00..03
             * (HEVC 7.4.2.3); anything else is a malformed sequence. */
            if (i + 3 >= len || ebsp[i+3] > 3) GORAV_DV_PARSE_DONE(-1);
            rbsp[rn++] = 0; rbsp[rn++] = 0; i += 2;
            continue;
        }
        rbsp[rn++] = ebsp[i];
    }
    /* Trailing-zero trim BEFORE the terminator check, mirroring the
     * reference parser (dovi_rpu.rs parse: trailing zeroes ignored). */
    while (rn > 0 && rbsp[rn - 1] == 0) rn--;
    /* Trailer validation first, mirroring the reference parser (dovi_rpu.rs):
     * [...][crc32 u32 BE][0x80 final byte]; CRC-32/MPEG-2 over RBSP bytes
     * AFTER the prefix byte up to crc32 start. Distinct error -2. */
    if (rn < GORAV_DV_RPU_MIN_BYTES || rbsp[rn - 1] != 0x80) GORAV_DV_PARSE_DONE(-1);
    size_t crcStart;
    {
        crcStart = rn - 5;
        uint32_t want = ((uint32_t)rbsp[crcStart] << 24) | ((uint32_t)rbsp[crcStart+1] << 16) |
                        ((uint32_t)rbsp[crcStart+2] << 8) | (uint32_t)rbsp[crcStart+3];
        uint32_t crc = 0xFFFFFFFFu;
        for (size_t i = 1; i < crcStart; i++) {
            crc ^= (uint32_t)rbsp[i] << 24;
            for (int b = 0; b < 8; b++)
                crc = (crc & 0x80000000u) ? (crc << 1) ^ 0x04C11DB7u : (crc << 1);
        }
        if (crc != want) GORAV_DV_PARSE_DONE(-2);
    }
    /* Field budget ends at the CRC (r3 finding 2): the reader may not
     * consume CRC/terminator bytes as field data. */
    GorAVBitRd r = { rbsp, crcStart, 0, 0 };
    GorAVDVRPUHeader h;
    memset(&h, 0, sizeof h);
    h.rpu_nal_prefix = (uint8_t)br_u(&r, 8);
    if (h.rpu_nal_prefix != 0x19) GORAV_DV_PARSE_DONE(-1); /* reference: ensure == 25 */
    h.rpu_type = (uint8_t)br_u(&r, 6);
    h.rpu_format = (uint16_t)br_u(&r, 11);
    h.vdr_rpu_profile = (uint8_t)br_u(&r, 4);
    h.vdr_rpu_level = (uint8_t)br_u(&r, 4);
    h.vdr_seq_info_present_flag = (uint8_t)br_u(&r, 1);
    if (h.vdr_seq_info_present_flag) {
        h.chroma_resampling_explicit_filter_flag = (uint8_t)br_u(&r, 1);
        h.coefficient_data_type = (uint8_t)br_u(&r, 2);
        if (h.coefficient_data_type == 0) h.coefficient_log2_denom = br_ue(&r);
        h.vdr_rpu_normalized_idc = (uint8_t)br_u(&r, 2);
        h.bl_video_full_range_flag = (uint8_t)br_u(&r, 1);
        /* coefficient_data_type == 1 adds NO bitstream field; cdt >= 2 is
         * invalid (reference: rpu_data_header.rs). */
        if (h.coefficient_data_type >= 2) GORAV_DV_PARSE_DONE(-1);
        h.bit_depth_block_present = (h.rpu_format & 0x700) == 0;
        if (h.bit_depth_block_present) {
            uint32_t el_packed;
            h.bl_bit_depth_minus8 = br_ue(&r);
            el_packed = br_ue(&r);
            /* Reference split (hdr.rs:91-99): el = packed & 0xFF; the NEXT
             * 8 bits form ext_mapping_idc (reference truncates with as u8);
             * ext_0_4 = low 5 of that, ext_5_7 = that >> 5. No wider slice
             * of the ue(v) is ever exposed - parity, not truncation. */
            {
                uint32_t ext8 = (el_packed >> 8) & 0xFF;
                h.el_bit_depth_minus8 = el_packed & 0xFF;
                h.ext_mapping_idc_0_4 = ext8 & 0x1F;
                h.ext_mapping_idc_5_7 = ext8 >> 5;
            }
            h.vdr_bit_depth_minus8 = br_ue(&r);
            h.spatial_resampling_filter_flag = (uint8_t)br_u(&r, 1);
            h.reserved_zero_3bits = (uint8_t)br_u(&r, 3); /* recorded, not rejected: reference reads without ensure */
            h.el_spatial_resampling_filter_flag = (uint8_t)br_u(&r, 1);
            h.disable_residual_flag = (uint8_t)br_u(&r, 1);
        }
    }
    if (h.rpu_type != 2) GORAV_DV_PARSE_DONE(-1); /* reference hdr.rs:59 ensure(rpu_type == 2) */
    h.vdr_dm_metadata_present_flag = (uint8_t)br_u(&r, 1);
    h.use_prev_vdr_rpu_flag = (uint8_t)br_u(&r, 1);
    if (h.use_prev_vdr_rpu_flag) h.prev_vdr_rpu_id = br_ue(&r);
    if (r.err) GORAV_DV_PARSE_DONE(-1);
    /* Semantic validation mirroring the reference DoviRpu::parse ->
     * RpuDataHeader::validate (hdr.rs). Distinct return -4 so callers can
     * tell a well-framed but reference-invalid RPU from a malformed one.
     * Reference limits: level==0, bl==el==2 (10-bit), vdr<=6, denom<=23,
     * profile/header consistency. NOTE: these reject RPUs the reference
     * decoder itself rejects; P5 streams have no bit-depth block and their
     * own validate arm (vdr_rpu_profile==0 + full range). */
    if (h.vdr_rpu_level != 0) GORAV_DV_PARSE_DONE(-4);
    /* Unconditional, exactly like the reference validate(): when the
     * bit-depth block is absent the fields stay 0 and the reference
     * rejects the RPU the same way. */
    if (h.bl_bit_depth_minus8 != 2 || h.el_bit_depth_minus8 != 2 ||
        h.vdr_bit_depth_minus8 > 6) GORAV_DV_PARSE_DONE(-4);
    if (h.coefficient_log2_denom > 23) GORAV_DV_PARSE_DONE(-4);
    /* The reference's profile-consistency arms (hdr.rs validate: 5/7/8)
     * are NOT mirrored: they are called with get_dovi_profile()'s own
     * output (dovi_rpu.rs:148-158), so they reduce to identities - keeping
     * them would be a tautological check pretending to validate. The
     * non-vacuous arms above (level/depths/denom) carry the actual weight.
     * An UNKNOWN guessed profile (0) is NOT a rejection: the reference
     * does not reject it either, and an unknown guess is distinct from a
     * configuration-record claim. */
    *out = h;
    GORAV_DV_PARSE_DONE(0);
#undef GORAV_DV_PARSE_DONE
}

int gorav_dv_parse_rpu_header_ex(const uint8_t *ebsp, size_t len, GorAVDVRPUHeader *out,
                                 const GorAVDVAllocator *allocator) {
    if (!ebsp || !out) return -6; /* caller bug, never a content verdict */
    /* Pair rule (r4.3): both or neither - a half pair is a family mismatch
     * waiting to happen, rejected typed before any work. */
    if (allocator && ((allocator->alloc == 0) != (allocator->free == 0))) return -6;
    if (allocator && allocator->alloc)
        return parse_impl(ebsp, len, out, allocator->alloc, allocator->free);
    return parse_impl(ebsp, len, out, malloc, free);
}

int gorav_dv_parse_rpu_header(const uint8_t *ebsp, size_t len, GorAVDVRPUHeader *out) {
    return gorav_dv_parse_rpu_header_ex(ebsp, len, out, 0);
}

uint8_t gorav_dv_guess_profile(const GorAVDVRPUHeader *h) {
    if (!h) return 0;
    if (h->vdr_rpu_profile == 0) return h->bl_video_full_range_flag ? 5 : 0;
    if (h->vdr_rpu_profile == 1) {
        if (h->el_spatial_resampling_filter_flag && !h->disable_residual_flag)
            return h->vdr_bit_depth_minus8 == 4 ? 7 : 4;
        return 8;
    }
    return 0;
}
