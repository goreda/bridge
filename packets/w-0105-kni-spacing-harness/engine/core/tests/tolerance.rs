use kni_core::tolerance::*;

fn rect(w: usize, h: usize, x0: usize, x1: usize, y0: usize, y1: usize, f: &dyn Fn(usize, usize) -> u8) -> Vec<u8> {
    let mut g = vec![255u8; w * h];
    for y in 0..h { for x in 0..w { if x >= x0 && x < x1 && y >= y0 && y < y1 { g[y * w + x] = f(x, y); } } }
    g
}

#[test]
fn binary_raster_gives_half_pixel_and_one_twelfth_variance() {
    let g = rect(40, 40, 10, 30, 10, 30, &|_, _| 0);
    let t = derive_from_gray(40, 40, &g).unwrap();
    assert!((t.rdp_eps_px - 0.5).abs() < 1e-12, "{}", t.rdp_eps_px);
    assert!((t.fit_variance_px2 - 0.25 / 3.0).abs() < 1e-12);
    assert!((t.t_line_px - 1.0).abs() < 1e-12);
    assert_eq!(t.step_fraction, 1.0);
}

#[test]
fn antialiased_edges_give_smaller_eps() {
    // ramp edge: 4 gray levels across the boundary, 3 of them non-step crossings are not both sides
    let w = 40; let h = 40;
    let mut g = vec![255u8; w * h];
    for y in 10..30 { for x in 0..w {
        g[y * w + x] = match x { 10 => 200, 11 => 120, 12 => 60, 13..=26 => 0, 27 => 60, 28 => 120, 29 => 200, _ => 255 };
    } }
    let t = derive_from_gray(w, h, &g).unwrap();
    assert!(t.rdp_eps_px < 0.5 && t.rdp_eps_px > 0.0, "{}", t.rdp_eps_px);
    assert!(t.step_fraction < 1.0);
}

#[test]
fn deterministic_and_scale_applied_only_at_the_accessor() {
    let g = rect(32, 32, 8, 24, 8, 24, &|_, _| 0);
    let a = derive_from_gray(32, 32, &g).unwrap();
    let b = derive_from_gray(32, 32, &g).unwrap();
    assert_eq!(a, b);
    assert!((a.fit_se_scaled(2.0) - 4.0 * a.fit_variance_px2).abs() < 1e-15);
    assert!((a.rdp_eps_scaled(2.0) - 2.0 * a.rdp_eps_px).abs() < 1e-15);
}

#[test]
fn blank_and_bad_size_are_errors() {
    assert!(derive_from_gray(8, 8, &vec![255u8; 64]).is_err());
    assert!(derive_from_gray(8, 8, &vec![255u8; 10]).is_err());
}

#[test]
fn legacy_arm_is_labelled_constants() {
    let l = DerivedTolerance::legacy();
    assert_eq!(l.rdp_eps_px, LEGACY_RDP_EPS_PX);
    assert_eq!(l.se_scaled, LEGACY_FIT_SE_SCALED);
}

#[test]
fn fixtures_png_derive_without_error() {
    for f in ["00C9_scan", "dot_00b7", "quote_2018", "r_scan", "s_scan", "u_scan"] {
        let p = format!("{}/tests/fixtures/{}.png", env!("CARGO_MANIFEST_DIR"), f);
        let t = derive_from_png(&std::fs::read(p).unwrap()).unwrap();
        assert!(t.rdp_eps_px > 0.0 && t.rdp_eps_px <= 0.5);
    }
}

#[test]
fn stair_term_dominates_on_rough_antialiased_edge_and_never_exceeds_binary_cap() {
    // jagged edge: alternate columns shift the boundary by one gray step pattern
    let (w, h) = (48usize, 48usize);
    let mut rough = vec![255u8; w * h];
    let mut smooth = vec![255u8; w * h];
    for y in 8..40 { for x in 8..40 {
        smooth[y * w + x] = 0;
        rough[y * w + x] = 0;
    } }
    // rough: left edge column alternates between 0 and 128 along y (sub-pixel edge ripple)
    for y in 8..40 { rough[y * w + 8] = if y % 2 == 0 { 0 } else { 128 }; }
    let ts = derive_from_gray(w, h, &smooth).unwrap();
    let tr = derive_from_gray(w, h, &rough).unwrap();
    assert!(tr.stair_rms_px > ts.stair_rms_px, "{} vs {}", tr.stair_rms_px, ts.stair_rms_px);
    assert!(tr.rdp_eps_px >= tr.stair_rms_px);
}

#[test]
fn binary_disc_eps_is_between_zero_and_half_pixel_cap_plus_stair() {
    let (w, h) = (64usize, 64usize);
    let mut g = vec![255u8; w * h];
    for y in 0..h { for x in 0..w {
        let dx = x as f64 - 31.5; let dy = y as f64 - 31.5;
        if dx * dx + dy * dy <= 400.0 { g[y * w + x] = 0; }
    } }
    let t = derive_from_gray(w, h, &g).unwrap();
    assert_eq!(t.step_fraction, 1.0);
    assert!(t.rdp_eps_px >= 0.5 - 1e-12);
    assert!(t.stair_rms_px > 0.0 && t.stair_rms_px < 0.5);
}
