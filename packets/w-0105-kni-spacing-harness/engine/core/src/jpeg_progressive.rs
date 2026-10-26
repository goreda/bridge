//! Bounded, dependency-free progressive (SOF2, Huffman, 8-bit) JPEG -> raw luma.
//!
//! Same output contract as `jpeg_source` (raw Y, no colour conversion, no PNG
//! conversion, EXIF orientation never applied) and the same bit-exact Q14 IDCT,
//! but coefficients are accumulated across scans (DC first/refine, AC first/refine,
//! EOB runs) and transformed once at the end.
//!
//! Supported subset: 8-bit, 1 or 3 components (same colour/sampling gates as the
//! baseline decoder), restart intervals, DHT/DQT between scans. The scan script
//! must be COMPLETE: every coefficient of every component must reach successive
//! approximation Al=0 with a valid Ah/Al chain, otherwise `UnsupportedScan`
//! (a truncated progression is refused, never silently decoded at lower quality).
//! Refused with typed errors: arithmetic coding, lossless, hierarchical, 12-bit,
//! 16-bit quant tables, DNL, interlaced-component scans in AC bands, trailing data.
//!
//! Budget (checked before any allocation, major payload only): coefficient store
//! (i16 per coefficient, padded to whole MCUs for every component) + output pixels +
//! hash peak + fixed tables. Not allocator overhead, RSS or Huffman scratch.
//! Validation evidence (unit tests): bit-exact parity with the baseline decoder on
//! identical quantized coefficients; raw-Y within 1 level of libjpeg (Pillow) on every
//! fixture (the Q14 IDCT and libjpeg islow round differently by at most 1); restart
//! intervals with DC first/refine, AC first/refine and EOB-run resets (hand-written
//! encoder, gen_dri_progressive.py). An EOB run crossing a restart or the scan end is
//! refused (MalformedEntropy). Colour state (JFIF/Adobe) is frozen at SOF; a later change
//! is UnsupportedColour. Constant-bounded pre-SOF scratch is charged before tables parse.
use crate::jpeg_source::{
    idct, sha256_hex, take, u16be, zeroes, Bits, DecodedGray, Huff,
    IdentityReceipt, JpegError, Limits, ZZ,
};

pub const DECODER_VERSION: &str = "kni.jpeg-progressive.v1-q14";
const CONFIG_PIN_TEXT: &[u8] = b"kni.jpeg-progressive.config.v1\nIDCT=Q14-direct\nround=floor(x+0.5)\nmode=sof2-huffman-8bit\nscript=complete-required\noutput=raw-Y\ntrailing=refuse\n";

/// True when the first SOF marker in the header is SOF2. Allocation-free; never
/// reads past the data; any structural problem returns false (the baseline path
/// then reports its own typed error).
pub fn is_progressive(data: &[u8]) -> bool {
    if data.get(..2) != Some(&[255, 216][..]) {
        return false;
    }
    let mut pos = 2usize;
    loop {
        if data.get(pos) != Some(&255) {
            return false;
        }
        pos += 1;
        let mut m = match data.get(pos) {
            Some(&m) => m,
            None => return false,
        };
        pos += 1;
        while m == 255 {
            m = match data.get(pos) {
                Some(&m) => m,
                None => return false,
            };
            pos += 1;
        }
        match m {
            0xc2 => return true,
            0xc0 | 0xc1 | 0xc3 | 0xc5..=0xc7 | 0xc9..=0xcb | 0xcd..=0xcf | 0xda | 0xd9 | 0xd8 | 0x00 | 0x01 | 0xd0..=0xd7 => return false,
            _ => {
                let len = match (data.get(pos), data.get(pos + 1)) {
                    (Some(&a), Some(&b)) => ((a as usize) << 8) | b as usize,
                    _ => return false,
                };
                if len < 2 {
                    return false;
                }
                pos = match pos.checked_add(len) {
                    Some(p) => p,
                    None => return false,
                };
            }
        }
    }
}

struct Comp {
    id: u8,
    h: usize,
    v: usize,
    q: usize,
    bw: usize,      // padded blocks per row (cols*h)
    bh: usize,      // padded block rows (rows*v)
    real_bw: usize, // non-interleaved blocks per row
    real_bh: usize,
    coef: Vec<i16>, // bw*bh*64, zigzag order
    pred: i32,
    qtab: Option<[u16; 64]>,
    al: [u8; 64], // 255 = coefficient not yet seen
}

fn raw_bits(b: &mut Bits<'_>, n: u8) -> Result<u32, JpegError> {
    let mut v = 0u32;
    for _ in 0..n {
        v = (v << 1) | b.bit()? as u32;
    }
    Ok(v)
}
fn shl_i16(v: i32, al: u8) -> Result<i16, JpegError> {
    let x = v.checked_mul(1i32 << al).ok_or(JpegError::CoefficientBound)?;
    i16::try_from(x).map_err(|_| JpegError::CoefficientBound)
}

