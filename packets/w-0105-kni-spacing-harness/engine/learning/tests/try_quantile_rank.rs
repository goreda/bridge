//! Nearest-rank exactness of `try_quantile`. The rank is `ceil(p * n)` computed
//! in f64. For the quantiles the gate uses (0.5 and 0.9) the product must land
//! on the same integer as the exact rational rank, including the sizes where
//! `p * n` is an exact integer in decimal. Slice lengths are far below 2^53, the
//! limit above which an f64 can no longer count every length, so that range is
//! out of reach and not tested.

use kni_learning::gate::try_quantile;

/// Sorted input 1..=n, so the value at rank r is r as f64.
fn ramp(n: usize) -> Vec<f64> {
    (1..=n).map(|x| x as f64).collect()
}

/// Exact rank ceil(num * n / den) in integers.
fn exact_rank(num: usize, den: usize, n: usize) -> usize {
    (num * n + den - 1) / den
}

#[test]
fn rank_matches_the_exact_rational_for_every_length_up_to_3000() {
    for n in 1..=3000usize {
        let v = ramp(n);
        assert_eq!(try_quantile(&v, 0.5), Ok(exact_rank(1, 2, n) as f64), "p=0.5 n={n}");
        assert_eq!(try_quantile(&v, 0.9), Ok(exact_rank(9, 10, n) as f64), "p=0.9 n={n}");
    }
}

#[test]
fn rank_is_exact_at_large_lengths_where_p_times_n_is_a_whole_number() {
    for n in [99_990usize, 100_000, 100_010, 999_990, 1_000_000, 1_000_010, 1_000_001] {
        let v = ramp(n);
        assert_eq!(try_quantile(&v, 0.5), Ok(exact_rank(1, 2, n) as f64), "p=0.5 n={n}");
        assert_eq!(try_quantile(&v, 0.9), Ok(exact_rank(9, 10, n) as f64), "p=0.9 n={n}");
    }
}

#[test]
fn quantile_bounds_pick_the_extreme_ranks() {
    for n in [1usize, 2, 3, 10, 1001] {
        let v = ramp(n);
        assert_eq!(try_quantile(&v, 0.0), Ok(1.0), "p=0 n={n}");
        assert_eq!(try_quantile(&v, 1.0), Ok(n as f64), "p=1 n={n}");
    }
}

#[test]
fn rank_does_not_depend_on_input_order() {
    let mut v = ramp(1000);
    v.reverse();
    assert_eq!(try_quantile(&v, 0.9), Ok(900.0));
    assert_eq!(try_quantile(&v, 0.5), Ok(500.0));
}
