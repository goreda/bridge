//! Deterministic generator for derive_names_parity.json (utility, not a test). Usage:
//!   cargo run --example gen_derive_names_parity -- <output.json>
//! Writes the exact case vectors (expected values are literals here, checked by the unit tests) and the per-scalar-value corpus
//! computed by `derive_names`. Refuses to run without an explicit output path.
#[path = "../src/run_config.rs"]
#[allow(dead_code)]
mod run_config;
use run_config::derive_names;

fn probe(prefix: &str) -> Vec<(u32, u32, String)> {
    let mut runs: Vec<(u32, u32, String)> = Vec::new();
    for cp in 0..=0x10FFFFu32 {
        let Some(c) = char::from_u32(cp) else { continue };
        let r = match derive_names(&format!("{prefix}{c}/S")) { Ok(d) => format!("ok:{}", d.postscript_name), Err(e) => format!("err:{}", e.kind()) };
        match runs.last_mut() { Some(l) if l.2 == r && l.1 + 1 == cp => l.1 = cp, _ => runs.push((cp, cp, r)) }
    }
    runs
}
fn dump(v: Vec<(u32, u32, String)>) -> String {
    v.iter().map(|(a, b, r)| format!("[\"{:04X}\",\"{:04X}\",\"{}\"]", a, b, r.replace('\\', "\\\\").replace('"', "\\\""))).collect::<Vec<_>>().join(",\n")
}
fn main() {
    let Some(path) = std::env::args().nth(1) else { eprintln!("usage: gen_derive_names_parity <output.json>"); std::process::exit(2) };
    let cases: Vec<(Vec<&str>, &str)> = vec![
        (vec!["L\u{00FF}no/Jean"], "ok:Lyno-Jean"), (vec!["MCA U/3U1.5"], "ok:MCAU-3U1.5"), (vec!["Marq/Alternate"], "ok:Marq-Alternate"),
        (vec!["\u{00F8}x/S"], "err:UnmappableChar"), (vec!["x\u{00DF}/S"], "err:UnmappableChar"), (vec!["\u{0132}/S"], "err:UnmappableChar"),
        (vec!["\u{0416}/S"], "err:UnmappableChar"), (vec!["Ly\u{0308}no/S"], "ok:Lyno-S"), (vec!["\u{0308}x/S"], "err:StrayCombiningMark"),
        (vec!["Lyno/Jean", "L\u{00FF}no/Jean"], "err:PostScriptCollision"), (vec!["Marq/Alternate", "Marq/Standard"], "ok:set"),
    ];
    let cj = cases.iter().map(|(ls, r)| format!("{{\"labels_cps\":[{}],\"expect\":\"{}\"}}",
        ls.iter().map(|l| format!("[{}]", l.chars().map(|c| (c as u32).to_string()).collect::<Vec<_>>().join(","))).collect::<Vec<_>>().join(","), r)).collect::<Vec<_>>().join(",\n");
    let out = format!("{{\"version\":1,\"rule\":\"label=<family>/<style>; result per label '{{prefix}}{{c}}/S'; ok:<ps> or err:<Kind>\",\n\"cases\":[\n{}\n],\n\"corpus_alone\":[\n{}\n],\n\"corpus_after_letter_a\":[\n{}\n]}}\n", cj, dump(probe("")), dump(probe("a")));
    std::fs::write(&path, out).expect("write output");
}
