/* DVRPUAnnexB.h - L6 Dolby Vision RPU extraction, Annex-B HEVC scan (r4.3).
 * Lane: gorav block 78 L6. Base: gorav trunk main c5f06bd (v1.4 exact base).
 *
 * SCOPE LABEL (architect review r2): this is FRAMING validation only -
 * start-code scan, NAL header policy, EBSP preservation. It is diagnostic
 * extraction, NOT semantic RPU or profile validation. No length-prefixed
 * HEVC (hvc1) and no AV1 (ITU-T T.35 OBU) claim: both are declared
 * extension points, not implemented.
 *
 * No FFmpeg dependency: byte-level scan, EBSP preserved (emulation
 * prevention bytes NOT removed) so output compares byte-exact against the
 * reference extractor (dovi_tool extract-rpu). */
#ifndef GORAV_DV_RPU_ANNEXB_H
#define GORAV_DV_RPU_ANNEXB_H

#include <stddef.h>
#include <stdint.h>

#define GORAV_DV_HEVC_NAL_RPU 62
/* Minimum RPU payload: 1 prefix byte + >=1 data byte + 4 CRC32 + 1 final
 * byte, grounded in the reference parser (dovi_rpu.rs: rpu_end >= 7). */
#define GORAV_DV_RPU_MIN_BYTES 7
/* Lane policy bound on one RPU payload for the parser's internal RBSP
 * buffer (parity with the Swift consumer's dvRPUMaxBytes). Real RPUs are
 * typically 150-400 B; larger inputs are rejected, never partially read. */
#define GORAV_DV_RPU_MAX_BYTES 1048576

typedef struct {
    uint64_t payloadOffset; /* offset of first payload byte (after 2-byte NAL header) */
    uint32_t payloadBytes;  /* EBSP payload length, header excluded, EP preserved  */
    uint64_t fnv1a64;       /* standard FNV-1a 64 over payload bytes (receipt only,
                               NOT a cryptographic integrity claim)                 */
} GorAVDVRPURef;

typedef struct {
    GorAVDVRPURef *items;   /* caller-provided storage                                */
    uint32_t capacity;      /* caller-provided capacity                               */
    uint32_t count;         /* out: valid RPU NALs recorded (capped at capacity)      */
    uint32_t totalFound;    /* out: valid RPU NALs seen even beyond capacity          */
    uint32_t rejectedHeader;/* out: type-62 candidates rejected on header policy      */
    uint32_t saturated;     /* out: nonzero iff any counter SATURATED at UINT32_MAX   */
                            /* (counts are then a lower bound, not exact - receipt)   */
} GorAVDVRPUList;

typedef enum {
    GORAV_DV_SCAN_OK = 0,           /* scanned; outputs valid                       */
    GORAV_DV_SCAN_INVALID_ARGS = 1, /* NULL out                                     */
    GORAV_DV_SCAN_INVALID_RANGE = 2 /* [buf, buf+len) not representable; NOTHING
                                       was read. NOTE: representability only -
                                       buffer ownership/liveness remain the
                                       caller's contract, never proven here.      */
} GorAVDVScanStatus;

/* Scan an in-memory Annex-B HEVC stream; record every VALID type-62 NAL.
 * All out fields are zeroed first. len==0 scans clean (all zero), with or
 * without a buffer. A NULL buf with a NONZERO len is
 * GORAV_DV_SCAN_INVALID_ARGS (r4.3): a null source claiming bytes is a
 * caller bug, never a valid empty source.
 *
 * Validity policy (framing only): a type-62 candidate is REJECTED (counted
 * in rejectedHeader, never in count/totalFound/extract) when
 *  - forbidden_zero_bit (header bit 7) is set; or
 *  - nuh_temporal_id_plus1 (header byte 1 low 3 bits) is zero; or
 *  - its EBSP payload is shorter than GORAV_DV_RPU_MIN_BYTES.
 * Rejection is a count, not a failure. */
GorAVDVScanStatus gorav_dv_scan_annexb(const uint8_t *buf, size_t len, GorAVDVRPUList *out);

