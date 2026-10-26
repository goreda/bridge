//! Source kerning pair-image INGESTION layer (inventory + decode + ink-extent measurement).
//!
//! Scope, stated honestly: this is the source ingestion layer only. It reads the actual member list of one
//! `<Family>/<Style>/kerning/` folder, parses the real file-name grammar, pins every image by sha256, decodes it
//! with the bounded PNG decoder and measures the ink extent of the rendered pair. It does NOT produce kern values:
//! turning a pair image into a target distance needs the KNI-generated outlines of the two glyphs (template offset
//! against this image) and the old kernband target/training layer, which is not in this tree. Nothing here is
//! copied from a source font's kern table, and no value is invented.
//!
//! File-name grammar (checked against all 4464 kerning member names of the hub's pair-source inventory):
//!   `<index:5 digits>__<CP>_<CP>[_<CP>...]__<sha256-prefix:12 hex>.png`
//! Two codepoints = a PAIR image; 3+ codepoints = a kerning STRING image (e.g. 8x repeated glyph, `f . ”`), kept as its own
//! kind and never treated as a pair. The same index/sequence may occur with several different images (distinct sha):
//! all are resolved by `resolve_roles`: identical content = alias (deduplicated with a receipt), different content = AmbiguousRole refusal; never first-wins. The 12-hex tail must equal the first 12 hex digits
//! of the file's own sha256. Any other name, a sha mismatch, a non-PNG or non-regular member is a typed refusal.
use kni_core::capture::DecodeLimits;
use kni_core::cff_reader::sha256_hex;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KernPairError {
    Io(String),
    BadName(String),
    /// Same role (codepoint sequence) with DIFFERENT image content: the source does not determine which one is the evidence.
    AmbiguousRole { seq: Vec<u32>, sha256: Vec<String> },
    ExtensionSignatureMismatch(String),
    ShaMismatch { file: String, name_prefix: String, actual: String },
    Decode { file: String, why: String },
    NoInk(String),
    TooManyMembers(usize),
    OverBudget(String),
    NoMem(String),
    /// Same image content under two DIFFERENT roles: the name does not say what the image is.
    ContentConflict { sha256: String, seqs: Vec<Vec<u32>> },
    NotRegularFile(String),
}

/// One real member of the kerning folder (pinned by content).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KernImageEntry {
    index: u32,
    /// Codepoint sequence from the name (len 2 = pair, len >= 3 = string).
    seq: Vec<u32>,
    sha256: String,
    path: PathBuf,
    ext: ImageExt,
}
impl KernImageEntry {
    pub fn index(&self) -> u32 { self.index }
    pub fn seq(&self) -> &[u32] { &self.seq }
    pub fn sha256(&self) -> &str { &self.sha256 }
    pub fn path(&self) -> &Path { &self.path }
    pub fn ext(&self) -> ImageExt { self.ext }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageExt { Png, Jpg, Jpeg }

/// Hard budget on members read from one folder; a larger folder is refused, never truncated.
/// Longest accepted codepoint sequence in a name.
pub const MAX_SEQ: usize = 16;
pub const MAX_KERN_IMAGES: usize = 20_000;

/// Bounded read: at most `cap` bytes. The buffer is reserved FALLIBLY (typed NoMem) for min(cap, file length)+1 before reading;
/// reads cap+1 (saturating) so growth past the cap is detected. Never reads unbounded.
pub fn read_capped(path: &Path, cap: u64) -> Result<Vec<u8>, KernPairError> {
    use std::io::Read;
    let name = path.display().to_string();
    let f = std::fs::File::open(path).map_err(|e| KernPairError::Io(format!("{name}: {e}")))?;
    let flen = f.metadata().map_err(|e| KernPairError::Io(format!("{name}: {e}")))?.len();
    if flen > cap { return Err(KernPairError::OverBudget(format!("{name}: {flen} bytes exceeds {cap}"))); }
    let reserve = usize::try_from(flen.min(cap).saturating_add(1)).map_err(|_| KernPairError::NoMem(name.clone()))?;
    let mut v: Vec<u8> = Vec::new();
    v.try_reserve_exact(reserve).map_err(|_| KernPairError::NoMem(name.clone()))?;
    f.take(cap.saturating_add(1)).read_to_end(&mut v).map_err(|e| KernPairError::Io(format!("{name}: {e}")))?;
    if v.len() as u64 > cap { return Err(KernPairError::OverBudget(format!("{name}: exceeds {cap} bytes"))); }
    Ok(v)
}

pub fn parse_member_name(name: &str) -> Result<(u32, Vec<u32>, String), KernPairError> {
    let bad = || KernPairError::BadName(name.to_string());
    let stem = [".png", ".jpeg", ".jpg"].iter().find_map(|e| name.strip_suffix(e)).ok_or_else(bad)?;
    let parts: Vec<&str> = stem.split("__").collect();
    if parts.len() != 3 { return Err(bad()); }
    let (idx, cps, sha) = (parts[0], parts[1], parts[2]);
    if idx.len() != 5 || !idx.bytes().all(|b| b.is_ascii_digit()) { return Err(bad()); }
    if sha.len() != 12 || !sha.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) { return Err(bad()); }
    let cp: Vec<&str> = cps.split('_').collect();
    if cp.len() < 2 || cp.len() > MAX_SEQ { return Err(bad()); }
    let hex = |s: &str| -> Result<u32, KernPairError> {
        if s.len() < 4 || s.len() > 6 || !s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'A'..=b'F')) { return Err(bad()); }
        let v = u32::from_str_radix(s, 16).map_err(|_| bad())?;
        if v > 0x10FFFF || (0xD800..=0xDFFF).contains(&v) { return Err(bad()); }
        Ok(v)
    };
    Ok((idx.parse().map_err(|_| bad())?, cp.iter().map(|c| hex(c)).collect::<Result<Vec<_>, _>>()?, sha.to_string()))
}

