//! OTF/CFF1 reference reader (A1 ref_intake). Reads only: sfnt table directory, cmap
//! (codepoint -> glyph selection), CFF header/Name/Top DICT/String/Global Subr INDEX,
//! CharStrings INDEX, Private DICT and local Subrs. hmtx, GPOS and kern are never read.
//! Full Type 2 operator set for outline work (stems, hintmask/cntrmask, all line and
//! curve operators, flex family converted to cubics, callsubr/callgsubr/return, endchar).
//! Anything else (arithmetic/storage operators, reserved codes, seac endchar, CID-keyed
//! fonts, non-Type2 charstrings, non-default FontMatrix, unsupported cmap formats) is a
//! typed reject, never a guess (supported: head.unitsPerEm == 1000 and FontMatrix absent or exactly [0.001 0 0 0.001 0 0]; anything else is rejected, no tolerance; head is read for unitsPerEm only). Output is `ReferenceRing`s with no open ring: an unclosed
//! subpath is closed by a Line to its start, exactly as CFF fill semantics imply, and each
//! such closure is counted in `implicit_closures`. Execution is NOT_RUN until tests run.
use crate::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReadReject {
    ShaMismatch { expected: String, actual: String },
    BadExpectedSha,
    Truncated(&'static str),
    NotOtto(u32),
    MissingTable([u8; 4]),
    DuplicateTable([u8; 4]),
    TableOutOfBounds([u8; 4]),
    BadIndex(&'static str),
    BadDict(&'static str),
    MissingTopDictEntry(&'static str),
    CidKeyed,
    CharstringTypeNotTwo(i64),
    NonDefaultFontMatrix,
    UnitsPerEmNotThousand(u16),
    CmapNoUsableSubtable,
    CmapUnsupportedFormat(u16),
    CmapGlyphOutOfRange { codepoint: u32, glyph: u16 },
    GlyphOutOfRange(u16),
    /// Single byte op as-is; two byte escape ops as 0x0c00 | second byte.
    UnsupportedOperator(u16),
    Seac,
    StackOverflow,
    StackUnderflow,
    BadArgumentCount { op: u16, count: usize },
    SubrOutOfRange,
    SubrDepthExceeded,
    MissingEndchar,
    DrawBeforeMoveto,
    TruncatedOperand,
    TruncatedHintmask,
}

// ---------------------------------------------------------------- SHA-256
pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 { msg.push(0); }
    msg.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for block in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([block[4 * i], block[4 * i + 1], block[4 * i + 2], block[4 * i + 3]]); }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v = [t1.wrapping_add(t2), v[0], v[1], v[2], v[3].wrapping_add(t1), v[4], v[5], v[6]];
        }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    h.iter().map(|x| format!("{x:08x}")).collect()
}

// ---------------------------------------------------------------- byte helpers
fn u16_at(b: &[u8], o: usize, what: &'static str) -> Result<u16, ReadReject> {
    b.get(o..o + 2).map(|s| u16::from_be_bytes([s[0], s[1]])).ok_or(ReadReject::Truncated(what))
}
fn u32_at(b: &[u8], o: usize, what: &'static str) -> Result<u32, ReadReject> {
    b.get(o..o + 4).map(|s| u32::from_be_bytes([s[0], s[1], s[2], s[3]])).ok_or(ReadReject::Truncated(what))
}

/// Parses an INDEX at `pos`; returns absolute (start,end) ranges and the position after it.
fn read_index(b: &[u8], pos: usize, what: &'static str) -> Result<(Vec<(usize, usize)>, usize), ReadReject> {
    let count = u16_at(b, pos, what)? as usize;
    if count == 0 { return Ok((Vec::new(), pos + 2)); }
    let off_size = *b.get(pos + 2).ok_or(ReadReject::Truncated(what))? as usize;
    if !(1..=4).contains(&off_size) { return Err(ReadReject::BadIndex(what)); }
    let offs_at = pos + 3;
    let data_base = offs_at + (count + 1) * off_size - 1;
    let mut offs = Vec::with_capacity(count + 1);
    for i in 0..=count {
        let s = b.get(offs_at + i * off_size..offs_at + (i + 1) * off_size).ok_or(ReadReject::Truncated(what))?;
        offs.push(s.iter().fold(0usize, |a, &x| (a << 8) | x as usize));
    }
    if offs[0] != 1 { return Err(ReadReject::BadIndex(what)); }
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        if offs[i + 1] < offs[i] { return Err(ReadReject::BadIndex(what)); }
        let (s, e) = (data_base + offs[i], data_base + offs[i + 1]);
        if e > b.len() { return Err(ReadReject::Truncated(what)); }
        out.push((s, e));
    }
    Ok((out, data_base + offs[count]))
}

