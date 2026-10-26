//! Dependency and walk records only, never an executable lane scheduler.
use crate::decision_evidence_envelope::PinClaim;

#[derive(Clone, Debug)]
pub enum MetricPassClaim {
    PreselectionPassOne,
    PostDraftingPassTwo,
}

#[derive(Clone, Debug)]
pub struct MetricInputClaim {
    pub pass: MetricPassClaim,
    pub candidate_evidence_refs: Vec<PinClaim>,
    pub drafting_refs: Vec<PinClaim>,
    pub dependency_rule_revision: PinClaim,
    pub unresolved_inputs: Vec<String>,
}

#[derive(Clone, Debug)]
pub enum CrashBoundaryClaim {
    BeforeCanonicalCommit,
    AfterCanonicalBeforeReceiptPersistence,
    AfterReceiptPersistence,
}

/// Retains the claimed storage model without asserting its capabilities.
#[derive(Clone, Debug)]
pub struct FenceClaim {
    pub authoritative_subject_ref: String,
    pub snapshot_or_epoch_ref: String,
    pub dependency_inventory: PinClaim,
    pub validation_ref: Option<PinClaim>,
    pub persistence_ref: Option<PinClaim>,
    pub mechanism_description: String,
    pub unresolved_capabilities: Vec<String>,
}

/// Expected results are plans, observed results require independently held pins.
/// Missing observation is NOT_RUN, not a passed walk or an outcome verdict.
#[derive(Clone, Debug)]
pub struct NegativeWalkRecord {
    pub walk_id: String,
    pub record_class_label: String,
    pub scenario_ref: String,
    pub expected_result_claim: String,
    pub observation_ref: Option<PinClaim>,
    pub observed_result_claim: Option<String>,
    pub boundary: Option<CrashBoundaryClaim>,
    pub unresolved_requirements: Vec<String>,
}
