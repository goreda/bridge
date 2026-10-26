//! Determinism probe: profile one synthetic glyph with many white
//! components N times in-process and print the to_bits of every
//! accumulated float. Any bit drift across iterations = iteration-order
//! dependent f64 accumulation.
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy};

fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
    vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
}
fn rect_rev(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
    vec![[x0, y0], [x0, y1], [x1, y1], [x1, y0]]
}

fn main() {
    // Outer frame + 24 enclosed holes of varied, non-round sizes (many
    // enclosed white components), plus two aperture shapes (open white to
    // the right / left bounds edges).
    let mut rings = Vec::new();
    // Mirrored "C" with its aperture on the global left edge.
    rings.push(vec![
        [100.0, 0.0], [0.0, 0.0], [0.0, 40.0], [55.0, 40.0], [55.0, 160.0], [0.0, 160.0], [0.0, 200.0], [100.0, 200.0],
    ]);
    // Solid frame + 24 true holes (opposite winding) of varied sizes:
    // 24 enclosed white components.
    rings.push(rect(150.0, 0.0, 650.0, 300.0));
    for i in 0..24 {
        let x = 170.0 + (i % 8) as f64 * 57.0;
        let y = 20.0 + (i / 8) as f64 * 90.0;
        let w = 13.0 + (i as f64) * 0.7 + (i % 3) as f64 * 0.13;
        let h = 17.0 + (i as f64) * 1.1 + (i % 5) as f64 * 0.07;
        rings.push(rect_rev(x, y, x + w, y + h));
    }
    // "C" with its aperture on the global right edge.
    rings.push(vec![
        [700.0, 0.0], [800.0, 0.0], [800.0, 40.0], [745.0, 40.0], [745.0, 160.0], [800.0, 160.0], [800.0, 200.0], [700.0, 200.0],
    ]);
    let input = OutlineInput {
        glyph_id: "determinism-probe".into(),
        source_pin: "probe".into(),
        upm: 1000,
        origin: [0.0, 0.0],
        flatten_tolerance: 0.0,
        rings,
    };
    let policy = ScanPolicy { row_step: 3.7, max_rows: 4096, merge_guard: kni_metrics::outline_spacing::MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
    let mut first: Option<(u64, u64, u64, u64)> = None;
    let mut stable = true;
    for it in 0..64 {
        let p = profile_outline(&input, policy).expect("profile");
        let sig = (p.ink_area.to_bits(), p.counter_area.to_bits(), p.open_left.to_bits(), p.open_right.to_bits());
        match first {
            None => { first = Some(sig); println!("iter {it}: ink={:016x} counter={:016x} open_l={:016x} open_r={:016x}  ({}, {}, {}, {})", sig.0, sig.1, sig.2, sig.3, p.ink_area, p.counter_area, p.open_left, p.open_right); }
            Some(f) => {
                if f != sig {
                    stable = false;
                    println!("iter {it}: DRIFT ink={:016x} counter={:016x} open_l={:016x} open_r={:016x}  ({}, {}, {}, {})", sig.0, sig.1, sig.2, sig.3, p.ink_area, p.counter_area, p.open_left, p.open_right);
                }
            }
        }
    }
    println!("RESULT: {}", if stable { "STABLE" } else { "DRIFT" });
}
