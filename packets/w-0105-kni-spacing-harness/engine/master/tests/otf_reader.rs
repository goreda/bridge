//! Reader tests. Synthetic fonts are assembled in the test from raw
//! charstring bytes, so every operator is exercised against hand-computed
//! outlines.

use kni_master::model::Op;
use kni_master::otf::{OtfFont, ReadError};

enum T {
    N(i32),
    Op(u8),
    Op2(u8, u8),
    Raw(u8),
}

fn cs(items: &[T]) -> Vec<u8> {
    let mut o = Vec::new();
    for it in items {
        match it {
            T::N(v) => {
                let v = *v;
                if (-107..=107).contains(&v) {
                    o.push((v + 139) as u8);
                } else if (108..=1131).contains(&v) {
                    let w = v - 108;
                    o.push((w / 256 + 247) as u8);
                    o.push((w % 256) as u8);
                } else if (-1131..=-108).contains(&v) {
                    let w = -v - 108;
                    o.push((w / 256 + 251) as u8);
                    o.push((w % 256) as u8);
                } else {
                    o.push(28);
                    o.extend_from_slice(&(v as i16).to_be_bytes());
                }
            }
            T::Op(b) => o.push(*b),
            T::Op2(a, b) => {
                o.push(*a);
                o.push(*b);
            }
            T::Raw(b) => o.push(*b),
        }
    }
    o
}

fn index(objs: &[Vec<u8>]) -> Vec<u8> {
    let mut o = Vec::new();
    o.extend_from_slice(&(objs.len() as u16).to_be_bytes());
    if objs.is_empty() {
        return o;
    }
    o.push(4);
    let mut off = 1u32;
    o.extend_from_slice(&off.to_be_bytes());
    for ob in objs {
        off += ob.len() as u32;
        o.extend_from_slice(&off.to_be_bytes());
    }
    for ob in objs {
        o.extend_from_slice(ob);
    }
    o
}

fn dict_int(v: u32) -> Vec<u8> {
    let mut o = vec![29];
    o.extend_from_slice(&v.to_be_bytes());
    o
}

struct Spec {
    glyphs: Vec<Vec<u8>>,
    gsubrs: Vec<Vec<u8>>,
    lsubrs: Vec<Vec<u8>>,
    /// (code point, glyph index) pairs for a format 12 cmap.
    cmap: Vec<(u32, u16)>,
    advance: u16,
    upm: u16,
}

impl Spec {
    fn new(glyphs: Vec<Vec<u8>>) -> Self {
        Self { glyphs, gsubrs: vec![], lsubrs: vec![], cmap: vec![], advance: 500, upm: 1000 }
    }
}

fn build_cff(s: &Spec) -> Vec<u8> {
    let header = vec![1u8, 0, 4, 1];
    let name = index(&[b"T".to_vec()]);
    let strings = index(&[]);
    let gs = index(&s.gsubrs);
    let top_len = 17usize;
    let top_index_len = 2 + 1 + 2 * 4 + top_len;
    let cs_off = header.len() + name.len() + top_index_len + strings.len() + gs.len();
    let cs_index = index(&s.glyphs);
    let priv_off = cs_off + cs_index.len();
    let private: Vec<u8> = if s.lsubrs.is_empty() {
        vec![]
    } else {
        let mut p = dict_int(6);
        p.push(19);
        p
    };
    let mut top = dict_int(cs_off as u32);
    top.push(17);
    top.extend(dict_int(private.len() as u32));
    top.extend(dict_int(priv_off as u32));
    top.push(18);
    assert_eq!(top.len(), top_len);
    let mut out = header;
    out.extend(name);
    out.extend(index(&[top]));
    out.extend(strings);
    out.extend(gs);
    out.extend(cs_index);
    out.extend(private.clone());
    if !s.lsubrs.is_empty() {
        out.extend(index(&s.lsubrs));
    }
    out
}

