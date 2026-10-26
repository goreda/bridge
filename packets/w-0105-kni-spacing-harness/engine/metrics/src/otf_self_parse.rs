//! Minimal OTF (sfnt) table-walk self-parse integrity gate.
//!
//! The engine's exported bytes are re-parsed through the table directory
//! before they ship: every directory record is walked, bounds-checked and
//! checksummed, and the whole-font checksum is validated against the head
//! table's checkSumAdjustment. A byte flipped anywhere in the file moves
//! at least one of these sums, so the gate rejects single-byte corruption
//! independent of where it landed.
//!
//! This is a library lane per the always-output rule: it keeps an honest
//! refusal type. Warn-export vs strict refusal is the pipeline runner's
//! decision, not this module's.
//!
//! CONVENTION: every constant below is an OpenType binary-format constant
//! (scaler types, magic numbers, checksum arithmetic, directory geometry),
//! not an artistic or tuned threshold.

/// CONVENTION: spec-listed sfnt scaler types (TrueType 1.0, CFF 'OTTO',
/// Apple 'true', Apple legacy 'typ1'), OpenType spec, sfnt header.
const SCALER_TYPES: [u32; 4] = [0x0001_0000, 0x4F54_544F, 0x7472_7565, 0x7479_7031];
/// CONVENTION: head.magicNumber, OpenType spec.
const HEAD_MAGIC: u32 = 0x5F0F_3CF5;
/// CONVENTION: whole-font checksum target with head.checkSumAdjustment in
/// place, OpenType spec.
const GLOBAL_CHECKSUM_TARGET: u32 = 0xB1B0_AFBA;
/// CONVENTION: sfnt header is 12 bytes; one directory record is 16 bytes;
/// tables and checksum words are 4-byte aligned. Binary format geometry.
const HEADER_LEN: usize = 12;
const RECORD_LEN: usize = 16;
const WORD: usize = 4;
/// CONVENTION: head.checkSumAdjustment sits at head bytes 8..12, the magic
/// at 12..16; a head shorter than 16 bytes cannot self-validate.
const HEAD_MIN_LEN: u32 = 16;

/// One walked directory record, byte-identical to the shipped file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TableRecord {
    pub tag: [u8; 4],
    pub checksum: u32,
    pub offset: u32,
    pub length: u32,
}

/// Successful walk: the scaler type plus every directory record in file order.
#[derive(Clone, Debug)]
pub struct IntegrityReport {
    pub scaler: u32,
    pub tables: Vec<TableRecord>,
}

/// Typed finding with a stable code; the runner maps codes to warnings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IntegrityFinding {
    pub code: &'static str,
    pub detail: String,
}

fn finding(code: &'static str, detail: String) -> IntegrityFinding {
    IntegrityFinding { code, detail: detail }
}

fn tag_text(tag: &[u8; 4]) -> String {
    tag.iter().map(|b| if b.is_ascii_graphic() || *b == b' ' { *b as char } else { '?' }).collect()
}

fn be_u32(bytes: &[u8], at: usize) -> u32 {
    u32::from_be_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]])
}

fn be_u16(bytes: &[u8], at: usize) -> u16 {
    u16::from_be_bytes([bytes[at], bytes[at + 1]])
}

/// Padded-word checksum over `slice` (OpenType table checksum arithmetic):
/// big-endian u32 words, zero-padded tail, wrapping sum. `zeroed` names an
/// absolute byte range forced to zero (the head adjustment field).
fn checksum_range(bytes: &[u8], start: usize, end: usize, zeroed: Option<(usize, usize)>) -> u32 {
    let mut sum = 0u32;
    let mut at = start;
    while at < end {
        let mut word = [0u8; WORD];
        for (slot, abs) in word.iter_mut().zip(at..(at + WORD).min(end)) {
            let masked = zeroed.map_or(false, |(zs, ze)| abs >= zs && abs < ze);
            *slot = if masked { 0 } else { bytes[abs] };
        }
        sum = sum.wrapping_add(u32::from_be_bytes(word));
        at += WORD;
    }
    sum
}

