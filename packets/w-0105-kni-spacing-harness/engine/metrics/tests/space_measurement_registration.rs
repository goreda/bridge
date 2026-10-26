//! Exact-tree registration check for kni-space-measurement/v2.3: the module
//! is exported from the crate root and carries the expected module id.
use kni_metrics::space_measurement::{MODULE_ID, LEDGER_HEADER, SpaceOutcome};

#[test]
fn space_measurement_is_registered_with_v23_id() {
    assert_eq!(MODULE_ID, "kni-space-measurement/v2.3");
    assert!(LEDGER_HEADER.starts_with("module\tstyle_id\tframe_id"));
    let _ = std::mem::size_of::<SpaceOutcome>();
}
