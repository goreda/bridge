// PN-3 diagnostic: per-glyph typed fallback ledger breakdown for Paul New tiles.
use kni_core::capture::DecodeLimits;
use kni_core::capture_dispatch::capture_source;
use kni_core::capture_fit::{fit_captured_with_typed_ledgers, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::jpeg_source::Limits;

fn main() {
    let scale: f64 = std::env::var("DIAG_SCALE").ok().and_then(|v| v.parse().ok()).unwrap_or(1000.0f64 / 1122.0);
    let eps: f64 = std::env::var("DIAG_EPS").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25);
    let se: f64 = std::env::var("DIAG_SE").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25);
    let policy = FitPolicy { squared_error: se, max_refits: 8 };
    let png_limits = DecodeLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let jpeg_limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    for path in std::env::args().skip(1) {
        let bytes = std::fs::read(&path).unwrap();
        let src = capture_source(&bytes, eps, &png_limits, jpeg_limits).unwrap();
        let name = std::path::Path::new(&path).file_name().unwrap().to_string_lossy().to_string();
        for (domain, contour) in [("meas", &src.contour)].into_iter().chain(src.outline_contour.as_ref().map(|o| ("outline", o))) {
            println!("{name}\t{domain}\tcapture_rings={}", contour.rings.len());
            let speck_marker = kni_core::capture_fit::speck_marker();
            let speck_span_base = kni_core::capture_fit::speck_spans();
            let (_rings, _n, _fb, _dropped, fevents, astubs, declined) =
                fit_captured_with_typed_ledgers(&contour.rings, scale, &policy);
            let specks = kni_core::capture_fit::speck_areas_since(speck_marker);
            let speck_spans = kni_core::capture_fit::speck_spans() - speck_span_base;
            {   let (mut mn, mut mx, mut sm) = (f64::INFINITY, 0.0f64, 0.0f64);
                for a in &specks { mn = mn.min(*a); mx = mx.max(*a); sm += a; }
                let mean = if specks.is_empty() { 0.0 } else { sm / specks.len() as f64 };
                let mnv = if specks.is_empty() { 0.0 } else { mn };
                println!("{name}\t{domain}\tdropped={_dropped}\tfit_spans={_n}\tspecks={}\tspeck_spans={speck_spans}\tspeck_area_min={mnv:.6}\tspeck_area_max={mx:.6}\tspeck_area_mean={mean:.6}", specks.len());
            }
            let mut su = 0; let mut dl = 0; let mut dt = 0; let mut sg = 0; let mut ac = 0;
            for e in &fevents {
                match e.reason {
                    FallbackReason::SplitUnresolved => su += 1,
                    FallbackReason::DepthLimit => dl += 1,
                    FallbackReason::DegenerateTangents => dt += 1,
                    FallbackReason::SubGridSpan => sg += 1,
                    FallbackReason::AreaCollapseRestored => ac += 1,
                }
            }
            for d in &declined {
                println!("  DECLINED arc {} s{} e{} {:?} lineage {:?} stub_dev {:.3} db {:.3}", d.arc, d.s, d.e, d.class, d.lineage_class, d.stub_dev, d.dense_bound);
            }
            for a in &astubs {
                println!("  ASTUB arc {} s{} e{} {:?}", a.arc, a.s, a.e, a.class);
            }
            let arc_max = fevents.iter().map(|e| e.arc).max();
            println!("{name}\t{domain}\tSU={su}\tDL={dl}\tDT={dt}\tSG={sg}\tAC={ac}\tstubs={}\tdeclined={}\tevents={}\tarc_max={arc_max:?}",
                astubs.len(), declined.len(), fevents.len());
            // per-arc histogram of event counts
            let mut per_arc: std::collections::BTreeMap<usize, usize> = Default::default();
            for e in &fevents { *per_arc.entry(e.arc).or_default() += 1; }
            println!("  per_arc: {:?}", per_arc);
        }
    }
}
