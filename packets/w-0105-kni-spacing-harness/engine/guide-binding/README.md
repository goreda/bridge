# Source-bound guide annotations

This package derives guide positions from independently classified source-edge observations within one font, master, style and frame. It reports node offsets without changing outlines, handles, capture data, frames or charstrings. There is no snapping, fitting hook, selector, gain claim or automatic semantic classifier.

Every measurement row carries `no snap, measurement/annotation only`. Binding is disabled by default and must be explicitly requested with `BindingMode::Measure`. The module uses the standard library only.

## Input contract

Supply a nonempty font/master/style/frame scope, a source SHA256, the requested guide classes and source edges. Each edge requires a unique identity, glyph identity, class, membership evidence and nonempty finite y-up font-unit source samples. These must be source observations, not the evaluated fitted nodes. The same source pin and frame apply to the full inventory. Class membership is an upstream evidence-bound input; this package neither verifies the external evidence's authorship nor discovers a class from a glyph name or height.

Classes are opaque names. Flat cap, round cap overshoot, flat baseline and round baseline overshoot remain separate when supplied separately. No default metric coordinates, UPM, cap ratios, glyph whitelist or nearest-height assignment exist.

Each edge's median contributes one observation to its class. Guide position is the median of those edge medians. Both each edge's sample range and the class range of edge medians must be at most the spread limit. All supplied edges in the class participate; a rejected edge does not silently disappear into a cleaner guide. Multiple edges per glyph receive multiple edge-median contributions, but cannot manufacture independent glyph support. Missing classes and classes with fewer than two distinct source glyphs abstain. That minimum is a CONVENTION for observing between-glyph spread, not a calibrated confidence threshold. Zero spread is not a confidence or uncertainty estimate.

Image limits use one source pixel converted with the recorded frame scale. Vector limits must be separately supplied as source-derived or declared with a derivation description; declared values remain labelled `declared, not measured`. Do not pass an image limit for a vector source. No MAD or invented fallback limit is used.

Nodes require unique identities, glyph identity, finite y, the same scope and a source edge identity. Unknown memberships, scope/frame/glyph mismatches and duplicate node identities abstain. Signed offset is `node_y - guide_y`. Missing offsets remain absent, never zero. Per-class summaries report signed median, signed p90, signed maximum, absolute maximum and class-known abstentions. Unclassified abstentions remain individual rows and are not assigned to an invented class. p90 is the nearest-rank CONVENTION `ceil(0.9*n)`. There is no pass threshold or composite score.

## Build and tests

Run `cargo test`, `cargo build --example capture_audit_guides`, and `python3 -m unittest discover -s tests -p 'test_*.py' -v` from the package directory. Rust tests cover independent support, missing evidence, spread, scope, identity, overshoot separation, offsets, summaries, deterministic ordering, nonfinite inputs and read-only behavior. Python tests exercise capture-audit frame validation, integer rounding, unknown membership rejection and the compiled Rust sidecar.

The tests check library behavior and sidecar mechanics. They do not establish semantic source-class validity.

## Capture-audit compatibility

`tools/capture_audit_sidecar.py` reads `kni.capture-audit.v1` and an independently prepared binding JSON, verifies the audit SHA256 and exact frame, and invokes the compiled `capture_audit_guides` example. It uses the audit's float rings plus recorded translation to replay on-curve integer y. CONVENTION: Rust nearest-integer ties away from zero. It reads but never rewrites the audit or charstring. This sidecar does not decode arbitrary CFF or claim source lineage that the audit lacks. Without supplied memberships all nodes abstain.

Binding JSON fields: `scope` (font/master/style/frame), `audit_frame` (the exact frame object), `audit_sha256`, `source_pin`, `glyph`, `classes`, `edges` (edge_id/glyph/class/membership_evidence/source_y), and `node_memberships` (map of `ring_index:node_index` to source edge id). Node index zero is the start; subsequent indices are span endpoints, including an explicit closing endpoint if present. This address convention is not a distinct-node economy count. Coordinates and source_y must already share the audit's final translated font-unit frame.

Invoke `python3 tools/capture_audit_sidecar.py AUDIT BINDINGS target/debug/examples/capture_audit_guides`. Output goes to stdout, not back into the audit. The raw Rust example's tab stream format is documented by its match arms and is intended for the preparing adapter.

## Boundaries

Automatic semantic class derivation, design-intent declarations and production font policy are outside this module. Source-edge authenticity and semantic membership validation are upstream responsibilities. The library and sidecar provide annotations only; they cannot change capture, fitted geometry or font output.
