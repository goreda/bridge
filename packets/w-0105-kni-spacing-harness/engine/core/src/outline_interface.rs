//! Per-glyph best-effort interface. No solver or confidence calculation exists.
//! No outcome carries a font-publication decision or sibling-glyph blocker.
use crate::decision_evidence_envelope::{PinClaim, SubjectBindingClaim};

#[derive(Clone, Debug)]
pub enum OutlineRequestKind {
    WholeContour,
    CurveSpan,
}

/// Stored request data alone does not attempt an operation.
#[derive(Clone, Debug)]
pub struct GlyphOutlineRequest {
    pub operation_id: String,
    pub subject: SubjectBindingClaim,
    pub kind: OutlineRequestKind,
    pub source_geometry_ref: PinClaim,
    pub current_policy_binding_claim: Option<PinClaim>,
    pub qualified_calibrated_evidence_claims: Vec<PinClaim>,
    pub configuration_revision: PinClaim,
    pub evaluator_revision: PinClaim,
    pub budget_description: String,
    pub seam_region_binding_claims: Vec<PinClaim>,
    pub junction_applicability_claims: Vec<PinClaim>,
}

#[derive(Clone, Debug)]
pub enum OutlineLimitation {
    MissingCurrentPolicyBinding,
    MissingQualifiedCalibratedEvidence,
    SuppliedPolicyBindingNotVerified,
    SuppliedEvidenceQualificationNotVerified,
    JunctionApplicabilityOpen,
}

/// References only: no geometry is fabricated, decoded or validated here.
#[derive(Clone, Debug)]
pub struct BestEffortOutline {
    pub operation_id: String,
    pub subject: SubjectBindingClaim,
    pub closed_outline: ClosedOutlineArtifact,
    pub producer_method_ref: PinClaim,
}

#[derive(Clone, Debug)]
pub enum ImpossibleOutlineReason {
    NoSourceData,
    NoMethodAvailable,
}

/// Hard refusal applies only to this requested glyph and called operation.
#[derive(Clone, Debug)]
pub struct OutlineOperationRefusal {
    pub operation_id: String,
    pub reason: ImpossibleOutlineReason,
    pub retained_request: GlyphOutlineRequest,
    pub limitations: Vec<OutlineLimitation>,
    pub required_next_steps: Vec<String>,
}

/// Future normal outcome is best effort; shell has no generation method yet.
#[derive(Clone, Debug)]
pub enum OutlineRequestOutcome {
    BestEffort(BestEffortOutline),
    Impossible(OutlineOperationRefusal),
}

pub trait GlyphOutlineInterface {
    fn request_outline(&self, request: GlyphOutlineRequest) -> OutlineRequestOutcome;
}

/// No method is available: this shell can never produce a best-effort outline.
#[derive(Clone, Debug)]
pub struct FailClosedOutlineShell;

impl GlyphOutlineInterface for FailClosedOutlineShell {
    fn request_outline(&self, request: GlyphOutlineRequest) -> OutlineRequestOutcome {
        let mut limitations = Vec::new();
        match &request.current_policy_binding_claim {
            None => limitations.push(OutlineLimitation::MissingCurrentPolicyBinding),
            Some(_) => limitations.push(OutlineLimitation::SuppliedPolicyBindingNotVerified),
        }
        if request.qualified_calibrated_evidence_claims.is_empty() {
            limitations.push(OutlineLimitation::MissingQualifiedCalibratedEvidence);
        } else {
            limitations.push(OutlineLimitation::SuppliedEvidenceQualificationNotVerified);
        }
        limitations.push(OutlineLimitation::JunctionApplicabilityOpen);
        OutlineRequestOutcome::Impossible(OutlineOperationRefusal {
            operation_id: request.operation_id.clone(),
            reason: ImpossibleOutlineReason::NoMethodAvailable,
            retained_request: request,
            limitations,
            required_next_steps: vec![
                String::from("Implement and validate an outline method for this requested glyph"),
                String::from("Keep any audit limitations internal; output only the drawn outline"),
            ],
        })
    }
}

/// Output invariant: every contour must be closed before artifact acceptance.
/// No raw-pin constructor; actual geometry adapter below must validate closure.
/// Endpoint coincidence alone must not be silently chosen as the closure rule.
#[derive(Clone, Debug)]
pub struct ClosedOutlineArtifact {
    outline_ref: PinClaim,
    closure_validation_ref: PinClaim,
}

impl ClosedOutlineArtifact {
    pub fn outline_ref(&self) -> &PinClaim {
        &self.outline_ref
    }

    pub fn closure_validation_ref(&self) -> &PinClaim {
        &self.closure_validation_ref
    }
}

