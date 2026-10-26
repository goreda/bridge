//! Usage: regress_class_report <cohort.tsv> <measurements.tsv> <arm_a> <arm_b>
use kni_core::regress_class::*;
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    if a.len() != 4 {
        eprintln!("usage: regress_class_report <cohort.tsv> <measurements.tsv> <arm_a> <arm_b>");
        std::process::exit(2);
    }
    let rd = |p: &str| std::fs::read_to_string(p).unwrap_or_else(|e| { eprintln!("{p}: {e}"); std::process::exit(1) });
    let c = parse_cohort(&rd(&a[0])).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    let m = parse_measurements(&rd(&a[1])).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    print!("{}", render_tsv(&report(&c, &m, &a[2], &a[3])));
}