fn build_font(s: &Spec) -> Vec<u8> {
    let n = s.glyphs.len();
    let cff = build_cff(s);
    let mut head = vec![0u8; 54];
    head[18..20].copy_from_slice(&s.upm.to_be_bytes());
    let mut hhea = vec![0u8; 36];
    hhea[34..36].copy_from_slice(&(n as u16).to_be_bytes());
    let mut hmtx = Vec::new();
    for _ in 0..n {
        hmtx.extend_from_slice(&s.advance.to_be_bytes());
        hmtx.extend_from_slice(&0u16.to_be_bytes());
    }
    let mut maxp = vec![0u8, 0, 0x50, 0];
    maxp.extend_from_slice(&(n as u16).to_be_bytes());
    let mut cmap = Vec::new();
    cmap.extend_from_slice(&0u16.to_be_bytes());
    cmap.extend_from_slice(&1u16.to_be_bytes());
    cmap.extend_from_slice(&3u16.to_be_bytes());
    cmap.extend_from_slice(&10u16.to_be_bytes());
    cmap.extend_from_slice(&12u32.to_be_bytes());
    cmap.extend_from_slice(&12u16.to_be_bytes());
    cmap.extend_from_slice(&0u16.to_be_bytes());
    cmap.extend_from_slice(&((16 + 12 * s.cmap.len()) as u32).to_be_bytes());
    cmap.extend_from_slice(&0u32.to_be_bytes());
    cmap.extend_from_slice(&(s.cmap.len() as u32).to_be_bytes());
    for (cp, g) in &s.cmap {
        cmap.extend_from_slice(&cp.to_be_bytes());
        cmap.extend_from_slice(&cp.to_be_bytes());
        cmap.extend_from_slice(&(*g as u32).to_be_bytes());
    }
    let tables: Vec<(&[u8; 4], Vec<u8>)> =
        vec![(b"CFF ", cff), (b"cmap", cmap), (b"head", head), (b"hhea", hhea), (b"hmtx", hmtx), (b"maxp", maxp)];
    let mut out = b"OTTO".to_vec();
    out.extend_from_slice(&(tables.len() as u16).to_be_bytes());
    out.extend_from_slice(&[0u8; 6]);
    let mut off = 12 + 16 * tables.len();
    for (tag, data) in &tables {
        out.extend_from_slice(*tag);
        out.extend_from_slice(&0u32.to_be_bytes());
        out.extend_from_slice(&(off as u32).to_be_bytes());
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        off += data.len();
    }
    for (_, data) in &tables {
        out.extend_from_slice(data);
    }
    out
}

fn ops_of(items: &[T]) -> Vec<Op> {
    let font = build_font(&Spec::new(vec![cs(items)]));
    let f = OtfFont::parse(&font).expect("parse");
    let g = f.glyph(0).expect("glyph");
    assert_eq!(g.contours.len(), 1);
    g.contours[0].ops.clone()
}

fn glyph_err(items: &[T]) -> ReadError {
    let font = build_font(&Spec::new(vec![cs(items)]));
    OtfFont::parse(&font).unwrap().glyph(0).unwrap_err()
}

use T::{Op as O, Op2 as O2, N, Raw};

const RMOVETO: u8 = 21;
const ENDCHAR: u8 = 14;

fn start() -> Vec<T> {
    vec![N(0), N(0), O(RMOVETO)]
}

fn with(mut head: Vec<T>, tail: Vec<T>) -> Vec<T> {
    head.extend(tail);
    head.push(O(ENDCHAR));
    head
}

#[test]
fn header_values_and_advance() {
    let mut s = Spec::new(vec![cs(&[O(ENDCHAR)])]);
    s.advance = 612;
    s.upm = 2048;
    let font = build_font(&s);
    let f = OtfFont::parse(&font).unwrap();
    assert_eq!(f.upm(), 2048.0);
    assert_eq!(f.glyph_count(), 1);
    let g = f.glyph(0).unwrap();
    assert_eq!((g.advance, g.upm), (612.0, 2048.0));
    assert!(g.contours.is_empty());
}

