//! Minimal final-OTF reader for the master kit: table directory, head,
//! hhea, hmtx, OS/2, name, cmap, maxp, post, and CFF outlines (via
//! kni_core::cff_reader). Every fact comes from the shipped bytes; unknown
//! or out-of-range structure is a typed error.

use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_core::native_font::NativeFontInput;
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata};

fn table<'a>(b: &'a [u8], tag: &[u8; 4]) -> Result<&'a [u8], String> {
    let n = u16::from_be_bytes([b[4], b[5]]) as usize;
    for i in 0..n {
        let o = 12 + 16 * i;
        if b.get(o..o + 4) == Some(tag) {
            let (off, len) = (u32::from_be_bytes(b[o + 8..o + 12].try_into().unwrap()) as usize, u32::from_be_bytes(b[o + 12..o + 16].try_into().unwrap()) as usize);
            return b.get(off..off + len).ok_or_else(|| format!("table {tag:?} out of range"));
        }
    }
    Err(format!("table {tag:?} missing"))
}
fn u16b(b: &[u8], o: usize) -> Result<u16, String> { b.get(o..o + 2).map(|v| u16::from_be_bytes([v[0], v[1]])).ok_or_else(|| "short table".to_string()) }
fn i16b(b: &[u8], o: usize) -> Result<i16, String> { Ok(u16b(b, o)? as i16) }
fn u32b(b: &[u8], o: usize) -> Result<u32, String> { b.get(o..o + 4).map(|v| u32::from_be_bytes(v.try_into().unwrap())).ok_or_else(|| "short table".to_string()) }

fn names(b: &[u8]) -> Result<Vec<NameRecord>, String> {
    let count = u16b(b, 2)? as usize;
    let base = u16b(b, 4)? as usize;
    let mut out = Vec::new();
    for i in 0..count {
        let o = 6 + 12 * i;
        let (platform, _enc, lang, id, len, off) = (u16b(b, o)?, u16b(b, o + 2)?, u16b(b, o + 4)?, u16b(b, o + 6)?, u16b(b, o + 8)? as usize, u16b(b, o + 10)? as usize);
        let raw = b.get(base + off..base + off + len).ok_or("name string out of range")?;
        let value = if platform == 3 || platform == 0 {
            if raw.len() % 2 != 0 { return Err("utf16 name odd length".into()); }
            String::from_utf16(&raw.chunks(2).map(|c| u16::from_be_bytes([c[0], c[1]])).collect::<Vec<_>>()).map_err(|_| "utf16 name invalid")?
        } else {
            raw.iter().map(|&c| c as char).collect()
        };
        out.push(NameRecord { language: lang, name_id: id, value });
    }
    Ok(out)
}

fn cmap(b: &[u8]) -> Result<Vec<(u32, u16)>, String> {
    let n = u16b(b, 2)? as usize;
    let mut chosen: Option<usize> = None;
    for i in 0..n {
        let o = 4 + 8 * i;
        let (platform, _enc, off) = (u16b(b, o)?, u16b(b, o + 2)?, u32b(b, o + 4)? as usize);
        let fmt = u16b(b, off)?;
        if fmt == 12 && platform == 3 { chosen = Some(off); break; }
        if fmt == 4 && platform == 3 && chosen.is_none() { chosen = Some(off); }
    }
    let off = chosen.ok_or("no usable cmap (need fmt 12 or 4, platform 3)")?;
    let mut out = Vec::new();
    if u16b(b, off)? == 12 {
        let groups = u32b(b, off + 12)? as usize;
        for g in 0..groups {
            let o = off + 16 + 12 * g;
            let (start, end, start_gid) = (u32b(b, o)?, u32b(b, o + 4)?, u32b(b, o + 8)?);
            for cp in start..=end {
                out.push((cp, u16::try_from(start_gid + (cp - start)).map_err(|_| "cmap gid overflow")?));
            }
        }
    } else {
        let seg_x2 = u16b(b, off + 6)? as usize;
        let segs = seg_x2 / 2;
        let end_o = off + 14;
        let start_o = end_o + seg_x2 + 2;
        let delta_o = start_o + seg_x2;
        let range_o = delta_o + seg_x2;
        for sgi in 0..segs {
            let (end, start, delta, ro) = (u16b(b, end_o + 2 * sgi)?, u16b(b, start_o + 2 * sgi)?, i16b(b, delta_o + 2 * sgi)? as i32, u16b(b, range_o + 2 * sgi)? as usize);
            if start == 0xFFFF && end == 0xFFFF { break; }
            for cp in start..=end {
                let gid = if ro == 0 {
                    ((cp as i32 + delta) & 0xFFFF) as u16
                } else {
                    let go = range_o + 2 * sgi + ro + 2 * (cp - start) as usize;
                    let g = u16b(b, go)?;
                    if g == 0 { 0 } else { ((g as i32 + delta) & 0xFFFF) as u16 }
                };
                if gid != 0 { out.push((cp as u32, gid)); }
            }
        }
    }
    Ok(out)
}

