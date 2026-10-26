//! Population floor: when no glyph survives (processed set empty or all
//! excluded) the engine still ships a minimal parseable OTF holding only an
//! empty `.notdef`. Nothing is invented: no outlines, no cmap rows, no kern.
use super::{clip_metadata, encode_with_layout, prepare_generated, DrawnGlyph, NativeFontInput};
use std::io::Write;
use std::path::{Path, PathBuf};

/// Receipt row marking that the font is the population floor.
pub const FLOOR_RECEIPT_ROW: &str = "population_floor\ttrue\n";

/// Build and publish the floor font into `out_dir/font.otf` (exclusive create).
/// `notdef_advance` is the advance already derived for the empty `.notdef`
/// by the caller (the font's own measurements); it is not defaulted here.
pub fn publish_floor(meta: NativeFontInput, notdef_advance: f64, out_dir: &Path, receipt: &mut String) -> Result<PathBuf, String> {
    let notdef = DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] };
    let rows: Vec<(String, f64, f64, f64)> = vec![(".notdef".into(), 0.0, 0.0, notdef_advance)];
    let prepared = clip_metadata(prepare_generated(&[notdef], &[], &rows, &meta)
        .map_err(|e| format!("population floor prepare refused: {e:?}"))?);
    let bytes = encode_with_layout(&prepared, None).map_err(|e| format!("population floor encode refused: {e:?}"))?;
    let path = out_dir.join("font.otf");
    let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(&path)
        .map_err(|e| format!("population floor publish: {e}"))?;
    f.write_all(&bytes).map_err(|e| format!("population floor publish: {e}"))?;
    receipt.push_str(FLOOR_RECEIPT_ROW);
    receipt.push_str(&format!("population_floor_glyphs\t1\tadvance\t{notdef_advance}\n"));
    std::fs::write(out_dir.join("receipt.txt"), receipt.as_bytes()).map_err(|e| format!("write receipt: {e}"))?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::names;
    use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, Os2Metadata, PostMetadata};

    fn meta() -> NativeFontInput {
        NativeFontInput {
            postscript_name: "Test-Regular".into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
            head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 1 },
            hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
            post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
            os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
                panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
            names: names("Test", "Regular", "Test-Regular"),
        }
    }
    fn u16at(b: &[u8], o: usize) -> u16 { u16::from_be_bytes([b[o], b[o + 1]]) }

    #[test]
    fn empty_population_builds_parseable_notdef_only_font() {
        let d = std::env::temp_dir().join(format!("kni_floor_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d); std::fs::create_dir_all(&d).unwrap();
        let mut r = String::new();
        let p = publish_floor(meta(), 500.0, &d, &mut r).unwrap();
        let b = std::fs::read(&p).unwrap();
        assert!(b.starts_with(b"OTTO"), "CFF sfnt magic");
        let n = u16at(&b, 4) as usize;
        let mut tags = Vec::new();
        let (mut maxp, mut hmtx_len) = (None, 0usize);
        for i in 0..n {
            let rec = 12 + i * 16;
            let tag = &b[rec..rec + 4];
            let off = u32::from_be_bytes(b[rec + 8..rec + 12].try_into().unwrap()) as usize;
            let len = u32::from_be_bytes(b[rec + 12..rec + 16].try_into().unwrap()) as usize;
            if tag == b"maxp" { maxp = Some(off); }
            if tag == b"hmtx" { hmtx_len = len; }
            tags.push(String::from_utf8_lossy(tag).to_string());
        }
        for t in ["CFF ", "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post"] { assert!(tags.iter().any(|x| x == t), "missing table {t}: {tags:?}"); }
        assert!(!tags.iter().any(|x| x == "GPOS"), "no kern invented");
        assert_eq!(u16at(&b, maxp.unwrap() + 4), 1, "exactly one glyph (.notdef)");
        assert!(hmtx_len >= 4);
        assert!(r.contains("population_floor\ttrue"));
        assert!(d.join("receipt.txt").exists());
        // exclusive publish: a second call refuses and leaves the first font intact
        assert!(publish_floor(meta(), 500.0, &d, &mut String::new()).is_err());
        assert_eq!(std::fs::read(&p).unwrap(), b);
        let _ = std::fs::remove_dir_all(&d);
    }
}