#[test]
fn width_operand_is_dropped_and_lines_alternate() {
    // width 500, then moveto (10,20); hlineto alternates h, v, h.
    let ops = ops_of(&[N(500), N(10), N(20), O(RMOVETO), N(100), N(50), N(-100), O(6), O(ENDCHAR)]);
    assert_eq!(
        ops,
        vec![Op::Move((10.0, 20.0)), Op::Line((110.0, 20.0)), Op::Line((110.0, 70.0)), Op::Line((10.0, 70.0)), Op::Close]
    );
}

#[test]
fn hmoveto_vmoveto_vlineto_rlineto() {
    let ops = ops_of(&[N(7), O(22), N(3), O(7), N(4), N(5), O(5), O(ENDCHAR)]);
    assert_eq!(ops, vec![Op::Move((7.0, 0.0)), Op::Line((7.0, 3.0)), Op::Line((11.0, 8.0)), Op::Close]);
    let ops = ops_of(&[N(9), O(4), O(ENDCHAR)]);
    assert_eq!(ops, vec![Op::Move((0.0, 9.0)), Op::Close]);
}

#[test]
fn hint_mask_bytes_are_skipped() {
    // Two stems, then a hintmask whose mask byte equals the endchar opcode.
    let ops = ops_of(&[
        N(10), N(20), O(18),
        N(5), N(6), O(19), Raw(14),
        N(0), N(0), O(RMOVETO), N(10), N(0), O(5), O(ENDCHAR),
    ]);
    assert_eq!(ops, vec![Op::Move((0.0, 0.0)), Op::Line((10.0, 0.0)), Op::Close]);
}

#[test]
fn width_before_stem_is_dropped() {
    let ops = ops_of(&[N(500), N(10), N(20), O(1), N(1), N(2), O(RMOVETO), O(ENDCHAR)]);
    assert_eq!(ops, vec![Op::Move((1.0, 2.0)), Op::Close]);
}

#[test]
fn curve_operators() {
    let m = Op::Move((0.0, 0.0));
    let c = |a: (f64, f64), b: (f64, f64), p: (f64, f64)| Op::Curve(a, b, p);
    // rrcurveto
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(0), N(10), N(10), N(0), N(10), O(8)])),
        vec![m.clone(), c((10., 0.), (20., 10.), (20., 20.)), Op::Close]
    );
    // hhcurveto with and without the leading dy
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(20), N(5), N(30), O(27)])),
        vec![m.clone(), c((10., 0.), (30., 5.), (60., 5.)), Op::Close]
    );
    assert_eq!(
        ops_of(&with(start(), vec![N(3), N(10), N(20), N(5), N(30), O(27)])),
        vec![m.clone(), c((10., 3.), (30., 8.), (60., 8.)), Op::Close]
    );
    // vvcurveto with and without the leading dx
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(20), N(5), N(30), O(26)])),
        vec![m.clone(), c((0., 10.), (20., 15.), (20., 45.)), Op::Close]
    );
    assert_eq!(
        ops_of(&with(start(), vec![N(7), N(10), N(20), N(5), N(30), O(26)])),
        vec![m.clone(), c((7., 10.), (27., 15.), (27., 45.)), Op::Close]
    );
    // hvcurveto: plain, with the final extra operand, alternating
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(20), N(5), N(30), O(31)])),
        vec![m.clone(), c((10., 0.), (30., 5.), (30., 35.)), Op::Close]
    );
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(20), N(5), N(30), N(4), O(31)])),
        vec![m.clone(), c((10., 0.), (30., 5.), (34., 35.)), Op::Close]
    );
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(20), N(5), N(30), N(6), N(7), N(8), N(9), O(31)])),
        vec![
            m.clone(),
            c((10., 0.), (30., 5.), (30., 35.)),
            c((30., 41.), (37., 49.), (46., 49.)),
            Op::Close
        ]
    );
    // vhcurveto
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(20), N(5), N(30), O(30)])),
        vec![m.clone(), c((0., 10.), (20., 15.), (50., 15.)), Op::Close]
    );
    // rlinecurve and rcurveline
    assert_eq!(
        ops_of(&with(start(), vec![N(5), N(5), N(10), N(0), N(10), N(10), N(0), N(10), O(25)])),
        vec![m.clone(), Op::Line((5., 5.)), c((15., 5.), (25., 15.), (25., 25.)), Op::Close]
    );
    assert_eq!(
        ops_of(&with(start(), vec![N(10), N(0), N(10), N(10), N(0), N(10), N(5), N(5), O(24)])),
        vec![m.clone(), c((10., 0.), (20., 10.), (20., 20.)), Op::Line((25., 25.)), Op::Close]
    );
}

