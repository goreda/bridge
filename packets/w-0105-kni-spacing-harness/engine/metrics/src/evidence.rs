//! Evidence discipline: every value the engine emits
//! carries its derivation tier, and the principles the engine encodes are
//! tracked in a ledger with per-mechanism satisfaction records.

/// Derivation tier of a metric value (per-pair tier tag in the final
/// measurement report).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    /// Measured directly from a source (capture or source font).
    DirectSource,
    /// Propagated through a side/class from direct-source values.
    ClassDerived,
    /// Produced by the engine's own mechanisms, without a source anchor.
    /// The baseline heuristic lives here: it is a published proxy, not a
    /// measurement of the font being spaced.
    EngineDerived,
    /// Set by a designer override.
    DesignerOverride,
}

/// Lifecycle of an engine rule (traceability discipline: no rule enters the
/// engine without provenance or an engine-side validation result).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleStatus {
    Proposed,
    Validated,
}

/// Principle ledger record: one row per encoded principle, with the fields
/// needed to audit where it came from and what satisfies it.
#[derive(Debug, Clone)]
pub struct PrincipleRecord {
    pub id: &'static str,
    pub source: &'static str,
    pub scope: &'static str,
    pub observable: &'static str,
    pub conflicts: &'static str,
    pub equivalents: &'static str,
    pub implemented_by: &'static str,
    pub status: RuleStatus,
}

/// Receipt attached to one spacing computation: the inputs and intermediates
/// needed to audit or reproduce the result.
#[derive(Debug, Clone)]
pub struct SpacingReceipt {
    /// Method identifier, including provenance.
    pub method: &'static str,
    /// Derivation tier of the emitted values.
    pub tier: Tier,
    /// The master parameters actually used.
    pub params: crate::params::MasterParams,
    /// Reference measurement window (min_y_ref, max_y_ref).
    pub window: (f64, f64),
    /// Free-form audit notes (abort reasons, clamp activity, ...).
    pub notes: String,
}

/// Per-pair evidence tag for the measurement report: the derivation tier of
/// the pair's values plus an audit note.
#[derive(Debug, Clone)]
pub struct PairEvidence {
    pub tier: Tier,
    pub note: String,
}

/// Map a wall's provenance to its derivation tier (per-pair tier tags in
/// the final report flow from this mapping; no wall enters a report
/// without its tier).
pub fn wall_source_tier(source: crate::side_walls::WallSource) -> Tier {
    use crate::side_walls::WallSource;
    match source {
        WallSource::Measured => Tier::DirectSource,
        WallSource::DefaultLine => Tier::EngineDerived,
        WallSource::DesignerOverride => Tier::DesignerOverride,
        WallSource::ClassPropagated => Tier::ClassDerived,
    }
}

/// The principle ledger: the registry of every principle the engine
/// encodes, auditable by id.
#[derive(Debug, Clone)]
pub struct Ledger {
    pub records: Vec<PrincipleRecord>,
}

impl Ledger {
    /// Look up one principle by id.
    pub fn get(&self, id: &str) -> Option<&PrincipleRecord> {
        self.records.iter().find(|r| r.id == id)
    }

    /// Principles implemented by one module (satisfaction query).
    pub fn satisfied_by(&self, module: &str) -> Vec<&PrincipleRecord> {
        self.records.iter().filter(|r| r.implemented_by == module).collect()
    }

    /// Structural validation: unique ids, no empty fields, implemented_by
    /// names a known module.
    pub fn validate(&self, known_modules: &[&str]) -> Result<(), String> {
        let mut seen = std::collections::BTreeSet::new();
        for r in &self.records {
            if !seen.insert(r.id) {
                return Err(format!("duplicate principle id {}", r.id));
            }
            for (field, name) in [
                (r.source, "source"),
                (r.scope, "scope"),
                (r.observable, "observable"),
                (r.implemented_by, "implemented_by"),
            ] {
                if field.is_empty() {
                    return Err(format!("principle {} has empty {}", r.id, name));
                }
            }
            if !known_modules.contains(&r.implemented_by) {
                return Err(format!(
                    "principle {} implemented_by unknown module {}",
                    r.id, r.implemented_by
                ));
            }
        }
        Ok(())
    }
}

