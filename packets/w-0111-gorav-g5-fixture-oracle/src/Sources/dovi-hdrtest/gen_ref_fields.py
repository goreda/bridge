#!/usr/bin/env python3
"""gen_ref_fields.py - render dovi_tool export JSON into the 22-field
reference lines consumed by dv_hdrtest. Field order is fixed; see C source."""
import json, sys
rpus = json.load(open(sys.argv[1]))
out = []
for r in rpus:
    h = r["header"]
    out.append(",".join(str(int(x)) for x in [
        h["rpu_nal_prefix"], h["rpu_type"], h["rpu_format"],
        h["vdr_rpu_profile"], h["vdr_rpu_level"],
        h["vdr_seq_info_present_flag"],
        h["chroma_resampling_explicit_filter_flag"],
        h["coefficient_data_type"], h["coefficient_log2_denom"],
        h["vdr_rpu_normalized_idc"], h["bl_video_full_range_flag"],
        h["bl_bit_depth_minus8"], h["el_bit_depth_minus8"],
        h["ext_mapping_idc_0_4"], h["ext_mapping_idc_5_7"],
        h["vdr_bit_depth_minus8"], h["spatial_resampling_filter_flag"],
        h["el_spatial_resampling_filter_flag"], h["disable_residual_flag"],
        h["vdr_dm_metadata_present_flag"], h["use_prev_vdr_rpu_flag"],
        h["prev_vdr_rpu_id"]]))
print("\n".join(out))
