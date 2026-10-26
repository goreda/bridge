//! Pixel-source .notdef evidence producer. No source-font metadata is consumed.
//!
//! Claim-only: bounded reads, byte pins and evidence packaging. The producer
//! never decodes images, never counts form frequency and never compares gray
//! pixels. The validator owns the shared types and the `pixel_form_sha256`
//! definition and verifies every claim (form hash, all-255 blank, frequency).
use kni_pipeline::notdef_types::{BadNotdef, PixelContext, PixelNotdefKind};
use kni_core::{cff_reader::sha256_hex, jpeg_source::Limits};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Component, Path},
};
// pre-staged, unwired: claim-only tile row; the validator verifies decoded pixels against the claimed role (module header)
#[allow(dead_code)]
pub struct Tile<'a> {
    pub cp: u32,
    pub path: &'a str,
    pub bytes: &'a [u8],
    /// Claimed candidate role; None is an ordinary capture row. A role is a
    /// claim only: the validator verifies decoded pixels against it.
    pub role: Option<PixelNotdefKind>,
}
// pre-staged, unwired: claim package for the validator; pixel_form_sha256 is emitted verbatim, never computed or verified here (field doc)
#[allow(dead_code)]
pub struct Request<'a> {
    pub context: &'a PixelContext,
    pub cohort: &'a str,
    pub request_source: &'a str,
    pub capture_record: &'a [u8],
    pub capture_sha256: &'a str,
    /// Removed from the pixel route: refused with Grammar when set.
    pub space_evidence_sha256: Option<&'a str>,
    /// Winning-form identity claim, defined by validator `pixel_form_sha256`.
    /// Shape-checked as 64 lowercase hex and emitted verbatim; never computed
    /// or verified here.
    pub pixel_form_sha256: &'a str,
    pub tiles: &'a [Tile<'a>],
    pub limits: Limits,
}
// pre-staged, unwired: evidence + evidence pin container returned by produce()
#[allow(dead_code)]
pub struct Produced {
    pub evidence: String,
    pub evidence_sha: String,
}
#[derive(Debug, PartialEq, Eq)]
// pre-staged, unwired: typed refusal enum for the producer route (From<BadNotdef> below)
#[allow(dead_code)]
pub enum ProducerError {
    MissingPixelEvidence,
    AmbiguousPixelCandidate,
    InvalidSourceImage,
    Invalid(BadNotdef),
}
impl From<BadNotdef> for ProducerError {
    fn from(e: BadNotdef) -> Self {
        Self::Invalid(e)
    }
}
// pre-staged, unwired: shape-check helper: 64 lowercase hex, per Request::pixel_form_sha256's doc
#[allow(dead_code)]
fn sha(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}
// pre-staged, unwired: receipt-field grammar guard: nonempty, no tab/newline/CR/NUL
#[allow(dead_code)]
fn field(s: &str) -> bool {
    !s.is_empty() && !s.chars().any(|c| matches!(c, '\t' | '\n' | '\r' | '\0'))
}
// pre-staged, unwired: relative source-path grammar: field() plus no whitespace, not absolute, normal components only
#[allow(dead_code)]
fn path(s: &str) -> bool {
    field(s)
        && !s.chars().any(char::is_whitespace)
        && !Path::new(s).is_absolute()
        && Path::new(s)
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
}
// pre-staged, unwired: producer entry: claim-only evidence packaging; the validator verifies every claim (module header)
#[allow(dead_code)]
pub fn produce(r: &Request<'_>) -> Result<Produced, ProducerError> {
    let c = r.context;
    if ![
        c.style.as_str(),
        c.frame.as_str(),
        r.cohort,
        r.request_source,
    ]
    .iter()
    .all(|s| field(s))
        || !c.units_per_px.is_finite()
        || c.units_per_px <= 0.0
        || c.ink_model != "decoded-gray-all-255-no-transform-v1"
        || !sha(&c.source_sha256)
    {
        return Err(BadNotdef::ContextMismatch.into());
    }
    if !sha(r.capture_sha256) || sha256_hex(r.capture_record) != r.capture_sha256 {
        return Err(BadNotdef::ShaMismatch.into());
    }
    if !sha(r.pixel_form_sha256) {
        return Err(BadNotdef::Grammar.into());
    }
    if r.tiles.len() > 65535 || r.capture_record.len() > r.limits.max_input_bytes {
        return Err(BadNotdef::ResourceLimit.into());
    }
    let held = r
        .tiles
        .iter()
        .try_fold(r.capture_record.len(), |n, t| {
            n.checked_add(t.bytes.len())
                .and_then(|n| n.checked_add(t.path.len().saturating_add(2048)))
        })
        .ok_or(BadNotdef::ResourceLimit)?;
    if held > r.limits.max_working_bytes {
        return Err(BadNotdef::ResourceLimit.into());
    }
    let mut cps = BTreeSet::new();
    let mut paths = BTreeMap::new();
    let mut rows = Vec::new();
    let mut claimed = Vec::new();
    for t in r.tiles {
        kni_pipeline::notdef_types::validate_codepoint(t.cp)?;
        if !cps.insert(t.cp) {
            return Err(BadNotdef::Duplicate.into());
        }
        if !path(t.path) {
            return Err(BadNotdef::ContextMismatch.into());
        }
        if t.bytes.is_empty() || t.bytes.len() > r.limits.max_input_bytes {
            return Err(ProducerError::InvalidSourceImage);
        }
        let pin = sha256_hex(t.bytes);
        if paths
            .insert(t.path, pin.clone())
            .map_or(false, |old| old != pin)
        {
            return Err(BadNotdef::AuditMismatch.into());
        }
        if t.role.is_some() {
            claimed.push(rows.len());
        }
        rows.push((t.cp, t.path, pin, t.role));
    }
    // A candidate needs a repeated claim: a single claimed form is none.
    if claimed.len() < 2 {
        return Err(ProducerError::MissingPixelEvidence);
    }
    let kind = rows[claimed[0]].3.unwrap();
    if claimed.iter().any(|&i| rows[i].3 != Some(kind)) {
        return Err(ProducerError::AmbiguousPixelCandidate);
    }
    // Selected source resolves by the context byte pin, not by order.
    let selected = claimed
        .iter()
        .copied()
        .find(|&i| rows[i].2 == c.source_sha256)
        .ok_or(BadNotdef::ShaMismatch)?;
    // Space binding is gone from the pixel route: the blank gid0 advance is
    // the advance of the font's widest character, bound later in assembly.
    if r.space_evidence_sha256.is_some() {
        return Err(BadNotdef::Grammar.into());
    }
    let kindstr = if kind == PixelNotdefKind::BlankCell {
        "blank-cell"
    } else {
        "repeated-form"
    };
    let mut evidence=format!("kni-pixel-notdef-evidence\tv3\nkind\t{kindstr}\nstyle\t{}\nframe\t{}\nscale\t{}\nink_model\t{}\ncapture_sha256\t{}\npixel_form_sha256\t{}\nselected\t{}\t{}\n",c.style,c.frame,c.units_per_px,c.ink_model,r.capture_sha256,r.pixel_form_sha256,rows[selected].1,rows[selected].2);
    // Extraction manifest (old codebase behavior): only the winner group is
    // listed. These CPs are not written into the font as characters; their
    // shared form is emitted only at gid0 as .notdef.
    for &i in &claimed {
        let (cp, p, pin, _) = &rows[i];
        evidence.push_str(&format!("pixel_source\t0x{cp:x}\t{kindstr}\t{p}\t{pin}\n"));
    }
    let evidence_sha = sha256_hex(evidence.as_bytes());
    Ok(Produced {
        evidence,
        evidence_sha,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    fn context(pin: String) -> PixelContext {
        PixelContext {
            style: "T/Regular".into(),
            frame: "frame1".into(),
            units_per_px: 2.4377,
            source_sha256: pin,
            ink_model: "decoded-gray-all-255-no-transform-v1".into(),
        }
    }
    fn req<'a>(c: &'a PixelContext, t: &'a [Tile<'a>], cap: &'a str, form: &'a str) -> Request<'a> {
        Request {
            context: c,
            cohort: "T/Regular",
            request_source: "synthetic-pixel-capture",
            capture_record: b"capture",
            capture_sha256: cap,
            space_evidence_sha256: None,
            pixel_form_sha256: form,
            tiles: t,
            limits: Limits {
                max_input_bytes: 1 << 20,
                max_pixels: 1024,
                max_working_bytes: 1 << 24,
            },
        }
    }
    fn blank() -> Vec<u8> {
        vec![
            137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 8, 0, 0, 0, 8,
            8, 0, 0, 0, 0, 225, 100, 225, 87, 0, 0, 0, 14, 73, 68, 65, 84, 120, 156, 99, 248, 15,
            5, 12, 148, 49, 0, 247, 192, 63, 193, 178, 52, 65, 187, 0, 0, 0, 0, 73, 69, 78, 68,
            174, 66, 96, 130,
        ]
    }
    fn form() -> String {
        "f".repeat(64)
    }
    #[test]
    fn repeated_claim_emits_v3_claims_and_keeps_all_cps() {
        let b = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let c = context(sha256_hex(b));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: b,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 66,
                path: "b.png",
                bytes: b,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 67,
                path: "c.bin",
                bytes: b"ordinary",
                role: None,
            },
        ];
        let p = produce(&req(&c, &t, &cap, &form)).unwrap();
        assert!(p.evidence.starts_with("kni-pixel-notdef-evidence\tv3\n"));
        assert!(p.evidence.contains("kind\trepeated-form\n"));
        assert!(p.evidence.contains(&format!("pixel_form_sha256\t{form}\n")));
        assert!(p
            .evidence
            .contains(&format!("selected\ta.png\t{}\n", c.source_sha256)));
        assert!(p.evidence.contains("pixel_source\t0x41\trepeated-form\ta.png\t"));
        assert!(!p.evidence.contains("c.bin"));
        assert!(!p.evidence.contains("ordinary"));
        assert!(!p.evidence.contains("unsupported"));
        assert!(!p.evidence.contains("font"));
        assert!(!p.evidence.contains("space_evidence"));
        assert_eq!(p.evidence_sha, sha256_hex(p.evidence.as_bytes()));
    }
    #[test]
    fn losing_and_competing_forms_are_not_listed_and_not_errors() {
        let a = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let other = include_bytes!("../../core/tests/fixtures/jpeg_source/image_checker.jpg");
        let c = context(sha256_hex(a));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: a,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 66,
                path: "b.jpg",
                bytes: other,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
        ];
        let p = produce(&req(&c, &t, &cap, &form)).unwrap();
        assert!(p.evidence.contains("pixel_source\t0x42\trepeated-form\tb.jpg\t"));
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: a,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 66,
                path: "b.png",
                bytes: a,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 67,
                path: "loser.jpg",
                bytes: other,
                role: None,
            },
        ];
        let p = produce(&req(&c, &t, &cap, &form)).unwrap();
        assert!(!p.evidence.contains("loser.jpg"));
    }
    #[test]
    fn missing_single_claim_and_invalid_bytes_refuse() {
        let b = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let c = context(sha256_hex(b));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [Tile {
            cp: 65,
            path: "a.png",
            bytes: b,
            role: None,
        }];
        assert!(matches!(
            produce(&req(&c, &t, &cap, &form)),
            Err(ProducerError::MissingPixelEvidence)
        ));
        let t = [Tile {
            cp: 65,
            path: "a.png",
            bytes: b,
            role: Some(PixelNotdefKind::RepeatedForm),
        }];
        assert!(matches!(
            produce(&req(&c, &t, &cap, &form)),
            Err(ProducerError::MissingPixelEvidence)
        ));
        let t = [Tile {
            cp: 65,
            path: "a.png",
            bytes: b"",
            role: Some(PixelNotdefKind::BlankCell),
        }];
        assert!(matches!(
            produce(&req(&c, &t, &cap, &form)),
            Err(ProducerError::InvalidSourceImage)
        ));
    }
    #[test]
    fn mixed_kind_claims_refuse_ambiguous() {
        let inked = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let white = blank();
        let c = context(sha256_hex(inked));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: inked,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 66,
                path: "b.png",
                bytes: &white,
                role: Some(PixelNotdefKind::BlankCell),
            },
        ];
        assert!(matches!(
            produce(&req(&c, &t, &cap, &form)),
            Err(ProducerError::AmbiguousPixelCandidate)
        ));
    }
    #[test]
    fn blank_claim_emits_without_space_binding_or_numeric_advance() {
        let b = blank();
        let c = context(sha256_hex(&b));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: &b,
                role: Some(PixelNotdefKind::BlankCell),
            },
            Tile {
                cp: 66,
                path: "b.png",
                bytes: &b,
                role: Some(PixelNotdefKind::BlankCell),
            },
        ];
        let p = produce(&req(&c, &t, &cap, &form)).unwrap();
        assert!(p.evidence.contains("kind\tblank-cell\n"));
        assert!(!p.evidence.contains("space_evidence"));
        assert!(!p.evidence.contains("advance\t"));
    }
    #[test]
    fn space_field_refused_for_both_kinds() {
        let sp = "a".repeat(64);
        let cap = sha256_hex(b"capture");
        let form = form();
        for (b, kind) in [
            (
                include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png").to_vec(),
                PixelNotdefKind::RepeatedForm,
            ),
            (blank(), PixelNotdefKind::BlankCell),
        ] {
            let c = context(sha256_hex(&b));
            let t = [
                Tile {
                    cp: 65,
                    path: "a.png",
                    bytes: &b,
                    role: Some(kind),
                },
                Tile {
                    cp: 66,
                    path: "b.png",
                    bytes: &b,
                    role: Some(kind),
                },
            ];
            let mut r = req(&c, &t, &cap, &form);
            r.space_evidence_sha256 = Some(&sp);
            assert!(matches!(
                produce(&r),
                Err(ProducerError::Invalid(BadNotdef::Grammar))
            ));
        }
    }
    #[test]
    fn selected_claim_must_match_context_pin() {
        let a = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let other = include_bytes!("../../core/tests/fixtures/jpeg_source/image_checker.jpg");
        let c = context(sha256_hex(other));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: a,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 66,
                path: "b.png",
                bytes: a,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 67,
                path: "c.jpg",
                bytes: other,
                role: None,
            },
        ];
        assert!(matches!(
            produce(&req(&c, &t, &cap, &form)),
            Err(ProducerError::Invalid(BadNotdef::ShaMismatch))
        ));
    }
    #[test]
    fn malformed_form_claim_refuses() {
        let b = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let c = context(sha256_hex(b));
        let cap = sha256_hex(b"capture");
        let t = [
            Tile {
                cp: 65,
                path: "a.png",
                bytes: b,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
            Tile {
                cp: 66,
                path: "b.png",
                bytes: b,
                role: Some(PixelNotdefKind::RepeatedForm),
            },
        ];
        assert!(matches!(
            produce(&req(&c, &t, &cap, "zz")),
            Err(ProducerError::Invalid(BadNotdef::Grammar))
        ));
    }
    #[test]
    fn context_hash_path_codepoint_and_budget_refuse() {
        let b = include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png");
        let c = context(sha256_hex(b));
        let cap = sha256_hex(b"capture");
        let form = form();
        let t = [Tile {
            cp: 65,
            path: "../a.png",
            bytes: b,
            role: Some(PixelNotdefKind::RepeatedForm),
        }];
        assert!(produce(&req(&c, &t, &cap, &form)).is_err());
        let t = [Tile {
            cp: 0,
            path: "a.png",
            bytes: b,
            role: Some(PixelNotdefKind::RepeatedForm),
        }];
        assert!(produce(&req(&c, &t, &cap, &form)).is_err());
        let t = [Tile {
            cp: 65,
            path: "a.png",
            bytes: b,
            role: Some(PixelNotdefKind::RepeatedForm),
        }];
        let mut r = req(&c, &t, &cap, &form);
        r.limits.max_working_bytes = 1;
        assert!(produce(&r).is_err());
        r = req(&c, &t, &cap, &form);
        r.capture_sha256 = "b";
        assert!(produce(&r).is_err());
    }


}
