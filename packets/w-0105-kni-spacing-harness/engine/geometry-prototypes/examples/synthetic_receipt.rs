use kni_geometry_prototypes::*;
fn rect(w: f64) -> Geometry {
    let p = |x, y| Point { x, y };
    Geometry {
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
    }
}
fn main() {
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
    let xs: Vec<_> = [2., 2.1, 2.2, 8., 8.1, 8.2].into_iter().map(rect).collect();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    print!("{}", a.canonical_receipt().unwrap());
    println!("artifact_sha256={}", a.pin());
    let qs: Vec<_> = [
        2., 2.01, 2.05, 2.1, 2.15, 2.2, 8., 8.01, 8.05, 8.1, 8.15, 8.2,
    ]
    .into_iter()
    .map(rect)
    .collect();
    print!("{}", a.query_receipt(&qs));
}
