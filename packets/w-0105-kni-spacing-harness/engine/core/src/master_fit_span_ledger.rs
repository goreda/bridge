//! Human-readable identity-only span ledger for one `BoundMasterFit`.
//!
//! STRUCTURAL_BINDING_ONLY. Every value printed here is structural identity
//! data carried by the binding: master/ring/span indices, carried IDs, span
//! kind, source column, L/R leaf path, the supplied wrapped raw interval and
//! the ordered split chain. Raw indices name positions in the supplied
//! master's captured ring `raw` point array as supplied by the trace; their
//! bounds are UNVERIFIED (no MasterSet here). The wrapped column interval is
//! printed as supplied and is NOT claimed to be the terminal leaf's
//! subinterval. `master_id` and `correspondence_id` are carried claims,
//! NOT verified. The format excludes the receipt, the policy echoes,
//! the axes and `source_pin`; the header carries claims only, plus glyph
//! structural IDs. This module prints NO endpoint coordinates, NO metrics,
//! NO grid or frame defaults, and it is NOT an exporter or serialization
//! registry entry: it returns one text value and performs no I/O, no file
//! artifact, no util wiring. It reads `fit.binding()` ONLY - never
//! `fit.result()` or `fit.trace()` (a static, greppable property; integer
//! index fields are not coordinates). Freshness of the binding is an
//! ownership fact, not a re-check here: the only `BoundMasterFit`
//! constructor binds the fresh pair atomically.
//!
//! Record grammar (v1), one record per line, TAB-separated fields:
//!   kni.span-ledger.v1
//!   scope\tSTRUCTURAL_BINDING_ONLY\tidentity only; raw bounds UNVERIFIED; carried claims NOT verified
//!   glyph\t<escaped glyph_id>
//!   master\t<master_index>\tmaster_id=<escaped>
//!   ring\t<ring position 0..>\tcorrespondence_id=<escaped>\tcaptured_ring_index=<n>\tstart_raw_index=<n>
//!   span\t<span_index_in_ring>\tkind=<line|cubic>\tcolumn=<n>\tpath=<escaped>\traw=(<start>,<end>)\tsplits=[<i0>,<i1>,...]
//! A span record belongs to the most recent ring record; a ring record to
//! the most recent master record. Ring identity travels on every ring
//! record (correspondence_id + captured_ring_index + start_raw_index).
//!
//! Escaping: delegated to the canonical `crate::iou_report::escape_id`
//! (same crate, unit-tested): ASCII alphanumerics and `.` `_` `-` `+` pass
//! verbatim, every other UTF-8 byte - including every byte of a non-ASCII
//! (Unicode) character's UTF-8 encoding - becomes `%XX` (uppercase hex),
//! and the empty string becomes `%EMPTY`. The result never contains whitespace,
//! TAB, LF or slash, so one-record-per-line and TAB-field rules cannot be
//! broken by a carried ID. The empty root path of an unsplit leaf therefore
//! prints as the explicit marker `%EMPTY`, never as a blank field.
//!
//! Ordering: records emit in STORED order (masters, rings, spans in
//! `span_index_in_ring` order). The binding's canonical guards (exact
//! span-index order, column position == column id) already make the stored
//! order canonical, so this function never sorts or reorders.

use crate::iou_report::escape_id;
use crate::master_fit_context::SpanKind;
use crate::master_fit_trace_binding::BoundMasterFit;

/// Format the whole bound fit as one deterministic text ledger. Pure: same
/// input, same output; no I/O.
pub fn format_span_ledger(fit: &BoundMasterFit) -> String {
    let b = fit.binding();
    let mut out = String::new();
    out.push_str("kni.span-ledger.v1\n");
    out.push_str("scope\tSTRUCTURAL_BINDING_ONLY\tidentity only; raw bounds UNVERIFIED; carried claims NOT verified\n");
    out.push_str(&format!("glyph\t{}\n", escape_id(&b.glyph_id)));
    for m in &b.masters {
        out.push_str(&format!(
            "master\t{}\tmaster_id={}\n",
            m.master_index,
            escape_id(&m.master_id),
        ));
        for (ri, r) in m.rings.iter().enumerate() {
            out.push_str(&format!(
                "ring\t{}\tcorrespondence_id={}\tcaptured_ring_index={}\tstart_raw_index={}\n",
                ri,
                escape_id(&r.correspondence_id),
                r.captured_ring_index,
                r.start_raw_index,
            ));
            for s in &r.spans {
                let chain = s
                    .split_chain
                    .iter()
                    .map(|i| i.to_string())
                    .collect::<Vec<_>>()
                    .join(",");
                out.push_str(&format!(
                    "span\t{}\tkind={}\tcolumn={}\tpath={}\traw=({},{})\tsplits=[{}]\n",
                    s.span_index_in_ring,
                    kind_str(s.kind),
                    s.source_column,
                    escape_id(&s.source_path),
                    s.column_raw_interval.0,
                    s.column_raw_interval.1,
                    chain,
                ));
            }
        }
    }
    out
}

fn kind_str(k: SpanKind) -> &'static str {
    match k {
        SpanKind::Line => "line",
        SpanKind::Cubic => "cubic",
    }
}
