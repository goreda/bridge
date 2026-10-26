//! Pixel-evidence validation over captured source images.
//! No original font or cmap-absence claim is needed or inferred.
//! Hashes establish integrity; bounded decode and run context are checked separately.
use kni_core::{cff_reader::sha256_hex, jpeg_source::Limits, scale_context::ScaleContext};
use std::io::Read;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

pub use kni_pipeline::notdef_types::{BadNotdef, PixelContext, PixelNotdefKind, validate_codepoint};

/// Complete captured population: one source image and integrity pin per CP.
pub type PixelPopulation = BTreeMap<u32, (PathBuf, String)>;
#[derive(Clone, Copy, Debug)]
pub struct ValidationLimits {
    pub image: Limits,
    pub max_record_bytes: usize,
    pub max_record_rows: usize,
    pub max_witnesses: usize,
    /// Retained evidence-record metadata allowance only, not a cumulative tile budget.
    /// Kept as an API-compatible field; image payload uses a fresh per-tile allowance.
    pub max_aggregate_working_bytes: usize,
}
struct Budget {
    left: usize,
}
impl Budget {
    fn charge(&mut self, n: usize) -> Result<(), BadNotdef> {
        self.left = self.left.checked_sub(n).ok_or(BadNotdef::ResourceLimit)?;
        Ok(())
    }
}
pub struct DecodedTile {
    pub width: usize,
    pub height: usize,
    pub gray: Vec<u8>,
    /// Limits actually applied by the decoder and where they came from.
    pub receipt: LimitsReceipt,
}
/// Decode limits as applied (after reserving this tile's pinned input/SHA allowance)
/// plus origin. Each tile starts with the same explicit image limits. Scope statements are fixed text:
/// budget covers major payload only and PNG chunk CRCs are not validated.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LimitsReceipt {
    pub max_input_bytes: usize,
    pub max_pixels: usize,
    pub max_working_bytes: usize,
    pub origin: String,
}
impl LimitsReceipt {
    pub fn line(&self) -> String {
        format!(
            "notdef_decode_limits\tmax_input_bytes\t{}\tmax_pixels\t{}\tmax_working_bytes\t{}\torigin\t{}\tbudget_scope\tmajor_payload_only(idat,raw,recon,gray;not_allocator_rss_huffman_scratch)\tpng_crc\tnot_validated\tparity\twithin_limits_only\n",
            self.max_input_bytes, self.max_pixels, self.max_working_bytes, self.origin
        )
    }
}
/// Decoder adapter must enforce its own inflate/output/scratch caps BEFORE
/// allocation. The pending shared-core bounded decoder is the production route.
pub trait BoundedDecoder {
    fn decode(&self, bytes: &[u8], limits: Limits) -> Result<DecodedTile, BadNotdef>;
}
// Placeholder decoder: refuses every decode with DecoderUnavailable until the pending shared-core bounded decoder (the production route, per the BoundedDecoder doc) lands; no construction site yet.
#[allow(dead_code)]
pub struct UnavailableDecoder;
impl BoundedDecoder for UnavailableDecoder {
    fn decode(&self, _: &[u8], _: Limits) -> Result<DecodedTile, BadNotdef> {
        Err(BadNotdef::DecoderUnavailable)
    }
}

/// Production adapter over the shared core bounded decoder. PNG goes through
/// `bounded_png_adapter` (Route::Notdef) with the caller's explicit limits; JPEG
/// goes through the existing bounded `jpeg_source` via `decode_source`. There is
/// no default limit, no unbounded fallback. Budget covers major payload only
/// (not allocator/RSS/Huffman scratch); PNG chunk CRCs are not validated.
/// The adapter receipt (limits + origin) is carried by `DecodedTile`.
pub struct CoreBoundedDecoder;
impl BoundedDecoder for CoreBoundedDecoder {
    fn decode(&self, bytes: &[u8], limits: Limits) -> Result<DecodedTile, BadNotdef> {
        use kni_core::bounded_png_adapter::{decode_gray, LimitsOrigin, Route};
        use kni_core::capture::{DecodeLimits, PngDecodeError};
        if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
            let dl = DecodeLimits {
                max_input_bytes: limits.max_input_bytes,
                max_pixels: limits.max_pixels,
                max_working_bytes: limits.max_working_bytes,
            };
            let g = decode_gray(
                Route::Notdef,
                bytes,
                &dl,
                LimitsOrigin::Explicit("notdef ValidationLimits.image".to_string()),
            )
            .map_err(|e| match e {
                PngDecodeError::InputTooLarge { .. }
                | PngDecodeError::TooManyPixels { .. }
                | PngDecodeError::WorkingBudgetExceeded { .. }
                | PngDecodeError::AllocationRefused { .. }
                | PngDecodeError::InflateOverrun { .. } => BadNotdef::ResourceLimit,
                _ => BadNotdef::InvalidSourceImage,
            })?;
            let r = &g.receipt;
            let receipt = LimitsReceipt {
                max_input_bytes: r.limits.max_input_bytes,
                max_pixels: r.limits.max_pixels,
                max_working_bytes: r.limits.max_working_bytes,
                origin: r.limits_origin.render(),
            };
            Ok(DecodedTile {
                width: g.width,
                height: g.height,
                gray: g.gray,
                receipt,
            })
        } else if bytes.starts_with(&[0xff, 0xd8]) {
            let png_unused = DecodeLimits {
                max_input_bytes: limits.max_input_bytes,
                max_pixels: limits.max_pixels,
                max_working_bytes: limits.max_working_bytes,
            };
            let d = kni_core::capture_dispatch::decode_source(bytes, &png_unused, limits).map_err(
                |e| match e {
                    kni_core::capture_dispatch::DispatchError::Jpeg(
                        kni_core::jpeg_source::JpegError::ResourceLimit,
                    )
                    | kni_core::capture_dispatch::DispatchError::Jpeg(
                        kni_core::jpeg_source::JpegError::AllocationFailed,
                    ) => BadNotdef::ResourceLimit,
                    _ => BadNotdef::InvalidSourceImage,
                },
            )?;
            let receipt = LimitsReceipt {
                max_input_bytes: limits.max_input_bytes,
                max_pixels: limits.max_pixels,
                max_working_bytes: limits.max_working_bytes,
                origin: kni_core::bounded_png_adapter::LimitsOrigin::Explicit(
                    "notdef ValidationLimits.image (jpeg_source)".to_string(),
                )
                .render(),
            };
            Ok(DecodedTile {
                width: d.width,
                height: d.height,
                gray: d.gray,
                receipt,
            })
        } else {
            Err(BadNotdef::InvalidSourceImage)
        }
    }
}

