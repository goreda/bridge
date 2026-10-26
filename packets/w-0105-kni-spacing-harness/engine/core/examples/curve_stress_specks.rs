//! curve_stress_specks: capture-only degenerate-ring census for one tile.
//! No fit: counts the rings capture::is_degenerate_ring exempts (the same
//! rule the fit drops), plus their total capture-space area. Used for the
//! per-style speck table.
//!
//! Usage: curve_stress_specks --style <id> --tile <png|jpg>

use kni_core::curve_stress::{PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS};

fn main() {
    let mut style = String::new();
    let mut tile: Option<std::path::PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--style" => style = args.next().unwrap(),
            "--tile" => tile = args.next().map(Into::into),
            other => { eprintln!("unknown arg {other}"); std::process::exit(2); }
        }
    }
    let tile = tile.expect("--tile");
    let glyph = tile.file_stem().unwrap().to_string_lossy().to_string();
    let bytes = std::fs::read(&tile).expect("read tile");
    let src = kni_core::capture_dispatch::capture_source(&bytes, 0.25, &PROBE_PNG_LIMITS, PROBE_JPEG_LIMITS)
        .expect("capture");
    let mut specks = 0usize;
    let mut area = 0.0f64;
    for r in &src.contour.rings {
        if kni_core::capture::is_degenerate_ring(&r.points) {
            specks += 1;
            area += kni_core::capture::ring_area2(&r.points).abs() / 2.0;
        }
    }
    println!("{style}\t{glyph}\trings\t{}\tspecks\t{specks}\tspeck_area_px2\t{area}", src.contour.rings.len());
}
