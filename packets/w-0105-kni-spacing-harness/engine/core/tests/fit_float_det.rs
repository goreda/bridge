//! Determinism of the fit under parallel glyph tasks. The fit is a pure
//! function of (rings, scale, policy): no output may depend on which thread ran
//! it, what that thread ran before, or in what order tasks were claimed.
//! The harness mimics the planned run: an indexed task list, worker threads
//! claiming indices in a racy order, results stored by index, then reduced in
//! index order. jobs=1 is the reference.

use kni_core::capture::{capture_png, MeasuredContour};
use kni_core::capture_fit::{fit_captured_with_fallback_events, FitCounters};
use kni_core::cubic_fit::FitPolicy;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

struct Item { mc: MeasuredContour, scale: f64 }

fn items() -> Vec<Item> {
    let files: [&[u8]; 6] = [
        include_bytes!("fixtures/r_scan.png"),
        include_bytes!("fixtures/s_scan.png"),
        include_bytes!("fixtures/u_scan.png"),
        include_bytes!("fixtures/quote_2018.png"),
        include_bytes!("fixtures/dot_00b7.png"),
        include_bytes!("fixtures/00C9_scan.png"),
    ];
    files.iter().map(|png| {
        let mc = capture_png(png, 0.29).expect("capture");
        let mxy = mc.rings.iter().flat_map(|r| r.points.iter()).fold(0f64, |a, p| a.max(p.y));
        let scale = 700.0 / mxy; // derived from the glyph itself, not a tuned constant
        Item { mc, scale }
    }).collect()
}

/// One glyph task: counters are taken before (discarding thread leftovers) and
/// after, and the whole result is serialised bit-exactly (f64 bit patterns
/// through Debug of the structs plus the counters).
fn task(it: &Item) -> String {
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let before = FitCounters::now();
    let out = fit_captured_with_fallback_events(&it.mc.rings, it.scale, &policy);
    let c: FitCounters = FitCounters::delta_since(before).expect("counters only grow");
    format!("{:?}|{:?}", out, c)
}

fn run(items: &[Item], jobs: usize, reverse_claim: bool) -> Vec<String> {
    let n = items.len();
    let next = AtomicUsize::new(0);
    let slots: Mutex<Vec<Option<String>>> = Mutex::new(vec![None; n]);
    std::thread::scope(|s| {
        for _ in 0..jobs {
            s.spawn(|| loop {
                let k = next.fetch_add(1, Ordering::SeqCst);
                if k >= n { break; }
                let idx = if reverse_claim { n - 1 - k } else { k };
                let r = task(&items[idx]);
                slots.lock().unwrap()[idx] = Some(r);
            });
        }
    });
    slots.into_inner().unwrap().into_iter().map(|o| o.expect("every index filled")).collect()
}

fn digest(rows: &[String]) -> Vec<u8> { rows.join("\n").into_bytes() }

#[test]
fn jobs4_five_runs_are_byte_equal_to_jobs1() {
    let its = items();
    let serial = digest(&run(&its, 1, false));
    assert!(serial.len() > 1000, "fixture fits produced real output");
    for i in 0..5 {
        let p = digest(&run(&its, 4, i % 2 == 1));
        assert_eq!(p, serial, "jobs=4 run {i} differs from jobs=1");
    }
}

#[test]
fn a_thread_reused_for_many_glyphs_matches_fresh_threads() {
    // Same thread runs every glyph twice in different orders: leftovers from
    // one glyph (RAW_RING, counters) must not reach the next.
    let its = items();
    let fresh: Vec<String> = its.iter().map(|it| std::thread::scope(|s| s.spawn(|| task(it)).join().unwrap())).collect();
    let mut reused = vec![String::new(); its.len()];
    for pass in 0..2 {
        let order: Vec<usize> = if pass == 0 { (0..its.len()).collect() } else { (0..its.len()).rev().collect() };
        for i in order { reused[i] = task(&its[i]); assert_eq!(reused[i], fresh[i], "glyph {i} pass {pass}"); }
    }
}

#[test]
fn counters_are_per_task_and_sum_in_index_order() {
    let its = items();
    let per: Vec<FitCounters> = its.iter().map(|it| {
        let before = FitCounters::now();
        let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
        let _ = fit_captured_with_fallback_events(&it.mc.rings, it.scale, &policy);
        FitCounters::delta_since(before).expect("counters only grow")
    }).collect();
    // No fit between two reads: the delta is empty.
    let idle = FitCounters::now();
    assert_eq!(FitCounters::delta_since(idle), Some(FitCounters::default()));
    // The same totals come back from 4 racing threads, reduced by index.
    let rows = run(&its, 4, true);
    let tail: Vec<String> = per.iter().map(|c| format!("{:?}", c)).collect();
    for (r, t) in rows.iter().zip(tail.iter()) { assert!(r.ends_with(t.as_str()), "counter mismatch: {t}"); }
    assert!(per.iter().any(|c| c.reloc_moved > 0 || c.straight_sweep > 0), "fixtures exercise the counters");
}