/// Walk and validate the table directory, then every table checksum, then
/// the whole-font checksum. Any finding rejects; Ok carries the walked
/// directory. No value is ever repaired or invented here.
pub fn verify(bytes: &[u8]) -> Result<IntegrityReport, Vec<IntegrityFinding>> {
    // Phase 1: header. The directory cannot be trusted until this passes.
    let mut findings = Vec::new();
    if bytes.len() < HEADER_LEN {
        return Err(vec![finding("OTFSP-TRUNCATED-HEADER", format!("file is {} bytes, header needs {}", bytes.len(), HEADER_LEN))]);
    }
    let scaler = be_u32(bytes, 0);
    if !SCALER_TYPES.contains(&scaler) {
        findings.push(finding("OTFSP-UNSUPPORTED-SCALER", format!("scaler type 0x{scaler:08x} is not a spec-listed sfnt scaler")));
    }
    let num_tables = be_u16(bytes, 4) as usize;
    if num_tables == 0 {
        findings.push(finding("OTFSP-ZERO-TABLES", "numTables is 0".into()));
    }
    let dir_end = HEADER_LEN.saturating_add(num_tables.saturating_mul(RECORD_LEN));
    if dir_end > bytes.len() {
        findings.push(finding("OTFSP-DIRECTORY-OVERFLOW", format!("{} records need {} bytes, file is {}", num_tables, dir_end, bytes.len())));
    }
    // CONVENTION: searchRange/entrySelector/rangeShift are functions of
    // numTables fixed by the spec (max power of two <= numTables, times 16).
    let mut pow2 = 1usize;
    let mut selector = 0u16;
    while pow2 * 2 <= num_tables {
        pow2 *= 2;
        selector += 1;
    }
    let search_range = (pow2 * RECORD_LEN) as u16;
    let range_shift = (num_tables * RECORD_LEN) as u16 - search_range;
    if be_u16(bytes, 6) != search_range || be_u16(bytes, 8) != selector || be_u16(bytes, 10) != range_shift {
        findings.push(finding("OTFSP-SEARCH-PARAMS", format!("header carries searchRange={} entrySelector={} rangeShift={}, spec derivation gives {}/{}/{}", be_u16(bytes, 6), be_u16(bytes, 8), be_u16(bytes, 10), search_range, selector, range_shift)));
    }
    if !findings.is_empty() {
        return Err(findings);
    }

    // Phase 2: directory walk, structural findings only.
    let mut tables = Vec::with_capacity(num_tables);
    for index in 0..num_tables {
        let at = HEADER_LEN + index * RECORD_LEN;
        tables.push(TableRecord {
            tag: [bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]],
            checksum: be_u32(bytes, at + 4),
            offset: be_u32(bytes, at + 8),
            length: be_u32(bytes, at + 12),
        });
    }
    for (index, rec) in tables.iter().enumerate() {
        let name = tag_text(&rec.tag);
        if tables[..index].iter().any(|prior| prior.tag == rec.tag) {
            findings.push(finding("OTFSP-DUPLICATE-TAG", format!("table '{name}' appears twice")));
        }
        if (rec.offset as usize) < dir_end {
            findings.push(finding("OTFSP-TABLE-OVERLAPS-DIRECTORY", format!("table '{name}' starts at {}, directory ends at {}", rec.offset, dir_end)));
        }
        if rec.offset % WORD as u32 != 0 {
            findings.push(finding("OTFSP-UNALIGNED-OFFSET", format!("table '{name}' offset {} is not 4-byte aligned", rec.offset)));
        }
        let end = rec.offset as u64 + rec.length as u64;
        if end > bytes.len() as u64 {
            findings.push(finding("OTFSP-TABLE-OUT-OF-BOUNDS", format!("table '{name}' spans {}..{}, file is {} bytes", rec.offset, end, bytes.len())));
        }
    }
    if !findings.is_empty() {
        return Err(findings);
    }

    // Phase 3: checksums. head's adjustment field is zeroed for its own
    // table checksum; the whole-font sum must hit the spec target.
    let head: Vec<usize> = tables.iter().enumerate().filter(|(_, rec)| &rec.tag == b"head").map(|(index, _)| index).collect();
    if head.is_empty() {
        findings.push(finding("OTFSP-MISSING-HEAD", "no 'head' table in the directory".into()));
    }
    for (index, rec) in tables.iter().enumerate() {
        let adjustment = if head.first() == Some(&index) {
            if rec.length < HEAD_MIN_LEN {
                findings.push(finding("OTFSP-HEAD-TOO-SHORT", format!("'head' is {} bytes, magic and checkSumAdjustment need {}", rec.length, HEAD_MIN_LEN)));
                None
            } else {
                let base = rec.offset as usize;
                if be_u32(bytes, base + 12) != HEAD_MAGIC {
                    findings.push(finding("OTFSP-HEAD-MAGIC", format!("head magic is 0x{:08x}, spec fixes 0x{HEAD_MAGIC:08x}", be_u32(bytes, base + 12))));
                }
                Some((base + 8, base + 12))
            }
        } else {
            None
        };
        let start = rec.offset as usize;
        let end = start + rec.length as usize;
        let actual = checksum_range(bytes, start, end, adjustment);
        if actual != rec.checksum {
            findings.push(finding("OTFSP-TABLE-CHECKSUM", format!("table '{}' records checksum 0x{:08x}, walk computes 0x{actual:08x}", tag_text(&rec.tag), rec.checksum)));
        }
    }
    let actual_global = checksum_range(bytes, 0, bytes.len(), None);
    if actual_global != GLOBAL_CHECKSUM_TARGET {
        findings.push(finding("OTFSP-GLOBAL-CHECKSUM", format!("whole-font checksum is 0x{actual_global:08x}, spec target 0x{GLOBAL_CHECKSUM_TARGET:08x}")));
    }
    if !findings.is_empty() {
        return Err(findings);
    }
    Ok(IntegrityReport { scaler, tables })
}
