//! tests/pair_visual_read.rs — K1: pair visual reading layer, negative controls included.
//! Synthetic gray rasters only; no font data. Measurement rows carry provenance;
//! every ambiguity is a typed refusal, never a guess.
use kni_metrics::pair_visual_read::*;

fn img(w: usize, h: usize, ink: &[(usize, usize, usize, usize)]) -> GrayImage {
    // ink rectangles: (x0, x1, y0, y1) painted black on white
    let mut gray = vec![255u8; w * h];
    for &(x0, x1, y0, y1) in ink {
        for y in y0..y1 { for x in x0..x1 { gray[y * w + x] = 0; } }
    }
    GrayImage { width: w, height: h, gray }
}

#[test]
fn clean_gap_measured() {
    let g = img(40, 30, &[(2, 14, 5, 25), (26, 38, 5, 25)]); // 12 zero-ink columns
    let m = read_pair_image("A", "V", &g, "sha", None).unwrap();
    assert_eq!(m.min_gap_px, 12.0); // clearance = rx - lx - 1
    assert_eq!(m.gap_band, (14, 26));
    assert_eq!(m.shared_rows, 20);
    assert_eq!(m.source_sha256, "sha");
    assert_eq!(m.uncertainty_px, GAP_UNCERTAINTY_PX);
    assert_eq!(m.left_bbox, (2, 5, 14, 25));
    assert_eq!(m.right_bbox, (26, 5, 38, 25));
}

#[test]
fn content_derived_band_narrow_glyph() {
    // narrow right glyph far off-center: a fixed middle-third band would miss it
    let g = img(300, 30, &[(2, 250, 5, 25), (270, 290, 5, 25)]);
    let m = read_pair_image("W", "i", &g, "sha", None).unwrap();
    assert_eq!(m.min_gap_px, 20.0);
    assert_eq!(m.gap_band, (250, 270));
}

#[test]
fn counter_narrower_than_gap_loses() {
    // 'A'-like left member: two bars with an 8px counter; real gap is 16px
    let g = img(60, 30, &[(2, 12, 5, 25), (20, 30, 5, 25), (46, 58, 5, 25)]);
    let m = read_pair_image("A", "o", &g, "sha", None).unwrap();
    assert_eq!(m.min_gap_px, 16.0);
    assert_eq!(m.gap_band, (30, 46));
}

#[test]
fn widest_runs_tie_is_refused() {
    // two 10px zero-ink runs: counter vs gap undecidable => typed refusal
    let g = img(60, 30, &[(2, 10, 5, 25), (20, 28, 5, 25), (38, 46, 5, 25)]);
    assert_eq!(read_pair_image("x", "y", &g, "sha", None).unwrap_err(), PairVisualError::AmbiguousGap);
}

#[test]
fn touching_glyphs_refused() {
    let g = img(30, 30, &[(2, 28, 5, 25)]);
    assert_eq!(read_pair_image("A", "V", &g, "sha", None).unwrap_err(), PairVisualError::AmbiguousGap);
}

#[test]
fn overlapping_pair_refused_by_design() {
    // kern-negative pair: strokes overlap, no zero-ink band => refused, counted
    let g = img(30, 30, &[(2, 20, 5, 25), (12, 28, 8, 22)]);
    assert_eq!(read_pair_image("A", "V", &g, "sha", None).unwrap_err(), PairVisualError::AmbiguousGap);
}

#[test]
fn single_blob_refused() {
    let g = img(30, 30, &[(10, 20, 5, 25)]);
    assert_eq!(read_pair_image("i", "j", &g, "sha", None).unwrap_err(), PairVisualError::AmbiguousGap);
}

#[test]
fn empty_and_full_ink_refused() {
    assert_eq!(read_pair_image("A", "B", &img(30, 30, &[]), "s", None).unwrap_err(), PairVisualError::NoInk("uniform image"));
    assert_eq!(read_pair_image("A", "B", &img(30, 30, &[(0, 30, 0, 30)]), "s", None).unwrap_err(), PairVisualError::NoInk("uniform image"));
}

#[test]
fn single_column_noise_band_refused() {
    // 1px white column between glyphs: below MIN_GAP_BAND_PX => not a gap
    let g = img(30, 30, &[(2, 14, 5, 25), (15, 28, 5, 25)]);
    assert_eq!(read_pair_image("A", "B", &g, "sha", None).unwrap_err(), PairVisualError::AmbiguousGap);
}

#[test]
fn inverted_polarity_refused() {
    let mut g = img(30, 30, &[(2, 14, 5, 25), (20, 28, 5, 25)]);
    for p in g.gray.iter_mut() { *p = 255 - *p; } // white ink on black
    assert_eq!(read_pair_image("A", "B", &g, "sha", None).unwrap_err(), PairVisualError::InvertedPolarity);
}