/// DICT parser: returns (operator, operands). Escape operators are 0x0c00 | b1.
fn read_dict(d: &[u8]) -> Result<Vec<(u16, Vec<f64>)>, ReadReject> {
    let mut out = Vec::new();
    let mut args: Vec<f64> = Vec::new();
    let mut i = 0;
    let bad = ReadReject::BadDict("dict");
    while i < d.len() {
        let b0 = d[i];
        match b0 {
            0..=21 => {
                let op = if b0 == 12 { i += 1; 0x0c00 | *d.get(i).ok_or(bad.clone())? as u16 } else { b0 as u16 };
                out.push((op, std::mem::take(&mut args)));
                i += 1;
            }
            28 => { let s = d.get(i + 1..i + 3).ok_or(bad.clone())?; args.push(i16::from_be_bytes([s[0], s[1]]) as f64); i += 3; }
            29 => { let s = d.get(i + 1..i + 5).ok_or(bad.clone())?; args.push(i32::from_be_bytes([s[0], s[1], s[2], s[3]]) as f64); i += 5; }
            30 => {
                let mut txt = String::new();
                i += 1;
                'real: loop {
                    let byte = *d.get(i).ok_or(bad.clone())?;
                    i += 1;
                    for nib in [byte >> 4, byte & 15] {
                        match nib {
                            0..=9 => txt.push((b'0' + nib) as char),
                            10 => txt.push('.'),
                            11 => txt.push('E'),
                            12 => txt.push_str("E-"),
                            14 => txt.push('-'),
                            15 => break 'real,
                            _ => return Err(bad),
                        }
                    }
                }
                args.push(txt.parse::<f64>().map_err(|_| bad.clone())?);
            }
            32..=246 => { args.push(b0 as f64 - 139.0); i += 1; }
            247..=250 => { let b1 = *d.get(i + 1).ok_or(bad.clone())? as f64; args.push((b0 as f64 - 247.0) * 256.0 + b1 + 108.0); i += 2; }
            251..=254 => { let b1 = *d.get(i + 1).ok_or(bad.clone())? as f64; args.push(-(b0 as f64 - 251.0) * 256.0 - b1 - 108.0); i += 2; }
            _ => return Err(bad),
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------- Type 2 interpreter
#[derive(Clone, Debug)]
pub struct ReadGlyph {
    pub gid: u16,
    /// Charstring width (nominalWidthX + delta, or defaultWidthX). Informational; hmtx is not read.
    pub width: Option<f64>,
    pub rings: Vec<ReferenceRing>,
    pub stem_count: usize,
    pub implicit_closures: usize,
}
impl ReadGlyph {
    pub fn drawn(self, glyph_id: String) -> DrawnGlyph { DrawnGlyph { glyph_id, rings: self.rings } }
}

const MAX_STACK: usize = 48;
const MAX_DEPTH: usize = 10;

struct Interp<'a> {
    global: &'a [&'a [u8]],
    local: &'a [&'a [u8]],
    stack: Vec<f64>,
    x: f64,
    y: f64,
    nstems: usize,
    width_done: bool,
    width: Option<f64>,
    nominal: f64,
    default_w: f64,
    start: Option<Point>,
    spans: Vec<Span>,
    rings: Vec<ReferenceRing>,
    closures: usize,
    ended: bool,
}

