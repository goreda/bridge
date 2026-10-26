//! Eacute public-API ancestry regression: fit -> E0 cleanup -> D2 -> D4 -> N1 -> final.
//! Fixture inputs and producer geometry/policies are unchanged. Typed report hashes,
//! counts and source objectives account for every post-fit node transition.
//! The fallback ledger is not a final-line count; capture drops are not N1 removals.
//! Explicit protection is tested separately and is not inferred from route success.
//! Fidelity assertions cover the producer's strict area/extrema guards, not a
//! certified Hausdorff bound or a visual-quality claim.
use kni_core::capture_dispatch::capture_source;
use kni_core::cubic_fit::FitPolicy;
use kni_core::generated_draw_frame::fit_captured_source_frame;
use kni_core::generated_draw_frame::{fit_from_source_frame_hooked, FrameFitError};
use kni_core::jpeg_source::Limits;
use kni_core::lever_api::{
    area_error, count_nodes, hash_rings, missing_extrema, LeverReport, NodeBudget, SourceMask,
    LEVER_API_VERSION,
};
use kni_core::reference_slice::Span;
use kni_core::reference_slice::{Point, ReferenceRing};
use kni_core::{
    capture_fit, emitted_geometry_refine as d2, node_objective as n1, tail_refine as d4,
};

const PNG: &[u8] = include_bytes!("fixtures/00C9_scan.png");
const PNG_SHA256: &str = "1cb29b0dc7177f112cdfed03e6c5196b5b881b8aa94390442777c16376bd685b";
const SCALE: f64 = 1.7100183991006373;
const EPS: f64 = 0.25;
fn policy() -> FitPolicy {
    FitPolicy {
        squared_error: 0.25,
        max_refits: 8,
    }
}
fn limits() -> Limits {
    Limits {
        max_input_bytes: 1 << 26,
        max_pixels: 1 << 26,
        max_working_bytes: 1 << 28,
    }
}

fn png_limits() -> kni_core::capture::DecodeLimits {
    kni_core::capture::DecodeLimits {
        max_input_bytes: 1 << 26,
        max_pixels: 1 << 26,
        max_working_bytes: 1 << 28,
    }
}

fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut m = data.to_vec();
    m.push(0x80);
    while m.len() % 64 != 56 {
        m.push(0);
    }
    m.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for c in m.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([c[4 * i], c[4 * i + 1], c[4 * i + 2], c[4 * i + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7]
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let mj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(mj);
            v = [
                t1.wrapping_add(t2),
                v[0],
                v[1],
                v[2],
                v[3].wrapping_add(t1),
                v[4],
                v[5],
                v[6],
            ];
        }
        for i in 0..8 {
            h[i] = h[i].wrapping_add(v[i]);
        }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}