#[test]
fn bad_scale_refused() {
    let g = img(40, 30, &[(2, 14, 5, 25), (26, 38, 5, 25)]);
    assert_eq!(read_pair_image("A", "B", &g, "s", Some(f64::NAN)).unwrap_err(), PairVisualError::BadScale);
    assert_eq!(read_pair_image("A", "B", &g, "s", Some(0.0)).unwrap_err(), PairVisualError::BadScale);
}

#[test]
fn gap_fu_is_min_times_scale() {
    let g = img(40, 30, &[(2, 14, 5, 25), (26, 38, 5, 25)]);
    let m = read_pair_image("A", "V", &g, "sha", Some(2.0)).unwrap();
    assert_eq!(m.gap_fu, Some(24.0)); // documented: MINIMUM clearance x scale, never mean
}

#[test]
fn bad_raster_refused() {
    let g = GrayImage { width: 10, height: 10, gray: vec![0u8; 99] };
    assert_eq!(read_pair_image("A", "B", &g, "s", None).unwrap_err(), PairVisualError::BadRaster);
}

#[test]
fn tsv_injection_guard() {
    let g = img(40, 30, &[(2, 14, 5, 25), (26, 38, 5, 25)]);
    assert_eq!(read_pair_image("A\tB", "C", &g, "s", None).unwrap_err(), PairVisualError::BadName);
    assert_eq!(read_pair_image("A\n", "C", &g, "s", None).unwrap_err(), PairVisualError::BadName);
    assert_eq!(read_pair_image("", "C", &g, "s", None).unwrap_err(), PairVisualError::BadName);
}

#[test]
fn manifest_per_row_typing() {
    let m = parse_manifest("A\tV\ta.png\n\nBROKENROW\nC\tD\tc.png\r\nE\tF\te.png\textra\n");
    assert_eq!(m.len(), 5);
    assert!(matches!(m[0], ManifestEntry::Valid { .. }));
    assert!(matches!(m[1], ManifestEntry::Invalid { .. })); // blank line typed, never skipped
    assert!(matches!(m[2], ManifestEntry::Invalid { .. })); // one column
    assert!(matches!(m[3], ManifestEntry::Invalid { .. })); // CR byte detected via split('\n')
    assert!(matches!(m[4], ManifestEntry::Invalid { .. })); // four columns
}

#[test]
fn failed_load_rows_carry_path_and_error_is_flattened() {
    let entries = parse_manifest("A\tV\tmissing.png\n");
    let (rows, failures) = read_manifest_pairs(&entries, None, |_p| Err("io\tbad\nline".to_string()));
    assert_eq!(failures, 1);
    match &rows[0] {
        PairReportRow::Failed { image_path, source_sha256, .. } => {
            assert_eq!(image_path, "missing.png");
            assert!(source_sha256.is_none());
        }
        _ => panic!("expected Failed"),
    }
    let tsv = report_tsv(&rows);
    assert_eq!(tsv.lines().count(), 2); // header + 1 row: tab/newline in error flattened
    assert!(tsv.contains("missing.png"));
    let (measured, refused) = report_summary(&rows);
    assert_eq!((measured, refused), (0, 1));
}

#[test]
fn refused_measurement_keeps_sha() {
    let entries = parse_manifest("A\tV\tx.png\n");
    let (rows, failures) = read_manifest_pairs(&entries, None, |_p| Ok((img(30, 30, &[(2, 28, 5, 25)]), "sha-x".to_string())));
    assert_eq!(failures, 1); // touching glyphs refuse AFTER load: provenance preserved
    match &rows[0] {
        PairReportRow::Failed { source_sha256, .. } => assert_eq!(source_sha256.as_deref(), Some("sha-x")),
        _ => panic!("expected Failed"),
    }
    let (measured, refused) = report_summary(&rows);
    assert_eq!((measured, refused), (0, 1));
}

#[test]
fn measured_row_in_summary() {
    let entries = parse_manifest("A\tV\tok.png\nA\tW\tbad.png\n");
    let (rows, failures) = read_manifest_pairs(&entries, None, |p| {
        if p == "ok.png" { Ok((img(40, 30, &[(2, 14, 5, 25), (26, 38, 5, 25)]), "sha-ok".to_string())) }
        else { Ok((img(30, 30, &[(2, 28, 5, 25)]), "sha-bad".to_string())) }
    });
    assert_eq!(failures, 1);
    assert_eq!(report_summary(&rows), (1, 1));
    let tsv = report_tsv(&rows);
    assert!(tsv.contains("measured"));
    assert!(tsv.contains("sha-ok"));
    assert!(tsv.lines().next().unwrap().ends_with("image_path"));
}
