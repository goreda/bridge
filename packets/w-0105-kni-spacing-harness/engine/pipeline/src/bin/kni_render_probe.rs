//! kni_render_probe: read-only render probe for solved spacing and kern output.
//!
//! Lambda dialogue work items 4 and 10 (docs/kni/2026-10-17-lambda-dialogue-derived-work-items.md):
//! render the solved spacing of a shipped OTF at several pixel sizes with two
//! independent rasterizers (item 4) and judge kerning quality on real typeset
//! paragraph texture instead of isolated pairs (item 10). The tool reads a
//! shipped OTF (CFF outlines via kni_core::cff_reader, hmtx and GPOS PairPos
//! format 1 via its own bounded parsers), lays text out with the font's own
//! advances and kern pairs, rasterizes, and emits PNG renders plus a typed
//! TSV ledger of measured values only. Nothing here mutates the font or any
//! production path; every skipped structure is a typed ledger row.
//!
//! Every constant below is either an OpenType binary-format constant or a
//! DECLARED_CONVENTION with provenance in docs/kni/2026-10-18-render-probe.md.

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_core::reference_slice::{Point, ReferenceRing, Span};
use kni_metrics::otf_self_parse;

/// DECLARED_CONVENTION (docs/kni/2026-10-18-render-probe.md): empty pixel
/// margin around every render canvas so edge ink never clips the ledger bbox.
const RENDER_PAD_PX: f64 = 2.0;
/// DECLARED_CONVENTION (same doc): subpixels per pixel axis when --supersample
/// is not passed.
const DEFAULT_SUPERSAMPLE: u32 = 4;
/// DECLARED_CONVENTION (same doc): cubic flattening chord deviation budget in
/// output pixels; at or below one quarter pixel the polyline is visually
/// identical to the curve at the probed resolutions.
const FLATTEN_TOLERANCE_PX: f64 = 0.25;
/// DECLARED_CONVENTION (same doc): flattening recursion cap; a cubic split
/// depth of 16 bounds the segment count at 2^16 per span, far past any
/// glyph contour seen in the collection.
const FLATTEN_MAX_DEPTH: u32 = 16;
/// DECLARED_CONVENTION (same doc): a texture pair is reported as an outlier
/// when its normalized mean gap deviates from the median normalized gap by
/// at least this factor; adjustable with --outlier-factor.
const DEFAULT_OUTLIER_FACTOR: f64 = 1.5;
/// DECLARED_CONVENTION (same doc): count of highest/lowest-coverage lines and
/// most frequent texture pairs listed in the summary report.
const SUMMARY_TOP_N: usize = 10;
/// OpenType format constant: maximum line-wrapped width of a zlib stored
/// block payload (deflate, RFC 1951).
const DEFLATE_STORED_MAX: usize = 65535;

#[derive(Debug)]
enum ProbeError {
    Io(std::io::Error),
    Integrity(String),
    Cff(String),
    Table(&'static str),
    Args(String),
}
impl std::fmt::Display for ProbeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(e) => write!(f, "io: {e}"),
            Self::Integrity(s) => write!(f, "otf integrity: {s}"),
            Self::Cff(s) => write!(f, "cff read: {s}"),
            Self::Table(t) => write!(f, "table: {t}"),
            Self::Args(s) => write!(f, "args: {s}"),
        }
    }
}
impl From<std::io::Error> for ProbeError {
    fn from(e: std::io::Error) -> Self { Self::Io(e) }
}
type ProbeResult<T> = Result<T, ProbeError>;

fn be_u16(b: &[u8], at: usize) -> ProbeResult<u16> {
    b.get(at..at + 2).map(|s| u16::from_be_bytes([s[0], s[1]])).ok_or(ProbeError::Table("truncated u16"))
}
fn be_i16(b: &[u8], at: usize) -> ProbeResult<i16> {
    Ok(be_u16(b, at)? as i16)
}
fn be_u32(b: &[u8], at: usize) -> ProbeResult<u32> {
    b.get(at..at + 4).map(|s| u32::from_be_bytes([s[0], s[1], s[2], s[3]])).ok_or(ProbeError::Table("truncated u32"))
}

#[derive(Default, Debug)]
struct Args {
    mode: String,
    font: Option<PathBuf>,
    text: Option<String>,
    text_file: Option<PathBuf>,
    sizes: Vec<f64>,
    size: Option<f64>,
    line_width: Option<f64>,
    line_pitch: Option<f64>,
    supersample: u32,
    outlier_factor: f64,
    out: Option<PathBuf>,
}

fn parse_args(argv: &[String]) -> ProbeResult<Args> {
    let mut a = Args { supersample: DEFAULT_SUPERSAMPLE, outlier_factor: DEFAULT_OUTLIER_FACTOR, ..Default::default() };
    let mut it = argv.iter().skip(1);
    a.mode = it.next().cloned().unwrap_or_default();
    while let Some(flag) = it.next() {
        let value = it.next().ok_or_else(|| ProbeError::Args(format!("{flag} needs a value")))?;
        match flag.as_str() {
            "--font" => a.font = Some(PathBuf::from(value)),
            "--text" => a.text = Some(value.clone()),
            "--text-file" => a.text_file = Some(PathBuf::from(value)),
            "--sizes" => {
                a.sizes = value.split(',').map(|s| s.trim().parse::<f64>().map_err(|_| ProbeError::Args(format!("bad size {s}")))).collect::<Result<Vec<_>, _>>()?;
            }
            "--size" => a.size = Some(value.parse().map_err(|_| ProbeError::Args("bad --size".into()))?),
            "--line-width" => a.line_width = Some(value.parse().map_err(|_| ProbeError::Args("bad --line-width".into()))?),
            "--line-pitch" => a.line_pitch = Some(value.parse().map_err(|_| ProbeError::Args("bad --line-pitch".into()))?),
            "--supersample" => a.supersample = value.parse().map_err(|_| ProbeError::Args("bad --supersample".into()))?,
            "--outlier-factor" => a.outlier_factor = value.parse().map_err(|_| ProbeError::Args("bad --outlier-factor".into()))?,
            "--out" => a.out = Some(PathBuf::from(value)),
            other => return Err(ProbeError::Args(format!("unknown flag {other}"))),
        }
    }
    Ok(a)
}

fn usage() -> String {
    "kni_render_probe line --font F.otf (--text T | --text-file P) --sizes 8,10,12 --out DIR [--supersample N]\n\
     kni_render_probe paragraph --font F.otf --text-file P --size PX --line-width PX --out DIR [--line-pitch PX] [--supersample N] [--outlier-factor F]".to_string()
}

fn main() {
    let argv: Vec<String> = std::env::args().collect();
    match run(&argv) {
        Ok(()) => {}
        Err(e) => { eprintln!("kni_render_probe: {e}\n{}", usage()); std::process::exit(2); }
    }
}

