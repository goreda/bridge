# Proposal: per-glyph segment metrics in the receipt

Status: proposed. Checker grammar and drift tracking are landed
(SCHEMA conc/ledger-schema/9, head registered as pending); the emitter
below is a draft for the architect, all execution NOT_RUN. Until the
emitter lands, receipt_head_drift.py tracks the head in
PENDING_EMITTER_HEADS; landing the emitter must remove that entry in
the same diff.

Goal: curve quality visible in every export. One persistent receipt row
per glyph carries the segment-type mix (line vs cubic), the join
quality (G1-smooth vs corner), and compactness (chord length per node),
so a regression in any of them diffs the receipt.

## Row format

    glyph_segments <TAB> subject <TAB> line <n> <TAB> cubic <n> <TAB>
    cubic_pct <f> <TAB> g1 <n> <TAB> corner <n> <TAB>
    corner_per_node <f> <TAB> chord_len <f> <TAB> len_per_node <f>

18 fields, registered arity (18,), full field grammar in
RECEIPT_KV_GRAMMAR. Semantics, all computed on the shipped drawing
(`d.rings`, the same rings the `glyph` row counts):

- `line`, `cubic`: span counts by variant. line + cubic == the `nodes`
  value of the glyph row.
- `cubic_pct`: 100 * cubic / nodes, `{:.6}`.
- `g1`, `corner`: join classes over every ring join (a closed ring of n
  spans has n joins; g1 + corner == nodes). G1 uses the exact integer
  tangent test already proven in economy_eval (`tangents` + `smooth`:
  first-nonzero in/out tangents, integer cross == 0 and dot > 0). A
  join whose tangent degenerates counts as corner.
- `corner_per_node`: corner / nodes, `{:.6}`.
- `chord_len`: sum of per-span chord lengths (end - start, euclidean,
  binary64, spans walked in ring order), `{:.6}`. Chord, not arc
  length: deterministic, no quadrature. The doc names the measure so a
  later arc-length swap is an explicit schema change.
- `len_per_node`: chord_len / nodes, `{:.6}`.
- Empty drawing (nodes == 0, e.g. space): no row is emitted; the glyph
  row already carries nodes 0. This keeps every emitted ratio finite.

The values are derived, but so are final_area and the pct fields
elsewhere: the receipt is the persistent quality record, and per-glyph
rows let a diff name the exact glyph that regressed.

## Emitter draft (architect proposal, NOT_RUN)

Insertion point: pipeline/src/main.rs, immediately after the `glyph`
row push_str (the same scope that holds `d`, `g.name`). Geometry
helpers mirror the private economy_eval tests; the draft asks for them
as small pub items in kni_core (architect merge point) so main.rs does
not duplicate the tangent rule:

```rust
// kni_core::economy_eval (make pub, bodies unchanged):
//   pub fn ring_join_tangents(r: &ReferenceRing, k: usize)
//       -> Option<((i128, i128), (i128, i128))>   // today's tangents()
//   pub fn join_is_smooth(a: (i128, i128), b: (i128, i128)) -> bool
//                                                    // today's smooth()

// pipeline/src/main.rs, after the glyph receipt row:
{
    use kni_core::reference_slice::Span;
    let (mut n_line, mut n_cubic) = (0usize, 0usize);
    let (mut n_g1, mut n_corner) = (0usize, 0usize);
    let mut chord = 0.0f64;
    for ring in &d.rings {
        let mut cur = ring.start;
        for span in &ring.spans {
            let end = match span {
                Span::Line { end } => { n_line += 1; *end }
                Span::Cubic { end, .. } => { n_cubic += 1; *end }
            };
            chord += ((end.x - cur.x).powi(2) + (end.y - cur.y).powi(2)).sqrt();
            cur = end;
        }
        for k in 0..ring.spans.len() {
            match kni_core::economy_eval::ring_join_tangents(ring, k) {
                Some((a, b)) if kni_core::economy_eval::join_is_smooth(a, b)
                    => n_g1 += 1,
                _ => n_corner += 1,
            }
        }
    }
    let nodes = n_line + n_cubic;
    if nodes > 0 {
        receipt.push_str(&format!(
            "glyph_segments\t{}\tline\t{}\tcubic\t{}\tcubic_pct\t{:.6}\tg1\t{}\tcorner\t{}\tcorner_per_node\t{:.6}\tchord_len\t{:.6}\tlen_per_node\t{:.6}\n",
            g.name, n_line, n_cubic,
            100.0 * n_cubic as f64 / nodes as f64,
            n_g1, n_corner,
            n_corner as f64 / nodes as f64,
            chord, chord / nodes as f64));
    }
}
```

Determinism: span order is ring order, summation order fixed, integer
join test, `{:.6}` formatting; same input gives byte-identical rows.

Landing checklist (one diff): the two pub renames in economy_eval, the
main.rs block above, remove glyph_segments from PENDING_EMITTER_HEADS,
then receipt_head_drift.py and ledger_mutation_test.py must pass.
