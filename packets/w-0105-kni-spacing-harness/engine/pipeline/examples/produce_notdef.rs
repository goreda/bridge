//! Runtime pixel producer, not a font export. No source-font argument or metadata.
//! Claim-only: packages bounded reads, byte pins and the request's candidate
//! claims into evidence v3. Decode, form frequency and gray checks are the
//! validator's job.
#[path = "../src/notdef_producer.rs"]
mod notdef_producer;
use kni_pipeline::notdef_types::{PixelContext, PixelNotdefKind};
use kni_core::{cff_reader::sha256_hex, jpeg_source::Limits};
use std::{
    collections::BTreeMap,
    fs,
    io::Read,
    path::{Component, Path, PathBuf},
};
fn bounded(p: &Path, cap: usize) -> Result<Vec<u8>, String> {
    let mut f = fs::File::open(p).map_err(|e| e.to_string())?;
    let m = f.metadata().map_err(|e| e.to_string())?;
    if !m.is_file() {
        return Err("InvalidSourceImage".into());
    }
    let n = usize::try_from(m.len()).map_err(|_| "ResourceLimit")?;
    let charge = n.checked_add(1).ok_or("ResourceLimit")?;
    if charge > cap {
        return Err("ResourceLimit".into());
    }
    let mut b = Vec::new();
    b.try_reserve_exact(charge).map_err(|_| "ResourceLimit")?;
    f.by_ref()
        .take(charge as u64)
        .read_to_end(&mut b)
        .map_err(|e| e.to_string())?;
    if b.len() != n {
        return Err("InputChangedDuringRead".into());
    }
    Ok(b)
}
fn within(root: &Path, rel: &str) -> Result<PathBuf, String> {
    let p = Path::new(rel);
    if p.is_absolute() || !p.components().all(|c| matches!(c, Component::Normal(_))) {
        return Err("ContextMismatch".into());
    }
    let p = root.join(p).canonicalize().map_err(|e| e.to_string())?;
    if !p.starts_with(root) {
        return Err("ContextMismatch".into());
    }
    Ok(p)
}
fn charge(left: &mut usize, n: usize) -> Result<(), String> {
    *left = left.checked_sub(n).ok_or("ResourceLimit")?;
    Ok(())
}
fn run() -> Result<(), String> {
    let a: Vec<_> = std::env::args().collect();
    if a.len() != 7 {
        return Err("usage: produce_notdef PIXEL_REQUEST.tsv TILE_ROOT NEW_OUTPUT_DIR MAX_INPUT_BYTES MAX_PIXELS MAX_WORKING_BYTES".into());
    }
    let cap = a[4].parse::<usize>().map_err(|_| "input cap")?;
    let pixels = a[5].parse::<usize>().map_err(|_| "pixel cap")?;
    let working = a[6].parse::<usize>().map_err(|_| "work cap")?;
    let mut left = working;
    let root = Path::new(&a[2]).canonicalize().map_err(|e| e.to_string())?;
    let raw = bounded(Path::new(&a[1]), cap.min(1 << 20).min(left))?;
    charge(&mut left, raw.len().saturating_mul(3).saturating_add(1024))?;
    let text = std::str::from_utf8(&raw).map_err(|_| "requestUTF8")?;
    let mut ls = text.lines();
    if ls.next() != Some("kni-pixel-notdef-request\tv3") {
        return Err("request schema".into());
    }
    let mut fields = BTreeMap::new();
    let mut inputs = Vec::new();
    for line in ls {
        let f: Vec<_> = line.split('\t').collect();
        match f.as_slice() {
            ["source", cp, path, pin, role] => {
                if inputs.len() >= 65535 {
                    return Err("ResourceLimit".into());
                }
                let cp = u32::from_str_radix(cp.trim_start_matches("0x"), 16).map_err(|_| "cp")?;
                charge(&mut left, path.len().saturating_add(512))?;
                let b = bounded(&within(&root, path)?, cap.min(left))?;
                charge(&mut left, b.len().saturating_add(1))?;
                if sha256_hex(&b) != *pin {
                    return Err("ShaMismatch".into());
                }
                let role = match *role {
                    "ordinary" => None,
                    "repeated-form" => Some(PixelNotdefKind::RepeatedForm),
                    "blank-cell" => Some(PixelNotdefKind::BlankCell),
                    _ => return Err("pixel role".into()),
                };
                inputs.push((cp, path.to_string(), b, role));
            }
            [k, v] => {
                if ![
                    "style",
                    "cohort",
                    "frame",
                    "scale",
                    "ink_model",
                    "selected_source_sha256",
                    "pixel_form_sha256",
                    "request_source",
                    "capture_record",
                    "capture_record_sha256",
                ]
                .contains(k)
                {
                    return Err("unknown request field".into());
                }
                if fields.insert(*k, *v).is_some() {
                    return Err("duplicate field".into());
                }
            }
            _ => return Err("request grammar".into()),
        }
    }
    let get = |k| fields.get(k).copied().ok_or_else(|| format!("missing {k}"));
    let capture = bounded(&within(&root, get("capture_record")?)?, cap.min(left))?;
    charge(&mut left, capture.len().saturating_add(1))?;
    let context = PixelContext {
        style: get("style")?.into(),
        frame: get("frame")?.into(),
        units_per_px: get("scale")?.parse().map_err(|_| "scale")?,
        source_sha256: get("selected_source_sha256")?.into(),
        ink_model: get("ink_model")?.into(),
    };
    let tiles: Vec<_> = inputs
        .iter()
        .map(|(cp, p, b, role)| notdef_producer::Tile {
            cp: *cp,
            path: p,
            bytes: b,
            role: *role,
        })
        .collect();
    let req = notdef_producer::Request {
        context: &context,
        cohort: get("cohort")?,
        request_source: get("request_source")?,
        capture_record: &capture,
        capture_sha256: get("capture_record_sha256")?,
        space_evidence_sha256: None,
        pixel_form_sha256: get("pixel_form_sha256")?,
        tiles: &tiles,
        limits: Limits {
            max_input_bytes: cap,
            max_pixels: pixels,
            max_working_bytes: working
                .checked_sub(raw.len().saturating_mul(3).saturating_add(1024))
                .ok_or("ResourceLimit")?,
        },
    };
    let p = notdef_producer::produce(&req).map_err(|e| format!("pixel_notdef::{e:?}"))?;
    let out = Path::new(&a[3]);
    fs::create_dir(out).map_err(|e| e.to_string())?;
    let write = (|| -> Result<(), String> {
        use std::io::Write;
        for (_, rel, b, _) in &inputs {
            let path = out.join(rel);
            if let Some(d) = path.parent() {
                fs::create_dir_all(d).map_err(|e| e.to_string())?;
            }
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(path)
                .map_err(|e| e.to_string())?;
            f.write_all(b).map_err(|e| e.to_string())?;
        }
        for (n, b) in [
            ("evidence.tsv", p.evidence.as_bytes()),
            ("producer-request.tsv", raw.as_slice()),
            ("source-capture-record.bin", capture.as_slice()),
        ] {
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(out.join(n))
                .map_err(|e| e.to_string())?;
            f.write_all(b).map_err(|e| e.to_string())?;
        }
        Ok(())
    })();
    if let Err(e) = write {
        let _ = fs::remove_dir_all(out);
        return Err(e);
    }
    println!("evidence_sha256\t{}", p.evidence_sha);
    Ok(())
}
fn main() {
    if let Err(e) = run() {
        eprintln!("REFUSED {e}");
        std::process::exit(3);
    }
}
#[cfg(test)]
mod remaining_cap_tests {
    use super::*;
    #[test]
    fn before_read_cap_and_checked_charge() {
        let p = std::env::temp_dir().join(format!("pixel-cap-{}", std::process::id()));
        fs::write(&p, b"12345678").unwrap();
        assert!(bounded(&p, 8).is_err());
        assert_eq!(bounded(&p, 9).unwrap(), b"12345678");
        let mut n = 0;
        assert!(charge(&mut n, 1).is_err());
        assert_eq!(n, 0);
        let _ = fs::remove_file(p);
    }
}
