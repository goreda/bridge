//! Synthetic-only tests. No third-party font data is used or required.
use kni_core::cff_reader::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn n(v: i32) -> Vec<u8> { let mut o = vec![28]; o.extend_from_slice(&(v as i16).to_be_bytes()); o }
fn run(code: Vec<u8>) -> Result<ReadGlyph, ReadReject> { interpret_type2(1, &code, &[], &[], 500.0, 600.0) }
fn cat(parts: Vec<Vec<u8>>) -> Vec<u8> { parts.concat() }
fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn ends(r: &ReferenceRing) -> Point { match r.spans.last().unwrap() { Span::Line { end } | Span::Cubic { end, .. } => *end } }

#[test] fn sha256_known_vectors() {
    assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}
#[test] fn width_default_and_nominal_and_implicit_closure() {
    // 10 20 rmoveto, 30 0 rlineto, 0 40 rlineto, endchar -> closed by implicit line
    let g = run(cat(vec![n(10), n(20), vec![21], n(30), n(0), vec![5], n(0), n(40), vec![5], vec![14]])).unwrap();
    assert_eq!(g.width, Some(500.0)); assert_eq!(g.implicit_closures, 1);
    assert_eq!(g.rings.len(), 1); assert_eq!(ends(&g.rings[0]), p(10., 20.)); assert_eq!(g.rings[0].spans.len(), 3);
    // explicit width delta: 7 10 20 rmoveto
    let g = run(cat(vec![n(7), n(10), n(20), vec![21], n(5), vec![6], vec![14]])).unwrap();
    assert_eq!(g.width, Some(607.0));
}
#[test] fn stems_hintmask_cntrmask_count_and_skip_mask_bytes() {
    // width 3, hstemhm with 2 pairs, then hintmask with 1 implicit vstem pair -> 3 stems -> 1 mask byte
    let code = cat(vec![n(3), n(0), n(10), n(20), n(30), vec![18], n(5), n(6), vec![19, 0b1110_0000], n(1), n(2), vec![21], n(10), vec![6], vec![20, 0xff], vec![14]]);
    // note: second moveto has no width (already consumed)
    let g = run(code).unwrap();
    assert_eq!(g.width, Some(603.0)); assert_eq!(g.stem_count, 3);
    assert_eq!(g.rings.len(), 1);
}
#[test] fn hintmask_mask_byte_value_is_not_an_operator() {
    // mask byte 0x0e would be endchar if misparsed
    let code = cat(vec![n(0), n(10), vec![1], vec![19, 0x0e], n(1), n(1), vec![21], n(4), vec![6], vec![14]]);
    assert!(run(code).is_ok());
}
#[test] fn all_line_and_curve_forms() {
    let mv = cat(vec![n(0), n(0), vec![21]]);
    // hlineto alternate h,v,h
    let g = run(cat(vec![mv.clone(), n(1), n(2), n(3), vec![6], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans.len(), 4); // 3 lines + closure
    // vlineto
    let g = run(cat(vec![mv.clone(), n(1), n(2), vec![7], vec![14]])).unwrap();
    match &g.rings[0].spans[0] { Span::Line { end } => assert_eq!(*end, p(0., 1.)), _ => panic!() }
    // rlinecurve: 1 line + curve
    let g = run(cat(vec![mv.clone(), n(1), n(1), n(1), n(0), n(1), n(1), n(0), n(1), vec![25], vec![14]])).unwrap();
    assert!(matches!(g.rings[0].spans[1], Span::Cubic { .. }));
    // rcurveline: curve + line
    let g = run(cat(vec![mv.clone(), n(1), n(0), n(1), n(1), n(0), n(1), n(5), n(5), vec![24], vec![14]])).unwrap();
    assert!(matches!(g.rings[0].spans[0], Span::Cubic { .. }) && matches!(g.rings[0].spans[1], Span::Line { .. }));
    // hhcurveto with leading dy1: dy1 dxa dxb dyb dxc
    let g = run(cat(vec![mv.clone(), n(7), n(1), n(2), n(3), n(4), vec![27], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[0].clone_cubic(), (p(1., 7.), p(3., 10.), p(7., 10.)));
    // vvcurveto with leading dx1: dx1 dya dxb dyb dyc
    let g = run(cat(vec![mv.clone(), n(7), n(1), n(2), n(3), n(4), vec![26], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[0].clone_cubic(), (p(7., 1.), p(9., 4.), p(9., 8.)));
    // hvcurveto with trailing odd arg: dx1 dx2 dy2 dy3 dxf
    let g = run(cat(vec![mv.clone(), n(1), n(2), n(3), n(4), n(9), vec![31], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[0].clone_cubic(), (p(1., 0.), p(3., 3.), p(12., 7.)));
    // vhcurveto two curves: dy1 dx2 dy2 dx3 | dx1 dx2 dy2 dy3(+dyf)
    let g = run(cat(vec![mv.clone(), n(1), n(2), n(3), n(4), n(5), n(6), n(7), n(8), n(9), vec![30], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[0].clone_cubic(), (p(0., 1.), p(2., 4.), p(6., 4.)));
    assert_eq!(g.rings[0].spans[1].clone_cubic(), (p(11., 4.), p(17., 11.), p(26., 19.)));
}
trait Cub { fn clone_cubic(&self) -> (Point, Point, Point); }
impl Cub for Span { fn clone_cubic(&self) -> (Point, Point, Point) { match self { Span::Cubic { control_one, control_two, end } => (*control_one, *control_two, *end), _ => panic!("not cubic") } } }

#[test] fn flex_family_to_cubics() {
    let mv = cat(vec![n(0), n(0), vec![21]]);
    let g = run(cat(vec![mv.clone(), n(1), n(0), n(1), n(1), n(1), n(0), n(1), n(0), n(1), n(-1), n(1), n(0), n(50), vec![12, 35], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans.len(), 3);
    let g = run(cat(vec![mv.clone(), n(1), n(2), n(3), n(4), n(5), n(6), n(7), vec![12, 34], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[1].clone_cubic().2, p(25., 0.));
    let g = run(cat(vec![mv.clone(), n(1), n(2), n(3), n(4), n(5), n(6), n(7), n(8), n(9), vec![12, 36], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[1].clone_cubic().2.y, 0.0); // flex1 hflex1: endpoint returns to start y
    let g = run(cat(vec![mv, n(10), n(1), n(10), n(1), n(10), n(1), n(10), n(1), n(10), n(1), n(7), vec![12, 37], vec![14]])).unwrap();
    assert_eq!(g.rings[0].spans[1].clone_cubic().2, p(57., 0.)); // |dx|>|dy| -> last dx=d6, y returns to start
}
#[test] fn subrs_bias_depth_and_return() {
    let sub: Vec<u8> = cat(vec![n(5), vec![6], vec![11]]); // hlineto 5 return
    let local = [&sub[..]];
    // bias 107: index -107 selects subr 0
    let code = cat(vec![n(0), n(0), vec![21], n(-107), vec![10], vec![14]]);
    let g = interpret_type2(1, &code, &[], &local, 0.0, 0.0).unwrap();
    assert_eq!(g.rings[0].spans.len(), 2);
    let code = cat(vec![n(0), n(0), vec![21], n(-107), vec![29], vec![14]]);
    assert_eq!(interpret_type2(1, &code, &local, &[], 0.0, 0.0).unwrap().rings.len(), 1);
    let code = cat(vec![n(0), n(0), vec![21], n(-106), vec![10], vec![14]]);
    assert_eq!(interpret_type2(1, &code, &[], &local, 0.0, 0.0).err(), Some(ReadReject::SubrOutOfRange));
    // recursion depth
    let rec = cat(vec![n(-107), vec![10]]);
    let local = [&rec[..]];
    let code = cat(vec![n(0), n(0), vec![21], n(-107), vec![10], vec![14]]);
    assert_eq!(interpret_type2(1, &code, &[], &local, 0.0, 0.0).err(), Some(ReadReject::SubrDepthExceeded));
    // endchar inside subr ends glyph
    let ec = cat(vec![n(2), vec![6], vec![14]]);
    let local = [&ec[..]];
    let code = cat(vec![n(0), n(0), vec![21], n(-107), vec![10], n(99), vec![6]]);
    assert!(interpret_type2(1, &code, &[], &local, 0.0, 0.0).is_ok());
}
#[test] fn typed_rejects() {
    let mv = cat(vec![n(0), n(0), vec![21]]);
    assert_eq!(run(cat(vec![mv.clone(), n(1), vec![12, 12], vec![14]])).err(), Some(ReadReject::UnsupportedOperator(0x0c0c))); // div
    assert_eq!(run(cat(vec![mv.clone(), vec![0], vec![14]])).err(), Some(ReadReject::UnsupportedOperator(0)));
    assert_eq!(run(cat(vec![n(0), n(0), n(0), n(0), vec![14]])).err(), Some(ReadReject::Seac));
    assert_eq!(run(cat(vec![n(5), n(0), n(0), n(0), n(0), vec![14]])).err(), Some(ReadReject::Seac)); // width + seac
    assert_eq!(run(cat(vec![n(1), n(1), vec![5], vec![14]])).err(), Some(ReadReject::DrawBeforeMoveto));
    assert_eq!(run(mv.clone()).err(), Some(ReadReject::MissingEndchar));
    assert!(matches!(run(cat(vec![mv.clone(), n(1), vec![5], vec![14]])), Err(ReadReject::BadArgumentCount { .. })));
    let mut big = Vec::new(); for _ in 0..49 { big.extend(n(1)); }
    assert_eq!(run(big).err(), Some(ReadReject::StackOverflow));
    assert_eq!(run(cat(vec![mv.clone(), n(1), n(2), vec![1], vec![19]])).err(), Some(ReadReject::TruncatedHintmask));
}
#[test] fn moveto_only_ring_dropped_and_rings_never_open() {
    let code = cat(vec![n(1), n(1), vec![21], n(2), n(2), vec![21], n(3), vec![6], n(3), vec![7], vec![14]]);
    let g = run(code).unwrap();
    assert_eq!(g.rings.len(), 1);
    for r in &g.rings { assert_eq!(ends(r), r.start); }
}
#[test] fn container_rejects_and_sha_gate() {
    assert_eq!(CffReader::from_bytes(b"x", "zz").err(), Some(ReadReject::BadExpectedSha));
    let bytes = vec![0u8, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let good = sha256_hex(&bytes);
    assert!(matches!(CffReader::from_bytes(&bytes, &"0".repeat(64)), Err(ReadReject::ShaMismatch { .. })));
    assert_eq!(CffReader::from_bytes(&bytes, &good).err(), Some(ReadReject::NotOtto(0x00010000)));
}

// ---------------------------------------------------------------- container: UPM / FontMatrix contract (synthetic OTTO)
fn index(objs: &[Vec<u8>]) -> Vec<u8> {
    let mut o = (objs.len() as u16).to_be_bytes().to_vec();
    if objs.is_empty() { return o; }
    o.push(1); let mut off = 1u8; o.push(off);
    for x in objs { off += x.len() as u8; o.push(off); }
    for x in objs { o.extend_from_slice(x); }
    o
}
fn real(s: &str) -> Vec<u8> {
    let mut nibs: Vec<u8> = s.bytes().map(|c| match c { b'0'..=b'9' => c - b'0', b'.' => 10, b'-' => 14, _ => panic!() }).collect();
    nibs.push(15); if nibs.len() % 2 == 1 { nibs.push(15); }
    let mut o = vec![30]; for p in nibs.chunks(2) { o.push(p[0] << 4 | p[1]); } o
}
fn otto(upm: u16, matrix: Option<[&str; 6]>) -> Vec<u8> {
    let g0 = cat(vec![vec![14]]);
    let g1 = cat(vec![n(0), n(0), vec![21], n(10), vec![6], n(10), vec![7], vec![14]]);
    let mut fm: Vec<u8> = Vec::new();
    if let Some(m) = matrix { for v in m { fm.extend(if v == "0" { vec![139] } else { real(v) }); } fm.extend([12, 7]); }
    let top_len = fm.len() + 6 + 11;
    let head_hdr = vec![1u8, 0, 4, 1];
    let name = index(&[b"T".to_vec()]);
    let top_idx_len = 2 + 1 + 2 + top_len;
    let strings = index(&[]); let gsubr = index(&[]);
    let cs_off = head_hdr.len() + name.len() + top_idx_len + strings.len() + gsubr.len();
    let cs = index(&[g0, g1]);
    let priv_off = cs_off + cs.len();
    let mut top = fm.clone();
    top.push(29); top.extend((cs_off as u32).to_be_bytes()); top.push(17);
    top.push(29); top.extend(0u32.to_be_bytes()); top.push(29); top.extend((priv_off as u32).to_be_bytes()); top.push(18);
    assert_eq!(top.len(), top_len);
    let mut cff = head_hdr; cff.extend(name); cff.extend(index(&[top])); cff.extend(strings); cff.extend(gsubr); cff.extend(cs);
    let mut cmap = vec![0u8, 0, 0, 1, 0, 3, 0, 10, 0, 0, 0, 12];
    cmap.extend([0, 12, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 1]);
    cmap.extend(0x41u32.to_be_bytes()); cmap.extend(0x41u32.to_be_bytes()); cmap.extend(1u32.to_be_bytes());
    let mut head = vec![0u8; 54]; head[18..20].copy_from_slice(&upm.to_be_bytes());
    let tables: Vec<([u8; 4], Vec<u8>)> = vec![(*b"CFF ", cff), (*b"cmap", cmap), (*b"head", head)];
    let mut out = vec![0x4F, 0x54, 0x54, 0x4F, 0, 3, 0, 0, 0, 0, 0, 0];
    let mut off = 12 + 16 * tables.len();
    let mut body: Vec<u8> = Vec::new();
    for (tag, d) in &tables {
        out.extend(tag); out.extend([0u8; 4]); out.extend((off as u32).to_be_bytes()); out.extend((d.len() as u32).to_be_bytes());
        body.extend(d); off += d.len();
    }
    out.extend(body); out
}
fn open(upm: u16, m: Option<[&str; 6]>) -> Result<CffReader, ReadReject> { let b = otto(upm, m); CffReader::from_bytes(&b, &sha256_hex(&b)) }
const DEF: [&str; 6] = ["0.001", "0", "0", "0.001", "0", "0"];

#[test] fn synthetic_otto_reads_with_default_scale() {
    for m in [None, Some(DEF)] {
        let r = open(1000, m).unwrap();
        assert_eq!(r.units_per_em(), 1000); assert_eq!(r.cmap_choice(), (3, 10, 12));
        let g = r.read_codepoint(0x41).unwrap().unwrap();
        assert_eq!(g.rings.len(), 1); assert_eq!(ends(&g.rings[0]), p(0., 0.));
        assert!(r.read_codepoint(0x42).unwrap().is_none());
    }
}
#[test] fn upm_other_than_1000_is_rejected_with_or_without_matrix() {
    assert_eq!(open(1024, None).err(), Some(ReadReject::UnitsPerEmNotThousand(1024)));
    assert_eq!(open(1024, Some(DEF)).err(), Some(ReadReject::UnitsPerEmNotThousand(1024)));
    assert_eq!(open(1024, Some(["0.0009765625", "0", "0", "0.0009765625", "0", "0"])).err(), Some(ReadReject::UnitsPerEmNotThousand(1024)));
    assert_eq!(open(2000, Some(["0.0005", "0", "0", "0.0005", "0", "0"])).err(), Some(ReadReject::UnitsPerEmNotThousand(2000)));
}
#[test] fn font_matrix_must_equal_default_exactly() {
    for m in [["0.002", "0", "0", "0.002", "0", "0"], ["0.001", "0", "0", "0.00100001", "0", "0"], ["0.001", "0", "0", "0.001", "10", "0"], ["0.001", "0.0001", "0", "0.001", "0", "0"], ["0.00099999", "0", "0", "0.00099999", "0", "0"]] {
        assert_eq!(open(1000, Some(m)).err(), Some(ReadReject::NonDefaultFontMatrix), "{m:?}");
    }
}