pub fn decode(data: &[u8], limits: Limits) -> Result<DecodedGray, JpegError> {
    if data.len() > limits.max_input_bytes {
        return Err(JpegError::ResourceLimit);
    }
    if data.get(..2) != Some(&[255, 216][..]) {
        return Err(JpegError::BadSignature);
    }
    // Constant-bounded scratch that exists before any SOF is seen (8 Huffman tables of
    // <=256 entries, 4 quant tables, <=3 components) is charged against the working
    // cap BEFORE the first table is parsed. Marker segments are borrowed, never copied.
    let pre_sof = 8usize
        .checked_mul(256 * std::mem::size_of::<(u16, u8, u8)>())
        .and_then(|v| v.checked_add(4 * std::mem::size_of::<[u16; 64]>() + 3 * std::mem::size_of::<Comp>()))
        .ok_or(JpegError::ArithmeticOverflow)?;
    if pre_sof > limits.max_working_bytes {
        return Err(JpegError::ResourceLimit);
    }
    let mut pos = 2usize;
    let mut adobe_at_sof: Option<Option<u8>> = None;
    let mut jfif_at_sof = false;
    let mut quant: [Option<[u16; 64]>; 4] = [None, None, None, None];
    let mut dc: [Option<Huff>; 4] = [None, None, None, None];
    let mut ac: [Option<Huff>; 4] = [None, None, None, None];
    let mut comps: Vec<Comp> = Vec::new();
    let (mut w, mut h) = (0usize, 0usize);
    // allow rationale: mh/mv start at 1x1 sampling and are overwritten from the SOF components before any read.
    #[allow(unused_assignments)]
    let (mut mh, mut mv, mut cols, mut rows) = (1usize, 1usize, 0usize, 0usize);
    let mut restart = 0usize;
    let mut jfif = false;
    let mut adobe: Option<u8> = None;
    let mut scans = 0usize;
    let mut sof_seen = false;
    loop {
        if take(data, &mut pos, 1)?[0] != 255 {
            return Err(JpegError::MalformedMarker);
        }
        let mut marker = take(data, &mut pos, 1)?[0];
        while marker == 255 {
            marker = take(data, &mut pos, 1)?[0];
        }
        if marker == 0xd9 {
            // EOI: only valid after at least one scan; completeness checked below.
            if adobe_at_sof != Some(adobe) || jfif_at_sof != jfif {
                return Err(JpegError::UnsupportedColour);
            }
            if scans == 0 || pos != data.len() {
                return Err(if scans == 0 { JpegError::MalformedMarker } else { JpegError::TrailingData });
            }
            break;
        }
        if marker == 0xd8 || marker == 0x00 || (0xd0..=0xd7).contains(&marker) {
            return Err(JpegError::MalformedMarker);
        }
        if marker == 0xda && !sof_seen {
            return Err(JpegError::MalformedMarker);
        }
        if marker == 0xdc || (marker != 0xc2 && marker != 0xc4 && (0xc0..=0xcf).contains(&marker)) {
            return Err(JpegError::UnsupportedMode);
        }
        let size = u16be(take(data, &mut pos, 2)?);
        if size < 2 {
            return Err(JpegError::MalformedMarker);
        }
        let seg = take(data, &mut pos, size - 2)?;
        match marker {
            0xe0 => {
                if seg.starts_with(b"JFIF\0") {
                    if seg.len() < 14 {
                        return Err(JpegError::MalformedMarker);
                    }
                    jfif = true;
                }
            }
            0xee => {
                if seg.starts_with(b"Adobe") {
                    if seg.len() < 12 {
                        return Err(JpegError::MalformedMarker);
                    }
                    adobe = Some(seg[11]);
                }
            }
            0xe1..=0xed | 0xef | 0xfe => {}
            0xdb => {
                let mut i = 0;
                while i < seg.len() {
                    let info = take(seg, &mut i, 1)?[0];
                    let id = (info & 15) as usize;
                    if info >> 4 != 0 {
                        return Err(JpegError::UnsupportedQuantization);
                    }
                    if id > 3 {
                        return Err(JpegError::MalformedTable);
                    }
                    let q = take(seg, &mut i, 64)?;
                    let mut table = [0u16; 64];
                    for k in 0..64 {
                        if q[k] == 0 {
                            return Err(JpegError::MalformedTable);
                        }
                        table[ZZ[k]] = q[k] as u16;
                    }
                    quant[id] = Some(table);
                }
            }
            0xc4 => {
                let mut i = 0;
                while i < seg.len() {
                    let info = take(seg, &mut i, 1)?[0];
                    let id = (info & 15) as usize;
                    if id > 3 || info >> 4 > 1 {
                        return Err(JpegError::MalformedTable);
                    }
                    let counts = take(seg, &mut i, 16)?;
                    let n: usize = counts.iter().map(|&v| v as usize).sum();
                    if n > 256 {
                        return Err(JpegError::MalformedTable);
                    }
                    let table = Huff::new(counts, take(seg, &mut i, n)?)?;
                    if info >> 4 == 0 {
                        dc[id] = Some(table);
                    } else {
                        ac[id] = Some(table);
                    }
                }
            }
            0xdd => {
                if seg.len() != 2 {
                    return Err(JpegError::MalformedMarker);
                }
                restart = u16be(seg);
            }
            0xc2 => {
                if sof_seen {
                    return Err(JpegError::UnsupportedMode);
                }
                if seg.len() < 6 {
                    return Err(JpegError::Truncated);
                }
                if seg[0] != 8 {
                    return Err(JpegError::UnsupportedPrecision);
                }
                h = u16be(&seg[1..3]);
                w = u16be(&seg[3..5]);
                let n = seg[5] as usize;
                if n != 1 && n != 3 {
                    return Err(JpegError::UnsupportedColour);
                }
                if seg.len() != 6 + 3 * n {
                    return Err(JpegError::MalformedDimensions);
                }
                if w == 0 || h == 0 {
                    return Err(JpegError::MalformedDimensions);
                }
                if w.checked_mul(h).ok_or(JpegError::ArithmeticOverflow)? > limits.max_pixels {
                    return Err(JpegError::ResourceLimit);
                }
                comps.try_reserve_exact(n).map_err(|_| JpegError::AllocationFailed)?;
                for s in seg[6..].chunks_exact(3) {
                    let hh = (s[1] >> 4) as usize;
                    let vv = (s[1] & 15) as usize;
                    if hh == 0 || vv == 0 || hh > 4 || vv > 4 || s[2] > 3 {
                        return Err(JpegError::MalformedTable);
                    }
                    if comps.iter().any(|c| c.id == s[0]) {
                        return Err(JpegError::MalformedMarker);
                    }
                    comps.push(Comp { id: s[0], h: hh, v: vv, q: s[2] as usize, bw: 0, bh: 0, real_bw: 0, real_bh: 0, coef: Vec::new(), pred: 0, qtab: None, al: [255; 64] });
                }
                if comps.iter().map(|c| c.h * c.v).sum::<usize>() > 10 {
                    return Err(JpegError::UnsupportedSampling);
                }
                if n == 1 && (comps[0].h != 1 || comps[0].v != 1) {
                    return Err(JpegError::UnsupportedSampling);
                }
                if adobe.is_some() && adobe != Some(1) {
                    return Err(JpegError::UnsupportedColour);
                }
                if n == 3 {
                    if !jfif && adobe != Some(1) {
                        return Err(JpegError::UnsupportedColour);
                    }
                    if comps.iter().enumerate().any(|(i, c)| c.id != (i + 1) as u8) {
                        return Err(JpegError::UnsupportedColour);
                    }
                }
                mh = comps.iter().map(|c| c.h).max().unwrap();
                mv = comps.iter().map(|c| c.v).max().unwrap();
                if comps[0].h != mh || comps[0].v != mv || comps.iter().any(|c| mh % c.h != 0 || mv % c.v != 0) {
                    return Err(JpegError::UnsupportedSampling);
                }
                cols = (w + 8 * mh - 1) / (8 * mh);
                rows = (h + 8 * mv - 1) / (8 * mv);
                // ---- budget, checked arithmetic, BEFORE any allocation ----
                let pixels = w * h; // <= max_pixels, cannot overflow after the check above
                let mut coef_bytes = 0usize;
                for c in comps.iter_mut() {
                    c.bw = cols.checked_mul(c.h).ok_or(JpegError::ArithmeticOverflow)?;
                    c.bh = rows.checked_mul(c.v).ok_or(JpegError::ArithmeticOverflow)?;
                    let cw = (w.checked_mul(c.h).ok_or(JpegError::ArithmeticOverflow)? + mh - 1) / mh;
                    let ch = (h.checked_mul(c.v).ok_or(JpegError::ArithmeticOverflow)? + mv - 1) / mv;
                    c.real_bw = (cw + 7) / 8;
                    c.real_bh = (ch + 7) / 8;
                    let blocks = c.bw.checked_mul(c.bh).ok_or(JpegError::ArithmeticOverflow)?;
                    let bytes = blocks.checked_mul(64 * std::mem::size_of::<i16>()).ok_or(JpegError::ArithmeticOverflow)?;
                    coef_bytes = coef_bytes.checked_add(bytes).ok_or(JpegError::ArithmeticOverflow)?;
                }
                let fixed = 9usize
                    .checked_mul(256 * std::mem::size_of::<(u16, u8, u8)>())
                    .and_then(|v| v.checked_add(4 * std::mem::size_of::<[u16; 64]>() + 3 * std::mem::size_of::<Comp>() + std::mem::size_of::<[i64; 64]>() + std::mem::size_of::<[u8; 64]>()))
                    .ok_or(JpegError::ArithmeticOverflow)?;
                let hash_peak = data.len().max(pixels).checked_add(72 + 3 * 64).ok_or(JpegError::ArithmeticOverflow)?;
                let total = fixed
                    .checked_add(coef_bytes)
                    .and_then(|v| v.checked_add(pixels))
                    .and_then(|v| v.checked_add(hash_peak))
                    .ok_or(JpegError::ArithmeticOverflow)?;
                if total > limits.max_working_bytes {
                    return Err(JpegError::ResourceLimit);
                }
                for c in comps.iter_mut() {
                    let n = c.bw * c.bh * 64;
                    c.coef.try_reserve_exact(n).map_err(|_| JpegError::AllocationFailed)?;
                    c.coef.resize(n, 0);
                }
                sof_seen = true;
                adobe_at_sof = Some(adobe);
                jfif_at_sof = jfif;
            }
            0xda => {
                // colour state is frozen at SOF: a later APP0/APP14 that changes it is refused
                if adobe_at_sof != Some(adobe) || jfif_at_sof != jfif {
                    return Err(JpegError::UnsupportedColour);
                }
                let ns = *seg.first().ok_or(JpegError::Truncated)? as usize;
                if ns == 0 || ns > comps.len() || seg.len() != 1 + 2 * ns + 3 {
                    return Err(JpegError::UnsupportedScan);
                }
                let (ss, se, ahl) = (seg[1 + 2 * ns] as usize, seg[2 + 2 * ns] as usize, seg[3 + 2 * ns]);
                let (ah, al) = (ahl >> 4, ahl & 15);
                if al > 13 || ah > 13 || (ah != 0 && al != ah - 1) {
                    return Err(JpegError::UnsupportedScan);
                }
                if ss == 0 {
                    if se != 0 {
                        return Err(JpegError::UnsupportedScan);
                    }
                } else if se < ss || se > 63 || ns != 1 {
                    return Err(JpegError::UnsupportedScan);
                }
                // scan component list, in frame order, distinct
                let mut idx: Vec<usize> = Vec::new();
                idx.try_reserve_exact(ns).map_err(|_| JpegError::AllocationFailed)?;
                let mut tdc = [0usize; 3];
                let mut tac = [0usize; 3];
                for i in 0..ns {
                    let cid = seg[1 + 2 * i];
                    let ci = comps.iter().position(|c| c.id == cid).ok_or(JpegError::UnsupportedScan)?;
                    if idx.last().map_or(false, |&p| ci <= p) {
                        return Err(JpegError::UnsupportedScan);
                    }
                    let sel = seg[2 + 2 * i];
                    if sel >> 4 > 3 || sel & 15 > 3 {
                        return Err(JpegError::MalformedTable);
                    }
                    tdc[i] = (sel >> 4) as usize;
                    tac[i] = (sel & 15) as usize;
                    idx.push(ci);
                }
                // successive-approximation chain per coefficient
                for &ci in &idx {
                    for k in ss..=se {
                        let st = comps[ci].al[k];
                        if (ah == 0 && st != 255) || (ah != 0 && st != ah) {
                            return Err(JpegError::UnsupportedScan);
                        }
                    }
                    if comps[ci].qtab.is_none() {
                        comps[ci].qtab = Some(quant[comps[ci].q].ok_or(JpegError::MalformedTable)?);
                    }
                }
                let mut bits = Bits { data, pos, byte: 0, left: 0 };
                let interleaved = ns > 1;
                let (units, per_row) = if interleaved {
                    (cols.checked_mul(rows).ok_or(JpegError::ArithmeticOverflow)?, cols)
                } else {
                    let c = &comps[idx[0]];
                    (c.real_bw.checked_mul(c.real_bh).ok_or(JpegError::ArithmeticOverflow)?, c.real_bw)
                };
                let mut rst = 0u8;
                let mut eobrun = 0u32;
                for c in comps.iter_mut() {
                    c.pred = 0;
                }
                for m in 0..units {
                    if restart > 0 && m > 0 && m % restart == 0 {
                        if eobrun != 0 {
                            return Err(JpegError::MalformedEntropy); // EOB run crosses a restart boundary
                        }
                        bits.restart(rst)?;
                        rst = (rst + 1) % 8;
                        for c in comps.iter_mut() {
                            c.pred = 0;
                        }
                    }
                    for (si, &ci) in idx.iter().enumerate() {
                        let (bh_n, bw_n) = if interleaved { (comps[ci].v, comps[ci].h) } else { (1, 1) };
                        for by in 0..bh_n {
                            for bx in 0..bw_n {
                                let (blk_x, blk_y) = if interleaved {
                                    ((m % per_row) * comps[ci].h + bx, (m / per_row) * comps[ci].v + by)
                                } else {
                                    (m % per_row, m / per_row)
                                };
                                let c = &mut comps[ci];
                                let base = (blk_y * c.bw + blk_x) * 64;
                                let blk = &mut c.coef[base..base + 64];
                                if ss == 0 {
                                    if ah == 0 {
                                        let t = dc[tdc[si]].as_ref().ok_or(JpegError::MalformedTable)?;
                                        let cat = t.symbol(&mut bits)?;
                                        if cat > 11 {
                                            return Err(JpegError::MalformedTable);
                                        }
                                        c.pred = c.pred.checked_add(bits.number(cat)?).ok_or(JpegError::ArithmeticOverflow)?;
                                        blk[0] = shl_i16(c.pred, al)?;
                                    } else if bits.bit()? == 1 {
                                        blk[0] |= (1i32 << al) as i16;
                                    }
                                } else {
                                    let t = ac[tac[si]].as_ref().ok_or(JpegError::MalformedTable)?;
                                    if ah == 0 {
                                        ac_first(&mut bits, t, blk, ss, se, al, &mut eobrun)?;
                                    } else {
                                        ac_refine(&mut bits, t, blk, ss, se, al, &mut eobrun)?;
                                    }
                                }
                            }
                        }
                    }
                }
                if eobrun != 0 {
                    return Err(JpegError::MalformedEntropy); // EOB run extends past the last block of the scan
                }
                bits.align()?;
                pos = bits.pos;
                for &ci in &idx {
                    for k in ss..=se {
                        comps[ci].al[k] = al;
                    }
                }
                scans += 1;
            }
            _ => return Err(JpegError::UnsupportedMode),
        }
    }
    // ---- completeness: every coefficient fully refined, else refuse ----
    if comps.iter().any(|c| c.al.iter().any(|&a| a != 0)) {
        return Err(JpegError::UnsupportedScan);
    }
    let c0 = &comps[0];
    let qt = c0.qtab.ok_or(JpegError::MalformedTable)?;
    let mut pixels = zeroes(w * h)?;
    let beyond = comps.iter().any(|c| c.coef.chunks_exact(64).any(|b| !(-1024..=1023).contains(&(b[0] as i32))));
    for by in 0..c0.bh {
        for bx in 0..c0.bw {
            let base = (by * c0.bw + bx) * 64;
            let mut coeff = [0i64; 64];
            for k in 0..64 {
                let v = c0.coef[base + k] as i64 * qt[ZZ[k]] as i64;
                if i32::try_from(v).is_err() {
                    return Err(JpegError::CoefficientBound);
                }
                coeff[ZZ[k]] = v;
            }
            let samples = idct(&coeff)?;
            let (x0, y0) = (bx * 8, by * 8);
            for y in 0..8 {
                for x in 0..8 {
                    if x0 + x < w && y0 + y < h {
                        pixels[(y0 + y) * w + x0 + x] = samples[y * 8 + x];
                    }
                }
            }
        }
    }
    let receipt = IdentityReceipt {
        orig_sha256: sha256_hex(data)?,
        decoded_gray_sha256: sha256_hex(&pixels)?,
        orig_len: data.len(),
        w,
        h,
        dtype: "u8",
        value_range: (0, 255),
        row_order: "top_to_bottom",
        stride: w,
        serialization: "one_byte_per_sample_row_major",
        subset_status: "supported_declared_subset_progressive_sof2",
        config_pin: sha256_hex(CONFIG_PIN_TEXT)?,
        decoder_version: DECODER_VERSION,
        beyond_nominal_quantized_11bit: beyond,
    };
    Ok(DecodedGray { w, h, pixels, receipt })
}

