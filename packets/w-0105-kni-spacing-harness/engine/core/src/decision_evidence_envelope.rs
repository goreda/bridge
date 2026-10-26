//! Inert, unverified records. No decisions, validation, hashing or effects.
//! Optional records mean absent storage, not an operational verdict.

#[derive(Clone, Debug)]
pub struct PinClaim {
    pub algorithm: String,
    pub claimed_digest: String,
    pub subject_ref: String,
}

#[derive(Clone, Debug)]
pub struct SubjectBindingClaim {
    pub source: PinClaim,
    pub subject_identity: String,
    pub frame_ref: String,
    pub region_revision: PinClaim,
    pub orientation_ref: Option<String>,
}

#[derive(Clone, Debug)]
pub enum RecordClass {
    Candidate,
    Assessment,
    CanonicalCore,
    Receipt,
    Evidence,
}

#[derive(Clone, Debug)]
pub struct EvidenceRecord {
    pub record_id: String,
    pub record_class: RecordClass,
    pub producer_revision: PinClaim,
    pub subject: SubjectBindingClaim,
    pub input_pins: Vec<PinClaim>,
    pub output_refs: Vec<String>,
    pub configuration_revision: PinClaim,
    pub evaluator_revision: PinClaim,
    pub claimed_created_timestamp: String,
    pub domain_label: String,
}

#[derive(Clone, Debug)]
pub enum DecisionClaim {
    NoEligible,
    UnresolvedRivals,
    ProvisionallySelected,
}

#[derive(Clone, Debug)]
pub struct DecisionRecord {
    pub claim: DecisionClaim,
    pub declared_candidate_set: PinClaim,
    pub candidate_refs: Vec<String>,
    pub rule_revision: PinClaim,
    pub evidence_refs: Vec<String>,
}

#[derive(Clone, Debug)]
pub enum SourceLogicalClaim {
    InvalidBinding,
    NoEligible,
    ValidUnresolvedRivals,
    UnknownProof,
    UnknownExecution,
}

#[derive(Clone, Debug)]
pub struct ProofBindingRecord {
    pub source_claim: SourceLogicalClaim,
    pub affected_scope: String,
    pub rule_revision: PinClaim,
    pub evidence_refs: Vec<String>,
}

#[derive(Clone, Debug)]
pub enum ExecutionClaim {
    RefusedOperation,
    OutcomeUnknown,
    CompletedNarrow,
}

#[derive(Clone, Debug)]
pub struct ExecutionRecord {
    pub claim: ExecutionClaim,
    pub operation_ref: String,
    pub reason_code: String,
    pub reason_details: Vec<String>,
    pub evidence_refs: Vec<String>,
    pub permitted_successor_claims: Vec<String>,
    pub receipt_ref: Option<String>,
}

/// Blocking vocabulary is descriptive input, not a decision-axis extension.
#[derive(Clone, Debug)]
pub struct BlockingObservation {
    pub source_label: String,
    pub affected_scope: String,
    pub missing_or_unknown_facts: Vec<String>,
    pub evidence_refs: Vec<String>,
    pub continuation_claims: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct DecisionEvidenceEnvelope {
    pub envelope_id: String,
    pub evidence: Vec<EvidenceRecord>,
    pub decision: Option<DecisionRecord>,
    pub proof_binding: Option<ProofBindingRecord>,
    pub execution: Option<ExecutionRecord>,
    pub blocking_observations: Vec<BlockingObservation>,
}