fn run(argv: &[String]) -> ProbeResult<()> {
    let args = parse_args(argv)?;
    let font_path = args.font.clone().ok_or_else(|| ProbeError::Args("--font required".into()))?;
    let out_dir = args.out.clone().ok_or_else(|| ProbeError::Args("--out required".into()))?;
    std::fs::create_dir_all(&out_dir)?;
    let font = LoadedFont::load(&font_path)?;
    let text = match (&args.text, &args.text_file) {
        (Some(t), None) => t.clone(),
        (None, Some(p)) => std::fs::read_to_string(p)?,
        _ => return Err(ProbeError::Args("exactly one of --text / --text-file".into())),
    };
    let mut ledger = Ledger::default();
    ledger.row("run_header", &[
        ("font", font_path.display().to_string()),
        ("font_sha256", font.sha256.clone()),
        ("units_per_em", font.upm.to_string()),
        ("glyph_count", font.glyph_count.to_string()),
        ("kern_pairs", font.kerns.len().to_string()),
        ("kern_class_rows", font.class_kerns.len().to_string()),
        ("mode", args.mode.clone()),
    ]);
    match args.mode.as_str() {
        "line" => {
            if args.sizes.is_empty() { return Err(ProbeError::Args("--sizes required".into())); }
            line_mode(&font, &text, &args, &out_dir, &mut ledger)?;
        }
        "paragraph" => {
            paragraph_mode(&font, &text, &args, &out_dir, &mut ledger)?;
        }
        other => return Err(ProbeError::Args(format!("unknown mode {other}"))),
    }
    let ledger_path = out_dir.join("ledger.tsv");
    std::fs::write(&ledger_path, ledger.render())?;
    let summary = out_dir.join("report.md");
    std::fs::write(&summary, ledger.summary(&font))?;
    println!("ledger: {}", ledger_path.display());
    println!("report: {}", summary.display());
    Ok(())
}

// ---------------------------------------------------------------- ledger

