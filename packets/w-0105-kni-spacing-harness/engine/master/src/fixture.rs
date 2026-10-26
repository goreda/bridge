//! Plain-text master glyph fixture format (one op per line), so fixtures can
//! be pinned by hash and loaded without a font parser.
//!
//! ```text
//! glyph <name> <advance> <upm>
//! stroke <name>
//! M x y | L x y | C x1 y1 x2 y2 x y | Z
//! ```

use crate::model::{MasterGlyph, Op, StrokeContour};

pub fn parse(text: &str) -> Result<MasterGlyph, String> {
    let mut g: Option<MasterGlyph> = None;
    for (n, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let t: Vec<&str> = line.split_whitespace().collect();
        let num = |i: usize| -> Result<f64, String> {
            t.get(i).ok_or(format!("line {}: missing field", n + 1))?.parse::<f64>().map_err(|e| format!("line {}: {}", n + 1, e))
        };
        match t[0] {
            "glyph" => {
                g = Some(MasterGlyph {
                    name: t.get(1).ok_or("glyph name")?.to_string(),
                    advance: num(2)?,
                    upm: num(3)?,
                    contours: vec![],
                })
            }
            "stroke" => {
                let g = g.as_mut().ok_or("stroke before glyph")?;
                g.contours.push(StrokeContour { stroke: t.get(1).ok_or("stroke name")?.to_string(), ops: vec![] });
            }
            k => {
                let g = g.as_mut().ok_or("op before glyph")?;
                let c = g.contours.last_mut().ok_or("op before stroke")?;
                c.ops.push(match k {
                    "M" => Op::Move((num(1)?, num(2)?)),
                    "L" => Op::Line((num(1)?, num(2)?)),
                    "C" => Op::Curve((num(1)?, num(2)?), (num(3)?, num(4)?), (num(5)?, num(6)?)),
                    "Z" => Op::Close,
                    o => return Err(format!("line {}: unknown op {}", n + 1, o)),
                });
            }
        }
    }
    g.ok_or_else(|| "empty fixture".to_string())
}

/// Multi-glyph master source: a sequence of `glyph` blocks in one file (the
/// font-level master source the kit pins in the manifest). Glyph order is
/// file order. Empty file is a typed error, never an empty font.
pub fn parse_many(text: &str) -> Result<Vec<MasterGlyph>, String> {
    let mut glyphs = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    let mut flush = |block: &mut Vec<&str>| -> Result<(), String> {
        if block.is_empty() {
            return Ok(());
        }
        let g = parse(&block.join("\n"))?;
        glyphs.push(g);
        block.clear();
        Ok(())
    };
    for line in text.lines() {
        let t = line.trim();
        if t.starts_with("glyph ") && !block.is_empty() {
            flush(&mut block)?;
        }
        if !t.is_empty() && !t.starts_with('#') {
            block.push(line);
        }
    }
    flush(&mut block)?;
    if glyphs.is_empty() {
        return Err("master source: no glyph blocks".into());
    }
    Ok(glyphs)
}
