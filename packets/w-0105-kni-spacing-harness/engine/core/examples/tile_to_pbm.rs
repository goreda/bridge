//! Convert a source PNG tile to a binary PBM (P4) at an explicit threshold,
//! for feeding external raster-only tracers the same pixels the harness
//! binarizes (gray < threshold == ink). No harness-owned constants: the
//! threshold is a CLI input, the same value the IoU evaluator is pinned with.
//!
//! Usage: tile_to_pbm IN.png OUT.pbm THRESHOLD
use kni_core::capture::decode_png_gray;

/// Read at most `cap` bytes: one open, take(cap + 1), typed refusal over
/// cap. No metadata-length check, never an unbounded read.
fn read_capped(path: &str, cap: u64) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let f = std::fs::File::open(path).map_err(|e| format!("open: {e}"))?;
    let mut buf = Vec::new();
    f.take(cap + 1).read_to_end(&mut buf).map_err(|e| format!("read: {e}"))?;
    if buf.len() as u64 > cap { return Err(format!("input over {cap} bytes")); }
    Ok(buf)
}

const MAX_TILE_BYTES: u64 = 32 * 1024 * 1024;

fn main() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 4 { return Err("usage: tile_to_pbm IN.png OUT.pbm THRESHOLD".into()); }
    let png = read_capped(&a[1], MAX_TILE_BYTES)?;
    let threshold: u8 = a[3].parse().map_err(|_| "bad threshold")?;
    let (w, h, gray) = decode_png_gray(&png)?;
    let stride = w.div_ceil(8);
    let mut out = format!("P4\n{w} {h}\n").into_bytes();
    for y in 0..h {
        for xb in 0..stride {
            let mut byte = 0u8;
            for bit in 0..8 {
                let x = xb * 8 + bit;
                if x < w {
                    // PBM: 1 = black (ink), 0 = white
                    if gray[y * w + x] < threshold { byte |= 0x80 >> bit; }
                }
            }
            out.push(byte);
        }
    }
    std::fs::write(&a[2], out).map_err(|e| format!("write: {e}"))?;
    Ok(())
}
