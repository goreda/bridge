//! Tests for try_quantile / try_stats and the closed report on non-finite input.

use kni_learning::gate::{evaluate_font, try_quantile, try_stats, StatsError};
use kni_learning::prior::Key;
use kni_learning::store::{Obs, Provenance, Store};
use kni_learning::{Cell, Priors};

fn key() -> Key {
    vec![("shape".to_string(), "a".to_string())]
}

fn obs(font: &str, mean: f64) -> Obs {
    Obs {
        key: key(),
        n: 1,
        sum: mean,
        sumsq: mean * mean,
        prov: Provenance {
            font_id: font.to_string(),
            run_id: "r".to_string(),
            receipt_id: "c".to_string(),
            tested_sha: "s".to_string(),
            declared_cap_u: 700.0,
            measured_cap_px: 70.0,
            certified: true,
        },
    }
}

fn store(fonts: &[(&str, f64)]) -> Store {
    let mut s = Store::new(1, &["shape"]).unwrap();
    for (f, m) in fonts {
        s.append(obs(f, *m)).unwrap();
    }
    s
}

#[test]
fn try_quantile_and_stats_values_and_refusals() {
    assert_eq!(try_quantile(&[], 0.5), Err(StatsError::Empty));
    assert_eq!(try_quantile(&[1.0, f64::NAN], 0.5), Err(StatsError::NonFinite { index: 1 }));
    assert_eq!(try_quantile(&[1.0, f64::INFINITY], 0.5), Err(StatsError::NonFinite { index: 1 }));
    assert_eq!(try_quantile(&[1.0], 1.5), Err(StatsError::BadQuantile));
    assert_eq!(try_quantile(&[1.0], f64::NAN), Err(StatsError::BadQuantile));
    assert_eq!(try_quantile(&[3.0, 1.0, 2.0], 0.5), Ok(2.0));
    assert_eq!(try_quantile(&[3.0, 1.0, 2.0], 0.0), Ok(1.0));
    assert_eq!(try_quantile(&[3.0, 1.0, 2.0], 1.0), Ok(3.0));
    let v: Vec<f64> = (1..=10).map(|x| x as f64).collect();
    let st = try_stats(&v).unwrap();
    assert_eq!((st.median, st.p90), (5.0, 9.0));
    assert_eq!(try_stats(&[]), Err(StatsError::Empty));
}

#[test]
fn non_finite_input_gives_a_closed_report_with_a_reason() {
    let s = store(&[("f1", 10.0), ("f2", 20.0), ("f3", 30.0)]);
    let pri = Priors::build(&s.records, Some("f3"));
    let cells = vec![Cell { key: key(), observed: 1.0, baseline_pred: f64::NAN }];
    let r = evaluate_font(&pri, "f3", &cells);
    assert!(!r.open);
    assert_eq!(r.refusal, Some(StatsError::NonFinite { index: 0 }));
    assert_eq!(r.scored, 1);
}