fn ac_first(b: &mut Bits<'_>, t: &Huff, blk: &mut [i16], ss: usize, se: usize, al: u8, eobrun: &mut u32) -> Result<(), JpegError> {
    if *eobrun > 0 {
        *eobrun -= 1;
        return Ok(());
    }
    let mut k = ss;
    while k <= se {
        let s = t.symbol(b)?;
        let (r, n) = ((s >> 4) as usize, s & 15);
        if n != 0 {
            if n > 10 {
                return Err(JpegError::MalformedEntropy);
            }
            k += r;
            if k > se {
                return Err(JpegError::MalformedEntropy);
            }
            blk[k] = shl_i16(b.number(n)?, al)?;
            k += 1;
        } else if r == 15 {
            k += 16;
            if k > se + 1 {
                return Err(JpegError::MalformedEntropy);
            }
        } else {
            *eobrun = 1u32 << r;
            if r > 0 {
                *eobrun += raw_bits(b, r as u8)?;
            }
            *eobrun -= 1;
            break;
        }
    }
    Ok(())
}

fn refine_nonzero(b: &mut Bits<'_>, c: &mut i16, p1: i16, m1: i16) -> Result<(), JpegError> {
    if b.bit()? == 1 && (*c & p1) == 0 {
        *c = c.checked_add(if *c >= 0 { p1 } else { m1 }).ok_or(JpegError::CoefficientBound)?;
    }
    Ok(())
}