/// Read the shipped OTF into the kit's source-of-facts input.
pub fn read_otf(bytes: &[u8]) -> Result<(NativeFontInput, Vec<(u32, u16)>), String> {
    let head = table(bytes, b"head")?;
    let hhea = table(bytes, b"hhea")?;
    let maxp = table(bytes, b"maxp")?;
    let os2 = table(bytes, b"OS/2")?;
    let hmtx = table(bytes, b"hmtx")?;
    let post = table(bytes, b"post")?;
    let name = table(bytes, b"name")?;
    let cmap_t = table(bytes, b"cmap")?;
    let num_glyphs = u16b(maxp, 4)? as usize;
    let metric_count = u16b(hhea, 34)? as usize;
    let reader = CffReader::from_bytes(bytes, &sha256_hex(bytes)).map_err(|e| format!("cff read: {e:?}"))?;
    if reader.glyph_count() != num_glyphs { return Err(format!("maxp numGlyphs {num_glyphs} != CFF {}", reader.glyph_count())); }
    let mut glyphs = Vec::with_capacity(num_glyphs);
    let mut lsbs = Vec::with_capacity(num_glyphs);
    for gid in 0..num_glyphs {
        let (adv, lsb) = if gid < metric_count {
            (u16b(hmtx, 4 * gid)?, i16b(hmtx, 4 * gid + 2)?)
        } else {
            (u16b(hmtx, 4 * (metric_count - 1))?, i16b(hmtx, 4 * metric_count + 2 * (gid - metric_count))?)
        };
        let rg = reader.read_glyph(gid as u16).map_err(|e| format!("glyph {gid}: {e:?}"))?;
        let drawn = rg.drawn(String::new());
        glyphs.push(kni_core::cff_container::CffGlyph { name: String::new(), advance: adv, outline: drawn });
        lsbs.push(lsb);
    }
    let os2m = Os2Metadata {
        average_width: i16b(os2, 2)?, weight: u16b(os2, 4)?, width: u16b(os2, 6)?, embedding: u16b(os2, 8)?,
        subscript: [i16b(os2, 10)?, i16b(os2, 12)?, i16b(os2, 14)?, i16b(os2, 16)?],
        superscript: [i16b(os2, 18)?, i16b(os2, 20)?, i16b(os2, 22)?, i16b(os2, 24)?],
        strikeout: [i16b(os2, 26)?, i16b(os2, 28)?], family_class: i16b(os2, 30)?,
        panose: os2.get(32..42).ok_or("OS/2 short panose")?.try_into().unwrap(),
        unicode_ranges: [u32b(os2, 42)?, u32b(os2, 46)?, u32b(os2, 50)?, u32b(os2, 54)?],
        vendor: os2.get(58..62).ok_or("OS/2 short vendor")?.try_into().unwrap(),
        selection: u16b(os2, 62)?, first_char: u16b(os2, 64)?, last_char: u16b(os2, 66)?,
        typo: [i16b(os2, 68)?, i16b(os2, 70)?, i16b(os2, 72)?],
        win_ascent: u16b(os2, 74)?, win_descent: u16b(os2, 76)?,
        version: u16b(os2, 0)?, cap_height: if u16b(os2, 0)? >= 2 { i16b(os2, 88)? } else { 0 }, x_height: if u16b(os2, 0)? >= 2 { i16b(os2, 86)? } else { 0 },
    };
    let head_m = HeadMetadata {
        revision: u32b(head, 4)?, flags: u16b(head, 16)?, units_per_em: u16b(head, 18)?,
        created: head.get(20..28).map(|v| i64::from_be_bytes(v.try_into().unwrap())).unwrap_or(0),
        modified: head.get(28..36).map(|v| i64::from_be_bytes(v.try_into().unwrap())).unwrap_or(0),
        bounds: [i16b(head, 36)?, i16b(head, 38)?, i16b(head, 40)?, i16b(head, 42)?],
        mac_style: u16b(head, 44)?, lowest_ppem: u16b(head, 46)?,
    };
    let post_m = PostMetadata {
        italic_angle_fixed: u32b(post, 4)? as i32,
        underline_position: i16b(post, 8)?, underline_thickness: i16b(post, 10)?,
        fixed_pitch: u32b(post, 12)?, memory: [u32b(post, 16)?, u32b(post, 20)?, u32b(post, 24)?, u32b(post, 28)?],
    };
    let input = NativeFontInput {
        postscript_name: names(name)?.iter().find(|r| r.name_id == 6).map(|r| r.value.clone()).unwrap_or_default(),
        glyphs,
        left_side_bearings: lsbs,
        mapping: cmap(cmap_t)?,
        head: head_m,
        hhea: HheaMetadata { ascender: i16b(hhea, 4)?, descender: i16b(hhea, 6)?, line_gap: i16b(hhea, 8)?, advance_max: u16b(hhea, 10)?, min_lsb: i16b(hhea, 12)?, min_rsb: i16b(hhea, 14)?, max_extent: i16b(hhea, 16)?, caret_rise: i16b(hhea, 18)?, caret_run: i16b(hhea, 20)?, caret_offset: i16b(hhea, 22)?, metric_count: metric_count as u16 },
        post: post_m,
        os2: os2m,
        names: names(name)?,
    };
    let mapping = input.mapping.clone();
    Ok((input, mapping))
}

