//! Producer-to-validator integration stays on the runtime binary test target.
use crate::notdef_producer::*;
use kni_pipeline::notdef_types::{PixelContext, PixelNotdefKind};
use kni_core::{cff_reader::sha256_hex, jpeg_source::Limits};
    fn context(pin: String) -> PixelContext {
        PixelContext {
            style: "T/Regular".into(),
            frame: "frame1".into(),
            units_per_px: 2.4377,
            source_sha256: pin,
            ink_model: "decoded-gray-all-255-no-transform-v1".into(),
        }
    }
    fn req<'a>(c: &'a PixelContext, t: &'a [Tile<'a>], cap: &'a str, form: &'a str) -> Request<'a> {
        Request {
            context: c,
            cohort: "T/Regular",
            request_source: "synthetic-pixel-capture",
            capture_record: b"capture",
            capture_sha256: cap,
            space_evidence_sha256: None,
            pixel_form_sha256: form,
            tiles: t,
            limits: Limits {
                max_input_bytes: 1 << 20,
                max_pixels: 1024,
                max_working_bytes: 1 << 24,
            },
        }
    }
    fn blank() -> Vec<u8> {
        vec![
            137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 8, 0, 0, 0, 8,
            8, 0, 0, 0, 0, 225, 100, 225, 87, 0, 0, 0, 14, 73, 68, 65, 84, 120, 156, 99, 248, 15,
            5, 12, 148, 49, 0, 247, 192, 63, 193, 178, 52, 65, 187, 0, 0, 0, 0, 73, 69, 78, 68,
            174, 66, 96, 130,
        ]
    }
    #[test]
    fn producer_to_b2_final2_real_bounded_consumer_both_pixel_kinds() {
        use crate::bound_detector_validator::{
            self as v, BoundedDecoder, CoreBoundedDecoder, DetectionState, EvidenceBinding,
            ValidationLimits,
        };
        use kni_core::scale_context::ScaleContext;
        let loser = include_bytes!("../../core/tests/fixtures/jpeg_source/image_checker.jpg");
        for is_blank in [false, true] {
            let b = if is_blank {
                blank()
            } else {
                include_bytes!("../../core/tests/fixtures/jpeg_source/png_guard.png").to_vec()
            };
            let image_limits = Limits {
                max_input_bytes: 1 << 20,
                max_pixels: 1 << 20,
                max_working_bytes: 1 << 28,
            };
            let decoded = CoreBoundedDecoder.decode(&b, image_limits).unwrap();
            let form = v::pixel_form_sha256(decoded.width, decoded.height, &decoded.gray).unwrap();
            let c = context(sha256_hex(&b));
            let cap = sha256_hex(b"capture");
            let kind = if is_blank {
                PixelNotdefKind::BlankCell
            } else {
                PixelNotdefKind::RepeatedForm
            };
            let t = [
                Tile {
                    cp: 65,
                    path: "a.png",
                    bytes: &b,
                    role: Some(kind),
                },
                Tile {
                    cp: 66,
                    path: "b.png",
                    bytes: &b,
                    role: Some(kind),
                },
                Tile {
                    cp: 67,
                    path: "c.jpg",
                    bytes: loser,
                    role: None,
                },
            ];
            let r = req(&c, &t, &cap, &form);
            let p = produce(&r).unwrap();
            let root =
                std::env::temp_dir().join(format!("pixel-final2-{}-{is_blank}", std::process::id()));
            std::fs::create_dir(&root).unwrap();
            std::fs::write(root.join("a.png"), &b).unwrap();
            std::fs::write(root.join("b.png"), &b).unwrap();
            std::fs::write(root.join("c.jpg"), loser).unwrap();
            std::fs::write(root.join("evidence.tsv"), &p.evidence).unwrap();
            let root = root.canonicalize().unwrap();
            let population: v::PixelPopulation = std::collections::BTreeMap::from([
                (65, (root.join("a.png"), sha256_hex(&b))),
                (66, (root.join("b.png"), sha256_hex(&b))),
                (67, (root.join("c.jpg"), sha256_hex(loser))),
            ]);
            let binding = EvidenceBinding {
                file: root.join("evidence.tsv"),
                sha256: p.evidence_sha.clone(),
                style: c.style.clone(),
                capture: cap.clone(),
                scale: c.units_per_px,
                frame: c.frame.clone(),
            };
            let scale = ScaleContext::from_convention(
                "unit",
                "fixture",
                c.units_per_px,
                1000.0,
                "T/Regular",
                &c.frame,
            )
            .unwrap();
            let lim = ValidationLimits {
                image: image_limits,
                max_record_bytes: 1 << 20,
                max_record_rows: 65535,
                max_witnesses: 65535,
                max_aggregate_working_bytes: 1 << 28,
            };
            let state =
                v::load(&binding, &population, &scale, &root, lim, &CoreBoundedDecoder).unwrap();
            let receipt = state.receipt();
            match state {
                DetectionState::PixelEvidence {
                    kind: actual,
                    context: got,
                    pixel_form_sha256,
                    sources,
                    space_advance,
                    ..
                } => {
                    assert_eq!(actual, kind);
                    assert_eq!(got, c);
                    assert_eq!(pixel_form_sha256, form);
                    assert_eq!(sources, vec![65, 66]);
                    assert!(space_advance.is_none());
                }
                _ => panic!("not pixel evidence"),
            }
            assert!(receipt.contains("placeholder_cp_count	2"));
            std::fs::remove_dir_all(root).unwrap();
        }
    }