#[test]
fn flex_operators() {
    let want = vec![
        Op::Move((0.0, 0.0)),
        Op::Curve((10., 0.), (20., 10.), (30., 10.)),
        Op::Curve((40., 10.), (50., 0.), (60., 0.)),
        Op::Close,
    ];
    // flex
    let a: Vec<i32> = vec![10, 0, 10, 10, 10, 0, 10, 0, 10, -10, 10, 0, 50];
    let mut t: Vec<T> = a.into_iter().map(N).collect();
    t.push(O2(12, 35));
    assert_eq!(ops_of(&with(start(), t)), want);
    // hflex
    let mut t: Vec<T> = [10, 10, 10, 10, 10, 10, 10].into_iter().map(N).collect();
    t.push(O2(12, 34));
    assert_eq!(ops_of(&with(start(), t)), want);
    // hflex1: end y returns to the start y
    let mut t: Vec<T> = [10, 0, 10, 10, 10, 10, 10, -10, 10].into_iter().map(N).collect();
    t.push(O2(12, 36));
    assert_eq!(ops_of(&with(start(), t)), want);
    // flex1, horizontal dominant: the last point lands on the start y
    let mut t: Vec<T> = [10, 0, 10, 10, 10, 0, 10, 0, 10, -10, 10].into_iter().map(N).collect();
    t.push(O2(12, 37));
    assert_eq!(ops_of(&with(start(), t)), want);
}

#[test]
fn subroutines_local_and_global() {
    let mut s = Spec::new(vec![cs(&[N(0), N(0), O(RMOVETO), N(-107), O(10), N(-107), O(29), O(ENDCHAR)])]);
    s.gsubrs = vec![cs(&[N(100), N(0), O(5), O(11)])];
    s.lsubrs = vec![cs(&[N(0), N(100), O(5), O(11)])];
    let font = build_font(&s);
    let g = OtfFont::parse(&font).unwrap().glyph(0).unwrap();
    assert_eq!(
        g.contours[0].ops,
        vec![Op::Move((0.0, 0.0)), Op::Line((0.0, 100.0)), Op::Line((100.0, 100.0)), Op::Close]
    );
}

#[test]
fn several_contours_each_close() {
    let ops_all = {
        let t = cs(&[
            N(0), N(0), O(RMOVETO), N(10), O(6), N(5), N(5), O(RMOVETO), N(1), O(6), O(ENDCHAR),
        ]);
        let font = build_font(&Spec::new(vec![t]));
        OtfFont::parse(&font).unwrap().glyph(0).unwrap()
    };
    assert_eq!(ops_all.contours.len(), 2);
    assert_eq!(ops_all.contours[0].ops, vec![Op::Move((0., 0.)), Op::Line((10., 0.)), Op::Close]);
    assert_eq!(ops_all.contours[1].ops, vec![Op::Move((15., 5.)), Op::Line((16., 5.)), Op::Close]);
    assert_eq!(ops_all.contours[0].stroke, "c0");
    assert_eq!(ops_all.contours[1].stroke, "c1");
}

