use kni_geometry_prototypes::{GaugeStatistic, Rule};
fn main() {
    let a: Vec<_> = std::env::args().collect();
    if a.len() != 8 {
        eprintln!("usage: freeze_rule MIN_N COVERAGE_NUM COVERAGE_DEN FLATTEN_FRACTION BOOTSTRAP_REPLICATES STABILITY_FRACTION MAX_UNIQUE_TRAINING");
        std::process::exit(2)
    }
    let r = Rule {
        minimum_training: a[1].parse().unwrap(),
        gauge_statistic: GaugeStatistic::Median,
        maximum_unique_training: a[7].parse().unwrap(),
        coverage_numerator: a[2].parse().unwrap(),
        coverage_denominator: a[3].parse().unwrap(),
        flatten_fraction: a[4].parse().unwrap(),
        bootstrap_replicates: a[5].parse().unwrap(),
        stability_fraction: a[6].parse().unwrap(),
    };
    print!("{}", r.canonical());
    eprintln!("rule_sha256={}", r.pin());
}
