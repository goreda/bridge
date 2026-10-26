//! Pure decision for the double-encode determinism check (job 4.1).
//!
//! The prepared baseline is encoded twice. If the two byte streams differ
//! the encoder was not deterministic for this input. Per the brief the
//! FIRST encode ships and a typed warning (`encode_nondeterministic\ttrue`)
//! is appended to the receipt; the run is no longer refused.
//!
//! CONVENTION: on disagreement the first encode is the shipped artifact.
//! Derivation: the first encode is the byte stream every downstream
//! consumer already saw (guard receipt sha, IoU readback, final bundle),
//! so shipping it keeps the shipped bytes consistent with the receipts
//! that reference them; refusing would violate the always-output rule.

/// Outcome of comparing two encodes of the same prepared baseline.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeterminismDecision {
    /// Both encodes produced identical bytes; nothing to warn about.
    Deterministic,
    /// Encodes differ; the first encode ships and the warning fires.
    ShipFirstEncodeWithWarning,
}

/// Stable typed warning code for the nondeterministic-encode event.
pub const WARNING_CODE: &str = "encode_nondeterministic";

/// Compare two encodes of the same prepared baseline. Pure: no I/O, no
/// state; identical inputs always yield the identical decision.
pub fn decide(first_encode: &[u8], second_encode: &[u8]) -> DeterminismDecision {
    if first_encode == second_encode {
        DeterminismDecision::Deterministic
    } else {
        DeterminismDecision::ShipFirstEncodeWithWarning
    }
}

/// Receipt line for the decision. `None` in the deterministic case: no
/// warning is emitted when the encodes agree.
pub fn warning_line(decision: DeterminismDecision) -> Option<String> {
    match decision {
        DeterminismDecision::Deterministic => None,
        DeterminismDecision::ShipFirstEncodeWithWarning => Some(format!(
            "{WARNING_CODE}\ttrue\tpolicy\tship_first_encode\n"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_bytes_are_deterministic() {
        let a = b"OTTO\x00\x01\x02\x03".to_vec();
        assert_eq!(decide(&a, &a), DeterminismDecision::Deterministic);
        assert!(warning_line(decide(&a, &a)).is_none());
    }

    #[test]
    fn different_bytes_ship_first_and_warn() {
        let first = b"OTTO first encode bytes";
        let second = b"OTTO second encode bytes!";
        let d = decide(first, second);
        assert_eq!(d, DeterminismDecision::ShipFirstEncodeWithWarning);
        let line = warning_line(d).expect("warning line present");
        assert!(line.contains("encode_nondeterministic\ttrue"));
        assert!(line.contains("policy\tship_first_encode"));
    }

    #[test]
    fn single_byte_flip_is_nondeterministic() {
        let first = [0u8; 64];
        let mut second = first;
        second[17] = 1;
        assert_eq!(decide(&first, &second), DeterminismDecision::ShipFirstEncodeWithWarning);
    }

    #[test]
    fn length_difference_alone_is_nondeterministic() {
        assert_eq!(
            decide(&[1, 2, 3], &[1, 2, 3, 4]),
            DeterminismDecision::ShipFirstEncodeWithWarning
        );
    }

    #[test]
    fn empty_encodes_are_deterministic() {
        assert_eq!(decide(&[], &[]), DeterminismDecision::Deterministic);
    }
}
