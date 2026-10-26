//! Equal-input kern output: the proposal table on the shared fixtures is
//! byte-stable. The pin file holds the table SHA-256.
//! If a change alters a derivation on purpose, the new pin and a label naming
//! the changed derivation go in the same change.

use kni_metrics::gen;
use kni_metrics::kern_proposal::build_proposal;

fn load_inputs() -> gen::GenerationInputs {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
    let rd = |n: &str| std::fs::read_to_string(format!("{dir}/{n}")).unwrap();
    let (glyphs, knowledge) = gen::parse_classes(&rd("classes.tsv")).unwrap();
    gen::GenerationInputs {
        glyphs,
        knowledge,
        targets: gen::parse_targets(&rd("targets.tsv")).unwrap(),
        walls: gen::parse_walls(&rd("walls.tsv")).unwrap(),
        existing: gen::existing_from_pairs(gen::parse_pairs(&rd("existing.tsv")).unwrap()).unwrap(),
        restore: gen::parse_pairs(&rd("restore.tsv")).unwrap(),
    }
}

#[test]
fn proposal_table_matches_the_pinned_digest() {
    let pin = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/kern-proposal.sha256")).unwrap();
    let pin = pin.trim();
    assert!(pin.len() == 64 && pin.chars().all(|c| c.is_ascii_hexdigit()), "pin must be a full SHA-256 in hex");
    let got = build_proposal(&load_inputs(), None).unwrap().tsv_sha256();
    assert_eq!(got, pin, "table digest differs from the pin");
}

#[test]
fn proposal_table_is_identical_across_runs() {
    let a = build_proposal(&load_inputs(), None).unwrap().tsv();
    let b = build_proposal(&load_inputs(), None).unwrap().tsv();
    assert_eq!(a, b);
}