// ---- GPOS kern extraction (master .glyphs kerning lane) ----
// Source of truth is the shipped OTF's GPOS table (chief kern lane ruling
// 19:50): effective pairs are extracted from the final bytes, never from the
// in-memory solution. Non-pair content is a typed residual with a ledger
// row, never dropped silently. Unknown or malformed structure is a typed
// error (refuse-whole-publish propagates from the caller).

/// One effective kern pair as shipped in the OTF GPOS: left glyph id, right
/// glyph id, xAdvance adjustment in font units.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GposKernPair {
    pub left: u16,
    pub right: u16,
    pub x_advance: i32,
}

/// Typed residual: GPOS content that is not an unconditional xAdvance pair.
/// `kind` is a stable token for receipt/ledger rows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GposResidual {
    pub kind: &'static str,
    pub detail: String,
}

/// The shipped GPOS kern content: effective pairs (sorted by left,right) and
/// every non-pair item as a typed residual.
#[derive(Clone, Debug, Default)]
pub struct GposKern {
    pub pairs: Vec<GposKernPair>,
    pub residuals: Vec<GposResidual>,
}

/// Like `table`, but a missing tag is `Ok(None)`; out-of-range stays an error.
fn table_opt<'a>(b: &'a [u8], tag: &[u8; 4]) -> Result<Option<&'a [u8]>, String> {
    let n = u16::from_be_bytes([b[4], b[5]]) as usize;
    for i in 0..n {
        let o = 12 + 16 * i;
        if b.get(o..o + 4) == Some(tag) {
            let (off, len) = (u32::from_be_bytes(b[o + 8..o + 12].try_into().unwrap()) as usize, u32::from_be_bytes(b[o + 12..o + 16].try_into().unwrap()) as usize);
            return Ok(Some(b.get(off..off + len).ok_or_else(|| format!("table {tag:?} out of range"))?));
        }
    }
    Ok(None)
}

/// Byte length of a value record for a value format (low 8 bits; each set
/// bit is one int16 field).
fn value_len(fmt: u16) -> usize { 2 * (fmt & 0xFF).count_ones() as usize }

/// Read one value record at `o` with format `fmt`. Returns the xAdvance (0
/// when the 0x4 bit is absent) and whether any non-xAdvance field was
/// present (typed residual per the kern lane: pairs carry xAdvance only).
fn read_value(b: &[u8], o: usize, fmt: u16) -> Result<(i32, bool), String> {
    let mut x_advance = 0i32;
    let mut extra = false;
    let mut p = o;
    for bit in 0..8u16 {
        if fmt & (1 << bit) == 0 { continue; }
        let v = i16b(b, p)? as i32;
        p += 2;
        if bit == 2 { x_advance = v; } else { extra = true; }
    }
    Ok((x_advance, extra))
}