fn bias(n: usize) -> i64 { if n < 1240 { 107 } else if n < 33900 { 1131 } else { 32768 } }

impl<'a> Interp<'a> {
    fn push(&mut self, v: f64) -> Result<(), ReadReject> {
        if self.stack.len() >= MAX_STACK { return Err(ReadReject::StackOverflow); }
        self.stack.push(v);
        Ok(())
    }
    fn width_from(&mut self, has_extra: bool) {
        if !self.width_done {
            self.width_done = true;
            self.width = Some(if has_extra { self.nominal + self.stack.remove(0) } else { self.default_w });
        }
    }
    fn close_ring(&mut self) {
        if let Some(start) = self.start.take() {
            if !self.spans.is_empty() {
                let cur = match self.spans.last() { Some(Span::Line { end }) | Some(Span::Cubic { end, .. }) => *end, None => start };
                if cur != start { self.spans.push(Span::Line { end: start }); self.closures += 1; }
                self.rings.push(ReferenceRing { start, spans: std::mem::take(&mut self.spans) });
            }
        }
        self.spans.clear();
    }
    fn moveto(&mut self, dx: f64, dy: f64) {
        self.close_ring();
        self.x += dx;
        self.y += dy;
        self.start = Some(Point { x: self.x, y: self.y });
    }
    fn need_start(&self) -> Result<(), ReadReject> { if self.start.is_none() { Err(ReadReject::DrawBeforeMoveto) } else { Ok(()) } }
    fn line(&mut self, dx: f64, dy: f64) {
        self.x += dx;
        self.y += dy;
        self.spans.push(Span::Line { end: Point { x: self.x, y: self.y } });
    }
    fn curve(&mut self, d: [f64; 6]) {
        let c1 = Point { x: self.x + d[0], y: self.y + d[1] };
        let c2 = Point { x: c1.x + d[2], y: c1.y + d[3] };
        let e = Point { x: c2.x + d[4], y: c2.y + d[5] };
        self.x = e.x;
        self.y = e.y;
        self.spans.push(Span::Cubic { control_one: c1, control_two: c2, end: e });
    }
    fn args_ok(&self, op: u16, ok: bool) -> Result<(), ReadReject> {
        if ok { Ok(()) } else { Err(ReadReject::BadArgumentCount { op, count: self.stack.len() }) }
    }