#[test]
fn fixture_is_the_pinned_eacute_scan() {
    assert_eq!(sha256_hex(PNG), PNG_SHA256);
    assert_eq!(
        sha256_hex(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "sha256 helper self-check"
    );
}

fn end(span: &Span) -> Point {
    match span {
        Span::Line { end } | Span::Cubic { end, .. } => *end,
    }
}

// Each boundary is checked against actual rings, not merely another receipt.
fn assert_boundary(
    rep: &LeverReport,
    before: &[ReferenceRing],
    after: &[ReferenceRing],
    mask: &SourceMask,
) {
    assert_eq!(rep.api_version, LEVER_API_VERSION);
    assert_eq!(rep.input_hash, hash_rings(before));
    assert_eq!(rep.output_hash, hash_rings(after));
    assert_eq!(rep.nodes_before, count_nodes(before));
    assert_eq!(rep.nodes_after, count_nodes(after));
    assert!(rep.nodes_after <= rep.nodes_before);
    assert_eq!(rep.area_before, area_error(before, mask));
    assert_eq!(rep.area_after, area_error(after, mask));
    assert!(rep.area_before.is_finite() && rep.area_after.is_finite());
    assert!(
        rep.area_after <= rep.area_before,
        "strict source objective: {rep:?}"
    );
    assert_eq!(rep.c2_missing, missing_extrema(after));
    assert_eq!(rep.c2_missing, 0);
    assert!(missing_extrema(after) <= missing_extrema(before));
}

#[test]
fn eacute_ancestry_is_honest_across_fit_cleanup_and_typed_levers() {
    let src = capture_source(PNG, EPS, &png_limits(), limits()).unwrap();
    let r = fit_captured_source_frame(&src, SCALE, &policy()).unwrap();
    let d = &r.drawing;
    let w = u32::from_be_bytes(PNG[16..20].try_into().unwrap()) as usize;
    let h = u32::from_be_bytes(PNG[20..24].try_into().unwrap()) as usize;
    assert_eq!((r.receipt.width, r.receipt.height), (w, h));
    assert_eq!(
        format!("{:?}", r.receipt.source_kind),
        "PngConvertedGrayWhiteAlpha"
    );
    assert!(r.receipt.jpeg_identity.is_none() && r.receipt.decoder_limits.is_none());
    assert_eq!(d.dropped, 0, "capture-fit drops, not legal lever removals");
    assert!(d.refused.is_empty(), "diagnostic refusals: {:?}", d.refused);
    assert_eq!(d.fallback, d.fallback_line_spans > 0);

    // Fit emission and E0 are different units. Replay the public fit and cleanup
    // boundary to account for cleanup independently, without assuming equality.
    let (mut float, fit_count, fallback, dropped, events) =
        capture_fit::fit_captured_with_fallback_events(&src.contour.rings, SCALE, &policy());
    assert_eq!(fit_count, count_nodes(&float));
    assert_eq!(
        (d.source_fit_spans, d.fallback, d.dropped),
        (fit_count, fallback, dropped)
    );
    assert_eq!(
        d.fallback_line_spans,
        events.len(),
        "fallback ledger has its own unit"
    );
    let dy = src.contour.origin_y * SCALE;
    for ring in &mut float {
        ring.start.y += dy;
        for span in &mut ring.spans {
            match span {
                Span::Line { end } => end.y += dy,
                Span::Cubic {
                    control_one,
                    control_two,
                    end,
                } => {
                    control_one.y += dy;
                    control_two.y += dy;
                    end.y += dy;
                }
            }
        }
    }
    let baseline: Vec<_> = float
        .iter()
        .map(|ring| capture_fit::round_and_clean_ring(ring, 1.0))
        .collect();
    assert_eq!(hash_rings(&baseline), hash_rings(&d.baseline));
    let cleanup_removed = fit_count.checked_sub(count_nodes(&baseline)).unwrap();
    let mask = SourceMask {
        w,
        h,
        ink: src.gray.clone(),
        scale: SCALE,
        origin: (-src.contour.origin_x * SCALE, 0.0),
    };
    let budget = NodeBudget {
        max_nodes: count_nodes(&baseline),
        max_nodes_per_ring: baseline.iter().map(|r| r.spans.len()).collect(),
    };
    let cfg = d2::RefineConfig {
        max_snap: d2::DERIVED_MAX_SNAP,
        run_int_refine: true,
        max_area_evals: d2::derived_eval_budget(budget.max_nodes),
    };
    // Unguided production route has no explicit E0/E1 protection ledger.
    let (after_d2, _) = d2::refine_emitted_guided(&baseline, &mask, &budget, &cfg, &[]).unwrap();
    let (before_n1, _) =
        d4::refine_tails(&after_d2, &mask, &budget, &d4::TailConfig::default()).unwrap();
    let (after_n1, _) = n1::try_apply_protected(
        &before_n1,
        &mask,
        &budget,
        n1::Policy::STRICT,
        &n1::Protected::new(),
    )
    .unwrap();
    assert_eq!(hash_rings(&after_n1), hash_rings(&d.rings));
    let stages = [
        (
            "emitted_geometry_refine",
            "D2.emitted_geometry_refine",
            "post-fit/default",
            &baseline,
            &after_d2,
        ),
        (
            "tail_refine",
            "D4.tail_refine",
            "post-fit/default",
            &after_d2,
            &before_n1,
        ),
        (
            "node_objective",
            "N1.node_objective",
            "post-fit/opt-in",
            &before_n1,
            &after_n1,
        ),
    ];
    assert_eq!(d.reports.len(), stages.len(), "no missing/duplicate stage");
    let mut cursor = (hash_rings(&baseline), count_nodes(&baseline));
    let mut lever_removed = 0;
    for (rep, (lever, id, tag, before, after)) in d.reports.iter().zip(stages) {
        assert_eq!((rep.lever, rep.lever_id, rep.stage_tag), (lever, id, tag));
        assert_eq!((rep.input_hash, rep.nodes_before), cursor);
        assert_boundary(rep, before, after, &mask);
        lever_removed += rep.nodes_before.checked_sub(rep.nodes_after).unwrap();
        cursor = (rep.output_hash, rep.nodes_after);
    }
    assert_eq!(cursor, (hash_rings(&d.rings), count_nodes(&d.rings)));
    assert_eq!(
        fit_count,
        cleanup_removed + lever_removed + count_nodes(&d.rings)
    );
    assert_eq!(d.baseline_area, area_error(&baseline, &mask));
    assert_eq!(d.final_area, area_error(&d.rings, &mask));
    assert!(d.final_area <= d.baseline_area);
    assert_eq!(d.baseline_missing_extrema, missing_extrema(&baseline));
    assert_eq!(d.final_missing_extrema, missing_extrema(&d.rings));
    assert!(d.final_missing_extrema <= d.baseline_missing_extrema);

    // Historical fit-stage characterization is retained, NOT imposed on the
    // post-N1 output. No final node-count literal is used as the oracle.
    assert_eq!(d.baseline.len(), 2);
    // Re-pinned 26 -> 27 with the raw-chain chord-deviation line accept
    // (t_line retirement of T_LINE_SLACK): the chord that the slack used to
    // accept against the captured RDP subset now measures the raw chain and
    // splits into two spans. Line-termination receipt unchanged (all Lines).
    // Re-pinned 27 -> 23 with the PN-3 fallback rescue (capture_fit): the
    // damped-Newton rescue + corner resplit + chord-line terminal accept
    // resolve the unresolved bottom-outs this fixture carried, merging
    // split chains into single accepted spans under the caller's dense
    // bound. Line-termination receipt still unchanged (all Lines).
    assert_eq!(fit_count, 23);
    assert!(baseline
        .iter()
        .flat_map(|r| &r.spans)
        .all(|s| matches!(s, Span::Line { .. })));
    assert!(d
        .rings
        .iter()
        .flat_map(|r| &r.spans)
        .all(|s| matches!(s, Span::Line { .. })));
    assert_eq!(d.rings.len(), baseline.len());

    // Stable node identity = end of input span i, not the following span.
    // Determine missing identities from the actual N1 input/output. D2 may move
    // coordinates, so do not compare final endpoints directly to E0 coordinates.
    let mut removed = Vec::new();
    for (ri, (before, after)) in before_n1.iter().zip(&d.rings).enumerate() {
        assert_eq!(before.start, after.start);
        // Coordinate-based identity recovery is valid only with unique input
        // endpoints. Fail rather than silently alias two original identities.
        for (i, span) in before.spans.iter().enumerate() {
            assert!(
                !before.spans[..i].iter().any(|s| end(s) == end(span)),
                "ambiguous input node identity"
            );
        }
        let mut surviving = Vec::new();
        for (ni, span) in before.spans.iter().enumerate() {
            if after.spans.iter().any(|s| end(s) == end(span)) {
                surviving.push(end(span));
            } else {
                removed.push((ri, ni));
            }
        }
        assert_eq!(
            surviving,
            after.spans.iter().map(end).collect::<Vec<_>>(),
            "surviving node order"
        );
        assert!(after.spans.len() >= 3);
        assert_eq!(end(after.spans.last().unwrap()), after.start);
    }
    // Re-pinned (1, 6) -> (1, 7) with the raw-chain chord-deviation line
    // accept, then (1, 7) -> [] with the PN-3 fallback rescue: the rescued
    // baseline resolves the unresolved split chain that inserted the extra
    // node, so the node objective now removes NO original node. The
    // removal-identity checks that pinned (1, 7) are retired with the
    // removal itself; the surviving-node-order asserts above still account
    // for every transition, and lever_removed accounts for the count.
    assert_eq!(
        removed,
        Vec::<(usize, usize)>::new(),
        "accent original node identity, not a final-count pin"
    );
    assert_eq!(removed.len(), lever_removed);
    assert!(
        before_n1
            .iter()
            .flat_map(|r| &r.spans)
            .all(|s| matches!(s, Span::Line { .. })),
        "N1 parents have no cubic controls to discard"
    );
    assert_eq!(
        d.reports.last().unwrap().max_node_displacement,
        0.0,
        "N1 removes, not moves, surviving nodes"
    );

    // Independent protection contract: explicitly protect the removable identity.
    // This is NOT a claim that the unguided production route supplied an E1 set.
    let protected: n1::Protected = removed.iter().copied().collect();
    let (kept, kept_report) =
        n1::try_apply_protected(&before_n1, &mask, &budget, n1::Policy::STRICT, &protected)
            .unwrap();
    assert_boundary(&kept_report, &before_n1, &kept, &mask);
    assert_eq!(
        hash_rings(&kept),
        hash_rings(&before_n1),
        "explicit protection prevents this fixture's removal"
    );

    let r2 = fit_captured_source_frame(&src, SCALE, &policy()).unwrap();
    assert_eq!(hash_rings(&d.rings), hash_rings(&r2.drawing.rings));
    assert_eq!(d.source_fit_spans, r2.drawing.source_fit_spans);
    assert_eq!(d.fallback_line_spans, r2.drawing.fallback_line_spans);
    assert_eq!(
        format!("{:?}", d.reports),
        format!("{:?}", r2.drawing.reports),
        "deterministic typed receipts"
    );
    eprintln!(
        "eacute: fit={} cleanup_removed={} lever_removed={} final={} chain={:?}",
        fit_count,
        cleanup_removed,
        lever_removed,
        count_nodes(&d.rings),
        d.reports
    );
}

#[test]
fn invalid_explicit_protection_is_a_typed_route_failure() {
    let src = capture_source(PNG, EPS, &png_limits(), limits()).unwrap();
    let invalid = |rings: &[ReferenceRing], _: &SourceMask| -> n1::Protected {
        [(rings.len(), 0)].into_iter().collect()
    };
    let result =
        fit_from_source_frame_hooked(&src.contour, &src.gray, SCALE, &policy(), Some(&invalid));
    assert!(
        matches!(
            result,
            Err(FrameFitError::ProtectedConstraint(
                kni_core::lever_api::LeverError::Violation(_)
            ))
        ),
        "invalid E1 identity must hard-fail, got {result:?}"
    );
}