/// Coverage table (format 1 glyph list or format 2 ranges) as glyph ids.
fn read_coverage(b: &[u8], o: usize) -> Result<Vec<u16>, String> {
    match u16b(b, o)? {
        1 => {
            let n = u16b(b, o + 2)? as usize;
            (0..n).map(|i| u16b(b, o + 4 + 2 * i)).collect()
        }
        2 => {
            let n = u16b(b, o + 2)? as usize;
            let mut out = Vec::new();
            for i in 0..n {
                let r = o + 4 + 6 * i;
                let (start, end) = (u16b(b, r)?, u16b(b, r + 2)?);
                if end < start { return Err("coverage range end < start".into()); }
                for g in start..=end { out.push(g); }
            }
            Ok(out)
        }
        f => Err(format!("coverage format {f} unsupported")),
    }
}

/// ClassDef table (format 1 array or format 2 ranges) as glyph->class map.
fn read_classdef(b: &[u8], o: usize) -> Result<std::collections::BTreeMap<u16, u16>, String> {
    let mut out = std::collections::BTreeMap::new();
    match u16b(b, o)? {
        1 => {
            let (start, n) = (u16b(b, o + 2)?, u16b(b, o + 4)? as usize);
            for i in 0..n {
                let g = start.checked_add(u16::try_from(i).map_err(|_| "classdef gid overflow")?).ok_or("classdef gid overflow")?;
                out.insert(g, u16b(b, o + 6 + 2 * i)?);
            }
        }
        2 => {
            let n = u16b(b, o + 2)? as usize;
            for i in 0..n {
                let r = o + 4 + 6 * i;
                let (gs, ge, c) = (u16b(b, r)?, u16b(b, r + 2)?, u16b(b, r + 4)?);
                if ge < gs { return Err("classdef range end < start".into()); }
                for g in gs..=ge { out.insert(g, c); }
            }
        }
        f => return Err(format!("classdef format {f} unsupported")),
    }
    Ok(out)
}

fn parse_pairpos(b: &[u8], so: usize, num_glyphs: u16, map: &mut std::collections::BTreeMap<(u16, u16), i32>, res: &mut Vec<GposResidual>) -> Result<(), String> {
    let fmt = u16b(b, so)?;
    let coverage = read_coverage(b, so + u16b(b, so + 2)? as usize)?;
    let (vf1, vf2) = (u16b(b, so + 4)?, u16b(b, so + 6)?);
    let (l1, l2) = (value_len(vf1), value_len(vf2));
    match fmt {
        1 => {
            let psc = u16b(b, so + 8)? as usize;
            if psc != coverage.len() { return Err(format!("pairSetCount {psc} != coverage glyphs {}", coverage.len())); }
            for (i, &left) in coverage.iter().enumerate() {
                let pso = so + u16b(b, so + 10 + 2 * i)? as usize;
                let pvc = u16b(b, pso)? as usize;
                let mut o = pso + 2;
                for _ in 0..pvc {
                    let right = u16b(b, o)?;
                    o += 2;
                    let (xa, e1) = read_value(b, o, vf1)?;
                    o += l1;
                    let (_, e2) = read_value(b, o, vf2)?;
                    o += l2;
                    if e1 || e2 { res.push(GposResidual { kind: "gpos_non_xadvance_value", detail: format!("pair {left} {right}") }); }
                    if xa == 0 && !e1 && !e2 { res.push(GposResidual { kind: "gpos_zero_pair", detail: format!("{left} {right}") }); continue; }
                    if map.insert((left, right), xa).is_some() { res.push(GposResidual { kind: "gpos_duplicate_pair", detail: format!("{left} {right} (last wins)") }); }
                }
            }
        }
        2 => {
            // Class-based: expand to effective glyph pairs (chief ruling:
            // class kerning only where it maps 1:1, else expanded pairs; a
            // reader cannot prove the doc-side class mapping, so it expands).
            let cd1 = read_classdef(b, so + u16b(b, so + 8)? as usize)?;
            let cd2 = read_classdef(b, so + u16b(b, so + 10)? as usize)?;
            let (c1n, c2n) = (u16b(b, so + 12)? as usize, u16b(b, so + 14)? as usize);
            if (c1n as u64) * (c2n as u64) * (num_glyphs as u64) > 4_000_000 { return Err("class pair expansion bound exceeded".into()); }
            let mut class2_glyphs: std::collections::BTreeMap<u16, Vec<u16>> = std::collections::BTreeMap::new();
            for g in 0..num_glyphs { class2_glyphs.entry(*cd2.get(&g).unwrap_or(&0)).or_default().push(g); }
            let mut expanded = 0usize;
            for &left in &coverage {
                let c1 = *cd1.get(&left).unwrap_or(&0) as usize;
                if c1 >= c1n { return Err(format!("coverage glyph {left} class {c1} >= class1Count {c1n}")); }
                for c2 in 0..c2n {
                    let ro = so + 16 + (c1 * c2n + c2) * (l1 + l2);
                    let (xa, e1) = read_value(b, ro, vf1)?;
                    let (_, e2) = read_value(b, ro + l1, vf2)?;
                    if xa == 0 && !e1 && !e2 { continue; }
                    let Some(rights) = class2_glyphs.get(&(c2 as u16)) else { continue; };
                    for &right in rights {
                        if e1 || e2 { res.push(GposResidual { kind: "gpos_non_xadvance_value", detail: format!("class pair {c1} {c2} (pair {left} {right})") }); }
                        if map.insert((left, right), xa).is_some() { res.push(GposResidual { kind: "gpos_duplicate_pair", detail: format!("{left} {right} (last wins)") }); }
                        expanded += 1;
                    }
                }
            }
            res.push(GposResidual { kind: "gpos_class_pairs_expanded", detail: format!("{expanded}") });
        }
        f => return Err(format!("PairPos format {f} unsupported")),
    }
    Ok(())
}

