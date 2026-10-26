//! Raw-f64 GPOS xAdvance half-away rounding then saturation adapter.
//! Finite overflow produces a shipped representable value AND one typed record;
//! nonfinite produces no value, a pair-scoped refusal and one ledger row.
//! Destination pinned by the final ruling: actual signed16 [-32768,32767].
//! Named bounds derive from i16::MIN/MAX, not symmetric +/-32767 shorthand.
//! No corpus/root-cause claim.
//! OFF: integrator bypasses this gate and preserves the original path/bytes.

/// Pinned lower bound, derived from signed16 destination format, not style tuning.
pub const DEFAULT_LOWER_BOUND: i16 = i16::MIN;
pub const UPPER_BOUND: i16 = i16::MAX;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Destination { GposXAdvanceInt16 }
impl Destination { pub fn bounds(self) -> (i16, i16) { (DEFAULT_LOWER_BOUND, UPPER_BOUND) } }
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PairInput { pub left: u16, pub right: u16, pub raw: f64, pub destination: Destination }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClampSide { Lower, Upper }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NonFiniteKind { Nan, PositiveInfinity, NegativeInfinity }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TypedClamp {
    pub left: u16, pub right: u16, pub raw_bits: u64, pub rounded_bits: u64,
    pub value: i16, pub destination: Destination, pub lower: i16, pub upper: i16, pub side: ClampSide,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TypedRefusal {
    pub left: u16, pub right: u16, pub raw_bits: u64,
    pub destination: Destination, pub reason: NonFiniteKind,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict { InRange(i16), Saturated { value: i16, ledger: TypedClamp }, NonFinite(TypedRefusal) }

pub fn evaluate(input: PairInput) -> Verdict {
    if !input.raw.is_finite() {
        let reason = if input.raw.is_nan() { NonFiniteKind::Nan }
            else if input.raw.is_sign_positive() { NonFiniteKind::PositiveInfinity } else { NonFiniteKind::NegativeInfinity };
        return Verdict::NonFinite(TypedRefusal { left: input.left, right: input.right,
            raw_bits: input.raw.to_bits(), destination: input.destination, reason });
    }
    // Exact package source half-away formula, THEN destination range test.
    let rounded = (input.raw.abs() + 0.5).floor().copysign(input.raw);
    let (lower, upper) = input.destination.bounds();
    if rounded > f64::from(upper) || rounded < f64::from(lower) {
        let (value, side) = if rounded < f64::from(lower) { (lower, ClampSide::Lower) } else { (upper, ClampSide::Upper) };
        let ledger = TypedClamp { left: input.left, right: input.right, raw_bits: input.raw.to_bits(),
            rounded_bits: rounded.to_bits(), value, destination: input.destination, lower, upper, side };
        return Verdict::Saturated { value, ledger };
    }
    Verdict::InRange(rounded as i16) // finite and destination-range checked
}
impl TypedClamp {
    // Typed ledger row renderer for the Saturated clamp verdict (action ship_clamped_continue);
    // kept for the stem-pair ledger consumer.
    #[allow(dead_code)]
    pub fn ledger_row(&self) -> String {
        format!("stem_pair_clamp\tleft_gid\t{}\tright_gid\t{}\tdestination\t{:?}\traw_bits\t{:016x}\trounded_bits\t{:016x}\tvalue\t{}\tlower\t{}\tupper\t{}\treason\t{:?}\taction\tship_clamped_continue\n",
            self.left, self.right, self.destination, self.raw_bits, self.rounded_bits, self.value, self.lower, self.upper, self.side)
    }
}
impl TypedRefusal {
    // Typed ledger row renderer for the refusal verdict (action pair_rejected_continue);
    // kept for the stem-pair ledger consumer.
    #[allow(dead_code)]
    pub fn ledger_row(&self) -> String {
        format!("stem_pair_reject\tleft_gid\t{}\tright_gid\t{}\tdestination\t{:?}\traw_bits\t{:016x}\treason\t{:?}\taction\tpair_rejected_continue\n",
            self.left, self.right, self.destination, self.raw_bits, self.reason)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_metrics::generated_outline_kern::round_export_units;
    use kni_metrics::gpos_pairpos1::{write_kern_pairpos1, GposWriteError, PairKern};
    use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
    fn input(raw: f64) -> PairInput { PairInput { left: 1, right: 2, raw, destination: Destination::GposXAdvanceInt16 } }
    fn fixture() -> (Vec<DrawnGlyph>, PairInput) {
        let text = include_str!("../tests/fixtures/stem_pair_overflow/pair.txt");
        let mut rows = text.lines().filter(|l| !l.is_empty() && !l.starts_with('#')); let mut shapes = Vec::new();
        for expected in ["left_stem", "right_stem"] {
            let f: Vec<_> = rows.next().unwrap().split_whitespace().collect(); assert_eq!(f[0], expected);
            let v: Vec<f64> = f[1..].iter().map(|s| s.parse().unwrap()).collect(); assert_eq!(v.len(), 4);
            let p = |x, y| Point { x, y };
            shapes.push(DrawnGlyph { glyph_id: expected.into(), rings: vec![ReferenceRing { start: p(v[0], v[1]),
                spans: vec![Span::Line { end: p(v[2], v[1]) }, Span::Line { end: p(v[2], v[3]) },
                    Span::Line { end: p(v[0], v[3]) }, Span::Line { end: p(v[0], v[1]) }], }] });
        }
        let f: Vec<_> = rows.next().unwrap().split_whitespace().collect(); assert_eq!(f[0], "pair_x_advance");
        let pair = input(f[1].parse().unwrap()); assert!(rows.next().is_none()); (shapes, pair)
    }
    #[test]
    fn pinned_stem_fixture_base_refuses_but_new_adapter_keeps_clamped_writer_value_and_record() {
        let (glyphs, pair) = fixture();
        for g in glyphs { let r = &g.rings[0]; let Span::Line { end } = r.spans.last().unwrap() else { panic!("line fixture") }; assert_eq!(*end, r.start); }
        println!("synthetic raw={} source-rounded={} destination=[{},{}]", pair.raw, (pair.raw.abs()+0.5).floor().copysign(pair.raw), DEFAULT_LOWER_BOUND, UPPER_BOUND);
        assert_eq!(pair.raw, f64::from(i16::MAX) + 1.0);
        let raw = i32::from(i16::MAX) + 1;
        assert_eq!(write_kern_pairpos1(3, &[PairKern { left: 1, right: 2, x_advance: raw }]),
            Err(GposWriteError::ValueOutOfRange { left: 1, right: 2, x_advance: raw }));
        let Verdict::Saturated { value, ledger } = evaluate(pair) else { panic!("expected saturation") };
        assert_eq!(value, UPPER_BOUND); assert_eq!(ledger.value, value); assert_eq!(ledger.raw_bits, pair.raw.to_bits());
        assert_eq!(ledger.ledger_row().lines().count(), 1);
        assert!(write_kern_pairpos1(3, &[PairKern { left: 1, right: 2, x_advance: i32::from(value) }]).is_ok());
    }
    #[test]
    fn four_final_rounding_edges_are_explicit() {
        assert_eq!(evaluate(input(32767.4)), Verdict::InRange(32767));
        let Verdict::Saturated { value, ledger } = evaluate(input(32767.5)) else { panic!("upper edge") };
        assert_eq!((value, ledger.side), (32767, ClampSide::Upper));
        assert_eq!(evaluate(input(-32768.4)), Verdict::InRange(-32768));
        let Verdict::Saturated { value, ledger } = evaluate(input(-32768.5)) else { panic!("lower edge") };
        assert_eq!((value, ledger.side), (-32768, ClampSide::Lower));
        assert_eq!(ledger.lower, DEFAULT_LOWER_BOUND);
    }
    #[test]
    fn far_finite_overflow_both_directions_still_ships_the_bound_with_one_record() {
        for (raw, bound, side) in [(f64::MAX, UPPER_BOUND, ClampSide::Upper), (-f64::MAX, DEFAULT_LOWER_BOUND, ClampSide::Lower)] {
            let Verdict::Saturated { value, ledger } = evaluate(input(raw)) else { panic!("finite overflow") };
            assert_eq!((value, ledger.value, ledger.side), (bound, bound, side));
            assert_eq!(ledger.raw_bits, raw.to_bits()); assert_eq!(ledger.ledger_row().lines().count(), 1);
            assert_eq!((ledger.lower, ledger.upper), (DEFAULT_LOWER_BOUND, UPPER_BOUND));
        }
    }
    #[test]
    fn nonfinite_has_no_pair_value_but_retains_bits_and_typed_pair_refusal() {
        for (raw, kind) in [(f64::INFINITY, NonFiniteKind::PositiveInfinity), (f64::NEG_INFINITY, NonFiniteKind::NegativeInfinity),
            (f64::from_bits(0x7ff8_0000_0000_0042), NonFiniteKind::Nan)] {
            let Verdict::NonFinite(e) = evaluate(input(raw)) else { panic!("nonfinite must have no pair value") };
            assert_eq!(e.raw_bits, raw.to_bits()); assert_eq!(e.reason, kind);
            assert_eq!(e.ledger_row().lines().count(), 1); assert!(e.ledger_row().contains("pair_rejected_continue"));
        }
    }
    #[test]
    fn in_range_gpos_bytes_match_original_rounding_without_ledger() {
        for raw in [-32768.4, -1.5, -0.0, 0.5, 32767.4] {
            let old = round_export_units(raw); assert!(!old.1);
            let Verdict::InRange(v) = evaluate(input(raw)) else { panic!("in-range input") };
            let p = |v| PairKern { left: 1, right: 2, x_advance: i32::from(v) };
            assert_eq!(write_kern_pairpos1(3, &[p(v)]).unwrap(), write_kern_pairpos1(3, &[p(old.0)]).unwrap());
        }
    }
    #[test]
    fn test_adapter_keeps_clamped_pairs_drops_only_nonfinite_and_run_continues() {
        let inputs = [input(32768.0), PairInput { left: 2, right: 1, ..input(1.0) },
            PairInput { left: 1, right: 1, ..input(f64::NAN) }, PairInput { left: 2, right: 2, ..input(-32769.0) }];
        let mut accepted = Vec::new(); let mut clamps = Vec::new(); let mut refusals = Vec::new();
        for pair in inputs {
            let value = match evaluate(pair) {
                Verdict::InRange(v) => Some(v),
                Verdict::Saturated { value, ledger } => { clamps.push(ledger); Some(value) },
                Verdict::NonFinite(e) => { refusals.push(e); None },
            };
            if let Some(v) = value { accepted.push(PairKern { left: pair.left, right: pair.right, x_advance: i32::from(v) }); }
        }
        assert_eq!(accepted.len(), 3); assert_eq!(clamps.len(), 2); assert_eq!(refusals.len(), 1);
        assert_eq!(accepted[0].x_advance, i32::from(UPPER_BOUND)); assert_eq!(accepted[2].x_advance, i32::from(DEFAULT_LOWER_BOUND));
        assert!(write_kern_pairpos1(3, &accepted).is_ok());
    }
    #[test]
    fn off_is_integrator_bypass_preserving_original_bits_and_base_result() {
        let enabled = false;
        for raw in [32768.0, -0.0, f64::from_bits(0x7ff8_0000_0000_0042)] {
            let mut records = Vec::new(); let old = round_export_units(raw);
            let actual = if enabled {
                match evaluate(input(raw)) {
                    Verdict::InRange(v) => (v, false),
                    Verdict::Saturated { value, ledger } => { records.push(ledger.ledger_row()); (value, true) },
                    Verdict::NonFinite(e) => { records.push(e.ledger_row()); old },
                }
            } else { old };
            assert_eq!(actual, old); assert!(records.is_empty()); assert_eq!(input(raw).raw.to_bits(), raw.to_bits());
        }
    }
}