    fn run(&mut self, code: &[u8], depth: usize) -> Result<(), ReadReject> {
        let mut i = 0usize;
        while i < code.len() {
            let b0 = code[i];
            i += 1;
            match b0 {
                32..=246 => self.push(b0 as f64 - 139.0)?,
                247..=250 => { let b1 = *code.get(i).ok_or(ReadReject::TruncatedOperand)? as f64; i += 1; self.push((b0 as f64 - 247.0) * 256.0 + b1 + 108.0)?; }
                251..=254 => { let b1 = *code.get(i).ok_or(ReadReject::TruncatedOperand)? as f64; i += 1; self.push(-(b0 as f64 - 251.0) * 256.0 - b1 - 108.0)?; }
                28 => { let s = code.get(i..i + 2).ok_or(ReadReject::TruncatedOperand)?; i += 2; self.push(i16::from_be_bytes([s[0], s[1]]) as f64)?; }
                255 => { let s = code.get(i..i + 4).ok_or(ReadReject::TruncatedOperand)?; i += 4; self.push(i32::from_be_bytes([s[0], s[1], s[2], s[3]]) as f64 / 65536.0)?; }
                1 | 3 | 18 | 23 => {
                    let op = b0 as u16;
                    let extra = self.stack.len() % 2 == 1;
                    self.width_from(extra);
                    self.args_ok(op, !self.stack.is_empty())?;
                    self.nstems += self.stack.len() / 2;
                    self.stack.clear();
                }
                19 | 20 => {
                    let op = b0 as u16;
                    let extra = self.stack.len() % 2 == 1;
                    self.width_from(extra);
                    self.nstems += self.stack.len() / 2;
                    self.stack.clear();
                    let n = (self.nstems + 7) / 8;
                    if i + n > code.len() { return Err(ReadReject::TruncatedHintmask); }
                    i += n;
                    let _ = op;
                }
                21 => { let n = self.stack.len(); self.width_from(n > 2); self.args_ok(21, self.stack.len() == 2)?; let (dx, dy) = (self.stack[0], self.stack[1]); self.stack.clear(); self.moveto(dx, dy); }
                22 => { let n = self.stack.len(); self.width_from(n > 1); self.args_ok(22, self.stack.len() == 1)?; let dx = self.stack[0]; self.stack.clear(); self.moveto(dx, 0.0); }
                4 => { let n = self.stack.len(); self.width_from(n > 1); self.args_ok(4, self.stack.len() == 1)?; let dy = self.stack[0]; self.stack.clear(); self.moveto(0.0, dy); }
                5 => {
                    self.need_start()?;
                    self.args_ok(5, self.stack.len() >= 2 && self.stack.len() % 2 == 0)?;
                    let a = std::mem::take(&mut self.stack);
                    for p in a.chunks(2) { self.line(p[0], p[1]); }
                }
                6 | 7 => {
                    self.need_start()?;
                    self.args_ok(b0 as u16, !self.stack.is_empty())?;
                    let a = std::mem::take(&mut self.stack);
                    let mut horiz = b0 == 6;
                    for v in a { if horiz { self.line(v, 0.0) } else { self.line(0.0, v) } horiz = !horiz; }
                }
                8 => {
                    self.need_start()?;
                    self.args_ok(8, !self.stack.is_empty() && self.stack.len() % 6 == 0)?;
                    let a = std::mem::take(&mut self.stack);
                    for c in a.chunks(6) { self.curve([c[0], c[1], c[2], c[3], c[4], c[5]]); }
                }
                24 => {
                    self.need_start()?;
                    let n = self.stack.len();
                    self.args_ok(24, n >= 8 && (n - 2) % 6 == 0)?;
                    let a = std::mem::take(&mut self.stack);
                    let curves = (n - 2) / 6;
                    for k in 0..curves { let c = &a[6 * k..6 * k + 6]; self.curve([c[0], c[1], c[2], c[3], c[4], c[5]]); }
                    self.line(a[n - 2], a[n - 1]);
                }
                25 => {
                    self.need_start()?;
                    let n = self.stack.len();
                    self.args_ok(25, n >= 8 && (n - 6) % 2 == 0)?;
                    let a = std::mem::take(&mut self.stack);
                    let lines = (n - 6) / 2;
                    for k in 0..lines { self.line(a[2 * k], a[2 * k + 1]); }
                    let c = &a[n - 6..];
                    self.curve([c[0], c[1], c[2], c[3], c[4], c[5]]);
                }
                26 => {
                    self.need_start()?;
                    let n = self.stack.len();
                    self.args_ok(26, n >= 4 && n % 4 <= 1)?;
                    let a = std::mem::take(&mut self.stack);
                    let (mut dx1, mut k) = (0.0, 0);
                    if n % 4 == 1 { dx1 = a[0]; k = 1; }
                    while k + 4 <= n { self.curve([dx1, a[k], a[k + 1], a[k + 2], 0.0, a[k + 3]]); dx1 = 0.0; k += 4; }
                }
                27 => {
                    self.need_start()?;
                    let n = self.stack.len();
                    self.args_ok(27, n >= 4 && n % 4 <= 1)?;
                    let a = std::mem::take(&mut self.stack);
                    let (mut dy1, mut k) = (0.0, 0);
                    if n % 4 == 1 { dy1 = a[0]; k = 1; }
                    while k + 4 <= n { self.curve([a[k], dy1, a[k + 1], a[k + 2], a[k + 3], 0.0]); dy1 = 0.0; k += 4; }
                }
                30 | 31 => {
                    self.need_start()?;
                    let n = self.stack.len();
                    self.args_ok(b0 as u16, n >= 4 && n % 4 <= 1)?;
                    let a = std::mem::take(&mut self.stack);
                    let mut horiz = b0 == 31;
                    let mut k = 0;
                    while k + 4 <= n {
                        let last = n - k == 5;
                        let extra = if last { a[k + 4] } else { 0.0 };
                        if horiz { self.curve([a[k], 0.0, a[k + 1], a[k + 2], extra, a[k + 3]]); } else { self.curve([0.0, a[k], a[k + 1], a[k + 2], a[k + 3], extra]); }
                        horiz = !horiz;
                        k += 4;
                    }
                }
                10 | 29 => {
                    let subrs = if b0 == 10 { self.local } else { self.global };
                    let idx = self.stack.pop().ok_or(ReadReject::StackUnderflow)?;
                    let n = idx as i64 + bias(subrs.len());
                    if idx.fract() != 0.0 || n < 0 || n as usize >= subrs.len() { return Err(ReadReject::SubrOutOfRange); }
                    if depth + 1 > MAX_DEPTH { return Err(ReadReject::SubrDepthExceeded); }
                    let body = subrs[n as usize];
                    self.run(body, depth + 1)?;
                    if self.ended { return Ok(()); }
                }
                11 => return Ok(()),
                14 => {
                    let n = self.stack.len();
                    self.width_from(n == 1 || n == 5);
                    if self.stack.len() == 4 { return Err(ReadReject::Seac); }
                    self.args_ok(14, self.stack.is_empty())?;
                    self.close_ring();
                    self.ended = true;
                    return Ok(());
                }
                12 => {
                    let b1 = *code.get(i).ok_or(ReadReject::TruncatedOperand)?;
                    i += 1;
                    let op = 0x0c00 | b1 as u16;
                    match b1 {
                        35 | 34 | 36 | 37 => {
                            self.need_start()?;
                            let a = std::mem::take(&mut self.stack);
                            let n = a.len();
                            let want = match b1 { 35 => 13, 34 => 7, 36 => 9, _ => 11 };
                            if n != want { return Err(ReadReject::BadArgumentCount { op, count: n }); }
                            match b1 {
                                35 => { self.curve([a[0], a[1], a[2], a[3], a[4], a[5]]); self.curve([a[6], a[7], a[8], a[9], a[10], a[11]]); }
                                34 => { self.curve([a[0], 0.0, a[1], a[2], a[3], 0.0]); self.curve([a[4], 0.0, a[5], -a[2], a[6], 0.0]); }
                                36 => { self.curve([a[0], a[1], a[2], a[3], a[4], 0.0]); self.curve([a[5], 0.0, a[6], a[7], a[8], -(a[1] + a[3] + a[7])]); }
                                _ => {
                                    let dx = a[0] + a[2] + a[4] + a[6] + a[8];
                                    let dy = a[1] + a[3] + a[5] + a[7] + a[9];
                                    let (dx6, dy6) = if dx.abs() > dy.abs() { (a[10], -dy) } else { (-dx, a[10]) };
                                    self.curve([a[0], a[1], a[2], a[3], a[4], a[5]]);
                                    self.curve([a[6], a[7], a[8], a[9], dx6, dy6]);
                                }
                            }
                        }
                        _ => return Err(ReadReject::UnsupportedOperator(op)),
                    }
                }
                // reserved / unsupported single-byte codes
                _ => return Err(ReadReject::UnsupportedOperator(b0 as u16)),
            }
        }
        Ok(())
    }
}