/// Inventory over the ACTUAL directory members (sorted by file name). Every member must be a regular, well-named,
/// sha-consistent PNG; the first violation refuses the whole inventory (no partial list, no skipping).
#[derive(Debug, Clone, Copy)]
pub struct InventoryBudget { pub max_members: usize, pub max_member_bytes: u64, pub max_total_bytes: u64 }

pub fn inventory(dir: &Path, b: &InventoryBudget) -> Result<Vec<KernImageEntry>, KernPairError> {
    let rd = std::fs::read_dir(dir).map_err(|e| KernPairError::Io(format!("{}: {e}", dir.display())))?;
    let mut names: Vec<String> = Vec::new();
    for e in rd {
        let e = e.map_err(|e| KernPairError::Io(e.to_string()))?;
        let n = e.file_name().to_string_lossy().into_owned();
        let md = std::fs::symlink_metadata(e.path()).map_err(|e| KernPairError::Io(e.to_string()))?;
        if !md.is_file() { return Err(KernPairError::NotRegularFile(n)); }
        names.push(n);
        if names.len() > b.max_members { return Err(KernPairError::TooManyMembers(names.len())); }
    }
    names.sort();
    let mut total: u64 = 0;
    let mut out = Vec::with_capacity(names.len());
    for n in names {
        let (index, seq, prefix) = parse_member_name(&n)?;
        let path = dir.join(&n);
        // size is taken from the bytes actually read (cap-bounded), not from metadata
        // cap = min(member cap, remaining total budget): no read can exceed what is left
        let remaining = b.max_total_bytes.saturating_sub(total);
        let bytes = read_capped(&path, b.max_member_bytes.min(remaining))?;
        total = total.checked_add(bytes.len() as u64).ok_or_else(|| KernPairError::OverBudget("total bytes overflow".into()))?;
        if total > b.max_total_bytes { return Err(KernPairError::OverBudget("total bytes".into())); }
        let sha = sha256_hex(&bytes);
        if !sha.starts_with(&prefix) { return Err(KernPairError::ShaMismatch { file: n, name_prefix: prefix, actual: sha }); }
        let ext = if n.ends_with(".png") { ImageExt::Png } else if n.ends_with(".jpeg") { ImageExt::Jpeg } else { ImageExt::Jpg };
        // same sha under two names is an ALIAS (kept here, resolved with a receipt by `resolve_roles`)
        out.push(KernImageEntry { index, seq, sha256: sha, path, ext });
    }
    Ok(out)
}

/// Ink extent of one pair image. `ink_threshold` is an explicit caller parameter (pixel < threshold is ink): no hidden default.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InkExtent {
    pub width: usize,
    pub height: usize,
    pub x_min: usize,
    pub x_max: usize,
    pub y_min: usize,
    pub y_max: usize,
    /// Inclusive column runs that contain ink. 1 run = the two glyphs touch/overlap in projection (gap not directly readable);
    /// 2+ runs = visible white gaps (gap widths available between runs).
    pub column_runs: Vec<(usize, usize)>,
    pub ink_pixels: u64,
}

