//! Font reader for the vector input path of master mode: reads the outlines
//! of CFF1 (`OTTO`) and simple TrueType (`0x00010000`) outlines into
//! `MasterGlyph`, in the font's own coordinate frame (font units, y up).
//!
//! Scope: read-only, no dependency, no writes. The reader reports what the
//! file says; it does not repair, snap or reorder anything. TrueType
//! quadratics are degree-elevated to cubics with binary64 arithmetic in the
//! existing model, not preserved as native quadratic operations. A file
//! feature it does not implement is a typed `ReadError::Unsupported`, never a
//! silently different outline.
//!
//! Supported: sfnt table directory, `head` (units per em), `hhea`/`hmtx`
//! (advance), `cmap` formats 4 and 12 (code point to glyph index), CFF1
//! simple TrueType glyf/loca outlines (quadratics degree-elevated to cubics), CFF1
//! with Type 2 charstrings (all path, hint-skipping, subroutine and flex
//! operators). Not supported (typed error): CID-keyed CFF, CFF2, TrueType
//! TrueType point-attached or ambiguously transformed composites, variable fonts, charstring arithmetic/storage operators, accented
//! composite `endchar` (4 extra operands).
//!
//! Numeric limits below are FORMAT limits of CFF Type 2 or resource guards
//! against hostile input. None is a measurement or a tolerance.

use crate::model::{MasterGlyph, Op, Pt, StrokeContour};
use std::collections::BTreeMap;