#[derive(Default)]
struct Ledger {
    rows: Vec<String>,
    pair_gaps: Vec<PairGapRow>,
    raster_diffs: Vec<RasterDiffRow>,
    texture_lines: Vec<TextureLineRow>,
    texture_pairs: Vec<TexturePairRow>,
}
#[derive(Clone, Debug)]
struct PairGapRow { size: f64, rasterizer: &'static str, left: String, right: String, gap_px: f64, gap_em: f64 }
#[derive(Clone, Debug)]
struct RasterDiffRow { size: f64, iou: f64, xor_px: u64, cover_a: f64, cover_b: f64, bbox_w_a: u64, bbox_w_b: u64 }
#[derive(Clone, Debug)]
struct TextureLineRow { index: usize, coverage: f64, gap_count: usize, gap_mean: f64, gap_stdev: f64, gap_min: f64, gap_max: f64, spaces: usize, space_mean: f64 }
#[derive(Clone, Debug)]
struct TexturePairRow { left: String, right: String, count: usize, mean_gap_em: f64, min_gap_em: f64, max_gap_em: f64 }

impl Ledger {
    fn row(&mut self, kind: &str, fields: &[(&str, String)]) {
        let mut line = String::from(kind);
        for (k, v) in fields {
            let _ = write!(line, "\t{k}={}", v.replace('\t', " ").replace('\n', " "));
        }
        self.rows.push(line);
    }
    fn render(&self) -> String {
        let mut out = String::from("# kni_render_probe typed ledger v1\n");
        for r in &self.rows { out.push_str(r); out.push('\n'); }
        out
    }
    fn summary(&self, font: &LoadedFont) -> String {
        let mut s = String::new();
        let _ = writeln!(s, "# kni_render_probe report\n");
        let _ = writeln!(s, "- font_sha256: {}", font.sha256);
        let _ = writeln!(s, "- units_per_em: {}", font.upm);
        let _ = writeln!(s, "- kern pairs applied from GPOS: {}", font.kerns.len());
        if !self.raster_diffs.is_empty() {
            let _ = writeln!(s, "\n## Rasterizer agreement (scanline vs evenodd, per size)");
            let _ = writeln!(s, "size_px\tiou\txor_px\tcover_scanline\tcover_evenodd\tbbox_w_scanline\tbbox_w_evenodd");
            for d in &self.raster_diffs {
                let _ = writeln!(s, "{}\t{:.6}\t{}\t{:.6}\t{:.6}\t{}\t{}", d.size, d.iou, d.xor_px, d.cover_a, d.cover_b, d.bbox_w_a, d.bbox_w_b);
            }
        }
        if !self.pair_gaps.is_empty() {
            let _ = writeln!(s, "\n## Pair gap spread across sizes (normalized em gap, scanline)");
            let mut by_pair: BTreeMap<(String, String), Vec<f64>> = BTreeMap::new();
            for g in self.pair_gaps.iter().filter(|g| g.rasterizer == "scanline") {
                by_pair.entry((g.left.clone(), g.right.clone())).or_default().push(g.gap_em);
            }
            let _ = writeln!(s, "pair\tmin_em\tmax_em\tspread_em\tmin_px\tmax_px\tsizes");
            for ((l, r), mut v) in by_pair {
                v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                let (lo, hi) = (v[0], v[v.len() - 1]);
                let rows: Vec<&PairGapRow> = self.pair_gaps.iter().filter(|g| g.rasterizer == "scanline" && g.left == l && g.right == r).collect();
                let min_px = rows.iter().map(|g| g.gap_px).fold(f64::INFINITY, f64::min);
                let max_px = rows.iter().map(|g| g.gap_px).fold(f64::NEG_INFINITY, f64::max);
                let sizes: Vec<String> = rows.iter().map(|g| g.size.to_string()).collect();
                let _ = writeln!(s, "{}{}\t{:.5}\t{:.5}\t{:.5}\t{min_px:.3}\t{max_px:.3}\t{}", l, r, lo, hi, hi - lo, sizes.join(","));
            }
        }
        if !self.texture_lines.is_empty() {
            let _ = writeln!(s, "\n## Paragraph texture (per line)");
            let _ = writeln!(s, "line\tcoverage\tgaps\tgap_mean_px\tgap_stdev\tgap_min\tgap_max\tspaces\tspace_mean_px");
            for t in &self.texture_lines {
                let _ = writeln!(s, "{}\t{:.6}\t{}\t{:.3}\t{:.3}\t{:.3}\t{:.3}\t{}\t{:.3}", t.index, t.coverage, t.gap_count, t.gap_mean, t.gap_stdev, t.gap_min, t.gap_max, t.spaces, t.space_mean);
            }
        }
        if !self.texture_pairs.is_empty() {
            let _ = writeln!(s, "\n## Most frequent texture pairs");
            let _ = writeln!(s, "pair\tcount\tmean_gap_em\tmin_em\tmax_em");
            let mut tp = self.texture_pairs.clone();
            tp.sort_by(|a, b| b.count.cmp(&a.count));
            for t in tp.iter().take(SUMMARY_TOP_N) {
                let _ = writeln!(s, "{}{}\t{}\t{:.5}\t{:.5}\t{:.5}", t.left, t.right, t.count, t.mean_gap_em, t.min_gap_em, t.max_gap_em);
            }
        }
        s
    }
}

// ---------------------------------------------------------------- png (grayscale 8-bit, zlib stored blocks)

fn crc32(data: &[u8]) -> u32 {
    let mut table = [0u32; 256];
    for (i, e) in table.iter_mut().enumerate() {
        let mut c = i as u32;
        for _ in 0..8 { c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 }; }
        *e = c;
    }
    let mut c = 0xFFFF_FFFFu32;
    for &b in data { c = table[((c ^ b as u32) & 0xFF) as usize] ^ (c >> 8); }
    c ^ 0xFFFF_FFFF
}
fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for &x in data { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
    (b << 16) | a
}
fn png_chunk(out: &mut Vec<u8>, tag: &[u8; 4], payload: &[u8]) {
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(tag);
    out.extend_from_slice(payload);
    let mut crc_in = Vec::with_capacity(4 + payload.len());
    crc_in.extend_from_slice(tag);
    crc_in.extend_from_slice(payload);
    out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
}
fn write_png(path: &Path, w: usize, h: usize, gray: &[u8]) -> ProbeResult<()> {
    let mut raw = Vec::with_capacity((w + 1) * h);
    for y in 0..h {
        raw.push(0);
        raw.extend_from_slice(&gray[y * w..(y + 1) * w]);
    }
    let mut z = Vec::with_capacity(raw.len() + 16);
    z.extend_from_slice(&[0x78, 0x01]);
    let mut at = 0;
    while at < raw.len() {
        let n = (raw.len() - at).min(DEFLATE_STORED_MAX);
        let last = at + n == raw.len();
        z.push(if last { 1 } else { 0 });
        z.extend_from_slice(&(n as u16).to_le_bytes());
        z.extend_from_slice(&(!(n as u16)).to_le_bytes());
        z.extend_from_slice(&raw[at..at + n]);
        at += n;
    }
    z.extend_from_slice(&adler32(&raw).to_be_bytes());
    let mut png = Vec::new();
    png.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);
    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&(w as u32).to_be_bytes());
    ihdr.extend_from_slice(&(h as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
    png_chunk(&mut png, b"IHDR", &ihdr);
    png_chunk(&mut png, b"IDAT", &z);
    png_chunk(&mut png, b"IEND", &[]);
    std::fs::write(path, png)?;
    Ok(())
}

// ---------------------------------------------------------------- font loading

struct LoadedFont {
    sha256: String,
    upm: f64,
    glyph_count: usize,
    reader: CffReader,
    advances: Vec<u16>,
    kerns: BTreeMap<(u16, u16), i16>,
    class_kerns: Vec<(u16, u16, i16, Vec<u16>, Vec<u16>)>,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    gid_names: BTreeMap<u16, String>,
}

impl LoadedFont {
    fn load(path: &Path) -> ProbeResult<Self> {
        let bytes = std::fs::read(path)?;
        let sha = sha256_hex(&bytes);
        let report = otf_self_parse::verify(&bytes).map_err(|fs| {
            ProbeError::Integrity(fs.iter().map(|f| format!("{}: {}", f.code, f.detail)).collect::<Vec<_>>().join("; "))
        })?;
        let table = |tag: &[u8; 4]| -> Option<&[u8]> {
            report.tables.iter().find(|t| &t.tag == tag).map(|t| &bytes[t.offset as usize..(t.offset + t.length) as usize])
        };
        let reader = CffReader::from_bytes(&bytes, &sha).map_err(|e| ProbeError::Cff(format!("{e:?}")))?;
        let upm = f64::from(reader.units_per_em());
        let hhea = table(b"hhea").ok_or(ProbeError::Table("missing hhea"))?;
        let ascender = be_i16(hhea, 4)?;
        let descender = be_i16(hhea, 6)?;
        let line_gap = be_i16(hhea, 8)?;
        let metric_count = be_u16(hhea, 34)? as usize;
        let maxp = table(b"maxp").ok_or(ProbeError::Table("missing maxp"))?;
        let num_glyphs = be_u16(maxp, 4)? as usize;
        let hmtx = table(b"hmtx").ok_or(ProbeError::Table("missing hmtx"))?;
        if metric_count == 0 || metric_count > num_glyphs { return Err(ProbeError::Table("bad numberOfHMetrics")); }
        if hmtx.len() < 4 * metric_count { return Err(ProbeError::Table("truncated hmtx")); }
        let last = be_u16(hmtx, 4 * (metric_count - 1))?;
        let mut advances = Vec::with_capacity(num_glyphs);
        for i in 0..num_glyphs {
            advances.push(if i < metric_count { be_u16(hmtx, 4 * i)? } else { last });
        }
        let (kerns, class_kerns) = match table(b"GPOS") {
            Some(gpos) => parse_gpos(gpos)?,
            None => (BTreeMap::new(), Vec::new()),
        };
        let mut gid_names: BTreeMap<u16, String> = BTreeMap::new();
        for (cp, gid) in reader.codepoints() {
            let label = char::from_u32(cp).filter(|c| !c.is_control()).map(|c| c.to_string()).unwrap_or_else(|| format!("U+{cp:04X}"));
            gid_names.insert(gid, label);
        }
        Ok(LoadedFont { sha256: sha, upm, glyph_count: num_glyphs, reader, advances, kerns, class_kerns, ascender, descender, line_gap, gid_names })
    }
    fn gid_of(&self, c: char) -> Option<u16> { self.reader.glyph_for_codepoint(c as u32) }
    fn advance(&self, gid: u16) -> f64 { f64::from(self.advances.get(gid as usize).copied().unwrap_or(0)) }
    fn kern(&self, left: u16, right: u16) -> f64 {
        if let Some(v) = self.kerns.get(&(left, right)) { return f64::from(*v); }
        for &(_c1, _c2, v, ref lefts, ref rights) in &self.class_kerns {
            if v != 0 && lefts.contains(&left) && rights.contains(&right) { return f64::from(v); }
        }
        0.0
    }
    fn name(&self, gid: u16) -> String { self.gid_names.get(&gid).cloned().unwrap_or_else(|| format!("gid{gid}")) }
}

/// Parse a GPOS table: collect every type-2 (PairPos) subtable. Format 1
/// pairs land in the pair map; format 2 class pairs land as expanded
/// (class value, left-member gids, right-member gids) rows so layout can
/// resolve them without inventing per-glyph pairs. OpenType binary-format
/// offsets only. Anything else is skipped and counted in the skip tally the
/// caller turns into typed ledger rows.
fn parse_gpos(gpos: &[u8]) -> ProbeResult<(BTreeMap<(u16, u16), i16>, Vec<(u16, u16, i16, Vec<u16>, Vec<u16>)>)> {
    let (map, class_rows, skips) = parse_gpos_inner(gpos)?;
    for s in skips { eprintln!("kni_render_probe: gpos note: {s}"); }
    Ok((map, class_rows))
}

fn parse_gpos_inner(gpos: &[u8]) -> ProbeResult<(BTreeMap<(u16, u16), i16>, Vec<(u16, u16, i16, Vec<u16>, Vec<u16>)>, Vec<String>)> {
    if be_u32(gpos, 0)? >> 16 != 1 { return Err(ProbeError::Table("GPOS major version not 1")); }
    let lookup_list_at = be_u16(gpos, 8)? as usize;
    let mut out: BTreeMap<(u16, u16), i16> = BTreeMap::new();
    let mut class_rows: Vec<(u16, u16, i16, Vec<u16>, Vec<u16>)> = Vec::new();
    let mut skips = Vec::new();
    let lookup_count = be_u16(gpos, lookup_list_at)? as usize;
    for li in 0..lookup_count {
        let lookup_at = lookup_list_at + be_u16(gpos, lookup_list_at + 2 + 2 * li)? as usize;
        let lookup_type = be_u16(gpos, lookup_at)?;
        if lookup_type != 2 {
            skips.push(format!("lookup {li} type {lookup_type} (not PairPos)"));
            continue;
        }
        let sub_count = be_u16(gpos, lookup_at + 4)? as usize;
        for si in 0..sub_count {
            let sub_at = lookup_at + be_u16(gpos, lookup_at + 6 + 2 * si)? as usize;
            let pos_format = be_u16(gpos, sub_at)?;
            let cov_at = sub_at + be_u16(gpos, sub_at + 2)? as usize;
            let vf1 = be_u16(gpos, sub_at + 4)?;
            let vf2 = be_u16(gpos, sub_at + 6)?;
            match pos_format {
                1 => {
                    let set_count = be_u16(gpos, sub_at + 8)? as usize;
                    let coverage = coverage_glyphs(gpos, cov_at)?;
                    if coverage.len() != set_count {
                        skips.push(format!("lookup {li} subtable {si} coverage/set count mismatch"));
                        continue;
                    }
                    let rec_len1 = value_record_len(vf1);
                    let rec_len2 = value_record_len(vf2);
                    for (set_i, &left) in coverage.iter().enumerate() {
                        let set_at = sub_at + be_u16(gpos, sub_at + 10 + 2 * set_i)? as usize;
                        let pair_count = be_u16(gpos, set_at)? as usize;
                        let mut rec = set_at + 2;
                        for _ in 0..pair_count {
                            let right = be_u16(gpos, rec)?;
                            rec += 2;
                            let mut x_adv: i16 = 0;
                            if vf1 & 0x4 != 0 {
                                let off = rec + value_field_offset(vf1, 0x4);
                                x_adv = be_i16(gpos, off)?;
                            }
                            rec += rec_len1 + rec_len2;
                            match out.entry((left, right)) {
                                std::collections::btree_map::Entry::Vacant(v) => { v.insert(x_adv); }
                                std::collections::btree_map::Entry::Occupied(o) => {
                                    if *o.get() != x_adv {
                                        skips.push(format!("conflicting pair ({left},{right}) {} vs {x_adv}; kept first", o.get()));
                                    }
                                }
                            }
                        }
                    }
                }
                2 => {
                    let cd1_at = sub_at + be_u16(gpos, sub_at + 8)? as usize;
                    let cd2_at = sub_at + be_u16(gpos, sub_at + 10)? as usize;
                    let c1_count = be_u16(gpos, sub_at + 12)? as usize;
                    let c2_count = be_u16(gpos, sub_at + 14)? as usize;
                    let class1 = class_def(gpos, cd1_at)?;
                    let class2 = class_def(gpos, cd2_at)?;
                    let coverage = coverage_glyphs(gpos, cov_at)?;
                    let rec_len = value_record_len(vf1) + value_record_len(vf2);
                    let mut rec = sub_at + 16;
                    for c1 in 0..c1_count {
                        for c2 in 0..c2_count {
                            let mut x_adv: i16 = 0;
                            if vf1 & 0x4 != 0 {
                                x_adv = be_i16(gpos, rec + value_field_offset(vf1, 0x4))?;
                            }
                            rec += rec_len;
                            if x_adv != 0 {
                                let lefts: Vec<u16> = coverage.iter().copied().filter(|g| class1.get(g).copied().unwrap_or(0) == c1 as u16).collect();
                                let rights: Vec<u16> = (0..=u16::MAX).filter(|g| class2.get(g).copied().unwrap_or(0) == c2 as u16).collect();
                                class_rows.push((c1 as u16, c2 as u16, x_adv, lefts, rights));
                            }
                        }
                    }
                }
                other => skips.push(format!("lookup {li} subtable {si} posFormat {other} unsupported")),
            }
        }
    }
    Ok((out, class_rows, skips))
}

/// ClassDef table (formats 1 and 2), glyph id to class id. OpenType binary
/// format; glyphs absent from the table are class 0 per spec.
fn class_def(b: &[u8], at: usize) -> ProbeResult<BTreeMap<u16, u16>> {
    let mut out = BTreeMap::new();
    match be_u16(b, at)? {
        1 => {
            let start = be_u16(b, at + 2)?;
            let count = be_u16(b, at + 4)? as usize;
            for i in 0..count {
                out.insert(start + i as u16, be_u16(b, at + 6 + 2 * i)?);
            }
        }
        2 => {
            let count = be_u16(b, at + 2)? as usize;
            for i in 0..count {
                let first = be_u16(b, at + 4 + 6 * i)?;
                let last = be_u16(b, at + 6 + 6 * i)?;
                let class = be_u16(b, at + 8 + 6 * i)?;
                for g in first..=last { out.insert(g, class); }
            }
        }
        _ => return Err(ProbeError::Table("unknown classDef format")),
    }
    Ok(out)
}

/// ValueRecord byte length: one int16 per set bit among the four placement
/// bits used here; OpenType spec reserves higher bits we treat as absent.
fn value_record_len(format: u16) -> usize { 2 * (format & 0xF).count_ones() as usize }
/// Byte offset of the field selected by `bit` inside a ValueRecord.
fn value_field_offset(format: u16, bit: u16) -> usize {
    let mut off = 0;
    let mut b = 1u16;
    while b < bit { if format & b != 0 { off += 2; } b <<= 1; }
    off
}

fn coverage_glyphs(b: &[u8], at: usize) -> ProbeResult<Vec<u16>> {
    match be_u16(b, at)? {
        1 => {
            let n = be_u16(b, at + 2)? as usize;
            let mut v = Vec::with_capacity(n);
            for i in 0..n { v.push(be_u16(b, at + 4 + 2 * i)?); }
            Ok(v)
        }
        2 => {
            let n = be_u16(b, at + 2)? as usize;
            let mut v = Vec::new();
            for i in 0..n {
                let start = be_u16(b, at + 4 + 6 * i)?;
                let end = be_u16(b, at + 6 + 6 * i)?;
                for g in start..=end { v.push(g); }
            }
            Ok(v)
        }
        other => Err(ProbeError::Table(match other { 3 => "coverage format 3 unsupported", _ => "unknown coverage format" })),
    }
}

// ---------------------------------------------------------------- outlines

/// Flatten one ring into a closed polyline in font units. Endpoints are the
/// exact span endpoints; cubics subdivide until the control-point deviation
/// from the chord fits FLATTEN_TOLERANCE_PX at the current scale.
fn flatten_ring(ring: &ReferenceRing, scale: f64) -> Vec<Point> {
    let tol_units = FLATTEN_TOLERANCE_PX / scale.max(f64::EPSILON);
    let mut out = vec![ring.start];
    let mut pen = ring.start;
    for span in &ring.spans {
        match *span {
            Span::Line { end } => { out.push(end); pen = end; }
            Span::Cubic { control_one, control_two, end } => {
                flatten_cubic(pen, control_one, control_two, end, tol_units, 0, &mut out);
                pen = end;
            }
        }
    }
    out
}

fn flatten_cubic(p0: Point, p1: Point, p2: Point, p3: Point, tol: f64, depth: u32, out: &mut Vec<Point>) {
    let dev = point_line_distance(p1, p0, p3).max(point_line_distance(p2, p0, p3));
    if dev <= tol || depth >= FLATTEN_MAX_DEPTH {
        out.push(p3);
        return;
    }
    let mid = |a: Point, b: Point| Point { x: 0.5 * (a.x + b.x), y: 0.5 * (a.y + b.y) };
    let a = mid(p0, p1);
    let b = mid(p1, p2);
    let c = mid(p2, p3);
    let d = mid(a, b);
    let e = mid(b, c);
    let t = mid(d, e);
    flatten_cubic(p0, a, d, t, tol, depth + 1, out);
    flatten_cubic(t, e, c, p3, tol, depth + 1, out);
}

fn point_line_distance(p: Point, a: Point, b: Point) -> f64 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    let len = (dx * dx + dy * dy).sqrt();
    if len <= f64::EPSILON { return ((p.x - a.x).powi(2) + (p.y - a.y).powi(2)).sqrt(); }
    ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len
}

