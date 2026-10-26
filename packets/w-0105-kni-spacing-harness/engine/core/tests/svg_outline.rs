// Authored fixture expectations, NOT_RUN. No quality or raster-trace evidence.
use kni_core::reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};
use kni_core::svg_outline::{outline_svg,FillRule,SourceViewport,SvgError};

fn ring(points: &[(f64,f64)]) -> ReferenceRing {
    let start = Point { x: points[0].0,y: points[0].1 };
    ReferenceRing { start,spans: points[1..].iter().map(|(x,y)| Span::Line { end: Point { x:*x,y:*y } }).collect() }
}
fn viewport() -> SourceViewport { SourceViewport { x:0.0,y:0.0,width:100.0,height:100.0 } }

#[test]
fn compound_two_counter_outline_keeps_three_rings() {
    let glyph = DrawnGlyph { glyph_id:String::from("B-fixture"),rings:vec![
        ring(&[(0.,0.),(100.,0.),(100.,100.),(0.,100.),(0.,0.)]),
        ring(&[(20.,20.),(20.,40.),(80.,40.),(80.,20.),(20.,20.)]),
        ring(&[(20.,60.),(20.,80.),(80.,80.),(80.,60.),(20.,60.)]),
    ]};
    let svg = outline_svg(&glyph,viewport(),FillRule::NonZero).unwrap();
    assert_eq!(svg.matches('Z').count(),3);
    assert!(svg.contains("fill-rule=\"nonzero\""));
    assert!(!svg.contains("confidence"));
}

#[test]
fn open_contour_is_not_silently_closed() {
    let glyph = DrawnGlyph { glyph_id:String::from("open"),rings:vec![ring(&[(0.,0.),(20.,0.),(20.,20.)])] };
    assert!(matches!(outline_svg(&glyph,viewport(),FillRule::EvenOdd),Err(SvgError::OpenContour)));
}

#[test]
fn supplied_cubic_controls_are_preserved() {
    let origin = Point { x:0.,y:0. };
    let glyph = DrawnGlyph { glyph_id:String::from("curve-fixture"),rings:vec![ReferenceRing { start:origin,spans:vec![
        Span::Cubic { control_one:Point { x:10.,y:20. },control_two:Point { x:30.,y:40. },end:origin }
    ]}]};
    let svg = outline_svg(&glyph,viewport(),FillRule::EvenOdd).unwrap();
    assert!(svg.contains("C10 20 30 40 0 0Z"));
}

#[test]
fn full_b_style_bytes() {
    let glyph = DrawnGlyph { glyph_id:String::from("B-fixture"),rings:vec![
        ring(&[(0.,0.),(100.,0.),(100.,100.),(0.,100.),(0.,0.)]),
        ring(&[(20.,20.),(20.,40.),(80.,40.),(80.,20.),(20.,20.)]),
        ring(&[(20.,60.),(20.,80.),(80.,80.),(80.,60.),(20.,60.)]),
    ]};
    assert_eq!(outline_svg(&glyph,viewport(),FillRule::NonZero).unwrap(),
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><path d=\"M0 0L100 0L100 100L0 100L0 0ZM20 20L20 40L80 40L80 20L20 20ZM20 60L20 80L80 80L80 60L20 60Z\" fill-rule=\"nonzero\"/></svg>");
}

#[test]
fn full_cubic_bytes() {
    let origin = Point { x:0.,y:0. };
    let glyph = DrawnGlyph { glyph_id:String::from("cubic"),rings:vec![ReferenceRing { start:origin,spans:vec![
        Span::Cubic { control_one:Point { x:10.,y:20. },control_two:Point { x:30.,y:40. },end:origin }
    ]}]};
    assert_eq!(outline_svg(&glyph,viewport(),FillRule::EvenOdd).unwrap(),
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><path d=\"M0 0C10 20 30 40 0 0Z\" fill-rule=\"evenodd\"/></svg>");
}

