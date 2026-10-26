//! Acceptance-structure tests for the Glyphs v3 writer (chief 2026-10-18):
//! fail on missing metrics/metricValues/order/master name/value mismatch,
//! legacy scalar master fields, invented facts, or nondeterminism.

use kni_master::fixture;
use kni_master::glyphs::*;

fn font() -> MasterFont {
    let h = fixture::parse(
        "glyph h 620 1000\nstroke stem\nM 60 0\nL 60 700\nL 140 700\nL 140 0\nZ\nstroke arm\nM 140 350\nC 200 430 300 430 300 300\nL 300 0\nL 380 0\nL 380 320\nC 380 500 200 500 140 400\nZ\n",
    )
    .unwrap();
    let dotlessi = fixture::parse("glyph dotlessi 260 1000\nstroke stem\nM 90 0\nL 90 500\nL 170 500\nL 170 0\nZ\n").unwrap();
    let notdef = fixture::parse("glyph .notdef 500 1000\nstroke box\nM 50 0\nL 50 700\nL 450 700\nL 450 0\nZ\n").unwrap();
    MasterFont {
        info: FontInfo {
            version_raw: "Version 1.050".into(),
            family_name: "Marq".into(),
            style_name: "Alternate".into(),
            version_major: 1,
            version_minor: 50,
            units_per_em: 1000,
            properties: vec![
                InfoProperty { key: "designer".into(), value: "Karl Nawrot".into() },
                InfoProperty { key: "copyright".into(), value: "© 2025 Karl Nawrot".into() },
            ],
            instance: InstanceInfo { weight_class: 400, width_class: 5, bold: false, italic: false },
        },
        metrics: VerticalMetrics { ascender: 770.0, cap_height: 700.0, x_height: 500.0, descender: -145.0 },
        glyphs: vec![(notdef, vec![], true), (h, vec![0x68], true), (dotlessi, vec![], true)],
        kerning: vec![],
    }
}

#[test]
fn top_level_metrics_in_fixed_order() {
    let s = write_glyphs(&font()).unwrap();
    let m = s.find("metrics = (").unwrap();
    let section = &s[m..];
    let a = section.find("type = \"ascender\";").unwrap();
    let c = section.find("type = \"cap height\";").unwrap();
    let x = section.find("type = \"x-height\";").unwrap();
    let b = section.find("type = \"baseline\";").unwrap();
    let d = section.find("type = \"descender\";").unwrap();
    assert!(a < c && c < x && x < b && b < d, "{section}");
}

#[test]
fn master_metric_values_align_with_metrics_order_and_source_values() {
    let s = write_glyphs(&font()).unwrap();
    let m = s.find("metricValues = (").unwrap();
    let section = &s[m..s.find("name = \"Alternate\";").unwrap()];
    let poss: Vec<&str> = section.matches("pos = ").collect();
    assert_eq!(poss.len(), 5, "one metricValues pos per metrics entry: {section}");
    for want in ["pos = 770;", "pos = 700;", "pos = 500;", "pos = 0;", "pos = -145;"] {
        assert!(section.contains(want), "missing {want}: {section}");
    }
    // order: ascender, cap height, x-height, baseline, descender
    let order: Vec<usize> = ["pos = 770;", "pos = 700;", "pos = 500;", "pos = 0;", "pos = -145;"]
        .iter()
        .map(|w| section.find(w).unwrap())
        .collect();
    assert!(order.windows(2).all(|w| w[0] < w[1]), "{order:?}");
    // no blind overshoots
    assert!(!section.contains("over ="), "unmeasured overshoot emitted: {section}");
}

#[test]
fn no_legacy_scalar_master_metrics() {
    let s = write_glyphs(&font()).unwrap();
    let fm = s.find("fontMaster = (").unwrap();
    let g = s.find("glyphs = (").unwrap();
    let master = &s[fm..g];
    for legacy in ["ascender =", "capHeight =", "xHeight =", "descender ="] {
        assert!(!master.contains(legacy), "legacy scalar field in master: {legacy}");
    }
    assert!(master.contains("name = \"Alternate\";"), "master name from style metadata");
    assert!(master.contains("id = \"m01\";"));
}