/// Interpret one Type 2 charstring. Subr slices are taken in INDEX order (bias applied here).
pub fn interpret_type2(gid: u16, code: &[u8], global: &[&[u8]], local: &[&[u8]], default_width: f64, nominal_width: f64) -> Result<ReadGlyph, ReadReject> {
    let mut it = Interp {
        global, local, stack: Vec::new(), x: 0.0, y: 0.0, nstems: 0, width_done: false, width: None,
        nominal: nominal_width, default_w: default_width, start: None, spans: Vec::new(), rings: Vec::new(), closures: 0, ended: false,
    };
    it.run(code, 0)?;
    if !it.ended { return Err(ReadReject::MissingEndchar); }
    Ok(ReadGlyph { gid, width: it.width, rings: it.rings, stem_count: it.nstems, implicit_closures: it.closures })
}

// ---------------------------------------------------------------- font container
pub struct CffReader {
    bytes: Vec<u8>,
    sha: String,
    charstrings: Vec<(usize, usize)>,
    global: Vec<(usize, usize)>,
    local: Vec<(usize, usize)>,
    default_width: f64,
    nominal_width: f64,
    cmap: BTreeMap<u32, u16>,
    cmap_choice: (u16, u16, u16),
    units_per_em: u16,
}

fn parse_cmap(b: &[u8], glyphs: usize) -> Result<(BTreeMap<u32, u16>, (u16, u16, u16)), ReadReject> {
    let n = u16_at(b, 2, "cmap")? as usize;
    let mut recs = Vec::new();
    for k in 0..n {
        let o = 4 + 8 * k;
        recs.push((u16_at(b, o, "cmap")?, u16_at(b, o + 2, "cmap")?, u32_at(b, o + 4, "cmap")? as usize));
    }
    let pref: [(u16, u16); 7] = [(3, 10), (0, 6), (0, 4), (3, 1), (0, 3), (0, 2), (0, 1)];
    let mut first_bad_format = None;
    for (p, e) in pref {
        for &(rp, re, off) in &recs {
            if (rp, re) != (p, e) { continue; }
            let fmt = u16_at(b, off, "cmap")?;
            let mut map = BTreeMap::new();
            match fmt {
                12 => {
                    let ng = u32_at(b, off + 12, "cmap12")? as usize;
                    for g in 0..ng {
                        let o = off + 16 + 12 * g;
                        let (s, en, sg) = (u32_at(b, o, "cmap12")?, u32_at(b, o + 4, "cmap12")?, u32_at(b, o + 8, "cmap12")?);
                        if en < s || en - s > 0x10FFFF { return Err(ReadReject::BadIndex("cmap12 group")); }
                        for c in s..=en {
                            let gid = sg as u64 + (c - s) as u64;
                            if gid == 0 { continue; }
                            if gid as usize >= glyphs { return Err(ReadReject::CmapGlyphOutOfRange { codepoint: c, glyph: gid.min(0xffff) as u16 }); }
                            map.insert(c, gid as u16);
                        }
                    }
                }
                4 => {
                    let segx2 = u16_at(b, off + 6, "cmap4")? as usize;
                    let seg = segx2 / 2;
                    let end_at = off + 14;
                    let start_at = end_at + segx2 + 2;
                    let delta_at = start_at + segx2;
                    let range_at = delta_at + segx2;
                    for s in 0..seg {
                        let end = u16_at(b, end_at + 2 * s, "cmap4")? as u32;
                        let start = u16_at(b, start_at + 2 * s, "cmap4")? as u32;
                        let delta = u16_at(b, delta_at + 2 * s, "cmap4")?;
                        let ro = u16_at(b, range_at + 2 * s, "cmap4")? as usize;
                        if start > end { return Err(ReadReject::BadIndex("cmap4 segment")); }
                        for c in start..=end {
                            if c == 0xFFFF { continue; }
                            let gid = if ro == 0 { (c as u16).wrapping_add(delta) } else {
                                let at = range_at + 2 * s + ro + 2 * (c - start) as usize;
                                let g = u16_at(b, at, "cmap4")?;
                                if g == 0 { 0 } else { g.wrapping_add(delta) }
                            };
                            if gid == 0 { continue; }
                            if gid as usize >= glyphs { return Err(ReadReject::CmapGlyphOutOfRange { codepoint: c, glyph: gid }); }
                            map.insert(c, gid);
                        }
                    }
                }
                other => { first_bad_format.get_or_insert(other); continue; }
            }
            return Ok((map, (p, e, fmt)));
        }
    }
    match first_bad_format { Some(f) => Err(ReadReject::CmapUnsupportedFormat(f)), None => Err(ReadReject::CmapNoUsableSubtable) }
}