impl KernImageEntry {
    /// Some((left,right)) only for a 2-codepoint PAIR image.
    pub fn pair(&self) -> Option<(u32, u32)> { if self.seq.len() == 2 { Some((self.seq[0], self.seq[1])) } else { None } }
}

pub fn measure_ink(entry: &KernImageEntry, ink_threshold: u8, max_bytes: u64, limits: &DecodeLimits, jpeg: kni_core::jpeg_source::Limits) -> Result<InkExtent, KernPairError> {
    let file = entry.path.display().to_string();
    let bytes = read_capped(&entry.path, max_bytes)?; // cap+1 read, then re-pinned by sha below
    if sha256_hex(&bytes) != entry.sha256 {
        return Err(KernPairError::ShaMismatch { file, name_prefix: entry.sha256.get(..12).unwrap_or("").into(), actual: sha256_hex(&bytes) });
    }
    let is_png = bytes.starts_with(b"\x89PNG\r\n\x1a\n");
    if is_png != (entry.ext == ImageExt::Png) { return Err(KernPairError::ExtensionSignatureMismatch(file)); }
    let d = kni_core::capture_dispatch::decode_source(&bytes, limits, jpeg).map_err(|e| KernPairError::Decode { file: file.clone(), why: format!("{e:?}") })?;
    let (w, h, px) = (d.width, d.height, d.gray);
    measure_gray(w, h, &px, ink_threshold).ok_or(KernPairError::NoInk(file))
}

pub fn measure_gray(w: usize, h: usize, px: &[u8], thr: u8) -> Option<InkExtent> {
    if w == 0 || h == 0 || px.len() != w * h { return None; }
    let (mut xmin, mut xmax, mut ymin, mut ymax, mut n) = (usize::MAX, 0usize, usize::MAX, 0usize, 0u64);
    let mut cols = vec![false; w];
    for y in 0..h { for x in 0..w { if px[y * w + x] < thr { cols[x] = true; n += 1; xmin = xmin.min(x); xmax = xmax.max(x); ymin = ymin.min(y); ymax = ymax.max(y); } } }
    if n == 0 { return None; }
    let (mut runs, mut s) = (Vec::new(), None);
    for (x, &c) in cols.iter().enumerate() {
        match (c, s) { (true, None) => s = Some(x), (false, Some(a)) => { runs.push((a, x - 1)); s = None; } _ => {} }
    }
    if let Some(a) = s { runs.push((a, w - 1)); }
    Some(InkExtent { width: w, height: h, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax, column_runs: runs, ink_pixels: n })
}

/// Resolved evidence per role (= codepoint sequence within one Family/Style folder) plus the alias receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Resolved {
    pub roles: std::collections::BTreeMap<Vec<u32>, KernImageEntry>,
    /// (seq, kept index, dropped index, sha256): identical content under another name; deduplicated, receipted.
    pub aliases: Vec<(Vec<u32>, u32, u32, String)>,
}

