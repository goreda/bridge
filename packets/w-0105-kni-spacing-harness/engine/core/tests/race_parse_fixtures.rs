//! Pinned parser fixtures for the four-way benchmark harness
//! (core/examples/race_external.rs). Each fixture is an inline SVG byte
//! string in one external tracer's convention; the test pins the parser's
//! behavior on it: potrace g-transform, autotrace white-background drop and
//! white counter flagging, vtracer authored winding with counter subpaths,
//! and typed refusals (unsupported transform, unsupported path command,
//! unsafe glyph name).

#![allow(dead_code)]

#[path = "../examples/race_external.rs"]
mod race;

use kni_core::reference_slice::Span;

fn square(x0: f64, y0: f64, s: f64) -> String {
    format!("M {} {} H {} V {} H {} Z", x0, y0, x0 + s, y0 + s, x0)
}

#[test]
fn potrace_g_transform_translate_scale() {
    let svg = format!(
        "<svg><g transform=\"translate(10,20) scale(2,3)\"><path d=\"{}\"/></g></svg>",
        square(0.0, 0.0, 4.0)
    );
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 1);
    let (start, spans, is_white) = &rings[0];
    assert!(!is_white);
    // translate(10,20) scale(2,3): x' = 10 + 2x, y' = 20 + 3y
    assert_eq!((start.x, start.y), (10.0, 20.0));
    let mut xs = Vec::new();
    let mut ys = Vec::new();
    for sp in spans {
        match sp {
            Span::Line { end } => { xs.push(end.x); ys.push(end.y); }
            _ => panic!("fixture has lines only"),
        }
    }
    assert!(xs.contains(&18.0) && ys.contains(&32.0), "scaled square corner 10+2*4=18, 20+3*4=32");
}