impl CffReader {
    /// `expected_sha256` (64 lowercase hex) is mandatory: the bytes are verified before any parsing.
    pub fn from_bytes(bytes: &[u8], expected_sha256: &str) -> Result<Self, ReadReject> {
        if expected_sha256.len() != 64 || !expected_sha256.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) {
            return Err(ReadReject::BadExpectedSha);
        }
        let actual = sha256_hex(bytes);
        if actual != expected_sha256 { return Err(ReadReject::ShaMismatch { expected: expected_sha256.to_string(), actual }); }
        let version = u32_at(bytes, 0, "sfnt header")?;
        if version != 0x4F54544F { return Err(ReadReject::NotOtto(version)); }
        let nt = u16_at(bytes, 4, "sfnt header")? as usize;
        let mut tables: BTreeMap<[u8; 4], (usize, usize)> = BTreeMap::new();
        for k in 0..nt {
            let o = 12 + 16 * k;
            let rec = bytes.get(o..o + 16).ok_or(ReadReject::Truncated("table directory"))?;
            let tag = [rec[0], rec[1], rec[2], rec[3]];
            let off = u32::from_be_bytes([rec[8], rec[9], rec[10], rec[11]]) as usize;
            let len = u32::from_be_bytes([rec[12], rec[13], rec[14], rec[15]]) as usize;
            if off.checked_add(len).map_or(true, |e| e > bytes.len()) { return Err(ReadReject::TableOutOfBounds(tag)); }
            if tables.insert(tag, (off, len)).is_some() { return Err(ReadReject::DuplicateTable(tag)); }
        }
        let (coff, clen) = *tables.get(b"CFF ").ok_or(ReadReject::MissingTable(*b"CFF "))?;
        let (moff, mlen) = *tables.get(b"cmap").ok_or(ReadReject::MissingTable(*b"cmap"))?;
        // CFF is parsed inside its own table slice; offsets in CFF are relative to its start.
        let cff = &bytes[coff..coff + clen];
        if cff.len() < 4 || cff[0] != 1 { return Err(ReadReject::Truncated("CFF header")); }
        let hdr = cff[2] as usize;
        let (_names, p) = read_index(cff, hdr, "Name INDEX")?;
        let (tops, p) = read_index(cff, p, "Top DICT INDEX")?;
        let (_strings, p) = read_index(cff, p, "String INDEX")?;
        let (gsubrs, _) = read_index(cff, p, "Global Subr INDEX")?;
        if tops.len() != 1 { return Err(ReadReject::BadIndex("Top DICT INDEX count")); }
        let top = read_dict(&cff[tops[0].0..tops[0].1])?;
        let mut cs_off = None;
        let mut private = None;
        let mut cs_type = 2i64;
        let mut font_matrix: Option<Vec<f64>> = None;
        for (op, args) in &top {
            match *op {
                0x0c1e | 0x0c24 | 0x0c25 => return Err(ReadReject::CidKeyed),
                17 => cs_off = args.first().map(|v| *v as usize),
                18 => if args.len() == 2 { private = Some((args[0] as usize, args[1] as usize)); } else { return Err(ReadReject::BadDict("Private")); },
                0x0c06 => cs_type = args.first().map(|v| *v as i64).unwrap_or(2),
                0x0c07 => { font_matrix = Some(args.clone()); }
                _ => {}
            }
        }
        // Narrow support contract: only 1000 units per em with the CFF default FontMatrix
        // [0.001 0 0 0.001 0 0] (absent, or present and exactly equal). Any other scale, shear or
        // translation is a typed reject; there is no tolerance and no 1/upm inference.
        let (hoff, hlen) = *tables.get(b"head").ok_or(ReadReject::MissingTable(*b"head"))?;
        let upm = u16_at(&bytes[hoff..hoff + hlen], 18, "head")?;
        if upm != 1000 { return Err(ReadReject::UnitsPerEmNotThousand(upm)); }
        if let Some(m) = &font_matrix {
            if m.as_slice() != [0.001, 0.0, 0.0, 0.001, 0.0, 0.0] { return Err(ReadReject::NonDefaultFontMatrix); }
        }
        if cs_type != 2 { return Err(ReadReject::CharstringTypeNotTwo(cs_type)); }
        let cs_off = cs_off.ok_or(ReadReject::MissingTopDictEntry("CharStrings"))?;
        let (charstrings, _) = read_index(cff, cs_off, "CharStrings INDEX")?;
        let (psize, poff) = private.ok_or(ReadReject::MissingTopDictEntry("Private"))?;
        let pdata = cff.get(poff..poff.checked_add(psize).ok_or(ReadReject::BadDict("Private"))?).ok_or(ReadReject::Truncated("Private DICT"))?;
        let pd = read_dict(pdata)?;
        let (mut dw, mut nw, mut subrs_rel) = (0.0, 0.0, None);
        for (op, args) in &pd {
            match *op {
                19 => subrs_rel = args.first().map(|v| *v as usize),
                20 => dw = args.first().copied().unwrap_or(0.0),
                21 => nw = args.first().copied().unwrap_or(0.0),
                _ => {}
            }
        }
        let local = match subrs_rel { Some(rel) => read_index(cff, poff + rel, "Local Subr INDEX")?.0, None => Vec::new() };
        let shift = |v: Vec<(usize, usize)>| v.into_iter().map(|(s, e)| (s + coff, e + coff)).collect::<Vec<_>>();
        let (cmap, cmap_choice) = parse_cmap(&bytes[moff..moff + mlen], charstrings.len())?;
        Ok(CffReader {
            bytes: bytes.to_vec(), sha: actual, charstrings: shift(charstrings), global: shift(gsubrs), local: shift(local),
            default_width: dw, nominal_width: nw, cmap, cmap_choice, units_per_em: upm,
        })
    }
    pub fn units_per_em(&self) -> u16 { self.units_per_em }
    pub fn sha256(&self) -> &str { &self.sha }
    pub fn glyph_count(&self) -> usize { self.charstrings.len() }
    pub fn global_subr_count(&self) -> usize { self.global.len() }
    pub fn local_subr_count(&self) -> usize { self.local.len() }
    /// (platform, encoding, format) of the cmap subtable used.
    pub fn cmap_choice(&self) -> (u16, u16, u16) { self.cmap_choice }
    pub fn glyph_for_codepoint(&self, cp: u32) -> Option<u16> { self.cmap.get(&cp).copied() }
    pub fn codepoints(&self) -> Vec<(u32, u16)> { self.cmap.iter().map(|(a, b)| (*a, *b)).collect() }
    pub fn read_glyph(&self, gid: u16) -> Result<ReadGlyph, ReadReject> {
        let (s, e) = *self.charstrings.get(gid as usize).ok_or(ReadReject::GlyphOutOfRange(gid))?;
        let g: Vec<&[u8]> = self.global.iter().map(|&(a, b)| &self.bytes[a..b]).collect();
        let l: Vec<&[u8]> = self.local.iter().map(|&(a, b)| &self.bytes[a..b]).collect();
        interpret_type2(gid, &self.bytes[s..e], &g, &l, self.default_width, self.nominal_width)
    }
    pub fn read_codepoint(&self, cp: u32) -> Result<Option<ReadGlyph>, ReadReject> {
        match self.glyph_for_codepoint(cp) { Some(g) => self.read_glyph(g).map(Some), None => Ok(None) }
    }
}