// ---------------------------------------------------------------- rasterizers

#[derive(Clone, Copy, PartialEq, Eq)]
enum Rasterizer { Scanline, EvenOdd }
impl Rasterizer {
    fn name(self) -> &'static str {
        match self { Self::Scanline => "scanline", Self::EvenOdd => "evenodd" }
    }
    const ALL: [Rasterizer; 2] = [Rasterizer::Scanline, Rasterizer::EvenOdd];
}

struct Canvas {
    w: usize,
    h: usize,
    px: Vec<u32>,
}

impl Canvas {
    fn new(w: usize, h: usize) -> Self { Self { w, h, px: vec![0; w * h] } }
    fn finish(&self, ss: u32) -> Vec<u8> {
        let denom = ss * ss;
        self.px.iter().map(|&c| ((c * 255 + denom / 2) / denom) as u8).collect()
    }
}

/// Rasterizer A: scanline nonzero-winding fill on a subpixel grid.
fn raster_scanline(polys: &[Vec<Point>], canvas: &mut Canvas, ss: u32, to_px: impl Fn(Point) -> (f64, f64)) {
    let flat: Vec<Vec<(f64, f64)>> = polys.iter().map(|p| p.iter().map(|&pt| to_px(pt)).collect()).collect();
    let sub_w = canvas.w * ss as usize;
    for py in 0..canvas.h {
        for sy in 0..ss {
            let y = py as f64 + (sy as f64 + 0.5) / ss as f64;
            let mut crossings: Vec<(f64, i32)> = Vec::new();
            for poly in &flat {
                for e in 0..poly.len() {
                    let (x0, y0) = poly[e];
                    let (x1, y1) = poly[(e + 1) % poly.len()];
                    if y0 <= y && y1 > y {
                        crossings.push((x0 + (y - y0) / (y1 - y0) * (x1 - x0), 1));
                    } else if y1 <= y && y0 > y {
                        crossings.push((x0 + (y - y0) / (y1 - y0) * (x1 - x0), -1));
                    }
                }
            }
            crossings.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
            let mut winding = 0i32;
            let mut edge_x = 0.0f64;
            for (cx, delta) in crossings {
                let was = winding;
                winding += delta;
                if was != 0 && winding == 0 || was == 0 && winding != 0 {
                    if was != 0 {
                        let xa = edge_x;
                        let xb = cx;
                        let mut sub = ((xa * ss as f64).floor() as i64).max(0);
                        let end = (xb * ss as f64).ceil() as i64;
                        while sub < end {
                            let ccx = (sub as f64 + 0.5) / ss as f64;
                            if ccx > xa && ccx < xb {
                                let px_i = (sub as usize).min(sub_w - 1) / ss as usize;
                                if px_i < canvas.w { canvas.px[py * canvas.w + px_i] += 1; }
                            }
                            sub += 1;
                        }
                    } else {
                        edge_x = cx;
                    }
                }
            }
        }
    }
}

