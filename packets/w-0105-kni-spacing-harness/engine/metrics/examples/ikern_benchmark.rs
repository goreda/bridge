//! Isolated benchmark adapter. Reads outline geometry, never reference metrics.
//! Protocol: UPM<TAB>n; G<TAB>name<TAB>codepoint; R<TAB>x,y ...; E.
//! Output: G name lsb rsb advance; K left right value; S receipt key value.
use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy};
use kni_metrics::self_anchored_spacing::{solve_spacing_jobs, FontContext, SpacingPolicy};
use kni_metrics::generated_outline_kern::{generate_residual_kern, ExportGeometry, ProfileFrame};
use std::{env, fs, io::{self, Write}};
fn run() -> Result<(), String> {
    let started = std::time::Instant::now();
    let args: Vec<String> = env::args().collect();
    if args.len() < 6 { return Err("usage: ikern_benchmark outlines.tsv lambda dcap|auto row_step jobs".into()); }
    let lambda: f64 = args[2].parse().map_err(|_| "bad lambda")?;
    let dcap = if args[3] == "auto" { None } else { Some(args[3].parse::<f64>().map_err(|_| "bad dcap")?) };
    let step: f64 = args[4].parse().map_err(|_| "bad row_step")?;
    let jobs: usize = args[5].parse().map_err(|_| "bad jobs")?;
    if !lambda.is_finite() || lambda < 0. || !step.is_finite() || step <= 0. || jobs == 0
        || dcap.is_some_and(|v| !v.is_finite() || v <= 0.) { return Err("invalid policy".into()); }
    let data = fs::read_to_string(&args[1]).map_err(|e| e.to_string())?;
    let mut lines = data.lines();
    let upm: u16 = lines.next().and_then(|s| s.strip_prefix("UPM\t")).ok_or("missing UPM")?.parse().map_err(|_| "bad UPM")?;
    let mut current: Option<OutlineInput> = None;
    let mut profiles = Vec::new();
    let mut ctx = FontContext::default();
    let scan = ScanPolicy { row_step: step, grid_anchor_y: Some(0.), ..ScanPolicy::default() };
    for line in lines {
        let cells: Vec<&str> = line.split('\t').collect();
        match cells[0] {
            "G" if cells.len() == 3 && current.is_none() => {
                let cp = cells[2].parse::<u32>().map_err(|_| "bad codepoint")?;
                ctx.glyph_codepoints.push((cells[1].into(), cp));
                current = Some(OutlineInput { glyph_id: cells[1].into(), source_pin: "benchmark-stripped-outline".into(), upm, origin: [0.,0.], flatten_tolerance: 0., rings: Vec::new() });
            }
            "R" if current.is_some() => {
                let ring: Result<Vec<[f64;2]>,String> = cells[1..].iter().map(|cell| {
                    let (x,y) = cell.split_once(',').ok_or("bad point")?;
                    Ok([x.parse().map_err(|_| "bad x")?, y.parse().map_err(|_| "bad y")?])
                }).collect();
                current.as_mut().unwrap().rings.push(ring?);
            }
            "E" if cells.len() == 1 => {
                let input = current.take().ok_or("E without G")?;
                profiles.push(profile_outline(&input, scan).map_err(|e| format!("profile {}: {e:?}",input.glyph_id))?);
            }
            _ => return Err(format!("invalid protocol row: {line}")),
        }
    }
    if current.is_some() || profiles.is_empty() { return Err("incomplete/empty geometry".into()); }
    let n = profiles.len();
    let policy = SpacingPolicy { lambda: Some(lambda), dcap, sample_resolution: step, max_pairs: n*n, max_pair_evaluations: (n*n) as u64, ..SpacingPolicy::default() };
    eprintln!("IKERN-PROGRESS profiles={} elapsed_ms={}", profiles.len(), started.elapsed().as_millis());
    let value = |flag:&str| args.iter().position(|v|v==flag).and_then(|i|args.get(i+1));
    let solution = if let Some(path)=value("--context-cache") {
        use kni_metrics::self_anchored_spacing::{solve_spacing_checkpoint,PairCheckpoint,PairCheckpointAction};
        let mode=value("--pair-range").ok_or("--context-cache requires --pair-range prepare|merge|start:end")?;
        let action=match mode.as_str() {
            "prepare"=>PairCheckpointAction::Prepare,"merge"=>PairCheckpointAction::Merge,
            _=>{let (a,b)=mode.split_once(':').ok_or("bad pair range")?;PairCheckpointAction::Range{start:a.parse().map_err(|_|"bad range start")?,end:b.parse().map_err(|_|"bad range end")?}}
        };
        match solve_spacing_checkpoint(&profiles,Some(&ctx),&policy,jobs,&PairCheckpoint{directory:path.into(),action}).map_err(|e|format!("checkpoint: {e:?}"))? {
            Some(solution)=>solution,None=>{eprintln!("IKERN-PROGRESS checkpoint complete elapsed_ms={}",started.elapsed().as_millis());return Ok(());}
        }
    } else { solve_spacing_jobs(&profiles, Some(&ctx), &policy, jobs).map_err(|e| format!("spacing: {e:?}"))? };
    eprintln!("IKERN-PROGRESS solved_pairs={} elapsed_ms={}", solution.pairs.len(), started.elapsed().as_millis());
    let geo = ExportGeometry { profile_frame: ProfileFrame::ExportedB, upm, overlap_tolerance_units: 0., drop_zero_residual: false, row_align_tolerance_units: step };
    let kern = generate_residual_kern(&solution, &profiles, &geo);
    eprintln!("IKERN-PROGRESS exported_ready={} elapsed_ms={}", kern.ready.len(), started.elapsed().as_millis());
    let mut out = io::BufWriter::new(io::stdout().lock());
    for g in &solution.glyphs { writeln!(out,"G\t{}\t{}\t{}\t{}",g.glyph_id,g.lsb,g.rsb,g.advance).map_err(|e|e.to_string())?; }
    for p in &kern.ready { writeln!(out,"K\t{}\t{}\t{}",p.left,p.right,p.export_value).map_err(|e|e.to_string())?; }
    for (key,value) in [("ready",kern.ready.len()),("fallback_ready_not_exported",kern.fallback_ready.len()),("held",kern.overlap_holds.len()),("rejected",kern.rejected.len()),("excluded",solution.excluded_pairs.len()),("complete",usize::from(solution.complete))] {
        writeln!(out,"S\t{key}\t{value}").map_err(|e|e.to_string())?;
    }
    out.flush().map_err(|e|e.to_string())?;
    Ok(())
}
fn main() { if let Err(e)=run() { eprintln!("IKERN-BENCHMARK-REFUSED: {e}"); std::process::exit(2); } }

