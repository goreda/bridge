use kni_geometry_prototypes::*;
// Exact fields from the pinned fitter interfaces. Not a full metrics build.
extern crate self as kni_metrics;
pub mod gen {
    #[derive(Clone, Debug)]
    pub struct GlyphKnowledge {
        pub case: char,
        pub freq_weight: i32,
        pub right_class: u32,
        pub left_class: u32,
    }
    #[derive(Clone, Debug)]
    pub struct GlyphWall {
        pub advance: f64,
        pub rows: std::collections::BTreeMap<i32, (f64, f64)>,
    }
}
pub mod training_only_fit {
    use super::gen::*;
    #[derive(Clone, Debug)]
    pub struct GeometryAssignment {
        pub glyph: String,
        pub knowledge: GlyphKnowledge,
        pub wall: GlyphWall,
        pub outline_pin: String,
        pub prototype_pin: String,
        pub query_only: bool,
    }
}
#[path = "../src/fitter_adapter.rs"]
mod adapter;
#[test]
fn exact_field_mapping_names_only_after_assignment() {
    let g = |w: f64| Geometry {
        advance: w + 2.,
        rings: vec![Ring {
            start: Point { x: 0., y: 0. },
            spans: vec![
                Span::Line(Point { x: w, y: 0. }),
                Span::Line(Point { x: w, y: 10. }),
                Span::Line(Point { x: 0., y: 10. }),
                Span::Line(Point { x: 0., y: 0. }),
            ],
        }],
    };
    let xs = vec![g(2.), g(2.1), g(8.), g(8.1)];
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
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    let q = a.query(&xs[0]);
    assert!(q.unavailable_reason.is_none());
    let x = adapter::map_assignment("routing-only", &xs[0], &q).unwrap();
    assert_eq!(x.knowledge.case, 'x');
    assert_eq!(x.knowledge.freq_weight, 0);
    assert_eq!(x.prototype_pin, a.pin());
    assert!(x.query_only);
    assert_eq!(x.wall.rows[&0], (0., 2.));
    let y = adapter::map_assignment("different-routing", &xs[0], &q).unwrap();
    assert_eq!(x.knowledge.left_class, y.knowledge.left_class);
    assert!(adapter::map_assignment("routing", &xs[1], &q).is_err());
}