/// Rasterizer B: per-subpixel even-odd point-in-polygon crossing test.
fn raster_evenodd(polys: &[Vec<Point>], canvas: &mut Canvas, ss: u32, to_px: impl Fn(Point) -> (f64, f64)) {
    let flat: Vec<Vec<(f64, f64)>> = polys.iter().map(|p| p.iter().map(|&pt| to_px(pt)).collect()).collect();
    for py in 0..canvas.h {
        for px_i in 0..canvas.w {
            for sy in 0..ss {
                let y = py as f64 + (sy as f64 + 0.5) / ss as f64;
                for sx in 0..ss {
                    let x = px_i as f64 + (sx as f64 + 0.5) / ss as f64;
                    let mut inside = false;
                    for poly in &flat {
                        let mut j = poly.len() - 1;
                        for i in 0..poly.len() {
                            let (xi, yi) = poly[i];
                            let (xj, yj) = poly[j];
                            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                                inside = !inside;
                            }
                            j = i;
                        }
                    }
                    if inside { canvas.px[py * canvas.w + px_i] += 1; }
                }
            }
        }
    }
}

fn rasterize(r: Rasterizer, polys: &[Vec<Point>], canvas: &mut Canvas, ss: u32, to_px: impl Fn(Point) -> (f64, f64) + Copy) {
    match r {
        Rasterizer::Scanline => raster_scanline(polys, canvas, ss, to_px),
        Rasterizer::EvenOdd => raster_evenodd(polys, canvas, ss, to_px),
    }
}

// ---------------------------------------------------------------- layout

#[derive(Clone, Debug)]
struct PlacedGlyph {
    gid: u16,
    label: String,
    x_units: f64,
    advance: f64,
    kern_after_prev: f64,
    is_space: bool,
}

fn layout_line(font: &LoadedFont, text: &str, ledger: &mut Ledger) -> Vec<PlacedGlyph> {
    let mut out: Vec<PlacedGlyph> = Vec::new();
    let mut pen = 0.0;
    let mut prev: Option<u16> = None;
    for c in text.chars() {
        if c == '\n' { break; }
        let gid = match font.gid_of(c) {
            Some(g) => g,
            None => {
                ledger.row("missing_glyph", &[("char", format!("U+{:04X}", c as u32))]);
                prev = None;
                continue;
            }
        };
        let kern = prev.map(|p| font.kern(p, gid)).unwrap_or(0.0);
        let advance = font.advance(gid);
        pen += kern;
        out.push(PlacedGlyph {
            gid,
            label: font.name(gid),
            x_units: pen,
            advance,
            kern_after_prev: kern,
            is_space: c == ' ',
        });
        pen += advance;
        prev = Some(gid);
    }
    out
}

struct RenderedLine {
    w: usize,
    h: usize,
    gray: Vec<u8>,
    ink_bbox: Option<(u64, u64, u64, u64)>,
    glyph_ink_spans: Vec<Option<(f64, f64)>>,
    canvas: Canvas,
}