#[derive(Clone, Debug)]
pub struct EvidenceBinding {
    pub file: PathBuf,
    pub sha256: String,
    pub style: String,
    pub capture: String,
    pub scale: f64,
    pub frame: String,
}
/// Canonical form identity: dimensions followed by unchanged decoded gray pixels.
/// File compression bytes are not form identity. No threshold or transform.
/// Placeholder-class dominance rule (architect decision, PN-3): a style's
/// slot population, grouped by pixel_form_sha256, carries a placeholder
/// class only when the group-size distribution splits on its own - the
/// largest REPEATED group (singletons excluded: a lone form repeats
/// nothing) must be larger than ALL other repeated groups COMBINED. No
/// threshold constant: the gap is the distribution's own split, and when
/// the largest repeated class does not dominate, the style has no
/// placeholder class. A tie at the top cannot dominate (the equal rival is
/// part of the combined rest), so the rule needs no tie-breaker. Validated
/// on the 19-style collection: flags exactly the known placeholder classes
/// (Lÿno x4, MCA x9, Marq, Mona, Mona Alt, Unit) and nothing in
/// placeholder-free styles (Paul New included).
pub fn dominant_placeholder<'a>(groups: &'a BTreeMap<String, Vec<u32>>) -> Option<&'a String> {
    let mut repeated: Vec<(&String, usize)> = groups
        .iter()
        .filter(|(_, cps)| cps.len() >= 2)
        .map(|(hash, cps)| (hash, cps.len()))
        .collect();
    if repeated.is_empty() {
        return None;
    }
    repeated.sort_by(|a, b| b.1.cmp(&a.1));
    let top = repeated[0].1;
    let rest: usize = repeated[1..].iter().map(|(_, n)| n).sum();
    if top > rest {
        Some(repeated[0].0)
    } else {
        None
    }
}

pub fn pixel_form_sha256(width: usize, height: usize, gray: &[u8]) -> Result<String, BadNotdef> {
    let count = width.checked_mul(height).ok_or(BadNotdef::ResourceLimit)?;
    if width == 0 || height == 0 || count != gray.len() { return Err(BadNotdef::InvalidSourceImage); }
    let width = u64::try_from(width).map_err(|_| BadNotdef::ResourceLimit)?;
    let height = u64::try_from(height).map_err(|_| BadNotdef::ResourceLimit)?;
    let length = gray.len().checked_add(16).ok_or(BadNotdef::ResourceLimit)?;
    let mut bytes = Vec::new();
    bytes.try_reserve_exact(length).map_err(|_| BadNotdef::ResourceLimit)?;
    bytes.extend_from_slice(&width.to_be_bytes());
    bytes.extend_from_slice(&height.to_be_bytes());
    bytes.extend_from_slice(gray);
    Ok(sha256_hex(&bytes))
}

pub const PIXEL_INK_MODEL: &str = "decoded-gray-all-255-no-transform-v1";
#[derive(Clone, Debug, PartialEq)]
pub struct SpaceAdvanceBinding {
    pub evidence_sha256: String,
    pub style: String,
    pub frame: String,
    pub units_per_px: f64,
}