/// The engine's principle ledger as implemented so far. Every entry names
/// its grounding; OUR SURROGATE/CANDIDATE principles are marked Proposed,
/// published or code-grounded ones with engine-side tests are Validated.
pub fn engine_ledger() -> Ledger {
    let rec = |id, source, scope, observable, conflicts, equivalents, implemented_by, status| {
        PrincipleRecord { id, source, scope, observable, conflicts, equivalents, implemented_by, status }
    };
    Ledger {
        records: vec![
            rec("htls-baseline-formula",
                "HT Letterspacer published method (GPL-3.0 upstream consulted for semantics only; clean-room)",
                "baseline_htls sidebearing computation",
                "sidebearings from area quadrature with depth clamp and 45-degree closure",
                "none known", "none", "baseline_htls", RuleStatus::Validated),
            rec("deslant-sign-convention",
                "engine-declared convention (raster plane y-down)",
                "italic deslant: x += (y - mline) * tan(angle), mline = baseline_y - x_height/2",
                "sheared measurement windows and slanted walls",
                "none known", "none", "baseline_htls", RuleStatus::Validated),
            rec("wall-format-v2",
                "BubbleKern v2 code",
                "wall storage: y-sorted (x,y) polyline, side-relative frames, upright storage",
                "wall point order and slant-at-use",
                "none known", "none", "side_walls", RuleStatus::Validated),
            rec("wall-offset-policy-surrogate",
                "OUR SURROGATE (BubbleKern walls are designer-drawn; no published auto policy)",
                "measured wall derivation from ink profiles",
                "offset applied outward from ink edge",
                "the BubbleKern author states the best bubble shape is unknown",
                "designer override path", "side_walls", RuleStatus::Proposed),
            rec("lockstep-exact-wall-gap",
                "BubbleKern v2 code",
                "pair wall gap: lockstep vertex sampling, exact for polylines",
                "min horizontal gap over shared y-range, no grid error",
                "none known", "BubbleKern v1 10-unit grid scan", "positions", RuleStatus::Validated),
            rec("v1-reference-thresholds",
                "BubbleKern v1 code (REFERENCE DEFAULTS, tunable, not doctrine)",
                "kern thresholding and fail-safe maxKern",
                ">=10 as-is, 8-10 round up, <8 skip, maxKern = min(w)/2",
                "v1 Adhere-to-SB trimming blocks positive kerns; KNI keeps both signs",
                "none", "positions", RuleStatus::Proposed),
            rec("softmin-gate-candidate",
                "OUR CANDIDATE (sigmoid/softmin experiments are ours, not published data)",
                "side_classes membership gating",
                "membership degrees normalized over class distances",
                "none known", "hard nearest-prototype assignment (regression baseline)",
                "side_classes", RuleStatus::Proposed),
            rec("htls-category-factor",
                "HTLS published rule semantics (hard category factor on paramArea)",
                "area factor resolution per glyph side",
                "effectiveArea = paramArea * factor; hard baseline recovered at one-hot membership",
                "none known", "membership-weighted factor (OUR CANDIDATE)",
                "side_classes", RuleStatus::Validated),
            rec("bblh-v1-format",
                "BubbleKern v1 code (table layout)",
                "runtime wall table serialization",
                "big-endian version+count, presence byte, int32 points, right set width-offset",
                "advance not stored; supplied from font metrics at runtime",
                "none", "export_gpos", RuleStatus::Validated),
            rec("byte-model-surrogate",
                "OUR SURROGATE (real GPOS serializer not yet landed)",
                "storage-aware compile cost function",
                "estimated bytes = fixed + class pairs + exceptions",
                "none known", "real serialized GPOS cost function (planned)",
                "export_gpos", RuleStatus::Proposed),
            rec("storage-aware-discipline",
                "Lucke downsizing; Adobe kernFeatureWriter order",
                "class compilation: exceptions first, locked pairs exact, max/mean reported separately",
                "merge ranking by error-increase per byte saved within budget",
                "none known", "none", "export_gpos", RuleStatus::Proposed),
            rec("per-pair-tier-tags",
                "per-pair traceability requirement; Willis traceability",
                "measurement report: every pair value carries its derivation tier",
                "wall provenance maps to DirectSource/ClassDerived/EngineDerived/DesignerOverride",
                "none known", "none", "evidence", RuleStatus::Validated),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_walls::WallSource;

    const MODULES: &[&str] = &[
        "air", "baseline_htls", "collision", "distance_field", "evidence",
        "export_gpos", "mechanisms", "params", "plane", "positions",
        "side_classes", "side_walls", "stress", "tracking", "variation",
    ];

    #[test]
    fn ledger_validates() {
        assert!(engine_ledger().validate(MODULES).is_ok());
    }

    #[test]
    fn ledger_lookup_and_satisfaction() {
        let l = engine_ledger();
        assert!(l.get("lockstep-exact-wall-gap").is_some());
        assert!(l.get("no-such-principle").is_none());
        let eg = l.satisfied_by("export_gpos");
        assert!(eg.len() >= 3, "bblh + byte model + discipline");
        assert!(l.satisfied_by("tracking").is_empty());
    }

    #[test]
    fn surrogates_and_candidates_marked_proposed() {
        let l = engine_ledger();
        for id in [
            "wall-offset-policy-surrogate",
            "softmin-gate-candidate",
            "byte-model-surrogate",
            "v1-reference-thresholds",
        ] {
            let r = l.get(id).unwrap();
            assert_eq!(r.status, RuleStatus::Proposed, "{id} must stay Proposed");
            assert!(r.source.contains("SURROGATE") || r.source.contains("CANDIDATE") || r.source.contains("REFERENCE"), "{id} source labels itself");
        }
    }

    #[test]
    fn wall_source_tier_mapping_complete() {
        assert_eq!(wall_source_tier(WallSource::Measured), Tier::DirectSource);
        assert_eq!(wall_source_tier(WallSource::DefaultLine), Tier::EngineDerived);
        assert_eq!(wall_source_tier(WallSource::DesignerOverride), Tier::DesignerOverride);
        assert_eq!(wall_source_tier(WallSource::ClassPropagated), Tier::ClassDerived);
    }

    #[test]
    fn validate_catches_duplicate_ids() {
        let mut l = engine_ledger();
        let dup = l.records[0].clone();
        l.records.push(dup);
        assert!(l.validate(MODULES).is_err());
    }
}