fn render_line(font: &LoadedFont, placed: &[PlacedGlyph], size: f64, r: Rasterizer, ss: u32) -> ProbeResult<RenderedLine> {
    let scale = size / font.upm;
    let mut min_y = f64::INFINITY;
    let mut max_y = f64::NEG_INFINITY;
    let mut glyph_polys: Vec<Vec<Vec<Point>>> = Vec::new();
    for pg in placed {
        let rings = match font.reader.read_glyph(pg.gid) {
            Ok(g) => g.rings,
            Err(_) => Vec::new(),
        };
        let polys: Vec<Vec<Point>> = rings.iter().map(|ring| flatten_ring(ring, scale)).collect();
        for poly in &polys {
            for p in poly {
                min_y = min_y.min(p.y);
                max_y = max_y.max(p.y);
            }
        }
        glyph_polys.push(polys);
    }
    if !min_y.is_finite() { min_y = font.descender.into(); }
    if !max_y.is_finite() { max_y = font.ascender.into(); }
    let line_end = placed.last().map(|p| p.x_units + p.advance).unwrap_or(0.0);
    let origin_x = RENDER_PAD_PX;
    let origin_y = RENDER_PAD_PX - min_y * scale;
    let w = (line_end * scale + 2.0 * RENDER_PAD_PX).ceil().max(1.0) as usize;
    let h = ((max_y - min_y) * scale + 2.0 * RENDER_PAD_PX).ceil().max(1.0) as usize;
    let mut canvas = Canvas::new(w, h);
    let mut glyph_ink_spans = Vec::with_capacity(placed.len());
    for (i, pg) in placed.iter().enumerate() {
        let base_x = origin_x + pg.x_units * scale;
        let to_px = |p: Point| (base_x + p.x * scale, origin_y - p.y * scale);
        rasterize(r, &glyph_polys[i], &mut canvas, ss, to_px);
        let mut span: Option<(f64, f64)> = None;
        for poly in &glyph_polys[i] {
            for p in poly {
                let (px, _) = to_px(*p);
                span = Some(match span {
                    None => (px, px),
                    Some((a, b)) => (a.min(px), b.max(px)),
                });
            }
        }
        glyph_ink_spans.push(span);
    }
    let gray = canvas.finish(ss);
    let ink_bbox = ink_bbox_of(&gray, w, h);
    Ok(RenderedLine { w, h, gray, ink_bbox, glyph_ink_spans, canvas })
}

fn ink_bbox_of(gray: &[u8], w: usize, h: usize) -> Option<(u64, u64, u64, u64)> {
    let mut bb: Option<(u64, u64, u64, u64)> = None;
    for y in 0..h {
        for x in 0..w {
            if gray[y * w + x] > 0 {
                bb = Some(match bb {
                    None => (x as u64, y as u64, x as u64, y as u64),
                    Some((a, b, c, d)) => (a.min(x as u64), b.min(y as u64), c.max(x as u64), d.max(y as u64)),
                });
            }
        }
    }
    bb
}

// ---------------------------------------------------------------- line mode

fn line_mode(font: &LoadedFont, text: &str, args: &Args, out_dir: &Path, ledger: &mut Ledger) -> ProbeResult<()> {
    let placed = layout_line(font, text, ledger);
    ledger.row("line_layout", &[
        ("glyphs", placed.len().to_string()),
        ("advance_sum_units", placed.iter().map(|p| p.advance).sum::<f64>().to_string()),
        ("kern_sum_units", placed.iter().map(|p| p.kern_after_prev).sum::<f64>().to_string()),
        ("kern_pairs_applied", placed.iter().filter(|p| p.kern_after_prev != 0.0).count().to_string()),
    ]);
    for &size in &args.sizes {
        let scale = size / font.upm;
        let mut renders: Vec<(Rasterizer, RenderedLine)> = Vec::new();
        for r in Rasterizer::ALL {
            let rl = render_line(font, &placed, size, r, args.supersample)?;
            let ink = rl.gray.iter().filter(|&&v| v > 0).count() as f64;
            let cover = ink / (rl.w * rl.h) as f64;
            ledger.row("line_render", &[
                ("size_px", size.to_string()),
                ("rasterizer", r.name().to_string()),
                ("canvas_w", rl.w.to_string()),
                ("canvas_h", rl.h.to_string()),
                ("ink_px", ink.to_string()),
                ("coverage", format!("{cover:.6}")),
                ("expected_line_w_px", format!("{:.3}", placed.last().map(|p| (p.x_units + p.advance) * scale).unwrap_or(0.0))),
                ("ink_bbox_w", rl.ink_bbox.map(|b| (b.2 - b.0 + 1).to_string()).unwrap_or_else(|| "0".into())),
            ]);
            for (wi, w) in placed.windows(2).enumerate() {
                if w[0].is_space || w[1].is_space { continue; }
                if let (Some((_, ar)), Some((bl, _))) = (rl.glyph_ink_spans[wi], rl.glyph_ink_spans[wi + 1]) {
                    let g = bl - ar;
                    ledger.row("pair_gap", &[
                        ("size_px", size.to_string()),
                        ("rasterizer", r.name().to_string()),
                        ("pair", format!("{}{}", w[0].label, w[1].label)),
                        ("gap_px", format!("{g:.3}")),
                        ("gap_em", format!("{:.5}", g / size)),
                    ]);
                    ledger.pair_gaps.push(PairGapRow { size, rasterizer: r.name(), left: w[0].label.clone(), right: w[1].label.clone(), gap_px: g, gap_em: g / size });
                }
            }
            let png = out_dir.join(format!("line_{size}px_{}.png", r.name()));
            write_png(&png, rl.w, rl.h, &rl.gray)?;
            renders.push((r, rl));
        }
        let (a, b) = (&renders[0].1, &renders[1].1);
        if a.w == b.w && a.h == b.h {
            let (mut inter, mut union) = (0u64, 0u64);
            for i in 0..a.gray.len() {
                let (x, y) = (a.gray[i] > 0, b.gray[i] > 0);
                if x && y { inter += 1; }
                if x || y { union += 1; }
            }
            let xor = union - inter;
            let iou = if union == 0 { 1.0 } else { inter as f64 / union as f64 };
            let cov = |rl: &RenderedLine| rl.gray.iter().filter(|&&v| v > 0).count() as f64 / (rl.w * rl.h) as f64;
            let bw = |rl: &RenderedLine| rl.ink_bbox.map(|bb| bb.2 - bb.0 + 1).unwrap_or(0);
            ledger.raster_diffs.push(RasterDiffRow { size, iou, xor_px: xor, cover_a: cov(a), cover_b: cov(b), bbox_w_a: bw(a), bbox_w_b: bw(b) });
            ledger.row("raster_diff", &[
                ("size_px", size.to_string()),
                ("iou", format!("{iou:.6}")),
                ("xor_px", xor.to_string()),
            ]);
        } else {
            ledger.row("raster_diff", &[("size_px", size.to_string()), ("note", "canvas size mismatch; diff skipped".to_string())]);
        }
    }
    Ok(())
}

// ---------------------------------------------------------------- paragraph mode

