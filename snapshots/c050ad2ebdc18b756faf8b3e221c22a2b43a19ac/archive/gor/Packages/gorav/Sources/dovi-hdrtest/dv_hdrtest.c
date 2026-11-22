/* dv_hdrtest.c - L6 header-parse cross-check against reference JSON.
 * Usage: dv_hdrtest <input.hevc> <ref-fields.txt> [ref-profiles.txt]
 * ref-fields.txt: one line per RPU, 18 comma-separated fields in the exact
 * order printed below (generated from dovi_tool export JSON by the lane
 * script gen_ref_fields.py). Stops at first mismatch. */
#include "DVRPUAnnexB.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *b = malloc((size_t)n);
    if (!b || fread(b, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(b); return 0; }
    fclose(f); *len = (size_t)n; return b;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 4) { fprintf(stderr, "usage: dv_hdrtest <in.hevc> <ref-fields.txt> [ref-profiles.txt]\n"); return 2; }
    size_t hvLen = 0;
    uint8_t *hv = slurp(argv[1], &hvLen);
    if (!hv) { printf("FAIL stage=read_input\n"); return 1; }
    FILE *ref = fopen(argv[2], "r");
    if (!ref) { printf("FAIL stage=read_ref\n"); return 1; }
    FILE *refProfiles = argc > 3 ? fopen(argv[3], "r") : 0;
    if (argc > 3 && !refProfiles) { printf("FAIL stage=read_profiles\n"); return 1; }

    GorAVDVRPURef refs[4096];
    GorAVDVRPUList list = { refs, 4096, 0, 0, 0, 0 };
    gorav_dv_scan_annexb(hv, hvLen, &list);
    if (list.count == 0) { printf("FAIL stage=scan rpucount=0\n"); return 1; }

    char line[1024];
    uint32_t checked = 0;
    for (uint32_t i = 0; i < list.count; i++) {
        if (!fgets(line, sizeof line, ref)) { printf("FAIL stage=ref_short at=%u\n", i); return 1; }
        unsigned long pfx, typ, fmt, prof, lvl, seq, crf, cdt, cld, idc,
                      full, blb, elb, e04, e57, vdrb, srf, esrf, dres, dmp, upv, pvid;
        int got = sscanf(line, "%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%lu",
            &pfx,&typ,&fmt,&prof,&lvl,&seq,&crf,&cdt,&cld,&idc,&full,
            &blb,&elb,&e04,&e57,&vdrb,&srf,&esrf,&dres,&dmp,&upv,&pvid);
        if (got != 22) { printf("FAIL stage=ref_parse at=%u got=%d\n", i, got); return 1; }
        GorAVDVRPUHeader h;
        if (gorav_dv_parse_rpu_header(hv + refs[i].payloadOffset, refs[i].payloadBytes, &h) != 0) {
            printf("FAIL stage=parse at=%u\n", i); return 1;
        }
        unsigned long mine[22] = {
            h.rpu_nal_prefix, h.rpu_type, h.rpu_format, h.vdr_rpu_profile, h.vdr_rpu_level,
            h.vdr_seq_info_present_flag, h.chroma_resampling_explicit_filter_flag,
            h.coefficient_data_type, h.coefficient_log2_denom, h.vdr_rpu_normalized_idc,
            h.bl_video_full_range_flag, h.bl_bit_depth_minus8, h.el_bit_depth_minus8,
            h.ext_mapping_idc_0_4, h.ext_mapping_idc_5_7, h.vdr_bit_depth_minus8,
            h.spatial_resampling_filter_flag, h.el_spatial_resampling_filter_flag,
            h.disable_residual_flag, h.vdr_dm_metadata_present_flag,
            h.use_prev_vdr_rpu_flag, h.prev_vdr_rpu_id
        };
        unsigned long want[22] = { pfx,typ,fmt,prof,lvl,seq,crf,cdt,cld,idc,full,
            blb,elb,e04,e57,vdrb,srf,esrf,dres,dmp,upv,pvid };
        for (int k = 0; k < 22; k++) {
            if (mine[k] != want[k]) {
                printf("FAIL stage=field rpu=%u field=%d ours=%lu ref=%lu\n", i, k, mine[k], want[k]);
                return 1;
            }
        }
        /* profile rule agreement (reference: get_dovi_profile) */
        if (refProfiles) {
            int wp = -1;
            if (fscanf(refProfiles, "%d", &wp) != 1) { printf("FAIL stage=profile_ref at=%u\n", i); return 1; }
            int gp = gorav_dv_guess_profile(&h);
            if (gp != wp) { printf("FAIL stage=profile rpu=%u ours=%d ref=%d\n", i, gp, wp); return 1; }
        }
        checked++;
    }
    if (fgets(line, sizeof line, ref)) { printf("FAIL stage=ref_longer\n"); return 1; }
    printf("HDRTEST_PASS rpucount=%u fields=22 profiles=%s\n", checked, refProfiles ? "checked" : "skipped");
    fclose(ref); free(hv);
    return 0;
}
