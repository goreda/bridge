//! G1 manifest-order fold tests for merge-visibility observation records.
//!
//! Worker completion is deliberately delayed in different patterns. The
//! stage-1 driver may finish jobs in any order, but its ordered outcomes must
//! reach the one shared reducer in manifest order so observer JSONL bytes stay
//! identical for 1/2/4/8 workers.

use super::*;
use kni_core::obs_envelope::{Frontier, Record};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

fn glyph_row(index: usize) -> GlyphRow {
    GlyphRow {
        codepoint: 0x41 + index as u32,
        extra_cps: vec![],
        name: format!("OBS{index}"),
        image: PathBuf::from("unused"),
        scale: None,
    }
}

fn outcome_with_observer_record(index: usize) -> FitOutcome {
    let mut outcome = FitOutcome::fatal(index, String::new());
    outcome.fatal = None;
    outcome.drawn = Err("synthetic observation-only test outcome".into());
    outcome.observer_records = vec![Record::Frontier(Frontier::new(
        "run-g1-fold-test".into(),
        format!("stage{}", index + 1),
        true,
        false,
    ))];
    outcome
}

fn run_fold(jobs: usize, slow_index: usize) -> (Vec<usize>, Vec<u8>) {
    let completion_order = Arc::new(Mutex::new(Vec::new()));
    let observed_completion_order = Arc::clone(&completion_order);
    let outcomes = stage1_drive(8, run_config::Jobs::new(jobs).unwrap(), move |index| {
        if index == slow_index {
            std::thread::sleep(Duration::from_millis(100));
        }
        observed_completion_order.lock().unwrap().push(index);
        outcome_with_observer_record(index)
    })
    .unwrap();

    let rows: Vec<GlyphRow> = (0..8).map(glyph_row).collect();
    let row_refs: Vec<&GlyphRow> = rows.iter().collect();
    let mut accumulator = Stage1Acc::default();
    let mut receipt = String::new();
    stage1_reduce_into(&row_refs, outcomes, &mut accumulator, None, &mut receipt).unwrap();

    let mut jsonl = Vec::new();
    for record in &accumulator.observer_records {
        jsonl.extend_from_slice(record.render().unwrap().as_bytes());
        jsonl.push(b'\n');
    }
    let finished = completion_order.lock().unwrap().clone();
    (finished, jsonl)
}

#[test]
fn observer_records_fold_in_manifest_order_despite_worker_completion_order() {
    let mut canonical: Option<Vec<u8>> = None;
    let mut saw_parallel_reordering = false;

    for jobs in [1usize, 2, 4, 8] {
        let (first_finish, first_jsonl) = run_fold(jobs, 0);
        assert_eq!(first_jsonl.iter().filter(|&&b| b == b'\n').count(), 8);
        if jobs > 1 {
            assert_ne!(
                first_finish,
                (0..8).collect::<Vec<_>>(),
                "fixture should exercise a non-manifest completion order at jobs={jobs}"
            );
            saw_parallel_reordering = true;
        }
        if let Some(expected) = &canonical {
            assert_eq!(first_jsonl, *expected, "first finish pattern, jobs={jobs}");
        } else {
            canonical = Some(first_jsonl.clone());
        }

        let (second_finish, second_jsonl) = run_fold(jobs, 7);
        if jobs > 1 {
            assert_ne!(
                first_finish, second_finish,
                "two forced completion patterns must differ at jobs={jobs}"
            );
            saw_parallel_reordering = true;
        }
        assert_eq!(
            second_jsonl,
            canonical.as_ref().unwrap(),
            "different finish pattern, jobs={jobs}"
        );
    }
    assert!(
        saw_parallel_reordering,
        "parallel fixture must produce out-of-order completion"
    );
}
