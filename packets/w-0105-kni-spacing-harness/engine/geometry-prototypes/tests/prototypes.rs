use kni_geometry_prototypes::*;
fn p(x: f64, y: f64) -> Point {
    Point { x, y }
}
fn rect(w: f64, h: f64) -> Geometry {
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
fn rule() -> Rule {
    Rule {
        minimum_training: 4,
        gauge_statistic: GaugeStatistic::Median,
        maximum_unique_training: 512,
        coverage_numerator: 1,
        coverage_denominator: 2,
        flatten_fraction: 1. / 1024.,
        bootstrap_replicates: 4,
        stability_fraction: 0.5,
    }
}
fn train() -> Vec<Geometry> {
    vec![
        rect(2., 10.),
        rect(2.1, 10.),
        rect(2.2, 10.),
        rect(8., 10.),
        rect(8.1, 10.),
        rect(8.2, 10.),
    ]
}
fn fit_train() -> Artifact {
    let r = rule();
    fit(&train(), r.clone(), &r.pin()).unwrap()
}
#[test]
fn frozen_training_receipts_and_queries() {
    let a = fit_train();
    assert!(a.available(), "{:?}", a.unavailable_reason());
    assert_eq!(a.training_assignments().len(), 6);
    assert!(a
        .training_assignments()
        .iter()
        .all(|r| !r.query_only && r.prototype_pin == a.pin() && r.status == "proposed"));
    let before = a.canonical_receipt().unwrap();
    let q = a.query(&rect(2.05, 10.));
    assert!(q.query_only);
    assert_eq!(q.unavailable_reason, None);
    assert!(knowledge(&q).is_some());
    assert_eq!(before, a.canonical_receipt().unwrap());
}
#[test]
fn byte_identical_permutations() {
    let r = rule();
    let xs = train();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    let mut ys = xs.clone();
    ys.reverse();
    let b = fit(&ys, r.clone(), &r.pin()).unwrap();
    assert_eq!(a.pin(), b.pin());
    assert_eq!(
        a.canonical_receipt().unwrap(),
        b.canonical_receipt().unwrap()
    );
    assert_eq!(a.query_receipt(&xs), a.query_receipt(&ys));
}
#[test]
fn rule_pin_and_small_training() {
    let r = rule();
    assert!(fit(&train(), r.clone(), "wrong").is_err());
    let a = fit(&train()[..3], r.clone(), &r.pin()).unwrap();
    assert!(!a.available());
    assert_eq!(
        a.unavailable_reason(),
        Some("insufficient_training_geometry")
    );
}
#[test]
fn out_of_support_queries_abstain() {
    let a = fit_train();
    let q = a.query(&rect(20., 10.));
    assert!(q.unavailable_reason.is_some());
    assert_eq!(knowledge(&q), None);
    let q = a.query(&rect(2., 11.));
    assert!(q.unavailable_reason.is_some());
}
#[test]
fn curve_type_and_nonfinite_are_explicit() {
    let r = rule();
    let mut xs = train();
    let mut g = rect(2., 10.);
    g.rings[0].spans[0] = Span::Cubic(p(0., 0.), p(1., 0.), p(2., 0.));
    xs.push(g);
    let mut g = rect(4., 10.);
    g.advance = f64::NAN;
    xs.push(g);
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    assert_eq!(a.training_assignments().len(), 8);
    assert!(a
        .training_assignments()
        .iter()
        .any(|a| a.unavailable_reason.as_deref() == Some("unsupported_curve_type")));
    assert!(a
        .canonical_receipt()
        .unwrap()
        .contains("excluded_fraction="));
}
#[test]
fn tt_implied_midpoints() {
    let pts = vec![
        TTPoint {
            point: p(0., 0.),
            on_curve: false,
        },
        TTPoint {
            point: p(4., 0.),
            on_curve: false,
        },
        TTPoint {
            point: p(4., 4.),
            on_curve: false,
        },
        TTPoint {
            point: p(0., 4.),
            on_curve: false,
        },
    ];
    let r = truetype_contour(&pts).unwrap();
    assert_eq!(r.start, p(0., 2.));
    assert!(r.spans.iter().all(|s| matches!(s, Span::Quadratic(..))));
    assert_eq!(r.spans.len(), 4);
}
#[test]
fn tt_quadratics_fit_not_empty_training() {
    let mut xs = Vec::new();
    for w in [2., 2.1, 8., 8.1] {
        let pts = [
            TTPoint {
                point: p(0., 0.),
                on_curve: true,
            },
            TTPoint {
                point: p(w / 2., -1.),
                on_curve: false,
            },
            TTPoint {
                point: p(w, 0.),
                on_curve: true,
            },
            TTPoint {
                point: p(w, 10.),
                on_curve: true,
            },
            TTPoint {
                point: p(w / 2., 11.),
                on_curve: false,
            },
            TTPoint {
                point: p(0., 10.),
                on_curve: true,
            },
        ];
        xs.push(Geometry {
            advance: w + 2.,
            rings: vec![truetype_contour(&pts).unwrap()],
        });
    }
    let r = rule();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    assert_eq!(a.training_assignments().len(), 4);
    assert!(!a
        .training_assignments()
        .iter()
        .any(|a| a.unavailable_reason.as_deref() == Some("unsupported_curve_type")));
    assert!(a
        .canonical_receipt()
        .unwrap()
        .contains("half_flatten_tolerance"));
}
#[test]
fn distribution_acceptance_matches_member_radius() {
    let a = fit_train();
    let mut accepted = 0;
    let mut total = 0;
    for w in [
        2., 2.02, 2.05, 2.1, 2.15, 2.2, 8., 8.02, 8.05, 8.1, 8.15, 8.2,
    ] {
        let q = a.query(&rect(w, 10.));
        accepted += usize::from(q.unavailable_reason.is_none());
        total += 1;
    }
    assert_eq!(total, 12);
    assert_eq!(accepted, 10); /* Exact zero-dispersion equality abstains on two binary64 area-ratio differences. */
}
#[test]
fn full_curve_ablation_stability_and_contribution_receipts() {
    let a = fit_train();
    let s = a.canonical_receipt().unwrap();
    assert_eq!(
        s.lines().filter(|s| s.starts_with("candidate k=")).count(),
        12
    );
    for key in [
        "LOO ",
        "bootstrap side=",
        "unstable=",
        "left_right_coassignment_agreement=",
        "ablation side=",
        "contribution_group side=",
        "radius=",
    ] {
        assert!(s.contains(key), "{key}");
    }
}
#[test]
fn rule_changes_pin() {
    let mut r = rule();
    let old = r.pin();
    r.coverage_numerator = 2;
    assert_ne!(old, r.pin());
}
#[test]
fn unclassified_singleton_query_and_candidate_curve() {
    let mut xs = train();
    xs.push(rect(100., 10.));
    let r = rule();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    assert!(a.available());
    let excluded: Vec<_> = a
        .training_assignments()
        .iter()
        .filter(|a| a.unavailable_reason.as_deref() == Some("unclassifiable_singleton"))
        .collect();
    assert!(!excluded.is_empty());
    for e in excluded {
        let g = xs
            .iter()
            .find(|g| geometry_pin(g) == e.outline_pin)
            .unwrap();
        assert_eq!(
            a.query(g).unavailable_reason.as_deref(),
            Some("unclassifiable_singleton")
        );
    }
    assert!(a
        .canonical_receipt()
        .unwrap()
        .contains("excluded_index_runs="));
}
#[test]
fn no_eligible_partition_no_forced_class() {
    let xs = vec![rect(1., 10.), rect(2., 10.), rect(3., 10.), rect(100., 10.)];
    let mut r = rule();
    r.coverage_numerator = 1;
    r.coverage_denominator = 1;
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    if !a.available() {
        assert!(a.query(&xs[0]).unavailable_reason.is_some());
        assert!(a
            .canonical_receipt()
            .unwrap()
            .contains("candidate k=1 silhouette= eligible=false"));
    }
}
#[test]
fn unsupported_fraction_counts_in_candidate_coverage() {
    let mut xs = train();
    for w in [3., 4., 5., 6., 7., 9., 10.] {
        let mut g = rect(w, 10.);
        g.rings[0].spans[0] = Span::Cubic(p(0., 0.), p(w / 2., 0.), p(w, 0.));
        xs.push(g)
    }
    let r = rule();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    assert!(!a.available());
    assert!(a.canonical_receipt().unwrap().contains("candidate k="));
}
#[test]
fn fitter_wall_keeps_source_frame_and_advance() {
    let mut g = rect(2., 10.);
    for r in &mut g.rings {
        r.start.x += 3.;
        r.start.y -= 5.;
        for span in &mut r.spans {
            if let Span::Line(p) = span {
                p.x += 3.;
                p.y -= 5.;
            }
        }
    }
    let w = fitter_wall(&g).unwrap();
    assert_eq!(w.advance, 4.);
    assert_eq!(w.rows[&0], (3., 5.));
    assert!(w.rows.contains_key(&-5));
}
#[test]
fn malformed_open_curve_and_tt_empty() {
    let mut g = rect(2., 10.);
    g.rings[0].spans.pop();
    let r = rule();
    let a = fit(&[g], r.clone(), &r.pin()).unwrap();
    assert!(!a.available());
    assert!(a.training_assignments()[0].unavailable_reason.is_some());
    assert!(truetype_contour(&[]).is_err());
}
#[test]
fn sha_matches_known_empty_digest() {
    assert_eq!(
        hash(b""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
}
#[test]
fn secondary_topology_failure_preserves_primary() {
    let mut xs = train();
    for g in &mut xs {
        let ring = g.rings[0].clone();
        g.rings.push(ring);
    }
    let r = rule();
    let a = fit(&xs, r.clone(), &r.pin()).unwrap();
    assert!(a.available());
    let receipt = a.canonical_receipt().unwrap();
    assert!(receipt.contains("proposed_inter_ring_contact_unavailable"));
    assert!(
        receipt.contains("group=add_proposed_structure unavailable=proposed_structure_unavailable")
    );
    assert!(a
        .training_assignments()
        .iter()
        .any(|a| a.unavailable_reason.is_none()));
    assert!(xs.iter().any(|g| a.query(g).unavailable_reason.is_none()));
    assert!(receipt.contains("delta=unavailable"));
}
#[test]
fn small_training_retains_full_k_curve() {
    let r = rule();
    let a = fit(&train()[..3], r.clone(), &r.pin()).unwrap();
    assert_eq!(
        a.unavailable_reason(),
        Some("insufficient_training_geometry")
    );
    let t = a.canonical_receipt().unwrap();
    for k in 1..=3 {
        assert!(t.contains(&format!("candidate k={k} ")));
    }
    assert!(t.contains("singletons=3"));
    assert!(t.contains("retained_clusters=0"));
}
#[test]
fn wall_resource_limit_is_explicit() {
    let g = rect(2., 1000001.);
    assert_eq!(fitter_wall(&g).unwrap_err(), "wall_row_resource_limit");
}

#[test]
fn aliases_fit_once_preserve_every_input_receipt() {
    let r = rule();
    let xs = train();
    let mut aliases = xs.clone();
    aliases.push(xs[0].clone());
    let a = fit(&aliases, r.clone(), &r.pin()).unwrap();
    assert_eq!(a.training_assignments().len(), 7);
    let t = a.canonical_receipt().unwrap();
    assert!(t.contains("unique_geometry_count=6 alias_count=1"));
    assert!(t.contains("input_occurrences=2 fit_once=true"));
    let mut rev = aliases;
    rev.reverse();
    let b = fit(&rev, r.clone(), &r.pin()).unwrap();
    assert_eq!(a.pin(), b.pin());
    let original = fit(&xs, r.clone(), &r.pin()).unwrap();
    for g in &xs {
        let x = a.query(g);
        let y = original.query(g);
        assert_eq!(x.left_class, y.left_class);
        assert_eq!(x.right_class, y.right_class);
        assert_eq!(x.unavailable_reason, y.unavailable_reason);
    }
}
#[test]
fn unique_count_limit_before_any_fit() {
    let r = rule();
    let xs = (0..513)
        .map(|i| rect(2. + i as f64, 10.))
        .collect::<Vec<_>>();
    assert_eq!(
        fit(&xs, r.clone(), &r.pin()).unwrap_err(),
        "unique_training_resource_limit"
    );
}
#[test]
fn raw_signed_zero_identity_is_explicit() {
    let a = rect(2., 10.);
    let mut b = a.clone();
    b.rings[0].start.x = -0.;
    assert_ne!(geometry_pin(&a), geometry_pin(&b));
    assert!(rule().canonical().contains("raw_signed_zero_preserved"));
}

#[test]
fn unique_limit_parameter_is_pinned_and_enforced() {
    let mut r = rule();
    let old = r.pin();
    r.maximum_unique_training = 4;
    assert_ne!(old, r.pin());
    assert_eq!(
        fit(&train(), r.clone(), &r.pin()).unwrap_err(),
        "unique_training_resource_limit"
    );
    r.maximum_unique_training = 3;
    assert_eq!(
        fit(&train(), r.clone(), &r.pin()).unwrap_err(),
        "invalid_preregistered_rule"
    );
}
#[test]
fn dictionary_and_effective_group_receipts() {
    let a = fit_train();
    let s = a.canonical_receipt().unwrap();
    assert_eq!(
        s.lines()
            .filter(|l| l.starts_with("pin_dictionary "))
            .count(),
        6
    );
    assert!(s.contains("effective_group_weight side=left group=vertical weight=0000000000000000 nonzero_range_channels=0"));
    assert!(s.contains("excluded_index_runs="));
    assert!(!s.contains(" excluded="));
}
#[test]
fn mean_tail_contrast_and_permutation_are_explicit() {
    let mut r = rule();
    r.gauge_statistic = GaugeStatistic::Median;
    let xs = vec![
        rect(2., 10.),
        rect(2.1, 10.),
        rect(2.2, 10.),
        rect(8., 10.),
        rect(8.1, 10.),
        rect(8.2, 10.),
        rect(3., 10000.),
    ];
    let median = fit(&xs, r.clone(), &r.pin()).unwrap();
    let mut mean_rule = r.clone();
    mean_rule.gauge_statistic = GaugeStatistic::ArithmeticMean;
    let mean = fit(&xs, mean_rule.clone(), &mean_rule.pin()).unwrap();
    let receipt_median = median.canonical_receipt().unwrap();
    let receipt_mean = mean.canonical_receipt().unwrap();
    assert!(receipt_median.contains(&format!("gauge={:016x}", 10f64.to_bits())));
    let expected: f64 = 6. * (10. / 7.) + 10000. / 7.;
    assert!(receipt_mean.contains(&format!("gauge={:016x}", expected.to_bits())));
    assert!(receipt_mean.contains("mean_contrast=one_sided_diagnostic_only"));
    assert_eq!(median.query(&rect(8., 10.)).unavailable_reason, None);
    assert_eq!(
        mean.query(&rect(8., 10.)).unavailable_reason.as_deref(),
        Some("unclassifiable_singleton")
    );
    assert_eq!(
        median.query(&rect(8.2, 10.)).unavailable_reason.as_deref(),
        Some("unclassifiable_singleton")
    );
    assert_eq!(mean.query(&rect(8.2, 10.)).unavailable_reason, None);
    let mut reverse = xs;
    reverse.reverse();
    let again = fit(&reverse, mean_rule.clone(), &mean_rule.pin()).unwrap();
    assert_eq!(
        mean.canonical_receipt().unwrap(),
        again.canonical_receipt().unwrap()
    );
}