fn ac_refine(b: &mut Bits<'_>, t: &Huff, blk: &mut [i16], ss: usize, se: usize, al: u8, eobrun: &mut u32) -> Result<(), JpegError> {
    let p1: i16 = 1i16 << al;
    let m1: i16 = -p1;
    let mut k = ss;
    if *eobrun == 0 {
        while k <= se {
            let s = t.symbol(b)?;
            let (mut r, n) = ((s >> 4) as i32, s & 15);
            let mut val: i16 = 0;
            if n != 0 {
                if n != 1 {
                    return Err(JpegError::MalformedEntropy);
                }
                val = if b.bit()? == 1 { p1 } else { m1 };
            } else if r != 15 {
                *eobrun = 1u32 << r;
                if r > 0 {
                    *eobrun += raw_bits(b, r as u8)?;
                }
                break;
            }
            loop {
                if k > se {
                    // ran off the band while skipping: only a pure ZRL at the very end is
                    // tolerated by no decoder; refuse as malformed.
                    return Err(JpegError::MalformedEntropy);
                }
                if blk[k] != 0 {
                    refine_nonzero(b, &mut blk[k], p1, m1)?;
                } else {
                    r -= 1;
                    if r < 0 {
                        break;
                    }
                }
                k += 1;
            }
            if val != 0 {
                blk[k] = val;
            }
            k += 1;
        }
    }
    if *eobrun > 0 {
        while k <= se {
            if blk[k] != 0 {
                refine_nonzero(b, &mut blk[k], p1, m1)?;
            }
            k += 1;
        }
        *eobrun -= 1;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::jpeg_source;
    const BIG: Limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 22, max_working_bytes: 1 << 28 };
    macro_rules! fx {
        ($n:expr) => {
            (
                include_bytes!(concat!("../tests/fixtures/jpeg_progressive/", $n, ".base.jpg")) as &[u8],
                include_bytes!(concat!("../tests/fixtures/jpeg_progressive/", $n, ".prog.jpg")) as &[u8],
            )
        };
    }
    fn cases() -> Vec<(&'static str, &'static [u8], &'static [u8])> {
        let v = [
            ("gray_17x13", fx!("gray_17x13")),
            ("gray_64x48_q95", fx!("gray_64x48_q95")),
            ("gray_1x1", fx!("gray_1x1")),
            ("gray_grad_40x40", fx!("gray_grad_40x40")),
            ("ycbcr_444_23x19", fx!("ycbcr_444_23x19")),
            ("ycbcr_420_35x27", fx!("ycbcr_420_35x27")),
            ("ycbcr_422_40x16", fx!("ycbcr_422_40x16")),
        ];
        v.into_iter().map(|(n, (b, p))| (n, b, p)).collect()
    }

    #[test]
    fn progressive_equals_baseline_on_identical_coefficients() {
        for (n, base, prog) in cases() {
            assert!(is_progressive(prog) && !is_progressive(base), "{n}");
            let b = jpeg_source::decode(base, BIG).unwrap_or_else(|e| panic!("{n} baseline {e:?}"));
            let p = decode(prog, BIG).unwrap_or_else(|e| panic!("{n} progressive {e:?}"));
            assert_eq!((p.w, p.h), (b.w, b.h), "{n}");
            assert_eq!(p.pixels, b.pixels, "{n}: progressive pixels differ from baseline");
            assert_eq!(p.receipt.decoded_gray_sha256, b.receipt.decoded_gray_sha256, "{n}");
        }
    }

    #[test]
    fn receipt_names_the_decoder_that_ran() {
        let (base, prog) = fx!("gray_17x13");
        let p = decode(prog, BIG).unwrap();
        assert_eq!(p.receipt.decoder_version, "kni.jpeg-progressive.v1-q14");
        assert_eq!(p.receipt.subset_status, "supported_declared_subset_progressive_sof2");
        let b = jpeg_source::decode(base, BIG).unwrap();
        assert_ne!(p.receipt.decoder_version, b.receipt.decoder_version);
        assert_ne!(p.receipt.config_pin, b.receipt.config_pin);
        assert_eq!(p.receipt.orig_sha256, sha256_hex(prog).unwrap());
    }

    #[test]
    fn dispatch_routes_sof2_and_reports_progressive_decoder_without_png() {
        let (base, prog) = fx!("ycbcr_420_35x27");
        let jl = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 22, max_working_bytes: 1 << 28 };
        let dl = crate::capture::DecodeLimits::default();
        let a = crate::capture_dispatch::decode_source(prog, &dl, jl).unwrap();
        assert_eq!(a.receipt.source_kind, crate::capture_dispatch::SourceKind::JpegRawY);
        assert_eq!(a.receipt.jpeg_identity.as_ref().unwrap().decoder_version, DECODER_VERSION);
        assert!(a.receipt.png_limits.is_none());
        let b = crate::capture_dispatch::decode_source(base, &dl, jl).unwrap();
        assert_eq!(b.receipt.jpeg_identity.as_ref().unwrap().decoder_version, jpeg_source::DECODER_VERSION);
        assert_eq!(a.gray, b.gray);
    }

    #[test]
    fn baseline_decoder_still_refuses_sof2_typed() {
        let (_, prog) = fx!("gray_17x13");
        assert_eq!(jpeg_source::decode(prog, BIG).err(), Some(JpegError::UnsupportedMode));
    }

    fn drop_last_scan(d: &[u8]) -> Vec<u8> {
        let i = d.windows(2).rposition(|w| w == [0xff, 0xda]).unwrap();
        let mut v = d[..i].to_vec();
        v.extend_from_slice(&[0xff, 0xd9]);
        v
    }

    #[test]
    fn incomplete_scan_script_is_refused_not_decoded_at_lower_quality() {
        for (n, _, prog) in cases() {
            let cut = drop_last_scan(prog);
            assert_eq!(decode(&cut, BIG).err(), Some(JpegError::UnsupportedScan), "{n}");
        }
    }

    #[test]
    fn budget_refused_before_allocation() {
        let (_, prog) = fx!("gray_64x48_q95");
        // working budget below the coefficient store + pixels
        let tight = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 22, max_working_bytes: 4096 };
        assert_eq!(decode(prog, tight).err(), Some(JpegError::ResourceLimit));
        let few_px = Limits { max_input_bytes: 1 << 24, max_pixels: 100, max_working_bytes: 1 << 28 };
        assert_eq!(decode(prog, few_px).err(), Some(JpegError::ResourceLimit));
        let small_in = Limits { max_input_bytes: 10, max_pixels: 1 << 22, max_working_bytes: 1 << 28 };
        assert_eq!(decode(prog, small_in).err(), Some(JpegError::ResourceLimit));
        // hostile SOF2: 65535x65535, 1 component, within a permissive pixel cap but not the working cap
        let mut d = vec![0xff, 0xd8, 0xff, 0xc2, 0, 11, 8, 0xff, 0xff, 0xff, 0xff, 1, 1, 0x11, 0, 0xff, 0xd9];
        let lim = Limits { max_input_bytes: 1 << 20, max_pixels: usize::MAX, max_working_bytes: 1 << 26 };
        assert_eq!(decode(&d, lim).err(), Some(JpegError::ResourceLimit));
        // checked arithmetic: pixel cap itself
        let lim2 = Limits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 26 };
        assert_eq!(decode(&d, lim2).err(), Some(JpegError::ResourceLimit));
        d[3] = 0xca; // SOF10 arithmetic progressive
        assert_eq!(decode(&d, lim).err(), Some(JpegError::UnsupportedMode));
    }

    #[test]
    fn typed_refusals_trailing_truncation_and_no_panic_on_prefixes() {
        let (_, prog) = fx!("ycbcr_444_23x19");
        let mut t = prog.to_vec();
        t.push(0);
        assert_eq!(decode(&t, BIG).err(), Some(JpegError::TrailingData));
        assert_eq!(decode(b"notjpeg", BIG).err(), Some(JpegError::BadSignature));
        for cut in 0..prog.len() {
            assert!(decode(&prog[..cut], BIG).is_err(), "prefix {cut} must not decode");
        }
        // flip bytes: must stay typed, never panic
        for i in 0..prog.len() {
            let mut m = prog.to_vec();
            m[i] ^= 0xff;
            let _ = decode(&m, BIG);
        }
    }

    #[test]
    fn precision_and_colour_gates_match_baseline() {
        let (_, prog) = fx!("gray_17x13");
        let sof = prog.windows(2).position(|w| w == [0xff, 0xc2]).unwrap();
        let mut p12 = prog.to_vec();
        p12[sof + 4] = 12;
        assert_eq!(decode(&p12, BIG).err(), Some(JpegError::UnsupportedPrecision));
        let mut c2 = prog.to_vec();
        c2[sof + 9] = 2;
        assert!(matches!(decode(&c2, BIG).err(), Some(JpegError::UnsupportedColour)));
    }

    // ---------------- restart-interval, EOB-run, colour-state and scan-shape tests ----------------
    macro_rules! raw {
        ($n:expr) => {
            include_bytes!(concat!("../tests/fixtures/jpeg_progressive/", $n)) as &[u8]
        };
    }
    fn max_abs_diff(a: &[u8], b: &[u8]) -> u8 {
        assert_eq!(a.len(), b.len());
        a.iter().zip(b).map(|(x, y)| x.abs_diff(*y)).max().unwrap_or(0)
    }

    #[test]
    fn dri_progressive_matches_no_dri_exactly_and_libjpeg_within_one() {
        // hand-written encoder (gen_dri_progressive.py): same coefficients with DRI 0/3/1.
        let sets: [(&str, &[u8], &[u8], &[u8], &[u8]); 2] = [
            ("first", raw!("dri_none_first.prog.jpg"), raw!("dri_3_first.prog.jpg"), raw!("dri_1_first.prog.jpg"), raw!("dri_none_first.prog.ref.gray")),
            ("refine", raw!("dri_none_refine.prog.jpg"), raw!("dri_3_refine.prog.jpg"), raw!("dri_1_refine.prog.jpg"), raw!("dri_none_refine.prog.ref.gray")),
        ];
        for (n, none, d3, d1, refgray) in sets {
            assert!(d3.windows(2).any(|w| w == [0xff, 0xdd]) && d3.windows(2).any(|w| w == [0xff, 0xd0]), "{n}: fixture must contain DRI + RST");
            assert!(d1.windows(2).any(|w| w == [0xff, 0xd7]), "{n}: dri=1 fixture must wrap RST0..7");
            let a = decode(none, BIG).unwrap_or_else(|e| panic!("{n} none {e:?}"));
            let b = decode(d3, BIG).unwrap_or_else(|e| panic!("{n} dri3 {e:?}"));
            let c = decode(d1, BIG).unwrap_or_else(|e| panic!("{n} dri1 {e:?}"));
            assert_eq!(a.pixels, b.pixels, "{n} dri3");
            assert_eq!(a.pixels, c.pixels, "{n} dri1");
            // independent reference: libjpeg (Pillow) decode of the same file. IDCT rounding
            // may differ by at most 1 level.
            let d = max_abs_diff(&a.pixels, refgray);
            assert!(d <= 1, "{n}: max |ours - libjpeg| = {d}");
        }
    }

    #[test]
    fn libjpeg_raw_y_reference_within_one_level() {
        let refs: [(&str, &[u8], &[u8]); 7] = [
            ("gray_17x13", fx!("gray_17x13").1, raw!("gray_17x13.prog.libjpeg-y.gray")),
            ("gray_64x48_q95", fx!("gray_64x48_q95").1, raw!("gray_64x48_q95.prog.libjpeg-y.gray")),
            ("gray_1x1", fx!("gray_1x1").1, raw!("gray_1x1.prog.libjpeg-y.gray")),
            ("gray_grad_40x40", fx!("gray_grad_40x40").1, raw!("gray_grad_40x40.prog.libjpeg-y.gray")),
            ("ycbcr_444_23x19", fx!("ycbcr_444_23x19").1, raw!("ycbcr_444_23x19.prog.libjpeg-y.gray")),
            ("ycbcr_420_35x27", fx!("ycbcr_420_35x27").1, raw!("ycbcr_420_35x27.prog.libjpeg-y.gray")),
            ("ycbcr_422_40x16", fx!("ycbcr_422_40x16").1, raw!("ycbcr_422_40x16.prog.libjpeg-y.gray")),
        ];
        for (n, jpg, r) in refs {
            let p = decode(jpg, BIG).unwrap();
            let d = max_abs_diff(&p.pixels, r);
            eprintln!("libjpeg-ref {n}: max_abs_diff={d}");
            assert!(d <= 1, "{n}: max |ours - libjpeg raw Y| = {d}");
        }
    }

    #[test]
    fn eob_run_must_not_cross_restart_or_scan_end() {
        assert_eq!(decode(raw!("bad_eob_end.prog.jpg"), BIG).err(), Some(JpegError::MalformedEntropy));
        assert_eq!(decode(raw!("bad_eob_restart.prog.jpg"), BIG).err(), Some(JpegError::MalformedEntropy));
        // control: the same encoder without the over-claim decodes
        assert!(decode(raw!("dri_3_refine.prog.jpg"), BIG).is_ok());
    }

    fn insert_before_nth_sos(d: &[u8], n: usize, seg: &[u8]) -> Vec<u8> {
        let mut seen = 0;
        let mut i = 2;
        // walk markers up to the n-th SOS using segment lengths; entropy data is skipped by
        // searching for the next 0xFF marker that is not stuffing/restart.
        while i + 1 < d.len() {
            if d[i] == 0xff && d[i + 1] == 0xda {
                if seen == n {
                    let mut v = d[..i].to_vec();
                    v.extend_from_slice(seg);
                    v.extend_from_slice(&d[i..]);
                    return v;
                }
                seen += 1;
            }
            i += 1;
        }
        panic!("sos {n} not found");
    }

    #[test]
    fn app14_colour_state_change_after_sof_is_refused() {
        let (_, prog) = fx!("ycbcr_444_23x19");
        // Adobe APP14 with transform 0 (RGB) and with transform 2 appearing between scans
        for transform in [0u8, 2, 1] {
            let mut seg = vec![0xff, 0xee, 0, 14];
            seg.extend_from_slice(b"Adobe");
            seg.extend_from_slice(&[0, 100, 0, 0, 0, 0, transform]);
            let m = insert_before_nth_sos(prog, 1, &seg);
            assert_eq!(decode(&m, BIG).err(), Some(JpegError::UnsupportedColour), "transform {transform}");
        }
        // unmodified control decodes
        assert!(decode(prog, BIG).is_ok());
    }

    #[test]
    fn interleaved_ac_band_scan_is_refused() {
        let (_, prog) = fx!("ycbcr_444_23x19");
        // find the first AC scan header (Ss>0, ns==1) and rewrite it as ns=2 with Ss=1
        let mut i = 2;
        let mut found = None;
        while i + 10 < prog.len() {
            if prog[i] == 0xff && prog[i + 1] == 0xda {
                let len = ((prog[i + 2] as usize) << 8) | prog[i + 3] as usize;
                let ns = prog[i + 4] as usize;
                let ss = prog[i + 4 + 1 + 2 * ns] as usize;
                if ns == 1 && ss > 0 {
                    found = Some((i, len));
                    break;
                }
            }
            i += 1;
        }
        let (at, len) = found.expect("AC scan");
        let mut v = prog[..at].to_vec();
        v.extend_from_slice(&[0xff, 0xda, 0, 10, 2, 1, 0x00, 2, 0x11, 1, 63, 0x00]);
        v.extend_from_slice(&prog[at + 2 + len..]);
        assert_eq!(decode(&v, BIG).err(), Some(JpegError::UnsupportedScan));
        // Se < Ss and Se > 63 are also refused
        for (ss, se) in [(5u8, 4u8), (1, 64)] {
            let mut w = prog.to_vec();
            let k = at + 4 + 1 + 2;
            w[k] = ss;
            w[k + 1] = se;
            assert_eq!(decode(&w, BIG).err(), Some(JpegError::UnsupportedScan), "ss={ss} se={se}");
        }
    }

    #[test]
    fn pre_sof_scratch_is_charged_before_tables_are_parsed() {
        let (_, prog) = fx!("gray_17x13");
        let l = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 22, max_working_bytes: 1000 };
        assert_eq!(decode(prog, l).err(), Some(JpegError::ResourceLimit));
    }
}