/// Same sequence + identical sha => alias (lowest index kept, the rest receipted). Same sequence + different sha => AmbiguousRole
/// (typed refusal for the whole resolution; no first-wins, no newest-wins).
pub fn resolve_roles(entries: &[KernImageEntry]) -> Result<Resolved, KernPairError> {
    let mut by_sha: std::collections::BTreeMap<&str, BTreeSet<Vec<u32>>> = Default::default();
    for e in entries { by_sha.entry(e.sha256.as_str()).or_default().insert(e.seq.clone()); }
    if let Some((sha, seqs)) = by_sha.into_iter().find(|(_, s)| s.len() > 1) { return Err(KernPairError::ContentConflict { sha256: sha.to_string(), seqs: seqs.into_iter().collect() }); }
    let mut by: std::collections::BTreeMap<Vec<u32>, Vec<&KernImageEntry>> = Default::default();
    for e in entries { by.entry(e.seq.clone()).or_default().push(e); }
    let (mut roles, mut aliases) = (std::collections::BTreeMap::new(), Vec::new());
    for (seq, mut v) in by {
        v.sort_by_key(|e| (e.index, e.path.clone()));
        let shas: BTreeSet<&String> = v.iter().map(|e| &e.sha256).collect();
        if shas.len() != 1 { return Err(KernPairError::AmbiguousRole { seq, sha256: shas.into_iter().cloned().collect() }); }
        for dup in &v[1..] { aliases.push((seq.clone(), v[0].index, dup.index, dup.sha256.clone())); }
        roles.insert(seq, v[0].clone());
    }
    Ok(Resolved { roles, aliases })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn grammar_matches_real_member_names_and_refuses_the_rest() {
        let (i, q, s) = parse_member_name("00192__0044_005F__1ad592aafb16.png").unwrap();
        assert_eq!((i, q, s.as_str()), (192, vec![0x44, 0x5F], "1ad592aafb16"));
        assert_eq!(parse_member_name("00204__0042_2018__b75412bdc84a.png").unwrap().1[1], 0x2018);
        assert_eq!(parse_member_name("00187__0066_002E_201D__4909591798f3.png").unwrap().1.len(), 3); // real string member
        assert_eq!(parse_member_name("00000__0048_0048_0048_0048_0048_0048_0048_0048__7d7e7565f2a3.png").unwrap().1.len(), 8);
        for bad in ["00192__0044__1ad592aafb16.png", "192__0044_005F__1ad592aafb16.png",
            "00192__0044_005F__1AD592AAFB16.png", "00192__0044_005F__1ad592aafb1.png", "00192__d044_005F__1ad592aafb16.png",
             "00192__D800_005F__1ad592aafb16.png"] {
            assert!(matches!(parse_member_name(bad), Err(KernPairError::BadName(_))), "{bad}");
        }
    }
    #[test]
    fn roles_alias_dedup_with_receipt_and_ambiguity_is_typed() {
        let mk = |index: u32, seq: Vec<u32>, sha: &str| KernImageEntry { index, seq, sha256: sha.into(), path: PathBuf::from(format!("{index}.png")), ext: ImageExt::Png };
        let r = resolve_roles(&[mk(5, vec![1, 2], "aa"), mk(3, vec![1, 2], "aa"), mk(4, vec![7, 8, 9], "bb")]).unwrap();
        assert_eq!(r.roles.len(), 2); assert_eq!(r.roles[&vec![1, 2]].index, 3);
        assert_eq!(r.aliases, vec![(vec![1, 2], 3, 5, "aa".to_string())]);
        assert_eq!(resolve_roles(&[mk(1, vec![1, 2], "aa"), mk(2, vec![1, 2], "bb")]).unwrap_err(), KernPairError::AmbiguousRole { seq: vec![1, 2], sha256: vec!["aa".into(), "bb".into()] });
    }
    #[test]
    fn jpeg_names_parse_and_signature_must_match_extension() {
        assert!(parse_member_name("00001__0041_0056__0123456789ab.jpg").is_ok() && parse_member_name("00001__0041_0056__0123456789ab.jpeg").is_ok());
        assert!(parse_member_name("00001__0041_0056__0123456789ab.JPG").is_err() && parse_member_name("00001__0041_0056__0123456789ab.gif").is_err());
        let d = tmp("sig"); let body = b"\xff\xd8not-really";
        put_ext(&d, 1, body, "png");
        let inv = inventory(&d, &ib()).unwrap();
        let lim = DecodeLimits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 24 };
        let j = kni_core::jpeg_source::Limits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 24 };
        assert!(matches!(measure_ink(&inv[0], 128, 1 << 20, &lim, j), Err(KernPairError::ExtensionSignatureMismatch(_))));
        let _ = std::fs::remove_dir_all(d);
    }
    fn put_ext(d: &Path, idx: u32, body: &[u8], ext: &str) {
        let sha = sha256_hex(body);
        std::fs::write(d.join(format!("{idx:05}__0041_0056__{}.{ext}", &sha[..12])), body).unwrap();
    }
    #[test]
    fn ink_extent_and_runs() {
        let (w, h) = (10, 4); let mut px = vec![255u8; w * h];
        for y in 1..3 { for x in [2usize, 3, 6] { px[y * w + x] = 0; } }
        let e = measure_gray(w, h, &px, 128).unwrap();
        assert_eq!((e.x_min, e.x_max, e.y_min, e.y_max, e.ink_pixels), (2, 6, 1, 2, 6));
        assert_eq!(e.column_runs, vec![(2, 3), (6, 6)]);
        assert!(measure_gray(w, h, &vec![255; w * h], 128).is_none() && measure_gray(w, h, &px[..5], 128).is_none());
    }
    fn inv_path(d: &Path) -> PathBuf { std::fs::read_dir(d).unwrap().next().unwrap().unwrap().path() }
    fn ib() -> InventoryBudget { InventoryBudget { max_members: 100, max_member_bytes: 1 << 16, max_total_bytes: 1 << 20 } }
    fn tmp(tag: &str) -> PathBuf { let d = std::env::temp_dir().join(format!("kp-{tag}-{}", std::process::id())); let _ = std::fs::remove_dir_all(&d); std::fs::create_dir_all(&d).unwrap(); d }
    fn put(d: &Path, idx: u32, l: u32, r: u32, body: &[u8], good_sha: bool) {
        let sha = sha256_hex(body); let p = if good_sha { sha[..12].to_string() } else { "000000000000".into() };
        std::fs::write(d.join(format!("{idx:05}__{l:04X}_{r:04X}__{p}.png")), body).unwrap();
    }
    #[test]
    fn inventory_pins_members_and_refuses_violations_whole() {
        let d = tmp("ok"); put(&d, 2, 0x44, 0x5F, b"aaa", true); put(&d, 1, 0x46, 0x5F, b"bbb", true);
        let inv = inventory(&d, &ib()).unwrap();
        assert_eq!(inv.iter().map(|e| (e.index, e.pair())).collect::<Vec<_>>(), vec![(1, Some((0x46, 0x5F))), (2, Some((0x44, 0x5F)))]);
        assert_eq!(inv[0].sha256, sha256_hex(b"bbb"));
        put(&d, 3, 0x44, 0x5F, b"ccc", true); // same pair, different image: kept as separate evidence
        assert_eq!(inventory(&d, &ib()).unwrap().len(), 3);
        let d2 = tmp("sha"); put(&d2, 1, 0x41, 0x56, b"x", false);
        assert!(matches!(inventory(&d2, &ib()).unwrap_err(), KernPairError::ShaMismatch { .. }));
        let d3 = tmp("junk"); put(&d3, 1, 0x41, 0x56, b"x", true); std::fs::write(d3.join("notes.txt"), b"x").unwrap();
        assert!(matches!(inventory(&d3, &ib()).unwrap_err(), KernPairError::BadName(_)));
        let d4 = tmp("idx"); put(&d4, 1, 0x41, 0x56, b"x", true); put(&d4, 1, 0x41, 0x57, b"y", true);
        assert_eq!(inventory(&d4, &ib()).unwrap().len(), 2);
        let d6 = tmp("max"); put(&d6, 1, 0x41, 0x56, b"x", true);
        assert_eq!(inventory(&d6, &InventoryBudget { max_members: 5, max_member_bytes: u64::MAX, max_total_bytes: u64::MAX }).unwrap().len(), 1); // cap+1 saturates, no overflow
        assert!(matches!(read_capped(&inv_path(&d6), 0), Err(KernPairError::OverBudget(_))));
        let _ = std::fs::remove_dir_all(&d6);
        let d5 = tmp("cap"); put(&d5, 1, 0x41, 0x56, &[7u8; 100], true);
        assert!(matches!(inventory(&d5, &InventoryBudget { max_members: 5, max_member_bytes: 99, max_total_bytes: 1 << 20 }), Err(KernPairError::OverBudget(_))));
        assert!(matches!(inventory(&d5, &InventoryBudget { max_members: 5, max_member_bytes: 1000, max_total_bytes: 50 }), Err(KernPairError::OverBudget(_))));
        assert!(matches!(inventory(&d5, &InventoryBudget { max_members: 0, max_member_bytes: 1000, max_total_bytes: 1000 }), Err(KernPairError::TooManyMembers(_))));
        let alias = KernImageEntry { index: 9, seq: vec![1, 2], sha256: "zz".into(), path: "a".into(), ext: ImageExt::Png };
        let other = KernImageEntry { index: 8, seq: vec![3, 4], sha256: "zz".into(), path: "b".into(), ext: ImageExt::Png };
        assert!(matches!(resolve_roles(&[alias, other]), Err(KernPairError::ContentConflict { .. })));
        for x in [d, d2, d3, d4, d5] { let _ = std::fs::remove_dir_all(x); }
    }
}