#[derive(Clone, Debug)]
pub enum DetectionState {
    PixelEvidence {
        kind: PixelNotdefKind,
        context: PixelContext,
        image: PathBuf,
        pixel_form_sha256: String,
        // Evidence sha256 retained as part of the pixel-evidence record; never read on this route.
        #[allow(dead_code)]
        evidence_sha256: String,
        /// Placeholder CPs: retained in capture evidence only. On both routes they
        /// are not ordinary glyphs (skipped, typed placeholder_skip, no cmap); the
        /// .notdef itself keeps the evidence form.
        sources: Vec<u32>,
        space_advance: Option<SpaceAdvanceBinding>,
        // Decode limits receipt retained as part of the pixel-evidence record; never read on this route.
        #[allow(dead_code)]
        decode: LimitsReceipt,
    },
    MissingPixelEvidence,
    // Detection state for an ambiguous pixel candidate; no construction site on this route yet.
    #[allow(dead_code)]
    AmbiguousPixelCandidate,
    CandidateProxy { selected_source_sha: String, selected_cp: u32, candidate_cps: Vec<u32>, selection_rule: String, generated_glyph_ref: String, source_snapshot: Vec<(u32,String,String)> },
    // Detection state for repeated art with its evidence fields; no construction site on this route yet.
    #[allow(dead_code)]
    RepeatedArt {
        image: PathBuf,
        source_sha256: String,
        advance: f64,
        scale: f64,
        evidence_sha256: String,
        witnesses: usize,
        decode: LimitsReceipt,
    },
    // Detection state for a verified blank; no construction site on this route yet.
    #[allow(dead_code)]
    VerifiedBlank {
        advance: f64,
        evidence_sha256: String,
        witnesses: usize,
        decode: LimitsReceipt,
    },
    // Detection state for missing evidence; no construction site on this route yet.
    #[allow(dead_code)]
    MissingEvidence,
    // Detection state for an ambiguous detection; no construction site on this route yet.
    #[allow(dead_code)]
    Ambiguous,
}
#[derive(Clone, Debug)]
pub enum Action {
    PixelEvidence {
        kind: PixelNotdefKind,
        context: PixelContext,
        image: PathBuf,
        // Space-advance binding retained in the pixel-evidence action; never read on this route.
        #[allow(dead_code)]
        space_advance: Option<SpaceAdvanceBinding>,
    },
    CandidateProxy,
    Process {
        image: PathBuf,
        source_sha256: String,
        advance: f64,
        scale: f64,
    },
    Empty {
        advance: f64,
        partial_reason: Option<&'static str>,
    },
}
impl DetectionState {
    /// `declared_em_advance`: the caller-declared em (manifest upm) used as the
    /// blank .notdef advance on the partial-degrade branches below - the same
    /// declared fallback the stage-5 assembly uses for an empty population.
    /// No fabricated zero: a 0.0 advance made .notdef collapse and shadowed
    /// the max-glyph-advance branch (the drawn glyph short-circuits it).
    pub fn action(&self, allow_partial_degrade: bool, declared_em_advance: f64) -> Result<Action, BadNotdef> {
        match self {
            Self::PixelEvidence { kind, context, image, space_advance, .. } => {
                if space_advance.is_some() { return Err(BadNotdef::ContextMismatch); }
                Ok(Action::PixelEvidence {
                    kind: *kind, context: context.clone(), image: image.clone(),
                    space_advance: space_advance.clone(),
                })
            }
            Self::MissingPixelEvidence if allow_partial_degrade => Ok(Action::Empty {
                advance: declared_em_advance,
                partial_reason: Some("missing_gid0_pixel_evidence"),
            }),
            Self::MissingPixelEvidence => Err(BadNotdef::MissingPixelEvidence),
            Self::AmbiguousPixelCandidate => Err(BadNotdef::AmbiguousPixelCandidate),
            Self::CandidateProxy { .. } => Ok(Action::CandidateProxy),
            Self::RepeatedArt {
                image,
                source_sha256,
                advance,
                scale,
                ..
            } => Ok(Action::Process {
                image: image.clone(),
                source_sha256: source_sha256.clone(),
                advance: *advance,
                scale: *scale,
            }),
            Self::VerifiedBlank { advance, .. } => Ok(Action::Empty {
                advance: *advance,
                partial_reason: None,
            }),
            Self::MissingEvidence | Self::Ambiguous if allow_partial_degrade => Ok(Action::Empty {
                advance: declared_em_advance,
                partial_reason: Some(match self {
                    Self::MissingEvidence => "missing_gid0_evidence",
                    _ => "ambiguous_gid0_evidence",
                }),
            }),
            Self::MissingEvidence => Err(BadNotdef::MissingEvidence),
            Self::Ambiguous => Err(BadNotdef::Ambiguous),
        }
    }
    pub fn receipt(&self) -> String {
        match self {
            Self::PixelEvidence { kind, pixel_form_sha256, space_advance, sources, .. } => format!(
                "classification\tpixel-notdef-candidate\tdecision_basis\tsource-image\tpixel_form_sha256\t{}\tkind\t{}\tspace_binding\t{}\tadvance_basis\t{}\tplaceholder_cp_count\t{}\n",
                pixel_form_sha256, kind.token(), space_advance.as_ref().map(|s| s.evidence_sha256.as_str()).unwrap_or("none"),
                if *kind == PixelNotdefKind::BlankCell { "max-glyph-advance" } else { "generated-source-solver-pending-assembly" }, sources.len()),
            Self::MissingPixelEvidence => "notdef_state\tMissingPixelEvidence\n".into(),
            Self::AmbiguousPixelCandidate => "notdef_state\tAmbiguousPixelCandidate\n".into(),
            Self::CandidateProxy { candidate_cps, selection_rule, .. } => format!("notdef_state\tCandidateProxy\tidentity_claim\tunverified\tpolicy\tcandidate-proxy\tplaceholder_cp_count\t{}\trule\t{}\n", candidate_cps.len(), selection_rule),
            Self::RepeatedArt { evidence_sha256, witnesses, decode, .. } => format!("notdef_state\tRepeatedArt\tevidence_sha256\t{evidence_sha256}\twitnesses\t{witnesses}\tclaim\tbound-detector-record\n{}", decode.line()),
            Self::VerifiedBlank { evidence_sha256, witnesses, decode, .. } => format!("notdef_state\tVerifiedBlank\tevidence_sha256\t{evidence_sha256}\twitnesses\t{witnesses}\tclaim\tbound-detector-record\n{}", decode.line()),
            Self::MissingEvidence => "notdef_state\tMissingEvidence\n".into(),
            Self::Ambiguous => "notdef_state\tAmbiguous\n".into(),
        }
    }
}
fn sha(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn positive(s: &str) -> Result<f64, BadNotdef> {
    let v: f64 = s.parse().map_err(|_| BadNotdef::Grammar)?;
    if !v.is_finite() || v <= 0.0 {
        return Err(BadNotdef::Grammar);
    }
    Ok(v)
}
// Advance parser (finite, range 0..=65535, else BadNotdef::Grammar refusal); kept for the route that reads advances, currently unused.
#[allow(dead_code)]
fn advance(s: &str) -> Result<f64, BadNotdef> {
    let v: f64 = s.parse().map_err(|_| BadNotdef::Grammar)?;
    if !v.is_finite() || !(0.0..=65535.0).contains(&v) {
        return Err(BadNotdef::Grammar);
    }
    Ok(v)
}
fn cp(s: &str) -> Result<u32, BadNotdef> {
    let v = u32::from_str_radix(s.strip_prefix("0x").unwrap_or(s), 16)
        .map_err(|_| BadNotdef::Grammar)?;
    validate_codepoint(v)?;
    Ok(v)
}
/// Shared producer/parser transport rule: preserve exact Unicode, encode only
/// ASCII space and percent. No normalization or transliteration.
pub fn encode_style_token(style: &str) -> Result<String, BadNotdef> {
    if style.is_empty() || style.chars().any(|c| c.is_whitespace() && c != ' ') {
        return Err(BadNotdef::Grammar);
    }
    Ok(style.replace('%', "%25").replace(' ', "%20"))
}
/// STYLE transport accepts only %20 (space) and %25 (percent). Decode once;
/// unknown, truncated, lowercase or recursive escape forms are never guessed.
fn decode_style_token(token: &str) -> Result<String, BadNotdef> {
    let mut out = String::new();
    let mut tail = token;
    while let Some(i) = tail.find('%') {
        out.push_str(&tail[..i]);
        tail = &tail[i..];
        if tail.starts_with("%20") {
            out.push(' ');
        } else if tail.starts_with("%25") {
            out.push('%');
        } else {
            return Err(BadNotdef::Grammar);
        }
        tail = &tail[3..];
    }
    out.push_str(tail);
    if encode_style_token(&out)? != token {
        return Err(BadNotdef::Grammar);
    }
    Ok(out)
}
/// Manifest grammar: notdef evidence FILE SHA STYLE CAPTURE SCALE FRAME.
/// FRAME is an explicit capture coordinate-frame identifier, never inferred.
pub fn parse_binding<'a>(
    fields: impl Iterator<Item = &'a str>,
    base: &Path,
) -> Result<EvidenceBinding, BadNotdef> {
    let f: Vec<_> = fields.collect();
    if f.len() != 7 || f[0] != "evidence" || !sha(f[2]) {
        return Err(BadNotdef::Grammar);
    }
    Ok(EvidenceBinding {
        file: base.join(f[1]),
        sha256: f[2].into(),
        style: decode_style_token(f[3])?,
        capture: f[4].into(),
        scale: positive(f[5])?,
        frame: f[6].into(),
    })
}
fn read_pinned(
    path: &Path,
    pin: &str,
    cap: usize,
    budget: &mut Budget,
) -> Result<Vec<u8>, BadNotdef> {
    if !sha(pin) {
        return Err(BadNotdef::Grammar);
    }
    let mut file = fs::File::open(path).map_err(|_| BadNotdef::Io)?;
    let metadata = file.metadata().map_err(|_| BadNotdef::Io)?;
    if !metadata.is_file() || metadata.len() > cap as u64 {
        return Err(BadNotdef::ResourceLimit);
    }
    let mut bytes = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        let n = file.read(&mut chunk).map_err(|_| BadNotdef::Io)?;
        if n == 0 {
            break;
        }
        if n > cap.saturating_sub(bytes.len()) {
            return Err(BadNotdef::ResourceLimit);
        }
        // One copy for bytes, one for sha256_hex's padded input buffer.
        budget.charge(n.checked_mul(2).ok_or(BadNotdef::ResourceLimit)?)?;
        bytes
            .try_reserve_exact(n)
            .map_err(|_| BadNotdef::ResourceLimit)?;
        bytes.extend_from_slice(&chunk[..n]);
    }
    budget.charge(128)?; // SHA padding allowance.
    if sha256_hex(&bytes) != pin {
        return Err(BadNotdef::ShaMismatch);
    }
    Ok(bytes)
}
/// One bounded decode pass over the complete population selects and validates
/// the unique most-frequent pixel form. No per-witness re-decode pass.
pub fn load(
    binding: &EvidenceBinding, population: &PixelPopulation, scale: &ScaleContext,
    root: &Path, limits: ValidationLimits, decoder: &impl BoundedDecoder,
) -> Result<DetectionState, BadNotdef> {
    if binding.frame != scale.frame_binding()
        || binding.scale.to_bits() != scale.units_per_px().to_bits() { return Err(BadNotdef::ContextMismatch); }
    let root = root.canonicalize().map_err(|_| BadNotdef::Io)?;
    let contained = |path: &Path| -> Result<PathBuf,BadNotdef> {
        use std::path::Component;
        if path.components().any(|c| matches!(c,Component::ParentDir)) { return Err(BadNotdef::ContextMismatch); }
        let path = path.canonicalize().map_err(|_| BadNotdef::Io)?;
        if !path.starts_with(&root) { return Err(BadNotdef::ContextMismatch); }
        Ok(path)
    };
    let record_path = contained(&binding.file)?;
    let base = record_path.parent().ok_or(BadNotdef::ContextMismatch)?;
    let mut budget = Budget { left: limits.max_aggregate_working_bytes };
    let bytes = read_pinned(&record_path,&binding.sha256,limits.max_record_bytes.min(limits.image.max_input_bytes),&mut budget)?;
    budget.charge(bytes.len().checked_mul(2).ok_or(BadNotdef::ResourceLimit)?)?;
    let text=std::str::from_utf8(&bytes).map_err(|_| BadNotdef::Grammar)?;
    let mut lines=text.lines();
    if lines.next()!=Some("kni-pixel-notdef-evidence\tv3") { return Err(BadNotdef::Grammar); }
    let mut singleton=BTreeMap::<&str,Vec<&str>>::new();
    let mut sources=Vec::new(); let mut seen=BTreeSet::new();
    for (row,line) in lines.enumerate() {
        if row>=limits.max_record_rows { return Err(BadNotdef::ResourceLimit); }
        if line.is_empty(){continue;}
        if line.split('\t').take(6).count()>5 { return Err(BadNotdef::Grammar); }
        let fields:Vec<_>=line.split('\t').collect();
        match fields.as_slice() {
            ["pixel_source",scalar,role,path,pin]=>{
                if sources.len()>=limits.max_witnesses{return Err(BadNotdef::ResourceLimit);}
                let scalar=cp(scalar)?;
                if !seen.insert(scalar){return Err(BadNotdef::Duplicate);}
                if path.is_empty() || !sha(pin){return Err(BadNotdef::Grammar);}
                budget.charge(256)?;
                sources.push((scalar,PixelNotdefKind::parse(role)?,*path,*pin));
            }
            [key,rest @ ..] if ["kind","style","frame","scale","ink_model","capture_sha256",
                "selected","space_evidence_sha256","pixel_form_sha256"].contains(key)=>{
                if singleton.insert(key,rest.to_vec()).is_some(){return Err(BadNotdef::Duplicate);}
            }
            _=>return Err(BadNotdef::Grammar),
        }
    }
    let one=|key:&str|->Result<&str,BadNotdef>{
        let v=singleton.get(key).ok_or(BadNotdef::Grammar)?;
        if v.len()!=1 || v[0].is_empty(){return Err(BadNotdef::Grammar);} Ok(v[0])
    };
    let kind=PixelNotdefKind::parse(one("kind")?)?;
    if one("style")?!=binding.style || one("frame")?!=binding.frame || one("capture_sha256")?!=binding.capture
        || positive(one("scale")?)?.to_bits()!=binding.scale.to_bits(){return Err(BadNotdef::ContextMismatch);}
    if one("ink_model")?!=PIXEL_INK_MODEL{return Err(BadNotdef::Grammar);}
    let form_hash=one("pixel_form_sha256")?;
    if !sha(form_hash){return Err(BadNotdef::Grammar);}
    // Repetition is required; a singleton is not a candidate.
    if sources.len()<2{return Err(BadNotdef::MissingPixelEvidence);}
    let selected=singleton.get("selected").ok_or(BadNotdef::MissingPixelEvidence)?;
    if selected.len()!=2 || selected[0].is_empty() || !sha(selected[1]){return Err(BadNotdef::Grammar);}
    let relative=|raw:&str|->Result<PathBuf,BadNotdef>{
        use std::path::Component;
        let path=Path::new(raw);
        if path.is_absolute() || path.components().any(|c|!matches!(c,Component::Normal(_)|Component::CurDir)){
            return Err(BadNotdef::ContextMismatch);
        }
        contained(&base.join(path))
    };
    let image=relative(selected[0])?;
    if population.len()>limits.max_witnesses{return Err(BadNotdef::ResourceLimit);}
    let mut groups=BTreeMap::<String,Vec<u32>>::new();
    let mut selected_hash=None;
    let mut selected_receipt=None;
    let mut winner_blank=BTreeMap::new();
    // The only population image decode pass. Count decoded forms, not PNG bytes.
    for (&scalar,(path,pin)) in population {
        validate_codepoint(scalar)?;
        let path=contained(path)?;
        // Only the current tile owns payload allowance. Previous decoded/input buffers
        // are dropped at the end of this iteration; their charges must not accumulate.
        let mut tile_budget = Budget { left: limits.image.max_working_bytes };
        let bytes=read_pinned(&path,pin,limits.image.max_input_bytes,&mut tile_budget)?;
        let mut applied=limits.image;
        applied.max_working_bytes=tile_budget.left;
        let decoded=decoder.decode(&bytes,applied)?;
        let count=decoded.width.checked_mul(decoded.height).ok_or(BadNotdef::ResourceLimit)?;
        if count!=decoded.gray.len() || count==0{return Err(BadNotdef::InvalidSourceImage);}
        if count>applied.max_pixels{return Err(BadNotdef::ResourceLimit);}
        // gray + canonical form buffer + SHA padded copy, with framing/padding allowance.
        // Check before pixel_form_sha256 allocates either hash buffer.
        tile_budget.charge(count.checked_mul(3).and_then(|n|n.checked_add(512)).ok_or(BadNotdef::ResourceLimit)?)?;
        let hash=pixel_form_sha256(decoded.width,decoded.height,&decoded.gray)?;
        let blank=decoded.gray.iter().all(|&pixel|pixel==255);
        winner_blank.insert(hash.clone(),blank);
        if path==image && pin==selected[1] {
            selected_hash=Some(hash.clone());selected_receipt=Some(decoded.receipt.clone());
        }
        groups.entry(hash).or_default().push(scalar);
        // Nothing pixel-sized escapes this iteration, including the selected tile.
        drop(decoded);
        drop(bytes);
    }
    let maximum=groups.values().map(Vec::len).max().ok_or(BadNotdef::MissingPixelEvidence)?;
    if maximum<2{return Err(BadNotdef::MissingPixelEvidence);}
    let mut maxima=groups.iter().filter(|(_,cps)|cps.len()==maximum);
    let (winning_hash,winning_cps)=maxima.next().ok_or(BadNotdef::MissingPixelEvidence)?;
    if maxima.next().is_some(){return Err(BadNotdef::AmbiguousPixelCandidate);}
    if winning_hash!=form_hash || selected_hash.as_ref()!=Some(winning_hash)
        || winner_blank.get(winning_hash)!=Some(&(kind==PixelNotdefKind::BlankCell)) {
        return Err(BadNotdef::AmbiguousPixelCandidate);
    }
    let mut selected_is_source=false; let mut codepoints=Vec::new();
    for (scalar,role,path,pin) in sources {
        if role!=kind{return Err(BadNotdef::AmbiguousPixelCandidate);}
        let path=relative(path)?;
        if population.get(&scalar)!=Some(&(path.clone(),pin.into())) {return Err(BadNotdef::ContextMismatch);}
        selected_is_source|=path==image && pin==selected[1];
        codepoints.push(scalar);
    }
    codepoints.sort_unstable();
    if !selected_is_source || &codepoints!=winning_cps{return Err(BadNotdef::AmbiguousPixelCandidate);}
    if singleton.contains_key("space_evidence_sha256") { return Err(BadNotdef::Grammar); }
    let space_advance=None;
    Ok(DetectionState::PixelEvidence{kind,context:PixelContext{style:binding.style.clone(),frame:binding.frame.clone(),units_per_px:binding.scale,
        source_sha256:selected[1].into(),ink_model:PIXEL_INK_MODEL.into()},image,pixel_form_sha256:form_hash.into(),evidence_sha256:binding.sha256.clone(),
        sources:codepoints,space_advance,decode:selected_receipt.ok_or(BadNotdef::MissingPixelEvidence)?})
}