fn paragraph_mode(font: &LoadedFont, text: &str, args: &Args, out_dir: &Path, ledger: &mut Ledger) -> ProbeResult<()> {
    let size = args.size.ok_or_else(|| ProbeError::Args("--size required".into()))?;
    let line_width = args.line_width.ok_or_else(|| ProbeError::Args("--line-width required".into()))?;
    let scale = size / font.upm;
    let pitch = match args.line_pitch {
        Some(p) => p,
        None => (f64::from(font.ascender) - f64::from(font.descender) + f64::from(font.line_gap)) * scale,
    };
    let limit_units = line_width / scale;
    let space_gid = font.gid_of(' ');
    let space_adv = space_gid.map(|g| font.advance(g)).unwrap_or(0.0);
    let mut lines: Vec<Vec<PlacedGlyph>> = Vec::new();
    let mut current: Vec<PlacedGlyph> = Vec::new();
    for raw in text.split('\n') {
        for word in raw.split(' ') {
            let word_placed = layout_line(font, word, ledger);
            if word_placed.is_empty() { continue; }
            let word_w: f64 = word_placed.iter().map(|p| p.advance).sum::<f64>() + word_placed.iter().map(|p| p.kern_after_prev).sum::<f64>();
            let cur_w: f64 = current.iter().map(|p| p.advance).sum::<f64>() + current.iter().map(|p| p.kern_after_prev).sum::<f64>();
            let need = if current.is_empty() { word_w } else { cur_w + space_adv + word_w };
            if !current.is_empty() && need > limit_units {
                lines.push(std::mem::take(&mut current));
            }
            if !current.is_empty() {
                if let Some(sg) = space_gid {
                    let kern = current.last().map(|p| font.kern(p.gid, sg)).unwrap_or(0.0);
                    let x: f64 = current.last().map(|p| p.x_units + p.advance).unwrap_or(0.0) + kern;
                    current.push(PlacedGlyph { gid: sg, label: " ".into(), x_units: x, advance: space_adv, kern_after_prev: kern, is_space: true });
                }
            }
            let base = current.last().map(|p| p.x_units + p.advance).unwrap_or(0.0);
            let kern_first = current.last().zip(word_placed.first()).map(|(a, b)| font.kern(a.gid, b.gid)).unwrap_or(0.0);
            for (i, mut pg) in word_placed.into_iter().enumerate() {
                let k = if i == 0 { kern_first } else { pg.kern_after_prev };
                pg.x_units += base + kern_first;
                pg.kern_after_prev = k;
                current.push(pg);
            }
        }
        if !current.is_empty() { lines.push(std::mem::take(&mut current)); }
    }
    let r = Rasterizer::Scanline;
    let mut page: Option<Canvas> = None;
    let mut page_h = 0usize;
    let page_w = (line_width + 2.0 * RENDER_PAD_PX).ceil() as usize;
    let mut pair_stats: BTreeMap<(String, String), Vec<f64>> = BTreeMap::new();
    for (li, placed) in lines.iter().enumerate() {
        let rl = render_line(font, placed, size, r, args.supersample)?;
        let y_off = (li as f64 * pitch).round() as usize;
        let need_h = y_off + rl.h;
        if page.is_none() { page = Some(Canvas::new(page_w, need_h)); page_h = need_h; }
        if need_h > page_h {
            let mut grown = Canvas::new(page_w, need_h);
            let old = page.take().unwrap_or_else(|| Canvas::new(page_w, 0));
            for y in 0..page_h {
                for x in 0..page_w { grown.px[y * page_w + x] = old.px[y * page_w + x]; }
            }
            page = Some(grown);
            page_h = need_h;
        }
        let page_ref = page.as_mut().expect("page canvas");
        for y in 0..rl.h {
            for x in 0..rl.w.min(page_w) {
                page_ref.px[(y_off + y) * page_w + x] = page_ref.px[(y_off + y) * page_w + x].max(rl.canvas.px[y * rl.w + x]);
            }
        }
        let ink = rl.gray.iter().filter(|&&v| v > 0).count() as f64;
        let coverage = ink / (rl.w * rl.h) as f64;
        let mut gaps: Vec<f64> = Vec::new();
        let mut space_gaps: Vec<f64> = Vec::new();
        for (wi, w) in placed.windows(2).enumerate() {
            let spans = (&rl.glyph_ink_spans[wi], &rl.glyph_ink_spans[wi + 1]);
            if w[1].is_space {
                space_gaps.push(w[1].advance * scale);
                continue;
            }
            if w[0].is_space { continue; }
            if let (Some((_, ar)), Some((bl, _))) = spans {
                gaps.push(bl - ar);
            }
            pair_stats.entry((w[0].label.clone(), w[1].label.clone())).or_default().push((bl_from(spans.1) - ar_from(spans.0)) / size);
        }
        let (mean, sd) = mean_stdev(&gaps);
        ledger.texture_lines.push(TextureLineRow {
            index: li,
            coverage,
            gap_count: gaps.len(),
            gap_mean: mean,
            gap_stdev: sd,
            gap_min: gaps.iter().cloned().fold(f64::INFINITY, f64::min),
            gap_max: gaps.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
            spaces: space_gaps.len(),
            space_mean: if space_gaps.is_empty() { 0.0 } else { space_gaps.iter().sum::<f64>() / space_gaps.len() as f64 },
        });
        ledger.row("texture_line", &[
            ("index", li.to_string()),
            ("coverage", format!("{coverage:.6}")),
            ("glyphs", placed.len().to_string()),
        ]);
    }
    let page = page.ok_or(ProbeError::Table("empty page"))?;
    let gray = page.finish(args.supersample);
    write_png(&out_dir.join(format!("paragraph_{size}px.png")), page_w, page_h, &gray)?;
    let med = median(&pair_stats.values().map(|v| v.iter().sum::<f64>() / v.len().max(1) as f64).collect::<Vec<_>>());
    for ((l, rr), v) in &pair_stats {
        let mean = v.iter().sum::<f64>() / v.len() as f64;
        let (mn, mx) = (v.iter().cloned().fold(f64::INFINITY, f64::min), v.iter().cloned().fold(f64::NEG_INFINITY, f64::max));
        ledger.texture_pairs.push(TexturePairRow { left: l.clone(), right: rr.clone(), count: v.len(), mean_gap_em: mean, min_gap_em: mn, max_gap_em: mx });
        let dev = if med > f64::EPSILON { (mean - med).abs() / med } else { 0.0 };
        if dev >= args.outlier_factor - 1.0 && *l != " " && *rr != " " {
            ledger.row("texture_pair_outlier", &[
                ("pair", format!("{l}{rr}")),
                ("count", v.len().to_string()),
                ("mean_gap_em", format!("{mean:.5}")),
                ("median_gap_em", format!("{med:.5}")),
                ("deviation", format!("{dev:.3}")),
            ]);
        }
    }
    ledger.row("paragraph", &[
        ("lines", lines.len().to_string()),
        ("size_px", size.to_string()),
        ("pitch_px", format!("{pitch:.3}")),
        ("distinct_pairs", pair_stats.len().to_string()),
    ]);
    Ok(())
}

