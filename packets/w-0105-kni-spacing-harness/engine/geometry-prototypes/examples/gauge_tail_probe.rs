use kni_geometry_prototypes::*;
fn rect(w: f64, h: f64) -> Geometry {
    let p = |x, y| Point { x, y };
    Geometry {
        advance: w + 2.,
        rings: vec![Ring {
            start: p(0., 0.),
            spans: vec![
                Span::Line(p(w, 0.)),
                Span::Line(p(w, h)),
                Span::Line(p(0., h)),
                Span::Line(p(0., 0.)),
            ],
        }],
    }
}
fn main() {
    let r = Rule {
        minimum_training: 4,
        gauge_statistic: GaugeStatistic::Median,
        maximum_unique_training: 64,
        coverage_numerator: 1,
        coverage_denominator: 2,
        flatten_fraction: 1. / 1024.,
        bootstrap_replicates: 4,
        stability_fraction: 0.5,
    };
    for tail in [30., 100., 1000., 10000.] {
        let xs = vec![
            rect(2., 10.),
            rect(2.1, 10.),
            rect(2.2, 10.),
            rect(8., 10.),
            rect(8.1, 10.),
            rect(8.2, 10.),
            rect(3., tail),
        ];
        let a = fit(&xs, r.clone(), &r.pin()).unwrap();
        let mut mean = r.clone();
        mean.gauge_statistic = GaugeStatistic::ArithmeticMean;
        let b = fit(&xs, mean.clone(), &mean.pin()).unwrap();
        println!(
            "tail={tail} median={:?} mean={:?}",
            a.unavailable_reason(),
            b.unavailable_reason()
        );
        for w in [
            2., 2.01, 2.05, 2.1, 2.15, 2.2, 8., 8.01, 8.05, 8.1, 8.15, 8.2, 3.,
        ] {
            let g = rect(w, 10.);
            let x = a.query(&g);
            let y = b.query(&g);
            if (x.left_class, x.right_class, &x.unavailable_reason)
                != (y.left_class, y.right_class, &y.unavailable_reason)
            {
                println!(
                    "diff w={w} median={:?}/{:?}/{:?} mean={:?}/{:?}/{:?}",
                    x.left_class,
                    x.right_class,
                    x.unavailable_reason,
                    y.left_class,
                    y.right_class,
                    y.unavailable_reason
                );
            }
        }
    }
}
