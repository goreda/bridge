//! kni-metrics: spacing and kerning engine for the KNI font engine.
//!
//! Implementation order:
//! 0. baseline_htls + collision (pipeline skeleton end-to-end on a published
//!    formula)
//! 1. distance_field
//! 2. side_walls
//! 3. side_classes
//! 4. stress + air
//! 5. mechanisms + positions
//! 6. export_gpos
//! 7. evidence ledger
//! 8. variation
//! 9. tracking
//!
//! Provenance boundaries (permanent):
//! - iKern's original equations are NOT public. Nothing in this crate claims
//!   to be the real iKern algorithm.
//! - BubbleKern v1+v2 code is recovered (Apache 2.0) and code-grounded, but
//!   its WALL OFFSET POLICY is open by the author's own statement: any
//!   auto-generated wall policy in this crate is OUR SURROGATE and is labeled
//!   as such.
//! - baseline_htls is a clean-room reimplementation of the published HT
//!   Letterspacer METHOD (huertatipografica/HTLetterspacer). Upstream code is
//!   GPL-3.0 and was consulted for formula semantics only; no code was copied.
//!
//! Input plane: pair geometry APIs accept BOTH
//! planes from day one. Today the raster plane (captures) is the operating
//! plane; when the engine emits trusted outlines, contours become the
//! geometric truth behind the same traits.

pub mod air;
pub mod anchor_audit;
pub mod baseline_htls;
pub mod cadence;
pub mod class_audit;
pub mod collision;
pub mod distance_field;
pub mod evidence;
pub mod gen;
pub mod gpos;
pub mod gpos_pairpos1;
pub mod gsub_liga;
pub mod kern_proposal;
pub mod learn;
pub mod export_gpos;
pub mod mechanisms;
pub mod params;
pub mod plane;
pub mod positions;
pub mod side_classes;
pub mod side_walls;
pub mod stress;
pub mod tracking;
pub mod training_only_fit;
pub mod variation;

/// Calibrated concrete-table apply lane; final-font insertion is downstream.
pub mod gen_production;
pub mod outline_spacing;
pub mod exact_rows;
pub mod signed_clearance;
pub mod self_anchored_spacing;
pub mod generated_outline_kern;
pub mod contrast_floor;
pub mod space_measurement;

/// Exported-OTF self-parse integrity gate (table walk + checksums).
/// Honest refusal type; the runner owns warn-export vs strict.
pub mod otf_self_parse;

pub mod pair_visual_read;