/// Extract the effective kern pairs and typed residuals from the shipped
/// OTF's GPOS table. No GPOS table = empty pairs + `gpos_absent` residual
/// (a font may ship without kerning; absence is a fact, not an error).
pub fn read_gpos_kern(bytes: &[u8]) -> Result<GposKern, String> {
    let Some(gpos) = table_opt(bytes, b"GPOS")? else {
        return Ok(GposKern { pairs: Vec::new(), residuals: vec![GposResidual { kind: "gpos_absent", detail: "no GPOS table".into() }] });
    };
    let num_glyphs = u16b(table(bytes, b"maxp")?, 4)?;
    let (major, minor) = (u16b(gpos, 0)?, u16b(gpos, 2)?);
    if major != 1 { return Err(format!("GPOS major version {major} unsupported")); }
    let (feat_off, look_off) = (u16b(gpos, 6)? as usize, u16b(gpos, 8)? as usize);
    let mut res = Vec::new();
    if minor >= 1 { res.push(GposResidual { kind: "gpos_feature_variations", detail: "v1.1 variations present (not extracted)".into() }); }
    let fcount = u16b(gpos, feat_off)? as usize;
    let mut lookup_idx: Vec<u16> = Vec::new();
    for i in 0..fcount {
        let o = feat_off + 2 + 6 * i;
        let tag = gpos.get(o..o + 4).ok_or("feature record short")?;
        let fo = feat_off + u16b(gpos, o + 4)? as usize;
        if tag == b"kern" {
            let lc = u16b(gpos, fo + 2)? as usize;
            for j in 0..lc { lookup_idx.push(u16b(gpos, fo + 4 + 2 * j)?); }
        } else {
            res.push(GposResidual { kind: "gpos_non_kern_feature", detail: String::from_utf8_lossy(tag).into_owned() });
        }
    }
    let lcount = u16b(gpos, look_off)? as usize;
    let mut map: std::collections::BTreeMap<(u16, u16), i32> = std::collections::BTreeMap::new();
    for &li in &lookup_idx {
        let li = li as usize;
        if li >= lcount { return Err(format!("lookup index {li} >= lookup count {lcount}")); }
        let lo = look_off + u16b(gpos, look_off + 2 + 2 * li)? as usize;
        let (ltype, lflag, scount) = (u16b(gpos, lo)?, u16b(gpos, lo + 2)?, u16b(gpos, lo + 4)? as usize);
        if lflag != 0 { res.push(GposResidual { kind: "gpos_conditional_lookup", detail: format!("flag 0x{lflag:04x}") }); }
        for s in 0..scount {
            let so = lo + u16b(gpos, lo + 6 + 2 * s)? as usize;
            match ltype {
                2 => parse_pairpos(gpos, so, num_glyphs, &mut map, &mut res)?,
                // ExtensionPos format 1: the writer wraps PairPos subtables
                // whose offsets exceed u16 (LOOKUP_EXTENSION path).
                9 => {
                    if u16b(gpos, so)? != 1 { return Err("ExtensionPos format != 1".into()); }
                    let ext_type = u16b(gpos, so + 2)?;
                    let ext_off = u32b(gpos, so + 4)? as usize;
                    match ext_type {
                        2 => parse_pairpos(gpos, so.checked_add(ext_off).ok_or("extension offset overflow")?, num_glyphs, &mut map, &mut res)?,
                        9 => return Err("nested extension lookup".into()),
                        t => res.push(GposResidual { kind: "gpos_non_pair_lookup", detail: format!("extension type {t}") }),
                    }
                }
                t => res.push(GposResidual { kind: "gpos_non_pair_lookup", detail: format!("type {t}") }),
            }
        }
    }
    let pairs = map.into_iter().map(|((left, right), x_advance)| GposKernPair { left, right, x_advance }).collect();
    Ok(GposKern { pairs, residuals: res })
}

