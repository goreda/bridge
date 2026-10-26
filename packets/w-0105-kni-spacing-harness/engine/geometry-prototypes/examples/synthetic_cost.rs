use kni_geometry_prototypes::*;
fn main() {
    for n in [32, 64, 128] {
        let mut xs = Vec::new();
        for i in 0..n {
            let w = 2. + (i as f64) / 10.;
            let p = |x, y| Point { x, y };
            xs.push(Geometry {
                advance: w + 2.,
                rings: vec![Ring {
                    start: p(0., 0.),
                    spans: vec![
                        Span::Line(p(w, 0.)),
                        Span::Line(p(w, 10.)),
                        Span::Line(p(0., 10.)),
                        Span::Line(p(0., 0.)),
                    ],
                }],
            });
        }
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
        println!("synthetic_unique={n} wall_levels=3 channels=11 bootstrap=4 elapsed_ms={} receipt_bytes={}",start.elapsed().as_millis(),a.canonical_receipt().unwrap().len());
    }
}
