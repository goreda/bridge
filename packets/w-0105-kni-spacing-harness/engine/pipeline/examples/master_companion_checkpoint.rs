//! Optional bounded native master emission from an exact final OTF and CFF names.
//! No fit work, no alternate decomposition thresholds. Full document only on completion.
fn main() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 7 {
        return Err("OTF NAMES.tsv OUTPUT.glyphs CACHE_DIR CONTEXT_SHA256 MAX_NEW".into());
    }
    let b = std::fs::read(&a[1]).map_err(|e| e.to_string())?;
    let (mut f, m) = kni_pipeline::otf_facts::read_otf(&b)?;
    let ns = std::fs::read_to_string(&a[2]).map_err(|e| e.to_string())?;
    if ns.lines().count() != f.glyphs.len() {
        return Err("name count mismatch".into());
    }
    for (g, n) in f.glyphs.iter_mut().zip(ns.lines()) {
        g.name = n.into();
        g.outline.glyph_id = n.into();
    }
    let (d, r) = kni_pipeline::master_companion::build_checkpointed(
        &b,
        &f,
        &m,
        std::path::Path::new(&a[4]),
        &a[5],
        a[6].parse().map_err(|_| "MAX_NEW invalid")?,
    )?;
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&a[3])
        .and_then(|mut file| std::io::Write::write_all(&mut file, d.as_bytes()))
        .map_err(|e| e.to_string())?;
    print!("{r}");
    Ok(())
}
