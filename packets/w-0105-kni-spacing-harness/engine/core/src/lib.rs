//! Core crate: storage types plus the capture, fit and economy modules.
//! No stored claim is validated or accepted by this crate.
pub mod decision_evidence_envelope;
pub mod serialization_draft;
pub mod receipt_evidence_records;
pub mod ordering_observations;
pub mod outline_interface;
pub mod reference_slice;
pub mod method_domains;
pub mod svg_outline;
pub mod cubic_evaluation;
pub mod polygon_intersections;
pub mod topology_strategy;
pub mod cff_container;
pub mod sfnt_metadata;
pub mod native_font;
pub mod cff_fill;
pub mod os2_consistency;
pub mod os2_ranges;
pub mod output_binding;
pub mod fitter_requirements;
pub mod cubic_fit;
pub mod fit_search;
pub mod capture;
pub mod bounded_png_adapter;
pub mod iou_report;
pub mod capture_fit;
pub mod thresholds;
pub mod tolerance;
pub mod lever_api;
pub mod int_refine;
pub mod boundary_bias;
pub mod form;

pub mod closed_fit;

pub mod economy;
pub mod economy_eval;
pub mod c3c4_roles;
pub mod construction_region;
pub mod stroke_counter_roles;

pub mod source_provenance;

pub mod duplicate_point_audit;
pub mod jpeg_source;
pub mod jpeg_progressive;
pub mod capture_dispatch;
pub mod emitted_geometry_refine;

pub mod generated_native;
// Rounding reconcile (quantize, constant-cubic cleanup, diagnostic advance
// recovery). Lives in core so both the production binary and the canonical
// harness wire the same landed code (CANON-FIX-1).
pub mod regress_class;
pub mod rounding_reconcile;
pub mod corner_wiring;
pub mod line_audit;
pub mod ink_bounds;
pub mod reference_guided;
pub mod cff_reader;
pub mod flatten_budget;
pub mod owner_reference;

pub mod master_fit_context;
pub mod master_fit_span_ledger;
pub mod master_fit_trace_binding;

pub mod node_objective;
pub mod curve_stress;
pub mod corner_nodes;
pub mod fit_objective;
pub mod vmet_gate;

pub mod tail_refine;

pub mod reference_transfer;

pub mod generated_draw;
pub mod generated_draw_frame;
#[cfg(test)]
#[path = "pipeline_stage_accounting_regression_work_v3.rs"]
mod pipeline_stage_accounting_regression_work_v3;
pub mod canonical_scale;
pub mod canonical_scale_calibration;
pub mod offset_scope;
pub mod scale_context;

pub mod iou_adapter;
pub mod glyph_segments;
pub mod fp;
pub mod obs_envelope;