typedef enum {
    GORAV_DV_EXTRACT_OK = 0,           /* at least one RPU written            */
    GORAV_DV_EXTRACT_NO_RPU = 1,       /* clean stream, zero valid RPUs       */
    GORAV_DV_EXTRACT_DST_TOO_SMALL = 2,/* required > dstCap; nothing written  */
    GORAV_DV_EXTRACT_INVALID_ARGS = 3, /* NULL buf/dst/written or len == 0    */
    GORAV_DV_EXTRACT_OVERLAP = 4       /* dst overlaps the source buffer      */
} GorAVDVExtractStatus;

/* One-shot extract into dovi_tool-compatible byte stream: for each VALID
 * RPU, writes 0x00000001 + EBSP payload (header stripped). Same validity
 * policy as the scan (single shared helper). required always receives the
 * byte count the full extraction needs, so DST_TOO_SMALL is retryable. */
GorAVDVExtractStatus gorav_dv_extract_rpu_stream(const uint8_t *buf, size_t len,
                                                 uint8_t *dst, uint64_t dstCap,
                                                 uint64_t *written, uint64_t *required,
                                                 uint32_t *rpuCount,
                                                 uint8_t *countSaturated /* optional; contract below */);
/* countSaturated contract (r4.3.1): zeroed at entry. Once the sizing pass
 * has scanned the stream, it is set iff counting saturated AT UINT32_MAX -
 * on EVERY later return (NO_RPU / DST_TOO_SMALL / size-overflow
 * INVALID_ARGS / OK), not only on success. It stays 0 on argument-reject
 * returns before any scan runs. A saturated rpuCount is a lower bound.
 * (Saturation itself is unit-tested at gorav_dv_sat_inc; an end-to-end
 * saturated stream would need 2^32 valid RPU NALs - infeasible.) */

/* Counter policy: count/totalFound/rejectedHeader (scan) and rpuCount
 * (extract) SATURATE at UINT32_MAX rather than wrap (r4). The single
 * increment below IS the policy, kept in one place so the near-maximum
 * boundary is unit-testable directly (dv_vectest.c r4.3 vectors) - an
 * end-to-end saturation run would need 2^32 valid RPU NALs and is
 * infeasible. Wiring (scan/extract call this on every hit) is exercised by
 * the ordinary vectors. */
static inline uint32_t gorav_dv_sat_inc(uint32_t *counter, uint32_t *saturatedFlag) {
    if (*counter < UINT32_MAX) return ++*counter;
    if (saturatedFlag) *saturatedFlag = 1;
    return *counter;
}

/* Standard FNV-1a 64 (offset basis 0xcbf29ce484222325, prime 0x100000001b3).
 * Receipt hash only; pinned by the standard vectors in dv_vectest.c. */
uint64_t gorav_dv_fnv1a64(const uint8_t *p, size_t n);

/* ---- RPU header parse (bounded subset, verified against reference) ----
 * Parses the fixed RPU header fields from one EBSP payload (as recorded by
 * the scan; EP bytes are stripped internally). Stops before
 * rpu_data_mapping; every field it reports is cross-checked against the
 * reference parser (dovi_tool) on the lane fixtures. Fields beyond this
 * subset are declared NOT_PARSED, never guessed. Field widths/order and the
 * CRC-32/MPEG-2 trailer are grounded in the reference parser source
 * (dolby_vision crate rpu_data_header.rs / dovi_rpu.rs). */
typedef struct {
    uint8_t  rpu_nal_prefix;
    uint8_t  rpu_type;
    uint16_t rpu_format;
    uint8_t  vdr_rpu_profile;
    uint8_t  vdr_rpu_level;
    uint8_t  vdr_seq_info_present_flag;
    /* valid only when vdr_seq_info_present_flag == 1: */
    uint8_t  chroma_resampling_explicit_filter_flag;
    uint8_t  coefficient_data_type;
    uint32_t coefficient_log2_denom;   /* ue(v), only when cdt == 0 */
    uint8_t  vdr_rpu_normalized_idc;
    uint8_t  bl_video_full_range_flag;
    uint32_t bl_bit_depth_minus8;      /* ue(v), only when bit_depth_block_present */
    uint32_t el_bit_depth_minus8;      /* ue(v) low 8 bits */
    uint8_t  ext_mapping_idc_0_4;      /* next 5 bits of the el ue(v) */
    uint8_t  ext_mapping_idc_5_7;      /* upper 3 bits of the el ue(v) */
    uint32_t vdr_bit_depth_minus8;     /* ue(v) */
    uint8_t  bit_depth_block_present;  /* rpu_format & 0x700 == 0 */
    uint8_t  reserved_zero_3bits;      /* recorded; reference reads without an ensure, so NOT rejected here */
    uint8_t  spatial_resampling_filter_flag;
    uint8_t  el_spatial_resampling_filter_flag;
    uint8_t  disable_residual_flag;
    uint8_t  vdr_dm_metadata_present_flag;
    uint8_t  use_prev_vdr_rpu_flag;
    uint32_t prev_vdr_rpu_id;      /* ue(v); reference type is u64 (hdr.rs:53); lane decodes up to 2^32-2 exactly, wider values are malformed (-1), never truncated */
} GorAVDVRPUHeader;

