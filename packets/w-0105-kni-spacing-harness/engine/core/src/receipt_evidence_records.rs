//! Draft records only. Graph separation, fences and chronology are not verified.
use crate::decision_evidence_envelope::PinClaim;

#[derive(Clone, Debug)]
pub struct DependencyInventoryClaim {
    pub declared_membership: PinClaim,
    pub consumed_inputs: Vec<PinClaim>,
    pub configuration_revision: PinClaim,
    pub evaluator_revision: PinClaim,
    pub dependency_scope_ref: String,
    pub subject_revision: PinClaim,
}

/// Stored outside canonical-core structure; no canonical hashing occurs.
#[derive(Clone, Debug)]
pub struct NarrowReceiptClaim {
    pub receipt_id: String,
    pub bound_record: PinClaim,
    pub claimed_freeze_timestamp: String,
    pub operation_scope_ref: String,
    pub validity_scope_ref: String,
    pub producer_ref: String,
    pub permitted_successor_claims: Vec<String>,
    pub dependency_inventory: DependencyInventoryClaim,
    pub claimed_validation_evidence: Vec<PinClaim>,
}

/// Original bit patterns remain available without normalization or validation.
#[derive(Clone, Debug)]
pub struct Binary64Observation {
    pub original_bits: u64,
    pub source_ref: String,
    pub proposed_rule_ref: Option<PinClaim>,
    pub claimed_normalized_bits: Option<u64>,
}

/// Storage of prerequisites does not certify qualification or choose a policy.
#[derive(Clone, Debug)]
pub struct DiscriminationPrerequisiteClaims {
    pub explicit_current_policy_binding: Option<PinClaim>,
    pub applicable_qualified_calibrated_evidence: Vec<PinClaim>,
    pub unresolved_requirements: Vec<String>,
}