#[test]
fn potrace_white_bg_not_dropped() {
    // Background drop is skipped in potrace mode (potrace SVGs carry none).
    let svg = format!("<svg><path fill=\"#ffffff\" d=\"{}\"/></svg>", square(0.0, 0.0, 100.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 1);
    assert!(rings[0].2, "white path kept and flagged white in potrace mode");
}

#[test]
fn autotrace_white_bg_dropped_white_counter_kept() {
    let bg = format!("<path fill=\"#ffffff\" d=\"{}\"/>", square(0.0, 0.0, 100.0));
    let ink = format!("<path fill=\"#000000\" d=\"{}\"/>", square(10.0, 10.0, 50.0));
    let counter = format!("<path fill=\"#ffffff\" d=\"{}\"/>", square(25.0, 25.0, 10.0));
    let svg = format!("<svg>{bg}{ink}{counter}</svg>");
    let rings = race::parse_svg(&svg, "autotrace", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 2, "canvas-covering white background dropped, ink + counter kept");
    let whites: Vec<bool> = rings.iter().map(|r| r.2).collect();
    assert_eq!(whites.iter().filter(|w| **w).count(), 1, "exactly one white counter");
    assert_eq!(whites.iter().filter(|w| !**w).count(), 1, "exactly one ink ring");
}

#[test]
fn vtracer_authored_winding_counter_subpath() {
    // One path, two subpaths: outer CCW, inner CW (authored counter winding).
    let outer = square(0.0, 0.0, 40.0);
    let inner = "M 10 10 V 30 H 20 V 10 Z".to_string();
    let svg = format!("<svg><path d=\"{outer} {inner}\"/></svg>");
    let rings = race::parse_svg(&svg, "vtracer", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 2, "two subpaths kept as two rings");
    let a0 = race::signed_area(rings[0].0, &rings[0].1);
    let a1 = race::signed_area(rings[1].0, &rings[1].1);
    assert!(a0 * a1 < 0.0, "counter subpath keeps opposite authored winding: {a0} vs {a1}");
}

#[test]
fn signed_area_square_value() {
    let svg = format!("<svg><path d=\"{}\"/></svg>", square(0.0, 0.0, 10.0));
    let rings = race::parse_svg(&svg, "vtracer", (100, 100)).expect("parse");
    let a = race::signed_area(rings[0].0, &rings[0].1);
    assert_eq!(a.abs(), 100.0, "10x10 square area magnitude");
}

#[test]
fn unsupported_transform_is_typed_error() {
    let svg = format!("<svg><g transform=\"rotate(90)\"><path d=\"{}\"/></g></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("unsupported function"), "got: {err}");
}

#[test]
fn quadratic_command_is_typed_error() {
    let svg = "<svg><path d=\"M 0 0 Q 5 5 10 0 Z\"/></svg>";
    let err = race::parse_svg(svg, "vtracer", (100, 100)).unwrap_err();
    assert!(err.contains("unsupported command Q"), "got: {err}");
}

#[test]
fn multiple_g_transform_groups_is_typed_error() {
    let svg = format!(
        "<svg><g transform=\"translate(1,1)\"><path d=\"{}\"/></g><g transform=\"scale(2,2)\"><path d=\"{}\"/></g></svg>",
        square(0.0, 0.0, 4.0), square(10.0, 10.0, 4.0)
    );
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("more than one transform group"), "got: {err}");
}

#[test]
fn unsafe_glyph_names_refused() {
    for bad in ["../escape", "a/b", "a\\b", "a..b", "", ".", ".."] {
        assert!(race::safe_glyph_name(bad).is_err(), "accepted: {bad:?}");
    }
    for good in ["A", "percent", "e.acute", "uni00E9", "f_f_i"] {
        assert!(race::safe_glyph_name(good).is_ok(), "refused: {good:?}");
    }
}

#[test]
fn transform_bad_numeric_arg_refused() {
    let svg = format!("<svg><g transform=\"translate(1,bad)\"><path d=\"{}\"/></g></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("bad number"), "got: {err}");
}

#[test]
fn transform_nonfinite_refused() {
    let svg = format!("<svg><g transform=\"translate(inf,1)\"><path d=\"{}\"/></g></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("nonfinite"), "got: {err}");
}

#[test]
fn transform_composition_is_ordered_not_commutative() {
    // translate(10,20) scale(2,3): x' = 10 + 2x ; scale first: x' = 2*(10+x) = 20 + 2x
    let mk = |t: &str| format!("<svg><g transform=\"{t}\"><path d=\"{}\"/></g></svg>", square(1.0, 1.0, 1.0));
    let a = race::parse_svg(&mk("translate(10,20) scale(2,3)"), "potrace", (100, 100)).expect("parse");
    let b = race::parse_svg(&mk("scale(2,3) translate(10,20)"), "potrace", (100, 100)).expect("parse");
    assert_eq!((a[0].0.x, a[0].0.y), (12.0, 23.0), "translate then scale");
    assert_eq!((b[0].0.x, b[0].0.y), (22.0, 63.0), "scale then translate differs");
}

#[test]
fn path_transform_refused() {
    let svg = format!("<svg><path transform=\"scale(2,2)\" d=\"{}\"/></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("path transform"), "got: {err}");
}

#[test]
fn transform_single_quote_variant_refused() {
    let svg = format!("<svg><g transform='translate(1,1)'><path d=\"{}\"/></g></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("unsupported attribute form"), "got: {err}");
}

#[test]
fn transform_whitespace_variant_refused() {
    let svg = format!("<svg><g transform = \"translate(1,1)\"><path d=\"{}\"/></g></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("unsupported attribute form"), "got: {err}");
}

#[test]
fn group_transform_scoped_to_group_only() {
    let inside = square(1.0, 1.0, 1.0);
    let outside = square(5.0, 5.0, 1.0);
    let svg = format!("<svg><g transform=\"translate(10,20)\"><path d=\"{inside}\"/></g><path d=\"{outside}\"/></svg>");
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 2);
    assert_eq!((rings[0].0.x, rings[0].0.y), (11.0, 21.0), "inside path translated");
    assert_eq!((rings[1].0.x, rings[1].0.y), (5.0, 5.0), "outside path untouched");
}

#[test]
fn unterminated_group_refused() {
    let svg = format!("<svg><g transform=\"translate(1,1)\"><path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("missing </g>"), "got: {err}");
}

#[test]
fn tokens_after_close_refused() {
    let svg = "<svg><path d=\"M 0 0 L 1 0 Z 5\"/></svg>";
    let err = race::parse_svg(svg, "vtracer", (100, 100)).unwrap_err();
    assert!(err.contains("tokens after close"), "got: {err}");
}

#[test]
fn empty_subpath_refused() {
    let svg = "<svg><path d=\"M 0 0 Z\"/></svg>";
    let err = race::parse_svg(svg, "vtracer", (100, 100)).unwrap_err();
    assert!(err.contains("empty subpath"), "got: {err}");
}

#[test]
fn scientific_notation_is_typed_subset_error() {
    let svg = "<svg><path d=\"M 0 0 L 1e-3 5 Z\"/></svg>";
    let err = race::parse_svg(svg, "vtracer", (100, 100)).unwrap_err();
    // typed subset refusal: the exponent letter never reaches the geometry
    assert!(err.contains("bad number") || err.contains("unsupported command"), "got: {err}");
}

#[test]
fn tile_pin_malformed_and_mismatch_refused() {
    let sha = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
    assert!(race::verify_tile_pin("00069__00D1__abcdef012345.png", sha).is_ok());
    assert!(race::verify_tile_pin("00069__00D1.png", sha).unwrap_err().contains("tile_pin_malformed"), "missing pin");
    assert!(race::verify_tile_pin("00069__00D1__abc.png", sha).unwrap_err().contains("tile_pin_malformed"), "short pin");
    assert!(race::verify_tile_pin("00069__00D1__abcdef01234g.png", sha).unwrap_err().contains("tile_pin_malformed"), "non-hex pin");
    assert!(race::verify_tile_pin("00069__00D1__000000000000.png", sha).unwrap_err().contains("tile_sha_mismatch"), "mismatch");
    assert!(race::verify_tile_pin("noextension", sha).unwrap_err().contains("tile_pin_malformed"), "no .png");
}

#[test]
fn read_capped_refuses_over_cap() {
    let dir = std::env::temp_dir();
    let p = dir.join(format!("race_read_capped_test_{}.bin", std::process::id()));
    std::fs::write(&p, vec![7u8; 64]).unwrap();
    let path = p.to_str().unwrap();
    assert_eq!(race::read_capped(path, 64, "t").unwrap().len(), 64, "at cap ok");
    let err = race::read_capped(path, 63, "t").unwrap_err();
    assert!(err.contains("over 63 bytes"), "got: {err}");
    assert!(race::read_capped("/nonexistent/race_test.bin", 64, "t").unwrap_err().contains("open"), "missing file");
    std::fs::remove_file(&p).ok();
}

#[test]
fn nested_group_refused_even_untransformed() {
    let svg = format!("<svg><g transform=\"translate(10,20)\"><g><path d=\"{}\"/></g><path d=\"{}\"/></g></svg>",
        square(1.0, 1.0, 1.0), square(5.0, 5.0, 1.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("nested group"), "got: {err}");
}

#[test]
fn newline_after_g_accepted_and_transformed() {
    let svg = format!("<svg><g\ntransform=\"translate(10,20)\"><path d=\"{}\"/></g></svg>", square(1.0, 1.0, 1.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("newline opener must parse");
    assert_eq!((rings[0].0.x, rings[0].0.y), (11.0, 21.0), "transform applied, not silently lost");
}

#[test]
fn stray_closer_refused() {
    let svg = format!("<svg></g><path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("stray </g>"), "got: {err}");
}

#[test]
fn unbalanced_group_refused() {
    let svg = format!("<svg><g><path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("unbalanced"), "got: {err}");
}

#[test]
fn transform_composition_overflow_refused() {
    let svg = format!("<svg><g transform=\"scale(1e308,1e308) scale(1e308,1e308)\"><path d=\"{}\"/></g></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("composition overflow"), "got: {err}");
}

#[test]
fn punctuation_in_path_data_refused() {
    let svg = "<svg><path d=\"M 0 0 @ L 1 1 Z\"/></svg>";
    let err = race::parse_svg(svg, "vtracer", (100, 100)).unwrap_err();
    assert!(err.contains("unexpected character"), "got: {err}");
}

#[test]
fn huge_number_overflow_refused() {
    let svg = "<svg><path d=\"M 0 0 L 9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999 1 Z\"/></svg>";
    let err = race::parse_svg(svg, "vtracer", (100, 100)).unwrap_err();
    assert!(err.contains("number overflow"), "got: {err}");
}

#[test]
fn glyph_element_before_group_does_not_swallow_it() {
    let svg = format!("<svg><glyph d=\"M 0 0\"/><garbage x=\"1\"/><g transform=\"translate(10,20)\"><path d=\"{}\"/></g></svg>", square(1.0, 1.0, 1.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("group after other g* elements must parse");
    assert_eq!((rings[0].0.x, rings[0].0.y), (11.0, 21.0), "real group transform applied");
}

#[test]
fn self_closing_group_refused() {
    for svg in [
        format!("<svg><g/><path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0)),
        format!("<svg><g /><path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0)),
        format!("<svg><g transform=\"translate(1,1)\"/><path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0)),
    ] {
        let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
        assert!(err.contains("self-closing"), "got: {err} for {svg}");
    }
}

#[test]
fn comment_with_group_text_does_not_confuse_scan() {
    let svg = format!("<svg><!-- <g transform=\"scale(9,9)\"> </g> --><g transform=\"translate(10,20)\"><path d=\"{}\"/></g></svg>", square(1.0, 1.0, 1.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!((rings[0].0.x, rings[0].0.y), (11.0, 21.0), "comment transform ignored, real one applied");
}

#[test]
fn comment_with_close_tag_inside_group_does_not_end_scope() {
    let svg = format!("<svg><g transform=\"translate(10,20)\"><!-- </g> --><path d=\"{}\"/></g></svg>", square(1.0, 1.0, 1.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!((rings[0].0.x, rings[0].0.y), (11.0, 21.0), "path after comment still in group scope");
}

#[test]
fn unterminated_comment_refused() {
    let svg = format!("<svg><!-- never closed <path d=\"{}\"/></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("comment: unterminated"), "got: {err}");
}

#[test]
fn comment_with_path_text_not_parsed_as_path() {
    let svg = format!("<svg><!-- <path d=\"M 0 0 L 1 1 Z\"/> --><path d=\"{}\"/></svg>", square(1.0, 1.0, 1.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 1, "only the real path parsed");
}

#[test]
fn whitespace_close_spelling_refused() {
    let svg = format!("<svg><g><path d=\"{}\"/></g ></svg>", square(0.0, 0.0, 4.0));
    let err = race::parse_svg(&svg, "potrace", (100, 100)).unwrap_err();
    assert!(err.contains("g close: unsupported spelling"), "got: {err}");
}

#[test]
fn pathology_element_skipped_real_path_parsed() {
    let svg = format!("<svg><pathology d=\"M 9 9\"/><path d=\"{}\"/></svg>", square(1.0, 1.0, 1.0));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("parse");
    assert_eq!(rings.len(), 1);
    assert_eq!((rings[0].0.x, rings[0].0.y), (1.0, 1.0));
}

#[test]
fn many_comments_before_path_iterative_no_stack_abort() {
    // 200k comments (200000 * 7 = ~1.4 MB, well under the 64 MiB cap): must return
    // normally - a recursive scanner would abort the stack here.
    let mut svg = String::with_capacity(3_000_000);
    svg.push_str("<svg>");
    for _ in 0..200_000 { svg.push_str("<!---->"); }
    svg.push_str(&format!("<path d=\"{}\"/></svg>", square(1.0, 1.0, 1.0)));
    let rings = race::parse_svg(&svg, "potrace", (100, 100)).expect("comment-dense input must parse");
    assert_eq!(rings.len(), 1);
    assert_eq!((rings[0].0.x, rings[0].0.y), (1.0, 1.0));
}
