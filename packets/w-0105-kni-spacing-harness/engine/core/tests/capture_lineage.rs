use kni_core::capture::{capture_png,capture_png_with_lineage};
#[test]fn indexed_capture_is_geometry_identical_and_ring_scoped(){for png in [include_bytes!("fixtures/r_scan.png").as_slice(),include_bytes!("fixtures/s_scan.png").as_slice()] {
 let baseline=capture_png(png,0.5).unwrap();let(observed,lineage)=capture_png_with_lineage(png,0.5).unwrap();assert_eq!(baseline.rings.len(),observed.rings.len());assert_eq!(observed.rings.len(),lineage.len());
 for (i,((a,b),l)) in baseline.rings.iter().zip(&observed.rings).zip(&lineage).enumerate(){assert_eq!(a.points,b.points);assert_eq!(a.raw,b.raw);assert_eq!(a.corners,b.corners);assert_eq!(i,l.captured_ring_index);assert_eq!(l.retained_raw_indices.len(),b.points.len());assert!(l.retained_raw_indices.iter().all(|&x|x<l.raw_point_count));for &(point,raw) in &l.corner_events{assert!(b.corners.contains(&point));assert_eq!(l.retained_raw_indices[point],raw);}}
}}
