//! Fixture-based gate test: a well-formed minimal OTF passes; flipping any
//! single byte - payload, directory, head magic, or head adjustment - is
//! rejected with typed findings.
use kni_metrics::otf_self_parse::{verify, IntegrityFinding};

fn codes(findings: &[IntegrityFinding]) -> Vec<&'static str> {
    findings.iter().map(|f| f.code).collect()
}

/// Padded-word checksum, same arithmetic the gate walks (OpenType spec).
fn padded_sum(bytes: &[u8]) -> u32 {
    let mut sum = 0u32;
    for chunk in bytes.chunks(4) {
        let mut word = [0u8; 4];
        word[..chunk.len()].copy_from_slice(chunk);
        sum = sum.wrapping_add(u32::from_be_bytes(word));
    }
    sum
}

/// Minimal two-table OTF ('CFF ' + 'head'), assembled by the binary format
/// rules: 4-byte aligned tables, directory checksums, head adjustment set
/// so the whole font sums to 0xB1B0AFBA.
fn fixture_otf() -> Vec<u8> {
    let cff: Vec<u8> = b"\x01\x00\x04\x04KNI-SELF-PARSE-FIXTURE".to_vec();
    let mut head = vec![0u8; 54];
    head[0..4].copy_from_slice(&0x0001_0000u32.to_be_bytes()); // version 1.0
    head[12..16].copy_from_slice(&0x5F0F_3CF5u32.to_be_bytes()); // magic
    let mut out = Vec::new();
    out.extend_from_slice(b"OTTO"); // scaler: CFF-flavoured sfnt
    out.extend_from_slice(&2u16.to_be_bytes()); // numTables
    out.extend_from_slice(&32u16.to_be_bytes()); // searchRange = 16 * 2
    out.extend_from_slice(&1u16.to_be_bytes()); // entrySelector = log2(2)
    out.extend_from_slice(&0u16.to_be_bytes()); // rangeShift = 32 - 32
    let dir_end = 12 + 2 * 16;
    let cff_off = dir_end;
    let head_off = cff_off + (cff.len() + 3) / 4 * 4;
    for (tag, body, offset) in [(*b"CFF ", &cff, cff_off), (*b"head", &head, head_off)] {
        out.extend_from_slice(&tag);
        out.extend_from_slice(&padded_sum(body).to_be_bytes());
        out.extend_from_slice(&(offset as u32).to_be_bytes());
        out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    }
    out.extend_from_slice(&cff);
    out.resize(head_off, 0);
    out.extend_from_slice(&head);
    let adjustment = 0xB1B0_AFBAu32.wrapping_sub(padded_sum(&out));
    let adjustment_at = head_off + 8;
    out[adjustment_at..adjustment_at + 4].copy_from_slice(&adjustment.to_be_bytes());
    out
}

/// The fixture's directory is the source of truth for where 'head' lives:
/// record index 1, offset field at record start + 8.
fn head_offset(font: &[u8]) -> usize {
    u32::from_be_bytes([font[36], font[37], font[38], font[39]]) as usize
}

#[test]
fn fixture_otf_passes() {
    let font = fixture_otf();
    let report = verify(&font).unwrap_or_else(|findings| panic!("fixture rejected: {findings:?}"));
    assert_eq!(report.scaler, u32::from_be_bytes(*b"OTTO"));
    let tags: Vec<[u8; 4]> = report.tables.iter().map(|t| t.tag).collect();
    assert_eq!(tags, [*b"CFF ", *b"head"]);
}

#[test]
fn single_byte_corruption_in_table_payload_is_rejected() {
    let mut font = fixture_otf();
    let payload_byte = 12 + 2 * 16; // first byte of the 'CFF ' table
    font[payload_byte] ^= 0x01;
    let findings = verify(&font).expect_err("corrupted payload must be rejected");
    let codes = codes(&findings);
    assert!(codes.contains(&"OTFSP-TABLE-CHECKSUM"), "{codes:?}");
    assert!(codes.contains(&"OTFSP-GLOBAL-CHECKSUM"), "{codes:?}");
}

#[test]
fn single_byte_corruption_in_directory_is_rejected() {
    let mut font = fixture_otf();
    font[12 + 12] ^= 0x10; // one byte of the first record's length field
    assert!(verify(&font).is_err(), "corrupted directory must be rejected");
}

#[test]
fn single_byte_corruption_of_head_magic_is_rejected() {
    let mut font = fixture_otf();
    let head_off = head_offset(&font);
    font[head_off + 12] ^= 0xFF; // head.magicNumber first byte
    let findings = verify(&font).expect_err("corrupted head magic must be rejected");
    assert!(codes(&findings).contains(&"OTFSP-HEAD-MAGIC"), "{findings:?}");
}

#[test]
fn single_byte_corruption_of_head_adjustment_is_rejected() {
    let mut font = fixture_otf();
    let head_off = head_offset(&font);
    font[head_off + 8] ^= 0x01; // checkSumAdjustment: head's own sum zeroes it,
    // so only the whole-font sum can catch this - and must.
    let findings = verify(&font).expect_err("corrupted adjustment must be rejected");
    let codes = codes(&findings);
    assert_eq!(codes, ["OTFSP-GLOBAL-CHECKSUM"], "{codes:?}");
}

#[test]
fn truncated_file_is_rejected() {
    let findings = verify(&fixture_otf()[..40]).expect_err("truncated file must be rejected");
    assert!(codes(&findings).contains(&"OTFSP-DIRECTORY-OVERFLOW"), "{findings:?}");
    assert_eq!(verify(&[0u8; 4]).unwrap_err()[0].code, "OTFSP-TRUNCATED-HEADER");
}

#[test]
fn garbage_scaler_is_rejected() {
    let mut font = fixture_otf();
    font[0..4].copy_from_slice(b"XXXX");
    let findings = verify(&font).expect_err("unknown scaler must be rejected");
    assert!(codes(&findings).contains(&"OTFSP-UNSUPPORTED-SCALER"), "{findings:?}");
}