#[cfg(test)]
mod gpos_kern_tests {
    use super::*;

    /// Minimal sfnt wrapper: GPOS + maxp tables around the writer's bytes.
    fn sfnt(gpos: Option<Vec<u8>>, num_glyphs: u16) -> Vec<u8> {
        let mut tables: Vec<(&[u8; 4], Vec<u8>)> = Vec::new();
        let mut maxp = vec![0u8; 6];
        maxp[4..6].copy_from_slice(&num_glyphs.to_be_bytes());
        tables.push((b"maxp", maxp));
        if let Some(g) = gpos { tables.push((b"GPOS", g)); }
        tables.sort_by_key(|(t, _)| *t);
        let n = tables.len() as u16;
        let mut out = vec![0u8; 4];
        out.extend_from_slice(&n.to_be_bytes());
        out.extend_from_slice(&[0u8; 6]);
        let mut off = 12 + 16 * tables.len();
        let mut recs = Vec::new();
        for (tag, data) in &tables {
            recs.extend_from_slice(*tag);
            recs.extend_from_slice(&[0u8; 4]);
            recs.extend_from_slice(&(off as u32).to_be_bytes());
            recs.extend_from_slice(&(data.len() as u32).to_be_bytes());
            off += (data.len() + 3) & !3;
        }
        out.extend_from_slice(&recs);
        for (_, data) in &tables {
            out.extend_from_slice(data);
            while out.len() % 4 != 0 { out.push(0); }
        }
        out
    }

    #[test]
    fn round_trip_writer_pairs() {
        let pairs = [
            kni_metrics::gpos_pairpos1::PairKern { left: 1, right: 2, x_advance: -80 },
            kni_metrics::gpos_pairpos1::PairKern { left: 1, right: 3, x_advance: 25 },
            kni_metrics::gpos_pairpos1::PairKern { left: 5, right: 0, x_advance: -12 },
        ];
        let gpos = kni_metrics::gpos_pairpos1::write_kern_pairpos1(6, &pairs).unwrap();
        let got = read_gpos_kern(&sfnt(Some(gpos), 6)).unwrap();
        let want: Vec<GposKernPair> = pairs.iter().map(|p| GposKernPair { left: p.left, right: p.right, x_advance: p.x_advance }).collect();
        assert_eq!(got.pairs, want, "extracted pairs must equal the written pairs");
        assert!(got.residuals.is_empty(), "writer shape yields no residuals, got {:?}", got.residuals);
    }

    #[test]
    fn absent_gpos_is_empty_with_residual() {
        let got = read_gpos_kern(&sfnt(None, 6)).unwrap();
        assert!(got.pairs.is_empty());
        assert_eq!(got.residuals.len(), 1);
        assert_eq!(got.residuals[0].kind, "gpos_absent");
    }

    #[test]
    fn malformed_gpos_is_typed_error() {
        let mut bad = sfnt(Some(vec![0, 1, 0, 0, 0, 4, 0, 6, 0, 8]), 6);
        let n = read_gpos_kern(&bad);
        assert!(n.is_err(), "short GPOS must be a typed error, got {n:?}");
        // Corrupt the table directory: a declared table range beyond the
        // file end is an out-of-range typed error, not silent absence.
        let gpos_rec = 12 + 16; // records sorted by tag: GPOS then maxp
        let off = u32::from_be_bytes(bad[gpos_rec + 8..gpos_rec + 12].try_into().unwrap()) as usize;
        bad.truncate(off + 2);
        assert!(read_gpos_kern(&bad).is_err());
    }
}
