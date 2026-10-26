//! Native editable master companion, generated before atomic OTF publication.
use crate::{master_glyphs, otf_facts};
use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_core::native_font::NativeFontInput;
use std::collections::BTreeSet;
pub fn build(
    final_bytes: &[u8],
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
) -> Result<(String, String), String> {
    build_inner(final_bytes, prepared, mapping, None)
}

/// Optional checkpoint mode. A pending return never publishes a partial document.
pub fn build_checkpointed(
    final_bytes: &[u8],
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
    dir: &std::path::Path,
    context: &str,
    max_new: usize,
) -> Result<(String, String), String> {
    let checkpoint =
        crate::master_checkpoint::Checkpoint::open(dir, final_bytes, prepared, mapping, context)?;
    build_inner(final_bytes, prepared, mapping, Some((checkpoint, max_new)))
}
fn build_inner(
    final_bytes: &[u8],
    prepared: &NativeFontInput,
    mapping: &[(u32, u16)],
    checkpoint: Option<(crate::master_checkpoint::Checkpoint, usize)>,
) -> Result<(String, String), String> {
    let reader = CffReader::from_bytes(final_bytes, &sha256_hex(final_bytes))
        .map_err(|e| format!("master final readback: {e:?}"))?;
    let mut final_readback = prepared.clone();
    let (facts, _) = otf_facts::read_otf(final_bytes)?;
    if facts.glyphs.len() != prepared.glyphs.len() {
        return Err("master final glyph count mismatch".into());
    }
    for (gid, g) in final_readback.glyphs.iter_mut().enumerate() {
        g.outline = reader
            .read_glyph(gid as u16)
            .map_err(|e| format!("master glyph {gid}: {e:?}"))?
            .drawn(g.name.clone());
        g.advance = facts.glyphs[gid].advance;
    }
    final_readback.os2 = facts.os2;
    final_readback.head = facts.head;
    final_readback.hhea = facts.hhea;
    final_readback.names = facts.names;
    final_readback.left_side_bearings = facts.left_side_bearings;
    let final_kern = otf_facts::read_gpos_kern(final_bytes)?;
    let mut kern_pairs = Vec::new();
    for k in &final_kern.pairs {
        let name = |gid: u16| {
            final_readback
                .glyphs
                .get(gid as usize)
                .map(|g| g.name.clone())
                .ok_or_else(|| format!("master kern gid {gid} out of range"))
        };
        kern_pairs.push(kni_master::glyphs_file::KerningPair {
            master_id: "m01".into(),
            left: name(k.left)?,
            right: name(k.right)?,
            value: f64::from(k.x_advance),
        });
    }
    // Preserve native parts semantics. Failed decomposition keeps the final
    // readback rings and is reported, never silently omitted.
    let upm = f64::from(final_readback.head.units_per_em);
    let mut masters: Vec<kni_master::model::MasterGlyph> =
        Vec::with_capacity(final_readback.glyphs.len());
    let mut rows = String::new();
    let (mut nparts, mut ncarry) = (0usize, 0usize);
    let mut new_count = 0;
    for (gid, g) in final_readback.glyphs.iter().enumerate() {
        if let Some((cp, limit)) = &checkpoint {
            if let Some((cached, ledger)) = cp.read(gid, g, upm)? {
                if ledger
                    .lines()
                    .any(|l| l.starts_with(&format!("glyph {} PARTS ", g.name)))
                {
                    nparts += 1;
                } else {
                    ncarry += 1;
                }
                masters.push(cached);
                rows.push_str(&ledger);
                continue;
            }
            if new_count >= *limit {
                return Err(format!(
                    "MASTER_CHECKPOINT_PENDING completed={} total={} new={}",
                    masters.len(),
                    final_readback.glyphs.len(),
                    new_count
                ));
            }
        }
        let clock = std::time::Instant::now();
        let contours: Vec<kni_master::model::StrokeContour> = g
            .outline
            .rings
            .iter()
            .map(kni_master::parts_plug::reference_ring_to_contour)
            .collect();
        let tmp = kni_master::model::MasterGlyph {
            name: g.name.clone(),
            advance: f64::from(g.advance),
            upm,
            contours,
        };
        let row_start = rows.len();
        let carved = kni_master::decompose::decompose_with(
            &tmp,
            &kni_master::decompose::DecomposeParams::default(),
        )
        .map_err(|e| {
            ncarry += 1;
            rows.push_str(&format!(
                "glyph {} EXACTCARRY reason=DecomposeError detail={e:?}\n",
                g.name
            ));
            e
        })
        .ok()
        .and_then(|d| {
            let iou = kni_master::parts_plug::wire_iou(&tmp.contours, &d);
            let outside = kni_master::parts_plug::part_outside_px(&tmp.contours, &d);
            match kni_master::parts_plug::decide_gated(d.parts.len(), iou, &outside) {
                kni_master::parts_plug::PartsOut::Parts(_) => Some((d, iou)),
                kni_master::parts_plug::PartsOut::ExactCarry { reason } => {
                    ncarry += 1;
                    let probe = std::env::var("PARTS_PROBE_GRID").ok().map(|g| {
                        g.split(',')
                            .filter_map(|s| s.trim().parse::<u32>().ok())
                            .map(|grid| {
                                (
                                    grid,
                                    kni_master::parts_plug::part_outside_px_at(
                                        &tmp.contours,
                                        &d,
                                        grid,
                                    ),
                                )
                            })
                            .collect::<Vec<_>>()
                    });
                    rows.push_str(&format!(
                        "glyph {} EXACTCARRY reason={:?} iou {:.6} outside_px {:?} probe {:?}\n",
                        g.name, reason, iou, outside, probe
                    ));
                    None
                }
            }
        });
        let selected = match carved {
            Some((d, iou)) => {
                nparts += 1;
                let names: Vec<String> =
                    d.glyph.contours.iter().map(|c| c.stroke.clone()).collect();
                rows.push_str(&format!(
                    "glyph {} PARTS n={} iou {:.6} parts [{}]\n",
                    g.name,
                    names.len(),
                    iou,
                    names.join(", ")
                ));
                d.glyph
            }
            None => tmp,
        };
        if let Some((cp, _)) = &checkpoint {
            let (finalized, ledger) = master_glyphs::finalize_one(&selected, &g.outline, upm);
            rows.push_str(&ledger);
            let ledger = rows[row_start..].to_string();
            cp.write(gid, g, upm, &finalized, &ledger)?;
            eprintln!(
                "master_checkpoint_progress completed={} total={} current={} elapsed_ms={} cached=false",
                gid+1,
                final_readback.glyphs.len(),
                g.name,
                clock.elapsed().as_millis()
            );
            masters.push(finalized);
            new_count += 1;
        } else {
            masters.push(selected);
        }
    }
    let glyph_n = masters.len();
    let ordered: Vec<_> = masters.iter().collect();
    let (doc, report) = if checkpoint.is_some() {
        master_glyphs::build_from_finalized_report(&final_readback, mapping, &ordered, &kern_pairs)?
    } else {
        master_glyphs::build_from_report(
            &final_readback,
            mapping,
            &ordered,
            &BTreeSet::new(),
            &kern_pairs,
        )?
    };
    let mut blanks = String::new();
    for name in &report.skipped_empty_names {
        blanks.push_str(&format!(
            "master_glyphs_skipped_empty\t{}\n",
            master_glyphs::receipt_escape(name)
        ));
    }
    let mode_row = format!("master_glyphs_mode\tparts-decompose\tglyphs\t{glyph_n}\tsegmented\t{nparts}\texactcarry\t{ncarry}\n{blanks}{rows}");
    let gate_rows = master_glyphs::gate_written_doc(&doc, &final_readback, &kern_pairs)?;
    let mut receipt = String::new();
    if final_readback.os2.version < 2 {
        receipt.push_str("master_glyphs_metrics_unmeasured\tcap_height\tx_height\treason\tempty_population_OS2_v0\tvalues\t0\n");
    }
    receipt.push_str(&format!("master_glyphs\tbytes\t{}\tsha256\t{}\nmaster_glyphs_parity\tcompared\t{}\tskipped_empty\t{}\n{}master_glyphs_kerning\tsource\tfinal-gpos\tpairs\t{}\tresiduals\t{}\n{}",doc.len(),sha256_hex(doc.as_bytes()),report.compared,report.skipped_empty,mode_row,kern_pairs.len(),final_kern.residuals.len(),gate_rows));
    for r in final_kern.residuals {
        receipt.push_str(&format!(
            "master_glyphs_kern_residual\t{}\t{}\n",
            r.kind,
            master_glyphs::receipt_escape(&r.detail)
        ));
    }
    Ok((doc, receipt))
}