/* Optional PER-CALL allocator pair for the parser's internal RBSP buffer
 * (r4.3, replacing the r4.2 global hook the architect rejected): the pair
 * travels with ONE call, so there are no independently mutable globals -
 * nothing to race during a parse, and no way to mix allocator families
 * across calls. A NULL allocator pointer, or a pair with BOTH fields NULL,
 * selects the default malloc/free. EXACTLY ONE field set is an invalid
 * call (-6): both or neither, never a mismatched family. A custom free is
 * only ever invoked on a non-NULL pointer (the <512 B stack path never
 * touches the allocator at all).
 * CALLER CONTRACT (not library-provable, r4.3.1): C cannot prove two
 * function pointers belong to one allocator family or are thread-safe -
 * the caller MUST pass a matched alloc/free pair from one family, and the
 * pair must itself be thread-safe if parses run concurrently (the default
 * malloc/free are; the lane's own uses are matched test pairs). The
 * per-call shape removes cross-call mixing and global-state races; the
 * within-pair family match remains a contract, not a guarantee. */
typedef void *(*GorAVDVAllocFn)(size_t);
typedef void (*GorAVDVFreeFn)(void *);
typedef struct { GorAVDVAllocFn alloc; GorAVDVFreeFn free; } GorAVDVAllocator;
int gorav_dv_parse_rpu_header_ex(const uint8_t *ebsp, size_t len, GorAVDVRPUHeader *out,
                                 const GorAVDVAllocator *allocator);

/* ue(v) read bound (r4.2): up to 31 leading zeros, so the largest
 * DECODABLE value is 2^32-2; anything wider (the reference reads u64) is
 * rejected as malformed (-1). Intentional bounded-subset policy, pinned by
 * boundary vectors - values like 2^32-1 are REJECTED, never truncated. */

/* Returns 0 on success; -1 truncated/malformed (including prefix != 0x19,
 * rpu_type != 2, bad emulation-prevention sequence, oversize payload, or
 * field reads overrunning the CRC budget); -2 CRC32 or trailer mismatch;
 * -4 framed and CRC-valid but rejected by the reference parser's semantic
 * validate() (level/bit-depth/denom limits, see .c);
 * -5 internal allocation failure (distinct from content malformation, so
 * callers never classify a resource failure as corrupt content);
 * -6 invalid call arguments: NULL ebsp/out, or an allocator pair with
 * exactly one of alloc/free set (a CALLER bug, never a content verdict).
 * On nonzero return the struct contents are undefined.
 * gorav_dv_parse_rpu_header is the default-allocator form of
 * gorav_dv_parse_rpu_header_ex (allocator = NULL). */
int gorav_dv_parse_rpu_header(const uint8_t *ebsp, size_t len, GorAVDVRPUHeader *out);



#endif /* GORAV_DV_RPU_ANNEXB_H */

/* dovi_profile from parsed header fields, mirroring the reference rule
 * exactly (dolby_vision crate RpuDataHeader::get_dovi_profile):
 *  vdr_rpu_profile 0 + full range -> 5;  1 -> 8, or 7/4 when EL spatial
 *  resampling + residual enabled (vdr_bit_depth_minus8==4 -> 7 else 4);
 *  anything else -> 0 (unknown). Framing-level indicator, not a config-
 *  record claim: the config record (dvcC) is the authoritative source and
 *  needs the shim dovi_meta.h patch. */
uint8_t gorav_dv_guess_profile(const GorAVDVRPUHeader *h);
