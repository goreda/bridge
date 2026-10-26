use kni_geometry_prototypes::*;
fn main() {
    let n = 512;
    let xs: Vec<_> = (0..n)
        .map(|i| {
            let w = 2. + i as f64 / 100.;
            let mut spans = Vec::new();
            spans.push(Span::Line(Point { x: w, y: 0. }));
            for j in 1..150 {
                spans.push(Span::Line(Point { x: w, y: j as f64 }));
            }
            spans.push(Span::Line(Point { x: 0., y: 149. }));
            for j in (0..149).rev() {
                spans.push(Span::Line(Point { x: 0., y: j as f64 }));
            }
            Geometry {
                advance: w + 2.,
                rings: vec![Ring {
                    start: Point { x: 0., y: 0. },
                    spans,
                }],
            }
        })
        .collect();
    let r = Rule {
        minimum_training: 4,
        gauge_statistic: GaugeStatistic::Median,
        maximum_unique_training: 512,
        coverage_numerator: 1,
        coverage_denominator: 2,
        flatten_fraction: 1. / 1024.,
        bootstrap_replicates: 4,
        stability_fraction: 0.5,
    };
    let start = std::time::Instant::now();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    let receipt = a.canonical_receipt().unwrap();
    println!("synthetic_unique=512 wall_levels=299 channels=603 bootstrap=4 elapsed_ms={} receipt_bytes={} receipt_lines={} rule_pin={} artifact_pin={}",start.elapsed().as_millis(),receipt.len(),receipt.lines().count(),r.pin(),a.pin());
    println!(
        "This is collinear subdivided rectangle geometry, not real-font topology or accuracy."
    );
}