#[test]
fn glyphs_keep_structural_strokes_widths_unicodes() {
    let s = write_glyphs(&font()).unwrap();
    // h: two structural strokes -> two closed paths, not merged
    let h_start = s.find("glyphname = \"h\";").unwrap();
    let h_end = s.find("glyphname = \"dotlessi\";").unwrap();
    let h = &s[h_start..h_end];
    assert_eq!(h.matches("closed = 1;").count(), 2, "{h}");
    assert!(h.contains("width = 620;"), "{h}");
    assert!(h.contains("unicode = 104;"), "{h}");
    assert!(h.contains("layerId = \"m01\";"), "{h}");
    // off-curve pairs and cubic nodes in tuple form
    assert!(h.contains(",o)"), "{h}");
    assert!(h.contains(",c)"), "{h}");
    // stroke names preserved via the shared userData contract, parallel to shapes
    assert!(h.contains("\"KNI.strokeNames\" = (\n\"stem\",\n\"arm\"\n);"), "{h}");
    // .notdef: no unicode row, still exported with its path
    let n_start = s.find("glyphname = \".notdef\";").unwrap();
    let nd = &s[n_start..s.find("glyphname = \"h\";").unwrap()];
    assert!(!nd.contains("unicode"), "{nd}");
    assert!(nd.contains("width = 500;"), "{nd}");
    // dotlessi unmapped: no unicode
    let d = &s[h_end..];
    assert!(!d.contains("unicode ="), "{d}");
}

#[test]
fn font_info_and_instance_from_source() {
    let s = write_glyphs(&font()).unwrap();
    assert!(s.contains("familyName = \"Marq\";"), "{s}");
    assert!(s.contains("unitsPerEm = 1000;"), "{s}");
    assert!(s.contains("versionMajor = 1;"), "{s}");
    assert!(s.contains("versionMinor = 50;"), "{s}");
    assert!(s.contains("weightClass = 400;"), "{s}");
    assert!(s.contains("widthClass = 5;"), "{s}");
    assert!(!s.contains("isBold"), "{s}");
    assert!(s.contains("key = \"designer\";\nvalue = \"Karl Nawrot\";"), "{s}");
    assert!(s.contains("key = \"copyright\";"), "{s}");
    assert!(s.contains(".formatVersion = 3;"), "{s}");
    // Declared generator exception: .appVersion is required by the official
    // schema but omitted, never forged (see module docs). This test FAILS if
    // anyone re-adds a forged build number.
    assert!(!s.contains(".appVersion"), "{s}");
}

#[test]
fn deterministic_write() {
    // Version grammar cases live in the ONE joint fixture
    // (master/tests/version_parse.rs, shared parser kni_master::version).
    let f = font();
    assert_eq!(write_glyphs(&f).unwrap(), write_glyphs(&f).unwrap());
}

#[test]
fn multi_unicode_and_nonfinite_refusal() {
    let mut f = font();
    f.glyphs[1].1 = vec![0x68, 0x2095];
    let s = write_glyphs(&f).unwrap();
    assert!(s.contains("unicode = (104,8341);"), "{s}");
    let mut bad = font();
    bad.metrics.ascender = f64::NAN;
    assert!(write_glyphs(&bad).is_err());
}

#[test]
fn write_glyphs_emits_kerning_ltr_under_m01() {
    let mut f = font();
    f.kerning = vec![
        kni_master::glyphs_file::KerningPair { master_id: "m01".into(), left: "h".into(), right: "dotlessi".into(), value: -42.0 },
        kni_master::glyphs_file::KerningPair { master_id: "m01".into(), left: "h".into(), right: "h".into(), value: -7.0 },
    ];
    let doc = kni_master::glyphs::write_glyphs(&f).unwrap();
    assert!(doc.contains("kerningLTR"), "doc must carry kerningLTR: {doc}");
    let root = kni_master::glyphsfile::parse(doc.as_bytes()).unwrap();
    let info = kni_master::glyphsfile::font_info(&root).unwrap();
    let home = info.kern_homes.iter().find(|h| h.table == "kerningLTR").expect("kerningLTR home");
    assert_eq!(home.master.as_deref(), Some("m01"));
    let mut got = home.pairs.clone();
    got.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    assert_eq!(got, vec![
        ("h".to_string(), "dotlessi".to_string(), -42.0),
        ("h".to_string(), "h".to_string(), -7.0),
    ]);
}