#[cfg(test)]
mod pixel_tests {
    use super::*;
    use std::cell::Cell;
    struct Decoder { calls:Cell<usize> }
    impl BoundedDecoder for Decoder {
        fn decode(&self,b:&[u8],l:Limits)->Result<DecodedTile,BadNotdef>{
            self.calls.set(self.calls.get().checked_add(1).unwrap());
            let &pixel=b.first().ok_or(BadNotdef::InvalidSourceImage)?;
            Ok(DecodedTile{width:2,height:1,gray:vec![pixel,255],receipt:LimitsReceipt{
                max_input_bytes:l.max_input_bytes,max_pixels:l.max_pixels,max_working_bytes:l.max_working_bytes,origin:"synthetic-unit-only".into()}})
        }
    }
    struct Fixture{root:PathBuf,binding:EvidenceBinding,population:PixelPopulation,decoder:Decoder}
    impl Drop for Fixture{fn drop(&mut self){let _=fs::remove_dir_all(&self.root);}}
    fn fixture(blank:bool)->Fixture{
        use std::sync::atomic::{AtomicUsize,Ordering};static N:AtomicUsize=AtomicUsize::new(0);
        let root=std::env::temp_dir().join(format!("pixel-simple-{}-{}",std::process::id(),N.fetch_add(1,Ordering::Relaxed)));
        fs::create_dir_all(&root).unwrap();let root=root.canonicalize().unwrap();
        let pixel=if blank{255}else{0};let bytes=[pixel];let pin=sha256_hex(&bytes);
        fs::write(root.join("a"),bytes).unwrap();fs::write(root.join("b"),bytes).unwrap();fs::write(root.join("c"),[127]).unwrap();
        let kind=if blank{"blank-cell"}else{"repeated-form"};
        let hash=pixel_form_sha256(2,1,&[pixel,255]).unwrap();
        let text=format!("kni-pixel-notdef-evidence\tv3\nkind\t{kind}\nstyle\tT\nframe\tf\nscale\t2\nink_model\t{PIXEL_INK_MODEL}\ncapture_sha256\t{}\npixel_form_sha256\t{hash}\nselected\ta\t{pin}\npixel_source\t41\t{kind}\ta\t{pin}\npixel_source\t42\t{kind}\tb\t{pin}\n","c".repeat(64));

        fs::write(root.join("evidence"),&text).unwrap();
        let binding=EvidenceBinding{file:root.join("evidence"),sha256:sha256_hex(text.as_bytes()),style:"T".into(),capture:"c".repeat(64),scale:2.0,frame:"f".into()};
        let population=BTreeMap::from([(65,(root.join("a"),pin.clone())),(66,(root.join("b"),pin)),(67,(root.join("c"),sha256_hex(&[127])))]);
        Fixture{root,binding,population,decoder:Decoder{calls:Cell::new(0)}}
    }
    fn run(f:&Fixture)->Result<DetectionState,BadNotdef>{
        let scale=ScaleContext::from_convention("T","synthetic-unit",2.0,1000.0,"T","f").unwrap();
        load(&f.binding,&f.population,&scale,&f.root,ValidationLimits{image:Limits{max_input_bytes:16384,max_pixels:64,max_working_bytes:1<<20},max_record_bytes:16384,max_record_rows:64,max_witnesses:8,max_aggregate_working_bytes:1<<20},&f.decoder)
    }
    #[test]fn population_decoded_once_placeholders_remain_in_evidence_not_font(){
        let f=fixture(false);let before=f.population.clone();let state=run(&f).unwrap();
        assert_eq!(f.decoder.calls.get(),3);assert_eq!(f.population,before);
        assert!(matches!(&state,DetectionState::PixelEvidence{sources,..}if sources==&vec![65,66]));
        assert!(state.receipt().contains("placeholder_cp_count\t2"));assert!(state.receipt().contains("decision_basis\tsource-image"));
    }
    #[test]fn tied_maximum_and_singleton_refuse(){
        let mut f=fixture(false);f.population.insert(68,(f.root.join("c"),sha256_hex(&[127])));
        assert_eq!(run(&f).unwrap_err(),BadNotdef::AmbiguousPixelCandidate);
        let mut f=fixture(false);f.population.remove(&66);assert_eq!(run(&f).unwrap_err(),BadNotdef::MissingPixelEvidence);
    }
    #[test]fn blank_needs_no_space_binding_and_numeric_advance_is_rejected(){
        let f=fixture(true);assert!(run(&f).is_ok());
        let mut f=fixture(true);let mut text=fs::read_to_string(&f.binding.file).unwrap();text.push_str(&format!("space_evidence_sha256\t{}\n","e".repeat(64)));fs::write(&f.binding.file,&text).unwrap();f.binding.sha256=sha256_hex(text.as_bytes());assert_eq!(run(&f).unwrap_err(),BadNotdef::Grammar);
        let mut f=fixture(false);let mut text=fs::read_to_string(&f.binding.file).unwrap();text.push_str("advance\t250\n");fs::write(&f.binding.file,&text).unwrap();f.binding.sha256=sha256_hex(text.as_bytes());assert_eq!(run(&f).unwrap_err(),BadNotdef::Grammar);
    }
    #[test]fn source_pin_and_form_hash_mismatch_refuse(){
        let f=fixture(false);fs::write(f.root.join("a"),[2]).unwrap();assert_eq!(run(&f).unwrap_err(),BadNotdef::ShaMismatch);
        let mut f=fixture(false);let text=fs::read_to_string(&f.binding.file).unwrap().replace(&pixel_form_sha256(2,1,&[0,255]).unwrap(),&"f".repeat(64));fs::write(&f.binding.file,&text).unwrap();f.binding.sha256=sha256_hex(text.as_bytes());assert_eq!(run(&f).unwrap_err(),BadNotdef::AmbiguousPixelCandidate);
    }
    fn large_population(blank:bool,n:usize)->Fixture {
        let mut f=fixture(blank);
        f.population.clear();
        let pixel=if blank{255}else{0};
        let pin=sha256_hex(&[pixel]);
        let kind=if blank{"blank-cell"}else{"repeated-form"};
        let hash=pixel_form_sha256(2,1,&[pixel,255]).unwrap();
        let mut text=format!("kni-pixel-notdef-evidence\tv3\nkind\t{kind}\nstyle\tT\nframe\tf\nscale\t2\nink_model\t{PIXEL_INK_MODEL}\ncapture_sha256\t{}\npixel_form_sha256\t{hash}\nselected\ta\t{pin}\n","c".repeat(64));
        for i in 0..n {
            let cp=65+u32::try_from(i).unwrap();
            let name=if i==0{"a".to_string()}else{format!("tile-{i}")};
            fs::write(f.root.join(&name),[pixel]).unwrap();
            f.population.insert(cp,(f.root.join(&name),pin.clone()));
            text.push_str(&format!("pixel_source\t{cp:x}\t{kind}\t{name}\t{pin}\n"));
        }
        fs::write(&f.binding.file,&text).unwrap();
        f.binding.sha256=sha256_hex(text.as_bytes());
        f
    }
    fn streaming_limits(f:&Fixture)->ValidationLimits {
        // Enough for the retained evidence bytes/index plus one tile, never 478 tile payloads.
        let record_len=usize::try_from(fs::metadata(&f.binding.file).unwrap().len()).unwrap();
        let metadata_allowance=record_len*4+128+f.population.len()*256;
        ValidationLimits{image:Limits{max_input_bytes:1<<20,max_pixels:64,max_working_bytes:1024},
            max_record_bytes:1<<20,max_record_rows:1024,max_witnesses:1024,
            max_aggregate_working_bytes:metadata_allowance+1024}
    }
    #[test]fn stream_478_repeated_and_blank_tiles_decode_exactly_once_each() {
        for blank in [false,true] {
            let f=large_population(blank,478);
            let scale=ScaleContext::from_convention("T","synthetic-unit",2.0,1000.0,"T","f").unwrap();
            let state=load(&f.binding,&f.population,&scale,&f.root,streaming_limits(&f),&f.decoder).unwrap();
            assert_eq!(f.decoder.calls.get(),478);
            assert!(matches!(state,DetectionState::PixelEvidence{sources,..}if sources.len()==478));
        }
    }
    #[test]fn stream_last_tile_pin_failure_is_not_skipped() {
        let f=large_population(false,478);
        let (_, (path,_))=f.population.iter().next_back().unwrap();
        fs::write(path,[99]).unwrap();
        let scale=ScaleContext::from_convention("T","synthetic-unit",2.0,1000.0,"T","f").unwrap();
        assert_eq!(load(&f.binding,&f.population,&scale,&f.root,streaming_limits(&f),&f.decoder).unwrap_err(),BadNotdef::ShaMismatch);
        assert_eq!(f.decoder.calls.get(),477);
    }
    #[test]fn stream_per_tile_pixel_and_working_limits_still_refuse() {
        let f=large_population(false,3);
        let scale=ScaleContext::from_convention("T","synthetic-unit",2.0,1000.0,"T","f").unwrap();
        let mut limits=streaming_limits(&f);limits.image.max_pixels=1;
        assert_eq!(load(&f.binding,&f.population,&scale,&f.root,limits,&f.decoder).unwrap_err(),BadNotdef::ResourceLimit);
        let mut limits=streaming_limits(&f);limits.image.max_working_bytes=128;
        assert_eq!(load(&f.binding,&f.population,&scale,&f.root,limits,&f.decoder).unwrap_err(),BadNotdef::ResourceLimit);
    }
    #[test]fn stream_per_tile_input_limit_still_refuses_on_last_tile() {
        let mut f=large_population(false,478);
        let (_, (path,pin))=f.population.iter_mut().next_back().unwrap();
        let bytes=vec![0; (1<<20)+1];fs::write(path,&bytes).unwrap();*pin=sha256_hex(&bytes);
        let scale=ScaleContext::from_convention("T","synthetic-unit",2.0,1000.0,"T","f").unwrap();
        assert_eq!(load(&f.binding,&f.population,&scale,&f.root,streaming_limits(&f),&f.decoder).unwrap_err(),BadNotdef::ResourceLimit);
        assert_eq!(f.decoder.calls.get(),477);
    }

    fn sizes_to_groups(sizes: &[usize]) -> BTreeMap<String, Vec<u32>> {
        let mut groups = BTreeMap::new();
        let mut cp = 1u32;
        for (i, &n) in sizes.iter().enumerate() {
            let cps: Vec<u32> = (0..n).map(|_| { let v = cp; cp += 1; v }).collect();
            groups.insert(format!("hash{i}"), cps);
        }
        groups
    }

    #[test]
    fn dominance_gap_flags_the_dominant_repeated_group() {
        // Gapped distribution: 263-slot class against 2+2+2 repeated rest -
        // the split is the distribution's own, no constant.
        let groups = sizes_to_groups(&[263, 2, 2, 2, 1, 1, 1]);
        assert_eq!(dominant_placeholder(&groups), Some(&"hash0".to_string()));
    }

    #[test]
    fn gapless_distribution_has_no_placeholder_class() {
        // Largest repeated group does not exceed the combined rest.
        let groups = sizes_to_groups(&[3, 2, 2]);
        assert_eq!(dominant_placeholder(&groups), None);
        // Tie at the top cannot dominate.
        let groups = sizes_to_groups(&[5, 5, 1]);
        assert_eq!(dominant_placeholder(&groups), None);
        // Singletons alone repeat nothing.
        let groups = sizes_to_groups(&[1, 1, 1]);
        assert_eq!(dominant_placeholder(&groups), None);
        // A single repeated class dominates the empty rest.
        let groups = sizes_to_groups(&[2, 1]);
        assert_eq!(dominant_placeholder(&groups), Some(&"hash0".to_string()));
    }

}