/// Type 2 argument stack depth (format limit).
const MAX_STACK: usize = 48;
/// Subroutine nesting depth (format limit).
const MAX_SUBR_DEPTH: usize = 10;
/// Resource guard: charstring bytes processed per glyph, calls included.
const MAX_STEPS: usize = 1_000_000;
/// Resource guard: code points read from one cmap.
const MAX_CMAP_ENTRIES: usize = 1 << 20;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadError {
    /// A read ran past the end of the data; the structure is named.
    Truncated(&'static str),
    /// The first four bytes are neither supported sfnt signature.
    NotCffOpenType,
    MissingTable(&'static str),
    /// A feature this reader does not implement.
    Unsupported(String),
    /// The charstring of glyph `gid` is malformed.
    BadCharstring { gid: u16, reason: &'static str },
    GlyphIndexOutOfRange(u16),
    BadGlyf { gid: u16, reason: &'static str },
    /// Resource guard exceeded while reading a charstring.
    Budget { gid: u16 },
}

impl std::fmt::Display for ReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReadError::Truncated(w) => write!(f, "truncated data: {w}"),
            ReadError::NotCffOpenType => write!(f, "not a supported OpenType font (OTTO or TrueType sfnt)"),
            ReadError::MissingTable(t) => write!(f, "missing table {t}"),
            ReadError::Unsupported(w) => write!(f, "unsupported: {w}"),
            ReadError::BadCharstring { gid, reason } => write!(f, "glyph {gid}: bad charstring: {reason}"),
            ReadError::BadGlyf { gid, reason } => write!(f, "glyph {gid}: bad glyf: {reason}"),
            ReadError::GlyphIndexOutOfRange(g) => write!(f, "glyph index {g} out of range"),
            ReadError::Budget { gid } => write!(f, "glyph {gid}: charstring resource guard exceeded"),
        }
    }
}

impl std::error::Error for ReadError {}

fn u8_at(d: &[u8], o: usize, what: &'static str) -> Result<u8, ReadError> {
    d.get(o).copied().ok_or(ReadError::Truncated(what))
}
fn u16_at(d: &[u8], o: usize, what: &'static str) -> Result<u16, ReadError> {
    let b = d.get(o..o.checked_add(2).ok_or(ReadError::Truncated(what))?).ok_or(ReadError::Truncated(what))?;
    Ok(u16::from_be_bytes([b[0], b[1]]))
}
fn u32_at(d: &[u8], o: usize, what: &'static str) -> Result<u32, ReadError> {
    let b = d.get(o..o.checked_add(4).ok_or(ReadError::Truncated(what))?).ok_or(ReadError::Truncated(what))?;
    Ok(u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
}

/// A CFF INDEX: absolute byte ranges of its objects, and the position after it.
fn read_index(d: &[u8], pos: usize, what: &'static str) -> Result<(Vec<(usize, usize)>, usize), ReadError> {
    let count = u16_at(d, pos, what)? as usize;
    if count == 0 {
        return Ok((Vec::new(), pos + 2));
    }
    let off_size = u8_at(d, pos + 2, what)? as usize;
    if !(1..=4).contains(&off_size) {
        return Err(ReadError::Unsupported(format!("INDEX offset size {off_size}")));
    }
    let base = pos + 3 + (count + 1) * off_size - 1;
    let off = |i: usize| -> Result<usize, ReadError> {
        let p = pos + 3 + i * off_size;
        let mut v = 0usize;
        for k in 0..off_size {
            v = (v << 8) | u8_at(d, p + k, what)? as usize;
        }
        Ok(v)
    };
    let mut out = Vec::with_capacity(count);
    let mut prev = off(0)?;
    for i in 1..=count {
        let cur = off(i)?;
        if cur < prev || prev < 1 {
            return Err(ReadError::Truncated(what));
        }
        let (s, e) = (base + prev, base + cur);
        if e > d.len() {
            return Err(ReadError::Truncated(what));
        }
        out.push((s, e));
        prev = cur;
    }
    Ok((out, base + prev))
}

/// DICT entries: operator (12 xx encoded as 1200 + xx) to its operands.
fn read_dict(d: &[u8]) -> Result<BTreeMap<u16, Vec<f64>>, ReadError> {
    let mut out = BTreeMap::new();
    let mut ops: Vec<f64> = Vec::new();
    let mut i = 0;
    while i < d.len() {
        let b0 = d[i];
        i += 1;
        match b0 {
            0..=21 => {
                let op = if b0 == 12 {
                    let b1 = u8_at(d, i, "DICT operator")?;
                    i += 1;
                    1200 + b1 as u16
                } else {
                    b0 as u16
                };
                out.insert(op, std::mem::take(&mut ops));
            }
            28 => {
                ops.push(u16_at(d, i, "DICT operand")? as i16 as f64);
                i += 2;
            }
            29 => {
                ops.push(u32_at(d, i, "DICT operand")? as i32 as f64);
                i += 4;
            }
            30 => {
                // Real number: nibbles to 0xf. The value is not needed here.
                loop {
                    let b = u8_at(d, i, "DICT real")?;
                    i += 1;
                    if b & 0x0f == 0x0f || b >> 4 == 0x0f {
                        break;
                    }
                }
                ops.push(f64::NAN);
            }
            32..=246 => ops.push(b0 as f64 - 139.0),
            247..=250 => {
                let b1 = u8_at(d, i, "DICT operand")? as f64;
                i += 1;
                ops.push((b0 as f64 - 247.0) * 256.0 + b1 + 108.0);
            }
            251..=254 => {
                let b1 = u8_at(d, i, "DICT operand")? as f64;
                i += 1;
                ops.push(-(b0 as f64 - 251.0) * 256.0 - b1 - 108.0);
            }
            _ => return Err(ReadError::Unsupported(format!("DICT byte {b0}"))),
        }
    }
    Ok(out)
}

fn subr_bias(n: usize) -> i64 {
    // Format constants of Type 2 subroutine numbering.
    if n < 1240 {
        107
    } else if n < 33900 {
        1131
    } else {
        32768
    }
}

/// An opened font. Borrows the file bytes.
#[derive(Debug)]
pub struct OtfFont<'a> {
    data: &'a [u8],
    upm: f64,
    char_strings: Vec<(usize, usize)>,
    gsubrs: Vec<(usize, usize)>,
    lsubrs: Vec<(usize, usize)>,
    advances: Vec<f64>,
    cmap: BTreeMap<u32, u16>,
    glyf_ranges: Option<Vec<(usize,usize)>>,
}

fn find_table(d: &[u8], tag: &[u8; 4]) -> Result<Option<(usize, usize)>, ReadError> {
    let n = u16_at(d, 4, "table directory")? as usize;
    for i in 0..n {
        let rec = 12 + 16 * i;
        let t = d.get(rec..rec + 4).ok_or(ReadError::Truncated("table directory"))?;
        if t == tag {
            let off = u32_at(d, rec + 8, "table directory")? as usize;
            let len = u32_at(d, rec + 12, "table directory")? as usize;
            if off.checked_add(len).map_or(true, |e| e > d.len()) {
                return Err(ReadError::Truncated("table extent"));
            }
            return Ok(Some((off, len)));
        }
    }
    Ok(None)
}

fn parse_cmap(d: &[u8], off: usize) -> Result<BTreeMap<u32, u16>, ReadError> {
    let n = u16_at(d, off + 2, "cmap")? as usize;
    let mut best: Option<(u8, usize)> = None; // (rank, subtable offset); lower rank wins
    for i in 0..n {
        let p = off + 4 + 8 * i;
        let plat = u16_at(d, p, "cmap record")?;
        let enc = u16_at(d, p + 2, "cmap record")?;
        let so = off + u32_at(d, p + 4, "cmap record")? as usize;
        let fmt = u16_at(d, so, "cmap subtable")?;
        let rank = match (plat, enc, fmt) {
            (3, 10, 12) => 0,
            (0, _, 12) => 1,
            (3, 1, 4) => 2,
            (0, _, 4) => 3,
            _ => continue,
        };
        if best.map_or(true, |(r, _)| rank < r) {
            best = Some((rank, so));
        }
    }
    let mut map = BTreeMap::new();
    let Some((_, so)) = best else { return Ok(map) };
    match u16_at(d, so, "cmap subtable")? {
        12 => {
            let groups = u32_at(d, so + 12, "cmap12")? as usize;
            // Counts every code point visited, including those whose glyph
            // index does not fit in 16 bits and are not stored.
            let mut visited = 0usize;
            for g in 0..groups {
                let p = so + 16 + 12 * g;
                let (s, e, gid) = (u32_at(d, p, "cmap12")?, u32_at(d, p + 4, "cmap12")?, u32_at(d, p + 8, "cmap12")?);
                if e < s || e - s > 0x10ffff {
                    return Err(ReadError::Unsupported("cmap12 group".into()));
                }
                for c in s..=e {
                    visited += 1;
                    if visited > MAX_CMAP_ENTRIES {
                        return Err(ReadError::Unsupported("cmap larger than the resource guard".into()));
                    }
                    let gi = gid.saturating_add(c - s);
                    if gi <= u16::MAX as u32 {
                        map.entry(c).or_insert(gi as u16);
                    }
                }
            }
        }
        4 => {
            let segx2 = u16_at(d, so + 6, "cmap4")? as usize;
            let seg = segx2 / 2;
            let end_p = so + 14;
            let start_p = end_p + segx2 + 2;
            let delta_p = start_p + segx2;
            let range_p = delta_p + segx2;
            for k in 0..seg {
                let end = u16_at(d, end_p + 2 * k, "cmap4")? as u32;
                let start = u16_at(d, start_p + 2 * k, "cmap4")? as u32;
                let delta = u16_at(d, delta_p + 2 * k, "cmap4")?;
                let ro = u16_at(d, range_p + 2 * k, "cmap4")? as usize;
                if end < start {
                    continue;
                }
                for c in start..=end {
                    if c == 0xffff {
                        continue;
                    }
                    let gid = if ro == 0 {
                        (c as u16).wrapping_add(delta)
                    } else {
                        let p = range_p + 2 * k + ro + 2 * (c - start) as usize;
                        let g = u16_at(d, p, "cmap4")?;
                        if g == 0 { 0 } else { g.wrapping_add(delta) }
                    };
                    if gid != 0 {
                        map.entry(c).or_insert(gid);
                    }
                }
            }
        }
        _ => {}
    }
    Ok(map)
}

impl<'a> OtfFont<'a> {
    pub fn parse(data: &'a [u8]) -> Result<Self, ReadError> {
        if data.get(0..4) == Some(&[0,1,0,0][..]) { return Self::parse_glyf(data); }
        if data.get(0..4) != Some(&b"OTTO"[..]) {
            return Err(ReadError::NotCffOpenType);
        }
        let need = |t: &'static [u8; 4], name: &'static str| -> Result<(usize, usize), ReadError> {
            find_table(data, t)?.ok_or(ReadError::MissingTable(name))
        };
        let (head, _) = need(b"head", "head")?;
        let upm = u16_at(data, head + 18, "head")? as f64;
        if upm == 0.0 {
            return Err(ReadError::Unsupported("units per em is 0".into()));
        }
        let (cff, cff_len) = need(b"CFF ", "CFF ")?;
        let c = &data[cff..cff + cff_len];
        if u8_at(c, 0, "CFF header")? != 1 {
            return Err(ReadError::Unsupported("CFF major version other than 1".into()));
        }
        let hdr = u8_at(c, 2, "CFF header")? as usize;
        let (_names, p) = read_index(c, hdr, "CFF Name INDEX")?;
        let (tops, p) = read_index(c, p, "CFF Top DICT INDEX")?;
        let (_strings, p) = read_index(c, p, "CFF String INDEX")?;
        let (gsubrs_rel, _) = read_index(c, p, "CFF Global Subr INDEX")?;
        let (ts, te) = *tops.first().ok_or(ReadError::Truncated("CFF Top DICT"))?;
        let top = read_dict(&c[ts..te])?;
        if top.contains_key(&1230) || top.contains_key(&1236) {
            return Err(ReadError::Unsupported("CID-keyed CFF".into()));
        }
        let cs_off = *top
            .get(&17)
            .and_then(|v| v.first())
            .ok_or(ReadError::Truncated("CFF CharStrings offset"))? as usize;
        let (cs_rel, _) = read_index(c, cs_off, "CFF CharStrings INDEX")?;
        let mut lsubrs_rel = Vec::new();
        if let Some(pv) = top.get(&18) {
            if pv.len() == 2 {
                let (size, poff) = (pv[0] as usize, pv[1] as usize);
                let pd = c.get(poff..poff.saturating_add(size)).ok_or(ReadError::Truncated("CFF Private DICT"))?;
                let private = read_dict(pd)?;
                if let Some(so) = private.get(&19).and_then(|v| v.first()) {
                    (lsubrs_rel, _) = read_index(c, poff.saturating_add(*so as usize), "CFF Local Subr INDEX")?;
                }
            }
        }
        let abs = |v: Vec<(usize, usize)>| -> Vec<(usize, usize)> { v.into_iter().map(|(s, e)| (s + cff, e + cff)).collect() };
        let char_strings = abs(cs_rel);
        // Advances.
        let (hhea, _) = need(b"hhea", "hhea")?;
        let nhm = u16_at(data, hhea + 34, "hhea")? as usize;
        let (hmtx, hmtx_len) = need(b"hmtx", "hmtx")?;
        let mut advances = Vec::with_capacity(char_strings.len());
        for g in 0..char_strings.len() {
            let idx = g.min(nhm.saturating_sub(1));
            if nhm == 0 || 4 * idx + 2 > hmtx_len {
                return Err(ReadError::Truncated("hmtx"));
            }
            advances.push(u16_at(data, hmtx + 4 * idx, "hmtx")? as f64);
        }
        let cmap = match find_table(data, b"cmap")? {
            Some((o, _)) => parse_cmap(data, o)?,
            None => BTreeMap::new(),
        };
        Ok(Self { data, upm, char_strings, gsubrs: abs(gsubrs_rel), lsubrs: abs(lsubrs_rel), advances, cmap, glyf_ranges:None })
    }

    fn parse_glyf(data:&'a [u8])->Result<Self,ReadError>{
        let need=|tag:&'static [u8;4],name:&'static str|->Result<&'a [u8],ReadError>{let(o,n)=find_table(data,tag)?.ok_or(ReadError::MissingTable(name))?;Ok(&data[o..o+n])};
        for tag in [b"gvar",b"fvar"] { if find_table(data,tag)?.is_some(){return Err(ReadError::Unsupported("variable TrueType outlines".into()))} }
        let head=need(b"head","head")?;let upm=u16_at(head,18,"head")? as f64;if upm==0.{return Err(ReadError::Unsupported("units per em is 0".into()))}
        let maxp=need(b"maxp","maxp")?;let count=u16_at(maxp,4,"maxp")? as usize;
        let loca=need(b"loca","loca")?;let (go,gl)=find_table(data,b"glyf")?.ok_or(ReadError::MissingTable("glyf"))?;
        let format=u16_at(head,50,"head")?;let mut offsets=Vec::new();for i in 0..=count {let v=match format{0=>u16_at(loca,i*2,"loca")? as usize*2,1=>u32_at(loca,i*4,"loca")? as usize,_=>return Err(ReadError::Unsupported("loca format".into()))};if v>gl||offsets.last().is_some_and(|x|v<*x){return Err(ReadError::Truncated("loca extent/order"))}offsets.push(v);}
        let hhea=need(b"hhea","hhea")?;let nh=u16_at(hhea,34,"hhea")? as usize;let hmtx=need(b"hmtx","hmtx")?;if nh==0||nh>count{return Err(ReadError::Truncated("hmtx metrics count"))}let required=nh*4+(count-nh)*2;if hmtx.len()<required{return Err(ReadError::Truncated("hmtx"))}let advances=(0..count).map(|i|u16_at(hmtx,i.min(nh-1)*4,"hmtx").map(|v|v as f64)).collect::<Result<Vec<_>,_>>()?;
        let cmap=match find_table(data,b"cmap")?{Some((o,n))=>parse_cmap(&data[o..o+n],0)?,None=>BTreeMap::new()};
        Ok(Self{data,upm,char_strings:vec![],gsubrs:vec![],lsubrs:vec![],advances,cmap,glyf_ranges:Some(offsets.windows(2).map(|w|(go+w[0],go+w[1])).collect())})
    }
    pub fn upm(&self) -> f64 {
        self.upm
    }
    pub fn glyph_count(&self) -> usize {
        self.glyf_ranges.as_ref().map_or(self.char_strings.len(),|r|r.len())
    }
    /// Complete sorted codepoint keys of the parsed supported cmap subtable.
    pub fn codepoints(&self)->impl Iterator<Item=u32>+'_ { self.cmap.keys().copied() }
    pub fn gid_for_codepoint(&self, cp: u32) -> Option<u16> {
        self.cmap.get(&cp).copied()
    }

    /// Read one glyph. The name is `uniXXXX` / `uXXXXXX` from the cmap when a
    /// code point maps to the glyph (lowest code point), else `gid<N>`.
    /// Glyph names stored in the CFF charset are not read.
    pub fn glyph(&self, gid: u16) -> Result<MasterGlyph, ReadError> {
        let ops=if let Some(ranges)=&self.glyf_ranges {
            crate::glyf::decode_font(self.data,ranges,gid)?
        }else{
            let (s, e) = *self.char_strings.get(gid as usize).ok_or(ReadError::GlyphIndexOutOfRange(gid))?;
            let mut st = State::new(self, gid);st.run(&self.data[s..e], 0)?;st.finish()?;st.contours
        };
        let name = match self.cmap.iter().find(|(_, g)| **g == gid) {
            Some((cp, _)) if *cp <= 0xffff => format!("uni{cp:04X}"),
            Some((cp, _)) => format!("u{cp:06X}"),
            None => format!("gid{gid}"),
        };
        let contours = ops
            .into_iter()
            .enumerate()
            .map(|(i, ops)| StrokeContour { stroke: format!("c{i}"), ops })
            .collect();
        Ok(MasterGlyph { name, advance: self.advances[gid as usize], upm: self.upm, contours })
    }

    pub fn glyph_by_codepoint(&self, cp: u32) -> Result<Option<MasterGlyph>, ReadError> {
        match self.gid_for_codepoint(cp) {
            Some(g) => self.glyph(g).map(Some),
            None => Ok(None),
        }
    }
}

struct State<'f, 'a> {
    font: &'f OtfFont<'a>,
    gid: u16,
    stack: Vec<f64>,
    x: f64,
    y: f64,
    contours: Vec<Vec<Op>>,
    open: bool,
    nstems: usize,
    width_done: bool,
    steps: usize,
    ended: bool,
}

impl<'f, 'a> State<'f, 'a> {
    fn new(font: &'f OtfFont<'a>, gid: u16) -> Self {
        Self { font, gid, stack: Vec::new(), x: 0.0, y: 0.0, contours: Vec::new(), open: false, nstems: 0, width_done: false, steps: 0, ended: false }
    }

    fn bad<T>(&self, reason: &'static str) -> Result<T, ReadError> {
        Err(ReadError::BadCharstring { gid: self.gid, reason })
    }

    fn finish(&mut self) -> Result<(), ReadError> {
        if !self.ended {
            return self.bad("no endchar");
        }
        Ok(())
    }

    fn close(&mut self) {
        if self.open {
            self.contours.last_mut().unwrap().push(Op::Close);
            self.open = false;
        }
    }

    /// Drop the optional leading width operand: `extra` is true when the
    /// operand count carries one more value than the operator takes.
    fn width(&mut self, extra: bool) {
        if !self.width_done {
            self.width_done = true;
            if extra && !self.stack.is_empty() {
                self.stack.remove(0);
            }
        }
    }

    fn move_to(&mut self, dx: f64, dy: f64) {
        self.close();
        self.x += dx;
        self.y += dy;
        self.contours.push(vec![Op::Move((self.x, self.y))]);
        self.open = true;
    }

    fn line_to(&mut self, dx: f64, dy: f64) -> Result<(), ReadError> {
        if !self.open {
            return self.bad("path operator before moveto");
        }
        self.x += dx;
        self.y += dy;
        let p = (self.x, self.y);
        self.contours.last_mut().unwrap().push(Op::Line(p));
        Ok(())
    }

    fn curve(&mut self, c1: Pt, c2: Pt, p: Pt) -> Result<(), ReadError> {
        if !self.open {
            return self.bad("path operator before moveto");
        }
        self.x = p.0;
        self.y = p.1;
        self.contours.last_mut().unwrap().push(Op::Curve(c1, c2, p));
        Ok(())
    }

    /// Relative curve from deltas.
    fn rcurve(&mut self, d: [f64; 6]) -> Result<(), ReadError> {
        let c1 = (self.x + d[0], self.y + d[1]);
        let c2 = (c1.0 + d[2], c1.1 + d[3]);
        let p = (c2.0 + d[4], c2.1 + d[5]);
        self.curve(c1, c2, p)
    }

    fn run(&mut self, cs: &[u8], depth: usize) -> Result<bool, ReadError> {
        let mut i = 0usize;
        while i < cs.len() {
            self.steps += 1;
            if self.steps > MAX_STEPS {
                return Err(ReadError::Budget { gid: self.gid });
            }
            let b0 = cs[i];
            i += 1;
            if self.ended {
                return Ok(true);
            }
            match b0 {
                28 | 32..=255 => {
                    let v = match b0 {
                        28 => {
                            let r = u16_at(cs, i, "charstring number").map_err(|_| ReadError::BadCharstring { gid: self.gid, reason: "truncated number" })?;
                            i += 2;
                            r as i16 as f64
                        }
                        32..=246 => b0 as f64 - 139.0,
                        247..=254 => {
                            let b1 = *cs.get(i).ok_or(ReadError::BadCharstring { gid: self.gid, reason: "truncated number" })? as f64;
                            i += 1;
                            if b0 <= 250 { (b0 as f64 - 247.0) * 256.0 + b1 + 108.0 } else { -(b0 as f64 - 251.0) * 256.0 - b1 - 108.0 }
                        }
                        _ => {
                            let r = u32_at(cs, i, "charstring number").map_err(|_| ReadError::BadCharstring { gid: self.gid, reason: "truncated number" })?;
                            i += 4;
                            r as i32 as f64 / 65536.0
                        }
                    };
                    if self.stack.len() >= MAX_STACK {
                        return self.bad("stack overflow");
                    }
                    self.stack.push(v);
                }
                1 | 3 | 18 | 23 => {
                    let n = self.stack.len();
                    self.width(n % 2 == 1);
                    self.nstems += self.stack.len() / 2;
                    self.stack.clear();
                }
                19 | 20 => {
                    let n = self.stack.len();
                    self.width(n % 2 == 1);
                    self.nstems += self.stack.len() / 2;
                    self.stack.clear();
                    i += (self.nstems + 7) / 8;
                    if i > cs.len() {
                        return self.bad("truncated hint mask");
                    }
                }
                21 => {
                    let n = self.stack.len();
                    self.width(n > 2);
                    if self.stack.len() != 2 {
                        return self.bad("rmoveto operands");
                    }
                    let (dx, dy) = (self.stack[0], self.stack[1]);
                    self.stack.clear();
                    self.move_to(dx, dy);
                }
                22 | 4 => {
                    let n = self.stack.len();
                    self.width(n > 1);
                    if self.stack.len() != 1 {
                        return self.bad("hmoveto/vmoveto operands");
                    }
                    let d = self.stack[0];
                    self.stack.clear();
                    if b0 == 22 { self.move_to(d, 0.0) } else { self.move_to(0.0, d) }
                }
                5 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() % 2 != 0 {
                        return self.bad("rlineto operands");
                    }
                    for p in a.chunks(2) {
                        self.line_to(p[0], p[1])?;
                    }
                }
                6 | 7 => {
                    let a = std::mem::take(&mut self.stack);
                    let mut horiz = b0 == 6;
                    for v in a {
                        if horiz { self.line_to(v, 0.0)? } else { self.line_to(0.0, v)? }
                        horiz = !horiz;
                    }
                }
                8 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() % 6 != 0 {
                        return self.bad("rrcurveto operands");
                    }
                    for c in a.chunks(6) {
                        self.rcurve([c[0], c[1], c[2], c[3], c[4], c[5]])?;
                    }
                }
                24 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() < 2 || (a.len() - 2) % 6 != 0 {
                        return self.bad("rcurveline operands");
                    }
                    let nc = (a.len() - 2) / 6;
                    for c in a[..nc * 6].chunks(6) {
                        self.rcurve([c[0], c[1], c[2], c[3], c[4], c[5]])?;
                    }
                    self.line_to(a[nc * 6], a[nc * 6 + 1])?;
                }
                25 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() < 6 || (a.len() - 6) % 2 != 0 {
                        return self.bad("rlinecurve operands");
                    }
                    let nl = (a.len() - 6) / 2;
                    for p in a[..nl * 2].chunks(2) {
                        self.line_to(p[0], p[1])?;
                    }
                    let c = &a[nl * 2..];
                    self.rcurve([c[0], c[1], c[2], c[3], c[4], c[5]])?;
                }
                26 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() % 4 > 1 {
                        return self.bad("vvcurveto operands");
                    }
                    let mut k = 0;
                    let mut dx1 = 0.0;
                    if a.len() % 4 == 1 {
                        dx1 = a[0];
                        k = 1;
                    }
                    while k + 4 <= a.len() {
                        self.rcurve([dx1, a[k], a[k + 1], a[k + 2], 0.0, a[k + 3]])?;
                        dx1 = 0.0;
                        k += 4;
                    }
                }
                27 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() % 4 > 1 {
                        return self.bad("hhcurveto operands");
                    }
                    let mut k = 0;
                    let mut dy1 = 0.0;
                    if a.len() % 4 == 1 {
                        dy1 = a[0];
                        k = 1;
                    }
                    while k + 4 <= a.len() {
                        self.rcurve([a[k], dy1, a[k + 1], a[k + 2], a[k + 3], 0.0])?;
                        dy1 = 0.0;
                        k += 4;
                    }
                }
                30 | 31 => {
                    let a = std::mem::take(&mut self.stack);
                    if a.len() % 4 > 1 || a.len() < 4 {
                        return self.bad("vhcurveto/hvcurveto operands");
                    }
                    let mut horiz = b0 == 31;
                    let mut k = 0;
                    while k + 4 <= a.len() {
                        let last = a.len() - k == 5;
                        let extra = if last { a[k + 4] } else { 0.0 };
                        if horiz {
                            self.rcurve([a[k], 0.0, a[k + 1], a[k + 2], extra, a[k + 3]])?;
                        } else {
                            self.rcurve([0.0, a[k], a[k + 1], a[k + 2], a[k + 3], extra])?;
                        }
                        horiz = !horiz;
                        k += if last { 5 } else { 4 };
                    }
                }
                10 | 29 => {
                    let Some(n) = self.stack.pop() else { return self.bad("subroutine call without index") };
                    let subrs = if b0 == 10 { &self.font.lsubrs } else { &self.font.gsubrs };
                    let idx = n as i64 + subr_bias(subrs.len());
                    if idx < 0 || idx as usize >= subrs.len() {
                        return self.bad("subroutine index out of range");
                    }
                    if depth >= MAX_SUBR_DEPTH {
                        return self.bad("subroutine nesting too deep");
                    }
                    let (s, e) = subrs[idx as usize];
                    let data = self.font.data;
                    if self.run(&data[s..e], depth + 1)? {
                        return Ok(true);
                    }
                }
                11 => return Ok(false),
                14 => {
                    let n = self.stack.len();
                    if n == 4 || n == 5 {
                        return Err(ReadError::Unsupported("endchar with accent operands (composite)".into()));
                    }
                    self.width(n == 1);
                    if !self.stack.is_empty() {
                        return self.bad("endchar operands");
                    }
                    self.close();
                    self.ended = true;
                    return Ok(true);
                }
                12 => {
                    let b1 = *cs.get(i).ok_or(ReadError::BadCharstring { gid: self.gid, reason: "truncated operator" })?;
                    i += 1;
                    let a = std::mem::take(&mut self.stack);
                    match b1 {
                        35 if a.len() == 13 => {
                            self.rcurve([a[0], a[1], a[2], a[3], a[4], a[5]])?;
                            self.rcurve([a[6], a[7], a[8], a[9], a[10], a[11]])?;
                        }
                        34 if a.len() == 7 => {
                            // hflex: the end y returns to the start y.
                            self.rcurve([a[0], 0.0, a[1], a[2], a[3], 0.0])?;
                            self.rcurve([a[4], 0.0, a[5], -a[2], a[6], 0.0])?;
                        }
                        36 if a.len() == 9 => {
                            let y0 = self.y;
                            self.rcurve([a[0], a[1], a[2], a[3], a[4], 0.0])?;
                            let dy6 = y0 - (self.y + a[7]);
                            self.rcurve([a[5], 0.0, a[6], a[7], a[8], dy6])?;
                        }
                        37 if a.len() == 11 => {
                            let (x0, y0) = (self.x, self.y);
                            let dx: f64 = (0..5).map(|k| a[2 * k]).sum();
                            let dy: f64 = (0..5).map(|k| a[2 * k + 1]).sum();
                            self.rcurve([a[0], a[1], a[2], a[3], a[4], a[5]])?;
                            let (d6x, d6y) = if dx.abs() > dy.abs() {
                                (a[10], y0 - (self.y + a[7] + a[9]))
                            } else {
                                (x0 - (self.x + a[6] + a[8]), a[10])
                            };
                            self.rcurve([a[6], a[7], a[8], a[9], d6x, d6y])?;
                        }
                        34..=37 => return self.bad("flex operands"),
                        _ => return Err(ReadError::Unsupported(format!("charstring operator 12 {b1}"))),
                    }
                }
                _ => return Err(ReadError::Unsupported(format!("charstring operator {b0}"))),
            }
        }
        Ok(false)
    }
}