/// Actual geometry closure adapter, not authenticity of supplied record pins.
#[derive(Clone,Debug)]
pub struct ValidatedClosedGeometry {geometry:crate::reference_slice::DrawnGlyph,validation_record:PinClaim}
#[derive(Clone,Debug)]
pub enum ClosedGeometryError {NoOutline,NonFinite,OpenContour}
impl ValidatedClosedGeometry {
    pub fn validate(geometry:crate::reference_slice::DrawnGlyph,validation_record:PinClaim)->Result<Self,ClosedGeometryError>{
        use crate::reference_slice::Span;
        if geometry.rings.is_empty(){return Err(ClosedGeometryError::NoOutline);}
        for ring in &geometry.rings{let mut points=vec![ring.start];let mut end=ring.start;if ring.spans.is_empty(){return Err(ClosedGeometryError::NoOutline);}for span in &ring.spans{match span{Span::Line{end:p}=>{points.push(*p);end=*p;},Span::Cubic{control_one,control_two,end:p}=>{points.extend([*control_one,*control_two,*p]);end=*p;}}}if points.iter().any(|p|!p.x.is_finite()||!p.y.is_finite()){return Err(ClosedGeometryError::NonFinite);}if end!=ring.start{return Err(ClosedGeometryError::OpenContour);}}
        Ok(Self{geometry,validation_record})
    }
    pub fn geometry(&self)->&crate::reference_slice::DrawnGlyph{&self.geometry}
    pub fn validation_record(&self)->&PinClaim{&self.validation_record}
    pub fn artifact_claim(&self,outline_ref:PinClaim)->ClosedOutlineArtifact{ClosedOutlineArtifact{outline_ref,closure_validation_ref:self.validation_record.clone()}}
}

// ---------- encode-boundary closure audit (detection only) ----------
/// Closure outcome of one glyph handed to the font encoder. The audit
/// shares the encode-side closure invariant through the library's own
/// adapter (`ValidatedClosedGeometry::validate`); nothing is copied,
/// mutated or refused here - the encoder's own gates stay the only
/// behavior gate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClosureAuditStatus {
    /// Every ring is closed, finite and non-empty.
    Closed,
    /// No rings, or a ring with no spans.
    NoOutline,
    /// A non-finite coordinate.
    NonFinite,
    /// A ring's last span end does not return to its start.
    OpenContour,
}

impl ClosureAuditStatus {
    pub fn tag(self) -> &'static str {
        match self {
            Self::Closed => "closed",
            Self::NoOutline => "no_outline",
            Self::NonFinite => "non_finite",
            Self::OpenContour => "open_contour",
        }
    }
}

/// One audited glyph at the encode boundary.
#[derive(Clone, Debug)]
pub struct ClosureAuditRow {
    pub glyph: String,
    pub rings: usize,
    pub spans: usize,
    pub status: ClosureAuditStatus,
}

/// Audit one shipped glyph's closure through the closure adapter. The
/// adapter stores a validation-record pin the audit does not need, so a
/// declared audit-marker pin is passed; the closure verdict is the row's
/// content, never the marker.
pub fn audit_glyph_closure(geometry: &crate::reference_slice::DrawnGlyph) -> ClosureAuditRow {
    let pin = PinClaim {
        algorithm: String::from("closure-audit-v1"),
        claimed_digest: String::from("unverified"),
        subject_ref: geometry.glyph_id.clone(),
    };
    let status = match ValidatedClosedGeometry::validate(geometry.clone(), pin) {
        Ok(_) => ClosureAuditStatus::Closed,
        Err(ClosedGeometryError::NoOutline) => ClosureAuditStatus::NoOutline,
        Err(ClosedGeometryError::NonFinite) => ClosureAuditStatus::NonFinite,
        Err(ClosedGeometryError::OpenContour) => ClosureAuditStatus::OpenContour,
    };
    ClosureAuditRow {
        glyph: geometry.glyph_id.clone(),
        rings: geometry.rings.len(),
        spans: geometry.rings.iter().map(|r| r.spans.len()).sum(),
        status,
    }
}

/// The always-written closure-audit artifact: one typed row per glyph
/// plus a summary header. Rendering only: no value is recomputed here.
pub fn closure_audit_tsv(rows: &[ClosureAuditRow]) -> String {
    let closed = rows.iter().filter(|r| r.status == ClosureAuditStatus::Closed).count();
    let mut out = String::from("# encode-closure-audit v1: every glyph handed to the encoder, closure validated via outline_interface::ValidatedClosedGeometry (detection only, no geometry or behavior change)\n");
    out.push_str(&format!("# glyphs\t{}\tclosed\t{}\tnot_closed\t{}\n", rows.len(), closed, rows.len() - closed));
    out.push_str("glyph\trings\tspans\tstatus\n");
    for r in rows {
        out.push_str(&format!("{}\t{}\t{}\t{}\n", r.glyph, r.rings, r.spans, r.status.tag()));
    }
    out
}