#[test]
fn malformed_charstrings_are_typed_errors() {
    assert!(matches!(glyph_err(&[N(0), N(0), O(RMOVETO)]), ReadError::BadCharstring { reason: "no endchar", .. }));
    assert!(matches!(glyph_err(&[N(1), N(1), O(5), O(ENDCHAR)]), ReadError::BadCharstring { .. }));
    assert!(matches!(glyph_err(&[N(1), N(1), O2(12, 10), O(ENDCHAR)]), ReadError::Unsupported(_)));
    assert!(matches!(glyph_err(&[N(5), O(10), O(ENDCHAR)]), ReadError::BadCharstring { .. }));
    assert!(matches!(
        glyph_err(&[N(1), N(2), N(3), N(4), O(ENDCHAR)]),
        ReadError::Unsupported(_)
    ));
    // stack overflow: 49 operands
    let mut t: Vec<T> = (0..49).map(N).collect();
    t.push(O(ENDCHAR));
    assert!(matches!(glyph_err(&t), ReadError::BadCharstring { reason: "stack overflow", .. }));
    // wrong operand count for rrcurveto
    assert!(matches!(glyph_err(&with(start(), vec![N(1), N(2), N(3), O(8)])), ReadError::BadCharstring { .. }));
}

#[test]
fn self_recursive_subroutine_hits_a_guard() {
    let mut s = Spec::new(vec![cs(&[N(-107), O(29), O(ENDCHAR)])]);
    s.gsubrs = vec![cs(&[N(-107), O(29), O(11)])];
    let font = build_font(&s);
    let e = OtfFont::parse(&font).unwrap().glyph(0).unwrap_err();
    assert!(matches!(e, ReadError::BadCharstring { .. } | ReadError::Budget { .. }));
}

#[test]
fn glyph_index_and_codepoint_lookup() {
    let mut s = Spec::new(vec![cs(&[O(ENDCHAR)]), cs(&[N(1), N(1), O(RMOVETO), O(ENDCHAR)])]);
    s.cmap = vec![(0x41, 1), (0x1F600, 0)];
    let font = build_font(&s);
    let f = OtfFont::parse(&font).unwrap();
    assert_eq!(f.gid_for_codepoint(0x41), Some(1));
    assert_eq!(f.glyph_by_codepoint(0x41).unwrap().unwrap().name, "uni0041");
    assert!(f.glyph_by_codepoint(0x42).unwrap().is_none());
    assert_eq!(f.glyph(0).unwrap().name, "u01F600");
    assert_eq!(f.glyph(7).unwrap_err(), ReadError::GlyphIndexOutOfRange(7));
}

#[test]
fn rejects_wrong_containers() {
    assert_eq!(OtfFont::parse(b"").unwrap_err(), ReadError::NotCffOpenType);
    assert_eq!(OtfFont::parse(b"ttcfrest").unwrap_err(), ReadError::NotCffOpenType);
}

// TrueType sfnt is now supported. The formerly rejected container signature
// must enter the table parser; its short directory is malformed, not unsupported.
#[test]
fn supported_truetype_short_directory_is_truncated() {
    assert!(matches!(OtfFont::parse(b"\x00\x01\x00\x00rest"), Err(ReadError::Truncated(_))));
}

#[test]
fn every_truncation_is_an_error_not_a_panic() {
    let mut s = Spec::new(vec![cs(&[N(0), N(0), O(RMOVETO), N(5), O(6), O(ENDCHAR)])]);
    s.cmap = vec![(0x41, 0)];
    s.gsubrs = vec![cs(&[O(11)])];
    s.lsubrs = vec![cs(&[O(11)])];
    let font = build_font(&s);
    for n in 0..font.len() {
        let r = OtfFont::parse(&font[..n]).and_then(|f| {
            for g in 0..f.glyph_count() as u16 {
                f.glyph(g)?;
            }
            Ok(())
        });
        // `maxp` is the last table and is not read, so cutting only it is not an error.
        assert!(r.is_err() || n >= font.len() - 6, "prefix of {n} bytes must not read as a whole font");
    }
}