#[test]
fn a_style_one_counter_exact_bytes_both_fill_rules() {
    // Synthetic triangular outline/counter, not a recovered typeface glyph.
    let glyph = DrawnGlyph { glyph_id:String::from("A-fixture"),rings:vec![
        ring(&[(0.,100.),(50.,0.),(100.,100.),(0.,100.)]),
        ring(&[(40.,60.),(60.,60.),(50.,40.),(40.,60.)]),
    ]};
    for (rule, name) in [(FillRule::NonZero,"nonzero"),(FillRule::EvenOdd,"evenodd")] {
        let expected = format!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><path d=\"M0 100L50 0L100 100L0 100ZM40 60L60 60L50 40L40 60Z\" fill-rule=\"{}\"/></svg>",name);
        assert_eq!(outline_svg(&glyph,viewport(),rule).unwrap(),expected);
    }
}

#[test]
fn empty_outline_and_empty_ring_rejected() {
    let mut glyph = DrawnGlyph { glyph_id:String::from("empty"),rings:vec![] };
    assert!(matches!(outline_svg(&glyph,viewport(),FillRule::NonZero),Err(SvgError::NoOutline)));
    glyph.rings.push(ReferenceRing { start:Point { x:0.,y:0. },spans:vec![] });
    assert!(matches!(outline_svg(&glyph,viewport(),FillRule::NonZero),Err(SvgError::NoOutline)));
}

#[test]
fn invalid_and_nonfinite_viewports_rejected() {
    let glyph = DrawnGlyph { glyph_id:String::from("square"),rings:vec![ring(&[(0.,0.),(1.,0.),(1.,1.),(0.,0.)])] };
    for width in [0.,-1.] {
        assert!(matches!(outline_svg(&glyph,SourceViewport { width,..viewport() },FillRule::NonZero),Err(SvgError::InvalidViewport)));
    }
    for height in [0.,-1.] {
        assert!(matches!(outline_svg(&glyph,SourceViewport { height,..viewport() },FillRule::NonZero),Err(SvgError::InvalidViewport)));
    }
    for bad in [f64::NAN,f64::INFINITY,f64::NEG_INFINITY] {
        for view in [SourceViewport { x:bad,..viewport() },SourceViewport { y:bad,..viewport() },SourceViewport { width:bad,..viewport() },SourceViewport { height:bad,..viewport() }] {
            assert!(matches!(outline_svg(&glyph,view,FillRule::NonZero),Err(SvgError::NonFinite)));
        }
    }
}

#[test]
fn nonfinite_start_endpoint_and_cubic_controls_rejected() {
    for bad in [f64::NAN,f64::INFINITY,f64::NEG_INFINITY] {
        let origin = Point { x:0.,y:0. };
        let cases = vec![
            ReferenceRing { start:Point { x:bad,y:0. },spans:vec![Span::Line { end:origin }] },
            ReferenceRing { start:origin,spans:vec![Span::Line { end:Point { x:0.,y:bad } }] },
            ReferenceRing { start:origin,spans:vec![Span::Cubic { control_one:Point { x:bad,y:0. },control_two:origin,end:origin }] },
            ReferenceRing { start:origin,spans:vec![Span::Cubic { control_one:origin,control_two:Point { x:0.,y:bad },end:origin }] },
        ];
        for candidate in cases {
            let glyph = DrawnGlyph { glyph_id:String::from("bad"),rings:vec![candidate] };
            assert!(matches!(outline_svg(&glyph,viewport(),FillRule::EvenOdd),Err(SvgError::NonFinite)));
        }
    }
}

#[test]
fn signed_zero_output_is_preserved_not_normalized() {
    let glyph = DrawnGlyph { glyph_id:String::from("signed-zero"),rings:vec![ring(&[(-0.,0.),(1.,0.),(1.,1.),(-0.,0.)])] };
    assert_eq!(outline_svg(&glyph,viewport(),FillRule::NonZero).unwrap(),
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><path d=\"M-0 0L1 0L1 1L-0 0Z\" fill-rule=\"nonzero\"/></svg>");
}