fn bl_from(s: &Option<(f64, f64)>) -> f64 { s.map(|(a, _)| a).unwrap_or(0.0) }
fn ar_from(s: &Option<(f64, f64)>) -> f64 { s.map(|(_, b)| b).unwrap_or(0.0) }

fn mean_stdev(v: &[f64]) -> (f64, f64) {
    if v.is_empty() { return (0.0, 0.0); }
    let mean = v.iter().sum::<f64>() / v.len() as f64;
    let var = v.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / v.len() as f64;
    (mean, var.sqrt())
}
fn median(v: &[f64]) -> f64 {
    if v.is_empty() { return 0.0; }
    let mut s = v.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    s[s.len() / 2]
}

// ---------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;

    fn square_ring(x0: f64, y0: f64, x1: f64, y1: f64) -> ReferenceRing {
        let p = |x, y| Point { x, y };
        ReferenceRing {
            start: p(x0, y0),
            spans: vec![
                Span::Line { end: p(x1, y0) },
                Span::Line { end: p(x1, y1) },
                Span::Line { end: p(x0, y1) },
                Span::Line { end: p(x0, y0) },
            ],
        }
    }

    #[test]
    fn png_signature_and_chunks_roundtrip() {
        let dir = std::env::temp_dir().join("kni_render_probe_test_png");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.png");
        let gray = vec![128u8; 4 * 3];
        write_png(&path, 4, 3, &gray).unwrap();
        let bytes = std::fs::read(&path).unwrap();
        assert_eq!(&bytes[..8], &[137, 80, 78, 71, 13, 10, 26, 10]);
        let mut at = 8;
        let mut tags = Vec::new();
        while at < bytes.len() {
            let len = u32::from_be_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]) as usize;
            tags.push([bytes[at + 4], bytes[at + 5], bytes[at + 6], bytes[at + 7]]);
            at += 12 + len;
        }
        assert_eq!(tags.first(), Some(b"IHDR"));
        assert_eq!(tags.last(), Some(b"IEND"));
        assert_eq!(at, bytes.len());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn crc32_known_vector() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }

    #[test]
    fn adler32_known_vector() {
        assert_eq!(adler32(b"Wikipedia"), 0x11E6_0398);
    }

    #[test]
    fn gpos_roundtrip_writer_bytes() {
        let pairs = vec![
            kni_metrics::gpos_pairpos1::PairKern { left: 5, right: 7, x_advance: -80 },
            kni_metrics::gpos_pairpos1::PairKern { left: 5, right: 9, x_advance: -40 },
            kni_metrics::gpos_pairpos1::PairKern { left: 12, right: 1, x_advance: 25 },
        ];
        let gpos = kni_metrics::gpos_pairpos1::write_kern_pairpos1(500, &pairs).unwrap();
        let (map, _class_rows, skips) = parse_gpos_inner(&gpos).unwrap();
        assert!(skips.iter().all(|s| !s.starts_with("conflicting")), "{skips:?}");
        assert_eq!(map.get(&(5, 7)), Some(&-80));
        assert_eq!(map.get(&(5, 9)), Some(&-40));
        assert_eq!(map.get(&(12, 1)), Some(&25));
        assert_eq!(map.len(), 3);
    }

    #[test]
    fn flatten_line_ring_is_exact() {
        let ring = square_ring(0.0, 0.0, 100.0, 100.0);
        let poly = flatten_ring(&ring, 0.01);
        assert_eq!(poly.len(), 5);
        assert_eq!(poly[0].x, 0.0);
        assert_eq!(poly[4].x, 0.0);
        assert_eq!(poly[4].y, 0.0);
    }

    #[test]
    fn flatten_cubic_endpoints_exact() {
        let p = |x, y| Point { x, y };
        let ring = ReferenceRing {
            start: p(0.0, 0.0),
            spans: vec![Span::Cubic { control_one: p(0.0, 100.0), control_two: p(100.0, 100.0), end: p(100.0, 0.0) }],
        };
        let poly = flatten_ring(&ring, 0.01);
        assert_eq!(poly.first().unwrap().x, 0.0);
        let last = poly.last().unwrap();
        assert_eq!((last.x, last.y), (100.0, 0.0));
        assert!(poly.len() > 4, "curve must subdivide, got {}", poly.len());
    }

    #[test]
    fn rasterizers_agree_on_square() {
        let polys = vec![flatten_ring(&square_ring(0.0, 0.0, 10.0, 10.0), 1.0)];
        let to_px = |p: Point| (2.0 + p.x, 2.0 + (10.0 - p.y));
        let mut a = Canvas::new(16, 16);
        let mut b = Canvas::new(16, 16);
        rasterize(Rasterizer::Scanline, &polys, &mut a, 4, to_px);
        rasterize(Rasterizer::EvenOdd, &polys, &mut b, 4, to_px);
        let ga = a.finish(4);
        let gb = b.finish(4);
        let diff: u32 = ga.iter().zip(gb.iter()).map(|(x, y)| (*x as i32 - *y as i32).unsigned_abs()).sum();
        assert_eq!(diff, 0, "square fill must be identical across rasterizers");
        let ink_a: usize = ga.iter().filter(|&&v| v == 255).count();
        assert_eq!(ink_a, 100, "10x10 square at integer offset, got {ink_a}");
    }

    #[test]
    fn hole_stays_empty_in_both_rasterizers() {
        let outer = flatten_ring(&square_ring(0.0, 0.0, 20.0, 20.0), 1.0);
        let mut hole = flatten_ring(&square_ring(5.0, 5.0, 15.0, 15.0), 1.0);
        hole.reverse();
        let polys = vec![outer, hole];
        let to_px = |p: Point| (1.0 + p.x, 1.0 + (22.0 - p.y));
        for r in Rasterizer::ALL {
            let mut c = Canvas::new(24, 24);
            rasterize(r, &polys, &mut c, 2, to_px);
            let g = c.finish(2);
            let center = g[12 * 24 + 12];
            assert_eq!(center, 0, "hole center must be empty in {}", r.name());
            let edge = g[3 * 24 + 3];
            assert_eq!(edge, 255, "outer ink must be full in {}", r.name());
        }
    }

    #[test]
    fn value_record_layout() {
        assert_eq!(value_record_len(0x4), 2);
        assert_eq!(value_record_len(0x5), 4);
        assert_eq!(value_field_offset(0x5, 0x4), 2);
        assert_eq!(value_field_offset(0x4, 0x4), 0);
    }

    #[test]
    fn coverage_format1_and_2() {
        let fmt1 = [0, 1, 0, 2, 0, 7, 0, 9];
        assert_eq!(coverage_glyphs(&fmt1, 0).unwrap(), vec![7, 9]);
        let fmt2 = [0, 2, 0, 1, 0, 5, 0, 7, 0, 0];
        assert_eq!(coverage_glyphs(&fmt2, 0).unwrap(), vec![5, 6, 7]);
    }

    #[test]
    fn stats_basics() {
        let (m, sd) = mean_stdev(&[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]);
        assert_eq!(m, 5.0);
        assert_eq!(sd, 2.0);
        assert_eq!(median(&[3.0, 1.0, 2.0]), 2.0);
        assert_eq!(median(&[]), 0.0);
    }
}
